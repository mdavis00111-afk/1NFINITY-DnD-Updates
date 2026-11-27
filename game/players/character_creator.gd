extends Control
## Four horizontal character-sheet screens. Every value is live; portraits are optional.
const RULES = preload("res://rules/character_rules.gd")
const STORE = preload("res://players/character_store.gd")
const GEMINI = preload("res://systems/gemini.gd")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const PORTRAIT = preload("res://themes/parts/portrait_empty.png")
const PORTRAIT_ART = preload("res://players/portrait_art.gd")
const PERSONAL_FIELDS = ["description","personality","ideal","bond","flaw","backstory"]
const PORTRAIT_SHADER = """
shader_type canvas_item;
uniform sampler2D picture : source_color, filter_linear;
uniform vec2 photo_size = vec2(260.0, 540.0);

void fragment() {
	vec4 frame = texture(TEXTURE, UV);
	vec2 center = vec2(130.0, 270.0);
	vec2 point = UV * vec2(260.0, 540.0) - center;
	vec2 capsule = vec2(point.x, point.y - clamp(point.y, -126.0, 126.0));
	float blend = 1.0 - smoothstep(105.0, 108.0, length(capsule));
	vec2 opening = vec2(216.0, 468.0);
	float fit_scale = max(opening.x / photo_size.x, opening.y / photo_size.y);
	vec2 photo_uv = point / (photo_size * fit_scale) + vec2(0.5);
	vec4 photo = texture(picture, clamp(photo_uv, vec2(0.0), vec2(1.0)));
	COLOR = mix(frame, vec4(photo.rgb, 1.0), blend * photo.a);
}
"""
const ICONS = preload("res://themes/parts/icons.png")
const SERIF = preload("res://themes/fonts/EBGaramond.ttf")
const SCENERY = preload("res://art/castle.jpg")
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
var list_regions: Dictionary = {}
var reference_subject: Label
var detail_subject: String = ""
var detail_stage: int = 1
var note: Label
var description_editor: TextEdit
var ai_button: Button
var gemini
var detail_text: String = ""
var pending_render: bool = false
var identity_editors: Dictionary = {}
var picker_overlay: Control

class TipButton extends Button:
	func _make_custom_tooltip(value: String) -> Object:
		var panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#101c30")
		style.border_color = Color("#d6aa62")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(edge,10)
		panel.add_theme_stylebox_override("panel",style)
		var label = Label.new()
		label.text = value.left(450) + ("…" if value.length()>450 else "")
		label.custom_minimum_size.x = 290
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",16)
		label.add_theme_color_override("font_color",Color("#fff0cf"))
		panel.add_child(label)
		return panel

func configure(is_quick: bool, on_exit: Callable, on_finish: Callable, saved: Dictionary = {}) -> void:
	quick = is_quick
	exit_action = on_exit
	finish_action = on_finish
	existing = saved
	draft = rules.fresh()
	draft.merge(saved.get("draft",{}).duplicate(true),true)
	# JSON stores all numbers in one representation, while the rules compare score pools as integers.
	for i in range(draft["roll_pool"].size()):
		draft["roll_pool"][i] = integral_value(draft["roll_pool"][i])
	for dice in draft["roll_history"]:
		if dice is Array:
			for i in range(dice.size()):
				dice[i] = integral_value(dice[i])
	for ability in draft["base_scores"]:
		draft["base_scores"][ability] = integral_value(draft["base_scores"][ability])

func integral_value(value: Variant) -> Variant:
	return int(value) if value is float and value == floor(value) else value

func _ready() -> void:
	var creator_theme = load("res://themes/master_theme.tres").duplicate() as Theme
	creator_theme.default_font = SERIF
	creator_theme.default_font_size = 17
	theme = creator_theme
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

func soft_style(lit: bool = false, field: bool = false) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08,0.14,0.23,0.90 if field else 0.66)
	s.border_color = Color("#ffe3a1") if lit else Color(0.73,0.53,0.27,0.72)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		s.set_content_margin(edge,8 if edge in [SIDE_LEFT,SIDE_RIGHT] else 4)
	if lit:
		s.shadow_color = Color(0.92,0.59,0.18,0.35)
		s.shadow_size = 3
	return s

func score_tile(parent: Container) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var surface = StyleBoxFlat.new()
	surface.bg_color = Color(0.06,0.11,0.19,0.31)
	surface.border_color = Color(0.80,0.62,0.34,0.74)
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(5)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: surface.set_content_margin(edge,4)
	panel.add_theme_stylebox_override("panel",surface)
	parent.add_child(panel)
	return column(panel,4)

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

func icon_texture(key: String) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = ICON_RECTS.get(key,ICON_RECTS["star"])
	return atlas

func icon(key: String, size_px: int = 22) -> TextureRect:
	var view = TextureRect.new()
	view.texture = icon_texture(key)
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
	t.custom_minimum_size.y = 8
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)

func action(parent: Container, caption: String, callback: Callable, highlight: bool = false, font_size: int = 21) -> Button:
	var b = TipButton.new()
	b.text = caption
	b.custom_minimum_size = Vector2(54,32)
	b.add_theme_font_size_override("font_size",font_size)
	b.add_theme_stylebox_override("normal",frame_style(highlight,4))
	b.add_theme_stylebox_override("hover",frame_style(true,4))
	b.add_theme_stylebox_override("pressed",frame_style(true,4))
	b.add_theme_stylebox_override("focus",frame_style(true,4))
	b.add_theme_stylebox_override("disabled",frame_style(false,4))
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

func framed(parent: Container, caption: String = "", ratio: float = 1.0, icon_id: String = "star", compact: bool = false) -> VBoxContainer:
	var p = PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	p.add_theme_stylebox_override("panel",soft_style(false))
	parent.add_child(p)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation",2 if compact else 4)
	p.add_child(v)
	if not caption.is_empty():
		var h = row(v)
		h.add_child(icon(icon_id,18))
		h.add_child(heading(caption,20 if compact else 22))
		if not compact:
			flourish(v)
	return v

func render(preserve_lists: bool = false) -> void:
	pending_render = false
	var offsets: Dictionary = {}
	if preserve_lists:
		for key in list_regions:
			offsets[key] = list_regions[key].scroll_vertical
	list_regions.clear()
	identity_editors.clear()
	if is_instance_valid(picker_overlay):
		picker_overlay.queue_free()
		picker_overlay = null
	if detail_stage != step:
		detail_stage = step
		detail_subject = ""
		detail_text = ""
	if is_instance_valid(body):
		remove_child(body)
		body.queue_free()
	body = MarginContainer.new()
	add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		body.add_theme_constant_override("margin_"+side,12)
	var root = column(body,5)
	var title = centered("Character Creator   ◆   "+str(step)+" / 4",40)
	title.add_theme_font_override("font",SERIF)
	title.add_theme_color_override("font_shadow_color",Color("#a65d14"))
	title.add_theme_constant_override("shadow_offset_x",1)
	title.add_theme_constant_override("shadow_offset_y",2)
	root.add_child(title)
	flourish(root)
	var tabs = row(root,7)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	var tab_names = ["Identity","Ability Scores","Skills & Spells","Loadout & Review"]
	var tab_icons = ["focus","initiative","wand","pack"]
	for i in range(4):
		var index = i+1
		if i > 0:
			tabs.add_child(icon("diamond",12))
		var b = action(tabs,tab_names[i],func(): go_to(index),index==step,19)
		b.icon = icon_texture(tab_icons[i])
		b.add_theme_constant_override("icon_max_width",19)
		b.custom_minimum_size = Vector2(186,33)
		b.disabled = index>step
	var columns = row(root,10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_column(columns)
	form = column(columns,5)
	form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.custom_minimum_size.x = 560
	form.size_flags_stretch_ratio = 3.4
	var side = framed(columns,"Reference",1.0,"wand")
	side.get_parent().custom_minimum_size.x = 218
	side.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var subject = row(side,5)
	subject.add_child(icon(["focus","initiative","wand","pack"][step-1],21))
	reference_subject = heading("",21)
	reference_subject.max_lines_visible = 2
	subject.add_child(reference_subject)
	reference = TextEdit.new()
	reference.editable = false
	reference.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	reference.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reference.custom_minimum_size = Vector2(190,110)
	reference.add_theme_font_size_override("font_size",17)
	reference.add_theme_color_override("font_readonly_color",IVORY)
	var reference_pad = StyleBoxEmpty.new()
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: reference_pad.set_content_margin(edge,7)
	reference.add_theme_stylebox_override("read_only",reference_pad)
	side.add_child(reference)
	var scenery = TextureRect.new()
	# Frame the painted castle without the title from the left side of the menu artwork.
	var landscape = AtlasTexture.new()
	landscape.atlas = SCENERY
	landscape.region = Rect2(900,14,760,570)
	scenery.texture = landscape
	scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scenery.custom_minimum_size.y = 125
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(scenery)
	var guidance = [
		"Choose your origins, background and personal details. Select an option to inspect it.",
		"Your six ability scores shape checks, saving throws, combat and spellcasting. The final values include racial bonuses.",
		"Choose proficiencies and spells. Prepared spells are the spells available to cast from your known options or spellbook.",
		"Review your starting equipment, attacks and proficiencies before saving. Select any entry to inspect it."
	]
	if detail_text.is_empty():
		show_detail(guidance[step-1],tab_names[step-1])
	else:
		show_detail(detail_text,detail_subject)
	if not rules.cat.initialize():
		form.add_child(heading("Cannot open rules database",26))
		form.add_child(heading(rules.cat.last_error,19,IVORY))
	else:
		match step:
			1: identity()
			2: abilities()
			3: features()
			4: loadout()
	note = heading("",16,IVORY)
	note.custom_minimum_size.y = 21
	note.max_lines_visible = 2
	root.add_child(note)
	var nav = row(root,10)
	nav.alignment = BoxContainer.ALIGNMENT_END
	action(nav,"Exit",func(): exit_action.call()).custom_minimum_size = Vector2(94,40)
	if step > 1:
		action(nav,"Back",func(): go_to(step-1)).custom_minimum_size = Vector2(104,40)
	action(nav,"Save Draft",func(): save(false)).custom_minimum_size = Vector2(138,40)
	if step < 4 and not (quick and step==1):
		action(nav,"Next",advance,true).custom_minimum_size = Vector2(138,40)
	elif step == 4:
		action(nav,"Save Character",func(): save(true),true).custom_minimum_size = Vector2(160,40)
		var begin = action(nav,"Begin Adventure",func(): pass)
		begin.custom_minimum_size = Vector2(160,40)
		begin.disabled = true
		begin.tooltip_text = "Campaign play is not available yet."
	for key in offsets:
		if list_regions.has(key):
			list_regions[key].set_deferred("scroll_vertical",offsets[key])

func list_region(parent: Container, key: String, min_height: int = 52) -> VBoxContainer:
	var viewport = ScrollContainer.new()
	viewport.name = key
	viewport.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport.custom_minimum_size.y = min_height
	parent.add_child(viewport)
	list_regions[key] = viewport
	return column(viewport,2)

func go_to(index: int) -> void:
	if index>=1 and index<=step:
		step=index
		render()

func queue_render() -> void:
	if pending_render:
		return
	pending_render = true
	render.call_deferred(true)

func show_detail(value: String, subject: String = "") -> void:
	detail_text = value
	detail_subject = subject if not subject.is_empty() else ["Identity","Ability Scores","Skills & Spells","Loadout & Review"][step-1]
	if is_instance_valid(reference):
		reference.text = value
		reference.scroll_vertical = 0
	if is_instance_valid(reference_subject):
		reference_subject.text = detail_subject

func portrait_column(parent: Container) -> void:
	var p = framed(parent)
	p.get_parent().custom_minimum_size.x = 228 if step < 3 else 174
	p.get_parent().size_flags_horizontal = Control.SIZE_FILL
	p.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var image = TextureRect.new()
	image.texture = PORTRAIT
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(image)
	var path = str(draft.get("portrait",""))
	var picture = PORTRAIT_ART.texture_for(path)
	var shader = Shader.new()
	shader.code = PORTRAIT_SHADER
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("picture",picture)
	material.set_shader_parameter("photo_size",Vector2(picture.get_size()))
	image.material = material
	if step==1 and not quick:
		action(p,"Choose Portrait",choose_portrait,true,18)
		if not path.is_empty():
			action(p,"Clear",func(): draft["portrait"]=""; queue_render(),false,17)
	else:
		var name_label = heading(str(draft.get("name","")),20)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.max_lines_visible = 2
		p.add_child(name_label)
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

func text_field(parent: Container, key: String, placeholder: String, multi: bool = false, height: int = 34) -> Control:
	if multi:
		var edit = TextEdit.new()
		edit.placeholder_text = placeholder
		edit.text = str(draft.get(key,""))
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.custom_minimum_size.y = height
		var normal = soft_style(false,true)
		var focused = soft_style(true,true)
		for edge in [SIDE_TOP,SIDE_BOTTOM]:
			normal.set_content_margin(edge,10)
			focused.set_content_margin(edge,10)
		edit.add_theme_stylebox_override("normal",normal)
		edit.add_theme_stylebox_override("focus",focused)
		edit.add_theme_font_size_override("font_size",17)
		edit.text_changed.connect(func(): draft[key]=edit.text)
		parent.add_child(edit)
		identity_editors[key] = edit
		return edit
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = str(draft.get(key,""))
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.tooltip_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = height
	edit.add_theme_stylebox_override("normal",soft_style(false,true))
	edit.add_theme_stylebox_override("focus",soft_style(true,true))
	edit.text_changed.connect(func(v: String): draft[key]=v)
	parent.add_child(edit)
	identity_editors[key] = edit
	return edit


func readable_value(value: Variant) -> String:
	if value is float and value == floor(value):
		return str(int(value))
	if value is Array:
		var entries: PackedStringArray = []
		for item in value:
			entries.append(readable_value(item))
		return "; ".join(entries)
	if value is Dictionary:
		if value.has("name"):
			return str(value["name"])
		var entries: PackedStringArray = []
		for key in value:
			var heading_text = str(key).replace("_"," ").capitalize()
			if key in ["index","url","option_type","type"]:
				continue
			if key in ["options_array","items","from","of"]:
				entries.append(readable_value(value[key]))
			elif key in ["counted_reference","choice","item"]:
				entries.append(readable_value(value[key]))
			elif key in ["count","quantity"]:
				entries.append("×"+readable_value(value[key]))
			elif key == "hit_die":
				entries.append("d"+readable_value(value[key]))
			else:
				entries.append(heading_text+": "+readable_value(value[key]))
		return ", ".join(entries)
	if value == null:
		return "—"
	return str(value)

func record_detail(table: String, id: String) -> String:
	if table == "proficiencies" and id.begins_with("skill-"):
		return record_detail("skills",id.trim_prefix("skill-"))
	var record = rules.cat.get_record(table,id)
	if record.is_empty():
		return rules.cat.describe(table,id)
	var sections: PackedStringArray = []
	for key in ["synopsis","desc"]:
		var text = record.get(key,"")
		if text is Array and not text.is_empty():
			sections.append("\n\n".join(PackedStringArray(text)))
		elif text is String and not text.is_empty():
			sections.append(text)
	for key in ["size_description","age","alignment","hit_die","speed","size","ability_bonuses","saving_throws","proficiencies","languages","range","casting_time","duration","components","material","higher_level","damage","armor_class","cost","weight","properties","contents","starting_equipment","starting_equipment_options","proficiency_choices","language_options","school","script"]:
		if record.has(key) and record[key] != null:
			var value = "d"+readable_value(record[key]) if key == "hit_die" else readable_value(record[key])
			if not value.is_empty():
				sections.append(str(key).replace("_"," ").capitalize()+": "+value)
	if table in ["races","subraces"]:
		for trait_id in rules.cat.references(record.get("traits",record.get("racial_traits",[]))):
			var trait_record = rules.cat.get_record("traits",trait_id)
			sections.append(rules.cat.title("traits",trait_id)+"\n"+readable_value(trait_record.get("desc",[])))
	if table == "classes":
		for feature_id in rules.cat.references(rules.cat.get_record("levels",id+"-1").get("features",[])):
			sections.append(rules.cat.title("features",feature_id)+"\n"+readable_value(rules.cat.get_record("features",feature_id).get("desc",[])))
	return "\n\n".join(sections) if not sections.is_empty() else rules.cat.title(table,id)

func options_text(opt: Dictionary) -> String:
	var descriptions: PackedStringArray = []
	for part in opt.get("parts",[]):
		if part["table"]=="text":
			descriptions.append(str(part["id"]).capitalize())
		else:
			var table = str(part["table"])
			var id = str(part["id"])
			descriptions.append(rules.cat.title(table,id)+"\n"+record_detail(table,id))
	return "\n\n────────\n\n".join(descriptions) if not descriptions.is_empty() else str(opt.get("label",""))

func close_picker() -> void:
	if is_instance_valid(picker_overlay):
		var old = picker_overlay
		picker_overlay = null
		old.hide()
		old.queue_free()

func choose_popup(caption: String, options: Array, callback: Callable, current: String = "") -> void:
	close_picker()
	var anchor = get_local_mouse_position()
	var focused = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and is_ancestor_of(focused):
		anchor = get_global_transform().affine_inverse() * focused.get_global_rect().end
		anchor.x -= focused.size.x
	picker_overlay = Control.new()
	picker_overlay.name = "ChoiceOverlay"
	add_child(picker_overlay)
	picker_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay = picker_overlay
	var scrim = ColorRect.new()
	scrim.color = Color(0,0,0,0.16)
	overlay.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: close_picker())
	var panel = PanelContainer.new()
	panel.name = "ChoiceDropdown"
	panel.add_theme_stylebox_override("panel",soft_style(true,true))
	overlay.add_child(panel)
	var extent = Vector2(minf(430.0,maxf(220.0,size.x-24.0)),minf(315.0,maxf(210.0,size.y-24.0)))
	panel.position = Vector2(clampf(anchor.x,12.0,maxf(12.0,size.x-extent.x-12.0)),clampf(anchor.y,12.0,maxf(12.0,size.y-extent.y-12.0)))
	panel.size = extent
	var shell = column(panel,4)
	var title = heading(caption,18)
	title.max_lines_visible = 2
	shell.add_child(title)
	var search = LineEdit.new()
	search.placeholder_text = "Search…"
	search.alignment = HORIZONTAL_ALIGNMENT_CENTER
	search.add_theme_stylebox_override("normal",soft_style(false,true))
	search.add_theme_stylebox_override("focus",soft_style(true,true))
	shell.add_child(search)
	var list = ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 100
	list.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	list.add_theme_stylebox_override("selected",soft_style(true,true))
	list.add_theme_stylebox_override("selected_focus",soft_style(true,true))
	list.add_theme_color_override("font_selected_color",IVORY)
	shell.add_child(list)
	var filtered: Array = []
	var refresh = func():
		filtered.clear()
		list.clear()
		for opt in options:
			if search.text.strip_edges().is_empty() or str(opt["label"]).to_lower().contains(search.text.to_lower()):
				filtered.append(opt)
				list.add_item(str(opt["label"]),icon_texture("diamond"))
				list.set_item_tooltip_enabled(list.item_count-1,false)
		for i in range(filtered.size()):
			if filtered[i]["key"] == current and not current.is_empty():
				list.select(i)
				break
	var select = func(i: int):
		if picker_overlay == overlay and i>=0 and i<filtered.size():
			var opt = filtered[i]
			show_detail(options_text(opt),str(opt["label"]))
			close_picker()
			callback.call(str(opt["key"]))
	list.item_selected.connect(select)
	list.item_activated.connect(select)
	list.item_clicked.connect(func(index: int, _position: Vector2, mouse_button: int):
		if mouse_button == MOUSE_BUTTON_LEFT: select.call(index))
	search.text_changed.connect(func(_value: String): refresh.call())
	search.text_submitted.connect(func(_value: String):
		if filtered.size()==1: select.call(0))
	var nav = row(shell)
	nav.alignment = BoxContainer.ALIGNMENT_END
	action(nav,"Cancel",close_picker,false,16).custom_minimum_size = Vector2(90,32)
	for control in [search,list]:
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
				close_picker()
				get_viewport().set_input_as_handled())
	refresh.call()
	search.grab_focus()


func identity_choice(parent: Container, caption: String, table: String, key: String, records: Array) -> void:
	var options: Array = []
	for rec in records:
		options.append({"key":str(rec["index"]),"label":str(rec["name"]),"parts":[{"table":table,"id":str(rec["index"])}]})
	var id = str(draft.get(key,""))
	var field = column(parent,1)
	var b = action(field,(caption if id.is_empty() else rules.cat.title(table,id))+"  ▾",func(): choose_popup(caption,options,func(value: String):
		if draft.get(key,"")!=value:
			draft[key]=value
			if key=="race_id": draft["subrace_id"]=""
			if key=="class_id": draft["subclass_id"]=""
			draft["answers"]={}
			for equipment_key in ["equipped_armor","equipped_shield","equipped_weapons"]: draft.erase(equipment_key)
			queue_render(),id),false,17)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal",soft_style(false,true))
	b.tooltip_text = caption if id.is_empty() else caption + ": " + rules.cat.summary(table,id)

func simple_choice(parent: Container, caption: String, key: String, choices: Array) -> void:
	var options: Array = []
	for value in choices:
		options.append({"key":value,"label":value})
	var current = str(draft.get(key,""))
	var field = column(parent,1)
	var b = action(field,(caption if current.is_empty() else current)+"  ▾",func(): choose_popup(caption,options,func(v: String): draft[key]=v; queue_render(),current),false,17)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal",soft_style(false,true))
	b.tooltip_text = caption

func labelled_field(parent: Container, caption: String, image_id: String) -> VBoxContainer:
	var field = column(parent,1)
	var h = row(field,4)
	h.add_child(icon(image_id,15))
	h.add_child(heading(caption,17))
	return field

func identity() -> void:
	var pane = framed(form,"Identity",1.0,"focus",true)
	pane.add_child(heading("Choose your origins, background and personal details.",17,IVORY))
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
	var desc = framed(form)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var h = row(desc)
	h.add_child(icon("wand",17))
	h.add_child(heading("Description",22))
	ai_button = action(h,"Generate with AI",generate_description,true,17)
	ai_button.custom_minimum_size.x = 140
	ai_button.disabled = gemini.active
	description_editor = text_field(desc,"description","Character description",true,100) as TextEdit
	description_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var character_details = [
		["personality","Personality","focus"],["ideal","Ideal","star"],
		["bond","Bond","diamond"],["flaw","Flaw","shield"],["backstory","Backstory","pack"]
	]
	for pair in character_details:
		text_field(desc,pair[0],pair[1],false,29)

func generate_description() -> void:
	var context: Dictionary = {}
	context["description"] = draft.get("description","")
	for pair in [["race_id","races"],["subrace_id","subraces"],["class_id","classes"],["subclass_id","subclasses"],["background_id","backgrounds"]]:
		var id = str(draft.get(pair[0],""))
		if not id.is_empty(): context[pair[0]]=rules.cat.title(pair[1],id)
	for key in ["name","sex","alignment","personality","ideal","bond","flaw","backstory"]:
		context[key]=draft.get(key,"")
	if str(draft.get("race_id","")).is_empty() or str(draft.get("class_id","")).is_empty():
		note.text="Choose a race and class first."
		return
	ai_button.disabled=true
	note.text="Generating character details…"
	gemini.generate("Write grounded fantasy character details using the supplied identity and existing text as context. No epic destiny, mechanical abilities, equipment, stats or dice. Return ONLY a JSON object with six nonempty string keys: description (2–3 sentences), personality, ideal, bond, flaw (one concise sentence each), backstory (2–4 sentences). Keep the total under 2500 characters. No markdown or additional keys. Character: "+JSON.stringify(context))

func description_received(ok: bool, message: String) -> void:
	if is_instance_valid(ai_button): ai_button.disabled=false
	if not ok:
		if is_instance_valid(note): note.text=message
		return
	var cleaned = message.strip_edges()
	if cleaned.begins_with("```") and cleaned.ends_with("```"):
		var newline = cleaned.find("\n")
		if newline>=0: cleaned = cleaned.substr(newline+1,cleaned.length()-newline-4).strip_edges()
	var parsed = JSON.parse_string(cleaned)
	if not parsed is Dictionary:
		if is_instance_valid(note): note.text="AI response was not valid character JSON. Existing details kept."
		return
	for key in PERSONAL_FIELDS:
		if not parsed.get(key) is String or str(parsed[key]).strip_edges().is_empty():
			if is_instance_valid(note): note.text="AI response omitted "+key+". Existing details kept."
			return
	for key in PERSONAL_FIELDS:
		draft[key]=str(parsed[key]).strip_edges().left(3000)
		var editor = identity_editors.get(key)
		if step==1 and is_instance_valid(editor): editor.text=draft[key]
	if is_instance_valid(note): note.text="All character details generated. Edit freely."


func stat_card(parent: Container, caption: String, value: String, image_id: String = "star") -> VBoxContainer:
	var v = score_tile(parent)
	var h = row(v,3)
	h.add_child(icon(image_id,15))
	var title = heading(caption,15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.max_lines_visible = 2
	h.add_child(title)
	v.add_child(centered(value,25,IVORY))
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
	var generation = framed(form,"Score Generation",1.0,"initiative",true)
	var h = row(generation)
	for pair in [["roll","Roll 4d6, Drop Lowest"],["array","Standard Array"],["point","Point Buy 27"]]:
		var method = str(pair[0])
		var b = action(h,pair[1],func(): rules.roll_scores(draft,method); render(),draft.get("ability_method")==method,19)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var has_scores = not str(draft.get("ability_method","")).is_empty()
	var reroll = action(generation,"Reroll",func(): rules.roll_scores(draft,"roll"); render(),false,17)
	reroll.size_flags_horizontal = Control.SIZE_SHRINK_END
	reroll.custom_minimum_size.x = 100
	reroll.disabled = draft.get("ability_method","")!="roll"
	if draft["ability_method"]=="point":
		generation.add_child(centered(str(27-rules.points_used(draft))+" / 27 points remaining",20))
	var result = rules.scores(draft) if has_scores else {}
	var score_panel = framed(form,"Ability Scores",1.0,"focus",true)
	var cards = row(score_panel,3)
	for a in RULES.ABILITIES:
		var score = int(result.get(a,0))
		var base = int(draft["base_scores"].get(a,0))
		var card = score_tile(cards)
		var label = action(card,a.to_upper(),func(): show_detail(record_detail("ability-scores",a),rules.cat.title("ability-scores",a)),false,18)
		label.custom_minimum_size.x=0
		label.custom_minimum_size.y=27
		label.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
		label.icon = icon_texture(["shield","speed","health","focus","wand","star"][RULES.ABILITIES.find(a)])
		label.add_theme_constant_override("icon_max_width",15)
		card.add_child(centered(str(score)+" (%+d)" % rules.mod_for(score) if has_scores else "—",25,IVORY))
		card.add_child(centered("Base "+str(base)+(" +"+str(score-base) if score!=base else "") if has_scores else "Not rolled",15,IVORY))
		if draft["ability_method"]=="point":
			var buttons = row(card,2)
			var minus=action(buttons,"−",func(): change_point(a,-1),false,17)
			minus.custom_minimum_size.x=20
			var plus=action(buttons,"+",func(): change_point(a,1),false,17)
			plus.custom_minimum_size.x=20
		else:
			var b=action(card,"Swap",func(): swap_score(a),false,17)
			b.custom_minimum_size.x=0
			b.disabled = not has_scores
	if has_scores:
		for g in rules.groups(draft,2): group_ui(score_panel,g)
	if not has_scores or draft["ability_method"]=="roll":
		var history=framed(form,"Roll History",1.0,"initiative",true)
		var roll_cards=row(history,3)
		var by_total: Dictionary = {}
		for dice in draft["roll_history"]:
			if not dice is Array or dice.size() != 4:
				continue
			var sorted = dice.duplicate()
			sorted.sort()
			var total = int(sorted[1])+int(sorted[2])+int(sorted[3])
			if not by_total.has(total):
				by_total[total] = []
			by_total[total].append({"dice": dice, "dropped": int(sorted[0])})
		for ability in RULES.ABILITIES:
			var total = int(draft["base_scores"].get(ability,0))
			var card = score_tile(roll_cards)
			card.add_child(centered(ability.to_upper()+" · "+(str(total) if has_scores else "—"),18,IVORY))
			var matching: Array = by_total.get(total,[])
			if matching.is_empty():
				card.add_child(centered("Awaiting roll",14,IVORY))
				continue
			var roll: Dictionary = matching.pop_front()
			var dice = ", ".join(PackedStringArray(roll["dice"].map(func(die): return str(int(die)))))
			card.add_child(centered(dice+" · Drop "+str(roll["dropped"]),14,IVORY))
	if not has_scores:
		var empty_stats = framed(form,"Derived Statistics",1.0,"star",true)
		var empty_row = row(empty_stats,5)
		for caption in ["Initiative","Hit Points","Passive Perception","Save DC","Spell Attack"]:
			stat_card(empty_row,caption,"—")
		return
	var preview=rules.full_record(draft)
	var c=preview["combat"]
	var sp=preview["spellcasting"]
	var stats=framed(form,"Derived Statistics",1.0,"star",true)
	var r=row(stats,4)
	stat_card(r,"Initiative","%+d" % int(c["initiative"]),"initiative")
	stat_card(r,"Hit Points",str(c["hp_max"]),"health")
	stat_card(r,"Passive Perception",str(c["passive_perception"]),"focus")
	if sp["save_dc"]!=null:
		stat_card(r,"Save DC",str(sp["save_dc"]),"wand")
		stat_card(r,"Spell Attack","%+d" % int(sp["attack_bonus"]),"wand")

func group_title(g: Dictionary) -> String:
	var titles = {"class-cantrips":"Cantrips","racial-cantrip":"Racial Cantrip","spellbook":"Spellbook","prepared":"Prepared Spells","known":"Known Spells","race-bonus":"Racial Bonuses","expertise":"Expertise","favored-enemy":"Favored Enemy","favored-terrain":"Favored Terrain","enemy-language":"Enemy Language"}
	if titles.has(g["key"]): return titles[g["key"]]
	if g["kind"]=="gear": return "Equipment Choice "+str(int(str(g["key"]).get_slice("-",1))+1)
	if g["kind"]=="profs":
		if not g["options"].is_empty() and str(g["options"][0]["parts"][0]["id"]).begins_with("skill-"): return "Skill Proficiencies"
		return "Tool Proficiencies"
	if g["kind"]=="languages":
		var key = str(g["key"])
		if key.begins_with("trait-language-"):
			return "Languages · "+rules.cat.title("traits",key.trim_prefix("trait-language-"))
		var source = key.trim_prefix("language-")
		var table = "backgrounds" if source == draft.get("background_id","") else "races"
		return "Languages · "+rules.cat.title(table,source)
	return str(g["label"])

func group_ui(parent: Container,g: Dictionary) -> void:
	var count=rules.selected(draft,g).size()
	var title=heading(group_title(g)+"   "+str(count)+" / "+str(g["count"]),20)
	title.tooltip_text=""
	parent.add_child(title)
	var answers = draft.get("answers",{}).get(g["key"],[])
	var spell_group = g["kind"] in ["cantrips","racial-spell","known-spells","prepared"]
	if spell_group:
		table_header(parent,["Spell","School","Effect"],[0,78,142])
	var columns: HBoxContainer
	for slot in range(int(g["count"])):
		if spell_group or slot%2==0: columns=row(parent,4)
		var current = str(answers[slot]) if slot<answers.size() and answers[slot]!=null else ""
		var available: Array=[]
		var caption = "+ Select"
		var tip = ""
		var school = "—"
		var effect = "—"
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
				if spell_group:
					var spell = rules.cat.get_record("spells",str(opt["parts"][0]["id"]))
					school = readable_value(spell.get("school"))
					var descriptions = spell.get("desc",[])
					effect = str(descriptions[0]) if descriptions is Array and not descriptions.is_empty() else str(descriptions)
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
					for equipment_key in ["equipped_armor","equipped_shield","equipped_weapons"]: draft.erase(equipment_key)
				queue_render(),current)
		var b=action(columns,caption+"  ▾",choose_slot,false,18)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.tooltip_text=tip
		b.add_theme_stylebox_override("normal",soft_style(false,true))
		b.disabled=available.is_empty()
		if spell_group:
			b.icon = icon_texture("wand")
			b.add_theme_constant_override("icon_max_width",15)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			for field in [[school,78],[effect,142]]:
				var value = heading(field[0],15,IVORY)
				value.custom_minimum_size.x = field[1]
				value.size_flags_horizontal = Control.SIZE_FILL
				value.autowrap_mode = TextServer.AUTOWRAP_OFF
				value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				value.max_lines_visible = 1
				value.tooltip_text = ""
				columns.add_child(value)

func reference_link(parent: Container,table: String,id: String,caption: String="") -> Button:
	var b = TipButton.new()
	b.text = caption if not caption.is_empty() else rules.cat.title(table,id)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = icon_texture({"spells":"wand","equipment":"pack","skills":"focus","ability-scores":"shield"}.get(table,"diamond"))
	b.add_theme_constant_override("icon_max_width",14)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size",16)
	b.add_theme_color_override("font_color",IVORY)
	b.tooltip_text=record_detail(table,id).left(450)
	b.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover",soft_style(true))
	b.add_theme_stylebox_override("pressed",soft_style(true))
	b.pressed.connect(func(): show_detail(record_detail(table,id),rules.cat.title(table,id)))
	parent.add_child(b)
	return b

func compact_panel(parent: Container, title: String, key: String, ratio: float, image_id: String, minimum: int = 55) -> VBoxContainer:
	var panel = framed(parent,title,ratio,image_id)
	panel.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	return list_region(panel,key,minimum)

func table_header(parent: Container, labels: Array, widths: Array) -> void:
	var h = row(parent,7)
	for i in range(labels.size()):
		var label = heading(str(labels[i]),15)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if i > 0:
			label.custom_minimum_size.x = widths[i]
			label.size_flags_horizontal = Control.SIZE_FILL
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(label)
	var divider = ColorRect.new()
	divider.color = Color("#a57b3a")
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(divider)

func table_entry(parent: Container, table: String, id: String, caption: String, values: Array, widths: Array) -> void:
	var h = row(parent,7)
	var b = reference_link(h,table,id,caption)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(values.size()):
		var label = heading(str(values[i]),15,IVORY)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = widths[i]
		label.size_flags_horizontal = Control.SIZE_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(label)

func features() -> void:
	var rec = rules.full_record(draft)
	var sp = rec["spellcasting"]
	var groups = rules.groups(draft,3)
	var top = framed(form,"Spellcasting & Proficiencies",1.0,"wand")
	var stats = row(top,4)
	stat_card(stats,"Proficiency","%+d" % int(rec["proficiency_bonus"]),"star")
	if sp["save_dc"] != null:
		var slots = sp["slots"]["1"]
		stat_card(stats,"Ability",str(sp["ability"]).to_upper(),"focus")
		stat_card(stats,"Save DC",str(sp["save_dc"]),"wand")
		stat_card(stats,"Spell Attack","%+d" % int(sp["attack_bonus"]),"wand")
		stat_card(stats,"Level 1 Slots","%d / %d" % [int(slots["maximum"])-int(slots["spent"]),int(slots["maximum"])],"focus")
		var totals: PackedStringArray = []
		for group in groups:
			if group["kind"] in ["cantrips","racial-spell","known-spells","prepared"]:
				totals.append("%s %d / %d" % [group_title(group),rules.selected(draft,group).size(),int(group["count"])])
		if not totals.is_empty():
			top.add_child(heading("   ·   ".join(totals),16,IVORY))
	var cols = row(form,5)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left = compact_panel(cols,"Skills & Saving Throws","SkillsAndSaves",0.92,"focus",115)
	table_header(left,["Skill","Bonus"],[0,50])
	for id in rec["skills"]:
		var skill = rec["skills"][id]
		var state = "◆ " if skill["proficient"] else "◇ "
		table_entry(left,"skills",id,state+rules.cat.title("skills",id)+" ("+str(skill["ability"]).capitalize()+")",["%+d" % int(skill["modifier"])],[50])
	table_header(left,["Saving Throw","Bonus"],[0,50])
	for ability in RULES.ABILITIES:
		var state = "◆ " if "saving-throw-"+ability in rec["proficiency_ids"] else "◇ "
		table_entry(left,"ability-scores",ability,state+rules.cat.title("ability-scores",ability),["%+d" % int(rec["saving_throws"][ability])],[50])
	var choices = compact_panel(cols,"Selections","SkillAndSpellChoices",1.55,"wand",115)
	for group in groups:
		group_ui(choices,group)
	if not sp["always_prepared_ids"].is_empty():
		choices.add_child(heading("Always Prepared",18))
	for id in sp["always_prepared_ids"]:
		reference_link(choices,"spells",id,rules.cat.title("spells",id)+" · Always prepared")
	var base = rules.base(draft)
	if not base["langs"].is_empty():
		choices.add_child(heading("Granted Languages",18))
		for id in base["langs"]:
			reference_link(choices,"languages",id)
	if not base["traits"].is_empty() or not base["features"].is_empty():
		choices.add_child(heading("Features & Traits",18))
		for id in base["traits"]:
			reference_link(choices,"traits",id)
		for id in base["features"]:
			reference_link(choices,"features",id)

func loadout() -> void:
	var rec = rules.full_record(draft)
	var c = rec["combat"]
	var sp = rec["spellcasting"]
	var identity_bar = framed(form)
	var details = row(identity_bar,6)
	var name_label = heading(str(rec["name"]),24)
	name_label.size_flags_stretch_ratio = 2.6
	name_label.max_lines_visible = 1
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = str(rec["name"])
	details.add_child(name_label)
	for field in [["races","race_id","focus"],["classes","class_id","shield"],["backgrounds","background_id","pack"]]:
		details.add_child(icon(field[2],15))
		var label = heading(rules.cat.title(field[0],rec[field[1]]),16,IVORY)
		label.max_lines_visible = 1
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		details.add_child(label)
	details.add_child(heading(str(rec["alignment"]),16,IVORY))
	details.add_child(heading("Level "+str(int(rec["level"])),17))
	var stats = row(form,4)
	stat_card(stats,"Armor Class",str(c["armor_class"]),"armor")
	stat_card(stats,"Hit Points","%d / %d" % [int(c["hp_current"]),int(c["hp_max"])],"health")
	stat_card(stats,"Initiative","%+d" % int(c["initiative"]),"initiative")
	stat_card(stats,"Speed","%d ft." % int(c["speed_feet"]),"speed")
	stat_card(stats,"Proficiency","%+d" % int(rec["proficiency_bonus"]),"star")
	stat_card(stats,"Save DC",str(sp["save_dc"]) if sp["save_dc"] != null else "—","wand")
	var columns = row(form,5)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var equip = compact_panel(columns,"Equipment","EquipmentChoices",1.05,"shield")
	for group in rules.groups(draft,4):
		group_ui(equip,group)
	equipment_selector(equip,rec,"armor")
	equipment_selector(equip,rec,"shield")
	var inventory = compact_panel(columns,"Inventory","Inventory",0.88,"pack")
	table_header(inventory,["Item","Qty"],[0,32])
	var attacks = compact_panel(columns,"Attacks","Attacks",1.4,"initiative")
	table_header(attacks,["Attack","To Hit","Damage","Type"],[0,40,48,60])
	for item in rec["inventory"]:
		var id = str(item["item_id"])
		var item_title = rules.cat.title("equipment",id)
		table_entry(inventory,"equipment",id,item_title,[int(item["quantity"])],[32])
		if item.get("equipped",false):
			reference_link(equip,"equipment",id,item_title)
		if rules.cat.get_record("equipment",id).has("weapon_category"):
			var equipped = id in draft.get("equipped_weapons",[])
			action(equip,("◆ " if equipped else "◇ ")+item_title,func(): toggle_weapon(id),equipped,16)
	for attack in rec["attacks"]:
		var id = str(attack["item_id"])
		var damage = str(attack["damage_dice"])+"%+d" % int(attack["damage_modifier"])
		table_entry(attacks,"equipment",id,rules.cat.title("equipment",id),["%+d" % int(attack["attack_bonus"]),damage,str(attack["damage_type"]).capitalize()],[40,48,60])
	for key in ["cantrip_ids","racial_cantrip_ids"]:
		for id in sp[key]:
			reference_link(attacks,"spells",id)
	inventory.add_child(heading("Weight: "+readable_value(rec["carried_weight_lb"])+" lb",16,IVORY))
	var lower = row(form,5)
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var traits = compact_panel(lower,"Features & Traits","FeaturesAndTraits",1.1,"star")
	for id in rec["racial_trait_ids"]:
		reference_link(traits,"traits",id)
	for id in rec["class_feature_ids"]:
		reference_link(traits,"features",id)
	for warning in rec["review_required"]:
		traits.add_child(heading("Review: "+str(warning),16,IVORY))
	var proficiencies = compact_panel(lower,"Languages & Proficiencies","LanguagesAndProficiencies",0.9,"focus")
	for id in rec["language_ids"]:
		reference_link(proficiencies,"languages",id)
	for id in rec["proficiency_ids"]:
		reference_link(proficiencies,"proficiencies",id)
	var coins = framed(lower,"Coins",0.4,"diamond")
	for key in ["cp","sp","ep","gp","pp"]:
		coins.add_child(centered("%d %s" % [int(rec["coins"][key]),key],16,IVORY))

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
			queue_render(),current)
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
