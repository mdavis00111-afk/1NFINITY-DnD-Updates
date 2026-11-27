extends Control
## Four horizontal character-sheet screens. Every value is live; portraits are optional.
const RULES = preload("res://rules/character_rules.gd")
const STORE = preload("res://players/character_store.gd")
const GEMINI = preload("res://systems/gemini.gd")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const PORTRAIT = preload("res://themes/parts/portrait_empty.png")
const ICONS = preload("res://themes/parts/icons.png")
const FLOURISH = preload("res://themes/gold_flourish.svg")
const GOLD = Color("#ffd989")
const IVORY = Color("#fff0cf")
const ICON_RECTS = {"armor":Rect2(0,0,34,34),"health":Rect2(50,0,42,31),"initiative":Rect2(100,0,43,36),"speed":Rect2(150,0,44,29),"wand":Rect2(200,0,27,25),"robe":Rect2(0,56,26,26),"shield":Rect2(50,56,23,24),"focus":Rect2(100,56,26,23),"pack":Rect2(150,56,24,23),"star":Rect2(200,56,13,13),"diamond":Rect2(0,112,18,17)}
var rules = RULES.new()
var store = STORE.new()
var draft: Dictionary = {}
var existing: Dictionary = {}
var step: int = 1
var quick: bool = false
var exit_action: Callable
var finish_action: Callable
var body: Control
var form: VBoxContainer
var reference: TextEdit
var scroll: ScrollContainer
var note: Label
var description_editor: TextEdit
var ai_button: Button
var gemini
var detail_text: String = "Select an option to view its details."
var pending_render: bool = false

func configure(is_quick: bool, on_exit: Callable, on_finish: Callable, saved: Dictionary = {}) -> void:
	quick = is_quick
	exit_action = on_exit
	finish_action = on_finish
	existing = saved
	draft = rules.fresh()
	draft.merge(saved.get("draft",{}),true)

func _ready() -> void:
	if draft.is_empty():
		draft = rules.fresh()
	gemini = GEMINI.new()
	add_child(gemini)
	gemini.completed.connect(description_received)
	render.call_deferred()

func frame_style(active: bool = false, margin: int = 9) -> StyleBoxTexture:
	var s = StyleBoxTexture.new()
	s.texture = ACTIVE if active else FRAME
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		s.set_texture_margin(side,22)
		s.set_content_margin(side,margin)
	return s

func heading(value: String, size_px: int = 22, color: Color = GOLD) -> Label:
	var l = Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size",size_px)
	l.add_theme_color_override("font_color",color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func centered(value: String, size_px: int = 22, color: Color = GOLD) -> Label:
	var l = heading(value,size_px,color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

func icon(key: String, size_px: int = 22) -> TextureRect:
	var view = TextureRect.new()
	var atlas = AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = ICON_RECTS.get(key,ICON_RECTS["star"])
	view.texture = atlas
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.custom_minimum_size = Vector2(size_px,size_px)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view

func flourish(parent: Container) -> void:
	var t = TextureRect.new()
	t.texture = FLOURISH
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size.y = 10
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)

func action(parent: Container, caption: String, callback: Callable, highlight: bool = false, font_size: int = 21) -> Button:
	var b = Button.new()
	b.text = caption
	b.custom_minimum_size = Vector2(74,32)
	b.add_theme_font_size_override("font_size",font_size)
	b.add_theme_stylebox_override("normal",frame_style(highlight,6))
	b.add_theme_stylebox_override("hover",frame_style(true,6))
	b.add_theme_stylebox_override("pressed",frame_style(true,6))
	b.add_theme_stylebox_override("focus",frame_style(true,6))
	b.add_theme_stylebox_override("disabled",frame_style(false,6))
	b.add_theme_color_override("font_color",IVORY)
	b.add_theme_color_override("font_disabled_color",Color("#a79b80"))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func row(parent: Container, gap: int = 6) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation",gap)
	parent.add_child(h)
	return h

func column(parent: Container, gap: int = 5) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation",gap)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	return v

func framed(parent: Container, caption: String = "", ratio: float = 1.0, icon_id: String = "star") -> VBoxContainer:
	var p = PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	p.add_theme_stylebox_override("panel",frame_style(false,10))
	parent.add_child(p)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation",5)
	p.add_child(v)
	if not caption.is_empty():
		var h = row(v)
		h.add_child(icon(icon_id,22))
		h.add_child(heading(caption,25))
		flourish(v)
	return v

func render(preserve_scroll: bool = false) -> void:
	pending_render = false
	var old_scroll = 0
	if is_instance_valid(scroll) and preserve_scroll:
		old_scroll = scroll.scroll_vertical
	if is_instance_valid(body):
		remove_child(body)
		body.queue_free()
	body = MarginContainer.new()
	add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		body.add_theme_constant_override("margin_"+side,16)
	var root = column(body,6)
	root.add_child(centered("Character Creator   ◆   "+str(step)+" / 4",38))
	flourish(root)
	var tabs = row(root,6)
	for i in range(4):
		var index = i+1
		var b = action(tabs,["Identity","Ability Scores","Skills & Spells","Loadout & Review"][i],func(): go_to(index),index==step,23)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = index>step
	var columns = row(root,7)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_column(columns)
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	center.custom_minimum_size.x = 520
	columns.add_child(center)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation",6)
	scroll.add_child(form)
	var side = framed(columns,"Reference",1.0,"wand")
	side.get_parent().custom_minimum_size.x = 245
	side.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	reference = TextEdit.new()
	reference.editable = false
	reference.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	reference.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reference.custom_minimum_size.x = 220
	reference.add_theme_font_size_override("font_size",20)
	reference.add_theme_color_override("font_readonly_color",IVORY)
	reference.add_theme_color_override("font_color",IVORY)
	reference.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	reference.add_theme_stylebox_override("read_only",StyleBoxEmpty.new())
	reference.text = detail_text
	side.add_child(reference)
	if not rules.cat.initialize():
		form.add_child(heading("Cannot open rules database",26))
		form.add_child(heading(rules.cat.last_error,19,IVORY))
	else:
		match step:
			1: identity()
			2: abilities()
			3: features()
			4: loadout()
	note = heading("",18,IVORY)
	note.custom_minimum_size.y = 24
	root.add_child(note)
	var nav = row(root,10)
	nav.alignment = BoxContainer.ALIGNMENT_END
	action(nav,"Exit",func(): exit_action.call())
	if step > 1:
		action(nav,"Back",func(): go_to(step-1))
	action(nav,"Save Draft",func(): save(false)).custom_minimum_size.x = 124
	if step < 4 and not (quick and step==1):
		action(nav,"Next",advance,true)
	elif step == 4:
		action(nav,"Save Character",func(): save(true),true).custom_minimum_size.x = 164
	if preserve_scroll:
		scroll.set_deferred("scroll_vertical",old_scroll)

func go_to(index: int) -> void:
	if index>=1 and index<=step:
		step=index
		render()

func queue_render() -> void:
	if pending_render:
		return
	pending_render = true
	render.call_deferred(true)

func show_detail(value: String) -> void:
	detail_text = value
	if is_instance_valid(reference):
		reference.text = value

func portrait_column(parent: Container) -> void:
	var p = VBoxContainer.new()
	p.custom_minimum_size.x = 174
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var image = TextureRect.new()
	image.texture = PORTRAIT
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(image)
	var path = str(draft.get("portrait",""))
	if not path.is_empty():
		var img = Image.load_from_file(path)
		if not img.is_empty():
			var actual = TextureRect.new()
			actual.texture = ImageTexture.create_from_image(img)
			actual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			actual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.add_child(actual)
			actual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			actual.offset_left=15
			actual.offset_right=-15
			actual.offset_top=25
			actual.offset_bottom=-25
	if step==1 and not quick:
		action(p,"Choose Portrait",choose_portrait,false,17)
		if not path.is_empty():
			action(p,"Clear",func(): draft["portrait"]=""; queue_render(),false,17)
	else:
		p.add_child(centered(str(draft.get("name","")),20))
		p.add_child(centered("Level 1",18))

func choose_portrait() -> void:
	var picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Portrait images"])
	add_child(picker)
	picker.file_selected.connect(func(path: String): draft["portrait"]=path; picker.queue_free(); queue_render())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.8)

func text_field(parent: Container, key: String, placeholder: String, multi: bool = false, height: int = 32) -> Control:
	if multi:
		var edit = TextEdit.new()
		edit.placeholder_text = placeholder
		edit.text = str(draft.get(key,""))
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.custom_minimum_size.y = height
		edit.add_theme_stylebox_override("normal",frame_style(false,7))
		edit.add_theme_stylebox_override("focus",frame_style(true,7))
		edit.add_theme_font_size_override("font_size",20)
		edit.text_changed.connect(func(): draft[key]=edit.text)
		parent.add_child(edit)
		return edit
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = str(draft.get(key,""))
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = height
	edit.add_theme_stylebox_override("normal",frame_style(false,6))
	edit.add_theme_stylebox_override("focus",frame_style(true,6))
	edit.text_changed.connect(func(v: String): draft[key]=v)
	parent.add_child(edit)
	return edit

func options_text(opt: Dictionary) -> String:
	var descriptions: PackedStringArray = []
	for part in opt.get("parts",[]):
		if part["table"]=="text":
			descriptions.append(str(part["id"]).capitalize())
		else:
			descriptions.append(rules.cat.describe(str(part["table"]),str(part["id"])))
	return "\n\n────────\n\n".join(descriptions) if not descriptions.is_empty() else str(opt.get("label",""))

func choose_popup(caption: String, options: Array, callback: Callable) -> void:
	var win = Window.new()
	win.title = caption
	win.transient = true
	win.exclusive = true
	win.unresizable = true
	win.size = Vector2i(740,490)
	add_child(win)
	var m = MarginContainer.new()
	win.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		m.add_theme_constant_override("margin_"+side,10)
	var shell = framed(m)
	var search = LineEdit.new()
	search.placeholder_text = "Search…"
	shell.add_child(search)
	var h = row(shell,8)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list = ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.x = 260
	h.add_child(list)
	var info = TextEdit.new()
	info.editable = false
	info.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = 340
	info.add_theme_color_override("font_readonly_color",IVORY)
	h.add_child(info)
	var filtered: Array = []
	var refresh = func():
		filtered.clear()
		list.clear()
		for opt in options:
			if search.text.strip_edges().is_empty() or str(opt["label"]).to_lower().contains(search.text.to_lower()):
				filtered.append(opt)
				list.add_item(str(opt["label"]))
		info.text = "Select an option."
	var select = func(i: int):
		if i>=0 and i<filtered.size():
			var opt = filtered[i]
			show_detail(options_text(opt))
			win.hide()
			callback.call(str(opt["key"]))
			win.queue_free()
	list.item_selected.connect(func(i: int):
		if i>=0 and i<filtered.size():
			info.text=options_text(filtered[i])
			show_detail(info.text))
	list.item_activated.connect(select)
	search.text_changed.connect(func(_value: String): refresh.call())
	var nav = row(shell)
	nav.alignment = BoxContainer.ALIGNMENT_END
	action(nav,"Cancel",win.queue_free)
	var confirm_pick = func():
		var selected = list.get_selected_items()
		if not selected.is_empty(): select.call(selected[0])
	action(nav,"Select",confirm_pick,true)
	win.close_requested.connect(win.queue_free)
	refresh.call()
	win.popup_centered()
	search.grab_focus()

func identity_choice(parent: Container, caption: String, table: String, key: String, records: Array) -> void:
	var options: Array = []
	for rec in records:
		options.append({"key":str(rec["index"]),"label":str(rec["name"]),"parts":[{"table":table,"id":str(rec["index"])}]})
	var id = str(draft.get(key,""))
	var b = action(parent,(caption if id.is_empty() else rules.cat.title(table,id))+"  ▾",func(): choose_popup(caption,options,func(value: String):
		if draft.get(key,"")!=value:
			draft[key]=value
			if key=="race_id": draft["subrace_id"]=""
			if key=="class_id": draft["subclass_id"]=""
			draft["answers"]={}
			for field in ["equipped_armor","equipped_shield","equipped_weapons"]: draft.erase(field)
			queue_render()))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not id.is_empty():
		b.tooltip_text = rules.cat.summary(table,id)

func simple_choice(parent: Container, caption: String, key: String, choices: Array) -> void:
	var options: Array = []
	for value in choices:
		options.append({"key":value,"label":value})
	var current = str(draft.get(key,""))
	var b = action(parent,(caption if current.is_empty() else current)+"  ▾",func(): choose_popup(caption,options,func(v: String): draft[key]=v; queue_render()))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func identity() -> void:
	var pane = framed(form)
	if quick:
		var h = row(pane)
		identity_choice(h,"Race","races","race_id",rules.cat.rows("races"))
		identity_choice(h,"Class","classes","class_id",rules.cat.rows("classes"))
		simple_choice(pane,"Sex / Gender","sex",["Female","Male","Nonbinary","Other / unspecified"])
		action(pane,"Generate and Review",quick_generate,true).custom_minimum_size.x = 200
		return
	var top = row(pane)
	text_field(top,"name","Character Name")
	identity_choice(top,"Race","races","race_id",rules.cat.rows("races"))
	identity_choice(top,"Class","classes","class_id",rules.cat.rows("classes"))
	var next = row(pane)
	identity_choice(next,"Background","backgrounds","background_id",rules.cat.rows("backgrounds"))
	simple_choice(next,"Sex / Gender","sex",["Female","Male","Nonbinary","Other / unspecified"])
	simple_choice(next,"Alignment","alignment",["Lawful Good","Neutral Good","Chaotic Good","Lawful Neutral","Neutral","Chaotic Neutral","Lawful Evil","Neutral Evil","Chaotic Evil"])
	var subs = rules.cat.filtered("subraces","race",str(draft.get("race_id","")))
	var role = str(draft.get("class_id",""))
	if not subs.is_empty() or int(RULES.SUBCLASS_AT.get(role,99))==1:
		var h = row(pane)
		if not subs.is_empty(): identity_choice(h,"Subrace","subraces","subrace_id",subs)
		if int(RULES.SUBCLASS_AT.get(role,99))==1: identity_choice(h,"Subclass","subclasses","subclass_id",rules.cat.filtered("subclasses","class",role))
	var desc = framed(form,"Description",1.0,"wand")
	description_editor = text_field(desc,"description","",true,84) as TextEdit
	var h = row(desc)
	ai_button = action(h,"Generate with AI",generate_description,true,19)
	ai_button.custom_minimum_size.x = 174
	ai_button.disabled = gemini.active
	var personality = framed(form,"Personality & History",1.0,"focus")
	for pair in [["personality","Personality"],["ideal","Ideal"],["bond","Bond"],["flaw","Flaw"],["backstory","Backstory"]]:
		var r = row(personality)
		var title = heading(pair[1],19)
		title.custom_minimum_size.x = 95
		title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		r.add_child(title)
		text_field(r,pair[0],"",false,29)

func generate_description() -> void:
	var context: Dictionary = {}
	for pair in [["race_id","races"],["subrace_id","subraces"],["class_id","classes"],["subclass_id","subclasses"],["background_id","backgrounds"]]:
		var id = str(draft.get(pair[0],""))
		if not id.is_empty(): context[pair[0]]=rules.cat.title(pair[1],id)
	for key in ["name","sex","alignment","personality","ideal","bond","flaw","backstory"]:
		context[key]=draft.get(key,"")
	if str(draft.get("race_id","")).is_empty() or str(draft.get("class_id","")).is_empty():
		note.text="Choose a race and class first."
		return
	ai_button.disabled=true
	note.text="Generating description…"
	gemini.generate("Write a grounded fantasy RPG character description in 2–4 sentences. Use only the supplied identity as context, avoid epic destiny, do not assign any mechanical abilities, equipment or stats. Return only prose, no markdown. Character: "+JSON.stringify(context))

func description_received(ok: bool, message: String) -> void:
	if is_instance_valid(ai_button): ai_button.disabled=false
	if ok:
		draft["description"]=message
		if step==1 and is_instance_valid(description_editor): description_editor.text=message
		if is_instance_valid(note): note.text="Description generated. Edit freely."
	elif is_instance_valid(note): note.text=message

func stat_card(parent: Container, caption: String, value: String, image_id: String = "star", small: String = "") -> VBoxContainer:
	var v = framed(parent,"",1.0)
	var h = row(v,3)
	h.add_child(icon(image_id,19))
	h.add_child(centered(caption,17))
	v.add_child(centered(value,29,IVORY))
	if not small.is_empty(): v.add_child(centered(small,16,IVORY))
	return v

func change_point(ability: String, delta: int) -> void:
	var current = int(draft["base_scores"].get(ability,8))
	var next = clampi(current+delta,8,15)
	var cost = rules.points_used(draft)-int(RULES.POINT_COST[current])+int(RULES.POINT_COST[next])
	if cost>27:
		note.text="No points remaining."
		return
	draft["base_scores"][ability]=next
	queue_render()

func swap_score(ability: String) -> void:
	var opts: Array=[]
	for a in RULES.ABILITIES:
		if a!=ability:
			opts.append({"key":a,"label":a.to_upper()+"   "+str(draft["base_scores"][a]),"parts":[{"table":"ability-scores","id":a}]})
	choose_popup("Swap "+ability.to_upper()+" score",opts,func(a: String):
		var old = draft["base_scores"][ability]
		draft["base_scores"][ability]=draft["base_scores"][a]
		draft["base_scores"][a]=old
		queue_render())

func abilities() -> void:
	var generation = framed(form,"Score Generation",1.0,"initiative")
	var h = row(generation)
	for pair in [["roll","Roll 4d6"],["array","Standard Array"],["point","Point Buy 27"]]:
		var method = str(pair[0])
		var b = action(h,pair[1],func(): rules.roll_scores(draft,method); render(),draft.get("ability_method")==method,19)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if str(draft.get("ability_method",""))=="roll": action(h,"Reroll",func(): rules.roll_scores(draft,"roll"); render(),false,19)
	if str(draft.get("ability_method","")).is_empty(): return
	if draft["ability_method"]=="point":
		generation.add_child(centered(str(27-rules.points_used(draft))+" / 27 points remaining",20))
	var result = rules.scores(draft)
	var score_panel = framed(form)
	var cards = row(score_panel,3)
	for a in RULES.ABILITIES:
		var score = int(result[a])
		var base = int(draft["base_scores"][a])
		var card = framed(cards,"",1.0)
		var label = action(card,a.to_upper(),func(): show_detail(rules.cat.describe("ability-scores",a)),false,18)
		label.custom_minimum_size.x=0
		card.add_child(centered(str(score)+" (%+d)" % rules.mod_for(score),24,IVORY))
		card.add_child(centered("Base "+str(base)+(" +"+str(score-base) if score!=base else ""),16,IVORY))
		if draft["ability_method"]=="point":
			var buttons = row(card,2)
			var minus=action(buttons,"−",func(): change_point(a,-1),false,17)
			minus.custom_minimum_size.x=20
			var plus=action(buttons,"+",func(): change_point(a,1),false,17)
			plus.custom_minimum_size.x=20
		else:
			var b=action(card,"Swap",func(): swap_score(a),false,17)
			b.custom_minimum_size.x=0
	for g in rules.groups(draft,2): group_ui(score_panel,g)
	if draft["ability_method"]=="roll":
		var history=framed(form,"Roll History",1.0,"initiative")
		var roll_cards=row(history,3)
		for dice in draft["roll_history"]:
			var sorted = dice.duplicate()
			sorted.sort()
			var total = int(sorted[1])+int(sorted[2])+int(sorted[3])
			var c=framed(roll_cards,"",1.0)
			c.add_child(centered(str(total),24,IVORY))
			c.add_child(centered(str(int(sorted[1]))+" + "+str(int(sorted[2]))+" + "+str(int(sorted[3])),16,IVORY))
			c.add_child(centered("Dropped "+str(int(sorted[0])),14))
	var preview=rules.full_record(draft)
	var c=preview["combat"]
	var sp=preview["spellcasting"]
	var stats=framed(form,"Derived Statistics",1.0,"star")
	var r=row(stats,4)
	stat_card(r,"Initiative","%+d" % int(c["initiative"]),"initiative")
	stat_card(r,"Hit Points",str(c["hp_max"]),"health")
	stat_card(r,"Passive",str(c["passive_perception"]),"focus")
	if sp["save_dc"]!=null:
		stat_card(r,"Save DC",str(sp["save_dc"]),"wand")
		stat_card(r,"Spell Atk","%+d" % int(sp["attack_bonus"]),"wand")

func group_title(g: Dictionary) -> String:
	var titles = {"class-cantrips":"Cantrips","racial-cantrip":"Racial Cantrip","spellbook":"Spellbook","prepared":"Prepared Spells","known":"Known Spells","race-bonus":"Racial Bonuses","expertise":"Expertise","favored-enemy":"Favored Enemy","favored-terrain":"Favored Terrain","enemy-language":"Enemy Language"}
	if titles.has(g["key"]): return titles[g["key"]]
	if g["kind"]=="gear": return "Equipment Choice "+str(int(str(g["key"]).get_slice("-",1))+1)
	if g["kind"]=="profs":
		if not g["options"].is_empty() and str(g["options"][0]["parts"][0]["id"]).begins_with("skill-"): return "Skill Proficiencies"
		return "Tool Proficiencies"
	if g["kind"]=="languages": return "Languages"
	return str(g["label"])

func group_ui(parent: Container,g: Dictionary) -> void:
	var count=rules.selected(draft,g).size()
	var title=heading(group_title(g)+"   "+str(count)+" / "+str(g["count"]),20)
	title.tooltip_text=str(g["label"])
	parent.add_child(title)
	var answers = draft.get("answers",{}).get(g["key"],[])
	var columns: HBoxContainer
	for slot in range(int(g["count"])):
		if slot%2==0: columns=row(parent,4)
		var current = str(answers[slot]) if slot<answers.size() and answers[slot]!=null else ""
		var available: Array=[]
		var caption = "+ Select"
		var tip = ""
		var occupied: Array=[]
		for j in range(answers.size()):
			if j!=slot:
				for opt in g["options"]:
					if opt["key"]==answers[j]:
						for part in opt["parts"]: occupied.append(part["id"])
		for opt in g["options"]:
			if opt["key"]==current:
				caption=str(opt["label"])
				tip=options_text(opt).left(650)
			var blocked=false
			if g["kind"]!="gear":
				for part in opt["parts"]:
					if part["id"] in occupied: blocked=true
			if not blocked: available.append(opt)
		var choose_slot = func():
			choose_popup(str(g["label"]),available,func(key: String):
				var values=draft["answers"].get(g["key"],[]).duplicate()
				values.resize(int(g["count"]))
				values[slot]=key
				draft["answers"][g["key"]]=values
				if g["kind"]=="gear":
					for field in ["equipped_armor","equipped_shield","equipped_weapons"]: draft.erase(field)
				queue_render())
		var b=action(columns,caption+"  ▾",choose_slot,false,18)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.tooltip_text=tip
		b.disabled=available.is_empty()

func reference_link(parent: Container,table: String,id: String,caption: String="") -> void:
	var b = Button.new()
	b.text = caption if not caption.is_empty() else rules.cat.title(table,id)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size",18)
	b.add_theme_color_override("font_color",IVORY)
	b.tooltip_text=rules.cat.summary(table,id)
	b.pressed.connect(func(): show_detail(rules.cat.describe(table,id)))
	parent.add_child(b)

func features() -> void:
	var rec=rules.full_record(draft)
	var sp=rec["spellcasting"]
	var top=framed(form,"Proficiencies & Spellcasting",1.0,"wand")
	var stats=row(top,4)
	stat_card(stats,"Prof.","+2","star")
	if sp["save_dc"]!=null:
		stat_card(stats,"Ability",str(sp["ability"]).to_upper(),"focus")
		stat_card(stats,"Save DC",str(sp["save_dc"]),"wand")
		stat_card(stats,"Attack","%+d" % int(sp["attack_bonus"]),"wand")
		stat_card(stats,"Level 1 Slots",str(sp["slots"]["1"]["maximum"]),"focus")
	var cols=row(form,5)
	var left=framed(cols,"Skills",0.85,"focus")
	left.get_parent().custom_minimum_size.x=210
	for id in rec["skills"]:
		var s=rec["skills"][id]
		reference_link(left,"skills",id,("◆ " if s["proficient"] else "◇ ")+rules.cat.title("skills",id)+("   %+d" % int(s["modifier"])))
	left.add_child(heading("Saving Throws",21))
	for a in RULES.ABILITIES:
		reference_link(left,"ability-scores",a,("◆ " if "saving-throw-"+a in rec["proficiency_ids"] else "◇ ")+a.to_upper()+"  %+d" % int(rec["saving_throws"][a]))
	var right=framed(cols,"",1.55)
	for g in rules.groups(draft,3): group_ui(right,g)
	for id in sp["always_prepared_ids"]: reference_link(right,"spells",id,rules.cat.title("spells",id)+" • Always prepared")
	var granted=framed(form,"Features & Traits",1.0,"star")
	var b=rules.base(draft)
	for id in b["traits"]: reference_link(granted,"traits",id)
	for id in b["features"]: reference_link(granted,"features",id)
	for id in rec["language_ids"]: reference_link(granted,"languages",id)

func loadout() -> void:
	var rec=rules.full_record(draft)
	var c=rec["combat"]
	var sp=rec["spellcasting"]
	var identity_bar=framed(form,"",1.0)
	identity_bar.add_child(heading(str(rec["name"])+"   ◆   "+rules.cat.title("races",rec["race_id"])+"   •   "+rules.cat.title("classes",rec["class_id"])+"   •   Level 1",25))
	var stats=row(form,4)
	stat_card(stats,"AC",str(c["armor_class"]),"armor")
	stat_card(stats,"Hit Points",str(c["hp_current"])+" / "+str(c["hp_max"]),"health")
	stat_card(stats,"Initiative","%+d" % int(c["initiative"]),"initiative")
	stat_card(stats,"Speed",str(c["speed_feet"])+" ft.","speed")
	stat_card(stats,"Prof.","+2","star")
	if sp["save_dc"]!=null: stat_card(stats,"Save DC",str(sp["save_dc"]),"wand")
	var choices=framed(form,"Starting Equipment",1.0,"pack")
	for g in rules.groups(draft,4): group_ui(choices,g)
	var columns=row(form,5)
	var equip=framed(columns,"Equipment",1.0,"shield")
	equipment_selector(equip,rec,"armor")
	equipment_selector(equip,rec,"shield")
	var inventory=framed(columns,"Inventory",1.0,"pack")
	var attacks=framed(columns,"Attacks",1.3,"initiative")
	for it in rec["inventory"]:
		var id=str(it["item_id"])
		var title=rules.cat.title("equipment",id)
		reference_link(inventory,"equipment",id,title+"   ×"+str(it["quantity"]))
		if it.get("equipped",false): reference_link(equip,"equipment",id,title)
		if rules.cat.get_record("equipment",id).has("weapon_category"):
			var equipped = id in draft.get("equipped_weapons",[])
			action(equip,("◆ " if equipped else "◇ ")+title,func(): toggle_weapon(id),equipped,16)
	for at in rec.get("attacks",[]):
		var id=str(at["item_id"])
		reference_link(attacks,"equipment",id,rules.cat.title("equipment",id)+"  %+d" % int(at["attack_bonus"])+"   "+str(at["damage_dice"])+"%+d" % int(at["damage_modifier"]))
	for key in ["cantrip_ids","racial_cantrip_ids"]:
		for id in sp[key]: reference_link(attacks,"spells",id)
	equip.add_child(heading("Coins",21))
	equip.add_child(heading(str(rec["coins"]["gp"])+" gp",20,IVORY))
	inventory.add_child(heading("Weight: "+str(rec.get("carried_weight_lb",0))+" lb",16,IVORY))
	var traits=framed(form,"Features, Traits & Proficiencies",1.0,"star")
	for id in rec["racial_trait_ids"]: reference_link(traits,"traits",id)
	for id in rec["class_feature_ids"]: reference_link(traits,"features",id)
	for id in rec["language_ids"]: reference_link(traits,"languages",id)
	for id in rec["proficiency_ids"]: reference_link(traits,"proficiencies",id)
	for warning in rec["review_required"]: traits.add_child(heading("Review: "+str(warning),18,IVORY))

func toggle_weapon(id: String) -> void:
	var weapons = draft.get("equipped_weapons",[]).duplicate()
	if id in weapons:
		weapons.erase(id)
	else:
		weapons.append(id)
		var rec=rules.full_record(draft)
		var hands=0 if str(rec["equipment"].get("shield_id","")).is_empty() else 1
		for weapon in weapons:
			hands+=2 if "two-handed" in rules.cat.references(rules.cat.get_record("equipment",weapon).get("properties",[])) else 1
		if hands>2:
			note.text="Not enough free hands."
			return
	draft["equipped_weapons"]=weapons
	queue_render()

func equipment_selector(parent: Container, rec: Dictionary, kind: String) -> void:
	var choices: Array=[{"key":"","label":"None","parts":[]}]
	for item in rec["inventory"]:
		var id=str(item["item_id"])
		var category=str(rules.cat.get_record("equipment",id).get("armor_category",""))
		if kind=="shield" and category=="Shield" or kind=="armor" and category in ["Light","Medium","Heavy"]:
			choices.append({"key":id,"label":rules.cat.title("equipment",id),"parts":[{"table":"equipment","id":id}]})
	var current=str(rec["equipment"].get(kind+"_id",""))
	var label=kind.capitalize()+": "+("None" if current.is_empty() else rules.cat.title("equipment",current))
	var select_gear=func():
		choose_popup(kind.capitalize(),choices,func(value: String):
			draft["equipped_"+kind]=value
			if kind=="shield" and not value.is_empty(): draft["equipped_weapons"]=[]
			queue_render())
	action(parent,label+" ▾",select_gear,false,16)

func advance() -> void:
	if not rules.cat.initialize():
		note.text=rules.cat.last_error
		return
	var error = rules.validate_step(draft,step)
	if not error.is_empty():
		note.text=error
		return
	step += 1
	render()

func auto_fill(stage: int) -> void:
	# Recompute groups after each selection, preserving dependencies such as Wizard preparation.
	var seen: Array = []
	for iteration in range(100):
		var pending: Dictionary = {}
		for g in rules.groups(draft,stage):
			if g["key"] not in seen:
				pending=g
				break
		if pending.is_empty():
			break
		seen.append(pending["key"])
		var options = pending["options"].duplicate()
		options.shuffle()
		var answers: Array = []
		var used: Array = []
		for opt in options:
			var blocked = false
			for part in opt["parts"]:
				if part["id"] in used and pending["kind"]!="gear":
					blocked=true
			if blocked:
				continue
			answers.append(opt["key"])
			for part in opt["parts"]:
				used.append(part["id"])
			if answers.size() >= int(pending["count"]):
				break
		draft["answers"][pending["key"]]=answers

func quick_generate() -> void:
	if str(draft.get("race_id","")).is_empty() or str(draft.get("class_id","")).is_empty():
		note.text="Choose race and class first."
		return
	if str(draft.get("name","")).strip_edges().is_empty():
		draft["name"]=["Aerin","Talan","Mira","Corin","Seren","Riven"].pick_random()+" "+["Starbrook","Ashfield","Greywood","Stormvale","Dawnmere"].pick_random()
	var sub = rules.cat.filtered("subraces","race",str(draft["race_id"]))
	if not sub.is_empty() and str(draft.get("subrace_id","")).is_empty():
		draft["subrace_id"]=sub.pick_random()["index"]
	var role = str(draft["class_id"])
	if int(RULES.SUBCLASS_AT.get(role,99))==1 and str(draft.get("subclass_id","")).is_empty():
		var choices = rules.cat.filtered("subclasses","class",role)
		if not choices.is_empty():
			draft["subclass_id"]=choices.pick_random()["index"]
	if str(draft.get("background_id","")).is_empty():
		draft["background_id"]=rules.cat.rows("backgrounds").pick_random()["index"]
	for pair in [["description","An adventurer setting out to make a life of their own."],["personality","Curious and observant."],["ideal","Earn trust through actions."],["bond","A promise to an old friend."],["flaw","Sometimes acts before thinking."],["backstory","Left a familiar home to travel and find new opportunities."]]:
		if str(draft.get(pair[0],"")).is_empty():
			draft[pair[0]]=pair[1]
	rules.roll_scores(draft,"roll")
	quick=false
	for i in range(2,5):
		auto_fill(i)
	for i in range(1,5):
		var error = rules.validate_step(draft,i)
		if not error.is_empty():
			step=i
			render()
			note.text="Review generated choices: "+error
			return
	step=4
	render()

func save(finalize: bool) -> void:
	if not rules.cat.initialize():
		note.text=rules.cat.last_error
		return
	if finalize:
		for i in range(1,5):
			var error = rules.validate_step(draft,i)
			if not error.is_empty():
				step=i
				render()
				note.text=error
				return
	var id = str(existing.get("id",store.make_id()))
	var path = str(draft.get("portrait",""))
	if not path.is_empty():
		var saved_portrait = store.save_portrait(id,path)
		if saved_portrait.is_empty():
			note.text="Portrait could not be saved. Choose a valid image or clear it."
			return
		draft["portrait"]=saved_portrait
	var record: Dictionary = rules.full_record(draft) if finalize else {"name":draft.get("name",""),"race_id":draft.get("race_id",""),"class_id":draft.get("class_id",""),"ruleset":"5e-2014-2018","catalog_revision":"srd51-2018-r2","draft":draft.duplicate(true)}
	record["id"]=id
	record["status"]="draft" if not finalize else ("ready" if record.get("review_required",[]).is_empty() else "needs_review")
	if existing.has("created_at"):
		record["created_at"]=existing["created_at"]
	var error = store.save_record(record)
	if not error.is_empty():
		note.text=error
		return
	existing=record
	note.text="Saved locally: "+str(record["status"])
	if finalize:
		finish_action.call()
