extends Control
## Full-width sheet viewer. Character selection and management stay in a compact toolbar.
const STORE = preload("res://players/character_store.gd")
const SHEET = preload("res://players/full_character_sheet.gd")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const FLOURISH = preload("res://themes/gold_flourish.svg")
const TITLE = preload("res://art/sheet_title.png")
var store = STORE.new()
var on_edit: Callable
var on_exit: Callable
var on_browser: Callable
var list: OptionButton
var body: VBoxContainer
var info: TextEdit
var note: Label
var scroll: ScrollContainer
var popup: AcceptDialog
var records: Array = []
var active: Dictionary = {}
var edit_button: Button
var archive_button: Button

func configure(edit: Callable,exit: Callable,browse: Callable) -> void:
	on_edit = edit
	on_exit = exit
	on_browser = browse

func style(lit: bool = false) -> StyleBoxTexture:
	var s = StyleBoxTexture.new()
	s.texture = ACTIVE if lit else FRAME
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		s.set_texture_margin(edge,22)
		s.set_content_margin(edge,10)
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
	b.custom_minimum_size.y = 36
	b.add_theme_font_size_override("font_size",19)
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
	var margin = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,18)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation",7)
	margin.add_child(root)
	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation",6)
	root.add_child(toolbar)
	list = OptionButton.new()
	list.custom_minimum_size = Vector2(205,36)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.fit_to_longest_item = false
	list.add_theme_font_size_override("font_size",20)
	list.add_theme_stylebox_override("normal",style())
	list.add_theme_stylebox_override("hover",style(true))
	list.item_selected.connect(select_record)
	toolbar.add_child(list)
	edit_button = button(toolbar,"Edit Character",func():
		if not active.is_empty():
			on_edit.call(active))
	archive_button = button(toolbar,"Archive",delete_selected)
	button(toolbar,"Rules Catalogue",func(): on_browser.call())
	button(toolbar,"Exit",func(): on_exit.call())
	note = label_text("",17)
	note.visible = false
	root.add_child(note)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	scroll.add_child(body)
	popup = AcceptDialog.new()
	popup.title = "Reference"
	popup.min_size = Vector2i(540,390)
	add_child(popup)
	popup.get_ok_button().text = "Close"
	info = TextEdit.new()
	info.editable = false
	info.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	info.custom_minimum_size = Vector2(510,340)
	info.add_theme_font_size_override("font_size",20)
	info.add_theme_color_override("font_readonly_color",Color("#fff0cf"))
	popup.add_child(info)
	refresh()

func show_reference(title_text: String, description: String) -> void:
	popup.title = title_text
	info.text = description
	popup.popup_centered(Vector2i(650,490))

func set_note(value: String) -> void:
	note.text = value
	note.visible = not value.is_empty()

func refresh() -> void:
	list.clear()
	list.disabled = false
	records = store.list_records()
	if not store.last_error.is_empty():
		set_note(store.last_error)
	for rec in records:
		var suffix = " (Draft)" if rec.get("status")=="draft" else (" (Review)" if rec.get("status")=="needs_review" else "")
		list.add_item(str(rec.get("name","Unnamed"))+suffix)
	active = {}
	edit_button.disabled = records.is_empty()
	archive_button.disabled = records.is_empty()
	if not records.is_empty():
		list.select(0)
		select_record(0)
	else:
		list.add_item("No saved characters")
		list.disabled = true
		clear_body()
		body.add_child(label_text("No characters saved yet. Create one in Player Manager.",24))

func clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

func select_record(i: int) -> void:
	if i < 0 or i >= records.size():
		return
	active = records[i]
	clear_body()
	var logo = TextureRect.new()
	logo.texture = TITLE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size.y = 116
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(logo)
	var sheet = SHEET.new()
	sheet.configure(active,show_reference)
	body.add_child(sheet)
	edit_button.text = "Resume Draft" if not active.has("combat") else "Edit Character"
	scroll.set_deferred("scroll_vertical",0)

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
