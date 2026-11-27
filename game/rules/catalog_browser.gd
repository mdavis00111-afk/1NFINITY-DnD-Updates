extends Control
const CAT=preload("res://rules/catalog.gd")
const FRAME=preload("res://themes/parts/frame.png")
var cat=CAT.new()
var exit_action: Callable
var table: OptionButton
var search: LineEdit
var results: ItemList
var detail: TextEdit
var filtered: Array = []

func configure(on_exit: Callable) -> void:
	exit_action=on_exit

func _ready() -> void:
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
	for id in CAT.TABLES:
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
	detail=TextEdit.new()
	detail.editable=false
	detail.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio=1.5
	detail.add_theme_font_size_override("font_size",19)
	columns.add_child(detail)
	table.item_selected.connect(func(_i: int): refresh())
	search.text_changed.connect(func(_s: String): refresh())
	results.item_selected.connect(func(i: int):
		if i>=0 and i<filtered.size():
			detail.text=cat.describe(str(table.get_item_metadata(table.selected)),str(filtered[i]["index"])))
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
	for rec in cat.rows(id):
		var name=str(rec.get("name",rec.get("index","")))
		if q.is_empty() or name.to_lower().contains(q):
			filtered.append(rec)
			results.add_item(name)
	detail.text=str(filtered.size())+" entries. Select one for its description. Catalogue is SRD 5.1 plus 2018 supplements, not the entire Player's Handbook."
