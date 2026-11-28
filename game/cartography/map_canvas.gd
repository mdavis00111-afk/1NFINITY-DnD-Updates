extends Control
## Draws the player MapView. World coordinates are miles. A separate direction-only sketch uses screen space.
## Pan/zoom and display settings are transient. No write API in this node.
signal location_selected(id: String)
signal region_selected(id: String)
signal view_changed
const MODEL = preload("res://cartography/map_model.gd")
const ART = preload("res://cartography/asset_catalog.gd")
const FONT = preload("res://themes/fonts/EBGaramond.ttf")
const INK = Color("#38261a")
const PAPER = Color("#f1d7a8")
const RED = Color("#a62220")
const MIN_ZOOM = 0.0000000001
const MAX_ZOOM = 2048.0
const LAYER_NAMES = ["Water","Terrain","Rivers & Coastlines","Roads & Tracks","Settlements","Points of Interest","Camps","Labels","Fog of War","Party Path","Party","Notes"]
var layers: Dictionary = {}
var art = ART.new()
var snapshot: Dictionary = {}
var places: Dictionary = {}
var regions: Dictionary = {}
var route_points: Dictionary = {}
var terrain_points: Dictionary = {}
var travel_points: Dictionary = {}
var notes_by_place: Dictionary = {}
var region_id = ""
var selected_id = ""
var measurement: Array = []
var ppm = 24.0
# Store centre as scalar doubles; subtract before converting to Vector2.
var center_x = 0.0
var center_y = 0.0
var hits: Array = []
var region_hits: Array = []
var label_rects: Array[Rect2] = []
var dragging = false
var drag_distance = 0.0
var press_at = Vector2.ZERO

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	art.initialize()
	for name_value in LAYER_NAMES:
		layers[name_value] = true
	resized.connect(queue_redraw)

func set_snapshot(value: Dictionary, refit: bool = true) -> void:
	snapshot = MODEL.filtered(value)
	places.clear()
	regions.clear()
	notes_by_place.clear()
	for row in snapshot.get("locations",[]):
		places[row["id"]] = row
	for row in snapshot.get("terrain_regions",[]):
		regions[row["id"]] = row
	for row in snapshot.get("annotations",[]):
		notes_by_place[row["location_id"]] = true
	route_points = group_points(snapshot.get("route_points",[]),"route_id")
	terrain_points = group_points(snapshot.get("terrain_points",[]),"region_id")
	travel_points = group_points(snapshot.get("travel_points",[]),"travel")
	if not regions.has(region_id):
		region_id = ""
	if not places.has(selected_id):
		selected_id = ""
	measurement.clear()
	if refit:
		fit()
	queue_redraw()

func group_points(rows: Array, key: String) -> Dictionary:
	var result = {}
	for row in rows:
		var id = MODEL.segment_key(row,true) if key=="travel" else str(row.get(key,""))
		if not result.has(id):
			result[id] = []
		result[id].append(row)
	for id in result:
		var points: Array = result[id]
		points.sort_custom(func(a,b): return int(a.get("seq",-1))<int(b.get("seq",-1)))
		var valid = points.size()<=256
		for i in range(points.size()):
			var p = points[i]
			if int(p.get("seq",-1))!=i or not MODEL.numeric(p.get("x")) or not MODEL.numeric(p.get("y")):
				valid = false
				break
		if not valid:
			result[id] = []
	return result

func set_layer(name_value: String, enabled: bool) -> void:
	if layers.has(name_value):
		layers[name_value] = enabled
		queue_redraw()

func in_region(row: Dictionary) -> bool:
	return region_id.is_empty() or row.get("region_id")==region_id

func endpoints_in_region(row: Dictionary) -> bool:
	return places.has(row.get("from_id")) and places.has(row.get("to_id")) and in_region(places[row["from_id"]]) and in_region(places[row["to_id"]])

func set_region(id: String) -> void:
	if not id.is_empty() and not regions.has(id):
		return
	region_id = id
	measurement.clear()
	fit()

func screen_point(x: float,y: float) -> Vector2:
	return size*0.5+Vector2((x-center_x)*ppm,(center_y-y)*ppm)

func at(row: Dictionary) -> Vector2:
	return screen_point(float(row["x"]),float(row["y"]))

func world_at(p: Vector2) -> Array:
	return [center_x+float(p.x-size.x*0.5)/ppm,center_y-float(p.y-size.y*0.5)/ppm]

func zoom(factor: float, pivot: Vector2) -> void:
	var before = world_at(pivot)
	ppm = clampf(ppm*factor,MIN_ZOOM,MAX_ZOOM)
	var after = world_at(pivot)
	center_x = clampf(center_x+before[0]-after[0],-1e12,1e12)
	center_y = clampf(center_y+before[1]-after[1],-1e12,1e12)
	queue_redraw()
	view_changed.emit()

func focus_place(id: String) -> bool:
	if not places.has(id) or not MODEL.positioned(places[id]):
		return false
	var row = places[id]
	if not in_region(row):
		region_id = ""
	center_x = float(row["x"])
	center_y = float(row["y"])
	selected_id = id
	queue_redraw()
	view_changed.emit()
	return true

func center_party() -> bool:
	var party = snapshot.get("party_location")
	return focus_place(str(party["id"])) if party is Dictionary else false

func fit() -> void:
	var bounds: Array = []
	for row in places.values():
		if in_region(row) and MODEL.positioned(row):
			bounds.append(row)
	for id in terrain_points:
		if region_id.is_empty() or id==region_id:
			bounds.append_array(terrain_points[id])
	for row in snapshot.get("routes",[]):
		if endpoints_in_region(row):
			bounds.append_array(route_points.get(row["id"],[]))
	for row in snapshot.get("travel",[]):
		if endpoints_in_region(row):
			bounds.append_array(travel_points.get(MODEL.segment_key(row),[]))
	if bounds.is_empty():
		center_x = 0.0
		center_y = 0.0
		ppm = 24.0
		# No origin symbol, scale or spatial claim for unresolved world.
	else:
		var min_x = float(bounds[0]["x"])
		var max_x = min_x
		var min_y = float(bounds[0]["y"])
		var max_y = min_y
		for row in bounds:
			min_x = minf(min_x,float(row["x"]))
			max_x = maxf(max_x,float(row["x"]))
			min_y = minf(min_y,float(row["y"]))
			max_y = maxf(max_y,float(row["y"]))
		center_x = min_x+(max_x-min_x)*0.5
		center_y = min_y+(max_y-min_y)*0.5
		ppm = clampf(minf(maxf(80.0,size.x-180)/maxf(1.0,max_x-min_x),maxf(80.0,size.y-140)/maxf(1.0,max_y-min_y)),MIN_ZOOM,64.0)
	queue_redraw()
	view_changed.emit()

func has_geometry() -> bool:
	for row in places.values():
		if in_region(row) and MODEL.positioned(row):
			return true
	for id in terrain_points:
		if (region_id.is_empty() or id==region_id) and terrain_points[id].size()>=3:
			return true
	for row in snapshot.get("routes",[]):
		if endpoints_in_region(row) and route_points.get(row["id"],[]).size()>=2:
			return true
	for row in snapshot.get("travel",[]):
		if endpoints_in_region(row) and travel_points.get(MODEL.segment_key(row),[]).size()>=2:
			return true
	return false

func draw_art(asset: Dictionary, pos: Vector2, width: float, tint: Color = Color.WHITE) -> Rect2:
	if asset.is_empty():
		return Rect2()
	var tex = art.texture(str(asset["id"]))
	if tex==null:
		return Rect2()
	var extent = Vector2(width,width*float(asset["height"])/float(asset["width"]))
	var anchor = Vector2(float(asset["anchor"][0]),float(asset["anchor"][1]))
	var rect = Rect2(pos-extent*anchor,extent)
	if rect.intersects(Rect2(Vector2.ZERO,size)):
		draw_texture_rect(tex,rect,false,tint)
	return rect

func decoration(id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	var tex = art.texture(id)
	if tex!=null:
		draw_texture_rect(tex,rect,false,tint)

func projected(rows: Array) -> PackedVector2Array:
	var points = PackedVector2Array()
	for row in rows:
		points.append(at(row))
	return points

func point_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var bounds = Rect2(points[0],Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	return bounds

func draw_fog() -> void:
	# This is only a decorative unknown substrate. It neither discloses
	# secret features nor claims that an arbitrary circle is explored.
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.35,0.27,0.17,0.42),true)
	for x in range(-60,int(size.x),144):
		for y in range(-48,int(size.y),108):
			var alternate = (int((x+60)/144)+int((y+48)/108))%2
			decoration("decor.fog_hatch.v1" if alternate==0 else "decor.fog_hatch.v2",Rect2(x,y,168,126),Color(1,1,1,0.60))
			decoration("decor.fog_cloud.v1" if alternate==0 else "decor.fog_cloud.v2",Rect2(x-12,y-8,184,140),Color(1,1,1,0.10))

func draw_region(row: Dictionary, points: PackedVector2Array, water: bool) -> void:
	if points.size()<3 or not point_bounds(points).grow(2).intersects(Rect2(Vector2.ZERO,size)):
		return
	# Never invent a boundary from a name or centroid. Invalid topology is not filled.
	var triangles = Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		return
	var reported = row.get("status")=="reported"
	var layer_visible = layers.get("Water",true) if water else layers.get("Terrain",true)
	var fill = PAPER
	if reported:
		fill = Color("#ad9775") if layers.get("Fog of War",true) else PAPER
	elif water and layer_visible:
		fill = Color("#d6c49a")
	# Known terrain is disclosed independently of the optional terrain art layer.
	draw_colored_polygon(points,fill)
	if not layer_visible:
		return
	var border = points.duplicate()
	border.append(points[0])
	draw_polyline(border,Color(INK,0.5 if reported else 0.86),1.2,true)
	var bounds = point_bounds(points)
	var stamp_at = bounds.get_center()
	if not Geometry2D.is_point_in_polygon(stamp_at,points):
		stamp_at = (points[triangles[0]]+points[triangles[1]]+points[triangles[2]])/3.0
	var asset = art.choose("water" if water else "terrain",row.get("kind",""),str(row["id"]),ppm<2.0)
	if not asset.is_empty():
		# A decorative region illustration, not a distinct geographic point.
		draw_art(asset,stamp_at,clampf(minf(bounds.size.x,bounds.size.y)*0.6,24,120),Color(1,1,1,0.42 if reported else 0.88))
	if layers.get("Labels",true) and Rect2(Vector2.ZERO,size).has_point(stamp_at):
		map_label(str(row.get("name","")),stamp_at+Vector2(0,26),15,Color(INK,0.6 if reported else 1.0))
	region_hits.append({"id":row["id"],"polygon":points})

func route_style(kind: Variant) -> Dictionary:
	var key = "navigation."+ART.normalize(kind)
	return art.styles.get(key,{"color":"#38261a","width":1.1,"dash":[3,4]})

func clipped_segment(a: Vector2,b: Vector2) -> Array:
	# Clip before drawing a dashed stroke: astronomical world extents must not
	# create unbounded dash loops or graphics coordinates outside the viewport.
	var rect = Rect2(Vector2.ZERO,size).grow(12)
	var d = b-a
	var lo = 0.0
	var hi = 1.0
	for pair in [[-d.x,a.x-rect.position.x],[d.x,rect.end.x-a.x],[-d.y,a.y-rect.position.y],[d.y,rect.end.y-a.y]]:
		var p = float(pair[0])
		var q = float(pair[1])
		if is_zero_approx(p):
			if q<0: return []
		else:
			var t = q/p
			if p<0: lo = maxf(lo,t)
			else: hi = minf(hi,t)
			if lo>hi: return []
	return [a+d*lo,a+d*hi]

func draw_route(rows: Array, style: Dictionary, tint: float = 1.0) -> void:
	if rows.size()<2:
		return
	var color = Color(str(style.get("color","#38261a")),tint)
	var width = float(style.get("width",1.2))
	var dashes: Array = style.get("dash",[])
	for i in range(1,rows.size()):
		var segment = clipped_segment(at(rows[i-1]),at(rows[i]))
		if segment.is_empty():
			continue
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		if dashes.is_empty():
			draw_line(a,b,color,width,true)
			if style.get("double_line",false):
				var side = (b-a).normalized().orthogonal()*3.0
				draw_line(a+side,b+side,color,width,true)
		else:
			var length = a.distance_to(b)
			var direction = (b-a).normalized()
			var distance = 0.0
			var index = 0
			while distance<length:
				var end = minf(length,distance+maxf(1.0,float(dashes[index%dashes.size()])))
				if index%2==0:
					draw_line(a+direction*distance,a+direction*end,color,width,true)
				distance = end
				index += 1

func draw_label(value: String, pos: Vector2, px: int, color: Color) -> void:
	var clipped = value.substr(0,70)
	var width = FONT.get_string_size(clipped,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	var start = pos-Vector2(width*0.5,0)
	draw_string_outline(FONT,start,clipped,HORIZONTAL_ALIGNMENT_LEFT,-1,px,3,Color(PAPER,0.9))
	draw_string(FONT,start,clipped,HORIZONTAL_ALIGNMENT_LEFT,-1,px,color)

func map_label(value: String,pos: Vector2,px: int,color: Color,priority: bool = false) -> void:
	var width = FONT.get_string_size(value.substr(0,70),HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	var bounds = Rect2(pos-Vector2(width*0.5+3,px),Vector2(width+6,px+5))
	if not priority:
		for prior in label_rects:
			if prior.intersects(bounds):
				return
	label_rects.append(bounds)
	draw_label(value,pos,px,color)

func place_layer(row: Dictionary, asset: Dictionary) -> String:
	var kind = ART.normalize(row.get("kind",""))
	if kind in ["camp","military_camp","adventurer_camp","bandit_camp"]:
		return "Camps"
	if kind in ["river","stream","rocky_coast","beach"]:
		return "Rivers & Coastlines"
	match str(asset.get("category","")):
		"settlements": return "Settlements"
		"terrain": return "Terrain"
		"water": return "Water"
		_: return "Points of Interest"

func draw_places() -> void:
	for row in places.values():
		if not in_region(row) or not MODEL.positioned(row):
			continue
		var p = at(row)
		if not Rect2(Vector2.ZERO,size).grow(140).has_point(p):
			continue
		var small = ppm<2.0
		var asset = art.for_place(row,small)
		var layer = place_layer(row,asset)
		if not layers.get(layer,true):
			continue
		var reported = row.get("status")=="reported"
		var width = 38.0 if asset.is_empty() else float(asset["scale"]["recommended_px"])
		width = clampf(width*(0.65 if small else 1.0),22,118)
		var rect = draw_art(asset,p,width,Color(1,1,1,0.48 if reported else 1.0))
		if reported:
			draw_art(art.entries.get("markers.unknown.v1",{}),p+Vector2(0,-10),16)
		elif (row.get("status")=="visited" or row.get("last_visit_event_id")!=null) and layers.get("Party Path",true):
			draw_art(art.entries.get("markers.visited.v1",{}),p,16)
		if row["id"]==selected_id:
			draw_arc(p,12,0,TAU,24,RED,1.5,true)
		if layers.get("Labels",true):
			map_label(str(row.get("name","")),p+Vector2(0,18),15,Color(INK,0.55 if reported else 1.0),row["id"]==selected_id or asset.is_empty())
		if layers.get("Notes",true) and notes_by_place.has(row["id"]):
			draw_art(art.entries.get("markers.annotation.v1",{}),p+Vector2(20,-15),19)
		if rect.has_area():
			hits.append({"id":row["id"],"rect":rect.merge(Rect2(p-Vector2(18,6),Vector2(36,26))),"point":p})
		elif layers.get("Labels",true) or reported:
			hits.append({"id":row["id"],"rect":Rect2(p-Vector2(38,12),Vector2(76,36)),"point":p})

func _draw() -> void:
	hits.clear()
	region_hits.clear()
	label_rects.clear()
	draw_rect(Rect2(Vector2.ZERO,size),PAPER)
	decoration("decor.parchment.v1",Rect2(Vector2.ZERO,size))
	if layers.get("Fog of War",true):
		draw_fog()
	for pass_water in [true,false]:
		for id in regions:
			if not region_id.is_empty() and id!=region_id:
				continue
			var row = regions[id]
			var is_water = not art.choose("water",row.get("kind",""),id).is_empty()
			if is_water==pass_water:
				draw_region(row,projected(terrain_points.get(id,[])),is_water)
	for row in snapshot.get("routes",[]):
		if not endpoints_in_region(row):
			continue
		var kind = ART.normalize(row.get("kind",""))
		var waterway = kind in ["river","stream","coastline","rocky_coast"]
		if layers.get("Rivers & Coastlines" if waterway else "Roads & Tracks",true):
			draw_route(route_points.get(row["id"],[]),route_style("coastline" if kind=="rocky_coast" else kind),0.5 if row.get("status")=="reported" else 1.0)
	if layers.get("Party Path",true):
		for row in snapshot.get("travel",[]):
			if endpoints_in_region(row):
				draw_route(travel_points.get(MODEL.segment_key(row),[]),art.styles.get("navigation.actual_player_path",{"color":"#a62220","width":2.1,"dash":[]}))
	draw_places()
	var party = snapshot.get("party_location")
	if layers.get("Party",true) and party is Dictionary and in_region(party) and MODEL.positioned(party):
		draw_art(art.entries.get("markers.party_position.v1",{}),at(party),26)
	if measurement.size()==2 and places.has(measurement[0]) and places.has(measurement[1]):
		var a = places[measurement[0]]
		var b = places[measurement[1]]
		if MODEL.positioned(a) and MODEL.positioned(b) and in_region(a) and in_region(b):
			draw_route([a,b],{"color":"#70523c","width":1.4,"dash":[4,4]})
	if not has_geometry() and not draw_relative_sketch():
		draw_label("Positions not yet established",size*0.5,25,INK)
		draw_label("Known names remain in the journal.",size*0.5+Vector2(0,25),16,INK)
	draw_chrome()

func draw_relative_sketch() -> bool:
	if not region_id.is_empty() or size.x<350 or size.y<270:
		return false
	var neighbors = MODEL.relative_neighbors(snapshot)
	if neighbors.is_empty():
		return false
	var center = size*0.5
	draw_label("Reported directions · not to scale",Vector2(size.x*0.5,35),21,INK)
	draw_circle(center,6,RED)
	draw_label(str(snapshot["party_location"]["name"]),center+Vector2(0,23),18,INK)
	var extent = Vector2(size.x*0.29,size.y*0.29)
	for direction in neighbors:
		var at_screen = center+direction*extent
		var line = center.direction_to(at_screen)
		draw_dashed_line(center+line*12,at_screen-line*20,Color(INK,0.5),1.3,5.0)
		draw_circle(at_screen,4,INK)
		var rows = neighbors[direction]
		for index in range(mini(rows.size(),3)):
			var row = rows[index]
			var label_at = at_screen+Vector2(0,18+index*18)
			draw_label(str(row["name"]).left(25),label_at,16,RED if row["id"]==selected_id else INK)
			hits.append({"id":row["id"],"rect":Rect2(label_at-Vector2(70,14),Vector2(140,18)),"point":label_at})
		if rows.size()>3:
			draw_label("More in the journal",at_screen+Vector2(0,72),14,INK)
	return true

func draw_chrome() -> void:
	# Fixed parchment ornaments, not part of world coordinates.
	var edge = 13.0
	decoration("decor.edge_top.harvest",Rect2(0,0,size.x,edge),Color(1,1,1,0.72))
	decoration("decor.edge_bottom.harvest",Rect2(0,size.y-edge,size.x,edge),Color(1,1,1,0.72))
	decoration("decor.edge_left.harvest",Rect2(0,0,edge,size.y),Color(1,1,1,0.72))
	decoration("decor.edge_right.harvest",Rect2(size.x-edge,0,edge,size.y),Color(1,1,1,0.72))
	for corner in [["top_left",Vector2.ZERO],["top_right",Vector2(size.x-32,0)],["bottom_left",Vector2(0,size.y-32)],["bottom_right",size-Vector2(32,32)]]:
		decoration("decor.corner_"+str(corner[0])+".harvest",Rect2(corner[1],Vector2(32,32)))
	decoration("decor.compass.harvest",Rect2(18,16,90,85))
	if has_geometry():
		var target = 110.0/ppm
		var power = pow(10.0,floor(log(target)/log(10.0)))
		var unit = power
		if target/power>=5.0: unit = 5.0*power
		elif target/power>=2.0: unit = 2.0*power
		var length = unit*ppm
		var origin = Vector2(24,size.y-25)
		draw_line(origin,origin+Vector2(length,0),INK,2,true)
		for i in range(5):
			var p = origin+Vector2(length*i/4.0,0)
			draw_line(p-Vector2(0,6 if i%2==0 else 3),p+Vector2(0,3),INK,1.2,true)
		draw_label(str(snappedf(unit,0.00000001))+" mi",origin+Vector2(length*0.5,-10),14,INK)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:
			zoom(1.2,event.position)
			accept_event()
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.0/1.2,event.position)
			accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT or event.button_index==MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				dragging = true
				drag_distance = 0.0
				press_at = event.position
			else:
				if dragging and drag_distance<5.0 and event.button_index==MOUSE_BUTTON_LEFT:
					select_at(event.position)
				dragging = false
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		if not (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)):
			dragging = false
			return
		drag_distance += event.relative.length()
		center_x = clampf(center_x-float(event.relative.x)/ppm,-1e12,1e12)
		center_y = clampf(center_y+float(event.relative.y)/ppm,-1e12,1e12)
		queue_redraw()
		accept_event()

func select_at(pos: Vector2) -> void:
	var best = ""
	var distance = INF
	for hit in hits:
		if hit["rect"].has_point(pos) and pos.distance_to(hit["point"])<distance:
			best = hit["id"]
			distance = pos.distance_to(hit["point"])
	if not best.is_empty():
		selected_id = best
		location_selected.emit(best)
		queue_redraw()
		return
	for i in range(region_hits.size()-1,-1,-1):
		if Geometry2D.is_point_in_polygon(pos,region_hits[i]["polygon"]):
			region_selected.emit(str(region_hits[i]["id"]))
			return
