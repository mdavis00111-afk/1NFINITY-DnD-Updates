extends RefCounted
## B4 trusted local reconciliation. No provider commands, mechanics, coordinates
## or actor movement. Build commands locally; TurnStore owns the write transaction.
const SQL = preload("res://systems/sqlite.gd")
const DTO = preload("res://world/world_dto.gd")
const WORLD = preload("res://world/world_store.gd")
const PACK = preload("res://turns/agent_packets.gd")
const PLACE_KINDS = ["house","cottage","hamlet","village","town","city","capital","port","harbour","castle","keep","fortress","watchtower","guard_post","inn","tavern","church","cathedral","temple","shrine","monastery","windmill","watermill","mill","farm","field","blacksmith","trading_post","bridge","dock","lighthouse","plain","grassland","hill","mountain","mountain_range","mountain_pass","cliff","valley","ravine","canyon","plateau","forest","woods","jungle","swamp","marsh","desert","dune","tundra","glacier","volcano","beach","coast","ocean","sea","lake","pond","river","stream","waterfall","spring","island","archipelago","reef","shipwreck","ship","boat","cave","cavern","mine","crypt","tomb","graveyard","ruin","ruins","dungeon","standing_stone","stone_circle","portal","camp","lair","battlefield","monument","well","entrance","landmark","market","court","road","settlement","building","region"]
const ROUTE_KINDS = ["road","track","path","trail","trade_route","sea_route","river","stream","crossing","mountain_pass"]
const RELATION_KINDS = ["relative","near","adjacent","bank","on","within","connected","upstream","downstream"]
const DIRECTIONS = ["north","south","east","west","northeast","northwest","southeast","southwest"]
const OPPOSITE = {"north":"south","south":"north","east":"west","west":"east","northeast":"southwest","southwest":"northeast","northwest":"southeast","southeast":"northwest"}
const RANK = {"unknown":0,"reported":1,"observed":2,"visited":3,"surveyed":4}
const WORD_NUMBERS = ["zero","one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen","twenty"]
const EVENT = "(SELECT event_id FROM turn_narrations WHERE turn_id=?)"
const PLACE_SELECT = "SELECT l.id,l.name,l.kind,l.parent_id,w.region_id,w.precision,w.public_description,d.status,d.visibility FROM locations l JOIN world_places w ON w.location_id=l.id LEFT JOIN world_discovery d ON d.location_id=l.id"
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
	re.compile("^[\\p{L}\\p{N}][\\p{L}\\p{N} '\\u2019-]{0,79}$")
	return re.search(value.strip_edges())!=null and value.split(" ",false).size()<=10

func evidence_has(evidence: String, value: String) -> bool:
	# Match complete phrase, not substrings of other names.
	if value.is_empty():
		return false
	var clean = RegEx.new()
	clean.compile("[^\\p{L}\\p{N}]+")
	var hay = " "+clean.sub(norm(evidence)," ",true).strip_edges()+" "
	var needle = " "+clean.sub(norm(value)," ",true).strip_edges()+" "
	return hay.contains(needle)

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
	commands.append(SQL.stmt("INSERT INTO geography_audit(id,request_id,source_event_id,proposal_index,revision,status,subject_id,detail) VALUES(?,?,"+EVENT+",?,?,?,?,?)",[make_id(),packet["request_id"],packet["turn_id"],index,token["revision"]+1,status,subject,detail]))

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

func place_or_region(f: Dictionary, index: int) -> bool:
	var kind = "place" if f["kind"]=="place" else "terrain_region"
	var ref: Dictionary = f["subject"]
	var name = str(f["name"]).strip_edges()
	var type = str(f["place_kind"] if kind=="place" else f["terrain_kind"]).to_lower()
	if not label_valid(name) or not type in PLACE_KINDS or not evidence_has(f["evidence"],name):
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
		if candidates.size()>1 or (candidates.size()==1 and not visible(candidates[0])):
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
		if description!=null and not str(existing.get("public_description","")).is_empty() and description!=existing["public_description"]:
			record(index,"deferred",existing["id"],"Existing description retained; additional prose not adjudicated.")
		else:
			record(index,"accepted",existing["id"],"Existing identity reused.")
		lines.append(existing["name"]+" — "+existing["kind"].replace("_"," ")+".")
		return true
	# Only unresolved positioning is accepted from B3. Do not set population,
	# terrain, footprint, elevation, occupancy or asset from unreviewed prose.
	var id = make_id()
	var row = {"id":id,"name":name,"kind":type,"parent_id":parent_id,"region_id":region_id,"precision":"provisional","public_description":"","status":"unknown","visibility":"player","entity_kind":kind}
	if not bind(ref,row):
		record(index,"conflict",null,"Proposal-local key collision.")
		return true
	if kind=="place":
		commands.append(SQL.stmt("INSERT INTO locations(id,parent_id,kind,name,x,y,payload) VALUES(?,?,?,?,NULL,NULL,'{}')",[id,parent_id,type,name]))
		commands.append(SQL.stmt("INSERT INTO world_places(location_id,region_id,precision,source_event_id) VALUES(?,?,'provisional',"+EVENT+")",[id,region_id,packet["turn_id"]]))
	else:
		commands.append(SQL.stmt("INSERT INTO terrain_regions(id,parent_id,name,kind,precision,source_event_id) VALUES(?,?,?,?,'provisional',"+EVENT+")",[id,parent_id,name,type,packet["turn_id"]]))
	discover(kind,row,"reported")
	record(index,"accepted",id,"New named entity, unresolved coordinates; descriptive extras require separate validation.")
	lines.append(name+" — "+type.replace("_"," ")+".")
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
	if evidence_has(evidence,"not") or evidence_has(evidence,"never") or evidence_has(evidence,"instead") or evidence_has(evidence,"no longer"):
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
			var forward = e.find(norm(b["name"]))<e.find(direction+" of "+norm(a["name"])) and e.contains(direction+" of "+norm(a["name"]))
			var reverse = e.find(norm(a["name"]))<e.find(OPPOSITE[direction]+" of "+norm(b["name"])) and e.contains(OPPOSITE[direction]+" of "+norm(b["name"]))
			if not forward and not reverse:
				record(index,"deferred",null,"Direction orientation requires clearer evidence.")
				return true
		var rows = query("SELECT id,from_id,to_id,kind,direction,distance_miles,visibility FROM geographic_relationships WHERE kind=? AND ((from_id=? AND to_id=?) OR (from_id=? AND to_id=?)) LIMIT 65",[kind,a["id"],b["id"],b["id"],a["id"]])
		for row in accepted_relations:
			if row["kind"]==kind and ((row["from_id"]==a["id"] and row["to_id"]==b["id"]) or (row["from_id"]==b["id"] and row["to_id"]==a["id"])):
				rows.append(row)
		if not rows.is_empty():
			for row in rows:
				var old_direction = row["direction"]
				if row["from_id"]!=a["id"] and old_direction!=null:
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
		if direction!=null:
			lines.append(b["name"]+" lies "+(str(dist)+" miles " if dist!=null else "")+direction+" of "+a["name"]+".")
		else:
			lines.append(a["name"]+" and "+b["name"]+" — "+kind.replace("_"," ")+".")
		return true
	var name = str(f["name"]).strip_edges()
	var kind = str(f["route_kind"]).to_lower()
	if not label_valid(name) or not kind in ROUTE_KINDS or not evidence_has(evidence,name) or not (evidence_has(evidence,"connects") or evidence_has(evidence,"between") or evidence_has(evidence,"from")):
		record(index,"deferred",null,"Route label or vocabulary not established.")
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

func other_fact(f: Dictionary,index: int) -> bool:
	var kind = "place" if f["kind"]=="alias" else str(f["entity_kind"])
	var row = lookup(f["subject"],kind)
	if row.is_empty():
		return false
	if not evidence_has(f["evidence"],row["name"]):
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
	if not label_valid(alias) or not evidence_has(f["evidence"],alias) or not (evidence_has(f["evidence"],"also called") or evidence_has(f["evidence"],"also known as")):
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
