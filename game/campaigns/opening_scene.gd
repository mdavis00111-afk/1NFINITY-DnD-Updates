extends RefCounted
## Opening proposals only. No gameplay or AI-controlled identifiers.
const STARTS = preload("res://campaigns/campaign_starts.gd")
const NARRATOR = preload("res://campaigns/narrator_prompt.gd")
const POPULATED = ["tavern","court","sea","market"]
const KEYS = ["start_id","location_name","atmosphere","npcs","world_facts","thumbnail_id"]
# The model is asked for this bounded JSON shape; validate() still owns acceptance.
# Use the documented responseJsonSchema subset, not unsupported string length keywords.
const NPC_KEYS = ["name","occupation","attitude"]
const PHASE_RULES = "OPENING PROPOSAL ONLY. No player action has occurred. Name the existing location without changing its kind. Describe static surroundings only. Supply 1–4 ordinary named locals for tavern, court, sea or market; 0–4 for woods or road. Occupations are descriptive, not stat blocks. Attitude is an integer -5 to +5. Provide 1–4 durable descriptive local facts. No dialogue, player actions, threats requiring resolution, quests, destiny, combat, dice, rewards, inventory, time or movement. No new locations, coordinates, IDs or mechanics. Use existing artwork ID or empty. Return exactly one JSON object matching the schema, no extra keys or markdown. Plain single-line text: location/name/occupation <=80, atmosphere <=500, fact <=240 characters. This is a proposal for engine validation, not committed narration."

static func response_schema(start_id: String) -> Dictionary:
	if STARTS.find_start(start_id).is_empty():
		return {}
	var art_ids: Array = STARTS.ART.keys()
	art_ids.append("")
	var npc = {"type":"object","required":NPC_KEYS.duplicate(),"additionalProperties":false,"properties":{"name":{"type":"string"},"occupation":{"type":"string"},"attitude":{"type":"integer","minimum":-5,"maximum":5}}}
	return {"type":"object","required":KEYS.duplicate(),"additionalProperties":false,"properties":{
		"start_id":{"type":"string","enum":[start_id]},
		"location_name":{"type":"string"},
		"atmosphere":{"type":"string"},
		"npcs":{"type":"array","minItems":1 if start_id in POPULATED else 0,"maxItems":4,"items":npc},
		"world_facts":{"type":"array","minItems":1,"maxItems":4,"items":{"type":"string"}},
		"thumbnail_id":{"type":"string","enum":art_ids}
	}}

static func prompt(record: Dictionary) -> String:
	var start = STARTS.find_start(str(record.get("start_id","")))
	if start.is_empty():
		return ""
	var context = {"phase":"opening","start_id":start["id"],"location_kind":start["kind"],"starting_circumstances":start["description"],"campaign_title":record.get("title",""),"player_name":record.get("player_name","")}
	return NARRATOR.build(str(record.get("maturity_id","")),context,response_schema(start["id"]),PHASE_RULES)

static func exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func clean_text(value: Variant, limit: int) -> String:
	if not value is String or value.length()>limit:
		return ""
	for i in range(value.length()):
		var code = value.unicode_at(i)
		if code<32 or code==127 or code==8232 or code==8233:
			return ""
	return value.strip_edges()

# Strict shape and scope validation, not a semantic content classifier.
static func validate(raw: String, start_id: String) -> Dictionary:
	if raw.length()>4000 or STARTS.find_start(start_id).is_empty():
		return {}
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary or not exact_keys(parsed,KEYS) or parsed["start_id"]!=start_id:
		return {}
	var name = clean_text(parsed["location_name"],80)
	var atmosphere = clean_text(parsed["atmosphere"],500)
	if name.is_empty() or atmosphere.is_empty():
		return {}
	var npcs = parsed["npcs"]
	var facts = parsed["world_facts"]
	if not npcs is Array or npcs.size()>4 or (start_id in POPULATED and npcs.is_empty()):
		return {}
	if not facts is Array or facts.is_empty() or facts.size()>4:
		return {}
	var people: Array = []
	var names: Dictionary = {}
	for npc in npcs:
		if not npc is Dictionary or not exact_keys(npc,NPC_KEYS):
			return {}
		var npc_name = clean_text(npc["name"],80)
		var occupation = clean_text(npc["occupation"],80)
		var attitude = npc["attitude"]
		if npc_name.is_empty() or occupation.is_empty() or names.has(npc_name.to_lower()):
			return {}
		if not (attitude is int or attitude is float) or not is_finite(float(attitude)) or float(attitude)!=floor(float(attitude)) or absf(float(attitude))>5:
			return {}
		names[npc_name.to_lower()]=true
		people.append({"name":npc_name,"occupation":occupation,"attitude":int(attitude)})
	var local_facts: Array = []
	var seen: Dictionary = {}
	for fact in facts:
		var cleaned = clean_text(fact,240)
		if cleaned.is_empty() or seen.has(cleaned.to_lower()):
			return {}
		seen[cleaned.to_lower()]=true
		local_facts.append(cleaned)
	if not parsed["thumbnail_id"] is String or parsed["thumbnail_id"].length()>32:
		return {}
	var art = parsed["thumbnail_id"]
	if not STARTS.valid_art(art):
		art=start_id
	return {"start_id":start_id,"location_name":name,"atmosphere":atmosphere,"npcs":people,"world_facts":local_facts,"thumbnail_id":art}

# Assemble the opening log from the exact committed facts, not an independent AI outcome.
static func log_text(scene: Dictionary) -> String:
	var lines: PackedStringArray = [scene["location_name"],scene["atmosphere"]]
	for fact in scene["world_facts"]:
		lines.append(fact)
	for npc in scene["npcs"]:
		lines.append("%s — %s" % [npc["name"],npc["occupation"]])
	return "\n\n".join(lines)
