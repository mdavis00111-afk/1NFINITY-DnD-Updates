extends RefCounted
## C5b local policy: semantic judgments are bounded evidence. Only this
## local code creates C3 clearance; C3 independently validates mechanics.
const REG=preload("res://gameplay/tool_registry.gd")
const DTO=preload("res://world/world_dto.gd")
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
	if req==job.get("tool") or req==job.get("story_request") or req==job.get("consequence_request"):
		return true
	return false

func direct_safe(req: Dictionary,job: Dictionary,state: Dictionary) -> bool:
	if not bound_request(req,job,state) or not controller.registry.noncombat.quiet_context(state):
		return false
	var intent=job["intent"]
	var exact=intent["kind"]==req["kind"] and intent["args"]==req["args"]
	if req["kind"] in ROUTINE and intent["kind"]=="chat" and req["args"]["text"]==intent["args"]["text"] and RAW.actor_ready(state["actor"]):
		return true
	return exact and req["kind"] in DIRECT_SAFE and controller.registry.noncombat.safe_actor(state)

func validate_assessment(req: Dictionary,report: Variant,job: Dictionary,state: Dictionary) -> Dictionary:
	if not bound_request(req,job,state) or not DTO.exact_keys(report,["disposition","intent_evidence","context","ruling","reason"]) or report["disposition"]!="supported" or not DTO.bounded_text(report["reason"],1000) or not report["ruling"] is Dictionary or not report["context"] is Array or report["context"].size()>12:
		return {"ok":false,"error":"Contextual action not established."}
	var kind=req["kind"]
	if kind in DESCRIPTIVE and kind!="story_update" and not controller.discovery_request_valid(req,job,state):
		return {"ok":false,"error":"Discovery arguments differ from staged proposal."}
	var args=req["args"]
	var original=intent_text(req,job,state)
	if not DTO.bounded_text(report["intent_evidence"],2000) or not original.contains(report["intent_evidence"]):
		return {"ok":false,"error":"Contextual decision lacks exact intent/source evidence."}
	if not controller.registry.noncombat.quiet_context(state):
		return {"ok":false,"error":"Active encounter outside supported mechanics."}
	var evidence_ids: Array=[]
	for entry in report["context"]:
		if not DTO.exact_keys(entry,["event_id","evidence"]) or not DTO.whole(entry["event_id"],1) or not DTO.bounded_text(entry["evidence"],2000):
			return {"ok":false,"error":"Malformed contextual evidence."}
		var event=controller.registry.session.source(state,entry["event_id"])
		if not controller.registry.session.public_source(event) or not source_text(event).contains(entry["evidence"]):
			return {"ok":false,"error":"Context evidence is not a committed public event."}
		if controller.registry.source_valid(state,int(entry["event_id"])):
			evidence_ids.append(entry["event_id"])
	# Consequential context is assessed against actual public local events;
	# a semantic inference from silence is not evidence of access/consent.
	if kind in CHECKS+ROUTES+["rest","attune","unattune","item_transfer","currency_transfer","loot_pickup","loot_take_all","object_interact","party_membership","loot_discover","actor_generate","story_update","define_custom","define_official"] and evidence_ids.is_empty():
		return {"ok":false,"error":"Local context evidence is required."}
	if args.has("source_event_id") and not args["source_event_id"] in evidence_ids:
		return {"ok":false,"error":"Proposed source does not match the contextual evidence."}
	var ruling: Dictionary={}
	var proposed=report["ruling"]
	if kind in CHECKS:
		if not RAW.actor_ready(state["actor"]) or not state["actor"].get("review_required",[]).is_empty() or not DTO.exact_keys(proposed,["seconds","establish_clock","optional_features_resolved","verified_circumstances","effect_dc"]) or proposed["establish_clock"]!=false or proposed["optional_features_resolved"]!=true or proposed["verified_circumstances"]!=args["circumstances"] or (proposed["seconds"]!=null and not DTO.whole(proposed["seconds"],0,RAW.MAX_WALK_SECONDS)):
			return {"ok":false,"error":"Check features, timing or circumstances not established."}
		for circumstance in args["circumstances"]:
			if not circumstance["source_event_id"] in evidence_ids:
				return {"ok":false,"error":"Advantage/disadvantage needs actual local evidence."}
		var dc: Variant=null
		if kind=="saving_throw":
			# Only an already persisted structured triggering effect can supply DC.
			var trigger=controller.registry.session.source(state,args["source_event_id"]).get("data",{})
			var effect=trigger.get("verified_saving_throw",{})
			if not effect is Dictionary or effect.get("actor_id")!=state["actor_id"] or effect.get("ability")!=args["ability"] or not DTO.whole(effect.get("dc"),0,DTO.MAX_INT) or proposed["effect_dc"]!=effect["dc"]:
				return {"ok":false,"error":"No verified triggering saving-throw DC."}
			dc=effect["dc"]
		elif proposed["effect_dc"]!=null or not RAW.DIFFICULTY.has(args["difficulty"]):
			return {"ok":false,"error":"Use actual RAW difficulty category, not invented numeric DC."}
		ruling={"seconds":proposed["seconds"],"establish_clock":false,"optional_features_resolved":true,"verified_circumstances":args["circumstances"],"effect_dc":dc}
	elif kind in ROUTES:
		if not DTO.exact_keys(proposed,["difficult","clearance","establish_clock"]) or not proposed["difficult"] is bool or proposed["clearance"]!="verified_unobstructed_supplied_foot_travel" or proposed["establish_clock"]!=false:
			return {"ok":false,"error":"Route clearance, terrain or clock not established."}
		var context=controller.scene_context(state)
		if not context.get("ok",false) or not context["scene"]["routes"].any(func(route): return route["id"]==args["route_id"] and state["location_id"] in [route["from_id"],route["to_id"]] and args["destination_id"] in [route["from_id"],route["to_id"]] and args["destination_id"]!=state["location_id"]):
			return {"ok":false,"error":"Route is not an established local route."}
		ruling={"difficult":proposed["difficult"],"clearance":"verified_unobstructed_supplied_foot_travel","establish_clock":false}
	elif kind in ROUTINE+["wait"]:
		if not DTO.exact_keys(proposed,["safe_nonmechanical","seconds","establish_clock"]) or proposed["safe_nonmechanical"]!=true or proposed["seconds"]!=args.get("seconds",0) or not proposed["establish_clock"] is bool or (proposed["establish_clock"] and (kind!="wait" or state["elapsed_seconds"]!=null or not DTO.whole(args.get("seconds"),1,RAW.MAX_WALK_SECONDS))):
			return {"ok":false,"error":"No-roll action, duration or tracked epoch not established."}
		ruling={"safe_nonmechanical":true,"seconds":args.get("seconds",0),"establish_clock":proposed["establish_clock"]}
	else:
		if not proposed.is_empty():
			return {"ok":false,"error":"Standalone tool cannot accept proposed mechanical patches."}
		if not kind in DESCRIPTIVE+["party_membership","reconcile_legacy_slots"] and not controller.registry.noncombat.safe_actor(state):
			return {"ok":false,"error":"Actor outside supported noncombat slice."}
		if kind in ["item_transfer","currency_transfer"]:
			if args["from_actor_id"]==args["to_actor_id"] or not state["actor_id"] in [args["from_actor_id"],args["to_actor_id"]]:
				return {"ok":false,"error":"Invalid local transfer participants."}
			var npc=args["to_actor_id"] if args["from_actor_id"]==state["actor_id"] else args["from_actor_id"]
			var local=controller.enquiry("actors",{"location_id":state["location_id"]},64)
			if not local.get("ok",false) or not local["data"]["actors"].any(func(row): return row["actor_id"]==npc and row["kind"]=="npc"):
				return {"ok":false,"error":"Transfer requires disclosed local NPC."}
		if req==job.get("consequence_request"):
			var pending=job.get("pending_consequence",{})
			var consent=pending.get("proposal",{}).get("consent","")
			if not DTO.bounded_text(consent,2000) or not original.contains(consent) or not job.get("narration_event_id") in evidence_ids or pending.get("candidate_hash")!=str(pending.get("candidate",{}).get("text","")).sha256_text():
				return {"ok":false,"error":"Original consent or committed pending-offer source unavailable."}
	# Every rule reference used by C3 must exist in the pinned catalogue.
	for section in REG.TOOLS[kind][2]:
		var rule=controller.enquiry("rule_record",{"category":"rule-sections","id":section},1)
		if not rule.get("ok",false):
			return {"ok":false,"error":"Pinned applicable rule unavailable."}
	return {"ok":true,"ruling":ruling}

# Derive descriptive clearance only from the exact staged proposal and committed public narration.
# The registry still validates the typed operation and performs its own transaction.
func descriptive_assessment(req: Dictionary,job: Dictionary,state: Dictionary) -> Dictionary:
	if not req["kind"] in DESCRIPTIVE or req!=job.get("story_request") or not bound_request(req,job,state):
		return {}
	if req["kind"]!="story_update" and not controller.discovery_request_valid(req,job,state):
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
	if not state.get("ok",false) or scope.get("location_id")!=state["location_id"] or scope.get("revision")!=state["revision"] or intent!=job.get("intent") or not bound_request(req,job,state):
		return out
	if direct_safe(req,job,state):
		out["accepted"]=true
		out["ruling"]={"safe_nonmechanical":true,"seconds":0,"establish_clock":false} if req["kind"] in ROUTINE else {}
		out["reason"]="Local explicit safe selection or no-effect observation."
		return out
	var record=job.get("context_review",{})
	if record.get("request")!=req or record.get("revision")!=state["revision"] or not DTO.id_valid(record.get("attempt_id")):
		return out
	var checked=validate_assessment(req,record.get("report"),job,state)
	if checked.get("ok",false):
		out["accepted"]=true
		out["ruling"]=checked["ruling"]
		out["reason"]="Locally validated contextual evidence and registered rule shape."
	else:
		out["reason"]=checked["error"]
	return out

# C4 compatibility callback checks the same durable independent reports.
func review_prose(candidate: Dictionary,_claims: Array,outcome: Dictionary,scene: Dictionary) -> bool:
	var job=controller.active()
	return candidate==job.get("candidate") and controller.reviewed_candidate(job,outcome,scene)
