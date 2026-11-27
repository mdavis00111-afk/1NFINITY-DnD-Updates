extends Control
const SQL=preload("res://systems/sqlite.gd")
const CAT=preload("res://rules/catalog.gd")
const ASSETS=preload("res://systems/asset_library.gd")
const FRAME=preload("res://themes/parts/panel_gold.png")
var cat=CAT.new()
var assets=ASSETS.new()
var preview: TextureRect
var open_sheet: Button
var selected_sheet: String = ""
var exit_action: Callable
var table: OptionButton
var search: LineEdit
var results: ItemList
var detail: TextEdit
var filtered: Array = []

func configure(on_exit: Callable) -> void:
	exit_action=on_exit

func _ready() -> void:
	build_layout.call_deferred()

func build_layout() -> void:
	var m=MarginContainer.new()
	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		m.add_theme_constant_override("margin_"+side,25)
	var panel=PanelContainer.new()
	var dark=StyleBoxFlat.new()
	dark.bg_color=Color(0.025,0.045,0.08,0.96)
	panel.add_theme_stylebox_override("panel",dark)
	m.add_child(panel)
	var frame=PanelContainer.new()
	var style=StyleBoxTexture.new()
	style.texture=FRAME
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(edge,20)
		style.set_content_margin(edge,16)
	frame.add_theme_stylebox_override("panel",style)
	panel.add_child(frame)
	var root=VBoxContainer.new()
	frame.add_child(root)
	var heading=Label.new()
	heading.text="Original 5e Rules Catalogue — 2014 / 2018"
	heading.add_theme_font_size_override("font_size",30)
	root.add_child(heading)
	var top=HBoxContainer.new()
	root.add_child(top)
	table=OptionButton.new()
	for id in CAT.TABLES + ["token-art","sheet-templates","book-pages"]:
		table.add_item(id.replace("-"," ").capitalize())
		table.set_item_metadata(table.item_count-1,id)
	top.add_child(table)
	search=LineEdit.new()
	search.placeholder_text="Search by name"
	search.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(search)
	var columns=HBoxContainer.new()
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	results=ItemList.new()
	results.custom_minimum_size.x=300
	results.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	results.size_flags_stretch_ratio=0.8
	columns.add_child(results)
	var right = VBoxContainer.new()
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio=1.5
	columns.add_child(right)
	preview=TextureRect.new()
	preview.custom_minimum_size=Vector2(150,160)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.hide()
	right.add_child(preview)
	open_sheet=Button.new()
	open_sheet.text="Open original PDF"
	open_sheet.hide()
	open_sheet.pressed.connect(open_selected_sheet)
	right.add_child(open_sheet)
	detail=TextEdit.new()
	detail.editable=false
	detail.add_theme_color_override("font_readonly_color",Color("#fff0cf"))
	detail.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical=Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("font_size",19)
	right.add_child(detail)
	table.item_selected.connect(func(_i: int): refresh())
	search.text_changed.connect(func(_s: String):
		if str(table.get_item_metadata(table.selected)) != "book-pages":
			refresh())
	search.text_submitted.connect(func(_s: String): refresh())
	var find_button = Button.new()
	find_button.text = "Search"
	find_button.pressed.connect(refresh)
	top.add_child(find_button)
	results.item_selected.connect(select_entry)
	var exit=Button.new()
	exit.text="Exit"
	exit.pressed.connect(func(): exit_action.call())
	root.add_child(exit)
	refresh()

func refresh() -> void:
	results.clear()
	filtered=[]
	var id=str(table.get_item_metadata(table.selected))
	var q=search.text.strip_edges().to_lower()
	preview.hide()
	preview.texture=null
	open_sheet.hide()
	selected_sheet=""
	if id == "book-pages":
		search.placeholder_text = "Search local books; press Enter"
		search_books(q)
		return
	search.placeholder_text = "Search by name"
	var is_asset = id in ["token-art","sheet-templates"]
	var rows_to_show = assets.rows(id) if is_asset else cat.rows(id)
	for rec in rows_to_show:
		var name=str(rec.get("name",rec.get("index","")))
		if q.is_empty() or name.to_lower().contains(q):
			filtered.append(rec)
			results.add_item(name)
	var message = assets.error if is_asset else cat.last_error
	detail.text=message if not message.is_empty() else str(filtered.size())+" entries. Select one for details."

func select_entry(i: int) -> void:
	if i<0 or i>=filtered.size():
		return
	preview.hide()
	preview.texture=null
	open_sheet.hide()
	selected_sheet=""
	var category = str(table.get_item_metadata(table.selected))
	var rec: Dictionary = filtered[i]
	if category == "book-pages":
		detail.text = str(rec["title"])+" | PDF page "+str(int(rec["pdf_page"]))+"\n\n"+str(rec["body"])
	elif category == "token-art":
		preview.texture=assets.texture_for_token(rec)
		preview.visible=preview.texture != null
		detail.text=str(rec["name"])+"\n\n"+str(rec["category"])+" • "+str(rec["width"])+" × "+str(rec["height"])+"\n\n"+("Linked to creature: "+str(rec["creature_id"]) if rec["link_status"]=="exact-name" else "Artwork only. No matching original-edition creature reference is currently installed.")
	elif category == "sheet-templates":
		selected_sheet=str(rec["id"])
		open_sheet.show()
		var fields = assets.template_fields(selected_sheet)
		var lines: PackedStringArray = [str(rec["name"]),str(rec["pages"])+" pages • "+str(rec["widget_count"])+" form widgets",str(rec["role"]).capitalize(),""]
		for field in fields:
			var mapping = str(field.get("record_path","")) if field.get("record_path") != null else ""
			lines.append("p. "+str(field["page"])+" · "+str(field["field_name"])+(" → "+mapping if not mapping.is_empty() else "")+" ["+str(field["mapping_status"])+"]")
		detail.text="\n".join(lines)
	else:
		var id = str(rec["index"])
		detail.text=cat.describe(category,id)
		if category=="monsters":
			preview.texture=assets.texture_for_creature(id)
			preview.visible=preview.texture != null

func open_selected_sheet() -> void:
	var path = assets.template_path(selected_sheet)
	if not path.is_empty() and FileAccess.file_exists(path):
		OS.shell_open(path)


func search_books(q: String) -> void:
	var db_path = OS.get_executable_path().get_base_dir().path_join("reference/private_rules.db")
	if not FileAccess.file_exists(db_path):
		detail.text = "Install the local reference database at reference/private_rules.db next to the Godot executable."
		return
	if q.is_empty():
		detail.text = "Enter a word or phrase and press Enter to search the installed rulebooks."
		return
	var query = "SELECT d.title,p.pdf_page,p.body FROM reference_pages p JOIN reference_documents d ON p.document_id=d.id WHERE instr(lower(p.body),lower(?))>0 ORDER BY d.title,p.pdf_page LIMIT 100"
	var response = SQL.run(db_path,[SQL.stmt(query,[q])],true)
	if not response.get("ok",false):
		detail.text = "Book index unavailable: "+str(response.get("error","unknown error"))
		return
	var sets: Array = response.get("results",[])
	if sets.is_empty():
		detail.text = "No results."
		return
	for rec in sets[0]:
		filtered.append(rec)
		results.add_item(str(rec["title"])+" | page "+str(int(rec["pdf_page"])))
	detail.text = str(filtered.size())+" matching pages (maximum 100). Select a page to read it."
