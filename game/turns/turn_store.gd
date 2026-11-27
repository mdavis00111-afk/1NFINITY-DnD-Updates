extends RefCounted
## Engine-only turn persistence. No dice, no provider, no AI SQL.
const SQL = preload("res://systems/sqlite.gd")
const BASE = preload("res://campaigns/campaign_store.gd")
const DTO = preload("res://world/world_dto.gd")
const MIGRATION = preload("res://world/world_migration.gd")

func failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

# B2 freezes this token BEFORE resolving. It stays local, never enters an AI packet.
func snapshot(id: String) -> Dictionary:
	var base = BASE.new()
	var record = base.load_campaign(id)
	if record.is_empty() or not DTO.id_valid(record.get("actor_id")):
		return failure("Campaign or actor unavailable.")
	var raw = base.loaded_metadata
	var result = SQL.run(base.path_for(id),[
		SQL.stmt("BEGIN"),
		SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),
		SQL.stmt("SELECT value FROM meta WHERE key='world_schema'"),
		SQL.stmt("SELECT campaign_id,revision,turn_number,pending_turn_id,elapsed_seconds FROM world_state"),
		SQL.stmt("SELECT id,location_id,payload,master_character_id FROM actors WHERE id=? AND kind='player'",[record["actor_id"]]),
		SQL.stmt("COMMIT")
	],true)
	if not result.get("ok",false):
		return failure("World state unavailable. Run migration first.")
	var sets: Array = result["results"]
	if sets.size()!=6 or sets[1].size()!=1 or sets[1][0]["value"]!=raw or sets[2].size()!=1 or sets[2][0]["value"]!=MIGRATION.VERSION or sets[3].size()!=1 or sets[4].size()!=1:
		return failure("Campaign changed or world state incomplete.")
	var state = sets[3][0]
	var actor = sets[4][0]
	var revision = DTO.sql_int(state["revision"])
	var turn = DTO.sql_int(state["turn_number"])
	var elapsed = DTO.sql_int(state["elapsed_seconds"])
	if state["campaign_id"]!=id or revision==null or turn==null or record.get("turn")!=turn or (state["elapsed_seconds"]!=null and elapsed==null):
		return failure("Campaign revision or turn mismatch.")
	if not DTO.id_valid(actor["location_id"]) or actor["location_id"]!=record.get("location_id") or actor["master_character_id"]!=record.get("master_character_id") or (state["pending_turn_id"]!=null and not DTO.id_valid(state["pending_turn_id"])):
		return failure("Campaign actor identity invalid.")
	var payload = JSON.parse_string(actor["payload"])
	if not payload is Dictionary or payload.get("id")!=actor["id"] or payload.get("master_character_id")!=actor["master_character_id"] or payload.get("location_id")!=actor["location_id"]:
		return failure("Campaign actor payload identity invalid.")
	return {"ok":true,"campaign_id":id,"actor_id":actor["id"],"location_id":actor["location_id"],"revision":revision,"turn":turn,"pending_turn_id":state["pending_turn_id"],"elapsed_seconds":elapsed,"metadata":raw,"actor_payload":actor["payload"],"campaign":record,"actor":payload}

# Read before rolling/retrying. A committed logical ID is never rolled again.
func receipt_by_id(id: String, turn_id: String) -> Dictionary:
	if not DTO.id_valid(turn_id):
		return failure("Invalid turn identity.")
	var base = BASE.new()
	var record = base.load_campaign(id)
	if record.is_empty():
		return failure("Campaign unavailable.")
	var result = SQL.run(base.path_for(id),[SQL.stmt("BEGIN"),SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),SQL.stmt("SELECT campaign_id FROM world_state"),SQL.stmt("SELECT r.payload,n.event_id AS narration_event_id FROM turn_receipts r LEFT JOIN turn_narrations n ON n.turn_id=r.turn_id WHERE r.turn_id=? AND r.actor_id=?",[turn_id,record["actor_id"]]),SQL.stmt("COMMIT")],true)
	if not result.get("ok",false):
		return failure("Receipt lookup failed.")
	var sets: Array = result["results"]
	if sets.size()!=5 or sets[1].size()!=1 or sets[1][0]["value"]!=base.loaded_metadata or sets[2].size()!=1 or sets[2][0]["campaign_id"]!=id:
		return failure("Receipt lookup snapshot changed. Retry lookup, not mechanics.")
	if sets[3].is_empty():
		return {"ok":true,"found":false}
	var row = sets[3][0]
	var receipt = JSON.parse_string(row["payload"])
	if not DTO.receipt_valid(receipt) or receipt["campaign_id"]!=id or receipt["actor_id"]!=record["actor_id"] or receipt["turn_id"]!=turn_id:
		return failure("Stored receipt invalid.")
	return {"ok":true,"found":true,"receipt":receipt,"narration_event_id":DTO.sql_int(row["narration_event_id"])}

# Guard inserts NULL on mismatch, violating meta.value NOT NULL. The entire
# transaction rolls back, including receipts, movement, metadata and events.
func guard(token: Dictionary) -> Dictionary:
	return SQL.stmt("INSERT INTO meta(key,value) VALUES('turn_write_guard',(SELECT m.value FROM meta m JOIN world_state s ON s.campaign_id=? JOIN actors a ON a.id=? WHERE m.key='campaign' AND m.value=? AND s.revision=? AND s.turn_number=? AND s.pending_turn_id IS ? AND a.kind='player' AND a.location_id=? AND a.payload=?))",[token["campaign_id"],token["actor_id"],token["metadata"],token["revision"],token["turn"],token["pending_turn_id"],token["location_id"],token["actor_payload"]])

func matching_token(a: Dictionary,b: Dictionary) -> bool:
	for key in ["campaign_id","actor_id","metadata","actor_payload","revision","turn","pending_turn_id","location_id","elapsed_seconds"]:
		if not a.has(key) or a[key]!=b.get(key):
			return false
	return true

# Only an engine-validated receipt enters this API. B1 rejects unsupported effects.
# No generic patch or caller-supplied SQL. The deterministic resolver is B2.
func commit_receipt(id: String, token: Dictionary, receipt: Dictionary) -> Dictionary:
	if not DTO.receipt_valid(receipt) or receipt["campaign_id"]!=id:
		return failure("Invalid receipt envelope or unsupported effect.")
	var prior = receipt_by_id(id,receipt["turn_id"])
	if not prior.get("ok",false):
		return prior
	if prior.get("found",false):
		if prior["receipt"]==receipt:
			return {"ok":true,"replayed":true,"receipt":prior["receipt"]}
		return failure("Logical turn already committed with different receipt.")
	var current = snapshot(id)
	if not current.get("ok",false) or not matching_token(token,current):
		return failure("Stale turn snapshot.")
	if current["pending_turn_id"]!=null or receipt["actor_id"]!=current["actor_id"] or receipt["prior_revision"]!=current["revision"] or receipt["resulting_turn"]!=current["turn"]+1:
		return failure("Pending narration or turn identity mismatch.")
	var commands: Array = [guard(current)]
	var turn_id = str(receipt["turn_id"])
	var turn = int(receipt["resulting_turn"])
	var actor_id = str(current["actor_id"])
	var record: Dictionary = current["campaign"].duplicate(true)
	var actor: Dictionary = current["actor"].duplicate(true)
	var location_id = str(current["location_id"])
	var elapsed = current["elapsed_seconds"]
	commands.append(SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'mechanical_receipt',?)",[turn,"Unspecified",JSON.stringify({"turn_id":turn_id,"text":"Mechanical receipt committed. Narration pending."})]))
	commands.append(SQL.stmt("INSERT INTO turn_receipts(turn_id,actor_id,prior_revision,next_revision,turn_number,event_id,payload) VALUES(?,?,?,?,?,last_insert_rowid(),?)",[turn_id,actor_id,int(receipt["prior_revision"]),int(receipt["next_revision"]),turn,JSON.stringify(receipt)]))
	if not receipt["effects"].is_empty():
		var effect = receipt["effects"][0]
		for i in range(effect["segments"].size()):
			var segment = effect["segments"][i]
			if segment["from_id"]!=location_id:
				return failure("Movement does not begin at the committed position.")
			# A scalar subquery returning NULL forces rollback on nonexistent
			# locations or a route that does not connect these endpoints.
			commands.append(SQL.stmt("INSERT INTO movement_history(turn_id,seq,actor_id,from_id,to_id,route_id,distance_miles,elapsed_seconds,precision) VALUES(?,?,?,(SELECT location_id FROM world_places WHERE location_id=?),(SELECT location_id FROM world_places WHERE location_id=? AND (? IS NULL OR EXISTS(SELECT 1 FROM world_routes WHERE id=? AND ((from_id=? AND to_id=?) OR (from_id=? AND to_id=?))))),?,?,?,?)",[turn_id,i,actor_id,segment["from_id"],segment["to_id"],segment["route_id"],segment["route_id"],segment["from_id"],segment["to_id"],segment["to_id"],segment["from_id"],segment["route_id"],segment["distance_miles"],segment["elapsed_seconds"],segment["precision"]]))
			var points: Array = segment["points"]
			if not points.is_empty():
				# Geometry must start/end at established positions; never infer a
				# straight line or copy proposed road geometry into actual travel.
				var first = points.front()
				var last = points.back()
				commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('movement_geometry_guard',(SELECT 'ok' FROM locations a JOIN world_places wa ON wa.location_id=a.id JOIN locations b ON b.id=? JOIN world_places wb ON wb.location_id=b.id WHERE a.id=? AND wa.precision IN ('approximate','surveyed') AND wb.precision IN ('approximate','surveyed') AND a.x=CAST(? AS REAL) AND a.y=CAST(? AS REAL) AND b.x=CAST(? AS REAL) AND b.y=CAST(? AS REAL)))",[segment["to_id"],segment["from_id"],first["x"],first["y"],last["x"],last["y"]]))
				for p in range(points.size()):
					commands.append(SQL.stmt("INSERT INTO movement_points(turn_id,segment_seq,seq,x,y) VALUES(?,?,?,?,?)",[turn_id,i,p,points[p]["x"],points[p]["y"]]))
				commands.append(SQL.stmt("DELETE FROM meta WHERE key='movement_geometry_guard'"))
			location_id=segment["to_id"]
			# Actual arrival is evidence of visit. Preserve surveyed and first discovery.
			commands.append(SQL.stmt("UPDATE world_discovery SET status=CASE WHEN status='surveyed' THEN status ELSE 'visited' END,visibility='player',first_event_id=COALESCE(first_event_id,(SELECT event_id FROM turn_receipts WHERE turn_id=?)),last_visit_event_id=(SELECT event_id FROM turn_receipts WHERE turn_id=?) WHERE location_id=?",[turn_id,turn_id,location_id]))
			commands.append(SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility,first_event_id,last_visit_event_id) SELECT ?,?,'visited','player',event_id,event_id FROM turn_receipts WHERE turn_id=? AND NOT EXISTS(SELECT 1 FROM world_discovery WHERE location_id=?)",[Crypto.new().generate_random_bytes(16).hex_encode(),location_id,turn_id,location_id]))
			if elapsed!=null:
				if segment["elapsed_seconds"]==null:
					elapsed=null
				else:
					elapsed+=int(segment["elapsed_seconds"])
					if not DTO.whole(elapsed):
						return failure("Elapsed time outside supported range.")
		actor["location_id"]=location_id
		record["location_id"]=location_id
		commands.append(SQL.stmt("UPDATE actors SET location_id=?,payload=? WHERE id=?",[location_id,JSON.stringify(actor),actor_id]))
	record["turn"]=turn
	record["updated_at"]=Time.get_datetime_string_from_system(true)
	commands.append(SQL.stmt("UPDATE meta SET value=? WHERE key='campaign'",[JSON.stringify(record)]))
	commands.append(SQL.stmt("UPDATE world_state SET revision=?,turn_number=?,pending_turn_id=?,elapsed_seconds=? WHERE campaign_id=?",[int(receipt["next_revision"]),turn,turn_id,elapsed,id]))
	commands.append(SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'"))
	var result = SQL.run(BASE.new().path_for(id),commands)
	if not result.get("ok",false):
		# A lost acknowledgment may conceal a successful commit. Never reroll.
		var persisted = receipt_by_id(id,turn_id)
		if persisted.get("found",false) and persisted["receipt"]==receipt:
			return {"ok":true,"replayed":true,"receipt":persisted["receipt"]}
		return failure("Receipt transaction rejected or unconfirmed. Look up turn ID before retry.")
	return {"ok":true,"replayed":false,"receipt":receipt}

# Text-only accepted narration boundary for B3. B4 will extend this transaction
# with validated descriptive fact commands, never a separate AI write.
func commit_narration(id: String, turn_id: String, revision: int, text: String) -> Dictionary:
	if not DTO.id_valid(turn_id) or not DTO.whole(revision,1,DTO.MAX_INT-1) or not DTO.bounded_text(text,12000):
		return failure("Invalid accepted narration.")
	var state = snapshot(id)
	if not state.get("ok",false) or state["revision"]!=revision or state["pending_turn_id"]!=turn_id:
		return failure("Narration is stale, already committed or unavailable.")
	var commands = [guard(state),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'narration',?)",[state["turn"],"Unspecified",JSON.stringify({"turn_id":turn_id,"text":text})]),SQL.stmt("INSERT INTO turn_narrations(turn_id,event_id,revision) VALUES(?,last_insert_rowid(),?)",[turn_id,revision+1]),SQL.stmt("UPDATE world_state SET revision=?,pending_turn_id=NULL WHERE campaign_id=?",[revision+1,id]),SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'")]
	var result = SQL.run(BASE.new().path_for(id),commands)
	return {"ok":true,"revision":revision+1} if result.get("ok",false) else failure("Narration transaction rejected. Reload receipt before retry.")
