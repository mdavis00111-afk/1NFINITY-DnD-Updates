extends RefCounted
## Immutable, local, edition-specific reference catalogue. IDs are stable across screens.
const ROOT = "res://data/2014/"
const RULESET = "5e-2014-2018"
const REVISION = "srd51-2018-r1"
const TABLES = ["races","subraces","classes","subclasses","backgrounds","skills","spells","equipment","equipment-categories","features","levels","languages","proficiencies","traits","ability-scores","magic-items","conditions","feats","weapon-properties","rule-sections"]
var cache: Dictionary = {}
var indexes: Dictionary = {}

func rows(table: String) -> Array:
	if not table in TABLES:
		return []
	if not cache.has(table):
		var data = JSON.parse_string(FileAccess.get_file_as_string(ROOT + table + ".json"))
		cache[table] = data if data is Array else []
		var index = {}
		for record in cache[table]:
			if record is Dictionary:
				index[str(record.get("index",""))] = record
		indexes[table] = index
	return cache[table]

func get_record(table: String, id: String) -> Dictionary:
	rows(table)
	return indexes.get(table, {}).get(id, {})

func title(table: String, id: String) -> String:
	return str(get_record(table,id).get("name",id.replace("-"," ").capitalize()))

func references(values: Array) -> Array:
	var result: Array = []
	for v in values:
		if v is Dictionary and v.has("index"):
			result.append(str(v["index"]))
	return result

func filtered(table: String, field: String, id: String) -> Array:
	var result: Array = []
	for v in rows(table):
		var value = v.get(field)
		if value is Dictionary and value.get("index") == id:
			result.append(v)
	return result

func spell_rows(role: String, level: int, subclass_id: String = "") -> Array:
	var result: Array = []
	for spell in rows("spells"):
		if int(spell.get("level",-1)) == level and (role in references(spell.get("classes",[])) or (not subclass_id.is_empty() and subclass_id in references(spell.get("subclasses",[])))):
			result.append(spell)
	return result

func human(value: Variant, depth: int = 0) -> String:
	if value == null:
		return "Not specified"
	if depth > 5:
		return "See referenced entry"
	if value is Dictionary:
		if value.has("name") and value.has("index") and value.size() <= 3:
			return str(value["name"])
		var lines: PackedStringArray = []
		for k in value:
			if k in ["url","index","image","class_levels","subclass_levels"]:
				continue
			lines.append(str(k).replace("_"," ").capitalize() + ": " + human(value[k],depth + 1))
		return "\n".join(lines)
	if value is Array:
		var lines: PackedStringArray = []
		for v in value:
			lines.append(human(v,depth + 1))
		return "\n".join(lines)
	return str(value)

func describe(table: String, id: String) -> String:
	if table == "proficiencies" and id.begins_with("skill-"):
		return describe("skills",id.trim_prefix("skill-"))
	var rec = get_record(table,id)
	if rec.is_empty():
		return "Reference not in this catalogue: " + id
	var parts: PackedStringArray = [title(table,id), "Original 5e | " + str(rec.get("source","SRD 5.1"))]
	var shown: Array = []
	for k in ["synopsis","desc","higher_level","range","casting_time","duration","components","material","ritual","concentration","level","school","hit_die","speed","size","size_description","age","alignment","ability_bonuses","ability_bonus_options","ability_score","saving_throws","damage","armor_class","cost","weight","properties","feature","starting_gold","starting_equipment","starting_equipment_options","proficiency_choices","proficiencies","starting_proficiencies","languages","language_desc","language_options","spellcasting","feature_specific","trait_specific","typical_speakers","script","rarity","contents","type","class","subclass","subclasses","prerequisites"]:
		if rec.has(k) and rec[k] != null:
			parts.append(str(k).replace("_"," ").capitalize() + "\n" + human(rec[k]))
			shown.append(k)
	for k in rec:
		if not k in shown and not k in ["name","index","url","image","source","class_levels","subclass_levels"] and rec[k] != null:
			parts.append(str(k).replace("_"," ").capitalize()+"\n"+human(rec[k]))
	if table == "races" or table == "subraces":
		for trait_id in references(rec.get("traits",rec.get("racial_traits",[]))):
			var t = get_record("traits",trait_id)
			parts.append(title("traits",trait_id) + "\n" + human(t.get("desc",[])))
	if table == "classes":
		for f in references(get_record("levels",id+"-1").get("features",[])):
			parts.append(title("features",f) + "\n" + human(get_record("features",f).get("desc",[])))
	if table == "proficiencies" and rec.has("reference"):
		var p = rec["reference"]
		var path = str(p.get("url","")).split("/")
		if path.size() >= 2 and path[path.size()-2] == "equipment":
			parts.append(describe("equipment",str(p.get("index",""))))
	if table == "equipment":
		for prop in references(rec.get("properties",[])):
			parts.append(title("weapon-properties",prop) + "\n" + human(get_record("weapon-properties",prop).get("desc",[])))
	if parts.size() <= 2:
		parts.append(human(rec))
	return "\n\n".join(parts)

func summary(table: String, id: String) -> String:
	var s = describe(table,id)
	return s.left(650) + ("…" if s.length() > 650 else "")
