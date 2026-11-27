extends RefCounted
## Shared DTO boundary. Provider text is never an EngineEffect.
const VERSION = "1"
const PRECISIONS = ["unknown","provisional","approximate","surveyed"]
const DISCOVERY = ["unknown","reported","observed","visited","surveyed"]
const MAX_COORD = 1e12
const MAX_INT = 2147483647
const RECEIPT_KEYS = ["schema_version","campaign_id","actor_id","turn_id","prior_revision","next_revision","resulting_turn","results","rolls","effects","rule_refs"]
const SEGMENT_KEYS = ["from_id","to_id","route_id","distance_miles","elapsed_seconds","precision","points"]

static func exact_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func id_valid(value: Variant) -> bool:
	if not value is String or value.length()!=32:
		return false
	for i in range(value.length()):
		if not value.substr(i,1) in "0123456789abcdef":
			return false
	return true

static func whole(value: Variant, minimum: int = 0, maximum: int = MAX_INT) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=minimum and value<=maximum

static func number(value: Variant, minimum: float = -MAX_COORD, maximum: float = MAX_COORD) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=minimum and value<=maximum

static func bounded_text(value: Variant, maximum: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length()<=maximum

static func known_position(precision: String) -> bool:
	return precision in ["approximate","surveyed"]

static func points_valid(points: Variant, precision: String) -> bool:
	if not points is Array or points.size()>256:
		return false
	if not known_position(precision):
		return points.is_empty()
	if not points.is_empty() and points.size()<2:
		return false
	for point in points:
		if not exact_keys(point,["x","y"]) or not number(point["x"]) or not number(point["y"]):
			return false
	return true

static func movement_valid(effect: Variant) -> bool:
	if not exact_keys(effect,["kind","segments"]) or effect["kind"]!="movement" or not effect["segments"] is Array or effect["segments"].is_empty() or effect["segments"].size()>64:
		return false
	var previous = ""
	for segment in effect["segments"]:
		if not exact_keys(segment,SEGMENT_KEYS):
			return false
		if not id_valid(segment["from_id"]) or not id_valid(segment["to_id"]) or segment["from_id"]==segment["to_id"]:
			return false
		if not previous.is_empty() and segment["from_id"]!=previous:
			return false
		if segment["route_id"]!=null and not id_valid(segment["route_id"]):
			return false
		if segment["distance_miles"]!=null and not number(segment["distance_miles"],0):
			return false
		if segment["elapsed_seconds"]!=null and not whole(segment["elapsed_seconds"]):
			return false
		if not segment["precision"] in PRECISIONS or not points_valid(segment["points"],segment["precision"]):
			return false
		previous=segment["to_id"]
	return true

# B1 only accepts internal receipts with no effects or one resolved movement.
# B2 must validate registered rule/result/roll unions BEFORE using this API.
static func receipt_valid(receipt: Variant) -> bool:
	if not exact_keys(receipt,RECEIPT_KEYS) or receipt["schema_version"]!=VERSION:
		return false
	for key in ["campaign_id","actor_id","turn_id"]:
		if not id_valid(receipt[key]):
			return false
	if not whole(receipt["prior_revision"],0,MAX_INT-2) or not whole(receipt["next_revision"]) or receipt["next_revision"]!=receipt["prior_revision"]+1 or not whole(receipt["resulting_turn"],1):
		return false
	for key in ["results","rolls","effects","rule_refs"]:
		if not receipt[key] is Array or receipt[key].size()>128:
			return false
	for key in ["results","rolls","rule_refs"]:
		for item in receipt[key]:
			if not item is Dictionary:
				return false
	# Retain structural readability of B1 receipts; B2 store requires strict
	# registered unions for every new commit.
	if receipt["effects"].size()>2:
		return false
	var movement_seen = false
	var time_seen = false
	for effect in receipt["effects"]:
		if movement_valid(effect) and not movement_seen and not time_seen:
			movement_seen=true
		elif exact_keys(effect,["kind","seconds","establish_clock"]) and effect["kind"]=="time" and not time_seen and effect["establish_clock"] is bool and (effect["seconds"]==null or whole(effect["seconds"],0,28800)):
			time_seen=true
		else:
			return false
	return JSON.stringify(receipt).length()<=131072

# SQLite bridge returns string/null. Never silently turn absence into zero.
static func sql_number(value: Variant) -> Variant:
	if value==null:
		return null
	if not value is String or not value.is_valid_float():
		return null
	var parsed = float(value)
	return parsed if number(parsed) else null

static func sql_int(value: Variant) -> Variant:
	if value==null or not value is String or not value.is_valid_int():
		return null
	var parsed = int(value)
	return parsed if whole(parsed) else null


# Proposal-local keys are not persistent IDs. Reconciliation assigns IDs only
# after checking established region/parent/aliases and source evidence (B4).
static func local_key_valid(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>48:
		return false
	for i in range(value.length()):
		if not value.substr(i,1) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			return false
	return true

static func ref_valid(value: Variant, optional: bool = false) -> bool:
	if value==null:
		return optional
	if not exact_keys(value,["id","local_key"]):
		return false
	return (id_valid(value["id"]) and value["local_key"]==null) or (value["id"]==null and local_key_valid(value["local_key"]))

static func nullable_text(value: Variant, limit: int) -> bool:
	return value==null or bounded_text(value,limit)

static func geographic_fact_valid(fact: Variant) -> bool:
	if not fact is Dictionary or not bounded_text(fact.get("evidence"),1000):
		return false
	match fact.get("kind"):
		"place":
			if not exact_keys(fact,["kind","subject","name","place_kind","parent","region","position","precision","uncertainty_miles","elevation_feet","terrain","footprint","population","occupancy","asset_id","description","visibility","evidence"]):
				return false
			if not ref_valid(fact["subject"]) or not ref_valid(fact["parent"],true) or not ref_valid(fact["region"],true) or not bounded_text(fact["name"],100) or not bounded_text(fact["place_kind"],60):
				return false
			var precision = fact["precision"]
			if not precision in PRECISIONS:
				return false
			if known_position(precision):
				var position = fact["position"]
				if not exact_keys(position,["x","y"]) or not number(position["x"]) or not number(position["y"]) or not number(fact["uncertainty_miles"],0):
					return false
			elif fact["position"]!=null or fact["uncertainty_miles"]!=null:
				return false
			if not points_valid(fact["footprint"],precision) or (not fact["footprint"].is_empty() and fact["footprint"].size()<3):
				return false
			return (fact["elevation_feet"]==null or number(fact["elevation_feet"])) and (fact["population"]==null or whole(fact["population"])) and fact["occupancy"] in ["unknown","inhabited","uninhabited","abandoned"] and nullable_text(fact["terrain"],80) and nullable_text(fact["asset_id"],80) and nullable_text(fact["description"],2000) and fact["visibility"] in ["player","private"]
		"alias":
			return exact_keys(fact,["kind","subject","alias","visibility","evidence"]) and ref_valid(fact["subject"]) and bounded_text(fact["alias"],100) and fact["visibility"] in ["player","private"]
		"relationship":
			return exact_keys(fact,["kind","from","to","relation_kind","direction","distance_miles","precision","visibility","evidence"]) and ref_valid(fact["from"]) and ref_valid(fact["to"]) and fact["from"]!=fact["to"] and bounded_text(fact["relation_kind"],60) and nullable_text(fact["direction"],80) and (fact["distance_miles"]==null or number(fact["distance_miles"],0)) and fact["precision"] in PRECISIONS and fact["visibility"] in ["player","private"]
		"route":
			return exact_keys(fact,["kind","subject","from","to","name","route_kind","precision","distance_miles","points","visibility","evidence"]) and ref_valid(fact["subject"]) and ref_valid(fact["from"]) and ref_valid(fact["to"]) and fact["from"]!=fact["to"] and bounded_text(fact["name"],100) and bounded_text(fact["route_kind"],60) and fact["precision"] in PRECISIONS and (fact["distance_miles"]==null or number(fact["distance_miles"],0)) and points_valid(fact["points"],fact["precision"]) and fact["visibility"] in ["player","private"]
		"terrain_region":
			return exact_keys(fact,["kind","subject","parent","name","terrain_kind","precision","points","description","visibility","evidence"]) and ref_valid(fact["subject"]) and ref_valid(fact["parent"],true) and bounded_text(fact["name"],100) and bounded_text(fact["terrain_kind"],60) and fact["precision"] in PRECISIONS and points_valid(fact["points"],fact["precision"]) and (fact["points"].is_empty() or fact["points"].size()>=3) and nullable_text(fact["description"],2000) and fact["visibility"] in ["player","private"]
		"discovery":
			# The interpreter cannot declare actual visits or surveyed positions.
			return exact_keys(fact,["kind","subject","entity_kind","status","visibility","evidence"]) and ref_valid(fact["subject"]) and fact["entity_kind"] in ["place","route","terrain_region"] and fact["status"] in ["unknown","reported","observed"] and fact["visibility"] in ["player","private"] and (fact["status"]!="unknown" or fact["visibility"]=="private")
	return false

# Shape validation only. Caller must check the exact frozen envelope and source
# text, then reconcile canon/visibility and commit in the narration transaction.
static func geography_proposal_valid(packet: Variant) -> bool:
	if not exact_keys(packet,["schema_version","request_id","turn_id","campaign_id","actor_id","expected_revision","source_event_id","facts"]) or packet["schema_version"]!=VERSION:
		return false
	for key in ["request_id","turn_id","campaign_id","actor_id"]:
		if not id_valid(packet[key]):
			return false
	if not whole(packet["expected_revision"]) or (packet["source_event_id"]!=null and not whole(packet["source_event_id"],1)) or not packet["facts"] is Array or packet["facts"].size()>32:
		return false
	for fact in packet["facts"]:
		if not geographic_fact_valid(fact):
			return false
	return JSON.stringify(packet).length()<=65536
