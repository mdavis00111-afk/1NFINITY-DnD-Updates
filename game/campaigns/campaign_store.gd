extends RefCounted
## Campaign-local database. All writes through Godot-owned, bound SQLite batches.
const SQL = preload("res://systems/sqlite.gd")
const PLAYER = preload("res://players/character_store.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const ROOT = "user://campaigns/v1"
const SCHEMA = "1"
var last_error = ""
var loaded_metadata = ""

func valid_id(id: String) -> bool:
	return PLAYER.new().valid_id(id)

func path_for(id: String) -> String:
	return ROOT.path_join(id+".db") if valid_id(id) else ""

func db_exists(id: String) -> bool:
	return valid_id(id) and FileAccess.file_exists(path_for(id))

func schema_commands() -> Array:
	var commands: Array = []
	for raw in FileAccess.get_file_as_string("res://systems/campaign_schema.sql").split(";"):
		var statement = raw.strip_edges()
		if statement.is_empty() or statement.begins_with("PRAGMA"):
			continue
		commands.append(SQL.stmt(statement))
	return commands

func result_error(result: Dictionary, fallback: String) -> String:
	return str(result.get("error",fallback))

func create_campaign(title: String, player_id: String, start_id: String, maturity_id: String) -> Dictionary:
	last_error = ""
	var clean_title = title.strip_edges()
	var start = STARTS.find_start(start_id)
	var profile = MATURITY.resolve(maturity_id)
	if clean_title.is_empty() or clean_title.length()>100 or start.is_empty() or profile.is_empty() or not maturity_id in MATURITY.IDS:
		last_error = "Enter a campaign name and choose a valid opening and maturity profile."
		return {}
	var master = PLAYER.new()
	var actor = master.campaign_template(player_id)
	if actor.is_empty():
		last_error = "Choose a completed, ready character."
		return {}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT)) != OK:
		last_error = "Cannot create campaign storage."
		return {}
	var id = master.make_id()
	if db_exists(id):
		last_error = "Campaign ID collision. Please retry."
		return {}
	var location_id = master.make_id()
	var now = Time.get_datetime_string_from_system(true)
	var record = {"id":id,"title":clean_title,"player_name":str(actor.get("name","Unnamed")),"master_character_id":player_id,"actor_id":actor["id"],"location_id":location_id,"start_id":start_id,"start_name":start["name"],"maturity_id":maturity_id,"maturity_name":profile["name"],"thumbnail_id":start_id,"created_at":now,"updated_at":now,"status":"active","turn":0}
	var commands = schema_commands()
	if commands.is_empty():
		last_error = "Campaign schema unavailable."
		return {}
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('schema',?)",[SCHEMA]))
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('campaign',?)",[JSON.stringify(record)]))
	commands.append(SQL.stmt("INSERT INTO locations(id,parent_id,kind,name,x,y,payload) VALUES(?,NULL,?,?,NULL,NULL,?)",[location_id,start["kind"],start["name"],JSON.stringify({"start_id":start_id,"description":start["description"]})]))
	actor["location_id"]=location_id
	commands.append(SQL.stmt("INSERT INTO actors(id,master_character_id,kind,catalog_id,location_id,payload) VALUES(?,?,'player',NULL,?,?)",[actor["id"],player_id,location_id,JSON.stringify(actor)]))
	for item in actor.get("inventory",[]):
		commands.append(SQL.stmt("INSERT INTO inventory(actor_id,item_id,quantity,payload) VALUES(?,?,?,?)",[actor["id"],item["item_id"],int(item["quantity"]),JSON.stringify(item)]))
	commands.append(SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,?,'campaign_created',?)",["Unstarted",JSON.stringify({"text":start["description"],"start_id":start_id,"actor_id":actor["id"]})]))
	var result = SQL.run(path_for(id),commands)
	if not result.get("ok",false):
		last_error = result_error(result,"Campaign creation failed.")
		# This UUID is new and has never been exposed as a valid campaign.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(id)))
		return {}
	return record

func load_campaign(id: String, include_deleted: bool = false) -> Dictionary:
	last_error = ""
	loaded_metadata = ""
	if not db_exists(id):
		last_error = "Campaign not found."
		return {}
	var result = SQL.run(path_for(id),[SQL.stmt("SELECT value FROM meta WHERE key='schema'"),SQL.stmt("SELECT value FROM meta WHERE key='campaign'")],true)
	if not result.get("ok",false):
		last_error = result_error(result,"Cannot open campaign.")
		return {}
	var rows = result["results"]
	if rows.size()!=2 or rows[0].is_empty() or rows[1].is_empty() or str(rows[0][0]["value"])!=SCHEMA:
		last_error = "Unsupported or incomplete campaign schema."
		return {}
	var raw_metadata = str(rows[1][0]["value"])
	var record = JSON.parse_string(raw_metadata)
	if not record is Dictionary or record.get("id")!=id or record.get("status") not in ["active","deleted"]:
		last_error = "Invalid campaign metadata."
		return {}
	if record["status"]=="deleted" and not include_deleted:
		return {}
	loaded_metadata = raw_metadata
	return record

func list_campaigns() -> Array:
	last_error = ""
	var folder = DirAccess.open(ROOT)
	if folder == null:
		return []
	var records: Array = []
	var errors: PackedStringArray = []
	for filename in folder.get_files():
		if not filename.ends_with(".db"):
			continue
		var id = filename.trim_suffix(".db")
		if not valid_id(id):
			continue
		var row = load_campaign(id)
		if not row.is_empty():
			records.append(row)
		elif not last_error.is_empty():
			errors.append(id.left(8)+": "+last_error)
	records.sort_custom(func(a,b): return str(a.get("updated_at",""))>str(b.get("updated_at","")))
	last_error = "; ".join(errors)
	return records

func update_thumbnail(id: String, thumbnail_id: String) -> String:
	if not STARTS.valid_art(thumbnail_id):
		return "Unknown artwork."
	var record = load_campaign(id)
	if record.is_empty():
		return last_error if not last_error.is_empty() else "Campaign is unavailable."
	record["thumbnail_id"]=thumbnail_id
	return write_metadata(id,loaded_metadata,record)

func delete_campaign(id: String) -> String:
	var record = load_campaign(id)
	if record.is_empty():
		return last_error if not last_error.is_empty() else "Campaign is unavailable."
	record["status"]="deleted"
	record["updated_at"]=Time.get_datetime_string_from_system(true)
	return write_metadata(id,loaded_metadata,record,true)

# Compare the exact stored JSON, not a reserialized approximation. The bridge
# runs the UPDATE and optional event together under BEGIN IMMEDIATE.
func write_metadata(id: String, previous: String, record: Dictionary, deleting: bool = false) -> String:
	if not db_exists(id) or previous.is_empty():
		return "Campaign is unavailable."
	var commands = [SQL.stmt("UPDATE meta SET value=? WHERE key='campaign' AND value=?",[JSON.stringify(record),previous]),SQL.stmt("SELECT changes() AS updated")]
	if deleting:
		commands.append(SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) SELECT ?,?,'campaign_deleted',? WHERE changes()=1",[int(record.get("turn",0)),"Unspecified",JSON.stringify({"deleted_at":record["updated_at"]})]))
	var result = SQL.run(path_for(id),commands)
	if not result.get("ok",false):
		return result_error(result,"Campaign metadata save failed.")
	if int(result["results"][1][0]["updated"])!=1:
		return "Campaign changed since it was loaded. Reopen and retry."
	return ""

func read_log(id: String, limit: int = 40) -> Array:
	last_error = ""
	if not db_exists(id):
		last_error = "Campaign not found."
		return []
	var result = SQL.run(path_for(id),[SQL.stmt("SELECT id,turn,game_time,kind,payload FROM events WHERE kind IN ('campaign_created','narration','synopsis') ORDER BY id DESC LIMIT ?",[clampi(limit,1,200)])],true)
	if not result.get("ok",false):
		last_error = result_error(result,"Cannot read campaign log.")
		return []
	var entries: Array = []
	for row in result["results"][0]:
		var payload = JSON.parse_string(str(row["payload"]))
		if payload is Dictionary and payload.get("text") is String:
			entries.append({"kind":row["kind"],"turn":int(row["turn"]),"text":str(payload["text"])})
	entries.reverse()
	return entries

func synopsis(id: String) -> String:
	var entries = read_log(id,30)
	if not last_error.is_empty():
		return last_error
	if entries.is_empty():
		return "No campaign log entries yet."
	# Prefer the last committed synopsis, followed by subsequent log entries.
	var start_index = 0
	for i in range(entries.size()):
		if entries[i]["kind"]=="synopsis":
			start_index=i
	var text: PackedStringArray = []
	for i in range(start_index,entries.size()):
		text.append(entries[i]["text"])
	return "\n\n".join(text).right(8000)

func actor_record(id: String) -> Dictionary:
	var record = load_campaign(id)
	if record.is_empty():
		return {}
	var result = SQL.run(path_for(id),[SQL.stmt("SELECT payload FROM actors WHERE id=? AND kind='player'",[record["actor_id"]])],true)
	if not result.get("ok",false) or result["results"][0].is_empty():
		last_error = result_error(result,"Campaign player not found.")
		return {}
	var actor = JSON.parse_string(str(result["results"][0][0]["payload"]))
	return actor if actor is Dictionary else {}
