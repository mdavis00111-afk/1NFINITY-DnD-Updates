extends RefCounted
## B4 trusted local reconciliation. No provider commands, mechanics, coordinates
## or actor movement. Build commands locally; TurnStore owns the write transaction.
const SQL = preload("res://systems/sqlite.gd")
const DTO = preload("res://world/world_dto.gd")
const WORLD = preload("res://world/world_store.gd")
const PACK = preload("res://turns/agent_packets.gd")
const TURN = preload("res://turns/turn_store.gd")
const BASE = preload("res://campaigns/campaign_store.gd")
const PLACE_KINDS = ["house","cottage","hamlet","village","town","city","capital","port","harbour","castle","keep","fortress","watchtower","guard_post","inn","tavern","church","cathedral","temple","shrine","monastery","windmill","watermill","mill","farm","field","blacksmith","trading_post","bridge","dock","lighthouse","plain","grassland","hill","mountain","mountain_range","mountain_pass","cliff","valley","ravine","canyon","plateau","forest","woods","jungle","swamp","marsh","desert","dune","tundra","glacier","volcano","beach","coast","ocean","sea","lake","pond","river","stream","waterfall","spring","island","archipelago","reef","shipwreck","ship","boat","cave","cavern","mine","crypt","tomb","graveyard","ruin","ruins","dungeon","standing_stone","stone_circle","portal","camp","lair","battlefield","monument","well","entrance","landmark","market","court","road","settlement","building","region","wilderness"]
const ROUTE_KINDS = ["road","track","path","trail","trade_route","sea_route","river","stream","crossing","mountain_pass"]
const RELATION_KINDS = ["relative","near","adjacent","bank","on","within","connected","upstream","downstream"]
const DIRECTIONS = ["north","south","east","west","northeast","northwest","southeast","southwest"]
const OPPOSITE = {"north":"south","south":"north","east":"west","west":"east","northeast":"southwest","southwest":"northeast","northwest":"southeast","southeast":"northwest"}
const RANK = {"unknown":0,"reported":1,"observed":2,"visited":3,"surveyed":4}
const WORD_NUMBERS = ["zero","one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen","twenty"]
const EVENT = "(SELECT event_id FROM turn_narrations WHERE turn_id=?)"
const PLACE_SELECT = "SELECT l.id,l.name,l.kind,l.parent_id,w.region_id,w.precision,l.x,l.y,w.uncertainty_miles,w.public_description,d.status,d.visibility FROM locations l JOIN world_places w ON w.location_id=l.id LEFT JOIN world_discovery d ON d.location_id=l.id"
const REGION_SELECT = "SELECT r.id,r.name,r.kind,r.parent_id,r.public_description,d.status,d.visibility FROM terrain_regions r LEFT JOIN world_discovery d ON d.region_id=r.id"
const ROUTE_SELECT = "SELECT r.id,r.name,r.kind,r.from_id,r.to_id,r.distance_miles,r.precision,d.status,d.visibility FROM world_routes r LEFT JOIN world_discovery d ON d.route_id=r.id"
var token: Dictionary
var packet: Dictionary
var commands: Array = []
var lines: PackedStringArray = []
var audit: Array = []
var keys: Dictionary = {}
var entities: Dictionary = {}
var accepted_aliases: Array = []
var accepted_relations: Array = []
var db_error = false
var offered_ids: Array = []

func make_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func query(sql: String, args: Array = []) -> Array:
	var result = WORLD.new().read_sets(token,[SQL.stmt(sql,args)])
	if not result.get("ok",false):
		db_error=true
		return []
	return result["sets"][0]

func norm(value: String) -> String:
	return value.strip_edges().to_lower()

# Names and kinds are labels, not narrative instructions or sentence payloads.
func label_valid(value: String) -> bool:
	var re = RegEx.new()
	re.compile("^[\\p{L}\\p{N}][\\p{L}\\p{N} '’-]{0,79}$")
	return re.search(value.strip_edges())!=null and value.split(" ",false).size()<=10 and not evidence_has(value,"you") and not evidence_has(value,"your") and not evidence_has(value,"player")

func evidence_has(evidence: String, value: String) -> bool:
	# Match complete phrase, not substrings of other names.
	if value.is_empty():
		return false
	var clean = RegEx.new()
	clean.compile("[^\\p{L}\\p{N}]+")
	var hay = " "+clean.sub(norm(evidence)," ",true).strip_edges()+" "
	var needle = " "+clean.sub(norm(value)," ",true).strip_edges()+" "
	return hay.contains(needle)

# Negated or hypothetical claims do not establish canon. Reported rumors
# remain reported, not visited or surveyed.
func uncertain_claim(evidence: String) -> bool:
	for word in ["not","never","no longer","might","maybe","perhaps","if","could be","imaginary","dream","hypothetical"]:
		if evidence_has(evidence,word):
			return true
	return false

func visible(row: Dictionary) -> bool:
	return row.get("visibility")=="player" and row.get("status","unknown")!="unknown"

func lookup(ref: Variant, kind: String) -> Dictionary:
	if ref==null:
		return {}
	var id = ref["id"]
	if id==null:
		id=keys.get(ref["local_key"])
	if id==null:
		return {}
	if entities.has(id):
		var row: Dictionary = entities[id]
		return row if row.get("entity_kind")==kind and visible(row) else {}
	var sql = PLACE_SELECT+" WHERE l.id=?"
	if kind=="route":
		sql=ROUTE_SELECT+" WHERE r.id=?"
	elif kind=="terrain_region":
		sql=REGION_SELECT+" WHERE r.id=?"
	var rows = query(sql,[id])
	if rows.size()!=1 or not visible(rows[0]):
		return {}
	var row: Dictionary = rows[0]
	row["entity_kind"]=kind
	entities[id]=row
	return row

func bind(ref: Dictionary, row: Dictionary) -> bool:
	var id = row["id"]
	if ref["id"]!=null and ref["id"]!=id:
		return false
	if ref["local_key"]!=null:
		if keys.has(ref["local_key"]) and keys[ref["local_key"]]!=id:
			return false
		keys[ref["local_key"]]=id
	entities[id]=row
	return true

func record(index: int, status: String, subject: Variant, detail: String) -> void:
	audit.append({"index":index,"status":status,"subject":subject,"detail":detail})
	commands.append(SQL.stmt("INSERT INTO geography_audit(id,request_id,source_event_id,proposal_index,revision,status,subject_id,detail) VALUES(?,?,"+EVENT+",?,?,?,?,?)",[make_id(),packet["request_id"],packet["turn_id"],index,token["revision"]+1,status,subject,JSON.stringify({"reason":detail,"proposal":packet["facts"][index]})]))

func discover(kind: String, row: Dictionary, status: String) -> void:
	var col = {"place":"location_id","route":"route_id","terrain_region":"region_id"}[kind]
	var current = str(row.get("status","unknown"))
	if RANK.get(current,0)>=RANK[status]:
		return
	commands.append(SQL.stmt("UPDATE world_discovery SET status=?,first_event_id=COALESCE(first_event_id,"+EVENT+") WHERE "+col+"=? AND visibility='player' AND status IN ('reported','observed')",[status,packet["turn_id"],row["id"]]))
	commands.append(SQL.stmt("INSERT INTO world_discovery(id,"+col+",status,visibility,first_event_id) SELECT ?,?,?,'player',"+EVENT+" WHERE NOT EXISTS(SELECT 1 FROM world_discovery WHERE "+col+"=?)",[make_id(),row["id"],status,packet["turn_id"],row["id"]]))
	row["status"]=status
	row["visibility"]="player"

func identity_candidates(kind: String, name: String, parent: Variant, region: Variant) -> Array:
	var rows: Array
	if kind=="place":
		# Include private names/aliases in local collision detection, never return
		# them to the provider or reveal their existence in player text.
		rows=query(PLACE_SELECT+" WHERE lower(trim(l.name))=lower(trim(?)) OR EXISTS(SELECT 1 FROM location_aliases a WHERE a.location_id=l.id AND lower(trim(a.alias))=lower(trim(?))) LIMIT 65",[name,name])
	else:
		rows=query(REGION_SELECT+" WHERE lower(trim(r.name))=lower(trim(?)) LIMIT 65",[name])
	if rows.size()>=65:
		db_error=true
	for row in entities.values():
		if row.get("entity_kind")==kind and norm(row["name"])==norm(name) and not rows.any(func(other): return other["id"]==row["id"]):
			rows.append(row)
	if kind=="place":
		for alias in accepted_aliases:
			if norm(alias["alias"])==norm(name) and entities.has(alias["location_id"]) and not rows.any(func(other): return other["id"]==alias["location_id"]):
				rows.append(entities[alias["location_id"]])
	# A supplied scope must match; unscoped names are not globally unique.
	# Unknown scope is ambiguous, never a licence to create a second entity.
	var candidates: Array = []
	for row in rows:
		if parent!=null and row.get("parent_id")!=null and row.get("parent_id")!=parent:
			continue
		if region!=null and row.get("region_id")!=null and row.get("region_id")!=region:
			continue
		candidates.append(row)
	return candidates

# Persist safe static descriptive prose rather than dropping every ordinary
# detail. The source excerpt must contain the exact proposed description.
func static_description(f: Dictionary, name: String) -> String:
	var description = f.get("description")
	if not description is String or not str(f["evidence"]).contains(description):
		return ""
	var clean = description.strip_edges()
	var lower = norm(clean)
	# Subject-specific static materials/appearance. No coordinates, outcomes,
	# player decisions, secrets, NPC behaviour or claims of movement.
	for subject in [norm(name),"the "+str(f.get("place_kind",f.get("terrain_kind",""))).replace("_"," ")]:
		for suffix in [" is built of stone."," is built of timber."," is built of brick."," is wooden."," is weathered."," is ivy-covered."," is thatched."," has a slate roof."," has an oak door."," has stone walls."," has a wooden roof."]:
			if lower==subject+suffix:
				return clean
	var flavor = sensory_lines(clean)
	if flavor.size()==1 and flavor[0]==clean:
		return clean
	return ""

func place_or_region(f: Dictionary, index: int) -> bool:
	var kind = "place" if f["kind"]=="place" else "terrain_region"
	var ref: Dictionary = f["subject"]
	var name = str(f["name"]).strip_edges()
	var type = str(f["place_kind"] if kind=="place" else f["terrain_kind"]).to_lower()
	if uncertain_claim(f["evidence"]) or not label_valid(name) or not type in PLACE_KINDS or not evidence_has(f["evidence"],name) or (not evidence_has(f["evidence"],type.replace("_"," ")) and ref["id"]==null):
		record(index,"deferred",null,"Name, vocabulary or evidence not established.")
		return true
	var parent = lookup(f["parent"],kind)
	var region = lookup(f.get("region"),"terrain_region")
	if (f["parent"]!=null and parent.is_empty()) or (f.get("region")!=null and region.is_empty()):
		return false
	var parent_id = parent.get("id")
	var region_id = region.get("id")
	if (not parent.is_empty() and not evidence_has(f["evidence"],parent["name"])) or (not region.is_empty() and not evidence_has(f["evidence"],region["name"])):
		record(index,"deferred",null,"Parent or region not supported by evidence.")
		return true
	var existing = lookup(ref,kind)
	var candidates = identity_candidates(kind,name,parent_id,region_id)
	if existing.is_empty():
		if ref["id"]!=null or keys.has(ref["local_key"]):
			record(index,"conflict",null,"Reference unavailable or ambiguous.")
			return true
		if candidates.size()>1 or (candidates.size()==1 and (not visible(candidates[0]) or (not candidates[0]["id"] in offered_ids and not candidates[0].get("staged",false) and parent_id==null and region_id==null))):
			record(index,"conflict",null,"Name resolution unavailable or ambiguous.")
			return true
		if candidates.size()==1:
			existing=candidates[0]
	if not existing.is_empty():
		var matches_name = norm(existing["name"])==norm(name)
		if kind=="place" and not matches_name:
			matches_name=not query("SELECT alias FROM location_aliases WHERE location_id=? AND alias=? COLLATE NOCASE AND visibility='player'",[existing["id"],name]).is_empty() or accepted_aliases.any(func(a): return a["location_id"]==existing["id"] and norm(a["alias"])==norm(name))
		existing["entity_kind"]=kind
		if not matches_name or existing["kind"]!=type or (parent_id!=null and existing.get("parent_id")!=parent_id) or (region_id!=null and existing.get("region_id")!=region_id) or not bind(ref,existing):
			record(index,"conflict",existing["id"],"Established identity, kind or scope preserved.")
			return true
		# Do not rewrite established positions, descriptions, scope or occupancy
		# from a new narrative. Record a conflict when a differing description
		# claims to replace canon; new descriptive prose stays a candidate.
		var description = f.get("description")
		var extra = f.get("population")!=null or f.get("elevation_feet")!=null or f.get("terrain")!=null or f.get("asset_id")!=null or f.get("occupancy","unknown")!="unknown"
		var safe = static_description(f,name)
		var old = str(existing.get("public_description",""))
		if old.is_empty() and not safe.is_empty():
			var col = "location_id" if kind=="place" else "id"
			var table = "world_places" if kind=="place" else "terrain_regions"
			commands.append(SQL.stmt("UPDATE "+table+" SET description=CASE WHEN description='' THEN ? ELSE description END,public_description=? WHERE "+col+"=? AND public_description=''",[safe,safe,existing["id"]]))
			existing["public_description"]=safe
			lines.append(safe)
		if extra or (description!=null and description!=old and description!=safe):
			record(index,"deferred",existing["id"],"Identity retained; unverified descriptive fields not applied.")
		elif description!=null and not old.is_empty() and description!=old:
			record(index,"conflict",existing["id"],"Existing description retained.")
		else:
			record(index,"accepted",existing["id"],"Existing identity reused.")
		lines.append(existing["name"]+" — "+existing["kind"].replace("_"," ")+".")
		return true
	# Only unresolved positioning is accepted from B3. Do not set population,
	# terrain, footprint, elevation, occupancy or asset from unreviewed prose.
	var id = make_id()
	var description = static_description(f,name)
	var row = {"id":id,"name":name,"kind":type,"parent_id":parent_id,"region_id":region_id,"precision":"provisional","public_description":description,"status":"unknown","visibility":"player","entity_kind":kind,"staged":true}
	if not bind(ref,row):
		record(index,"conflict",null,"Proposal-local key collision.")
		return true
	if kind=="place":
		commands.append(SQL.stmt("INSERT INTO locations(id,parent_id,kind,name,x,y,payload) VALUES(?,?,?,?,NULL,NULL,'{}')",[id,parent_id,type,name]))
		commands.append(SQL.stmt("INSERT INTO world_places(location_id,region_id,precision,description,public_description,source_event_id) VALUES(?,?,'provisional',?,?,"+EVENT+")",[id,region_id,description,description,packet["turn_id"]]))
	else:
		commands.append(SQL.stmt("INSERT INTO terrain_regions(id,parent_id,name,kind,precision,description,public_description,source_event_id) VALUES(?,?,?,?,'provisional',?,?,"+EVENT+")",[id,parent_id,name,type,description,description,packet["turn_id"]]))
	discover(kind,row,"reported")
	var extras = f.get("population")!=null or f.get("elevation_feet")!=null or f.get("terrain")!=null or f.get("asset_id")!=null or f.get("occupancy","unknown")!="unknown" or (f.get("description")!=null and description.is_empty())
	record(index,"deferred" if extras else "accepted",id,"Named entity recorded with unresolved coordinates; unverified optional fields deferred." if extras else "New named entity, unresolved coordinates.")
	lines.append(name+" — "+type.replace("_"," ")+".")
	if not description.is_empty():
		lines.append(description)
	return true

func distance_supported(evidence: String, value: Variant) -> bool:
	if value==null:
		return true
	var re = RegEx.new()
	re.compile("(?i)([0-9]+(?:\\.[0-9]+)?|"+ "|".join(WORD_NUMBERS)+")\\s+miles?\\b")
	for hit in re.search_all(evidence):
		var word = hit.get_string(1).to_lower()
		var n = float(word) if word.is_valid_float() else float(WORD_NUMBERS.find(word))
		if is_equal_approx(n,float(value)):
			return true
	return false

# Compare claims to already established positions, without deriving any new
# coordinate from narrative. Allow stated positional uncertainty.
func geometry_conflict(a: Dictionary,b: Dictionary,direction: Variant,dist: Variant,route: bool) -> bool:
	if not DTO.known_position(str(a.get("precision","unknown"))) or not DTO.known_position(str(b.get("precision","unknown"))):
		return false
	var ax = DTO.sql_number(a.get("x"))
	var ay = DTO.sql_number(a.get("y"))
	var bx = DTO.sql_number(b.get("x"))
	var by = DTO.sql_number(b.get("y"))
	var au = DTO.sql_number(a.get("uncertainty_miles"))
	var bu = DTO.sql_number(b.get("uncertainty_miles"))
	if ax==null or ay==null or bx==null or by==null or au==null or bu==null:
		return true
	var dx = bx-ax
	var dy = by-ay
	var uncertainty = au+bu+0.000001
	if direction!=null:
		if (direction.contains("north") and dy < -uncertainty) or (direction.contains("south") and dy > uncertainty) or (direction.contains("east") and dx < -uncertainty) or (direction.contains("west") and dx > uncertainty):
			return true
	if dist!=null:
		var separation = sqrt(dx*dx+dy*dy)
		if route:
			return float(dist)+uncertainty<separation
		return absf(float(dist)-separation)>uncertainty
	return false

func endpoints(f: Dictionary) -> Array:
	var a = lookup(f["from"],"place")
	var b = lookup(f["to"],"place")
	if a.is_empty() or b.is_empty():
		return []
	return [a,b]

func relation_or_route(f: Dictionary,index: int) -> bool:
	var ends = endpoints(f)
	if ends.is_empty():
		return false
	var a: Dictionary = ends[0]
	var b: Dictionary = ends[1]
	var evidence = str(f["evidence"])
	if uncertain_claim(evidence) or evidence_has(evidence,"instead"):
		record(index,"deferred",null,"Negated or changed geography requires reconciliation.")
		return true
	var dist = f["distance_miles"]
	if a["id"]==b["id"] or not evidence_has(evidence,a["name"]) or not evidence_has(evidence,b["name"]) or not distance_supported(evidence,dist):
		record(index,"deferred",null,"Endpoints or distance not explicitly supported.")
		return true
	if f["kind"]=="relationship":
		var kind = str(f["relation_kind"]).to_lower()
		var direction = f["direction"]
		if not kind in RELATION_KINDS or (direction!=null and not direction in DIRECTIONS) or (direction==null and kind=="relative") or (direction==null and not evidence_has(evidence,kind)):
			record(index,"deferred",null,"Relation vocabulary or direction not established.")
			return true
		# For directional relation, only accept unambiguous 'B ... north of A'
		# or 'A ... south of B' evidence. The stored direction is from A to B.
		if direction!=null:
			var e = norm(evidence)
			var forward = e.find(norm(b["name"]))>=0 and e.find(norm(b["name"]))<e.find(direction+" of "+norm(a["name"])) and e.contains(direction+" of "+norm(a["name"]))
			var reverse = kind=="relative" and e.find(norm(a["name"]))<e.find(OPPOSITE[direction]+" of "+norm(b["name"])) and e.contains(OPPOSITE[direction]+" of "+norm(b["name"]))
			if kind=="bank" and direction in ["north","south","east","west"]:
				var bank = direction+"ern bank of "+norm(a["name"])
				forward=e.contains(bank) and e.find(norm(b["name"]))<e.find(bank)
			if not forward and not reverse:
				record(index,"deferred",null,"Direction orientation requires clearer evidence.")
				return true
		if geometry_conflict(a,b,direction,dist if kind=="relative" else null,false):
			record(index,"conflict",null,"Claim contradicts established position or uncertainty.")
			return true
		var rows = query("SELECT id,from_id,to_id,kind,direction,distance_miles,visibility FROM geographic_relationships WHERE kind=? AND ((from_id=? AND to_id=?) OR (from_id=? AND to_id=?)) LIMIT 65",[kind,a["id"],b["id"],b["id"],a["id"]])
		for row in accepted_relations:
			if row["kind"]==kind and ((row["from_id"]==a["id"] and row["to_id"]==b["id"]) or (row["from_id"]==b["id"] and row["to_id"]==a["id"])):
				rows.append(row)
		if not rows.is_empty():
			for row in rows:
				var old_direction = row["direction"]
				if row["from_id"]!=a["id"]:
					if not kind in ["relative","near","adjacent","connected"]:
						record(index,"conflict",null,"Asymmetric relationship orientation preserved.")
						return true
					if old_direction!=null:
						old_direction=OPPOSITE.get(old_direction)
				var old_dist = DTO.sql_number(row["distance_miles"])
				if row["visibility"]!="player" or (direction!=null and old_direction!=direction) or (dist!=null and (old_dist==null or not is_equal_approx(float(dist),old_dist))):
					record(index,"conflict",null,"Established relationship preserved.")
					return true
			record(index,"accepted",rows[0]["id"],"Existing relationship reused.")
		else:
			var id = make_id()
			commands.append(SQL.stmt("INSERT INTO geographic_relationships(id,from_id,to_id,kind,direction,distance_miles,precision,visibility,source_event_id) VALUES(?,?,?,?,?,?,'provisional','player',"+EVENT+")",[id,a["id"],b["id"],kind,direction,dist,packet["turn_id"]]))
			accepted_relations.append({"id":id,"from_id":a["id"],"to_id":b["id"],"kind":kind,"direction":direction,"distance_miles":str(dist) if dist!=null else null,"visibility":"player"})
			record(index,"accepted",id,"Established relative knowledge; no absolute coordinates.")
		if kind=="bank" and direction!=null:
			lines.append(b["name"]+" stands on the "+direction+"ern bank of "+a["name"]+".")
		elif direction!=null:
			lines.append(b["name"]+" lies "+(str(dist)+" miles " if dist!=null else "")+direction+" of "+a["name"]+".")
		else:
			lines.append(a["name"]+" and "+b["name"]+" — "+kind.replace("_"," ")+".")
		return true
	var name = str(f["name"]).strip_edges()
	var kind = str(f["route_kind"]).to_lower()
	if not label_valid(name) or not kind in ROUTE_KINDS or not evidence_has(evidence,name) or not evidence_has(evidence,kind.replace("_"," ")) or not (evidence_has(evidence,"connects") or evidence_has(evidence,"between") or evidence_has(evidence,"from")):
		record(index,"deferred",null,"Route label or vocabulary not established.")
		return true
	if geometry_conflict(a,b,null,dist,true):
		record(index,"conflict",null,"Route distance contradicts established endpoint positions.")
		return true
	var ref: Dictionary = f["subject"]
	var rows = query(ROUTE_SELECT+" WHERE ((r.from_id=? AND r.to_id=?) OR (r.from_id=? AND r.to_id=?)) AND r.kind=? LIMIT 65",[a["id"],b["id"],b["id"],a["id"],kind])
	for row in entities.values():
		if row.get("entity_kind")=="route" and row["kind"]==kind and ((row["from_id"]==a["id"] and row["to_id"]==b["id"]) or (row["from_id"]==b["id"] and row["to_id"]==a["id"])) and not rows.any(func(other): return other["id"]==row["id"]):
			rows.append(row)
	var existing = lookup(ref,"route")
	if existing.is_empty() and rows.size()==1 and visible(rows[0]):
		existing=rows[0]
	if not existing.is_empty():
		var same_ends = (existing["from_id"]==a["id"] and existing["to_id"]==b["id"]) or (existing["from_id"]==b["id"] and existing["to_id"]==a["id"])
		existing["entity_kind"]="route"
		var old_dist = DTO.sql_number(existing["distance_miles"])
		if not same_ends or existing["kind"]!=kind or norm(existing["name"])!=norm(name) or (dist!=null and (old_dist==null or not is_equal_approx(float(dist),old_dist))) or not bind(ref,existing):
			record(index,"conflict",null,"Established route preserved.")
			return true
		record(index,"accepted",existing["id"],"Existing route reused.")
	elif not rows.is_empty() or ref["id"]!=null or keys.has(ref["local_key"]):
		record(index,"conflict",null,"Route resolution unavailable or ambiguous.")
		return true
	else:
		var id = make_id()
		var row = {"id":id,"name":name,"kind":kind,"from_id":a["id"],"to_id":b["id"],"distance_miles":str(dist) if dist!=null else null,"precision":"provisional","status":"unknown","visibility":"player","entity_kind":"route"}
		if not bind(ref,row):
			record(index,"conflict",null,"Proposal-local key collision.")
			return true
		commands.append(SQL.stmt("INSERT INTO world_routes(id,from_id,to_id,name,kind,precision,distance_miles,source_event_id) VALUES(?,?,?,?,?,'provisional',?,"+EVENT+")",[id,a["id"],b["id"],name,kind,dist,packet["turn_id"]]))
		discover("route",row,"reported")
		record(index,"accepted",id,"Known route proposal; not traveled or mechanically cleared.")
	lines.append(name+" connects "+a["name"]+" and "+b["name"]+((" ("+str(dist)+" miles)") if dist!=null else "")+".")
	return true

# Optional descriptive NPC proposal. Local identity only; never assign
# statistics, attitude, movement, quest or mechanical relationships.
func npc_fact(f: Dictionary,index: int) -> bool:
	var location = lookup(f["location"],"place")
	if location.is_empty():
		return false
	var name = str(f["name"]).strip_edges()
	var occupation = str(f["occupation"]).strip_edges()
	var evidence = norm(f["evidence"])
	if location["id"]!=token["location_id"] or uncertain_claim(evidence) or not (evidence_has(evidence,location["name"]) or evidence_has(evidence,"here") or evidence_has(evidence,"nearby") or evidence_has(evidence,"in the "+str(location["kind"]).replace("_"," "))) or not label_valid(name) or not label_valid(occupation) or not (evidence.contains(norm(name)+", the "+norm(occupation)) or evidence.contains(norm(name)+" is the "+norm(occupation)) or evidence.contains(norm(name)+" — "+norm(occupation))):
		record(index,"deferred",null,"NPC introduction not explicitly local and descriptive.")
		return true
	var ref: Dictionary = f["subject"]
	var rows = query("SELECT id,location_id,payload FROM actors WHERE kind='npc' AND (id=? OR instr(lower(payload),lower(?))>0) LIMIT 65",[ref["id"],name])
	if rows.size()>=65:
		db_error=true
	var matches: Array = []
	for raw in rows:
		var data = JSON.parse_string(raw["payload"])
		if data is Dictionary and data.get("name") is String and norm(data["name"])==norm(name):
			matches.append({"id":raw["id"],"name":name,"occupation":data.get("occupation"),"location_id":raw["location_id"],"payload":data,"entity_kind":"npc_description"})
	for row in entities.values():
		if row.get("entity_kind")=="npc_description" and norm(row["name"])==norm(name) and not matches.any(func(other): return other["id"]==row["id"]):
			matches.append(row)
	if not matches.is_empty():
		if matches.size()!=1 or matches[0]["location_id"]!=location["id"] or matches[0]["occupation"]!=occupation or (ref["id"]!=null and ref["id"]!=matches[0]["id"]):
			record(index,"conflict",null,"NPC identity or established location/role differs.")
			return true
		var row: Dictionary = matches[0]
		# Existing actor is not made public by a new model claim. Require
		# a committed disclosure or a staged public introduction.
		if not row.get("staged",false):
			var disclosures = query("SELECT e.payload FROM world_links w JOIN events e ON e.id=w.source_event_id WHERE w.actor_id=? AND w.location_id=? AND e.kind='narration' ORDER BY e.id LIMIT 32",[row["id"],location["id"]])
			var disclosed = false
			for item in disclosures:
				var event = JSON.parse_string(item["payload"])
				var data = row["payload"]
				if event is Dictionary and event.get("text") is String and ((event.get("phase")=="opening" and data.get("descriptive_only")==true and event["text"].contains(name+" — "+occupation)) or (event.get("b4_reconciled")==true and data.get("public")==true and event["text"].contains(name) and event["text"].contains(occupation))):
					disclosed=true
			if not disclosed:
				record(index,"conflict",null,"NPC disclosure unavailable.")
				return true
		if not bind(ref,row):
			record(index,"conflict",null,"NPC local key collision.")
			return true
		record(index,"accepted",row["id"],"Existing disclosed NPC reused.")
	elif ref["id"]!=null or keys.has(ref["local_key"]):
		record(index,"conflict",null,"NPC reference unavailable.")
		return true
	else:
		var id = make_id()
		var row = {"id":id,"name":name,"occupation":occupation,"location_id":location["id"],"entity_kind":"npc_description","staged":true}
		if not bind(ref,row):
			record(index,"conflict",null,"NPC local key collision.")
			return true
		var data = {"id":id,"name":name,"occupation":occupation,"location_id":location["id"],"descriptive_only":true,"public":true}
		commands.append(SQL.stmt("INSERT INTO actors(id,kind,location_id,payload) VALUES(?,'npc',?,?)",[id,location["id"],JSON.stringify(data)]))
		commands.append(SQL.stmt("INSERT INTO world_links(id,location_id,actor_id,source_event_id) VALUES(?,?,?,"+EVENT+")",[make_id(),location["id"],id,packet["turn_id"]]))
		record(index,"accepted",id,"Descriptive NPC introduced at current location.")
	lines.append(name+" — "+occupation+".")
	return true

func other_fact(f: Dictionary,index: int) -> bool:
	var kind = "place" if f["kind"]=="alias" else str(f["entity_kind"])
	var row = lookup(f["subject"],kind)
	if row.is_empty():
		return false
	if uncertain_claim(f["evidence"]) or not evidence_has(f["evidence"],row["name"]):
		record(index,"deferred",row["id"],"Subject not named in evidence.")
		return true
	if f["kind"]=="discovery":
		# A mention is reported, not proof of direct observation. Only explicit
		# observation wording permits observed; never visited/surveyed here.
		var status = "reported"
		if f["status"]=="observed" and (evidence_has(f["evidence"],"visible") or evidence_has(f["evidence"],"in sight")):
			status="observed"
		discover(kind,row,status)
		record(index,"accepted",row["id"],"Discovery monotonically updated.")
		lines.append(row["name"]+" is "+("visible." if status=="observed" else "reported."))
		return true
	var alias = str(f["alias"]).strip_edges()
	if not label_valid(alias) or not evidence_has(f["evidence"],alias) or not (norm(f["evidence"]).contains(norm(row["name"])+" is also called "+norm(alias)) or norm(f["evidence"]).contains(norm(row["name"])+" is also known as "+norm(alias)) or norm(f["evidence"]).contains(norm(row["name"])+", also called "+norm(alias))):
		record(index,"deferred",row["id"],"Alias equivalence not established.")
		return true
	var candidates = identity_candidates("place",alias,row.get("parent_id"),row.get("region_id"))
	if candidates.any(func(other): return other["id"]!=row["id"]):
		record(index,"conflict",row["id"],"Alias collision; established names retained.")
		return true
	var prior = query("SELECT visibility FROM location_aliases WHERE location_id=? AND alias=? COLLATE NOCASE",[row["id"],alias])
	if not prior.is_empty() and prior[0]["visibility"]!="player":
		record(index,"conflict",null,"Alias unavailable.")
		return true
	if prior.is_empty() and not accepted_aliases.any(func(other): return other["location_id"]==row["id"] and norm(other["alias"])==norm(alias)):
		commands.append(SQL.stmt("INSERT INTO location_aliases(location_id,alias,visibility,source_event_id) VALUES(?,?,'player',"+EVENT+")",[row["id"],alias,packet["turn_id"]]))
		accepted_aliases.append({"location_id":row["id"],"alias":alias})
	record(index,"accepted",row["id"],"Alias reconciled.")
	lines.append(row["name"]+" is also known as "+alias+".")
	return true

func plan(state: Dictionary, proposal: Dictionary, text: String, known_ids: Array) -> Dictionary:
	token=state
	packet=proposal
	offered_ids=known_ids.duplicate()
	if not PACK.valid_geography(proposal,PACK.identity(state,proposal.get("turn_id",""),proposal.get("request_id","")),text,known_ids) or proposal["turn_id"]!=state["pending_turn_id"]:
		return {"ok":false,"error":"Invalid geography envelope."}
	var pending: Array = []
	for i in range(proposal["facts"].size()):
		pending.append(i)
	# Resolve dependencies in passes; no cycles, no unresolved reference writes.
	while not pending.is_empty():
		var next: Array = []
		for i in pending:
			var f: Dictionary = proposal["facts"][i]
			var done = false
			match f["kind"]:
				"place","terrain_region": done=place_or_region(f,i)
				"relationship","route": done=relation_or_route(f,i)
				"npc_description": done=npc_fact(f,i)
				_: done=other_fact(f,i)
			if not done:
				next.append(i)
		if next.size()==pending.size():
			for i in next:
				record(i,"deferred",null,"Unresolved or cyclic proposal reference.")
			break
		pending=next
	if db_error:
		return {"ok":false,"error":"Canon lookup failed; no facts committed."}
	var unique: PackedStringArray = []
	for line in lines:
		if not line in unique:
			unique.append(line)
	return {"ok":true,"commands":commands,"lines":unique,"audit":audit}


# The automatic path renders committed mechanics plus accepted facts. Free-form
# prose cannot be proven semantically safe by substring/schema validation.
# A trusted local reviewer may supply approval for the EXACT bundle; ordinary
# descriptions and discoveries never require a player confirmation.
func receipt_line(receipt: Dictionary) -> String:
	var action: Dictionary = receipt["results"][0]
	match action["kind"]:
		"ability_check","saving_throw":
			return "The "+action["kind"].replace("_"," ")+" "+("succeeds." if action["outcome"]=="success" else "fails.")
		"move","travel":
			return "The resolved journey is complete."
		"wait":
			return "The resolved wait is complete."
	return "You observe your surroundings."

# Limited static sensory grammar. No player action, mechanics, geography,
# dialogue, figures, hidden references, or mutable state implied.
func sensory_lines(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var re = RegEx.new()
	re.compile("(?i)^(?:the air (?:smells of|is scented with) (?:woodsmoke|rain|pine|salt|earth|fresh bread|lavender|hay)|(?:soft|warm|pale|dim|golden) (?:light|sunlight|lantern light) (?:fills|illuminates) the (?:room|hall|inn)|(?:a|the) (?:gentle|cool|warm|soft) breeze (?:stirs|drifts) (?:the leaves|through the air)|(?:the )?(?:walls|beams|floor) (?:are|is) (?:weathered|rough|smooth|old|dark|pale)|the air is (?:cool|warm|damp|dry|still|fresh|crisp)(?: and (?:cool|warm|damp|dry|still|fresh|crisp))?|a fire crackles in the hearth|rain patters against the windows|leaves rustle in the breeze|the scent of (?:woodsmoke|pine|salt|earth|fresh bread|lavender|hay) hangs in the air)\\.$")
	for sentence in text.replace("\n"," ").split(".",false):
		var line = sentence.strip_edges()+"."
		if re.search(line)!=null and not line in out:
			out.append(line)
		if out.size()>=4:
			break
	return out

# Invoked with the frozen local controller bundle and known IDs, not a provider
# action. The receipt, event, revision, all accepted facts and audit are checked
# and persisted together. No commands from the input dictionary are executed.
func commit_bundle(id: String, bundle: Dictionary, known_ids: Array, reviewed_prose: bool = false) -> Dictionary:
	var store = TURN.new()
	var state = store.snapshot(id)
	if not state.get("ok",false) or not DTO.exact_keys(bundle,["campaign_id","actor_id","turn_id","expected_revision","receipt","narration","geography"]):
		return {"ok":false,"error":"Invalid reconciliation state."}
	var turn_id = bundle["turn_id"]
	if not DTO.id_valid(turn_id) or bundle["campaign_id"]!=id or bundle["actor_id"]!=state["actor_id"] or not DTO.whole(bundle["expected_revision"],1,DTO.MAX_INT-1):
		return {"ok":false,"error":"Invalid reconciliation identity."}
	var prior = store.receipt_by_id(id,turn_id)
	if not prior.get("ok",false) or not prior.get("found",false) or prior["receipt"]!=bundle["receipt"] or not PACK.committed_receipt_usable(prior["receipt"]):
		return {"ok":false,"error":"Committed receipt unavailable."}
	if prior.get("narration_event_id")!=null:
		return {"ok":true,"replayed":true,"revision":state["revision"]}
	if state["pending_turn_id"]!=turn_id or state["revision"]!=bundle["expected_revision"] or state["revision"]!=prior["receipt"]["next_revision"]:
		return {"ok":false,"error":"Stale reconciliation revision."}
	var narration = bundle["narration"]
	var geography = bundle["geography"]
	if not narration is Dictionary or not geography is Dictionary or not DTO.id_valid(narration.get("request_id")) or not DTO.id_valid(geography.get("request_id")) or narration["request_id"]==geography["request_id"] or not PACK.valid_narration(narration,PACK.identity(state,turn_id,narration["request_id"])):
		return {"ok":false,"error":"Invalid narrative envelope."}
	var planned = plan(state,geography,narration["text"],known_ids)
	if not planned.get("ok",false):
		return planned
	var clean = true
	for item in planned["audit"]:
		if item["status"]!="accepted":
			clean=false
	var text = narration["text"] if reviewed_prose and clean else receipt_line(prior["receipt"])
	if not (reviewed_prose and clean):
		var flavor = sensory_lines(narration["text"]) if clean else PackedStringArray()
		var passages: PackedStringArray = [text]
		passages.append_array(flavor)
		passages.append_array(planned["lines"])
		text="\n\n".join(passages)
	var game_time = "Unspecified" if state["elapsed_seconds"]==null else "Elapsed "+str(state["elapsed_seconds"])+" seconds (tracked epoch)"
	var batch: Array = [store.guard(state),SQL.stmt("INSERT INTO events(turn,game_time,kind,payload) VALUES(?,?,'narration',?)",[state["turn"],game_time,JSON.stringify({"turn_id":turn_id,"location_id":state["location_id"],"text":text,"b4_reconciled":true})]),SQL.stmt("INSERT INTO turn_narrations(turn_id,event_id,revision) VALUES(?,last_insert_rowid(),?)",[turn_id,state["revision"]+1])]
	batch.append_array(planned["commands"])
	batch.append(SQL.stmt("UPDATE world_state SET revision=?,pending_turn_id=NULL WHERE campaign_id=?",[state["revision"]+1,id]))
	batch.append(SQL.stmt("DELETE FROM meta WHERE key='turn_write_guard'"))
	var result = SQL.run(BASE.new().path_for(id),batch)
	if not result.get("ok",false):
		var confirmed = store.receipt_by_id(id,turn_id)
		if confirmed.get("found",false) and confirmed.get("narration_event_id")!=null:
			return {"ok":true,"replayed":true}
		return {"ok":false,"error":"World/narration transaction rejected. Receipt retained; retry reconciliation."}
	return {"ok":true,"revision":state["revision"]+1,"audit_count":planned["audit"].size()}
