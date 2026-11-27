extends RefCounted
## Versioned, additive campaign-local extension. No master data access.
const SQL = preload("res://systems/sqlite.gd")
const BASE = preload("res://campaigns/campaign_store.gd")
const VERSION = "1"
const MIGRATION = "res://world/world_schema.sql"
var last_error = ""

func path_for(id: String) -> String:
	var store = BASE.new()
	return store.path_for(id) if store.db_exists(id) else ""

func ensure(id: String) -> Dictionary:
	last_error=""
	var store = BASE.new()
	var record = store.load_campaign(id)
	if record.is_empty():
		return failure("Campaign unavailable.")
	var path = store.path_for(id)
	var previous = store.loaded_metadata
	var check = SQL.run(path,[SQL.stmt("SELECT value FROM meta WHERE key='world_schema'")],true)
	if not check.get("ok",false):
		return failure("Cannot inspect world schema.")
	if not check["results"][0].is_empty():
		if check["results"][0][0]["value"]!=VERSION:
			return failure("Unsupported world schema version.")
		var state = SQL.run(path,[SQL.stmt("SELECT campaign_id FROM world_state")],true)
		if not state.get("ok",false) or state["results"][0].size()!=1 or state["results"][0][0]["campaign_id"]!=id:
			return failure("World state identity mismatch.")
		return {"ok":true,"migrated":false}
	# Consistent SQLite snapshot, not a raw file copy of a possibly open DB.
	# VACUUM INTO requires SQLite 3.27+. Fail closed if the platform lacks it.
	var backup = path.trim_suffix(".db")+".pre-world-"+Crypto.new().generate_random_bytes(16).hex_encode()+".bak"
	var copied = SQL.run(path,[SQL.stmt("VACUUM INTO ?",[ProjectSettings.globalize_path(backup)])],true)
	if not copied.get("ok",false):
		return failure("World migration backup failed. Original campaign unchanged.")
	var verified = SQL.run(backup,[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),SQL.stmt("SELECT value FROM meta WHERE key='schema'")],true)
	if not verified.get("ok",false) or verified["results"][0].size()!=1 or verified["results"][0][0].get("integrity_check")!="ok" or verified["results"][1].size()!=1 or verified["results"][1][0]["value"]!=previous or verified["results"][2].size()!=1 or verified["results"][2][0]["value"]!="1":
		return failure("World migration backup did not match the campaign. Original unchanged.")
	var commands: Array = [SQL.stmt("INSERT INTO meta(key,value) VALUES('world_migration_guard',(SELECT value FROM meta WHERE key='campaign' AND value=? AND NOT EXISTS(SELECT 1 FROM meta WHERE key='world_schema')))",[previous])]
	var source = FileAccess.get_file_as_string(MIGRATION)
	if source.is_empty():
		return failure("World schema resource unavailable.")
	for raw in source.split(";"):
		var statement = raw.strip_edges()
		if not statement.is_empty():
			commands.append(SQL.stmt(statement))
	var turn = record.get("turn",0)
	if not (turn is int or turn is float) or not is_finite(float(turn)) or float(turn)!=floor(float(turn)) or turn<0 or turn>2147483647:
		return failure("Invalid legacy campaign turn.")
	commands.append(SQL.stmt("INSERT INTO world_state(campaign_id,revision,turn_number) VALUES(?,0,?)",[id,int(turn)]))
	# Existing numeric coordinates have unknown provenance; leave original values
	# intact but never expose them as known world-space coordinates.
	commands.append(SQL.stmt("INSERT INTO world_places(location_id) SELECT id FROM locations"))
	# Only actual saved player position plus an existing committed start event is
	# evidence of a visited place. Other legacy locations remain undisclosed.
	commands.append(SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility,first_event_id,last_visit_event_id) SELECT l.id,l.id,'visited','player',e.id,e.id FROM locations l JOIN actors a ON a.location_id=l.id JOIN events e ON e.id=(SELECT min(id) FROM events WHERE kind='campaign_created' AND turn=0) WHERE a.id=? AND a.kind='player' AND l.id=?",[record.get("actor_id",""),record.get("location_id","")]))
	# Seed only committed turn-zero descriptive data and provenance. Preserve
	# raw legacy coordinates, actor payloads and original event records.
	var opening = SQL.run(path,[SQL.stmt("SELECT e.id,e.payload,l.id AS location_id,l.payload AS location_payload FROM events e JOIN locations l ON l.id=? WHERE e.kind='narration' AND e.turn=0 ORDER BY e.id LIMIT 1",[record.get("location_id","")])],true)
	if not opening.get("ok",false):
		return failure("Cannot read opening provenance.")
	if not opening["results"][0].is_empty():
		var row = opening["results"][0][0]
		var event = JSON.parse_string(row["payload"])
		var place = JSON.parse_string(row["location_payload"])
		if event is Dictionary and event.get("phase")=="opening" and event.get("location_id")==row["location_id"] and place is Dictionary and place.get("opening_generated")==true and place.get("description") is String:
			commands.append(SQL.stmt("UPDATE world_places SET description=?,public_description=?,source_event_id=? WHERE location_id=?",[place["description"],place["description"],row["id"],row["location_id"]]))
			# Opening NPC names/occupations are public only when explicitly in
			# that committed opening log. No other actor payload is disclosed.
			var npcs = SQL.run(path,[SQL.stmt("SELECT id,payload FROM actors WHERE kind='npc' AND location_id=? ORDER BY id LIMIT 32",[row["location_id"]])],true)
			if not npcs.get("ok",false):
				return failure("Cannot read opening NPC provenance.")
			for npc in npcs["results"][0]:
				var data = JSON.parse_string(npc["payload"])
				if data is Dictionary and data.get("descriptive_only")==true and data.get("name") is String and data.get("occupation") is String and str(event.get("text","")).contains(data["name"]+" — "+data["occupation"]):
					commands.append(SQL.stmt("INSERT INTO world_links(id,location_id,actor_id,source_event_id) VALUES(?,?,?,?)",[Crypto.new().generate_random_bytes(16).hex_encode(),row["location_id"],npc["id"],row["id"]]))
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('world_schema',?)",[VERSION]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='world_migration_guard'"))
	var result = SQL.run(path,commands)
	if not result.get("ok",false):
		return failure("World migration failed or campaign changed. Backup retained; retry after reopening.")
	return {"ok":true,"migrated":true,"backup":backup}

func failure(message: String) -> Dictionary:
	last_error=message
	return {"ok":false,"error":message}
