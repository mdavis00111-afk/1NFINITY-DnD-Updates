extends RefCounted
## Explicit migration only. Legacy normalized inventory remains the compatibility
## aggregate, instances are authoritative for C2/C3 transfers. Never write master.
const SQL = preload("res://systems/sqlite.gd")
const BASE = preload("res://campaigns/campaign_store.gd")
const WORLD = preload("res://world/world_migration.gd")
const ITEMS = preload("res://persistence/item_catalog.gd")
const DTO = preload("res://world/world_dto.gd")
const SCHEMA = "res://persistence/gameplay_schema.sql"
const VERSION = "1"

func fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func ensure(id: String) -> Dictionary:
	var base = BASE.new()
	var record = base.load_campaign(id)
	if record.is_empty():
		return fail("Campaign unavailable.")
	var path = base.path_for(id)
	# Do not let an unsupported C2 marker trigger a world migration.
	var marker = SQL.run(path,[SQL.stmt("SELECT value FROM meta WHERE key='gameplay_schema'")],true)
	if not marker.get("ok",false):
		return fail("Cannot inspect gameplay schema.")
	if not marker["results"][0].is_empty():
		return {"ok":true,"migrated":false} if marker["results"][0][0]["value"]==VERSION else fail("Unsupported gameplay schema.")
	# World migration has its own verified backup. C2 never proceeds on failure.
	var world = WORLD.new().ensure(id)
	if not world.get("ok",false):
		return world
	record=base.load_campaign(id)
	if record.is_empty():
		return fail("Campaign changed during migration.")
	var metadata = base.loaded_metadata
	var read = SQL.run(path,[SQL.stmt("BEGIN"),SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),SQL.stmt("SELECT campaign_id,revision,pending_turn_id FROM world_state"),SQL.stmt("SELECT id,kind,payload FROM actors ORDER BY id"),SQL.stmt("SELECT actor_id,item_id,quantity,payload,typeof(quantity) AS storage_type FROM inventory ORDER BY actor_id,item_id"),SQL.stmt("SELECT id,kind,payload FROM events WHERE kind='campaign_created' ORDER BY id LIMIT 1"),SQL.stmt("COMMIT")],true)
	if not read.get("ok",false):
		return fail("Cannot inspect legacy campaign.")
	var sets: Array = read["results"]
	if sets.size()!=7 or sets[1].size()!=1 or sets[1][0]["value"]!=metadata or sets[2].size()!=1 or sets[2][0]["campaign_id"]!=id or sets[2][0]["pending_turn_id"]!=null:
		return fail("Campaign must be idle to migrate gameplay.")
	var revision = DTO.sql_int(sets[2][0]["revision"])
	if revision==null or revision>=DTO.MAX_INT-1:
		return fail("Unsupported migration revision.")
	var backup = path.trim_suffix(".db")+".pre-gameplay-"+Crypto.new().generate_random_bytes(16).hex_encode()+".bak"
	var copied = SQL.run(path,[SQL.stmt("VACUUM INTO ?",[ProjectSettings.globalize_path(backup)])],true)
	if not copied.get("ok",false):
		return fail("C2 backup failed. No C2 writes.")
	var verified = SQL.run(backup,[SQL.stmt("PRAGMA integrity_check"),SQL.stmt("PRAGMA foreign_key_check"),SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),SQL.stmt("SELECT campaign_id,revision,pending_turn_id FROM world_state"),SQL.stmt("SELECT id,kind,payload FROM actors ORDER BY id"),SQL.stmt("SELECT actor_id,item_id,quantity,payload,typeof(quantity) AS storage_type FROM inventory ORDER BY actor_id,item_id")],true)
	if not verified.get("ok",false) or verified["results"][0].size()!=1 or verified["results"][0][0].get("integrity_check")!="ok" or not verified["results"][1].is_empty() or verified["results"][2]!=sets[1] or verified["results"][3]!=sets[2] or verified["results"][4]!=sets[3] or verified["results"][5]!=sets[4]:
		return fail("Backup did not match the frozen campaign. No C2 writes.")
	var commands: Array = [SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_migration_guard',(SELECT m.value FROM meta m JOIN world_state s ON s.campaign_id=? WHERE m.key='campaign' AND m.value=? AND s.revision=? AND s.pending_turn_id IS NULL AND NOT EXISTS(SELECT 1 FROM meta WHERE key='gameplay_schema')))",[id,metadata,revision])]
	var source = FileAccess.get_file_as_string(SCHEMA)
	if source.is_empty():
		return fail("C2 schema unavailable.")
	for raw in source.split(";"):
		if not raw.strip_edges().is_empty():
			commands.append(SQL.stmt(raw.strip_edges()))
	var catalog = ITEMS.new()
	var definitions: Dictionary = {}
	var by_actor: Dictionary = {}
	var actor_data: Dictionary = {}
	# Exact legacy actor and inventory values rechecked under the write lock,
	# including counts; no concurrent old-code changes silently overwritten.
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_row_guard',(SELECT 'ok' WHERE (SELECT count(*) FROM actors)=CAST(? AS INTEGER) AND (SELECT count(*) FROM inventory)=CAST(? AS INTEGER)))",[sets[3].size(),sets[4].size()]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_row_guard'"))
	for row in sets[3]:
		var data = JSON.parse_string(row["payload"])
		if not data is Dictionary or not DTO.id_valid(row["id"]):
			return fail("Malformed legacy actor. Backup retained.")
		actor_data[row["id"]]=data
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_row_guard',(SELECT 'ok' FROM actors WHERE id=? AND kind=? AND payload=?))",[row["id"],row["kind"],row["payload"]]))
		commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_row_guard'"))
	for row in sets[4]:
		var quantity = DTO.sql_int(row["quantity"])
		var payload = JSON.parse_string(row["payload"])
		var item_id = str(row["item_id"])
		if quantity==null or quantity<1 or row["storage_type"]!="integer" or not payload is Dictionary or not DTO.bounded_text(item_id,128):
			return fail("Malformed legacy inventory. Backup retained.")
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('c2_row_guard',(SELECT 'ok' FROM inventory WHERE actor_id=? AND item_id=? AND quantity=CAST(? AS INTEGER) AND typeof(quantity)='integer' AND payload=?))",[row["actor_id"],item_id,quantity,row["payload"]]))
		commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_row_guard'"))
		if not definitions.has(item_id):
			var definition = catalog.legacy_definition(item_id)
			if not catalog.last_error.is_empty():
				return fail(catalog.last_error)
			definitions[item_id]=definition
			commands.append(catalog.insert_definition(definition))
		var instance_id = Crypto.new().generate_random_bytes(16).hex_encode()
		var charges = payload.get("charges")
		if not DTO.whole(charges):
			charges=null
		var condition = payload.get("condition","unknown")
		if not condition in ["unknown","intact","worn","damaged","broken"]:
			condition="unknown"
		var attunement = payload.get("attunement_status","unknown")
		if not attunement in ["unknown","not_required","unattuned","attuned"]:
			attunement="unknown"
		commands.append(SQL.stmt("INSERT INTO item_instances(id,definition_id,actor_id,quantity,charges,condition,attunement,provenance) VALUES(?,?,?,?,?,?,?,?)",[instance_id,item_id,row["actor_id"],quantity,charges,condition,attunement,JSON.stringify({"kind":"legacy_stack","payload":payload})]))
		if not by_actor.has(row["actor_id"]):
			by_actor[row["actor_id"]]={}
		by_actor[row["actor_id"]][item_id]={"id":instance_id,"payload":payload}
	for actor_id in by_actor:
		var gear = actor_data[actor_id].get("equipment",{})
		if not gear is Dictionary or not gear.get("weapon_ids",[]) is Array:
			return fail("Malformed legacy equipment. Backup retained.")
		var owned: Dictionary = by_actor[actor_id]
		var claimed: Array = gear.get("weapon_ids",[]).duplicate()
		for pair in [["armor_id","body","worn"],["shield_id","shield","one_handed"]]:
			var item = str(gear.get(pair[0],""))
			if item.is_empty():
				continue
			if not owned.has(item):
				return fail("Legacy equipped item not owned. Backup retained.")
			claimed.append(item)
			var options = catalog.physical_options(definitions[item])
			var compatible = options.any(func(opt): return opt["slot"]==pair[1] and opt["grip"]==pair[2])
			if compatible and owned[item]["payload"].get("equipped",true)==true:
				commands.append(SQL.stmt("INSERT INTO equipment_assignments(actor_id,slot,instance_id,grip) VALUES(?,?,?,?)",[actor_id,pair[1],owned[item]["id"],pair[2]]))
			else:
				commands.append(SQL.stmt("INSERT INTO equipment_review(actor_id,instance_id,reason) VALUES(?,?,?)",[actor_id,owned[item]["id"],"Legacy slot/category/flag requires reconciliation."]))
		for item in gear.get("weapon_ids",[]):
			if not owned.has(item):
				return fail("Legacy weapon not owned. Backup retained.")
			# The legacy ordered weapon list did not establish specific hands.
			commands.append(SQL.stmt("INSERT OR IGNORE INTO equipment_review(actor_id,instance_id,reason) VALUES(?,?,?)",[actor_id,owned[item]["id"],"Legacy equipped weapon has no established hand assignment."]))
		for item in owned:
			if owned[item]["payload"].get("equipped",false)==true and not item in claimed:
				commands.append(SQL.stmt("INSERT OR IGNORE INTO equipment_review(actor_id,instance_id,reason) VALUES(?,?,?)",[actor_id,owned[item]["id"],"Legacy equipped flag has no established slot."]))
	commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('gameplay_schema',?)",[VERSION]))
	commands.append(SQL.stmt("UPDATE world_state SET revision=revision+1 WHERE campaign_id=?",[id]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='c2_migration_guard'"))
	var result = SQL.run(path,commands)
	return {"ok":true,"migrated":true,"backup":backup} if result.get("ok",false) else fail("C2 migration rolled back. Backup retained.")
