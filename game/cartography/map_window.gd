extends Window
## Modal journal over existing game workspace. Only MapView reads and B1 notes.
## Future controller explicitly binds intent_handler; never move the party here.
const MODEL = preload("res://cartography/map_model.gd")
const CANVAS = preload("res://cartography/map_canvas.gd")
const ART = preload("res://cartography/asset_catalog.gd")
const FONT = preload("res://themes/fonts/EBGaramond.ttf")
const INK = Color("#302116")
const PAPER = Color("#f0d6a5")
const DARK_PAPER = Color("#d9b883")
const FRAME = Color("#745338")
const RED = Color("#a62220")
var model = MODEL.new()
var art = ART.new()
var campaign_id = ""
var campaign_title = ""
var intent_handler: Callable
var canvas
var region_select: OptionButton
var scope_label: Label
var state_label: Label
var search_box: LineEdit
var location_list: ItemList
var details: RichTextLabel
var note_box: TextEdit
var note_button: Button
var travel_button: Button
var center_button: Button
var open_region_button: Button
var measure_button: Button
var fullscreen_button: Button
var history_box: RichTextLabel
var tabs: TabContainer
var refresh_button: Button
var note_drafts: Dictionary = {}
var selected_id = ""
var selected_region = ""
var measure_mode = false
var is_loading = false
var load_generation = 0
var fullscreen_map = false
var normal_size = Vector2i(1100,650)
var normal_position = Vector2i.ZERO
var scope_sync = false

func configure(id: String,title_value: String,handler: Callable = Callable()) -> void:
	campaign_id = id
	campaign_title = title_value
	intent_handler = handler

func _ready() -> void:
	title = "Adventurer's Cartography"
	transient = true
	exclusive = true
	min_size = Vector2i(940,610)
	close_requested.connect(queue_free)
	art.initialize()
	theme = map_theme()
	build()
	refresh_map.call_deferred(true)

func map_theme() -> Theme:
	var t = Theme.new()
	t.default_font = FONT
	t.default_font_size = 17
	for cls in ["Label","Button","CheckBox","OptionButton","LineEdit","ItemList","TabContainer","TextEdit","RichTextLabel","PopupMenu"]:
		for key in ["font_color","font_hover_color","font_pressed_color","font_selected_color","font_focus_color","font_outline_color","default_color","font_placeholder_color"]:
			t.set_color(key,cls,INK)
		t.set_color("font_disabled_color",cls,Color("#8c7557"))
	for cls in ["Button","OptionButton"]:
		t.set_stylebox("normal",cls,panel_style(PAPER,5))
		t.set_stylebox("hover",cls,panel_style(Color("#fce9bc"),5))
		t.set_stylebox("pressed",cls,panel_style(DARK_PAPER,5))
		t.set_stylebox("disabled",cls,panel_style(Color("#d8c29e"),5))
		t.set_stylebox("focus",cls,panel_style(Color("#f9e1b2"),5))
	for cls in ["LineEdit","TextEdit","ItemList","PopupMenu"]:
		t.set_stylebox("normal",cls,panel_style(Color("#f7e1b8"),5))
		t.set_stylebox("panel",cls,panel_style(Color("#f7e1b8"),5))
		t.set_stylebox("focus",cls,panel_style(Color("#fce9bc"),5))
	t.set_stylebox("selected","ItemList",panel_style(DARK_PAPER,2))
	t.set_stylebox("selected_focus","ItemList",panel_style(DARK_PAPER,2))
	t.set_stylebox("panel","TabContainer",panel_style(PAPER,6))
	t.set_stylebox("tab_selected","TabContainer",panel_style(Color("#fce9bc"),4))
	t.set_stylebox("tab_unselected","TabContainer",panel_style(DARK_PAPER,4))
	t.set_stylebox("tab_hovered","TabContainer",panel_style(Color("#fce9bc"),4))
	t.set_color("font_selected_color","TabContainer",INK)
	t.set_color("font_unselected_color","TabContainer",INK)
	t.set_color("font_hovered_color","TabContainer",INK)
	var check = art.texture("tools.checkbox_checked.v1")
	var uncheck = art.texture("tools.checkbox_empty.v1")
	# Existing art is 128px. Use scaled images for compact native CheckBoxes.
	if check!=null:
		var im = check.get_image()
		im.resize(18,18,Image.INTERPOLATE_LANCZOS)
		t.set_icon("checked","CheckBox",ImageTexture.create_from_image(im))
	if uncheck!=null:
		var im = uncheck.get_image()
		im.resize(18,18,Image.INTERPOLATE_LANCZOS)
		t.set_icon("unchecked","CheckBox",ImageTexture.create_from_image(im))
	return t

func panel_style(color: Color, padding: int = 5) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = FRAME
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		s.set_content_margin(side,padding)
	return s

func vbox(parent: Node, gap: int = 5) -> VBoxContainer:
	var node = VBoxContainer.new()
	node.add_theme_constant_override("separation",gap)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func hbox(parent: Node, gap: int = 5) -> HBoxContainer:
	var node = HBoxContainer.new()
	node.add_theme_constant_override("separation",gap)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func label(parent: Node,value: String,px: int = 17,wrap: bool = true) -> Label:
	var node = Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size",px)
	node.add_theme_color_override("font_color",INK)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not wrap:
		node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(node)
	return node

func button(parent: Node,caption: String,action: Callable,icon_id: String = "",compact: bool = false) -> Button:
	var node = Button.new()
	node.text = caption
	node.custom_minimum_size = Vector2(40,32)
	node.tooltip_text = caption
	if not icon_id.is_empty():
		node.icon = art.texture(icon_id)
		node.expand_icon = true
		node.add_theme_constant_override("icon_max_width",25)
	if compact:
		node.text = ""
		node.custom_minimum_size = Vector2(44,43)
	if action.is_valid():
		node.pressed.connect(action)
	parent.add_child(node)
	return node

func rich(parent: Node,minimum: int = 110) -> RichTextLabel:
	var node = RichTextLabel.new()
	node.bbcode_enabled = false
	node.add_theme_color_override("default_color",INK)
	node.custom_minimum_size.y = minimum
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func section(parent: Node,caption: String) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",panel_style(Color("#efd4a4"),5))
	parent.add_child(panel)
	var col = vbox(panel,2)
	if not caption.is_empty():
		var heading = label(col,caption,22)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(HSeparator.new())
	return col

func build() -> void:
	var panel = PanelContainer.new()
	var bg = StyleBoxTexture.new()
	bg.texture = art.texture("decor.parchment.v1")
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		bg.set_content_margin(side,9)
	panel.add_theme_stylebox_override("panel",bg if bg.texture!=null else panel_style(PAPER,8))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root = vbox(panel,5)
	var header = hbox(root,6)
	var ribbon = PanelContainer.new()
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ribbon_style = StyleBoxTexture.new()
	ribbon_style.texture = art.texture("decor.title_ribbon.v1")
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		ribbon_style.set_content_margin(side,7)
	ribbon.add_theme_stylebox_override("panel",ribbon_style if ribbon_style.texture!=null else panel_style(PAPER,6))
	header.add_child(ribbon)
	var title_label = label(ribbon,campaign_title if not campaign_title.is_empty() else "Campaign atlas",26,false)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.tooltip_text = campaign_title
	refresh_button = button(header,"Refresh",func(): refresh_map(false))
	fullscreen_button = button(header,"Fullscreen",toggle_fullscreen,"tools.fullscreen.v1")
	button(header,"Close",queue_free)
	var sub = hbox(root,5)
	scope_label = label(sub,"World overview",19,false)
	region_select = OptionButton.new()
	region_select.custom_minimum_size.x = 180
	region_select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	region_select.item_selected.connect(change_region)
	sub.add_child(region_select)
	search_box = LineEdit.new()
	search_box.placeholder_text = "Find known place or alias..."
	search_box.max_length = 100
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_box.text_submitted.connect(func(_value: String): search_locations())
	sub.add_child(search_box)
	button(sub,"Find",search_locations,"tools.search.v1")
	var body = hbox(root,6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tools = section(body,"")
	tools.custom_minimum_size.x = 55
	button(tools,"Zoom in",func(): canvas.zoom(1.25,canvas.size*0.5),"tool.zoom_in.harvest",true)
	button(tools,"Zoom out",func(): canvas.zoom(0.8,canvas.size*0.5),"tool.zoom_out.harvest",true)
	button(tools,"World / region overview",func(): canvas.fit(),"tools.overview.v1",true)
	center_button = button(tools,"Centre party",focus_party,"tools.center.v1",true)
	measure_button = button(tools,"Measure between known locations",toggle_measure,"tool.measure.harvest",true)
	button(tools,"Add note to selected location",show_note_editor,"tool.pencil.harvest",true)
	var erase = button(tools,"Erase annotation",Callable(),"tool.erase.harvest",true)
	erase.disabled = true
	erase.tooltip_text = "Annotation deletion is not exposed by B1."
	button(tools,"Travel history",func(): tabs.current_tab=2,"tools.history.v1",true)
	var pan_hint = label(tools,"Drag\nto pan",13)
	pan_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var filler = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools.add_child(filler)
	canvas = CANVAS.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(300,260)
	body.add_child(canvas)
	canvas.location_selected.connect(select_location)
	canvas.region_selected.connect(select_region_info)
	canvas.view_changed.connect(sync_scope)
	tabs = TabContainer.new()
	tabs.custom_minimum_size.x = 268
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	build_legend()
	build_journal()
	build_history()
	state_label = label(root,"Loading committed map...",16)
	state_label.custom_minimum_size.y = 26
	state_label.max_lines_visible = 2

func scroll_column(parent: Node) -> VBoxContainer:
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	return vbox(sc,3)

func build_legend() -> void:
	var page = vbox(tabs)
	page.name = "Layers"
	var col = scroll_column(page)
	var layer_panel = section(col,"Map Layers")
	for name_value in CANVAS.LAYER_NAMES:
		var key = name_value
		var check = CheckBox.new()
		check.text = key
		check.button_pressed = true
		check.toggled.connect(func(enabled: bool): canvas.set_layer(key,enabled))
		layer_panel.add_child(check)
	var legend = section(col,"Legend")
	for entry in [["Capital","settlement.capital.harvest"],["City","settlement.city.harvest"],["Town","settlement.town.harvest"],["Village","settlement.village.harvest"],["Keep / fortress","settlement.keep.harvest"],["Church / temple","settlement.church.harvest"],["Mill","settlement.windmill.harvest"],["Mine","adventure.mine.harvest"],["Ruins","adventure.ruins.harvest"],["Cave / dungeon","adventure.cave.harvest"],["Camp","adventure.camp.harvest"],["Point of interest","adventure.point_of_interest.harvest"],["Terrain","terrain.mountain_range.harvest"],["Party","markers.party_position.v1"],["Visited","markers.visited.v1"],["Reported position","markers.unknown.v1"],["Notes","markers.annotation.v1"],["Unknown ground","decor.fog_hatch.harvest"]]:
		var row = hbox(legend,7)
		var image = TextureRect.new()
		image.texture = art.texture(entry[1])
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(37,25)
		row.add_child(image)
		label(row,entry[0],16)
	var travel_legend = label(legend,"—  Actual committed travel",16)
	travel_legend.add_theme_color_override("font_color",RED)
	label(legend,"- -  Known route / border",15)
	label(legend,"≈  Approximate distance",15)
	label(col,"Fog is illustrative. No surveyed-area denominator is available.",14)

func build_journal() -> void:
	var page = vbox(tabs,4)
	page.name = "Journal"
	label(page,"Known locations",20)
	location_list = ItemList.new()
	location_list.custom_minimum_size = Vector2(0,110)
	location_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	location_list.item_selected.connect(func(index: int): select_location(str(location_list.get_item_metadata(index))))
	location_list.item_activated.connect(func(index: int): focus_selected(str(location_list.get_item_metadata(index))))
	page.add_child(location_list)
	button(page,"All known locations",populate_locations)
	details = rich(page,130)
	var actions = hbox(page,3)
	button(actions,"Centre",func(): focus_selected(selected_id))
	open_region_button = button(actions,"Open region",open_region)
	open_region_button.disabled = true
	travel_button = button(page,"Travel intention",request_travel)
	travel_button.disabled = true
	travel_button.tooltip_text = "Turn controller not connected. No movement can be submitted."
	label(page,"Location annotation (not world canon)",15)
	note_box = TextEdit.new()
	note_box.custom_minimum_size.y = 56
	note_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	note_box.placeholder_text = "Write a note..."
	page.add_child(note_box)
	note_button = button(page,"Save annotation",save_annotation)
	note_button.disabled = true

func build_history() -> void:
	var page = vbox(tabs)
	page.name = "History"
	label(page,"Committed journeys",20)
	history_box = rich(page,250)

func status(message: String) -> void:
	state_label.text = message

func refresh_map(refit: bool = false) -> void:
	var old_region = canvas.region_id
	var old_selected = selected_id
	var had_geometry = canvas.has_geometry()
	stash_note()
	load_generation += 1
	var generation = load_generation
	is_loading = true
	refresh_button.disabled = true
	selected_id = ""
	selected_region = ""
	note_box.clear()
	measure_mode = false
	model.start(campaign_id)
	canvas.set_snapshot({},false)
	location_list.clear()
	region_select.clear()
	region_select.add_item("World overview")
	region_select.set_item_metadata(0,"")
	center_button.disabled = true
	open_region_button.disabled = true
	travel_button.disabled = true
	note_button.disabled = true
	details.text = "Loading committed player-visible geography..."
	history_box.text = ""
	status("Reading committed map. No world generation or migration.")
	await get_tree().process_frame
	while generation==load_generation and is_inside_tree():
		var result = model.fetch_next()
		if result=="more":
			status("Reading map pages: "+str(model.next_page))
			await get_tree().process_frame
			continue
		is_loading = false
		refresh_button.disabled = false
		if result=="error":
			details.text = model.error
			status("World map unavailable. "+model.error+" No save migration has been attempted.")
			return
		canvas.set_snapshot(model.data,false)
		canvas.region_id = old_region if canvas.regions.has(old_region) else ""
		if refit or not had_geometry:
			canvas.fit()
		else:
			canvas.queue_redraw()
		populate_regions()
		populate_locations()
		populate_history()
		center_button.disabled = not (model.data.get("party_location") is Dictionary and MODEL.positioned(model.data["party_location"]))
		var party = model.data.get("party_location")
		var party_name = str(party.get("name","")) if party is Dictionary else "Unestablished"
		status("Party: "+party_name+"  ·  "+str(model.data["locations"].size())+" known locations  ·  Revision "+str(model.revision)+"  ·  Explored area not quantified")
		if canvas.places.has(old_selected) and canvas.in_region(canvas.places[old_selected]):
			select_location(old_selected,false)
		elif not canvas.region_id.is_empty():
			select_region_info(canvas.region_id)
		elif party is Dictionary:
			select_location(str(party["id"]),false)
		else:
			details.text = "No visible party location established."
		return

func populate_regions() -> void:
	scope_sync = true
	region_select.clear()
	region_select.add_item("World overview")
	region_select.set_item_metadata(0,"")
	for row in model.data.get("terrain_regions",[]):
		region_select.add_item(str(row.get("name","Region")))
		region_select.set_item_metadata(region_select.item_count-1,row["id"])
	scope_sync = false
	sync_scope()

func sync_scope() -> void:
	if not is_instance_valid(region_select):
		return
	scope_sync = true
	for i in range(region_select.item_count):
		if region_select.get_item_metadata(i)==canvas.region_id:
			region_select.select(i)
			break
	scope_label.text = "World overview" if canvas.region_id.is_empty() else "Regional atlas"
	scope_sync = false

func change_region(index: int) -> void:
	if scope_sync or is_loading:
		return
	canvas.set_region(str(region_select.get_item_metadata(index)))
	populate_locations()
	if not canvas.region_id.is_empty():
		select_region_info(canvas.region_id)
	else:
		stash_note()
		selected_id = ""
		selected_region = ""
		note_box.clear()
		canvas.selected_id = ""
		canvas.queue_redraw()
		open_region_button.disabled = true
		travel_button.disabled = true
		note_button.disabled = true
		details.text = "World overview. Select a known location."

func populate_locations() -> void:
	location_list.clear()
	for row in model.data.get("locations",[]):
		if canvas.in_region(row):
			append_location(row)

func append_location(row: Dictionary) -> void:
	location_list.add_item(str(row.get("name","Unnamed"))+" · "+str(row.get("status",""))+("" if MODEL.positioned(row) else " (unplaced)"))
	location_list.set_item_metadata(location_list.item_count-1,row["id"])

func search_locations() -> void:
	if is_loading or model.data.is_empty():
		return
	var query = search_box.text.strip_edges()
	if query.is_empty():
		populate_locations()
		tabs.current_tab = 1
		return
	var reply = model.search(query)
	if not reply.get("ok",false):
		status(str(reply.get("error","Search failed.")))
		return
	location_list.clear()
	for row in reply.get("locations",[]):
		if MODEL.visible(row) and canvas.places.has(row.get("id")):
			append_location(canvas.places[row["id"]])
	tabs.current_tab = 1
	status(str(location_list.item_count)+" visible search results (up to 128). Double-click to centre positioned entries.")

func name_for(id: Variant) -> String:
	return str(canvas.places.get(id,{}).get("name","Unresolved"))

func human(value: Variant) -> String:
	return "Unknown" if value==null or str(value).is_empty() else str(value).replace("_"," ").capitalize()

func stash_note() -> void:
	if not selected_id.is_empty() and is_instance_valid(note_box):
		note_drafts[selected_id] = note_box.text

func select_location(id: String, switch_tab: bool = true) -> void:
	if not canvas.places.has(id):
		return
	if id!=selected_id:
		stash_note()
		note_box.text = str(note_drafts.get(id,""))
	selected_id = id
	selected_region = ""
	canvas.selected_id = id
	canvas.queue_redraw()
	var row = canvas.places[id]
	if switch_tab:
		tabs.current_tab = 1
	for i in range(location_list.item_count):
		if location_list.get_item_metadata(i)==id:
			location_list.select(i)
			break
	var lines: PackedStringArray = [str(row.get("name","")),human(row.get("kind"))+" · "+human(row.get("status")),""]
	var description = str(row.get("public_description",""))
	if not description.is_empty():
		lines.append(description)
	lines.append("Position: "+human(row.get("precision")))
	if MODEL.positioned(row):
		lines.append("East "+str(row["x"])+" mi; North "+str(row["y"])+" mi")
		lines.append("Uncertainty: "+str(row["uncertainty_miles"])+" mi")
	else:
		lines.append("Coordinates not established; no point plotted.")
	if row.get("terrain")!=null:
		lines.append("Terrain: "+human(row.get("terrain")))
	if row.get("elevation_feet")!=null:
		lines.append("Elevation: "+str(row["elevation_feet"])+" ft")
	lines.append("Occupancy: "+human(row.get("occupancy")))
	if row.get("population")!=null:
		lines.append("Population: "+str(row["population"]))
	if row.get("parent_id")!=null:
		lines.append("Within: "+name_for(row["parent_id"]))
	if canvas.regions.has(row.get("region_id")):
		lines.append("Region: "+str(canvas.regions[row["region_id"]]["name"]))
	for alias in model.data.get("aliases",[]):
		if alias.get("location_id")==id:
			lines.append("Also known as: "+str(alias["alias"]))
	for relation in model.data.get("relationships",[]):
		if relation.get("from_id")==id or relation.get("to_id")==id:
			var outgoing = relation["from_id"]==id
			var other = relation["to_id"] if outgoing else relation["from_id"]
			var relation_text = name_for(relation["from_id"])+" "+human(relation.get("kind"))+" "+name_for(relation["to_id"])
			if relation.get("direction")!=null:
				relation_text += " ("+str(relation["direction"])+")"
			if relation.get("distance_miles")!=null:
				relation_text += " · "+str(relation["distance_miles"])+" mi ("+human(relation.get("precision"))+")"
			lines.append(relation_text)
	for route in model.data.get("routes",[]):
		if route.get("from_id")==id or route.get("to_id")==id:
			var other = route["to_id"] if route["from_id"]==id else route["from_id"]
			lines.append("Route: "+str(route.get("name",""))+" → "+name_for(other)+" · "+(str(route["distance_miles"])+" mi" if route.get("distance_miles")!=null else "length unknown"))
	for note in model.data.get("annotations",[]):
		if note.get("location_id")==id:
			lines.append("Note: "+str(note.get("text","")))
	details.text = "\n".join(lines)
	note_button.disabled = false
	open_region_button.disabled = not canvas.regions.has(row.get("region_id"))
	var party = model.data.get("party_location")
	travel_button.disabled = not intent_handler.is_valid() or not party is Dictionary or party.get("id")==id
	travel_button.tooltip_text = "Submit destination intention only; movement requires turn resolution." if not travel_button.disabled else "Turn controller unavailable or already at this location."
	if measure_mode:
		measure_pick(id)

func select_region_info(id: String) -> void:
	if not canvas.regions.has(id):
		return
	stash_note()
	selected_id = ""
	note_box.clear()
	canvas.selected_id = ""
	canvas.queue_redraw()
	selected_region = id
	var row = canvas.regions[id]
	tabs.current_tab = 1
	details.text = str(row.get("name","Region"))+"\n"+human(row.get("kind"))+" · "+human(row.get("status"))+"\n"+str(row.get("public_description",""))+"\nBoundary: "+human(row.get("precision"))+"\nLocal settlement/interior/tactical frames are not available in MapView v1."
	note_button.disabled = true
	travel_button.disabled = true
	open_region_button.disabled = false

func open_region() -> void:
	var id = selected_region
	if canvas.places.has(selected_id):
		var value = canvas.places[selected_id].get("region_id")
		id = str(value) if value!=null else ""
	if not id.is_empty() and canvas.regions.has(id):
		canvas.set_region(id)
		populate_locations()
		select_region_info(id)

func focus_selected(id: String) -> void:
	var old_region = canvas.region_id
	if not canvas.focus_place(id):
		status("This location has no established position.")
	else:
		if canvas.region_id!=old_region:
			populate_locations()
		select_location(id,false)

func focus_party() -> void:
	var old_region = canvas.region_id
	if not canvas.center_party():
		status("Party location is known by name only; no position to centre.")
		return
	if canvas.region_id!=old_region:
		populate_locations()
	select_location(str(model.data["party_location"]["id"]),false)

func toggle_measure() -> void:
	measure_mode = not measure_mode
	canvas.measurement.clear()
	canvas.queue_redraw()
	status("Measure: choose two positioned locations. Straight-line miles only." if measure_mode else "Measurement cleared.")

func measure_pick(id: String) -> void:
	if not MODEL.positioned(canvas.places[id]) or not canvas.in_region(canvas.places[id]):
		status("Measurement requires two established positions within the displayed map.")
		return
	if canvas.measurement.size()>=2:
		canvas.measurement.clear()
	if not canvas.measurement.is_empty() and canvas.measurement[0]==id:
		return
	canvas.measurement.append(id)
	canvas.queue_redraw()
	if canvas.measurement.size()==2:
		var result = MODEL.measure(canvas.places[canvas.measurement[0]],canvas.places[id])
		status("Straight-line: "+str(snappedf(result["miles"],0.01))+" mi (± up to "+str(snappedf(result["uncertainty"],0.01))+" mi); not route length.")
	else:
		status("Measure from "+name_for(id)+": select a second known position.")

func show_note_editor() -> void:
	tabs.current_tab = 1
	if selected_id.is_empty():
		status("Select a known location before writing a note.")
	else:
		note_box.grab_focus()

func save_annotation() -> void:
	if is_loading or selected_id.is_empty():
		return
	var value = note_box.text.strip_edges()
	if value.is_empty() or value.length()>1000:
		status("A note must contain 1–1000 characters.")
		return
	var result = model.annotate(selected_id,value)
	if not result.get("ok",false):
		status(str(result.get("error","Annotation was not saved.")))
		return
	note_box.clear()
	note_drafts.erase(selected_id)
	refresh_map(false)

func populate_history() -> void:
	var lines: PackedStringArray = []
	for row in model.data.get("travel",[]):
		var line = "Turn "+str(row.get("turn_number"))+" · "+name_for(row.get("from_id"))+" → "+name_for(row.get("to_id"))
		line += "\n"+(str(row["distance_miles"])+" mi" if row.get("distance_miles")!=null else "Distance unknown")
		if row.get("elapsed_seconds")!=null:
			line += " · "+str(row["elapsed_seconds"])+" seconds"
		if canvas.travel_points.get(MODEL.segment_key(row),[]).size()<2:
			line += " · no established path geometry"
		lines.append(line)
	history_box.text = "\n\n".join(lines) if not lines.is_empty() else "No committed journeys yet."

func request_travel() -> void:
	if not intent_handler.is_valid() or is_loading or not canvas.places.has(selected_id):
		status("Turn controller unavailable; no travel intention submitted.")
		return
	var party = model.data.get("party_location")
	if not party is Dictionary or party.get("id")==selected_id:
		return
	# Future controller must revalidate campaign, revision, actor and destination.
	# This is not ActionSubmission, receipt, a route choice or resolved movement.
	intent_handler.call({"kind":"travel_intention","campaign_id":campaign_id,"expected_revision":model.revision,"destination_id":selected_id})
	status("Travel intention forwarded for controller validation. No map movement applied.")

func toggle_fullscreen() -> void:
	var root_size = Vector2i(get_parent().get_viewport().get_visible_rect().size) if get_parent() is Control else get_tree().root.size
	if not fullscreen_map:
		normal_size = size
		normal_position = position
		fullscreen_map = true
		size = root_size
		position = Vector2i.ZERO
		fullscreen_button.text = "Restore"
	else:
		fullscreen_map = false
		size = normal_size
		position = normal_position
		fullscreen_button.text = "Fullscreen"
