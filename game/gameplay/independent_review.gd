extends RefCounted
## Independent semantic assessments are evidence, not provider clearance.
## Local reconciliation compares material claims and checks actual outcomes.
const DTO=preload("res://world/world_dto.gd")
const REG=preload("res://gameplay/tool_registry.gd")
const PACK=preload("res://turns/agent_packets.gd")
const TRANSFERS=["item_transfer","currency_transfer"]
const KINDS=["description","dialogue","npc_action","offer","hypothetical","receipt_claim","agency","disclosure","contradiction","required_effect"]
const HARMFUL=["agency","disclosure","contradiction"]
const MATERIAL=["receipt_claim","required_effect"]
var controller: Node

func outcome_value(outcome: Dictionary,path: Variant) -> Dictionary:
	if not path is Array or path.is_empty() or path.size()>8 or not path[0] in ["results","rolls","effects","result","action"]:
		return {}
	var value: Variant=outcome
	for key in path:
		if value is Dictionary and key is String and key not in ["dc","target","points"] and value.has(key):
			value=value[key]
		elif value is Array and DTO.whole(key,0,value.size()-1):
			value=value[int(key)]
		else:
			return {}
	if value is Dictionary or value is Array or value==null:
		return {}
	return {"value":value}

func public_ids(scene: Dictionary,view: Dictionary) -> Array:
	var ids: Array=[controller.actor_id]
	for key in ["locations","routes","regions","local_npcs","local_quests"]:
		for row in scene.get(key,[]):
			if DTO.id_valid(row.get("id")) and not row["id"] in ids:
				ids.append(row["id"])
	for key in ["public_actors","public_quests","story_records","inventory_instances","loot_containers"]:
		for row in view.get(key,[]):
			for field in ["id","actor_id","instance_id","container_id","record_id","quest_id"]:
				if DTO.id_valid(row.get(field)) and not row[field] in ids:
					ids.append(row[field])
	return ids

func evidence_valid(value: Variant,text: String) -> bool:
	return DTO.bounded_text(value,2000) and text.contains(value)

func parse_report(report: Variant,text: String,original: String,outcome: Dictionary,known: Array) -> Dictionary:
	if not DTO.exact_keys(report,["candidate_hash","coverage","claims"]) or report["candidate_hash"]!=text.sha256_text() or not report["coverage"] is Array or report["coverage"].is_empty() or report["coverage"].size()>64 or not report["claims"] is Array or report["claims"].size()>48:
		return {"ok":false,"error":"Invalid review envelope."}
	# Coverage is explicit traversal of exact passage, not a truth assertion.
	# Offsets are local character offsets; ordered contiguous spans cover all.
	var end=0
	for span in report["coverage"]:
		if not DTO.exact_keys(span,["start","end"]) or not DTO.whole(span["start"],0,text.length()) or not DTO.whole(span["end"],1,text.length()) or span["start"]!=end or span["end"]<=end:
			return {"ok":false,"error":"Incomplete passage coverage."}
		end=int(span["end"])
	if end!=text.length():
		return {"ok":false,"error":"Review omitted part of passage."}
	var material: Array=[]
	for claim in report["claims"]:
		if not DTO.exact_keys(claim,["kind","evidence","refs","proposal"]) or not claim["kind"] in KINDS or not evidence_valid(claim["evidence"],text) or not claim["refs"] is Array or claim["refs"].size()>16:
			return {"ok":false,"error":"Malformed semantic claim."}
		for id in claim["refs"]:
			if not DTO.id_valid(id) or not id in known:
				return {"ok":false,"error":"Claim refers to undisclosed or unavailable identity."}
		if claim["kind"] in HARMFUL:
			return {"ok":false,"error":"Review identified "+claim["kind"]+": "+claim["evidence"].left(240)}
		if claim["kind"]=="receipt_claim":
			var proposal=claim["proposal"]
			if not DTO.exact_keys(proposal,["path","value"]):
				return {"ok":false,"error":"Quantified outcome needs a typed receipt assertion."}
			var actual=outcome_value(outcome,proposal["path"])
			if actual.is_empty() or actual["value"]!=proposal["value"]:
				return {"ok":false,"error":"Narrative outcome contradicts the verified result."}
		elif claim["kind"]=="required_effect":
			var proposal=claim["proposal"]
			if not DTO.exact_keys(proposal,["kind","args","consent"]) or not proposal["kind"] in TRANSFERS or not transfer_args_valid(proposal["kind"],proposal["args"]) or not evidence_valid(proposal["consent"],original):
				return {"ok":false,"error":"New effect is unsupported or lacks original player consent."}
			var args=proposal["args"]
			if args["from_actor_id"]==args["to_actor_id"] or not controller.actor_id in [args["from_actor_id"],args["to_actor_id"]] or not args["from_actor_id"] in known or not args["to_actor_id"] in known:
				return {"ok":false,"error":"Transfer parties are not established."}
			if outcome.get("action")==proposal["kind"]:
				return {"ok":false,"error":"Possible repeated settled transfer; describe the existing outcome instead."}
		elif claim["proposal"]!=null:
			return {"ok":false,"error":"Descriptive claim cannot carry an effect."}
		if claim["kind"] in MATERIAL:
			material.append(claim.duplicate(true))
	return {"ok":true,"material":material}

func same_material(a: Dictionary,b: Dictionary) -> bool:
	# Wording of excerpts need not match exactly; both must cite overlapping
	# text and the same concrete assertion / effect. No approval boolean.
	return a["kind"]==b["kind"] and a["proposal"]==b["proposal"] and (a["evidence"].contains(b["evidence"]) or b["evidence"].contains(a["evidence"]))

func reconcile(first: Dictionary,second: Dictionary,text: String,original: String,outcome: Dictionary,known: Array) -> Dictionary:
	var a=parse_report(first,text,original,outcome,known)
	var b=parse_report(second,text,original,outcome,known)
	if not a.get("ok",false):
		return a
	if not b.get("ok",false):
		return b
	for pair in [[a["material"],b["material"]],[b["material"],a["material"]]]:
		for claim in pair[0]:
			if not pair[1].any(func(other): return same_material(claim,other)):
				return {"ok":false,"error":"Independent review disagrees on a consequential claim."}
	var effects: Array=[]
	for claim in a["material"]:
		if claim["kind"]=="required_effect" and not effects.any(func(other): return other["proposal"]==claim["proposal"]):
			effects.append(claim)
	if effects.size()>1:
		return {"ok":false,"error":"Multiple new transfers require a separate ordered action."}
	return {"ok":true,"effects":effects}

# For an NPC possession not publicly enumerated, a reviewer may identify
# its definition rather than invent a private instance ID. Resolve only
# that specific possession locally after the original narrative settles.
func transfer_args_valid(kind: String,args: Variant) -> bool:
	if controller.registry.arguments_valid(args,REG.TOOLS[kind][0]):
		return true
	return kind=="item_transfer" and DTO.exact_keys(args,["from_actor_id","to_actor_id","definition_id","quantity"]) and DTO.id_valid(args["from_actor_id"]) and DTO.id_valid(args["to_actor_id"]) and DTO.bounded_text(args["definition_id"],100) and DTO.whole(args["quantity"],1,DTO.MAX_INT)

func resolve_transfer(proposal: Dictionary,state: Dictionary) -> Dictionary:
	var kind=proposal["kind"]
	var args=proposal["args"].duplicate(true)
	if not transfer_args_valid(kind,args):
		return {}
	if kind=="item_transfer" and args.has("definition_id"):
		var pack=controller.registry.noncombat.read_owned(state,args["from_actor_id"])
		if not pack.get("ok",false):
			return {}
		var matches_found: Array=[]
		for iid in pack["items"]:
			var item=pack["items"][iid]
			if item["definition_id"]==args["definition_id"] and item["quantity"]>=args["quantity"] and not controller.registry.noncombat.assigned(pack,iid) and item["attunement"]!="attuned":
				matches_found.append(iid)
		if matches_found.size()!=1:
			return {}
		args.erase("definition_id")
		args["instance_id"]=matches_found[0]
	return args if controller.registry.arguments_valid(args,REG.TOOLS[kind][0]) else {}
