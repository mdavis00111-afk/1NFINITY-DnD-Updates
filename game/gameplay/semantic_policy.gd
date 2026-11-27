extends RefCounted
## Conservative independent local gate. Semantic proposals are not clearance.
## Contextual judgments beyond the deterministic safe slice require a separate
## trusted adjudicator, never the provider's approval flag.
const REG=preload("res://gameplay/tool_registry.gd")
const DTO=preload("res://world/world_dto.gd")
const RECON=preload("res://world/geography_reconciler.gd")
const PACK=preload("res://turns/agent_packets.gd")
const BASE=preload("res://campaigns/campaign_store.gd")
var controller: Node
var contextual: Callable
var prose: Callable

func review(req: Dictionary,scope: Dictionary,intent: Dictionary) -> Dictionary:
	var out={"request_id":req["request_id"],"campaign_id":req["campaign_id"],"actor_id":req["actor_id"],"expected_revision":req["expected_revision"],"accepted":false,"ruling":{},"reason":"Independent contextual review required; no effect committed."}
	if not is_instance_valid(controller) or not REG.TOOLS.has(req["kind"]):
		return out
	var state=controller.registry.session.token(req["campaign_id"])
	if not state.get("ok",false) or state["revision"]!=req["expected_revision"] or state["actor_id"]!=req["actor_id"] or scope["location_id"]!=state["location_id"] or intent["actor_id"]!=req["actor_id"] or intent["campaign_id"]!=req["campaign_id"] or not controller.registry.arguments_valid(req["args"],REG.TOOLS[req["kind"]][0]):
		return out
	if not controller.registry.noncombat.quiet_context(state):
		out["reason"]="Active encounter: combat not supported."
		return out
	var exact=intent["kind"]==req["kind"] and intent["args"]==req["args"]
	# Ordinary conversation and looking do not change possessions, position,
	# HP, time, resources or quests. No roll is implied.
	if req["kind"] in ["conversation","observe"] and intent["kind"]=="chat" and req["args"]["text"]==intent["args"]["text"]:
		out["accepted"]=true
		out["ruling"]={"safe_nonmechanical":true,"seconds":0,"establish_clock":false}
		out["reason"]="Bounded no-effect action; no implied mechanical success."
		return out
	# Explicit local selections; C3 checks ownership, slot displacement,
	# capacity and supported effect eligibility. No implicit target.
	if exact and req["kind"] in ["equip","swap","unequip","item_drop","loot_pickup","loot_take_all","reconcile_legacy_slots"] and controller.registry.noncombat.safe_actor(state):
		out["accepted"]=true
		out["reason"]="Explicit scoped selection; C3 validates actual state."
		return out
	# More consequential / context-dependent actions require independent local
	# evidence and judgment (safe rest, casting components, consent, DC, etc.).
	if contextual.is_valid():
		var decision=contextual.call(req.duplicate(true),scope.duplicate(true),intent.duplicate(true),state.duplicate(true))
		if decision is Dictionary and decision.get("request_id")==req["request_id"] and decision.get("expected_revision")==state["revision"]:
			return decision
	return out

func review_prose(candidate: Dictionary,claims: Array,outcome: Dictionary,scene: Dictionary) -> bool:
	var text=candidate.get("text","")
	if not DTO.bounded_text(text,12000):
		return false
	for claim in claims:
		if not claim is Dictionary or claim.get("kind") in ["agency","contradiction","required_effect"] or claim.get("proposal")!=null:
			return false
	# An independent trusted reviewer may authorize unrestricted creative prose
	# after checking the exact candidate, receipt/state and all omitted claims.
	if prose.is_valid():
		var result=prose.call(candidate.duplicate(true),claims.duplicate(true),outcome.duplicate(true),scene.duplicate(true))
		return result is bool and result
	# Without one, only mechanically inert static sensory lines can be proven
	# locally. Never treat an AI claim list as proof of unrestricted prose.
	var lines=RECON.new().sensory_lines(text)
	return not lines.is_empty() and (" ".join(lines)==text.strip_edges() or "\n".join(lines)==text.strip_edges())
