extends RefCounted
## Immutable, local, edition-specific reference catalogue. IDs are stable across screens.
const SQL = preload("res://systems/sqlite.gd")
const ROOT = "res://data/rules.db"
const RULESET = "5e-2014-2018"
const REVISION = "srd51-2018-r2"
const TABLES = ["races","subraces","classes","subclasses","backgrounds","skills","spells","equipment","equipment-categories","features","levels","languages","proficiencies","traits","ability-scores","magic-items","conditions","feats","weapon-properties","rule-sections","monsters"]
static var cache: Dictionary = {}
static var indexes: Dictionary = {}
static var loaded: bool = false
static var last_error: String = ""

func initialize() -> bool:
	if loaded:
		return true
	var database = database_path()
	if database.is_empty():
		return false
	var result = SQL.run(database,[SQL.stmt("SELECT value FROM metadata WHERE key='ruleset'"),SQL.stmt("SELECT category,id,payload FROM catalog ORDER BY category,name COLLATE NOCASE")],true)
	if not result.get("ok",false):
		last_error = str(result.get("error","Cannot open rules database."))
		return false
	var lists = result.get("results",[])
	if lists.size()!=2 or lists[0].is_empty() or lists[0][0].get("value")!=RULESET:
		last_error = "Wrong rules database edition."
		return false
	cache.clear()
	indexes.clear()
	for t in TABLES:
		cache[t] = []
		indexes[t] = {}
	for row in lists[1]:
		var t = str(row["category"])
		if not cache.has(t):
			continue
		var record = JSON.parse_string(str(row["payload"]))
		if not record is Dictionary:
			last_error = "Invalid catalogue record: "+str(row["id"])
			return false
		cache[t].append(record)
		indexes[t][str(row["id"])] = record
	# Personal-use book text is separate from the distributable rules database.
	var private_path = OS.get_executable_path().get_base_dir().path_join("reference/private_rules.db")
	if FileAccess.file_exists(private_path):
		var local = SQL.run(private_path,[SQL.stmt("SELECT category,id,payload FROM catalog WHERE category='monsters' ORDER BY name COLLATE NOCASE")],true)
		if local.get("ok",false):
			for row in local["results"][0]:
				var record = JSON.parse_string(str(row["payload"]))
				if record is Dictionary:
					cache["monsters"].append(record)
					indexes["monsters"][str(row["id"])] = record
	loaded = not cache["classes"].is_empty()
	return loaded

# Release transport uses gzip; the Windows ZIP already contains the raw DB.
# The unpacked cache is accepted only if it matches the original database SHA-256.
func database_path() -> String:
	var expected = "c4ce8012056b69d4f14c6a48b0a330408ed68562221ad3925d480100920ddb00"
	if FileAccess.file_exists(ROOT) and FileAccess.get_sha256(ROOT) == expected:
		return ROOT
	var folder = "user://rules_cache"
	var cached = folder.path_join("srd51-2018-r2-" + expected.left(16) + ".db")
	if FileAccess.file_exists(cached) and FileAccess.get_sha256(cached) == expected:
		return cached
	if not FileAccess.file_exists(ROOT + ".gz"):
		last_error = "Rules database missing or checksum mismatch."
		return ""
	var packed = FileAccess.get_file_as_bytes(ROOT + ".gz")
	var unpacked = packed.decompress_dynamic(3534848,FileAccess.COMPRESSION_GZIP)
	if unpacked.size() != 3534848:
		last_error = "Rules database decompression failed."
		return ""
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		last_error = "Cannot create rules cache."
		return ""
	var temp = cached + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var file = FileAccess.open(temp,FileAccess.WRITE)
	if file == null:
		last_error = "Cannot write rules database."
		return ""
	file.store_buffer(unpacked)
	file.close()
	if FileAccess.get_sha256(temp) != expected:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		last_error = "Rules database checksum mismatch."
		return ""
	if FileAccess.file_exists(cached):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cached))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(cached)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		last_error = "Cannot activate rules database cache."
		return ""
	return cached

func rows(table: String) -> Array:
	if not table in TABLES or not initialize():
		return []
	return cache.get(table,[])

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
			if k in ["url","index","image","source","source_page","verification","class_levels","subclass_levels"]:
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
	var parts: PackedStringArray = [title(table,id)]
	var shown: Array = []
	for k in ["synopsis","desc","higher_level","range","casting_time","duration","components","material","ritual","concentration","level","school","hit_die","speed","size","size_description","age","alignment","ability_bonuses","ability_bonus_options","ability_score","saving_throws","damage","armor_class","cost","weight","properties","feature","starting_gold","starting_equipment","starting_equipment_options","proficiency_choices","proficiencies","starting_proficiencies","languages","language_desc","language_options","spellcasting","feature_specific","trait_specific","typical_speakers","script","rarity","contents","type","class","subclass","subclasses","prerequisites"]:
		if rec.has(k) and rec[k] != null:
			parts.append(human(rec[k]) if k in ["synopsis","desc"] else str(k).replace("_"," ").capitalize() + "\n" + human(rec[k]))
			shown.append(k)
	for k in rec:
		if not k in shown and not k in ["name","index","url","image","source","source_page","verification","class_levels","subclass_levels"] and rec[k] != null:
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
	if parts.size() <= 1:
		parts.append(human(rec))
	return "\n\n".join(parts)

func summary(table: String, id: String) -> String:
	var s = describe(table,id)
	return s.left(650) + ("…" if s.length() > 650 else "")
