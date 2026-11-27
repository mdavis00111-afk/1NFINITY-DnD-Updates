extends RefCounted
## B2 trusted local controller boundary. Never pass provider JSON as approval.
## One logical action per turn. No UI/provider wiring; B3 owns that integration.
const DTO = preload("res://world/world_dto.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const STORE = preload("res://turns/turn_store.gd")
const CAT = preload("res://rules/catalog.gd")
const KEYS = ["schema_version","request_id","turn_id","campaign_id","actor_id","expected_revision","status","actions","clarification","rule_refs"]
var store = STORE.new()
var cat = CAT.new()
# Preserve a prepared receipt after ambiguous acknowledgement. Do not roll a
# second time while this resolver instance holds an unresolved logical turn.
var unresolved: Dictionary = {}

func validate_proposal(token: Dictionary, request_id: String, turn_id: String, proposal: Variant, offered_refs: Array) -> Dictionary:
	if not token.get("ok",false) or not DTO.id_valid(request_id) or not DTO.id_valid(turn_id) or not DTO.exact_keys(proposal,KEYS) or JSON.stringify(proposal).length()>65536:
		return RAW.fail("Malformed action proposal.","invalid")
	if proposal["schema_version"]!="1" or proposal["request_id"]!=request_id or proposal["turn_id"]!=turn_id or proposal["campaign_id"]!=token["campaign_id"] or proposal["actor_id"]!=token["actor_id"] or not DTO.whole(proposal["expected_revision"]) or proposal["expected_revision"]!=token["revision"]:
		return RAW.fail("Stale or mismatched action proposal.","invalid")
	if not proposal["actions"] is Array or not proposal["rule_refs"] is Array or proposal["rule_refs"].size()>32:
		return RAW.fail("Invalid action or rule references.","invalid")
	if not cat.initialize():
		return RAW.fail("The pinned 2014/2018 rules catalogue is unavailable.")
	for rule in proposal["rule_refs"]:
		if not RAW.ref_valid(rule,cat) or not rule in offered_refs:
			return RAW.fail("Rule was not in the frozen context.","invalid")
	if proposal["status"] in ["clarification","unsupported"]:
		if not proposal["actions"].is_empty() or not DTO.bounded_text(proposal["clarification"],1000):
			return RAW.fail("Invalid clarification envelope.","invalid")
		return RAW.fail(proposal["clarification"],proposal["status"])
	if proposal["status"]!="proposed" or proposal["clarification"]!=null or proposal["actions"].size()!=1:
		return RAW.fail("Submit one supported action at a time.","clarification")
	var action = proposal["actions"][0]
	if not DTO.exact_keys(action,["handler_id","target_refs","reference_refs","intent_text","arguments"]) or not DTO.bounded_text(action["intent_text"],2000) or not action["target_refs"] is Array or not action["reference_refs"] is Array or action["reference_refs"].size()>32 or action["target_refs"].size()>1:
		return RAW.fail("Malformed action intent.","invalid")
	for rule in action["reference_refs"]:
		if not rule in proposal["rule_refs"]:
			return RAW.fail("Action reference not offered.","invalid")
	var kind = action["handler_id"]
	var args = action["arguments"]
	if not kind in RAW.HANDLERS:
		return RAW.fail("Action handler is not implemented.")
	if kind in ["ability_check","saving_throw"]:
		if not DTO.exact_keys(args,["ability","skill"]) or not args["ability"] in RAW.ABILITIES or (args["skill"]!=null and (not DTO.bounded_text(args["skill"],100) or cat.get_record("skills",args["skill"]).is_empty())) or (kind=="saving_throw" and args["skill"]!=null) or not action["target_refs"].is_empty():
			return RAW.fail("Invalid check or save operands.","invalid")
	elif kind in ["move","travel"]:
		if not DTO.exact_keys(args,["route_id","destination_id","pace","fast_travel"]) or not DTO.id_valid(args["route_id"]) or not DTO.id_valid(args["destination_id"]) or not RAW.PACE.has(args["pace"]) or not args["fast_travel"] is bool or action["target_refs"]!=[{"kind":"location","id":args["destination_id"]}]:
			return RAW.fail("Choose one known destination and route.","clarification")
	else:
		if not DTO.exact_keys(args,[]) or not action["target_refs"].is_empty():
			return RAW.fail("Unexpected action operands.","invalid")
	var required = RAW.refs_for(kind)
	if kind in ["ability_check","saving_throw"]:
		if not RAW.actor_ready(token["actor"]):
			return RAW.fail("Actor edition, revision, statistics or effects require review.")
		required=RAW.refs_for(kind,args["ability"],args["skill"],token["actor"])
	for rule in required:
		if not rule in offered_refs or not RAW.ref_valid(rule,cat):
			return RAW.fail("Required verified rule was not in the frozen context.")
	return {"ok":true,"action":action}

# Local approval binds the exact interpreted action and snapshot. It is
# supplied ONLY by trusted Godot adjudication or explicit human adjudication,
# never by copying a model reply. Missing rules/clearance are a hard stop.
func approval_valid(token: Dictionary, turn_id: String, action: Dictionary, approval: Variant) -> bool:
	return DTO.exact_keys(approval,["campaign_id","actor_id","turn_id","expected_revision","action","ruling"]) and approval["campaign_id"]==token["campaign_id"] and approval["actor_id"]==token["actor_id"] and approval["turn_id"]==turn_id and DTO.whole(approval["expected_revision"]) and approval["expected_revision"]==token["revision"] and approval["action"]==action and approval["ruling"] is Dictionary

func time_effect(seconds: Variant, establish_clock: bool) -> Dictionary:
	return {"kind":"time","seconds":seconds,"establish_clock":establish_clock}

func prepare(token: Dictionary, turn_id: String, action: Dictionary, approval: Variant) -> Dictionary:
	if not approval_valid(token,turn_id,action,approval):
		return RAW.fail("Local player-intent confirmation and adjudication are required.","clarification")
	if token.get("pending_turn_id")!=null:
		return RAW.fail("Committed narration is pending.","clarification")
	var kind = action["handler_id"]
	var args = action["arguments"]
	var ruling = approval["ruling"]
	var receipt = {"schema_version":"1","campaign_id":token["campaign_id"],"actor_id":token["actor_id"],"turn_id":turn_id,"prior_revision":token["revision"],"next_revision":token["revision"]+1,"resulting_turn":token["turn"]+1,"results":[],"rolls":[],"effects":[],"rule_refs":[]}
	var result: Dictionary = {}
	var time: Dictionary = {}
	if kind in ["ability_check","saving_throw"]:
		if not DTO.exact_keys(ruling,["difficulty","effect_dc","advantage","disadvantage","seconds","establish_clock","optional_features_resolved"]) or not ruling["advantage"] is bool or not ruling["disadvantage"] is bool or not ruling["establish_clock"] is bool or not ruling["optional_features_resolved"] is bool or ruling["optional_features_resolved"]!=true:
			return RAW.fail("Check/save needs a locally approved challenge, circumstances and feature handling.","clarification")
		var dc: int
		if kind=="ability_check" and RAW.DIFFICULTY.has(ruling["difficulty"]) and ruling["effect_dc"]==null:
			dc=int(RAW.DIFFICULTY[ruling["difficulty"]])
		elif ruling["difficulty"]==null and DTO.whole(ruling["effect_dc"],0,DTO.MAX_INT):
			# Saving DC is supplied by the verified triggering effect; a fixed
			# check DC must likewise come from a locally verified rule/challenge.
			dc=int(ruling["effect_dc"])
		else:
			return RAW.fail("No verified challenge or effect DC.","clarification")
		var mod = RAW.modifier_for(token["actor"],kind,args["ability"],args["skill"],cat)
		if not mod.get("ok",false):
			return mod
		var context = RAW.roll_context(token["actor"],kind,args["ability"],ruling["advantage"],ruling["disadvantage"])
		if not context.get("ok",false):
			return context
		time=time_effect(ruling["seconds"],ruling["establish_clock"])
		receipt["rule_refs"]=RAW.refs_for(kind,args["ability"],args["skill"],token["actor"])
		if not RAW.time_valid(time,token) or not RAW.valid_refs(receipt["rule_refs"],receipt["rule_refs"],cat):
			return RAW.fail("Time or required rules are unavailable.")
		result={"kind":kind,"ability":args["ability"],"skill":args["skill"],"dc":dc,"advantage":ruling["advantage"],"disadvantage":ruling["disadvantage"],"mode":context["mode"],"outcome":"automatic_failure","roll_id":null}
		# Optional roll-altering features must be handled/declined locally
		# before this basic handler. No silently consumed inspiration or reroll.
		if not context["automatic_failure"]:
			var roll = RAW.roll_receipt(kind,context["mode"],mod["modifier"],dc)
			receipt["rolls"].append(roll)
			result["roll_id"]=roll["roll_id"]
			result["outcome"]=roll["result"]
	elif kind in ["move","travel"]:
		if not DTO.exact_keys(ruling,["difficult","clearance","establish_clock"]) or not ruling["difficult"] is bool or not ruling["establish_clock"] is bool or ruling["clearance"]!="verified_unobstructed_supplied_foot_travel":
			return RAW.fail("Route hazards, resources, terrain and travel clearance require local resolution.","clarification")
		var actor = RAW.travel_actor(token["actor"],token["inventory"],cat)
		if not actor.get("ok",false):
			return actor
		var route = store.route_context(token["campaign_id"],token,args["route_id"],args["destination_id"])
		if not route.get("ok",false):
			return RAW.fail(route["error"],"clarification")
		var seconds = RAW.travel_seconds(route["distance"],args["pace"],ruling["difficult"])
		if seconds==null or route["walked"]+int(seconds)>RAW.MAX_WALK_SECONDS:
			return RAW.fail("Journey exceeds the supported eight-hour walking allowance; forced march/rest resolution required.")
		if args["fast_travel"] and route["prior_traversals"]==0:
			return RAW.fail("Fast travel requires a previously traversed route; use ordinary travel.","clarification")
		time=time_effect(seconds,ruling["establish_clock"])
		result={"kind":kind,"outcome":"arrived","pace":args["pace"],"difficult":ruling["difficult"],"fast_travel":args["fast_travel"],"passive_perception":actor["passive_perception"]-(5 if args["pace"]=="fast" else 0),"route_id":args["route_id"],"destination_id":args["destination_id"]}
		receipt["effects"].append({"kind":"movement","segments":[{"from_id":token["location_id"],"to_id":args["destination_id"],"route_id":args["route_id"],"distance_miles":route["distance"],"elapsed_seconds":seconds,"precision":route["row"]["precision"],"points":route["points"]}]})
		receipt["rule_refs"]=RAW.refs_for(kind)
	elif kind in ["observe","wait"]:
		if not DTO.exact_keys(ruling,["seconds","establish_clock","safe_nonmechanical"]) or not ruling["safe_nonmechanical"] is bool or ruling["safe_nonmechanical"]!=true or not ruling["establish_clock"] is bool or (kind=="wait" and not DTO.whole(ruling["seconds"],1,RAW.MAX_WALK_SECONDS)):
			return RAW.fail("Local duration and absence of unresolved effects required.","clarification")
		time=time_effect(ruling["seconds"],ruling["establish_clock"])
		result={"kind":kind,"outcome":"completed"}
		receipt["rule_refs"]=RAW.refs_for(kind)
	else:
		return RAW.fail("Handler unavailable.")
	receipt["results"].append(result)
	receipt["effects"].append(time)
	if not RAW.receipt_valid(receipt,token,cat):
		return RAW.fail("Mechanical plan did not satisfy the registered receipt contract.")
	return {"ok":true,"receipt":receipt}

# Lookup first, even after a network or commit error. A found receipt is
# returned untouched. An unconfirmed in-memory receipt is retried as-is.
func resolve(id: String, token: Dictionary, request_id: String, turn_id: String, proposal: Variant, offered_refs: Array, approval: Variant, player_text: String = "") -> Dictionary:
	if not player_text.is_empty() and not DTO.bounded_text(player_text,2000):
		return RAW.fail("Invalid local player action text.","invalid")
	if not DTO.id_valid(id) or id!=token.get("campaign_id") or not DTO.id_valid(turn_id):
		return RAW.fail("Wrong campaign or turn identity.","invalid")
	var prior = store.receipt_by_id(id,turn_id)
	if not prior.get("ok",false):
		return prior
	if prior.get("found",false):
		if prior["receipt"]["actor_id"]!=token.get("actor_id") or not RAW.stored_receipt_usable(prior["receipt"]):
			return RAW.fail("Stored receipt requires review; no new roll.","invalid")
		if unresolved.has(id) and unresolved[id]["receipt"]["turn_id"]==turn_id:
			unresolved.erase(id)
		return {"ok":true,"replayed":true,"receipt":prior["receipt"],"narration_event_id":prior["narration_event_id"]}
	if unresolved.has(id):
		var pending = unresolved[id]
		if pending["receipt"]["turn_id"]!=turn_id:
			return RAW.fail("An unconfirmed receipt must be reconciled before another turn.")
		var latest = store.snapshot(id)
		if not latest.get("ok",false):
			return latest
		if not store.matching_token(pending["token"],latest):
			return RAW.fail("Uncommitted receipt is stale; explicitly abandon it before replanning.")
		var retry = store.commit_receipt(id,pending["token"],pending["receipt"],str(pending.get("player_text","")))
		if retry.get("ok",false):
			unresolved.erase(id)
		return retry
	var current = store.snapshot(id)
	if not current.get("ok",false) or not store.matching_token(token,current):
		return RAW.fail("Frozen turn context changed; request clarification/replan.","invalid")
	var verified = validate_proposal(current,request_id,turn_id,proposal,offered_refs)
	if not verified.get("ok",false):
		return verified
	var planned = prepare(current,turn_id,verified["action"],approval)
	if not planned.get("ok",false):
		return planned
	unresolved[id]={"token":current,"receipt":planned["receipt"],"player_text":player_text}
	var committed = store.commit_receipt(id,current,planned["receipt"],player_text)
	if committed.get("ok",false):
		unresolved.erase(id)
	return committed

# Local explicit abandon, only after successful lookup proves there is no
# committed receipt. Caller must use a new logical ID for a new action.
func abandon_uncommitted(id: String, turn_id: String) -> Dictionary:
	if not unresolved.has(id) or unresolved[id]["receipt"]["turn_id"]!=turn_id:
		return RAW.fail("No matching prepared receipt.")
	var prior = store.receipt_by_id(id,turn_id)
	if not prior.get("ok",false):
		return prior
	if prior.get("found",false):
		return RAW.fail("Receipt already committed; resume narration instead.")
	unresolved.erase(id)
	return {"ok":true,"abandoned_turn_id":turn_id}
