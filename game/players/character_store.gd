extends RefCounted
## Persistent SQLite player records. Existing JSON files remain intact after migration.
const SQL = preload("res://systems/sqlite.gd")
const ROOT = "user://players/v1"
const DB = "user://players.db"
const SCHEMA = 1
static var initialized: bool = false
static var last_error: String = ""

func make_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func valid_id(id: String) -> bool:
	var re = RegEx.new()
	re.compile("^[0-9a-f]{32}$")
	return re.search(id) != null

func commands_for(record: Dictionary, ignore: bool = false) -> Array:
	var id = str(record.get("id",""))
	var insert = "INSERT OR IGNORE" if ignore else "INSERT OR REPLACE"
	var out: Array = [SQL.stmt(insert+" INTO players(id,name,status,race_id,class_id,level,ruleset,revision,updated_at,payload) VALUES(?,?,?,?,?,?,?,?,?,?)",[id,record.get("name",""),record.get("status","draft"),record.get("race_id",""),record.get("class_id",""),int(record.get("level",1)),record.get("ruleset","5e-2014-2018"),record.get("catalog_revision",""),record.get("updated_at",""),JSON.stringify(record)])]
	if ignore:
		return out
	for key in ["ability_scores","skills","saving_throws","coins","combat","equipment","resources"]:
		for k in record.get(key,{}):
			out.append(SQL.stmt("INSERT INTO player_values(player_id,category,key,value) VALUES(?,?,?,?)",[id,key,k,JSON.stringify(record[key][k])]))
	for key in ["proficiency_ids","expertise_ids","language_ids","racial_trait_ids","class_feature_ids"]:
		for value in record.get(key,[]):
			out.append(SQL.stmt("INSERT OR IGNORE INTO player_refs(player_id,category,ref_id) VALUES(?,?,?)",[id,key,value]))
	for key in ["cantrip_ids","racial_cantrip_ids","known_ids","prepared_ids","always_prepared_ids"]:
		for value in record.get("spellcasting",{}).get(key,[]):
			out.append(SQL.stmt("INSERT OR IGNORE INTO player_refs(player_id,category,ref_id) VALUES(?,?,?)",[id,key,value]))
	for item in record.get("inventory",[]):
		out.append(SQL.stmt("INSERT INTO inventory(player_id,item_id,quantity,equipped,payload) VALUES(?,?,?,?,?)",[id,item["item_id"],int(item["quantity"]),1 if item.get("equipped",false) else 0,JSON.stringify(item)]))
	return out

func ensure() -> bool:
	if initialized:
		return true
	var result = SQL.run(DB,[SQL.stmt("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)"),SQL.stmt("CREATE TABLE IF NOT EXISTS players(id TEXT PRIMARY KEY,name TEXT NOT NULL,status TEXT NOT NULL,race_id TEXT,class_id TEXT,level INTEGER,ruleset TEXT,revision TEXT,updated_at TEXT,payload TEXT NOT NULL)"),SQL.stmt("CREATE INDEX IF NOT EXISTS players_name ON players(name COLLATE NOCASE)"),SQL.stmt("CREATE TABLE IF NOT EXISTS player_values(player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,category TEXT NOT NULL,key TEXT NOT NULL,value TEXT NOT NULL,PRIMARY KEY(player_id,category,key))"),SQL.stmt("CREATE TABLE IF NOT EXISTS player_refs(player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,category TEXT NOT NULL,ref_id TEXT NOT NULL,PRIMARY KEY(player_id,category,ref_id))"),SQL.stmt("CREATE TABLE IF NOT EXISTS inventory(player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,item_id TEXT NOT NULL,quantity INTEGER NOT NULL CHECK(quantity>0),equipped INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(player_id,item_id))"),SQL.stmt("CREATE TABLE IF NOT EXISTS archived_players(id TEXT PRIMARY KEY,payload TEXT NOT NULL,archived_at TEXT NOT NULL)"),SQL.stmt("SELECT value FROM meta WHERE key='legacy_migration'")])
	if not result.get("ok",false):
		last_error = str(result.get("error","Cannot open player database."))
		return false
	if result["results"].back().is_empty():
		var migration: Array = []
		var dir = DirAccess.open(ROOT)
		if dir != null:
			for name in dir.get_files():
				if not name.ends_with(".json") or not valid_id(name.trim_suffix(".json")):
					continue
				var row = JSON.parse_string(FileAccess.get_file_as_string(ROOT.path_join(name)))
				if row is Dictionary and row.get("id") == name.trim_suffix(".json") and row.get("ruleset") == "5e-2014-2018":
					migration.append_array(commands_for(row,false))
		migration.append(SQL.stmt("INSERT OR REPLACE INTO meta VALUES('legacy_migration','1')"))
		migration.append(SQL.stmt("INSERT OR REPLACE INTO meta VALUES('schema','1')"))
		var migrated = SQL.run(DB,migration)
		if not migrated.get("ok",false):
			last_error = str(migrated.get("error","Migration failed; original files retained."))
			return false
	initialized = true
	last_error = ""
	return true

func list_records() -> Array:
	if not ensure():
		return []
	var result = SQL.run(DB,[SQL.stmt("SELECT payload FROM players ORDER BY name COLLATE NOCASE")],true)
	if not result.get("ok",false):
		last_error = str(result.get("error","Cannot list players."))
		return []
	var rows: Array = []
	for r in result["results"][0]:
		var record = JSON.parse_string(str(r["payload"]))
		if record is Dictionary:
			rows.append(record)
	last_error = ""
	return rows

func load_record(id: String) -> Dictionary:
	if not valid_id(id) or not ensure():
		return {}
	var result = SQL.run(DB,[SQL.stmt("SELECT payload FROM players WHERE id=?",[id])],true)
	if result.get("ok",false) and not result["results"][0].is_empty():
		var record = JSON.parse_string(str(result["results"][0][0]["payload"]))
		if record is Dictionary:
			return record
	return {}

func save_record(record: Dictionary) -> String:
	if not valid_id(str(record.get("id",""))):
		return "Invalid character ID."
	if not ensure():
		return last_error
	var copy = record.duplicate(true)
	copy["schema_version"] = SCHEMA
	copy["updated_at"] = Time.get_datetime_string_from_system(true)
	if not copy.has("created_at"):
		copy["created_at"] = copy["updated_at"]
	var result = SQL.run(DB,commands_for(copy))
	return "" if result.get("ok",false) else str(result.get("error","Save failed."))

func save_portrait(id: String, source: String) -> String:
	if source.is_empty() or not valid_id(id):
		return ""
	if source.begins_with(ROOT + "/") and FileAccess.file_exists(source):
		return source
	var image = Image.load_from_file(source)
	if image.is_empty():
		return ""
	if maxi(image.get_width(),image.get_height()) > 1024:
		var scale = 1024.0 / maxi(image.get_width(),image.get_height())
		image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join("portraits"))) != OK:
		return ""
	var path = ROOT.path_join("portraits").path_join(id + ".png")
	if image.save_png(path) != OK:
		return ""
	return path

func archive(id: String) -> String:
	if not valid_id(id) or not ensure():
		return "Cannot access player."
	var result = SQL.run(DB,[SQL.stmt("INSERT OR REPLACE INTO archived_players SELECT id,payload,? FROM players WHERE id=?",[Time.get_datetime_string_from_system(true),id]),SQL.stmt("DELETE FROM players WHERE id=?",[id])])
	return "" if result.get("ok",false) else str(result.get("error","Archive failed."))

func campaign_template(id: String) -> Dictionary:
	var record = load_record(id)
	if record.get("status") != "ready" or record.get("id") != id or record.get("ruleset") != "5e-2014-2018" or not record.get("review_required",[]).is_empty():
		return {}
	var instance = record.duplicate(true)
	instance["master_character_id"] = id
	instance["id"] = make_id()
	return instance
