extends RefCounted
## Campaign-local database. All writes through Godot-owned, bound SQLite batches.
const SQL = preload("res://systems/sqlite.gd")
const PLAYER = preload("res://players/character_store.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const OPENING = preload("res://campaigns/opening_scene.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const CATALOG = preload("res://rules/catalog.gd")
const C2_VIEW = preload("res://persistence/interaction_projection.gd")
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

# Only a pristine campaign may receive a one-time opening proposal.
func opening_guard(record: Dictionary, previous: String) -> Dictionary:
	var start = STARTS.find_start(str(record.get("start_id","")))
	return SQL.stmt("SELECT value FROM meta WHERE key='campaign' AND value=? AND EXISTS(SELECT 1 FROM locations WHERE id=? AND kind=? AND parent_id IS NULL AND x IS NULL AND y IS NULL) AND (SELECT count(*) FROM locations)=1 AND EXISTS(SELECT 1 FROM actors WHERE id=? AND kind='player' AND location_id=?) AND (SELECT count(*) FROM actors)=1 AND (SELECT count(*) FROM events)=1 AND EXISTS(SELECT 1 FROM events WHERE kind='campaign_created' AND turn=0) AND NOT EXISTS(SELECT 1 FROM quests) AND NOT EXISTS(SELECT 1 FROM encounters) AND NOT EXISTS(SELECT 1 FROM relationships)",[previous,record["location_id"],start.get("kind",""),record["actor_id"],record["location_id"]])

func opening_eligible(record: Dictionary) -> bool:
	return not record.is_empty() and record.get("status")=="active" and record.get("turn") == 0 and not record.get("opening_committed",false) and valid_id(str(record.get("actor_id",""))) and valid_id(str(record.get("location_id",""))) and not STARTS.find_start(str(record.get("start_id",""))).is_empty()

func prepare_opening(id: String) -> Dictionary:
	var record = load_campaign(id)
	if not opening_eligible(record):
		last_error="Campaign opening is unavailable or already committed."
		return {}
	var previous = loaded_metadata
	var check = SQL.run(path_for(id),[opening_guard(record,previous)],true)
	if not check.get("ok",false) or check["results"][0].is_empty():
		last_error="Campaign is no longer in its original opening state."
		return {}
	return {"record":record,"previous":previous,"prompt":OPENING.prompt(record),"response_schema":OPENING.response_schema(str(record["start_id"]))}

func commit_opening(id: String, previous: String, raw: String) -> String:
	var prepared = prepare_opening(id)
	if prepared.is_empty() or prepared["previous"]!=previous:
		return "Opening changed or is no longer available. No scene saved."
	var record: Dictionary = prepared["record"]
	var scene = OPENING.validate(raw,str(record["start_id"]))
	if scene.is_empty():
		return "Opening response was invalid. No scene saved."
	var guard = opening_guard(record,previous)
	var location_id = str(record["location_id"])
	var location = {"start_id":record["start_id"],"description":scene["atmosphere"],"world_facts":scene["world_facts"],"opening_generated":true}
	var commands: Array = []
	# Recheck under the write lock. NULL violates meta.value NOT NULL and rolls back.
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('opening_commit_guard',("+guard["sql"]+"))",guard["params"]))
	commands.append(SQL.stmt("UPDATE locations SET name=?,payload=? WHERE id=?",[scene["location_name"],JSON.stringify(location),location_id]))
	var maker = PLAYER.new()
	var opening_npc_ids: Array = []
	for npc in scene["npcs"]:
		var npc_id = maker.make_id()
		opening_npc_ids.append(npc_id)
		var payload = {"id":npc_id,"name":npc["name"],"occupation":npc["occupation"],"attitude":npc["attitude"],"location_id":location_id,"descriptive_only":true}
		commands.append(SQL.stmt("INSERT INTO actors(id,master_character_id,kind,catalog_id,location_id,payload) VALUES(?,NULL,'npc',NULL,?,?)",[npc_id,location_id,JSON.stringify(payload)]))
	record["opening_committed"]=true
	record["location_name"]=scene["location_name"]
	record["thumbnail_id"]=scene["thumbnail_id"]
	record["updated_at"]=Time.get_datetime_string_from_system(true)
	commands.append(SQL.stmt("UPDATE meta SET value=? WHERE key='campaign'",[JSON.stringify(record)]))
	commands.append(SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(0,?,'narration',?)",["Unstarted",JSON.stringify({"text":OPENING.log_text(scene),"phase":"opening","location_id":location_id})]))
	# If the world extension is present, synchronize the opening in this same
	# transaction. A concurrent migration/turn cannot leave split provenance.
	var marker = SQL.run(path_for(id),[SQL.stmt("SELECT value FROM meta WHERE key='world_schema'"),SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'")],true)
	if not marker.get("ok",false):
		return "Cannot inspect world schema. No opening saved."
	var c2 = null if marker["results"][1].is_empty() else marker["results"][1][0]["value"]
	if c2!=null and c2!="1":
		return "Unsupported gameplay schema. No opening saved."
	if marker["results"][0].is_empty():
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('opening_world_guard',(SELECT 'ok' WHERE NOT EXISTS(SELECT 1 FROM meta WHERE key IN ('world_schema','gameplay_schema'))))"))
	else:
		if marker["results"][0][0]["value"]!="1":
			return "Unsupported world schema. No opening saved."
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('opening_world_guard',(SELECT 'ok' FROM world_state WHERE campaign_id=? AND revision=CAST(? AS INTEGER) AND turn_number=0 AND pending_turn_id IS NULL AND EXISTS(SELECT 1 FROM world_places WHERE location_id=?) AND ((? IS NULL AND NOT EXISTS(SELECT 1 FROM meta WHERE key='gameplay_schema')) OR EXISTS(SELECT 1 FROM meta WHERE key='gameplay_schema' AND value=?))))",[id,1 if c2=="1" else 0,location_id,c2,c2]))
		commands.append(SQL.stmt("UPDATE world_places SET description=?,public_description=?,source_event_id=(SELECT max(id) FROM events WHERE turn=0 AND kind='narration') WHERE location_id=?",[scene["atmosphere"],scene["atmosphere"],location_id]))
		for npc_id in opening_npc_ids:
			commands.append(SQL.stmt("INSERT INTO world_links(id,location_id,actor_id,source_event_id) VALUES(?,?,?,(SELECT max(id) FROM events WHERE turn=0 AND kind='narration'))",[maker.make_id(),location_id,npc_id]))
		if c2=="1":
			commands.append(SQL.stmt("UPDATE story_records SET description=?,location_id=?,updated_event_id=(SELECT max(id) FROM events WHERE turn=0 AND kind='narration') WHERE identity_key='campaign-situation' AND kind='situation'",[OPENING.log_text(scene),location_id]))
		commands.append(SQL.stmt("UPDATE world_state SET revision=revision+1 WHERE campaign_id=?",[id]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='opening_world_guard'"))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='opening_commit_guard'"))
	var result = SQL.run(path_for(id),commands)
	if not result.get("ok",false):
		return "Opening could not be committed. No scene saved."
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

# Read-only workspace projection. Inventory quantities come from normalized rows,
# not the actor's original inventory snapshot. No master player access or writes.
func gameplay_view(id: String) -> Dictionary:
	var record = load_campaign(id)
	if record.is_empty():
		return {}
	var actor_id = str(record.get("actor_id",""))
	if not valid_id(actor_id):
		last_error = "Invalid campaign player identifier."
		return {}
	var expected_metadata = loaded_metadata
	# Legacy saves work without migrating. Once the extension exists, the old
	# location-list popup must not bypass player discovery or precision.
	var marker = SQL.run(path_for(id),[SQL.stmt("SELECT value FROM meta WHERE key='world_schema'"),SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'")],true)
	if not marker.get("ok",false):
		last_error = "Cannot inspect world schema."
		return {}
	var world_version = null if marker["results"][0].is_empty() else marker["results"][0][0]["value"]
	var gameplay_version = null if marker["results"][1].is_empty() else marker["results"][1][0]["value"]
	if gameplay_version!=null and (gameplay_version!="1" or world_version!="1"):
		last_error = "Unsupported gameplay schema."
		return {}
	if world_version!=null and world_version!="1":
		last_error = "Unsupported world schema version."
		return {}
	var location_sql = "SELECT id,name,kind,x,y,payload FROM locations ORDER BY name COLLATE NOCASE,id"
	if world_version=="1":
		location_sql = "SELECT l.id,l.name,l.kind,CASE WHEN w.precision IN ('approximate','surveyed') THEN l.x END AS x,CASE WHEN w.precision IN ('approximate','surveyed') THEN l.y END AS y,CASE WHEN l.id=? AND d.first_event_id=(SELECT min(id) FROM events WHERE kind='campaign_created' AND turn=0) THEN l.payload ELSE '{}' END AS payload,w.public_description FROM locations l JOIN world_places w ON w.location_id=l.id JOIN world_discovery d ON d.location_id=l.id WHERE d.visibility='player' AND d.status<>'unknown' ORDER BY l.name COLLATE NOCASE,l.id"
	var location_command = SQL.stmt(location_sql,[record.get("location_id","")] if world_version=="1" else [])
	# Use the exact same eligibility guard as the opening write, in the read snapshot.
	var available = opening_guard(record,expected_metadata) if opening_eligible(record) else SQL.stmt("SELECT NULL WHERE 0")
	var commands: Array = [
		SQL.stmt("BEGIN"),
		SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),
		SQL.stmt("SELECT payload,location_id,master_character_id FROM actors WHERE id=? AND kind='player'",[actor_id]),
		SQL.stmt("SELECT item_id,quantity,payload FROM inventory WHERE actor_id=? ORDER BY item_id",[actor_id]),
		SQL.stmt("SELECT id,turn,kind,payload FROM events WHERE kind IN ('campaign_created','narration') ORDER BY id"),
		location_command,
		SQL.stmt("SELECT id,status,payload FROM quests ORDER BY id"),
		available,
		SQL.stmt("SELECT value FROM meta WHERE key='world_schema'"),
		SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'")
	]
	if gameplay_version=="1":
		commands.append_array(C2_VIEW.new().commands(id,actor_id,str(record.get("location_id",""))))
	commands.append(SQL.stmt("COMMIT"))
	var result = SQL.run(path_for(id),commands,true)
	if not result.get("ok",false):
		last_error = result_error(result,"Cannot read campaign workspace.")
		return {}
	var sets: Array = result.get("results",[])
	if sets.size()!=commands.size() or sets[1].size()!=1 or str(sets[1][0]["value"])!=expected_metadata or sets[2].size()!=1:
		last_error = "Campaign changed or player data unavailable. Reopen and retry."
		return {}
	var snapshot_version = null if sets[8].is_empty() else sets[8][0]["value"]
	var snapshot_gameplay = null if sets[9].is_empty() else sets[9][0]["value"]
	if snapshot_version!=world_version or snapshot_gameplay!=gameplay_version:
		last_error = "World or gameplay schema changed. Reopen and retry."
		return {}
	var c2_sets: Array = sets.slice(10,sets.size()-1) if gameplay_version=="1" else []
	# One read-only transaction on the bridge connection.
	var can_open = not sets[7].is_empty()
	sets = sets.slice(2,7)
	var actor = JSON.parse_string(str(sets[0][0]["payload"]))
	if not actor is Dictionary or actor.get("id")!=actor_id or not valid_id(str(record.get("master_character_id",""))) or actor.get("master_character_id")!=record["master_character_id"] or sets[0][0].get("master_character_id")!=record["master_character_id"]:
		last_error = "Invalid campaign player identity."
		return {}
	if not display_shape_valid(actor):
		last_error = "Campaign player data is malformed. No saved data was changed."
		return {}
	actor["location_id"] = sets[0][0]["location_id"]
	var items: Array = []
	for row in sets[1]:
		var payload = JSON.parse_string(str(row["payload"]))
		if not payload is Dictionary:
			payload = {}
		payload["item_id"] = str(row["item_id"])
		# SQLite affinity and CHECK(quantity>0) alone do not exclude REAL or text.
		var quantity_text = str(row["quantity"])
		if not quantity_text.is_valid_int() or int(quantity_text)<=0:
			last_error = "Campaign inventory quantity is invalid. No saved data was changed."
			return {}
		payload["quantity"] = int(quantity_text)
		items.append(payload)
	DISPLAY.project_inventory(CATALOG.new(),actor,items)
	var events: Array = []
	for row in sets[2]:
		var payload = JSON.parse_string(str(row["payload"]))
		if payload is Dictionary and payload.get("text") is String:
			events.append({"id":int(row["id"]),"turn":int(row["turn"]),"kind":str(row["kind"]),"text":payload["text"]})
	var locations: Array = []
	var current: Dictionary = {}
	for row in sets[3]:
		var payload = JSON.parse_string(str(row["payload"]))
		if not payload is Dictionary:
			payload = {}
		if world_version=="1":
			var public_facts: Array = []
			# Only the already player-visible opening facts, not arbitrary legacy
			# payload keys. New geography is projected separately by world_store.
			if payload.get("opening_generated")==true and payload.get("world_facts") is Array:
				for fact in payload["world_facts"].slice(0,16):
					if fact is String and fact.length()<=500:
						public_facts.append(fact)
			payload={"world_facts":public_facts,"description":str(row.get("public_description",""))}
		var location = {"id":str(row["id"]),"name":str(row["name"]),"kind":str(row["kind"]),"x":row["x"],"y":row["y"],"payload":payload}
		locations.append(location)
		if location["id"]==actor["location_id"]:
			current=location
	var quests: Array = []
	for row in sets[4]:
		var payload = JSON.parse_string(str(row["payload"]))
		quests.append({"id":str(row["id"]),"status":str(row["status"]),"payload":payload if payload is Dictionary else {}})
	var snapshot = {"campaign":record,"actor":actor,"inventory":items,"events":events,"locations":locations,"location":current,"quests":quests,"opening_available":can_open}
	if gameplay_version=="1":
		var extension = C2_VIEW.new().project(snapshot,c2_sets)
		if extension.is_empty():
			last_error = "Authoritative gameplay state unavailable or inconsistent. No saved data changed."
			return {}
		if extension["interaction"]!=null:
			snapshot["interaction"]=extension["interaction"]
		snapshot["interaction_extension"]=extension["interaction_extension"]
		snapshot["events"]=extension["events"]
		snapshot["actor"]["weight_projection"]=extension["weight_projection"]
		snapshot["actor"]["carried_weight_lb"]=extension["weight_projection"]["known_lb"] if extension["weight_projection"]["complete"] else null
		# Do not expose raw private legacy quest payloads after C2 migration.
		var disclosed: Array = []
		for quest in extension["interaction_extension"]["public_quests"]:
			disclosed.append({"id":quest["id"],"status":quest["status"],"payload":{"title":quest["title"],"public_description":quest["description"],"public":true}})
		snapshot["quests"]=disclosed
	return snapshot

# Reject malformed present containers before display code dereferences them. Missing
# optional fields remain supported for older snapshots; never rewrite saved data.
func display_shape_valid(actor: Dictionary) -> bool:
	for key in ["combat","ability_scores","ability_modifiers","saving_throws","skills","coins","equipment","spellcasting","resources","background_feature"]:
		if actor.has(key) and not actor[key] is Dictionary:
			return false
	for key in ["attacks","proficiency_ids","expertise_ids","racial_trait_ids","class_feature_ids","language_ids"]:
		if actor.has(key) and not actor[key] is Array:
			return false
	for value in actor.get("attacks",[]):
		if not value is Dictionary:
			return false
	for key in ["skills","resources"]:
		for value in actor.get(key,{}).values():
			if not value is Dictionary:
				return false
	var equipment = actor.get("equipment",{})
	if not equipment.get("weapon_ids",[]) is Array:
		return false
	var spellcasting = actor.get("spellcasting",{})
	var slots = spellcasting.get("slots",{})
	if not slots is Dictionary:
		return false
	for slot in slots.values():
		if not slot is Dictionary:
			return false
	for key in ["cantrip_ids","racial_cantrip_ids","known_ids","prepared_ids","always_prepared_ids"]:
		if not spellcasting.get(key,[]) is Array:
			return false
	if not actor.get("combat",{}).get("conditions",[]) is Array:
		return false
	return true
