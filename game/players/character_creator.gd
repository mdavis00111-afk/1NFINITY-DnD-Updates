extends Control
## Four distinct screens with one persisted draft. All mechanical values come from CharacterRules.
const RULES = preload("res://rules/character_rules.gd")
const STORE = preload("res://players/character_store.gd")
const FRAME = preload("res://themes/parts/frame.png")
const ICONS = preload("res://themes/parts/icons.png")
const CORNER = preload("res://themes/parts/corner.png")
const GOLD = Color("#f2cf83")
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
var detail_text: String = "Select any race, class, skill, spell, feature or item to see its reference."
var pending_render: bool = false

func configure(is_quick: bool, on_exit: Callable, on_finish: Callable, saved: Dictionary = {}) -> void:
	quick = is_quick
	exit_action = on_exit
	finish_action = on_finish
	existing = saved
	draft = saved.get("draft",rules.fresh()).duplicate(true)

func _ready() -> void:
	if draft.is_empty():
		draft = rules.fresh()
	# Parent anchors and viewport size must settle before building nested containers.
	render.call_deferred()

func heading(value: String,size_px: int = 23) -> Label:
	var l = Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size",size_px)
	l.add_theme_color_override("font_color",GOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func action(parent: Container, caption: String, callback: Callable) -> Button:
	var b = Button.new()
	b.text = caption
	b.custom_minimum_size.y = 32
	b.add_theme_font_size_override("font_size",23)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func framed(parent: Container) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dark = StyleBoxFlat.new()
	dark.bg_color = Color(0.025,0.045,0.08,0.94)
	panel.add_theme_stylebox_override("panel",dark)
	parent.add_child(panel)
	var inner = PanelContainer.new()
	var frame_style = StyleBoxTexture.new()
	frame_style.texture = FRAME
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		frame_style.set_texture_margin(side,20)
		frame_style.set_content_margin(side,13)
	inner.add_theme_stylebox_override("panel",frame_style)
	panel.add_child(inner)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation",8)
	inner.add_child(v)
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
		body.add_theme_constant_override("margin_"+side,24)
	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation",9)
	body.add_child(root)
	var title_row = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(title_row)
	var corner = TextureRect.new()
	corner.texture = CORNER
	corner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	corner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	corner.custom_minimum_size = Vector2(38,38)
	title_row.add_child(corner)
	var page_title = heading("Character Creator   •   "+str(step)+" / 4",32)
	page_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(page_title)
	var steps = HBoxContainer.new()
	root.add_child(steps)
	var names = ["Identity","Ability Scores","Skills & Spells","Loadout & Review"]
	for i in range(4):
		var label = heading(("◆ " if i+1==step else "◇ ")+names[i],19)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		steps.add_child(label)
	var columns = HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",14)
	root.add_child(columns)
	var left = framed(columns)
	left.get_parent().get_parent().size_flags_stretch_ratio = 1.7
	left.get_parent().get_parent().custom_minimum_size.x = 440
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation",8)
	scroll.add_child(form)
	var right = framed(columns)
	right.get_parent().get_parent().size_flags_stretch_ratio = 1.0
	right.get_parent().get_parent().custom_minimum_size.x = 315
	right.add_child(heading("Rules & Reference",25))
	reference = TextEdit.new()
	reference.editable = false
	reference.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	reference.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reference.custom_minimum_size.x = 260
	reference.add_theme_font_size_override("font_size",19)
	reference.text = detail_text
	right.add_child(reference)
	match step:
		1: identity()
		2: abilities()
		3: features()
		4: loadout()
	note = heading("",17)
	root.add_child(note)
	var nav = HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(nav)
	action(nav,"Exit",func(): exit_action.call())
	action(nav,"Save Draft",func(): save(false))
	if step > 1:
		action(nav,"Back",func(): step -= 1; render())
	if step < 4:
		action(nav,"Next",advance)
	else:
		action(nav,"Create Character" if existing.is_empty() else "Save Character",func(): save(true))
	if preserve_scroll:
		scroll.set_deferred("scroll_vertical",old_scroll)

func queue_render() -> void:
	if pending_render:
		return
	pending_render = true
	render.call_deferred(true)

func show_detail(value: String) -> void:
	detail_text = value
	if is_instance_valid(reference):
		reference.text = value

func row_label(parent: Container,caption: String) -> void:
	parent.add_child(heading(caption,20))

func text_field(caption: String,key: String,multi: bool = false) -> void:
	row_label(form,caption)
	if multi:
		var e = TextEdit.new()
		e.text = str(draft.get(key,""))
		e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		e.custom_minimum_size.y = 65
		form.add_child(e)
		e.text_changed.connect(func(): draft[key]=e.text)
	else:
		var e = LineEdit.new()
		e.text = str(draft.get(key,""))
		e.placeholder_text = caption
		e.custom_minimum_size.y = 32
		form.add_child(e)
		e.text_changed.connect(func(value: String): draft[key]=value)

func dropdown(parent: Container,caption: String,options: Array,current: String,changed: Callable,allow_blank: bool = true) -> OptionButton:
	row_label(parent,caption)
	var o = OptionButton.new()
	o.fit_to_longest_item = false
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size.y = 34
	if allow_blank:
		o.add_item("Choose…")
		o.set_item_metadata(0,"")
	var chosen = 0
	for opt in options:
		o.add_item(str(opt["label"]))
		var idx = o.item_count-1
		o.set_item_metadata(idx,str(opt["key"]))
		if str(opt["key"]) == current:
			chosen = idx
		if options.size() <= 60:
			var tooltip = str(opt["label"])+" — select for details"
			if opt.has("parts") and opt["parts"].size() == 1:
				var p = opt["parts"][0]
				if p["table"] != "text":
					tooltip = rules.cat.summary(p["table"],p["id"])
			o.get_popup().set_item_tooltip(idx,tooltip)
	if o.item_count > 0:
		o.select(chosen)
	o.item_selected.connect(func(i: int):
		var key = str(o.get_item_metadata(i))
		changed.call(key))
	parent.add_child(o)
	return o

func choose_identity(caption: String,table: String,key: String,records: Array,reset_children: bool = false) -> void:
	var choices: Array = []
	for rec in records:
		choices.append({"key":str(rec["index"]),"label":str(rec["name"]),"parts":[{"table":table,"id":str(rec["index"])}]})
	dropdown(form,caption,choices,str(draft.get(key,"")),func(id: String):
		if not id.is_empty():
			show_detail(rules.cat.describe(table,id))
		if str(draft.get(key,"")) != id:
			draft[key]=id
			if key == "race_id":
				draft["subrace_id"]=""
			if key == "class_id":
				draft["subclass_id"]=""
			draft["answers"]={}
			if reset_children:
				queue_render())

func portrait() -> void:
	var row = HBoxContainer.new()
	form.add_child(row)
	var image = TextureRect.new()
	image.custom_minimum_size = Vector2(96,120)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path = str(draft.get("portrait",""))
	if not path.is_empty():
		var img = Image.load_from_file(path)
		if not img.is_empty():
			image.texture = ImageTexture.create_from_image(img)
	row.add_child(image)
	var buttons = VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(buttons)
	var portrait_title = heading("Portrait",23)
	portrait_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	buttons.add_child(portrait_title)
	buttons.add_child(heading("Supply an image now or leave blank. Stock portraits will be added later.",17))
	action(buttons,"Choose Image",func():
		var picker = FileDialog.new()
		picker.access = FileDialog.ACCESS_FILESYSTEM
		picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		picker.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Portrait images"])
		add_child(picker)
		picker.file_selected.connect(func(file_path: String):
			draft["portrait"]=file_path
			picker.queue_free()
			queue_render())
		picker.canceled.connect(picker.queue_free)
		picker.popup_centered_ratio(0.8))
	action(buttons,"Clear Portrait",func(): draft["portrait"]=""; queue_render())

func identity() -> void:
	form.add_child(heading("I. Identity",29))
	form.add_child(heading("Original D&D 5e • 2018 Basic Rules / 2014 SRD • Level 1",17))
	if quick:
		choose_identity("Race","races","race_id",rules.cat.rows("races"),true)
		choose_identity("Class","classes","class_id",rules.cat.rows("classes"),true)
		text_field("Sex / Gender","sex")
		action(form,"Generate and Review",quick_generate)
		form.add_child(heading("Godot selects supported background, subrace, class options, ability scores, skills, spells and starting equipment. Review before saving.",18))
		return
	portrait()
	text_field("Character Name","name")
	choose_identity("Race","races","race_id",rules.cat.rows("races"),true)
	var subraces = rules.cat.filtered("subraces","race",str(draft.get("race_id","")))
	if not subraces.is_empty():
		choose_identity("Subrace","subraces","subrace_id",subraces)
	choose_identity("Class","classes","class_id",rules.cat.rows("classes"),true)
	var role = str(draft.get("class_id",""))
	if not role.is_empty():
		var level = int(RULES.SUBCLASS_AT.get(role,99))
		if level == 1:
			choose_identity("Subclass","subclasses","subclass_id",rules.cat.filtered("subclasses","class",role))
		else:
			form.add_child(heading("Subclass is selected at level "+str(level)+". View available subclasses in the reference library.",17))
	choose_identity("Background","backgrounds","background_id",rules.cat.rows("backgrounds"))
	text_field("Sex / Gender","sex")
	var alignments: Array = []
	for a in ["Lawful Good","Neutral Good","Chaotic Good","Lawful Neutral","Neutral","Chaotic Neutral","Lawful Evil","Neutral Evil","Chaotic Evil"]:
		alignments.append({"key":a,"label":a})
	dropdown(form,"Alignment",alignments,str(draft.get("alignment","Neutral")),func(id: String): draft["alignment"]=id,false)
	text_field("Description","description",true)
	text_field("Personality","personality",true)
	text_field("Ideal","ideal",true)
	text_field("Bond","bond",true)
	text_field("Flaw","flaw",true)
	text_field("Backstory","backstory",true)
	if quick:
		action(form,"Generate and Review",quick_generate)
	form.add_child(heading("Catalogue coverage: licensed SRD choices plus 2018 supplements. Additional PHB options are not yet available.",16))

func abilities() -> void:
	form.add_child(heading("II. Ability Scores",29))
	var methods = HBoxContainer.new()
	form.add_child(methods)
	action(methods,"4d6 Drop Lowest",func(): rules.roll_scores(draft,"roll"); render())
	action(methods,"Standard Array",func(): rules.roll_scores(draft,"array"); render())
	action(methods,"Point Buy",func(): rules.roll_scores(draft,"point"); render())
	if str(draft.get("ability_method","")).is_empty():
		form.add_child(heading("Choose a method to begin.",20))
		return
	if draft["ability_method"] == "roll":
		form.add_child(heading("Godot dice: "+str(draft["roll_history"]),17))
	if draft["ability_method"] != "point":
		form.add_child(heading("Pool: "+str(draft["roll_pool"])+" • assign each score once",18))
	var result = rules.scores(draft)
	var grid = GridContainer.new()
	grid.columns = 4
	form.add_child(grid)
	for label in ["Ability","Base","Final","Modifier"]:
		grid.add_child(heading(label,19))
	for a in RULES.ABILITIES:
		var field = Button.new()
		field.text = a.to_upper()
		field.pressed.connect(func(): show_detail(rules.cat.describe("ability-scores",a)))
		grid.add_child(field)
		if draft["ability_method"] == "point":
			var spin = SpinBox.new()
			spin.min_value = 8
			spin.max_value = 15
			spin.step = 1
			spin.value = int(draft["base_scores"].get(a,8))
			grid.add_child(spin)
			spin.value_changed.connect(func(v: float):
				draft["base_scores"][a]=int(v)
				queue_render())
		else:
			var o = OptionButton.new()
			var seen: Array = []
			for n in draft["roll_pool"]:
				if int(n) not in seen:
					seen.append(int(n))
					o.add_item(str(int(n)),int(n))
					if int(n) == int(draft["base_scores"].get(a,0)):
						o.select(o.item_count-1)
			grid.add_child(o)
			o.item_selected.connect(func(i: int):
				draft["base_scores"][a]=o.get_item_id(i)
				queue_render())
		grid.add_child(heading(str(result[a]),24))
		grid.add_child(heading("%+d" % rules.mod_for(int(result[a])),23))
	if draft["ability_method"] == "point":
		form.add_child(heading("Points spent: "+str(rules.points_used(draft))+" / 27",20))
	for g in rules.groups(draft,2):
		group_ui(g)
	form.add_child(heading("Final scores include original-edition racial ability increases.",17))

func group_ui(g: Dictionary) -> void:
	form.add_child(heading(str(g["label"])+"  •  choose "+str(g["count"]),21))
	var answers = draft.get("answers",{}).get(g["key"],[])
	for slot in range(int(g["count"])):
		var current = str(answers[slot]) if slot < answers.size() else ""
		dropdown(form,"Selection "+str(slot+1),g["options"],current,func(key: String):
			var list = draft["answers"].get(g["key"],[]).duplicate()
			list.resize(int(g["count"]))
			list[slot]=key
			draft["answers"][g["key"]]=list
			for opt in g["options"]:
				if opt["key"]==key:
					var descriptions: PackedStringArray = []
					for part in opt["parts"]:
						if part["table"]=="text":
							descriptions.append(str(part["id"]).capitalize())
						else:
							descriptions.append(rules.cat.describe(part["table"],part["id"]))
					show_detail("\n\n────────\n\n".join(descriptions))
					break
			queue_render())
	if g["options"].is_empty():
		form.add_child(heading("No verified option is available yet.",17))

func features() -> void:
	form.add_child(heading("III. Skills, Features & Spells",29))
	var b = rules.base(draft)
	form.add_child(heading("Granted traits and class features",23))
	for id in b["traits"]:
		action(form,rules.cat.title("traits",id),func(): show_detail(rules.cat.describe("traits",id)))
	for id in b["features"]:
		action(form,rules.cat.title("features",id),func(): show_detail(rules.cat.describe("features",id)))
	form.add_child(heading("Fixed proficiencies",22))
	for id in b["profs"]:
		action(form,rules.cat.title("proficiencies",id),func(): show_detail(rules.cat.describe("proficiencies",id)))
	for id in b["langs"]:
		action(form,rules.cat.title("languages",id),func(): show_detail(rules.cat.describe("languages",id)))
	for g in rules.groups(draft,3):
		group_ui(g)

func loadout() -> void:
	form.add_child(heading("IV. Starting Loadout & Review",29))
	form.add_child(heading("Class and background equipment packages • original 5e",18))
	for g in rules.groups(draft,4):
		group_ui(g)
	var record = rules.full_record(draft)
	form.add_child(heading("Starting Inventory",23))
	for item in record["inventory"]:
		var id = str(item["item_id"])
		var caption = str(item["quantity"])+" × "+rules.cat.title("equipment",id)+("  [Equipped]" if item["equipped"] else "")
		action(form,caption,func(): show_detail(rules.cat.describe("equipment",id)))
	var c = record["combat"]
	form.add_child(heading("AC  "+str(c["armor_class"])+"    HP  "+str(c["hp_max"])+"    Initiative  "+str(c["initiative"])+"    Speed  "+str(c["speed_feet"])+" ft.",24))
	form.add_child(heading("Passive Perception "+str(c["passive_perception"])+"    Gold "+str(record["coins"]["gp"])+" gp",19))
	form.add_child(heading("Ability scores, proficiency, spells and all selected IDs will be saved together.",17))
	for warning in record["review_required"]:
		form.add_child(heading("Needs review: "+str(warning),17))

func advance() -> void:
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
	var record: Dictionary = rules.full_record(draft) if finalize else {"name":draft.get("name",""),"race_id":draft.get("race_id",""),"class_id":draft.get("class_id",""),"ruleset":"5e-2014-2018","catalog_revision":"srd51-2018-r1","draft":draft.duplicate(true)}
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
