extends RefCounted
## Read models for map renderer and DM. No provider calls or world generation.
const SQL = preload("res://systems/sqlite.gd")
const BASE = preload("res://campaigns/campaign_store.gd")
const DTO = preload("res://world/world_dto.gd")
const TURN = preload("res://turns/turn_store.gd")
const LIMIT = 128
const DM_LIMIT = 24
const VISIBLE = "d.visibility='player' AND d.status<>'unknown'"
const MAP_LOCATIONS = "SELECT l.id,l.name,l.kind,CASE WHEN w.precision IN ('approximate','surveyed') THEN l.x ELSE NULL END AS x,CASE WHEN w.precision IN ('approximate','surveyed') THEN l.y ELSE NULL END AS y,w.precision,w.uncertainty_miles,w.elevation_feet,w.terrain,w.occupancy,w.population,w.asset_id,w.public_description,d.status,d.first_event_id,d.last_visit_event_id,CASE WHEN EXISTS(SELECT 1 FROM world_discovery p WHERE p.location_id=l.parent_id AND p.visibility='player' AND p.status<>'unknown') THEN l.parent_id END AS parent_id,CASE WHEN EXISTS(SELECT 1 FROM world_discovery r WHERE r.region_id=w.region_id AND r.visibility='player' AND r.status<>'unknown') THEN w.region_id END AS region_id FROM locations l JOIN world_places w ON w.location_id=l.id JOIN world_discovery d ON d.location_id=l.id WHERE "+VISIBLE
const MAP_ROUTES = "SELECT r.id,r.from_id,r.to_id,r.name,r.kind,r.precision,r.distance_miles,d.status FROM world_routes r JOIN world_discovery d ON d.route_id=r.id JOIN world_discovery a ON a.location_id=r.from_id JOIN world_discovery b ON b.location_id=r.to_id WHERE "+VISIBLE+" AND a.visibility='player' AND a.status<>'unknown' AND b.visibility='player' AND b.status<>'unknown'"
const MAP_REGIONS = "SELECT r.id,r.name,r.kind,r.precision,r.public_description,d.status FROM terrain_regions r JOIN world_discovery d ON d.region_id=r.id WHERE "+VISIBLE
const MAP_TRAVEL = "SELECT m.turn_id,m.seq,m.from_id,m.to_id,CASE WHEN rd.visibility='player' AND rd.status<>'unknown' THEN m.route_id END AS route_id,m.distance_miles,m.elapsed_seconds,m.precision,t.turn_number FROM movement_history m JOIN turn_receipts t ON t.turn_id=m.turn_id JOIN world_discovery a ON a.location_id=m.from_id JOIN world_discovery b ON b.location_id=m.to_id LEFT JOIN world_discovery rd ON rd.route_id=m.route_id WHERE m.actor_id=? AND a.visibility='player' AND a.status<>'unknown' AND b.visibility='player' AND b.status<>'unknown'"
const DM_PLACES = "SELECT l.id,l.parent_id,l.name,l.kind,CASE WHEN w.precision IN ('approximate','surveyed') THEN l.x END AS x,CASE WHEN w.precision IN ('approximate','surveyed') THEN l.y END AS y,w.precision,w.uncertainty_miles,w.elevation_feet,w.terrain,w.region_id,w.occupancy,w.population,w.description,w.source_event_id,d.status,d.visibility FROM locations l JOIN world_places w ON w.location_id=l.id LEFT JOIN world_discovery d ON d.location_id=l.id"
const DM_RELEVANT = " WHERE l.id=? OR l.id=(SELECT parent_id FROM locations WHERE id=?) OR l.parent_id=? OR l.id IN (SELECT to_id FROM geographic_relationships WHERE from_id=? UNION SELECT from_id FROM geographic_relationships WHERE to_id=? UNION SELECT to_id FROM world_routes WHERE from_id=? UNION SELECT from_id FROM world_routes WHERE to_id=?) OR (w.precision IN ('approximate','surveyed') AND EXISTS(SELECT 1 FROM locations c JOIN world_places cw ON cw.location_id=c.id WHERE c.id=? AND cw.precision IN ('approximate','surveyed') AND abs(l.x-c.x)<=? AND abs(l.y-c.y)<=? AND ((l.x-c.x)*(l.x-c.x)+(l.y-c.y)*(l.y-c.y))<=?))"
const DM_RELATIONS = "SELECT id,from_id,to_id,kind,direction,distance_miles,precision,source_event_id,visibility FROM geographic_relationships WHERE from_id=? OR to_id=? ORDER BY id LIMIT ?"
const DM_ROUTES = "SELECT id,from_id,to_id,name,kind,precision,distance_miles,source_event_id FROM world_routes WHERE from_id=? OR to_id=? ORDER BY id LIMIT ?"

func failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

# The projection holds one read transaction, compares the exact metadata and
# revision from the prior token, and returns no partial data on failure.
func read_sets(token: Dictionary, commands: Array) -> Dictionary:
	var batch: Array = [SQL.stmt("BEGIN"),SQL.stmt("SELECT value FROM meta WHERE key='campaign'"),SQL.stmt("SELECT revision,turn_number,pending_turn_id FROM world_state WHERE campaign_id=?",[token["campaign_id"]])]
	batch.append_array(commands)
	batch.append(SQL.stmt("COMMIT"))
	var result = SQL.run(BASE.new().path_for(token["campaign_id"]),batch,true)
	if not result.get("ok",false):
		return failure("World query failed.")
	var sets: Array = result["results"]
	if sets.size()!=commands.size()+4 or sets[1].size()!=1 or sets[1][0]["value"]!=token["metadata"] or sets[2].size()!=1 or DTO.sql_int(sets[2][0]["revision"])!=token["revision"] or DTO.sql_int(sets[2][0]["turn_number"])!=token["turn"] or sets[2][0]["pending_turn_id"]!=token["pending_turn_id"]:
		return failure("World snapshot changed. Reopen and retry.")
	return {"ok":true,"sets":sets.slice(3,sets.size()-1)}

func typed_rows(rows: Array) -> Array:
	var output: Array = []
	for row in rows:
		var item: Dictionary = row.duplicate(true)
		for key in ["x","y","distance_miles","uncertainty_miles","elevation_feet"]:
			if item.has(key):
				item[key]=DTO.sql_number(item[key])
		for key in ["seq","segment_seq","turn_number","elapsed_seconds","population","first_event_id","last_visit_event_id","source_event_id","event_id","turn"]:
			if item.has(key):
				item[key]=DTO.sql_int(item[key])
		if item.has("x") and (item["x"]==null or item["y"]==null):
			item["x"]=null
			item["y"]=null
			if item.has("precision") and DTO.known_position(str(item["precision"])):
				item["precision"]="unknown"
				if item.has("uncertainty_miles"):
					item["uncertainty_miles"]=null
		output.append(item)
	return output

# Player-safe pages, no raw payloads, private notes, undiscovered IDs or coordinates.
# Each geometry list is tied to the corresponding page and complete for that page.
func map_view(id: String, page: int = 0, limit: int = LIMIT) -> Dictionary:
	if page<0 or page>100000 or limit<1 or limit>LIMIT:
		return failure("Invalid map page.")
	var token = TURN.new().snapshot(id)
	if not token.get("ok",false):
		return token
	var offset = page*limit
	var places_page = MAP_LOCATIONS+" ORDER BY l.name COLLATE NOCASE,l.id LIMIT ? OFFSET ?"
	var routes_page = MAP_ROUTES+" ORDER BY r.id LIMIT ? OFFSET ?"
	var regions_page = MAP_REGIONS+" ORDER BY r.id LIMIT ? OFFSET ?"
	var travel_page = MAP_TRAVEL+" ORDER BY t.turn_number DESC,m.seq DESC LIMIT ? OFFSET ?"
	var result = read_sets(token,[
		SQL.stmt(places_page,[limit,offset]),
		SQL.stmt("SELECT a.location_id,a.alias FROM location_aliases a JOIN ("+places_page+") p ON p.id=a.location_id WHERE a.visibility='player' ORDER BY a.location_id,a.alias LIMIT ?",[limit,offset,limit*8]),
		SQL.stmt("SELECT g.id,g.from_id,g.to_id,g.kind,g.direction,g.distance_miles,g.precision FROM geographic_relationships g JOIN world_discovery a ON a.location_id=g.from_id JOIN world_discovery b ON b.location_id=g.to_id WHERE g.visibility='player' AND a.visibility='player' AND a.status<>'unknown' AND b.visibility='player' AND b.status<>'unknown' ORDER BY g.id LIMIT ? OFFSET ?",[limit,offset]),
		SQL.stmt(routes_page,[limit,offset]),
		SQL.stmt("SELECT p.route_id,p.seq,p.x,p.y FROM route_points p JOIN ("+routes_page+") r ON r.id=p.route_id WHERE r.precision IN ('approximate','surveyed') ORDER BY p.route_id,p.seq",[limit,offset]),
		SQL.stmt(regions_page,[limit,offset]),
		SQL.stmt("SELECT p.region_id,p.seq,p.x,p.y FROM terrain_points p JOIN ("+regions_page+") r ON r.id=p.region_id WHERE r.precision IN ('approximate','surveyed') ORDER BY p.region_id,p.seq",[limit,offset]),
		SQL.stmt(travel_page,[token["actor_id"],limit,offset]),
		SQL.stmt("SELECT p.turn_id,p.segment_seq,p.seq,p.x,p.y FROM movement_points p JOIN ("+travel_page+") m ON m.turn_id=p.turn_id AND m.seq=p.segment_seq WHERE m.precision IN ('approximate','surveyed') ORDER BY m.turn_number,m.seq,p.seq",[token["actor_id"],limit,offset]),
		SQL.stmt("SELECT n.id,n.location_id,n.text,n.created_at FROM world_annotations n JOIN world_discovery d ON d.location_id=n.location_id WHERE n.actor_id=? AND "+VISIBLE+" ORDER BY n.id LIMIT ? OFFSET ?",[token["actor_id"],limit,offset]),
		SQL.stmt(MAP_LOCATIONS+" AND l.id=?",[token["location_id"]])
	])
	if not result.get("ok",false):
		return result
	var sets: Array = result["sets"]
	var party = typed_rows(sets[10])
	# No manufactured point: party location can be known by name only.
	return {"ok":true,"schema_version":DTO.VERSION,"campaign_id":id,"world_id":id,"revision":token["revision"],"page":page,"limit":limit,"distance_unit":"mile","x_axis":"east","y_axis":"north","locations":typed_rows(sets[0]),"aliases":sets[1],"relationships":typed_rows(sets[2]),"routes":typed_rows(sets[3]),"route_points":typed_rows(sets[4]),"terrain_regions":sets[5],"terrain_points":typed_rows(sets[6]),"travel":typed_rows(sets[7]),"travel_points":typed_rows(sets[8]),"annotations":sets[9],"party_location":party[0] if not party.is_empty() else null}

# Separate private DM read model. Only current, connected or geographically
# nearby places; no whole-campaign dump. Distances are not inferred.
func dm_geography(id: String, radius_miles: float = 25.0) -> Dictionary:
	if not DTO.number(radius_miles,0,250):
		return failure("Invalid DM context radius.")
	var token = TURN.new().snapshot(id)
	if not token.get("ok",false):
		return token
	var at = token["location_id"]
	var relevant = DM_PLACES+DM_RELEVANT+" ORDER BY CASE WHEN l.id=? THEN 0 ELSE 1 END,l.id LIMIT ?"
	var args = [at,at,at,at,at,at,at,at,radius_miles,radius_miles,radius_miles*radius_miles,at,DM_LIMIT]
	var result = read_sets(token,[
		SQL.stmt(relevant,args),
		SQL.stmt("SELECT a.location_id,a.alias,a.visibility,a.source_event_id FROM location_aliases a JOIN ("+relevant+") p ON p.id=a.location_id ORDER BY a.location_id,a.alias LIMIT ?",args+[DM_LIMIT*4]),
		SQL.stmt(DM_RELATIONS,[at,at,DM_LIMIT]),
		SQL.stmt(DM_ROUTES,[at,at,DM_LIMIT]),
		SQL.stmt("SELECT p.route_id,p.seq,p.x,p.y FROM route_points p JOIN ("+DM_ROUTES+") r ON r.id=p.route_id WHERE r.precision IN ('approximate','surveyed') ORDER BY p.route_id,p.seq",[at,at,DM_LIMIT]),
		SQL.stmt("SELECT r.id,r.parent_id,r.name,r.kind,r.precision,r.description,r.source_event_id FROM terrain_regions r WHERE r.id=(SELECT region_id FROM world_places WHERE location_id=?) ORDER BY r.id LIMIT 1",[at]),
		SQL.stmt("SELECT id,kind,substr(payload,1,4000) AS payload FROM actors WHERE location_id=? AND kind<>'player' ORDER BY id LIMIT ?",[at,DM_LIMIT]),
		SQL.stmt("SELECT q.id,q.status,substr(q.payload,1,4000) AS payload FROM quests q JOIN world_links w ON w.quest_id=q.id WHERE w.location_id=? ORDER BY q.id LIMIT ?",[at,DM_LIMIT]),
		SQL.stmt("SELECT id AS event_id,turn,kind,substr(payload,1,4000) AS payload FROM events WHERE kind IN ('campaign_created','narration','mechanical_receipt') ORDER BY id DESC LIMIT 12"),
		SQL.stmt("SELECT m.turn_id,m.seq,m.from_id,m.to_id,m.route_id,m.distance_miles,m.elapsed_seconds,m.precision,t.turn_number FROM movement_history m JOIN turn_receipts t ON t.turn_id=m.turn_id WHERE m.actor_id=? ORDER BY t.turn_number DESC,m.seq DESC LIMIT ?",[token["actor_id"],DM_LIMIT]),
		SQL.stmt("SELECT a.id,a.status,a.subject_id,substr(a.detail,1,1000) AS detail,a.source_event_id FROM geography_audit a WHERE a.status IN ('conflict','deferred') AND (a.subject_id=? OR a.subject_id IN (SELECT to_id FROM geographic_relationships WHERE from_id=? UNION SELECT from_id FROM geographic_relationships WHERE to_id=?)) ORDER BY a.revision DESC,a.id LIMIT ?",[at,at,at,DM_LIMIT]),
		SQL.stmt("SELECT substr(payload,1,6000) AS payload FROM locations WHERE id=?",[at])
	])
	if not result.get("ok",false):
		return result
	var sets: Array = result["sets"]
	var local_facts: Array = []
	# Legacy opening payload is campaign-local. Only its bounded descriptive facts
	# are read; malformed/truncated JSON is ignored rather than guessed.
	if not sets[11].is_empty():
		var payload = JSON.parse_string(sets[11][0]["payload"])
		if payload is Dictionary and payload.get("world_facts") is Array:
			for fact in payload["world_facts"].slice(0,16):
				if DTO.bounded_text(fact,500):
					local_facts.append(fact)
	var output = {"ok":true,"schema_version":DTO.VERSION,"campaign_id":id,"world_id":id,"actor_id":token["actor_id"],"revision":token["revision"],"current_location_id":at,"distance_unit":"mile","locations":typed_rows(sets[0]),"aliases":sets[1],"relationships":typed_rows(sets[2]),"routes":typed_rows(sets[3]),"route_points":typed_rows(sets[4]),"region":typed_rows(sets[5]),"local_npcs":sets[6],"local_quests":sets[7],"recent_events":typed_rows(sets[8]),"recent_travel":typed_rows(sets[9]),"unresolved":typed_rows(sets[10]),"local_facts":local_facts}
	# A hard packet size cap prevents unusually long stored text from leaking a
	# whole campaign. Caller can request narrower context if this fails.
	if JSON.stringify(output).length()>100000:
		return failure("DM geography context exceeds its size budget.")
	return output

func add_annotation(id: String, location_id: String, text: String) -> Dictionary:
	if not DTO.id_valid(location_id) or not DTO.bounded_text(text,1000):
		return failure("Invalid annotation.")
	var token = TURN.new().snapshot(id)
	if not token.get("ok",false):
		return token
	var annotation_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var commands = [TURN.new().guard(token),SQL.stmt("INSERT INTO world_annotations(id,location_id,actor_id,text,created_at) VALUES(?,(SELECT location_id FROM world_discovery WHERE location_id=? AND visibility='player' AND status<>'unknown'),?,?,?)",[annotation_id,location_id,token["actor_id"],text.strip_edges(),Time.get_datetime_string_from_system(true)]),SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'")]
	var result = SQL.run(BASE.new().path_for(id),commands)
	return {"ok":true,"annotation_id":annotation_id} if result.get("ok",false) else failure("Annotation was not saved.")


# Visible-only lookup by established name or visible alias; no fuzzy invention.
func search_locations(id: String, query: String, limit: int = 32) -> Dictionary:
	if not DTO.bounded_text(query,100) or limit<1 or limit>LIMIT:
		return failure("Invalid location search.")
	var token = TURN.new().snapshot(id)
	if not token.get("ok",false):
		return token
	var needle = query.strip_edges()
	var result = read_sets(token,[SQL.stmt(MAP_LOCATIONS+" AND (instr(lower(l.name),lower(?))>0 OR EXISTS(SELECT 1 FROM location_aliases a WHERE a.location_id=l.id AND a.visibility='player' AND instr(lower(a.alias),lower(?))>0)) ORDER BY l.name COLLATE NOCASE,l.id LIMIT ?",[needle,needle,limit])])
	if not result.get("ok",false):
		return result
	return {"ok":true,"schema_version":DTO.VERSION,"campaign_id":id,"revision":token["revision"],"locations":typed_rows(result["sets"][0])}
