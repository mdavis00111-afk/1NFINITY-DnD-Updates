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
var seen: Dictionary = {}

func start(id: String) -> void:
	campaign_id = id
	data = {}
	error = ""
	pending = {}
	seen = {}
	next_page = 0
	revision = -1
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
	if next_page==0:
		revision = page["revision"]
	elif page["revision"]!=revision:
		return fail("World changed while reading map. Refresh to retry.")
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
	pending["revision"] = revision
	pending["campaign_id"] = campaign_id
	pending["party_location"] = page.get("party_location")
	data = filtered(pending)
	pending = {}
	return "done"

static func visible(row: Dictionary) -> bool:
	return row.get("status") in VISIBLE

static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<=1e12

static func positioned(row: Dictionary) -> bool:
	return row.get("precision") in ["approximate","surveyed"] and numeric(row.get("x")) and numeric(row.get("y")) and numeric(row.get("uncertainty_miles")) and float(row["uncertainty_miles"])>=0

static func segment_key(row: Dictionary, point: bool = false) -> String:
	return str(row.get("turn_id",""))+":"+str(row.get("segment_seq" if point else "seq",-1))

static func filtered(snapshot: Dictionary) -> Dictionary:
	# Defensive projection only. SQL is the authoritative privacy boundary.
	var out = snapshot.duplicate(true)
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
			out["travel"].append(row)
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
			if keep:
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
