extends RefCounted
## Local authorization from journal-bound requests and persisted facts.
## C3 independently validates mechanics; provider assessments are never authority.
const REG=preload("res://gameplay/tool_registry.gd")
const DTO=preload("res://world/world_dto.gd")
const SQL=preload("res://systems/sqlite.gd")
const RAW=preload("res://turns/raw_mechanics.gd")
const PACK=preload("res://turns/agent_packets.gd")
const BASE=preload("res://campaigns/campaign_store.gd")
const CHECKS=["ability_check","skill_check","object_check","saving_throw"]
const ROUTES=["move","travel"]
const ROUTINE=["conversation","observe"]
const DIRECT_SAFE=["equip","quick_equip","swap","unequip","reconcile_legacy_slots"]
const DESCRIPTIVE=["define_official","define_custom","actor_generate","loot_discover","story_update"]
var controller: Node

func source_text(source: Dictionary) -> String:
	var data=source.get("data",{})
	return str(data.get("text",""))

func intent_text(req: Dictionary,job: Dictionary,state: Dictionary) -> String:
	if req["kind"] in DESCRIPTIVE:
		return source_text(controller.registry.session.source(state,req["args"].get("source_event_id")))
	return str(job["intent"]["args"].get("text",JSON.stringify(job["intent"]["args"])))

func rule_shape(req: Dictionary) -> Dictionary:
	if req["kind"] in CHECKS:
		return {"seconds":"nonnegative integer or null if unknown","establish_clock":"false","optional_features_resolved":"true only if actual supported features accounted for","verified_circumstances":req["args"]["circumstances"],"effect_dc":"null except verified existing structured effect"}
	if req["kind"] in ROUTES:
		return {"difficult":"boolean based on actual route/terrain","clearance":"verified_unobstructed_supplied_foot_travel only if established","establish_clock":"false"}
	if req["kind"] in ROUTINE+["wait"]:
		return {"safe_nonmechanical":"true only if no unresolved challenge","seconds":req["args"].get("seconds",0),"establish_clock":"false, or true for explicit known-duration wait starting a local tracked epoch if unknown"}
	return {}

func bound_request(req: Dictionary,job: Dictionary,state: Dictionary) -> bool:
	if req.get("campaign_id")!=state["campaign_id"] or req.get("actor_id")!=state["actor_id"] or req.get("expected_revision")!=state["revision"] or not REG.TOOLS.has(req.get("kind")) or not controller.registry.arguments_valid(req["args"],REG.TOOLS[req["kind"]][0]):
		return false
	if controller.registry.session.same_request(req,job.get("tool")) or controller.registry.session.same_request(req,job.get("story_request")) or controller.registry.session.same_request(req,job.get("consequence_request")):
		return true
	return false

func direct_safe(req: Dictionary,job: Dictionary,state: Dictionary) -> bool:
	if not bound_request(req,job,state) or not controller.registry.noncombat.quiet_context(state):
		return false
	var intent=job["intent"]
	var exact=intent["kind"]==req["kind"] and controller.registry.session.typed_equal(intent["args"],req["args"])
	if req["kind"] in ROUTINE and intent["kind"]=="chat" and req["args"]["text"]==intent["args"]["text"] and RAW.actor_ready(state["actor"]):
		return true
	return exact and req["kind"] in DIRECT_SAFE and controller.registry.noncombat.safe_actor(state)

# Only local state and the exact journal-bound request can authorize mechanics.
func local_decision(req: Dictionary,job: Dictionary,state: Dictionary) -> Dictionary:
	if not bound_request(req,job,state):
		return {"ok":false,"error":"Request identity or campaign revision changed."}
	var kind=req["kind"]
	var args=req["args"]
	var nc=controller.registry.noncombat
	if not nc.quiet_context(state):
		return {"ok":false,"error":"Active encounter or unavailable encounter state; noncombat action blocked."}
	var ruling: Dictionary={}
	if kind in DESCRIPTIVE:
		if descriptive_assessment(req,job,state).is_empty():
			return {"ok":false,"error":"Committed descriptive source or staged proposal unavailable."}
	elif kind=="inspect_inscription":
		var text = str(job["intent"]["args"].get("text","")).strip_edges().to_lower()
		if job["intent"]["kind"]!="chat" or not (text.begins_with("read the inscription on ") or text.begins_with("inspect the inscription on ")) or not nc.safe_actor(state):
			return {"ok":false,"error":"Ask explicitly to read the inscription on an owned custom object."}
		var target = text.trim_prefix("read the inscription on ").trim_prefix("inspect the inscription on ").trim_suffix(".").trim_suffix("?").strip_edges()
		var owned = nc.read_owned(state,state["actor_id"])
		if not owned.get("ok",false):
			return owned
		var matches: Array = []
		for item in owned["items"].values():
			if target==item["id"] or target==str(item["name"]).strip_edges().to_lower():
				matches.append(item["id"])
		if matches!=[args["instance_id"]]:
			return {"ok":false,"error":"Use an exact, unique owned item name or instance ID."}
	elif direct_safe(req,job,state):
		if kind in ROUTINE:
			ruling={"safe_nonmechanical":true,"seconds":0,"establish_clock":false}
	elif kind in ["equip","quick_equip","swap","unequip","item_use","item_drop","resource_use","spell_prepare","spell_unprepare","spell_cast"]:
		if not nc.safe_actor(state):
			return {"ok":false,"error":"Actor outside supported noncombat mechanics."}
		# Self-contained handlers independently validate ownership, equipment,
		# target, quantities, resources and the committed preparation window.
		if args.has("target_id") and args["target_id"]!=state["actor_id"]:
			return {"ok":false,"error":"Only explicit self-target use is supported."}
		if args.has("instance_id"):
			var owned=nc.read_owned(state,state["actor_id"])
			if not owned.get("ok",false):
				return {"ok":false,"code":owned.get("code","review_required"),"error":"Authoritative ownership or equipment state unavailable."}
			if not owned["items"].has(args["instance_id"]):
				return {"ok":false,"error":"Selected item is not owned."}
			if args.has("quantity") and args["quantity"]>owned["items"][args["instance_id"]]["quantity"]:
				return {"ok":false,"error":"Requested quantity exceeds owned quantity."}
	elif kind in CHECKS:
		var actor = state["actor"]
		# Narrow first pass. Complex feature, effect and contest cases keep
		# their existing denial until their local mechanics are supported.
		if kind!="ability_check" or not job.get("dm_basic_check",false) or job["intent"]["kind"]!="chat" or args["text"]!=job["intent"]["args"]["text"] or not args["circumstances"].is_empty() or not nc.safe_actor(state) or actor.get("race_id")!="human" or not actor.get("class_id") in ["fighter","cleric"] or not str(actor.get("subclass_id","")).is_empty() or not actor.get("feat_ids",[]).is_empty() or actor.get("inspiration",false):
			return {"ok":false,"error":"This check needs local challenge or feature handling outside the supported basic check."}
		var source = controller.registry.session.source(state,args["source_event_id"])
		if not controller.registry.session.public_source(source) or not controller.registry.source_valid(state,int(args["source_event_id"])):
			return {"ok":false,"error":"The check's local scene evidence is unavailable."}
		if args["skill"]!=null:
			var skill = controller.enquiry("rule_record",{"category":"skills","id":args["skill"]},1)
			if not skill.get("ok",false) or skill["data"].get("ability_score",{}).get("index","").to_lower()!=args["ability"]:
				return {"ok":false,"error":"Skill or its pinned ability does not match."}
		ruling={"seconds":0,"establish_clock":false,"optional_features_resolved":true,"verified_circumstances":[],"effect_dc":null}
	elif kind in ROUTES:
		return {"ok":false,"error":"Route terrain, hazards and supplies are not established by a local clearance record."}
	elif kind in ["rest","attune","unattune"]:
		return {"ok":false,"error":"Uninterrupted rest or attunement context is not established."}
	elif kind in ["item_transfer","currency_transfer","party_membership"]:
		return {"ok":false,"error":"Verified participant consent is not established; no transfer or membership change."}
	elif kind in ["loot_pickup","loot_take_all"]:
		if not nc.safe_actor(state):
			return {"ok":false,"error":"Actor outside supported pickup mechanics."}
		# A locally created drop belonging to this actor is explicit access
		# evidence, unlike a narrated discovery or another actor's possessions.
		var rows=controller.registry.session.read(state,[SQL.stmt("SELECT id FROM loot_containers WHERE id=? AND location_id=? AND source_kind='drop' AND source_actor_id=? AND source_event_id=? AND visibility='player' AND status='available'",[args["container_id"],state["location_id"],state["actor_id"],args["source_event_id"]])])
		if not rows.get("ok",false) or rows["sets"][0].size()!=1:
			return {"ok":false,"error":"No locally established right of access to this container."}
		var event=controller.registry.session.source(state,args["source_event_id"])
		if event.get("kind")!="gameplay_change" or not controller.registry.session.public_source(event):
			return {"ok":false,"error":"Committed local drop event unavailable."}
	elif kind=="object_interact":
		return {"ok":false,"error":"Unlocked and unobstructed object state is not established."}
	elif kind=="wait":
		return {"ok":false,"error":"Safe uninterrupted duration is not established locally."}
	else:
		return {"ok":false,"error":"Action has no supported local contextual authorization."}
	for section in REG.TOOLS[kind][2]:
		var rule=controller.enquiry("rule_record",{"category":"rule-sections","id":section},1)
		if not rule.get("ok",false):
			return {"ok":false,"error":"Pinned applicable rule unavailable: "+section}
	return {"ok":true,"ruling":ruling}

# Derive descriptive clearance only from the exact staged proposal and committed public narration.
# The registry still validates the typed operation and performs its own transaction.
func descriptive_assessment(req: Dictionary,job: Dictionary,state: Dictionary) -> Dictionary:
	if not req["kind"] in DESCRIPTIVE or not controller.registry.session.same_request(req,job.get("story_request")) or not bound_request(req,job,state):
		return {}
	if not controller.committed_job_source(job,state) or (req["kind"]!="story_update" and not controller.discovery_request_valid(req,job,state)):
		return {}
	var event_id=job.get("narration_event_id")
	if req["args"].get("source_event_id")!=event_id or not DTO.whole(event_id,1):
		return {}
	var source=controller.registry.session.source(state,event_id)
	if source.get("kind")!="narration" or not controller.registry.session.public_source(source):
		return {}
	var entries=job.get("story",[]) if req["kind"]=="story_update" else job.get("discoveries",[])
	var index=int(job.get("story_index",0)) if req["kind"]=="story_update" else int(job.get("discovery_index",0))
	if index<0 or index>=entries.size():
		return {}
	var entry=entries[index]
	if req["kind"]!="story_update" and entry.get("kind")!=req["kind"]:
		return {}
	var evidence=entry.get("evidence","")
	if not DTO.bounded_text(evidence,2000) or not source_text(source).contains(evidence):
		return {}
	return {"disposition":"supported","intent_evidence":evidence,"context":[{"event_id":event_id,"evidence":evidence}],"ruling":{},"reason":"Committed descriptive proposal; no player resource authorization."}

func review(req: Dictionary,scope: Dictionary,intent: Dictionary) -> Dictionary:
	var out={"request_id":req["request_id"],"campaign_id":req["campaign_id"],"actor_id":req["actor_id"],"expected_revision":req["expected_revision"],"accepted":false,"ruling":{},"reason":"Independent contextual evidence unavailable."}
	var state=controller.registry.session.token(req["campaign_id"])
	var job=controller.active()
	if not state.get("ok",false) or scope.get("location_id")!=state["location_id"] or scope.get("revision")!=state["revision"] or not controller.registry.session.typed_equal(intent,job.get("intent")) or not bound_request(req,job,state):
		return out
	var checked=local_decision(req,job,state)
	if checked.get("ok",false):
		out["accepted"]=true
		out["ruling"]=checked["ruling"]
		out["reason"]="Deterministic local authorization; registered handler validates mechanics."
	else:
		out["reason"]=checked.get("error","Local authorization unavailable.")
	return out

# C4 compatibility callback checks the same durable independent reports.
func review_prose(candidate: Dictionary,_claims: Array,outcome: Dictionary,scene: Dictionary) -> bool:
	var job=controller.active()
	return candidate==job.get("candidate") and controller.reviewed_candidate(job,outcome,scene)
