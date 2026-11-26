extends "res://character_ui.gd"
const CombatEngine=preload("res://combat_engine.gd")
var skins: Dictionary={}
var pending_strip: PanelContainer
var pending_title: Label
var pending_button: Button
var approach_button: Button
var selected_hero: int=0
var action_rows: Array=[]

func _ready():
	super._ready()
	var old=native
	remove_child(old)
	old.queue_free()
	native=CombatEngine.new()
	add_child(native)
	theme.default_font_size=17
	for kind in ["LineEdit","OptionButton","TextEdit","PopupMenu"]:
		for mode in ["normal","hover","pressed","focus","panel"]:
			var s=panel_style()
			s.content_margin_top=6
			s.content_margin_bottom=6
			theme.set_stylebox(mode,kind,s)
		theme.set_color("font_color",kind,Color("f3e4c9"))
	for mode in ["panel","tab_selected","tab_unselected","tab_hovered"]:
		theme.set_stylebox(mode,"TabContainer",panel_style())
		theme.set_stylebox(mode,"TabBar",panel_style())
	var margins=body.get_parent()
	for edge in ["left","right","top","bottom"]: margins.add_theme_constant_override("margin_"+edge,18)
	body.add_theme_constant_override("separation",9)
	# Frame is a non-interactive overlay, not another background behind each panel.
	var border=Panel.new()
	border.mouse_filter=Control.MOUSE_FILTER_IGNORE
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.offset_left=5; border.offset_top=5; border.offset_right=-5; border.offset_bottom=-5
	var frame=StyleBoxFlat.new()
	frame.draw_center=false
	frame.border_color=Color("b38b4b")
	frame.set_border_width_all(1)
	border.add_theme_stylebox_override("panel",frame)
	add_child(border)

func panel_style() -> StyleBoxFlat:
	var s=StyleBoxFlat.new()
	s.bg_color=Color(0.022,0.085,0.095,0.96)
	s.border_color=Color("b18a4c")
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.shadow_color=Color(0,0,0,0.55)
	s.shadow_size=4
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: s.set_content_margin(side,10)
	return s

# Nine-slice vector ornament: the end caps never stretch into the lettering.
func button_skin(mode: String) -> StyleBoxTexture:
	if skins.has(mode): return skins[mode]
	var hot: bool=mode in ["hover","pressed"]
	var edge: String="#ffe3a0" if hot else "#b78b48" if mode!="disabled" else "#566461"
	var top: String="#745020" if hot else "#20494a"
	var svg: String='<svg xmlns="http://www.w3.org/2000/svg" width="180" height="56" viewBox="0 0 180 56"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop stop-color="'+top+'"/><stop offset="1" stop-color="#071e26"/></linearGradient></defs><path d="M13 2 H167 L178 14 V42 L167 54 H13 L2 42 V14 Z" fill="url(#g)" stroke="'+edge+'" stroke-width="2"/><path d="M17 6 H163 L174 17 V39 L163 50 H17 L6 39 V17 Z" fill="none" stroke="#96713e" stroke-width="1"/><path d="M8 28 L15 21 L22 28 L15 35 Z M158 28 L165 21 L172 28 L165 35 Z" fill="none" stroke="'+edge+'" stroke-width="1.5"/></svg>'
	var img=Image.new()
	img.load_svg_from_string(svg)
	var s=StyleBoxTexture.new()
	s.texture=ImageTexture.create_from_image(img)
	for side in [SIDE_LEFT,SIDE_RIGHT]:
		s.set_texture_margin(side,25)
		s.set_content_margin(side,30)
	for side in [SIDE_TOP,SIDE_BOTTOM]:
		s.set_texture_margin(side,14)
		s.set_content_margin(side,7)
	skins[mode]=s
	return s

func button(text: String,callback: Callable) -> Button:
	var b=Button.new()
	b.text=text
	b.custom_minimum_size.y=38
	b.add_theme_font_size_override("font_size",16)
	b.add_theme_color_override("font_color",Color("f1d397"))
	b.add_theme_color_override("font_hover_color",Color("fff2cb"))
	b.add_theme_color_override("font_disabled_color",Color("82918e"))
	for mode in ["normal","hover","pressed","disabled"]: b.add_theme_stylebox_override(mode,button_skin(mode))
	var focus=StyleBoxFlat.new()
	focus.draw_center=false
	focus.border_color=Color("f9d99a")
	focus.set_border_width_all(1)
	b.add_theme_stylebox_override("focus",focus)
	b.pressed.connect(callback)
	return b

func heading(parent: Container,text: String):
	var frame=PanelContainer.new()
	frame.add_theme_stylebox_override("panel",button_skin("normal"))
	parent.add_child(frame)
	var h=label(text,18)
	h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(h)

func menu():
	clear()
	screen_name="menu"
	set_backdrop("castle")
	var row=HBoxContainer.new()
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var col=VBoxContainer.new()
	col.custom_minimum_size.x=455
	col.alignment=BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation",11)
	row.add_child(col)
	var title=label("1NFINITY D&D",50)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub=label("✦  NATIVE GODOT  •  v"+display_version+"  ✦",17)
	sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var gap=Control.new(); gap.custom_minimum_size.y=16; col.add_child(gap)
	for entry in [["Continue adventure",func(): send("list")],["New adventure",func(): roster_mode="new";send("roster")],["Characters",func(): roster_mode="manage";send("roster")],["Settings",func(): send("settings")],["Update centre",func(): send("updates")],["Exit",func(): get_tree().quit()]]:
		var b=button(entry[0],entry[1]); b.custom_minimum_size.y=46; col.add_child(b)
	var spacer=Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(spacer)
	status=label("Campaigns saved locally   •   F11 fullscreen",15)
	body.add_child(status)

func adventure():
	super.adventure()
	action_rows.clear()
	var controls=body.get_child(body.get_child_count()-3)
	action_rows.append(controls)
	var left=portrait.get_parent()
	var left_panel=left.get_parent()
	var scroll=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(scroll)
	left.reparent(scroll)
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if combat_view: arena.get_parent().custom_minimum_size.y=130
	var journal_bg=panel_style(); journal_bg.bg_color=Color("081c23")
	journal.add_theme_stylebox_override("normal",journal_bg)
	journal.add_theme_color_override("default_color",Color("f2eadb"))
	var fill=StyleBoxFlat.new();fill.bg_color=Color("ad3440");fill.set_corner_radius_all(4)
	hpbar.add_theme_stylebox_override("fill",fill)
	hpbar.add_theme_stylebox_override("background",panel_style())
	pending_strip=PanelContainer.new()
	pending_strip.add_theme_stylebox_override("panel",panel_style())
	var r=HBoxContainer.new();pending_strip.add_child(r)
	var die=TextureRect.new();die.texture=load("res://art/d20.png");die.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;die.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;die.custom_minimum_size=Vector2(42,42);r.add_child(die)
	pending_title=label("",17);pending_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pending_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;r.add_child(pending_title)
	pending_button=button("Roll dice",roll_dialog);r.add_child(pending_button)
	body.add_child(pending_strip)
	body.move_child(pending_strip,body.get_child_count()-3)
	pending_strip.hide()
	if combat_view:
		var quick=target_choice.get_parent()
		action_rows.append(quick)
		approach_button=button("Approach target",func():
			if operation=="" and target_choice.selected>=0 and target_choice.selected<target_ids.size(): send("approach",{"target":target_ids[target_choice.selected]}))
		quick.add_child(approach_button)
	else:
		approach_button=null
		controls.add_child(button("Attack",attack_picker))
		controls.add_child(button("Check",func(): action.grab_focus();action.placeholder_text="Describe the ability check you want to attempt"))

func update_scene(data: Dictionary):
	# Publish the saved roll first, even if a portrait or sidebar later fails.
	scene_data=data
	var has_roll: bool=data.get("pending") is Dictionary and not data.player.dead
	roll.disabled=not has_roll
	pending_strip.visible=has_roll
	for row in action_rows: row.visible=not has_roll
	if has_roll:
		var p: Dictionary=data.pending
		pending_title.text="DICE REQUIRED  •  "+str(p.get("skill","Action"))+"\n"+str(p.get("reason","Resolve your action"))
		pending_button.text="Roll "+str(p.get("roll_type","dice"))
		pending_button.disabled=false
		action.editable=false
	super.update_scene(data)
	if combat_view:
		if target_choice.item_count>0 and target_choice.selected<0: target_choice.select(0)
		if is_instance_valid(approach_button): approach_button.disabled=has_roll or data.player.dead or target_choice.item_count==0

func roll_dialog():
	if operation!="" or not scene_data.get("pending") is Dictionary or scene_data.player.dead: return
	roll.disabled=true
	pending_button.disabled=true
	pending_title.text="Resolving the saved roll…"
	send("roll")

func received(op: String,data: Dictionary):
	super.received(op,data)
	if op=="roll" and data.has("error") and screen_name=="adventure" and is_instance_valid(pending_button):
		var current: Dictionary=native.snapshot(native.state,native.active)
		update_scene(current)
		status.text=str(data.error)

func combat_options():
	super.combat_options()
	if choice_kind.selected==0 and str(scene_data.combat.get("awaiting_companion",""))=="":
		player_actions.append("Unarmed strike")
		choice_action.add_item("Unarmed strike")
	if choice_action.item_count>0: choice_action.select(0)

func attack_picker():
	if operation!="" or scene_data.get("pending")!=null or scene_data.player.dead: return
	var d=ConfirmationDialog.new()
	d.title="Choose an attack"
	var v=VBoxContainer.new();d.add_child(v)
	var targets=OptionButton.new();var weapons=OptionButton.new();var ids: Array=[]
	for id in scene_data.npcs:
		var n: Dictionary=scene_data.npcs[id]
		if n.location==scene_data.location and not n.dead:
			ids.append(id);targets.add_item(str(n.name)+" (ID "+str(id)+")")
	if ids.is_empty():
		d.free();status.text="No known target here. Describe the intended attack or look around.";return
	v.add_child(label("Target",18));v.add_child(targets)
	v.add_child(label("Equipped weapon",18));v.add_child(weapons)
	for w in scene_data.weapon_rows: weapons.add_item(str(w.name))
	weapons.add_item("Unarmed strike")
	targets.select(0);weapons.select(0)
	add_child(d)
	d.confirmed.connect(func():
		var command="I attack "+targets.get_item_text(targets.selected)+" with "+weapons.get_item_text(weapons.selected)+"."
		d.queue_free();submit(command))
	d.canceled.connect(d.queue_free)
	d.popup_centered(Vector2i(480,200))

func roster_page():
	clear()
	screen_name="roster"
	set_backdrop("forest")
	var title=label("1NFINITY D&D  •  CHARACTERS",34)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;body.add_child(title)
	var row=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(row)
	var list=panel_column(row,270);heading(list,"YOUR CHARACTERS")
	var sc=ScrollContainer.new();sc.size_flags_vertical=Control.SIZE_EXPAND_FILL;sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;list.add_child(sc)
	var choices=VBoxContainer.new();choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sc.add_child(choices)
	var center=panel_column(row,0);center.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var manage=panel_column(row,230);heading(manage,"MANAGE")
	var heroes: Array=roster_data.get("characters",[])
	for i in range(heroes.size()):
		var p: Dictionary=heroes[i]
		var b=button(str(p.name)+"  •  Lv "+str(int(p.level)),select_hero.bind(i));choices.add_child(b)
	if not heroes.is_empty():
		selected_hero=clampi(selected_hero,0,heroes.size()-1)
		var p: Dictionary=heroes[selected_hero]
		var id: String=str(p.slug)
		heading(center,str(p.name))
		var info=HBoxContainer.new();info.size_flags_vertical=Control.SIZE_EXPAND_FILL;center.add_child(info)
		var pic=hero_portrait(p,Vector2(190,220));info.add_child(pic)
		var desc=VBoxContainer.new();desc.size_flags_horizontal=Control.SIZE_EXPAND_FILL;info.add_child(desc)
		small_text(desc,str(p.race)+" • "+str(p.char_class)+" • Level "+str(int(p.level)))
		var grid=GridContainer.new();grid.columns=3;desc.add_child(grid)
		for a in ["STR","DEX","CON","INT","WIS","CHA"]:
			var tile=PanelContainer.new();tile.add_theme_stylebox_override("panel",panel_style());grid.add_child(tile)
			var l=label(a+"\n"+str(int(p.attributes.get(a,10))),18);l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;tile.add_child(l)
		small_text(desc,"HP %d/%d   •   AC %d\nSpeed %d ft   •   Gold %.2f"%[int(p.hp),int(p.max_hp),int(p.ac),int(p.speed),float(p.gold)])
		heading(center,"EQUIPMENT")
		var gear: Array=[]
		for slot in p.equipped:
			if p.equipped[slot]!=null: gear.append(str(p.equipped[slot]))
		small_text(center,", ".join(gear) if not gear.is_empty() else "No equipment")
		heading(center,"DESCRIPTION");small_text(center,str(p.get("description","")))
		manage.add_child(button("New campaign",func(): campaign_page(id)))
		if roster_mode=="manage":
			manage.add_child(button("Edit character",func(): edit_character(p)))
			manage.add_child(button("Delete character",func(): confirm("Delete this saved character?",func(): send("delete_character",{"character":id}))))
	else:
		heading(center,"No saved adventurers")
		small_text(center,"Create a character to begin your adventure.")
	manage.add_child(button("New character",creator));manage.add_child(button("Main menu",menu))
	status=label("Choose an adventurer",15);body.add_child(status)

func select_hero(index: int):
	selected_hero=index
	roster_page()
