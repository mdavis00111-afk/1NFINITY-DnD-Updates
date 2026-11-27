extends Control
## Campaign creation, library and saved opening workspace. No turn adjudication yet.
const STORE = preload("res://campaigns/campaign_store.gd")
const PLAYERS = preload("res://players/character_store.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
const MATURITY = preload("res://campaigns/maturity_profiles.gd")
const PORTRAIT = preload("res://players/portrait_art.gd")
const GEMINI = preload("res://systems/gemini.gd")
const FONT = preload("res://themes/fonts/EBGaramond.ttf")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const GOLD = Color("#f4ce7b")
const IVORY = Color("#fff0cf")
var store = STORE.new()
var gemini
var exit_action: Callable
var settings_action: Callable
var mode = "library"
var active: Dictionary = {}
var rows: Array = []
var players: Array = []
var profiles: Array = []
var selected_player = ""
var selected_start = "tavern"
var title_input: LineEdit
var maturity_choice: OptionButton
var adult_confirmation: CheckBox
var synopsis: TextEdit
var note: Label
var resume_button: Button
var delete_button: Button
var pending_campaign = ""
var pending_metadata = ""
var opening_button: Button
var listing_error = ""
var roster_buttons: Array[Button] = []
var layout: MarginContainer

func configure(initial_mode: String, on_exit: Callable, on_settings: Callable) -> void:
	mode = initial_mode
	exit_action = on_exit
	settings_action = on_settings

func _ready() -> void:
	var local_theme = load("res://themes/master_theme.tres").duplicate() as Theme
	local_theme.default_font = FONT
	local_theme.default_font_size = 19
	theme = local_theme
	gemini = GEMINI.new()
	add_child(gemini)
	gemini.completed.connect(opening_received)
	render.call_deferred()

func surface(opacity: float = 0.58) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.065,0.115,opacity)
	style.border_color = Color(0.82,0.62,0.32,0.88)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		style.set_content_margin(edge,10)
	return style

func button_style(lit: bool = false) -> StyleBoxTexture:
	var style = StyleBoxTexture.new()
	style.texture = ACTIVE if lit else FRAME
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		style.set_texture_margin(edge,22)
		style.set_content_margin(edge,5)
	return style

func text_label(value: String, px: int = 21, centered: bool = false) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",px)
	label.add_theme_color_override("font_color",GOLD)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func action(parent: Container, caption: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(112,38)
	button.add_theme_font_size_override("font_size",18)
	button.add_theme_stylebox_override("normal",button_style())
	button.add_theme_stylebox_override("hover",button_style(true))
	button.add_theme_stylebox_override("pressed",button_style(true))
	button.add_theme_stylebox_override("focus",button_style(true))
	button.add_theme_stylebox_override("disabled",button_style())
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func column(parent: Container, gap: int = 7) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation",gap)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return box

func row(parent: Container, gap: int = 10) -> HBoxContainer:
	var box = HBoxContainer.new()
	box.add_theme_constant_override("separation",gap)
	parent.add_child(box)
	return box

func panel(parent: Container, width: float = 0.0, expand: bool = true) -> VBoxContainer:
	var box = PanelContainer.new()
	box.add_theme_stylebox_override("panel",surface())
	box.custom_minimum_size.x = width
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return column(box,8)

func scrolled(parent: Container) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 100
	parent.add_child(scroll)
	return column(scroll,7)

func art_entry(parent: Container, caption: String, picture: Texture2D, callback: Callable) -> Button:
	var button = action(parent,caption,callback)
	button.custom_minimum_size = Vector2(0,72)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = picture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width",60)
	button.toggle_mode = true
	return button

func render() -> void:
	if is_instance_valid(layout):
		remove_child(layout)
		layout.queue_free()
	layout = MarginContainer.new()
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:
		layout.add_theme_constant_override("margin_"+edge,12)
	var root = column(layout,8)
	var title = "Existing Campaigns" if mode=="library" else ("New Campaign" if mode=="new" else str(active.get("title","Campaign")))
	var title_label = text_label(title,34,true)
	title_label.max_lines_visible=2
	root.add_child(title_label)
	var body = row(root,12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	match mode:
		"new": build_new(body)
		"workspace": build_workspace(body)
		_: build_library(body)
	note = text_label("",16)
	note.max_lines_visible = 2
	note.visible = false
	root.add_child(note)
	var nav = row(root,8)
	nav.alignment = BoxContainer.ALIGNMENT_BEGIN
	action(nav,"Exit" if mode!="workspace" else "Save & Exit",leave)
	if mode=="library":
		resume_button = action(nav,"Resume",resume)
		delete_button = action(nav,"Delete",confirm_delete)
		resume_button.disabled = active.is_empty()
		delete_button.disabled = active.is_empty()
		if not listing_error.is_empty():
			show_note(listing_error)
	elif mode=="new":
		action(nav,"Content Rules",func(): settings_action.call())
		var begin = action(nav,"Create Campaign",create)
		begin.tooltip_text = "Save the campaign and open its opening workspace. Gameplay is not implemented yet."
		begin.disabled = profiles.is_empty() or players.is_empty()
		if profiles.is_empty():
			show_note("Configure maturity profiles in Content Rules first.")
		elif players.is_empty():
			show_note("Create and finalize a ready character first.")
	else:
		if not active.get("opening_committed",false) and active.get("turn",0)==0:
			opening_button = action(nav,"Generate Opening",request_opening)
			opening_button.disabled = not pending_campaign.is_empty()
		show_note("Generating opening… Saved campaign is safe." if pending_campaign==active.get("id") else "Opening workspace saved. Gameplay turn resolution is not implemented yet.")

func show_note(value: String) -> void:
	if is_instance_valid(note):
		note.text = value
		note.visible = not value.is_empty()

func leave() -> void:
	if mode=="workspace":
		mode="library"
		render()
	else:
		exit_action.call()

func read_only_text(parent: Container, value: String) -> TextEdit:
	var edit = TextEdit.new()
	edit.editable = false
	edit.text = value
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size",20)
	edit.add_theme_color_override("font_readonly_color",IVORY)
	var padding = StyleBoxEmpty.new()
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		padding.set_content_margin(edge,8)
	edit.add_theme_stylebox_override("read_only",padding)
	parent.add_child(edit)
	return edit

func build_library(parent: Container) -> void:
	var left = panel(parent,250,false)
	left.add_child(text_label("Saved Campaigns",24,true))
	var roster = scrolled(left)
	rows = store.list_campaigns()
	listing_error = store.last_error
	var previous_id = str(active.get("id",""))
	active = {}
	roster_buttons.clear()
	for i in range(rows.size()):
		var index = i
		var rec = rows[i]
		var entry = art_entry(roster,str(rec["title"]),STARTS.texture_for(str(rec.get("thumbnail_id","road"))),func(): select_campaign(index))
		roster_buttons.append(entry)
		if rec["id"]==previous_id:
			active=rec
	if active.is_empty() and not rows.is_empty():
		active=rows[0]
	if rows.is_empty():
		roster.add_child(text_label("No saved campaigns",18,true))
	var right = panel(parent)
	synopsis = read_only_text(right,"Choose a saved campaign to view its adventure log.")
	if not active.is_empty():
		update_library()

func select_campaign(index: int) -> void:
	if index<0 or index>=rows.size():
		return
	active=rows[index]
	update_library()

func update_library() -> void:
	for i in range(roster_buttons.size()):
		roster_buttons[i].set_pressed_no_signal(rows[i]["id"]==active["id"])
	var profile = MATURITY.resolve(str(active.get("maturity_id","")))
	var maturity_name = str(profile.get("name","Standard (fallback: unknown or missing profile)"))
	synopsis.text = str(active["title"])+"\n\nCharacter: "+str(active.get("player_name",""))+"\nOpening: "+str(active.get("start_name",""))+"\nMaturity: "+maturity_name+"\nTurn: "+str(active.get("turn",0))+"\n\nAdventure Synopsis\n────────────────\n\n"+store.synopsis(str(active["id"]))
	synopsis.scroll_vertical=0
	if is_instance_valid(resume_button): resume_button.disabled=false
	if is_instance_valid(delete_button): delete_button.disabled=false

func build_new(parent: Container) -> void:
	var left = panel(parent,250,false)
	left.add_child(text_label("Choose Your Character",23,true))
	var roster = scrolled(left)
	players = []
	for player in PLAYERS.new().list_records():
		if player.get("status")=="ready":
			players.append(player)
	if players.is_empty():
		roster.add_child(text_label("No ready characters",18,true))
	var player_group = ButtonGroup.new()
	var valid_selected = false
	for player in players:
		if player["id"]==selected_player: valid_selected=true
	if not valid_selected: selected_player=""
	for player in players:
		var id = str(player["id"])
		var portrait_path = str(player.get("portrait",player.get("draft",{}).get("portrait","")))
		var entry = art_entry(roster,str(player.get("name","Unnamed")),PORTRAIT.texture_for(portrait_path),func(): selected_player=id)
		entry.button_group = player_group
		if selected_player.is_empty():
			selected_player=id
		entry.set_pressed_no_signal(id==selected_player)
	var right = panel(parent)
	title_input = LineEdit.new()
	title_input.placeholder_text = "Campaign Name"
	title_input.max_length = 100
	title_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_input.custom_minimum_size.y = 38
	title_input.add_theme_stylebox_override("normal",surface(0.84))
	right.add_child(title_input)
	profiles = MATURITY.selectable_profiles()
	maturity_choice = OptionButton.new()
	maturity_choice.custom_minimum_size.y=38
	maturity_choice.add_theme_stylebox_override("normal",surface(0.84))
	for profile in profiles:
		maturity_choice.add_item(str(profile["name"]))
		maturity_choice.set_item_metadata(maturity_choice.item_count-1,profile["id"])
	maturity_choice.select(MATURITY.IDS.find(MATURITY.DEFAULT_ID))
	right.add_child(maturity_choice)
	adult_confirmation = CheckBox.new()
	adult_confirmation.text = "I confirm everyone at this table is an adult (18+)."
	adult_confirmation.visible = false
	right.add_child(adult_confirmation)
	maturity_choice.item_selected.connect(func(i: int):
		adult_confirmation.set_pressed_no_signal(false)
		adult_confirmation.visible = MATURITY.needs_adult_confirmation(str(maturity_choice.get_item_metadata(i))))
	right.add_child(text_label("Choose Your Opening",23,true))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	right.add_child(grid)
	var group = ButtonGroup.new()
	for start in STARTS.STARTS:
		var id = str(start["id"])
		var button = art_entry(grid,str(start["name"]),STARTS.texture_for(id),func(): select_start(id))
		button.button_group=group
		button.set_pressed_no_signal(id==selected_start)
	var preview = STARTS.find_start(selected_start)
	synopsis = read_only_text(right,str(preview.get("description","")))
	synopsis.custom_minimum_size.y=80

func select_start(id: String) -> void:
	selected_start=id
	var start = STARTS.find_start(id)
	synopsis.text=str(start.get("description",""))

func create() -> void:
	if not pending_campaign.is_empty():
		return
	if maturity_choice.selected<0:
		show_note("Select a maturity profile.")
		return
	var profile_id = str(maturity_choice.get_item_metadata(maturity_choice.selected))
	if MATURITY.needs_adult_confirmation(profile_id) and not adult_confirmation.button_pressed:
		show_note("Confirm an adult table before creating a Mature campaign.")
		return
	var record = store.create_campaign(title_input.text,selected_player,selected_start,profile_id)
	if record.is_empty():
		show_note(store.last_error)
		return
	active=record
	open_workspace()
	# Save first; provider failure leaves the original opening intact.
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	if gemini.key_valid(str(config.get_value("gemini","api_key","")).strip_edges()):
		request_opening()

func request_opening() -> void:
	if mode!="workspace" or active.is_empty() or not pending_campaign.is_empty():
		return
	var id = str(active["id"])
	var prepared = store.prepare_opening(id)
	if prepared.is_empty():
		show_note(store.last_error)
		return
	pending_campaign=id
	pending_metadata=prepared["previous"]
	if is_instance_valid(opening_button):
		opening_button.disabled=true
	show_note("Generating opening… Saved campaign is safe.")
	gemini.generate(prepared["prompt"])

func opening_received(ok: bool, message: String) -> void:
	var id = pending_campaign
	var previous = pending_metadata
	pending_campaign=""
	pending_metadata=""
	if id.is_empty():
		return
	var error = "Opening generation unavailable. Your saved opening is unchanged."
	if ok:
		error = store.commit_opening(id,previous,message)
	if mode=="workspace" and active.get("id")==id:
		if error.is_empty():
			var refreshed = store.load_campaign(id)
			if not refreshed.is_empty():
				active=refreshed
				render()
				show_note("Opening saved. Gameplay turn resolution is not implemented yet.")
			else:
				show_note("Opening saved. Reopen the campaign to reload it.")
		else:
			if is_instance_valid(opening_button):
				opening_button.disabled=false
			show_note(error)
	elif mode=="library":
		render()
	elif mode=="workspace" and is_instance_valid(opening_button):
		opening_button.disabled=false

func resume() -> void:
	if active.is_empty():
		return
	var record = store.load_campaign(str(active["id"]))
	if record.is_empty():
		show_note(store.last_error)
		return
	active=record
	open_workspace()

func open_workspace() -> void:
	mode="workspace"
	render()

func build_workspace(parent: Container) -> void:
	var left = panel(parent,250,false)
	var actor = store.actor_record(str(active["id"]))
	left.add_child(text_label(str(active.get("player_name","Character")),25,true))
	var picture = TextureRect.new()
	picture.texture = PORTRAIT.texture_for(str(actor.get("portrait",actor.get("draft",{}).get("portrait",""))))
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(picture)
	left.add_child(text_label(str(active.get("location_name",active.get("start_name",""))),20,true))
	var right = panel(parent)
	right.add_child(text_label("Adventure Log",24,true))
	synopsis = read_only_text(right,store.synopsis(str(active["id"])))
	var profile = MATURITY.resolve(str(active.get("maturity_id","")))
	if profile.is_empty():
		right.add_child(text_label("Maturity profile missing. Restore it in Settings before gameplay.",17))
	else:
		right.add_child(text_label("Maturity: "+str(profile["name"]),17))

func confirm_delete() -> void:
	if active.is_empty():
		return
	var id = str(active["id"])
	var dialog = ConfirmationDialog.new()
	dialog.title="Delete campaign?"
	dialog.dialog_text="Delete "+str(active["title"])+" from your campaign list? A recovery copy will remain."
	add_child(dialog)
	dialog.get_ok_button().text="Delete"
	dialog.confirmed.connect(func():
		var error = store.delete_campaign(id)
		dialog.queue_free()
		if error.is_empty():
			active={}
			render()
			show_note("Campaign deleted.")
		else:
			show_note(error))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
