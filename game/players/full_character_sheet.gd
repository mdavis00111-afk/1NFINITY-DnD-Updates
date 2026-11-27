extends VBoxContainer
## Full saved-character sheet; presentation only. No mechanical values are overwritten.
const CAT = preload("res://rules/catalog.gd")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const PORTRAIT = preload("res://themes/parts/portrait_empty.png")
const ICONS = preload("res://themes/parts/icons.png")
const FLOURISH = preload("res://themes/gold_flourish.svg")
const GOLD = Color("#ffd989")
const IVORY = Color("#fff0cf")
const ABILITIES = ["str","dex","con","int","wis","cha"]
const ABILITY_NAMES = ["Strength","Dexterity","Constitution","Intelligence","Wisdom","Charisma"]
const XP_THRESHOLDS = [0,300,900,2700,6500,14000,23000,34000,48000,64000,85000,100000,120000,140000,165000,195000,225000,265000,305000,355000]
var cat = CAT.new()
var data: Dictionary = {}
var icon_rects: Dictionary = {}
var reference_requested: Callable

func configure(record: Dictionary, on_reference: Callable) -> void:
	data = record
	reference_requested = on_reference

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://themes/parts/icons.json"))
	if parsed is Dictionary:
		icon_rects = parsed
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",maxi(1,roundi(9 * 0.55)))
	display()

func number(value: Variant, signed: bool = false) -> String:
	if value == null:
		return "—"
	if value is int or value is float:
		return "%+d" % int(value) if signed else str(int(value))
	return str(value)

func frame_style(lit: bool = false, margin: int = 8) -> StyleBoxTexture:
	var s = StyleBoxTexture.new()
	s.texture = ACTIVE if lit else FRAME
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		s.set_texture_margin(edge,22)
		s.set_content_margin(edge,maxi(2,roundi(margin * 0.5)))
	return s

func label_text(t: String, px: int = 19, color: Color = IVORY, wrap: bool = false) -> Label:
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size",maxi(11,roundi(px * 0.64)))
	l.add_theme_color_override("font_color",color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func centered(t: String, px: int = 19, color: Color = IVORY) -> Label:
	var l = label_text(t,px,color,true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func row(parent: Container, gap: int = 8) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation",maxi(1,roundi(gap * 0.55)))
	parent.add_child(h)
	return h

func column(parent: Container, ratio: float = 1.0) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation",maxi(1,roundi(4 * 0.55)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = ratio
	parent.add_child(v)
	return v

func icon(id: String, px: int = 25) -> TextureRect:
	var t = TextureRect.new()
	var coords = icon_rects.get(id,icon_rects.get("star",[200,56,13,13]))
	var atlas = AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = Rect2(coords[0],coords[1],coords[2],coords[3])
	t.texture = atlas
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(maxi(10,roundi(px * 0.65)),maxi(10,roundi(px * 0.65)))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func rule(parent: Container) -> void:
	var line = ColorRect.new()
	line.color = Color(0.77,0.57,0.24,0.48)
	line.custom_minimum_size.y = maxi(1,roundi(1 * 0.58))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func ornament(parent: Container) -> void:
	var t = TextureRect.new()
	t.texture = FLOURISH
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size.y = maxi(1,roundi(8 * 0.58))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)

func panel(parent: Container, title_text: String = "", ratio: float = 1.0, icon_id: String = "star", lit: bool = false) -> VBoxContainer:
	var p = PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	p.add_theme_stylebox_override("panel",frame_style(lit,10))
	parent.add_child(p)
	var v = column(p)
	if not title_text.is_empty():
		var h = row(v,5)
		h.add_child(icon(icon_id,22))
		h.add_child(label_text(title_text,25,GOLD,true))
		ornament(v)
	return v

func ref_button(parent: Container, table: String, id: String, caption: String = "", px: int = 18) -> Button:
	var b = Button.new()
	b.text = caption if not caption.is_empty() else cat.title(table,id)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = maxi(1,roundi(25 * 0.58))
	b.add_theme_font_size_override("font_size",maxi(11,roundi(px * 0.64)))
	b.add_theme_color_override("font_color",IVORY)
	b.add_theme_color_override("font_hover_color",GOLD)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = cat.summary(table,id)
	b.pressed.connect(func():
		if reference_requested.is_valid():
			reference_requested.call(cat.title(table,id),cat.describe(table,id)))
	parent.add_child(b)
	return b

func text_ref(parent: Container, title_text: String, detail: String) -> Button:
	var b = Button.new()
	b.text = title_text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size",maxi(11,roundi(18 * 0.64)))
	b.add_theme_color_override("font_color",IVORY)
	b.tooltip_text = detail
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.pressed.connect(func():
		if reference_requested.is_valid():
			reference_requested.call(title_text,detail))
	parent.add_child(b)
	return b

func field(key: String, default_value: Variant = "") -> Variant:
	return data.get(key,data.get("draft",{}).get(key,default_value))

func portrait(parent: Container) -> void:
	var v = VBoxContainer.new()
	v.custom_minimum_size = Vector2(110,176)
	parent.add_child(v)
	var t = TextureRect.new()
	t.texture = PORTRAIT
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(166,266)
	v.add_child(t)
	var path = str(field("portrait"))
	if not path.is_empty() and FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if not img.is_empty():
			var actual = TextureRect.new()
			actual.texture = ImageTexture.create_from_image(img)
			actual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			actual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			actual.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.add_child(actual)
			actual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			actual.offset_left = 16
			actual.offset_right = -16
			actual.offset_top = 25
			actual.offset_bottom = -25

func stat(parent: Container, caption: String, value: String, icon_id: String) -> void:
	var p = panel(parent,"",1.0,"star",true)
	var t = icon(icon_id,27)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(t)
	p.add_child(centered(caption,19,GOLD))
	p.add_child(centered(value,31))

func identity() -> void:
	var h = row(self,12)
	portrait(h)
	var right = column(h)
	var main = panel(right)
	var top = row(main)
	var names = column(top)
	var name_label = label_text(str(field("name","Unnamed")),36,GOLD,true)
	names.add_child(name_label)
	rule(names)
	var details = row(names,9)
	var race_table = "subraces" if not str(field("subrace_id")).is_empty() else "races"
	var race_id = str(field("subrace_id")) if race_table=="subraces" else str(field("race_id"))
	for spec in [["Race",race_table,race_id],["Class","classes",str(field("class_id"))],["Background","backgrounds",str(field("background_id"))]]:
		var c = column(details)
		c.add_child(label_text(spec[0],17,GOLD))
		if not str(spec[2]).is_empty():
			ref_button(c,spec[1],spec[2],"",22)
		else:
			c.add_child(label_text("—"))
	var align = column(details)
	align.add_child(label_text("Alignment",17,GOLD))
	align.add_child(label_text(str(field("alignment","—")),21,IVORY,true))
	var level_box = panel(top,"",0.25,"star",true)
	level_box.get_parent().custom_minimum_size.x = 60
	level_box.add_child(centered("Level",19,GOLD))
	level_box.add_child(centered(number(data.get("level")),40))
	var subclass = str(field("subclass_id"))
	if not subclass.is_empty():
		ref_button(main,"subclasses",subclass)
	if not str(field("sex")).is_empty():
		main.add_child(label_text(str(field("sex")),17))
	if not data.has("combat"):
		main.add_child(label_text("Unfinished character — resume creation to complete the sheet.",20,GOLD,true))
		return
	var xp = int(data.get("xp",0))
	var level = clampi(int(data.get("level",1)),1,20)
	var xp_row = row(main)
	var next_xp = XP_THRESHOLDS[level] if level < 20 else XP_THRESHOLDS[19]
	xp_row.add_child(label_text("Experience   "+str(xp)+(" / "+str(next_xp) if level<20 else "")+" XP",19,GOLD))
	var bar = ProgressBar.new()
	bar.min_value = XP_THRESHOLDS[level-1]
	bar.max_value = next_xp if level<20 else XP_THRESHOLDS[19]+1
	bar.value = xp if level<20 else XP_THRESHOLDS[19]+1
	bar.show_percentage = false
	bar.custom_minimum_size.y = maxi(1,roundi(12 * 0.58))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color("#08111e")
	bg.border_color = GOLD
	bg.set_border_width_all(1)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color("#d9a343")
	bar.add_theme_stylebox_override("background",bg)
	bar.add_theme_stylebox_override("fill",fill)
	xp_row.add_child(bar)
	var c = data.get("combat",{})
	var stats = row(right)
	stat(stats,"Armor Class",number(c.get("armor_class")),"armor")
	stat(stats,"Hit Points",number(c.get("hp_current"))+" / "+number(c.get("hp_max")),"health")
	stat(stats,"Initiative",number(c.get("initiative"),true),"initiative")
	stat(stats,"Speed",number(c.get("speed_feet"))+" ft.","speed")

func ability_section() -> void:
	var h = row(self)
	var abilities = panel(h,"Ability Scores",0.95,"star")
	var saves = panel(h,"Saving Throws",0.8,"shield")
	var skills = panel(h,"Skills",1.65,"diamond")
	var scores = data.get("ability_scores",{})
	var modifiers = data.get("ability_modifiers",{})
	var saving = data.get("saving_throws",{})
	var profs = data.get("proficiency_ids",[])
	for i in range(6):
		var id = ABILITIES[i]
		var r = row(abilities,4)
		var b = ref_button(r,"ability-scores",id,id.to_upper()+"  "+ABILITY_NAMES[i],18)
		b.custom_minimum_size.x = 78
		var score = label_text(number(scores.get(id)),23,GOLD)
		score.custom_minimum_size.x = 22
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(score)
		var mod_label = label_text(number(modifiers.get(id),true),20)
		mod_label.custom_minimum_size.x = 25
		mod_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(mod_label)
		rule(abilities)
		var sr = row(saves,3)
		ref_button(sr,"ability-scores",id,("◆ " if "saving-throw-"+id in profs else "◇ ")+ABILITY_NAMES[i],18)
		sr.add_child(label_text(number(saving.get(id),true),20))
		rule(saves)
	var skill_columns = row(skills,9)
	var left = column(skill_columns)
	var right = column(skill_columns)
	var keys = data.get("skills",{}).keys()
	keys.sort()
	for i in range(keys.size()):
		var id = str(keys[i])
		var s = data["skills"][id]
		var target = left if i < ceili(keys.size()/2.0) else right
		var r = row(target,3)
		var mark = "◆ " if s.get("proficient",false) else "◇ "
		if s.get("expertise",false):
			mark = "✦ "
		ref_button(r,"skills",id,mark+cat.title("skills",id)+" ("+str(s.get("ability","")).capitalize()+")",17)
		r.add_child(label_text(number(s.get("modifier"),true),18))
		rule(target)

func attack_section(parent: Container) -> void:
	var p = panel(parent,"Attacks",1.0,"initiative")
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",maxi(1,roundi(8 * 0.55)))
	grid.add_theme_constant_override("v_separation",maxi(1,roundi(4 * 0.55)))
	p.add_child(grid)
	for title_text in ["Attack","To Hit","Damage","Type"]:
		grid.add_child(label_text(title_text,16,GOLD))
	for a in data.get("attacks",[]):
		var id = str(a.get("item_id",""))
		ref_button(grid,"equipment",id,"",18)
		grid.add_child(label_text(number(a.get("attack_bonus"),true),18))
		var m = int(a.get("damage_modifier",0))
		var dice = str(a.get("damage_dice","—"))
		grid.add_child(label_text(dice+(" "+number(m,true) if m!=0 else ""),18))
		grid.add_child(label_text(str(a.get("damage_type","")).capitalize(),17))
	if data.get("attacks",[]).is_empty():
		p.add_child(label_text("No recorded weapon attacks.",17))

func feature_line(parent: Container, table: String, id: String) -> void:
	var r = row(parent,5)
	r.add_child(icon("star",13))
	var rec = cat.get_record(table,id)
	var desc = rec.get("desc",[])
	var summary = str(desc[0]) if desc is Array and not desc.is_empty() else (str(desc) if desc is String else "")
	var line = cat.title(table,id)
	if not summary.is_empty():
		line += " — "+summary.left(96)+("…" if summary.length()>96 else "")
	ref_button(r,table,id,line,18)

func features_section(parent: Container) -> void:
	var p = panel(parent,"Features & Traits",1.2,"star")
	for id in data.get("class_feature_ids",[]):
		feature_line(p,"features",str(id))
	for id in data.get("racial_trait_ids",[]):
		feature_line(p,"traits",str(id))
	var bg = data.get("background_feature",{})
	if not bg.is_empty():
		text_ref(p,str(bg.get("name","Background feature")),cat.human(bg.get("desc",[])))
	for id in data.get("resources",{}):
		var res = data["resources"][id]
		p.add_child(label_text(str(id).replace("_"," ").capitalize()+"   "+str(int(res.get("max",0))-int(res.get("spent",0)))+" / "+number(res.get("max")),17,GOLD))

func item_sections(parent: Container) -> void:
	var gear = panel(parent,"Equipment",0.75,"shield")
	var inventory = panel(parent,"Inventory",0.85,"pack")
	for item in data.get("inventory",[]):
		var id = str(item.get("item_id",""))
		var equipped = bool(item.get("equipped",false))
		var target = gear if equipped else inventory
		var r = row(target,3)
		ref_button(r,"equipment",id,"",18)
		r.add_child(label_text(number(item.get("quantity")),18))
		rule(target)
	if gear.get_child_count()<=2:
		gear.add_child(label_text("Nothing equipped",17))
	var coins = data.get("coins",{})
	var values: PackedStringArray = []
	for unit in ["cp","sp","ep","gp","pp"]:
		values.append(number(coins.get(unit,0))+" "+unit.to_upper())
	inventory.add_child(label_text("  ·  ".join(values),17,GOLD,true))
	if data.has("carried_weight_lb"):
		inventory.add_child(label_text("Load: "+str(data["carried_weight_lb"])+" / "+number(data.get("carrying_capacity_lb"))+" lb.",17,IVORY,true))

func spell_section(parent: Container) -> void:
	var p = panel(parent,"Spells",1.4,"wand")
	var sp = data.get("spellcasting",{})
	if sp.get("save_dc") != null:
		p.add_child(label_text("Spell Save DC "+number(sp.get("save_dc"))+"   |   Spell Attack "+number(sp.get("attack_bonus"),true),18,GOLD,true))
	var any_spell = false
	for key in ["cantrip_ids","racial_cantrip_ids","known_ids","prepared_ids","always_prepared_ids"]:
		var ids = sp.get(key,[])
		if ids.is_empty():
			continue
		any_spell = true
		var caption = {"cantrip_ids":"Cantrips","racial_cantrip_ids":"Racial Cantrips","known_ids":"Spellbook" if data.get("class_id")=="wizard" else "Known Spells","prepared_ids":"Prepared Spells","always_prepared_ids":"Always Prepared"}.get(key,key)
		p.add_child(label_text(str(caption)+"  ("+str(ids.size())+")",19,GOLD))
		var group = HFlowContainer.new()
		group.add_theme_constant_override("h_separation",maxi(1,roundi(7 * 0.55)))
		p.add_child(group)
		for id in ids:
			var b = ref_button(group,"spells",str(id),"",17)
			b.size_flags_horizontal = Control.SIZE_FILL
			b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		rule(p)
	for level in sp.get("slots",{}):
		var slot = sp["slots"][level]
		if int(slot.get("maximum",0)) > 0:
			any_spell = true
			p.add_child(label_text("Level "+str(level)+" Slots   "+str(int(slot["maximum"])-int(slot.get("spent",0)))+" / "+number(slot["maximum"]),18))
	if not any_spell:
		p.add_child(label_text("No spells recorded.",17))

func extra_section() -> void:
	var h = row(self)
	var p = panel(h,"Languages & Proficiencies",1.0,"shield")
	for group in [["languages","language_ids"],["proficiencies","proficiency_ids"]]:
		var flow = HFlowContainer.new()
		p.add_child(flow)
		for id in data.get(group[1],[]):
			var b = ref_button(flow,group[0],str(id),"",17)
			b.size_flags_horizontal = Control.SIZE_FILL
			b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var survival = panel(h,"Adventuring",0.85,"health")
	var c = data.get("combat",{})
	for entry in [["Proficiency",number(data.get("proficiency_bonus"),true)],["Passive Perception",number(c.get("passive_perception"))],["Hit Dice",str(int(c.get("hit_dice_total",0))-int(c.get("hit_dice_spent",0)))+" / "+number(c.get("hit_dice_total"))+"  d"+number(c.get("hit_die"))],["Temporary HP",number(c.get("hp_temp"))],["Inspiration","Yes" if c.get("inspiration",false) else "No"],["Death Saves",number(c.get("death_save_successes"))+" successes · "+number(c.get("death_save_failures"))+" failures"],["Exhaustion",number(c.get("exhaustion"))]]:
		var r = row(survival)
		r.add_child(label_text(entry[0],17,GOLD,true))
		r.add_child(label_text(entry[1],17))
	for id in c.get("conditions",[]):
		if id is String:
			ref_button(survival,"conditions",id)
	var notes = panel(self,"Notes & Background",1.0,"star")
	for key in ["description","personality","ideal","bond","flaw","backstory","notes"]:
		var value = str(field(key))
		if not value.is_empty():
			notes.add_child(label_text(str(key).capitalize()+"  ·  "+value,18,IVORY,true))
	for warning in data.get("review_required",[]):
		notes.add_child(label_text("Needs review: "+str(warning),18,GOLD,true))

func display() -> void:
	identity()
	if not data.has("combat"):
		return
	ability_section()
	var middle = row(self)
	attack_section(middle)
	features_section(middle)
	var bottom = row(self)
	item_sections(bottom)
	spell_section(bottom)
	extra_section()
