extends RefCounted
## Player-facing read model. No migration, private DM lookup or movement writes.
const WORLD = preload("res://world/world_store.gd")
const LIMIT = 128
const MAX_PAGES = 512
const LISTS = ["locations","aliases","relationships","routes","route_points","terrain_regions","terrain_points","travel","travel_points","annotations"]
const VISIBLE = ["reported","observed","visited","surveyed"]
var store = WORLD.new()
var data: Dictionary = {}
var error = ""
var campaign_id = ""
var pending: Dictionary = {}
var next_page = 0
var revision = -1
var annotation_count = -1
var seen: Dictionary = {}

func start(id: String) -> void:
	campaign_id = id
	data = {}
	error = ""
	pending = {}
	seen = {}
	next_page = 0
	revision = -1
	annotation_count = -1
	for key in LISTS:
		pending[key] = []
		seen[key] = {}

func fail(message: String) -> String:
	error = message
	data = {}
	pending = {}
	return "error"

func fetch_next() -> String:
	if next_page >= MAX_PAGES:
		return fail("Map exceeds the current read budget. No partial map displayed.")
	return accept_page(store.map_view(campaign_id,next_page,LIMIT))

func row_key(key: String, row: Dictionary) -> String:
	match key:
		"aliases": return JSON.stringify([row.get("location_id"),row.get("alias")])
		"route_points": return JSON.stringify([row.get("route_id"),row.get("seq")])
		"terrain_points": return JSON.stringify([row.get("region_id"),row.get("seq")])
		"travel": return JSON.stringify([row.get("turn_id"),row.get("seq")])
		"travel_points": return JSON.stringify([row.get("turn_id"),row.get("segment_seq"),row.get("seq")])
		_: return str(row.get("id",""))

func accept_page(page: Dictionary) -> String:
	if not page.get("ok",false):
		return fail(str(page.get("error","World map unavailable.")))
	if page.get("campaign_id")!=campaign_id or page.get("world_id")!=campaign_id or page.get("schema_version")!="1" or page.get("page")!=next_page or page.get("distance_unit")!="mile" or page.get("x_axis")!="east" or page.get("y_axis")!="north":
		return fail("Map projection identity or coordinate contract mismatch.")
	if not page.get("revision") is int or int(page["revision"])<0:
		return fail("Invalid map revision.")
	if not page.get("annotation_count") is int or page["annotation_count"]<0:
		return fail("Invalid map annotation snapshot.")
	if next_page==0:
		revision = page["revision"]
		annotation_count = page["annotation_count"]
	elif page["revision"]!=revision or page["annotation_count"]!=annotation_count:
		return fail("World or annotations changed while reading map. Refresh to retry.")
	var empty = true
	for key in LISTS:
		var rows = page.get(key)
		if not rows is Array:
			return fail("Invalid map projection list: "+key)
		if not rows.is_empty():
			empty = false
		for row in rows:
			if not row is Dictionary:
				return fail("Invalid map row: "+key)
			var identity = row_key(key,row)
			if identity.is_empty() or seen[key].has(identity):
				return fail("Duplicate or missing map row identity: "+key)
			seen[key][identity] = true
			pending[key].append(row)
	next_page += 1
	if not empty:
		return "more"
	if pending["annotations"].size()!=annotation_count:
		return fail("Incomplete map annotations. Refresh to retry.")
	pending["revision"] = revision
	pending["campaign_id"] = campaign_id
	pending["party_location"] = page.get("party_location")
	data = filtered(pending)
	pending = {}
	return "done"

static func visible(row: Dictionary) -> bool:
	return row.get("status") in VISIBLE and row.get("visibility","player")=="player"

static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<=1e12

static func positioned(row: Dictionary) -> bool:
	return row.get("precision") in ["approximate","surveyed"] and numeric(row.get("x")) and numeric(row.get("y")) and numeric(row.get("uncertainty_miles")) and float(row["uncertainty_miles"])>=0

static func segment_key(row: Dictionary, point: bool = false) -> String:
	return str(row.get("turn_id",""))+":"+str(row.get("segment_seq" if point else "seq",-1))

static func filtered(snapshot: Dictionary) -> Dictionary:
	# Defensive projection only. SQL is the authoritative privacy boundary.
	var out = {"campaign_id":snapshot.get("campaign_id",""),"revision":snapshot.get("revision",-1)}
	var places = {}
	var regions = {}
	var routes = {}
	var travel = {}
	out["locations"] = []
	for row in snapshot.get("locations",[]):
		if visible(row):
			places[row["id"]] = row
			out["locations"].append(row)
	out["terrain_regions"] = []
	for row in snapshot.get("terrain_regions",[]):
		if visible(row):
			regions[row["id"]] = row
			out["terrain_regions"].append(row)
	out["routes"] = []
	for row in snapshot.get("routes",[]):
		if visible(row) and places.has(row.get("from_id")) and places.has(row.get("to_id")):
			routes[row["id"]] = row
			out["routes"].append(row)
	out["travel"] = []
	for row in snapshot.get("travel",[]):
		if places.has(row.get("from_id")) and places.has(row.get("to_id")):
			travel[segment_key(row)] = row
			var visible_segment = row.duplicate(true)
			if not routes.has(visible_segment.get("route_id")):
				visible_segment["route_id"] = null
			out["travel"].append(visible_segment)
	for key in ["aliases","annotations","relationships","route_points","terrain_points","travel_points"]:
		out[key] = []
		for row in snapshot.get(key,[]):
			var keep = false
			match key:
				"aliases","annotations": keep = places.has(row.get("location_id"))
				"relationships": keep = places.has(row.get("from_id")) and places.has(row.get("to_id"))
				"route_points": keep = routes.has(row.get("route_id")) and routes[row["route_id"]].get("precision") in ["approximate","surveyed"]
				"terrain_points": keep = regions.has(row.get("region_id")) and regions[row["region_id"]].get("precision") in ["approximate","surveyed"]
				"travel_points": keep = travel.has(segment_key(row,true)) and travel[segment_key(row,true)].get("precision") in ["approximate","surveyed"]
			if keep and row.get("visibility","player")=="player":
				out[key].append(row)
	var party = snapshot.get("party_location")
	out["party_location"] = places.get(party.get("id")) if party is Dictionary else null
	return out

static func measure(a: Dictionary,b: Dictionary) -> Dictionary:
	if not positioned(a) or not positioned(b):
		return {}
	var dx = float(a["x"])-float(b["x"])
	var dy = float(a["y"])-float(b["y"])
	return {"miles":sqrt(dx*dx+dy*dy),"uncertainty":float(a["uncertainty_miles"])+float(b["uncertainty_miles"])}

func search(query: String) -> Dictionary:
	var result = store.search_locations(campaign_id,query,128)
	if result.get("ok",false) and (result.get("campaign_id")!=campaign_id or result.get("schema_version")!="1" or result.get("revision")!=revision):
		return {"ok":false,"error":"World changed. Refresh the map before searching."}
	return result

func annotate(location_id: String, note: String) -> Dictionary:
	if not data.get("locations",[]).any(func(row): return row.get("id")==location_id):
		return {"ok":false,"error":"Choose a known location."}
	return store.add_annotation(campaign_id,location_id,note)

# Direction-only view for campaigns without plotted geometry. These are
# screen directions, with no world position, scale or movement authority.
const SCREEN_DIRECTIONS = {
	"north":Vector2.UP,"south":Vector2.DOWN,"east":Vector2.RIGHT,"west":Vector2.LEFT,
	"northeast":Vector2(1,-1),"northwest":Vector2(-1,-1),"southeast":Vector2(1,1),"southwest":Vector2(-1,1)
}

static func relative_neighbors(snapshot: Dictionary) -> Dictionary:
	var party = snapshot.get("party_location")
	if not party is Dictionary:
		return {}
	var by_id: Dictionary = {}
	for row in snapshot.get("locations",[]):
		by_id[row["id"]]=row
	var directions: Dictionary = {}
	for relation in snapshot.get("relationships",[]):
		var direction = SCREEN_DIRECTIONS.get(relation.get("direction"))
		if relation.get("kind")!="relative" or direction==null:
			continue
		var target = relation["to_id"]
		if target==party["id"]:
			target=relation["from_id"]
			direction=-direction
		elif relation["from_id"]!=party["id"]:
			continue
		if by_id.has(target) and target!=party["id"]:
			if directions.has(target) and directions[target]!=direction:
				directions[target]=null
			else:
				directions[target]=direction
	var groups: Dictionary = {}
	var ids = directions.keys()
	ids.sort()
	for id in ids:
		var direction = directions[id]
		if direction==null:
			continue
		if not groups.has(direction):
			groups[direction]=[]
		groups[direction].append(by_id[id])
	return groups
