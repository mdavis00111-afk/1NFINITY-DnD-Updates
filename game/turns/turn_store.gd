extends RefCounted
## Engine-only turn persistence. No dice, no provider, no AI SQL.
const SQL = preload("res://systems/sqlite.gd")
const BASE = preload("res://campaigns/campaign_store.gd")
const DTO = preload("res://world/world_dto.gd")
const MIGRATION = preload("res://world/world_migration.gd")
const RAW = preload("res://turns/raw_mechanics.gd")
const CAT = preload("res://rules/catalog.gd")

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
		SQL.stmt("SELECT item_id,quantity,payload FROM inventory WHERE actor_id=? ORDER BY item_id",[record["actor_id"]]),
		SQL.stmt("COMMIT")
	],true)
	if not result.get("ok",false):
		return failure("World state unavailable. Run migration first.")
	var sets: Array = result["results"]
	if sets.size()!=7 or sets[1].size()!=1 or sets[1][0]["value"]!=raw or sets[2].size()!=1 or sets[2][0]["value"]!=MIGRATION.VERSION or sets[3].size()!=1 or sets[4].size()!=1:
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
	var inventory: Array = []
	for row in sets[5]:
		var quantity = DTO.sql_int(row["quantity"])
		var item = JSON.parse_string(row["payload"])
		if quantity==null or quantity<1 or not item is Dictionary or not DTO.bounded_text(row["item_id"],100):
			return failure("Invalid normalized inventory row.")
		item["item_id"]=row["item_id"]
		item["quantity"]=quantity
		inventory.append(item)
	return {"ok":true,"campaign_id":id,"actor_id":actor["id"],"location_id":actor["location_id"],"revision":revision,"turn":turn,"pending_turn_id":state["pending_turn_id"],"elapsed_seconds":elapsed,"metadata":raw,"actor_payload":actor["payload"],"campaign":record,"actor":payload,"inventory":inventory,"inventory_rows":sets[5]}

# Read before rolling/retrying. A committed logical ID is never rolled again.
func receipt_by_id(id: String, turn_id: String) -> Dictionary:
	if not DTO.id_valid(turn_id):
		return failure("Invalid turn identity.")
	var base = BASE.new()
	var record = base.load_campaign(id)
	if record.is_empty():
		return failure("Campaign unavailable.")
	var result = SQL.run(base.path_for(id),[SQL.stmt("BEGIN"),SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),SQL.stmt("SELECT campaign_id FROM world_state"),SQL.stmt("SELECT r.payload,r.prior_revision,r.next_revision,r.turn_number,e.payload AS event_payload,e.kind AS event_kind,e.turn AS event_turn,n.event_id AS narration_event_id,n.revision AS narration_revision,ne.kind AS narration_kind,ne.turn AS narration_turn,ne.payload AS narration_payload FROM turn_receipts r JOIN events e ON e.id=r.event_id LEFT JOIN turn_narrations n ON n.turn_id=r.turn_id LEFT JOIN events ne ON ne.id=n.event_id WHERE r.turn_id=? AND r.actor_id=?",[turn_id,record["actor_id"]]),SQL.stmt("COMMIT")],true)
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
	# JSON and relational receipt provenance must agree. Never treat a corrupt
	# record as a successful acknowledgement or permit a new roll on lookup failure.
	if DTO.sql_int(row["prior_revision"])!=receipt["prior_revision"] or DTO.sql_int(row["next_revision"])!=receipt["next_revision"] or DTO.sql_int(row["turn_number"])!=receipt["resulting_turn"] or row["event_kind"]!="mechanical_receipt" or DTO.sql_int(row["event_turn"])!=receipt["resulting_turn"]:
		return failure("Stored receipt revision or event provenance mismatch.")
	var event = JSON.parse_string(row["event_payload"])
	var modern = not receipt["effects"].is_empty() and receipt["effects"].back().get("kind")=="time"
	if not event is Dictionary or (event.has("turn_id") and event["turn_id"]!=turn_id) or (modern and event.get("turn_id")!=turn_id):
		return failure("Stored receipt event identity mismatch.")
	var narration_id = DTO.sql_int(row["narration_event_id"])
	if row["narration_event_id"]!=null:
		var narrated = JSON.parse_string(str(row["narration_payload"]))
		if narration_id==null or DTO.sql_int(row["narration_revision"])!=receipt["next_revision"]+1 or row["narration_kind"]!="narration" or DTO.sql_int(row["narration_turn"])!=receipt["resulting_turn"] or not narrated is Dictionary or (narrated.has("turn_id") and narrated["turn_id"]!=turn_id) or (modern and narrated.get("turn_id")!=turn_id):
			return failure("Stored narration provenance mismatch.")
	var player_text = ""
	if event.get("turn_id")==turn_id and DTO.bounded_text(event.get("player_text"),2000):
		player_text=event["player_text"]
	return {"ok":true,"found":true,"receipt":receipt,"narration_event_id":narration_id,"player_text":player_text}

# Guard inserts NULL on mismatch, violating meta.value NOT NULL. The entire
# transaction rolls back, including receipts, movement, metadata and events.
func guard(token: Dictionary) -> Dictionary:
	return SQL.stmt("INSERT INTO meta(key,value) VALUES('turn_write_guard',(SELECT m.value FROM meta m JOIN world_state s ON s.campaign_id=? JOIN actors a ON a.id=? WHERE m.key='campaign' AND m.value=? AND s.revision=? AND s.turn_number=? AND s.pending_turn_id IS ? AND s.elapsed_seconds IS ? AND a.kind='player' AND a.location_id=? AND a.payload=?))",[token["campaign_id"],token["actor_id"],token["metadata"],token["revision"],token["turn"],token["pending_turn_id"],token["elapsed_seconds"],token["location_id"],token["actor_payload"]])

func matching_token(a: Dictionary,b: Dictionary) -> bool:
	for key in ["campaign_id","actor_id","metadata","actor_payload","revision","turn","pending_turn_id","location_id","elapsed_seconds","inventory_rows"]:
		if not a.has(key) or a[key]!=b.get(key):
			return false
	return true

# Read known canonical route and previous walking time; never infer distance
# from coordinates. Geometry is copied only after actual traversal resolves.
func route_context(id: String, token: Dictionary, route_id: String, destination: String) -> Dictionary:
	if not DTO.id_valid(id) or id!=token.get("campaign_id") or not DTO.id_valid(route_id) or not DTO.id_valid(destination) or destination==token.get("location_id"):
		return failure("Invalid route intent.")
	var result = SQL.run(BASE.new().path_for(id),[
		SQL.stmt("BEGIN"),
		SQL.stmt("SELECT campaign_id,revision,turn_number FROM world_state"),
		SQL.stmt("SELECT r.id,r.from_id,r.to_id,r.kind,r.precision,r.distance_miles,d.status AS route_status,fa.precision AS from_precision,fb.precision AS to_precision,a.x AS from_x,a.y AS from_y,b.x AS to_x,b.y AS to_y FROM world_routes r JOIN world_discovery d ON d.route_id=r.id JOIN world_discovery da ON da.location_id=r.from_id JOIN world_discovery db ON db.location_id=r.to_id JOIN world_places fa ON fa.location_id=r.from_id JOIN world_places fb ON fb.location_id=r.to_id JOIN locations a ON a.id=r.from_id JOIN locations b ON b.id=r.to_id WHERE r.id=? AND ((r.from_id=? AND r.to_id=?) OR (r.to_id=? AND r.from_id=?)) AND d.visibility='player' AND d.status<>'unknown' AND da.visibility='player' AND da.status<>'unknown' AND db.visibility='player' AND db.status<>'unknown'",[route_id,token["location_id"],destination,token["location_id"],destination]),
		SQL.stmt("SELECT seq,x,y FROM route_points WHERE route_id=? ORDER BY seq",[route_id]),
		SQL.stmt("SELECT COALESCE(sum(elapsed_seconds),0) AS walked,count(*)-count(elapsed_seconds) AS unknown_time,COALESCE(sum(CASE WHEN route_id=? THEN 1 ELSE 0 END),0) AS prior_traversals FROM movement_history WHERE actor_id=?",[route_id,token["actor_id"]]),
		SQL.stmt("SELECT count(*) AS unresolved FROM encounters WHERE status NOT IN ('resolved','completed','closed','defeated')"),
		SQL.stmt("COMMIT")
	],true)
	if not result.get("ok",false):
		return failure("Route context unavailable.")
	var sets: Array = result["results"]
	if sets.size()!=7 or sets[1].size()!=1 or sets[2].size()!=1 or sets[4].size()!=1 or sets[5].size()!=1 or sets[1][0]["campaign_id"]!=id or DTO.sql_int(sets[1][0]["revision"])!=token["revision"] or DTO.sql_int(sets[1][0]["turn_number"])!=token["turn"]:
		return failure("Route is unknown, hidden, not connected, or stale.")
	if DTO.sql_int(sets[5][0]["unresolved"])!=0:
		return failure("An unresolved encounter requires ordinary adjudication before any travel.")
	var row = sets[2][0]
	var distance = DTO.sql_number(row["distance_miles"])
	var walked = DTO.sql_int(sets[4][0]["walked"])
	var traversals = DTO.sql_int(sets[4][0]["prior_traversals"])
	if not row["kind"] in ["road","track","path","trail"] or distance==null or distance<=0 or walked==null or traversals==null or DTO.sql_int(sets[4][0]["unknown_time"])!=0:
		return failure("Route distance, terrain type or walking history requires adjudication.")
	var points: Array = []
	for i in range(sets[3].size()):
		var point = sets[3][i]
		var x = DTO.sql_number(point["x"])
		var y = DTO.sql_number(point["y"])
		if DTO.sql_int(point["seq"])!=i or x==null or y==null:
			return failure("Route geometry invalid.")
		points.append({"x":x,"y":y})
	if not DTO.points_valid(points,row["precision"]):
		return failure("Route geometry lacks accepted precision.")
	if not points.is_empty():
		if not DTO.known_position(row["from_precision"]) or not DTO.known_position(row["to_precision"]) or points.front()!= {"x":DTO.sql_number(row["from_x"]),"y":DTO.sql_number(row["from_y"])} or points.back()!= {"x":DTO.sql_number(row["to_x"]),"y":DTO.sql_number(row["to_y"])}:
			return failure("Route geometry does not match its endpoints.")
	if row["from_id"]!=token["location_id"]:
		points.reverse()
	return {"ok":true,"row":row,"point_rows":sets[3],"distance":distance,"walked":walked,"prior_traversals":traversals,"points":points}

func inventory_guards(token: Dictionary) -> Array:
	var commands: Array = [SQL.stmt("INSERT INTO meta(key,value) VALUES('turn_inventory_guard',(SELECT 'ok' WHERE (SELECT count(*) FROM inventory WHERE actor_id=?)=CAST(? AS INTEGER)))",[token["actor_id"],token["inventory_rows"].size()]),SQL.stmt("DELETE FROM meta WHERE key='turn_inventory_guard'")]
	for row in token["inventory_rows"]:
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('turn_inventory_guard',(SELECT 'ok' FROM inventory WHERE actor_id=? AND item_id=? AND quantity=CAST(? AS INTEGER) AND typeof(quantity)='integer' AND payload=?))",[token["actor_id"],row["item_id"],row["quantity"],row["payload"]]))
		commands.append(SQL.stmt("DELETE FROM meta WHERE key='turn_inventory_guard'"))
	return commands

func route_guards(token: Dictionary, route: Dictionary) -> Array:
	var row = route["row"]
	var commands: Array = [SQL.stmt("INSERT INTO meta(key,value) VALUES('turn_route_guard',(SELECT 'ok' FROM world_routes r JOIN world_discovery d ON d.route_id=r.id JOIN world_discovery a ON a.location_id=r.from_id JOIN world_discovery b ON b.location_id=r.to_id WHERE r.id=? AND r.from_id=? AND r.to_id=? AND r.kind=? AND r.precision=? AND r.distance_miles=CAST(? AS REAL) AND d.visibility='player' AND d.status=? AND a.visibility='player' AND a.status<>'unknown' AND b.visibility='player' AND b.status<>'unknown' AND (SELECT count(*) FROM route_points WHERE route_id=r.id)=CAST(? AS INTEGER) AND (SELECT COALESCE(sum(elapsed_seconds),0) FROM movement_history WHERE actor_id=?)=CAST(? AS INTEGER) AND NOT EXISTS(SELECT 1 FROM movement_history WHERE actor_id=? AND elapsed_seconds IS NULL) AND NOT EXISTS(SELECT 1 FROM encounters WHERE status NOT IN ('resolved','completed','closed','defeated')) AND (SELECT count(*) FROM movement_history WHERE actor_id=? AND route_id=r.id)=CAST(? AS INTEGER)))",[row["id"],row["from_id"],row["to_id"],row["kind"],row["precision"],row["distance_miles"],row["route_status"],route["point_rows"].size(),token["actor_id"],route["walked"],token["actor_id"],token["actor_id"],route["prior_traversals"]]),SQL.stmt("DELETE FROM meta WHERE key='turn_route_guard'")]
	for point in route["point_rows"]:
		commands.append(SQL.stmt("INSERT INTO meta(key,value) VALUES('turn_route_guard',(SELECT 'ok' FROM route_points WHERE route_id=? AND seq=CAST(? AS INTEGER) AND x=CAST(? AS REAL) AND y=CAST(? AS REAL)))",[row["id"],point["seq"],point["x"],point["y"]]))
		commands.append(SQL.stmt("DELETE FROM meta WHERE key='turn_route_guard'"))
	return commands

# Engine-only API; strict registered RAW unions, exact state and SQL guards.
# No generic patch or caller-supplied SQL.
func commit_receipt(id: String, token: Dictionary, receipt: Dictionary, player_text: String = "") -> Dictionary:
	if not player_text.is_empty() and not DTO.bounded_text(player_text,2000):
		return failure("Invalid local player action text.")
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
	var cat = CAT.new()
	if not RAW.receipt_valid(receipt,current,cat):
		return failure("Unregistered or inconsistent mechanical receipt.")
	var commands: Array = [guard(current)]
	commands.append_array(inventory_guards(current))
	var action = receipt["results"][0]
	if action["kind"] in ["move","travel"]:
		var route = route_context(id,current,action["route_id"],action["destination_id"])
		if not route.get("ok",false):
			return route
		var segment = receipt["effects"][0]["segments"][0]
		if segment["distance_miles"]!=route["distance"] or segment["precision"]!=route["row"]["precision"] or segment["points"]!=route["points"] or route["walked"]+int(segment["elapsed_seconds"])>RAW.MAX_WALK_SECONDS or (action["fast_travel"] and route["prior_traversals"]==0):
			return failure("Route, walking allowance or fast-travel eligibility changed.")
		commands.append_array(route_guards(current,route))
	var turn_id = str(receipt["turn_id"])
	var turn = int(receipt["resulting_turn"])
	var actor_id = str(current["actor_id"])
	var record: Dictionary = current["campaign"].duplicate(true)
	var actor: Dictionary = current["actor"].duplicate(true)
	var location_id = str(current["location_id"])
	var elapsed = RAW.time_after(receipt["effects"].back(),current)
	var game_time = "Unspecified" if elapsed==null else "Elapsed "+str(elapsed)+" seconds (tracked epoch)"
	commands.append(SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'mechanical_receipt',?)",[turn,game_time,JSON.stringify({"turn_id":turn_id,"text":RAW.summary(receipt),"player_text":player_text})]))
	commands.append(SQL.stmt("INSERT INTO turn_receipts(turn_id,actor_id,prior_revision,next_revision,turn_number,event_id,payload) VALUES(?,?,?,?,?,last_insert_rowid(),?)",[turn_id,actor_id,int(receipt["prior_revision"]),int(receipt["next_revision"]),turn,JSON.stringify(receipt)]))
	if receipt["effects"].size()==2:
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
			commands.append(SQL.stmt("UPDATE world_discovery SET status=CASE WHEN status='surveyed' THEN status ELSE 'visited' END,last_visit_event_id=(SELECT event_id FROM turn_receipts WHERE turn_id=?) WHERE route_id=? AND visibility='player'",[turn_id,segment["route_id"]]))
			# Actual arrival is evidence of visit. Preserve surveyed and first discovery.
			commands.append(SQL.stmt("UPDATE world_discovery SET status=CASE WHEN status='surveyed' THEN status ELSE 'visited' END,visibility='player',first_event_id=COALESCE(first_event_id,(SELECT event_id FROM turn_receipts WHERE turn_id=?)),last_visit_event_id=(SELECT event_id FROM turn_receipts WHERE turn_id=?) WHERE location_id=?",[turn_id,turn_id,location_id]))
			commands.append(SQL.stmt("INSERT INTO world_discovery(id,location_id,status,visibility,first_event_id,last_visit_event_id) SELECT ?,?,'visited','player',event_id,event_id FROM turn_receipts WHERE turn_id=? AND NOT EXISTS(SELECT 1 FROM world_discovery WHERE location_id=?)",[Crypto.new().generate_random_bytes(16).hex_encode(),location_id,turn_id,location_id]))
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
	var game_time = "Unspecified" if state["elapsed_seconds"]==null else "Elapsed "+str(state["elapsed_seconds"])+" seconds (tracked epoch)"
	var commands = [guard(state),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'narration',?)",[state["turn"],game_time,JSON.stringify({"turn_id":turn_id,"text":text})]),SQL.stmt("INSERT INTO turn_narrations(turn_id,event_id,revision) VALUES(?,last_insert_rowid(),?)",[turn_id,revision+1]),SQL.stmt("UPDATE world_state SET revision=?,pending_turn_id=NULL WHERE campaign_id=?",[revision+1,id]),SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'")]
	var result = SQL.run(BASE.new().path_for(id),commands)
	return {"ok":true,"revision":revision+1} if result.get("ok",false) else failure("Narration transaction rejected. Reload receipt before retry.")
