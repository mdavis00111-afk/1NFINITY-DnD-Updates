extends Control
## Fixed-scale character sheet with portrait roster and bottom-left actions.
const STORE = preload("res://players/character_store.gd")
const SHEET = preload("res://players/full_character_sheet.gd")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const TITLE = preload("res://art/sheet_title.png")
const SHEET_ART = preload("res://art/sheet_reference.jpg")
const SHEET_WIDTH = 1103.0
const SHEET_HEIGHT = 1426.0
const VIEWER_GUTTER = 24.0
const SHEET_SCALE = 0.70
const PORTRAIT_ART = preload("res://players/portrait_art.gd")
const SERIF = preload("res://themes/fonts/EBGaramond.ttf")
var store = STORE.new()
var on_edit: Callable
var on_exit: Callable
var on_browser: Callable
var roster_scroll: ScrollContainer
var roster: VBoxContainer
var roster_buttons: Array[Button] = []
var toolbar: HBoxContainer
var body: VBoxContainer
var info: TextEdit
var note: Label
var scroll: ScrollContainer
var popup: AcceptDialog
var records: Array = []
var active: Dictionary = {}
var edit_button: Button
var archive_button: Button
var sheet_extent: Control
var canvas: PanelContainer

func configure(edit: Callable,exit: Callable,browse: Callable) -> void:
	on_edit = edit
	on_exit = exit
	on_browser = browse

func style(lit: bool = false) -> StyleBoxTexture:
	var s = StyleBoxTexture.new()
	s.texture = ACTIVE if lit else FRAME
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		s.set_texture_margin(edge,22)
		s.set_content_margin(edge,5)
	return s

func label_text(t: String,n: int = 21) -> Label:
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size",n)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func button(parent: Container,t: String,cb: Callable) -> Button:
	var b = Button.new()
	b.text = t
	b.custom_minimum_size.y = 38
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size",16)
	b.add_theme_stylebox_override("normal",style())
	b.add_theme_stylebox_override("hover",style(true))
	b.add_theme_stylebox_override("pressed",style(true))
	b.add_theme_stylebox_override("focus",style(true))
	b.add_theme_stylebox_override("disabled",style())
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _ready() -> void:
	build_layout.call_deferred()

func build_layout() -> void:
	var manager_theme = load("res://themes/master_theme.tres").duplicate() as Theme
	manager_theme.default_font = SERIF
	manager_theme.default_font_size = 19
	theme = manager_theme
	var margin = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,12)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation",8)
	margin.add_child(root)
	var title = label_text("Character Management",32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	var side = PanelContainer.new()
	side.custom_minimum_size.x = 226
	side.add_theme_stylebox_override("panel",sheet_frame())
	content.add_child(side)
	var sidebar = VBoxContainer.new()
	sidebar.add_theme_constant_override("separation",6)
	side.add_child(sidebar)
	var heading = label_text("Saved Characters",23)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar.add_child(heading)
	roster_scroll = ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(roster_scroll)
	roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation",6)
	roster_scroll.add_child(roster)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	content.add_child(scroll)
	for bar in [scroll.get_v_scroll_bar(),roster_scroll.get_v_scroll_bar()]:
		bar.add_theme_stylebox_override("scroll",scrollbar_style(Color("#101b2b")))
		bar.add_theme_stylebox_override("grabber",scrollbar_style(Color("#9e7037")))
		bar.add_theme_stylebox_override("grabber_highlight",scrollbar_style(Color("#e2b66a")))
		bar.add_theme_stylebox_override("grabber_pressed",scrollbar_style(Color("#ffda88")))
	sheet_extent = Control.new()
	sheet_extent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_extent.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(sheet_extent)
	canvas = PanelContainer.new()
	canvas.add_theme_stylebox_override("panel",sheet_frame())
	sheet_extent.add_child(canvas)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	canvas.add_child(body)
	canvas.minimum_size_changed.connect(update_sheet_extent.call_deferred)
	scroll.resized.connect(update_sheet_extent.call_deferred)
	sheet_extent.resized.connect(update_sheet_extent.call_deferred)
	note = label_text("",17)
	note.visible = false
	root.add_child(note)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation",8)
	toolbar.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(toolbar)
	button(toolbar,"Exit",func(): on_exit.call()).custom_minimum_size.x = 94
	edit_button = button(toolbar,"Edit Character",func():
		if not active.is_empty(): on_edit.call(active))
	edit_button.custom_minimum_size.x = 148
	archive_button = button(toolbar,"Archive",delete_selected)
	archive_button.custom_minimum_size.x = 112
	button(toolbar,"Rules Catalogue",func(): on_browser.call()).custom_minimum_size.x = 148
	popup = AcceptDialog.new()
	popup.title = "Reference"
	popup.min_size = Vector2i(460,300)
	add_child(popup)
	popup.get_ok_button().text = "Close"
	info = TextEdit.new()
	info.editable = false
	info.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	info.custom_minimum_size = Vector2(420,240)
	info.add_theme_font_size_override("font_size",17)
	info.add_theme_color_override("font_readonly_color",Color("#fff0cf"))
	popup.add_child(info)
	refresh()


func scrollbar_style(color: Color) -> StyleBoxFlat:
	var surface = StyleBoxFlat.new()
	surface.bg_color = color
	surface.set_corner_radius_all(4)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		surface.set_content_margin(edge,4)
	return surface

func sheet_frame() -> StyleBoxFlat:
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color("#0b1628")
	frame.border_color = Color("#c39049")
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(12)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		frame.set_content_margin(edge,14)
	return frame

func sheet_scale() -> float:
	var reserved = scroll.get_v_scroll_bar().get_combined_minimum_size().x
	return minf(SHEET_SCALE,maxf(0.1,(scroll.size.x-reserved-VIEWER_GUTTER)/maxf(SHEET_WIDTH,canvas.size.x)))

func update_sheet_extent() -> void:
	if not is_instance_valid(canvas): return
	var has_sheet = not active.is_empty()
	var dimensions = Vector2(SHEET_WIDTH,SHEET_HEIGHT) if has_sheet else Vector2(minf(maxf(scroll.size.x - VIEWER_GUTTER,160.0),SHEET_WIDTH),0.0)
	canvas.custom_minimum_size = dimensions
	var actual = dimensions.max(canvas.get_combined_minimum_size())
	if canvas.size != actual: canvas.size = actual
	var factor = sheet_scale() if has_sheet else minf(1.0,sheet_scale())
	canvas.scale = Vector2.ONE * factor
	sheet_extent.custom_minimum_size = Vector2(0.0,ceilf(canvas.size.y*factor))
	canvas.position = Vector2(maxf(0.0,(sheet_extent.size.x-canvas.size.x*factor)*0.5),0.0)

func show_reference(title_text: String, description: String) -> void:
	popup.title = title_text
	info.text = description
	popup.popup_centered(Vector2i(650,490))

func set_note(value: String) -> void:
	note.text = value
	note.visible = not value.is_empty()

func refresh() -> void:
	records = store.list_records()
	set_note(store.last_error)
	active = {}
	edit_button.disabled = records.is_empty()
	archive_button.disabled = records.is_empty()
	rebuild_roster()
	if not records.is_empty():
		select_record(0)
	else:
		clear_body()
		body.add_child(label_text("No characters saved yet. Create one in Player Manager.",24))
		update_sheet_extent.call_deferred()

func rebuild_roster() -> void:
	for child in roster.get_children():
		roster.remove_child(child)
		child.queue_free()
	roster_buttons.clear()
	var group = ButtonGroup.new()
	for i in range(records.size()):
		var rec = records[i]
		var suffix = "\nDraft" if rec.get("status")=="draft" else ("\nReview" if rec.get("status")=="needs_review" else "")
		var index = i
		var entry = button(roster,str(rec.get("name","Unnamed"))+suffix,func(): select_record(index))
		entry.toggle_mode = true
		entry.button_group = group
		entry.icon = PORTRAIT_ART.texture_for(str(rec.get("portrait",rec.get("draft",{}).get("portrait",""))))
		entry.expand_icon = true
		entry.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.add_theme_constant_override("icon_max_width",57)
		entry.custom_minimum_size.y = 76
		entry.tooltip_text = str(rec.get("name","Unnamed")).left(100)
		roster_buttons.append(entry)
	if records.is_empty():
		roster.add_child(label_text("No saved characters",17))


func clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

func select_record(i: int) -> void:
	if i < 0 or i >= records.size():
		return
	active = records[i]
	for index in range(roster_buttons.size()):
		roster_buttons[index].set_pressed_no_signal(index==i)
	edit_button.disabled = false
	archive_button.disabled = false
	clear_body()
	var logo = TextureRect.new()
	logo.texture = TITLE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size.y = 151
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(logo)
	header_scenery(logo,Rect2(7,6,263,72),false)
	header_scenery(logo,Rect2(838,6,242,146),true)
	var sheet = SHEET.new()
	sheet.configure(active,show_reference)
	body.add_child(sheet)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	# The existing sheet artwork's scenic footer begins below its sample notes.
	body.add_child(sheet_art(Rect2(8,1292,1072,107),102))
	update_sheet_extent.call_deferred()
	edit_button.text = "Resume Draft" if not active.has("combat") else "Edit Character"
	scroll.set_deferred("scroll_vertical",0)

func sheet_art(region: Rect2, artwork_height: float) -> TextureRect:
	var artwork = TextureRect.new()
	var crop = AtlasTexture.new()
	crop.atlas = SHEET_ART
	crop.region = region
	artwork.texture = crop
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_SCALE
	artwork.custom_minimum_size.y = artwork_height
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return artwork

func header_scenery(logo: TextureRect, region: Rect2, right: bool) -> void:
	var artwork = sheet_art(region,region.size.y)
	logo.add_child(artwork)
	artwork.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT)
	artwork.offset_left = -region.size.x if right else 0.0
	artwork.offset_right = 0.0 if right else region.size.x
	artwork.offset_bottom = region.size.y

func delete_selected() -> void:
	if active.is_empty():
		return
	var id = str(active["id"])
	var dialog = ConfirmationDialog.new()
	dialog.title = "Archive character?"
	dialog.dialog_text = "Archive "+str(active.get("name","Unnamed"))+"? Its save will be retained."
	add_child(dialog)
	dialog.confirmed.connect(func():
		var error = store.archive(id)
		dialog.queue_free()
		refresh()
		set_note("Character archived." if error.is_empty() else error))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
