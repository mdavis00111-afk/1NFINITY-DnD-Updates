extends Control
const CAT = preload("res://rules/catalog.gd")
const STORE = preload("res://players/character_store.gd")
const FRAME = preload("res://themes/parts/frame.png")
var cat = CAT.new()
var store = STORE.new()
var on_edit: Callable
var on_exit: Callable
var on_browser: Callable
var list: ItemList
var body: VBoxContainer
var info: TextEdit
var note: Label
var records: Array = []
var active: Dictionary = {}

func configure(edit: Callable,exit: Callable,browse: Callable) -> void:
	on_edit = edit
	on_exit = exit
	on_browser = browse

func label_text(t: String,n: int=23) -> Label:
	var l = Label.new()
	l.text=t
	l.add_theme_font_size_override("font_size",n)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return l

func button(parent: Container,t: String,cb: Callable,tip: String="") -> Button:
	var b=Button.new()
	b.text=t
	b.tooltip_text=tip
	b.add_theme_font_size_override("font_size",20)
	b.custom_minimum_size.y=32
	b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func pane(parent: Container,ratio: float) -> VBoxContainer:
	var p=PanelContainer.new()
	p.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	p.size_flags_vertical=Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio=ratio
	var dark=StyleBoxFlat.new()
	dark.bg_color=Color(0.025,0.045,0.08,0.95)
	p.add_theme_stylebox_override("panel",dark)
	parent.add_child(p)
	var frame=PanelContainer.new()
	var s=StyleBoxTexture.new()
	s.texture=FRAME
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		s.set_texture_margin(side,20)
		s.set_content_margin(side,12)
	frame.add_theme_stylebox_override("panel",s)
	p.add_child(frame)
	var v=VBoxContainer.new()
	v.add_theme_constant_override("separation",6)
	frame.add_child(v)
	return v

func _ready() -> void:
	var margin=MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,24)
	var root=VBoxContainer.new()
	margin.add_child(root)
	root.add_child(label_text("Manage Players",32))
	var columns=HBoxContainer.new()
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	var left=pane(columns,0.7)
	left.add_child(label_text("Saved Characters"))
	list=ItemList.new()
	list.custom_minimum_size.x=165
	list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	left.add_child(list)
	list.item_selected.connect(func(i: int): select_record(i))
	button(left,"Edit / Resume Draft",func():
		if not active.is_empty():
			on_edit.call(active))
	button(left,"Delete / Archive",delete_selected)
	button(left,"Rules Catalogue",func(): on_browser.call())
	button(left,"Exit",func(): on_exit.call())
	note=label_text("",17)
	left.add_child(note)
	var middle=pane(columns,1.65)
	var scroll=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	middle.add_child(scroll)
	body=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var right=pane(columns,1.0)
	right.add_child(label_text("Rules & Reference"))
	info=TextEdit.new()
	info.editable=false
	info.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	info.size_flags_vertical=Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x=240
	info.add_theme_font_size_override("font_size",18)
	right.add_child(info)
	refresh()

func refresh() -> void:
	list.clear()
	records=store.list_records()
	for rec in records:
		list.add_item(str(rec.get("name","Unnamed"))+" ["+str(rec.get("status","draft"))+"]")
	active={}
	if not records.is_empty():
		list.select(0)
		select_record(0)
	else:
		clear_body()
		body.add_child(label_text("No characters saved yet."))
		info.text="Create a character in Player Manager."

func clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

func link(table: String,id: String,caption: String="") -> void:
	var t=caption if not caption.is_empty() else cat.title(table,id)
	button(body,t,func(): info.text=cat.describe(table,id),cat.summary(table,id))

func section(title: String) -> void:
	body.add_child(HSeparator.new())
	body.add_child(label_text(title,24))

func select_record(i: int) -> void:
	if i<0 or i>=records.size():
		return
	active=records[i]
	clear_body()
	var d=active.get("draft",{})
	var row=HBoxContainer.new()
	body.add_child(row)
	var path=str(d.get("portrait",""))
	if not path.is_empty():
		var image=Image.load_from_file(path)
		if not image.is_empty():
			var portrait=TextureRect.new()
			portrait.texture=ImageTexture.create_from_image(image)
			portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size=Vector2(90,120)
			row.add_child(portrait)
	var identity=VBoxContainer.new()
	row.add_child(identity)
	identity.add_child(label_text(str(active.get("name","Unnamed")),31))
	identity.add_child(label_text("Level "+str(active.get("level",1))+" · "+str(active.get("status","draft")),18))
	for pair in [["races","race_id"],["subraces","subrace_id"],["classes","class_id"],["subclasses","subclass_id"],["backgrounds","background_id"]]:
		var id=str(d.get(pair[1],""))
		if not id.is_empty():
			link(pair[0],id)
	body.add_child(label_text(str(d.get("sex",""))+" · "+str(d.get("alignment","")),18))
	for warning in active.get("review_required",[]):
		body.add_child(label_text("Needs review: "+str(warning),17))
	if not active.has("combat"):
		body.add_child(label_text("Draft saved. Resume to complete creation.",20))
		info.text="Select a reference or resume the draft."
		return
	var c=active["combat"]
	section("Combat Statistics")
	body.add_child(label_text("AC "+str(c["armor_class"])+"   HP "+str(c["hp_current"])+"/"+str(c["hp_max"])+"   Speed "+str(c["speed_feet"])+" ft.",24))
	body.add_child(label_text("Initiative "+str(c["initiative"])+"   Passive Perception "+str(c["passive_perception"]),19))
	section("Abilities & Saving Throws")
	for id in active["ability_scores"]:
		link("ability-scores",id,id.to_upper()+"    "+str(active["ability_scores"][id])+"    Mod "+str(active["ability_modifiers"][id])+"    Save "+str(active["saving_throws"][id]))
	section("Skills")
	for id in active["skills"]:
		var s=active["skills"][id]
		link("skills",id,("◆ " if s["proficient"] else "◇ ")+cat.title("skills",id)+"  "+str(s["modifier"])+("  Expertise" if s["expertise"] else ""))
	section("Class Features & Racial Traits")
	for id in active["class_feature_ids"]:
		link("features",id)
	for id in active["racial_trait_ids"]:
		link("traits",id)
	section("Proficiencies & Languages")
	for id in active["proficiency_ids"]:
		link("proficiencies",id)
	for id in active["language_ids"]:
		link("languages",id)
	section("Spellcasting")
	var sp=active["spellcasting"]
	body.add_child(label_text("Ability "+str(sp["ability"]).to_upper()+"    Save DC "+str(sp["save_dc"])+"    Attack "+str(sp["attack_bonus"]),18))
	for key in ["cantrip_ids","racial_cantrip_ids","known_ids","prepared_ids","always_prepared_ids"]:
		if not sp[key].is_empty():
			body.add_child(label_text(key.trim_suffix("_ids").replace("_"," ").capitalize(),20))
			for id in sp[key]:
				link("spells",id)
	for level in sp["slots"]:
		var slot=sp["slots"][level]
		if int(slot["maximum"])>0:
			body.add_child(label_text("Level "+level+": "+str(int(slot["maximum"])-int(slot["spent"]))+"/"+str(slot["maximum"])+" slots",18))
	section("Equipment & Wealth")
	for item in active["inventory"]:
		var id=str(item["item_id"])
		link("equipment",id,str(item["quantity"])+" × "+cat.title("equipment",id)+(" [Equipped]" if item["equipped"] else ""))
	body.add_child(label_text(cat.human(active["coins"]),18))
	section("Personality & Background")
	for key in ["description","personality","ideal","bond","flaw","backstory"]:
		body.add_child(label_text(key.capitalize()+": "+str(active.get(key,"")),18))
	info.text="Select any highlighted reference. This character is stored under ID "+str(active["id"])+"."

func delete_selected() -> void:
	if active.is_empty():
		return
	var id=str(active["id"])
	var dialog=ConfirmationDialog.new()
	dialog.title="Archive character?"
	dialog.dialog_text="Remove "+str(active.get("name","Unnamed"))+" from the player list? Its save is retained in the local archive."
	add_child(dialog)
	dialog.confirmed.connect(func():
		var error=store.archive(id)
		note.text="Character archived." if error.is_empty() else error
		dialog.queue_free()
		refresh())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
