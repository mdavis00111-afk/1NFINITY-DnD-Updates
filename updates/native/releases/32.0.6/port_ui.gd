extends "res://visual_ui.gd"
const PortEngine=preload("res://port_engine.gd")
var roll_animation=false

func _ready():
	super._ready()
	var previous=native
	remove_child(previous)
	previous.queue_free()
	native=PortEngine.new()
	add_child(native)
	# Actual opaque reading panels; scenery is never used as a widget fill.
	for child in get_children():
		if child is ColorRect:
			child.color=Color(0.015,0.045,0.06,0.64)
			child.mouse_filter=Control.MOUSE_FILTER_IGNORE
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	gold=Color("f1d59d")
	menu()

func panel_style() -> StyleBoxFlat:
	var style=super.panel_style()
	style.bg_color=Color("0b2229")
	style.border_color=Color("c69b56")
	style.set_content_margin(SIDE_LEFT,8)
	style.set_content_margin(SIDE_RIGHT,8)
	style.set_content_margin(SIDE_TOP,7)
	style.set_content_margin(SIDE_BOTTOM,7)
	return style

func button(text: String,callback: Callable) -> Button:
	var b=super.button(text,callback)
	b.custom_minimum_size=Vector2(92,36)
	b.clip_text=true
	b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text=text
	return b

func set_backdrop(kind: String):
	var preferred="varied"
	if is_instance_valid(native):preferred=str(native.cfg.get("background","varied"))
	super.set_backdrop(kind if preferred=="varied" else preferred)
	backdrop.modulate=Color(0.86,0.86,0.86,1)
	backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	for child in get_children():
		if child is ColorRect:
			child.color=Color(0.015,0.045,0.06,0.64)

func menu_texture(svg: String) -> Texture2D:
	var img=Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)

func menu():
	super.menu()
	# The inherited menu supplies the same navigation callbacks as v32.0.5.
	var row=body.get_child(0)
	if not row is HBoxContainer:return
	var col=row.get_child(0)
	col.custom_minimum_size.x=465
	col.add_theme_constant_override("separation",9)
	backdrop.texture=load("res://art/castle.jpg")
	backdrop.modulate=Color.WHITE
	for child in get_children():
		if child is ColorRect:
			child.color=Color(0.015,0.045,0.06,0.12)
	var title=col.get_child(0) as Label
	title.text="1NFINITY D&D"
	title.add_theme_font_size_override("font_size",51)
	title.add_theme_color_override("font_color",Color("ffe1a0"))
	title.add_theme_color_override("font_shadow_color",Color("321b08"))
	title.add_theme_constant_override("shadow_offset_x",2)
	title.add_theme_constant_override("shadow_offset_y",3)
	var subtitle=col.get_child(1) as Label
	subtitle.text="━━━━  GODOT EDITION  ━━━━"
	subtitle.add_theme_font_size_override("font_size",19)
	var crest=TextureRect.new()
	crest.texture=menu_texture('<svg xmlns="http://www.w3.org/2000/svg" width="180" height="92" viewBox="0 0 180 92"><defs><linearGradient id="gold" x2="0" y2="1"><stop stop-color="#fff2bd"/><stop offset="1" stop-color="#b97a25"/></linearGradient></defs><path d="M20 78 A70 70 0 0 1 160 78 M28 78 A62 62 0 0 1 152 78" fill="none" stroke="#d9aa55"/><path d="M90 4 L95 17 L90 30 L85 17 Z" fill="#ffe2a0"/><path d="M105 76 C62 91 51 59 66 37 C78 20 106 25 112 42 L130 48 L119 55 L105 51 L99 63 L119 65 L112 72 C90 69 81 56 89 43 C73 48 73 71 105 76 Z" fill="url(#gold)" stroke="#ffe2a0"/><path d="M76 36 L71 19 L87 32 L94 18 L101 34 M105 42 L109 42" fill="none" stroke="#ffe2a0" stroke-width="2"/></svg>')
	crest.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.custom_minimum_size=Vector2(180,82)
	crest.mouse_filter=Control.MOUSE_FILTER_IGNORE
	col.add_child(crest)
	col.move_child(crest,0)
	var captions=["CONTINUE ADVENTURE","NEW ADVENTURE","CHARACTERS","SETTINGS","UPDATE CENTRE","EXIT"]
	var glyphs=["▶","▤","♟","⚙","↓","↪"]
	var index=0
	for child in col.get_children():
		if child is Button:
			child.text=glyphs[index]+"     "+captions[index]
			child.custom_minimum_size.y=46
			child.alignment=HORIZONTAL_ALIGNMENT_LEFT
			child.add_theme_font_size_override("font_size",22)
			child.add_theme_color_override("font_color",Color("ffe3aa"))
			index+=1
	# Reuse the existing status label so error reporting remains intact.
	body.remove_child(status)
	var footer=HBoxContainer.new()
	body.add_child(footer)
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	status.text="F11 fullscreen  •  Campaigns saved locally"
	footer.add_child(status)
	var update=button("Update  •  v"+display_version,func():send("updates"))
	update.custom_minimum_size=Vector2(210,38)
	footer.add_child(update)

func received(op: String,data: Dictionary):
	if not data.has("error") and op=="list":
		operation=""
		campaign_cards(data)
		return
	if not data.has("error") and (op=="appearance" or op=="save_guidance"):
		operation=""
		settings_page(data)
		return
	if not data.has("error") and op=="import_legacy":
		operation=""
		status.text="Imported "+str(data.imported)+" as "+str(data.slug)+". Original file unchanged."
		return
	if not data.has("error") and op=="dm_guidance":
		operation=""
		guidance_dialog(data.get("guidance",{}))
		return
	if not data.has("error") and op=="diagnostics":
		operation=""
		status.text="Native diagnostics ready."
		var lines: Array=[]
		for key in data.get("checks",{}):lines.append(("PASS  " if data.checks[key] else "FAIL  ")+str(key))
		show_info("Native diagnostics","Version: "+str(data.version)+"\nRuntime: Godot / GDScript\nAPI configured: "+str(data.configured)+"\nModel: "+str(data.model)+"\nClass definitions: "+str(data.rules)+"\nSpell entries: "+str(data.spells)+"\nMonster entries: "+str(data.monsters)+"\nLocal storage: "+str(data.save_folder)+"\n\n"+ "\n".join(lines))
		return
	super.received(op,data)

func campaign_cards(data: Dictionary):
	clear()
	screen_name="campaigns"
	set_backdrop("lake")
	forge_title("CONTINUE ADVENTURE","Select a saved world")
	var row=HBoxContainer.new()
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var list=panel_column(row,0)
	var sc=ScrollContainer.new()
	sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical=Control.SIZE_EXPAND_FILL
	list.add_child(sc)
	var v=VBoxContainer.new()
	v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation",8)
	sc.add_child(v)
	for campaign in data.get("campaigns",[]):
		var id=str(campaign.slug)
		var card=PanelContainer.new()
		card.add_theme_stylebox_override("panel",panel_style())
		v.add_child(card)
		var item_row=HBoxContainer.new()
		item_row.add_theme_constant_override("separation",12)
		card.add_child(item_row)
		item_row.add_child(hero_portrait(campaign.player,Vector2(76,96)))
		var details=VBoxContainer.new()
		details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		details.alignment=BoxContainer.ALIGNMENT_CENTER
		item_row.add_child(details)
		var name=label(str(campaign.name),22)
		name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		details.add_child(name)
		var line=label(str(campaign.player.name)+"  •  "+str(campaign.player.char_class)+"  •  Level "+str(int(campaign.player.level)),16)
		line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		details.add_child(line)
		details.add_child(label("Adventure ended" if campaign.player.dead else "HP %d / %d"%[int(campaign.player.hp),int(campaign.player.max_hp)],15))
		var choices=VBoxContainer.new()
		choices.alignment=BoxContainer.ALIGNMENT_CENTER
		item_row.add_child(choices)
		var load_button=button("Continue",func():slug=id;send("load"))
		load_button.custom_minimum_size.x=144
		choices.add_child(load_button)
		choices.add_child(button("Delete",func():confirm("Delete this campaign permanently?",func():slug=id;send("delete_campaign"))))
	var footer=HBoxContainer.new()
	body.add_child(footer)
	footer.add_child(button("Main menu",menu))
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(spacer)
	status=label("Choose a campaign." if not data.campaigns.is_empty() else "No saved campaigns.",16)
	footer.add_child(status)

func forge_title(title: String,subtitle: String):
	var p=PanelContainer.new()
	p.add_theme_stylebox_override("panel",panel_style())
	body.add_child(p)
	var v=VBoxContainer.new();p.add_child(v)
	var h=label("1NFINITY D&D  •  "+title,27)
	h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(h)
	var sub=label(subtitle,16)
	sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(sub)

func adventure():
	super.adventure()
	var controls=action_rows[0]
	for child in controls.get_children():
		controls.remove_child(child);child.queue_free()
	var actions=[["Dodge","I dodge"],["Disengage","I disengage"],["Dash away","I dash away"],["Move away","I move away"],["End turn","I end my turn"]] if combat_view else [["Look around","I look around"],["Wait","I wait"],["Rest",""],["Attack",""],["Check",""],["Cast",""]]
	for pair in actions:
		var text=str(pair[0])
		var command=str(pair[1])
		var callback: Callable=func():submit(command)
		match text:
			"Rest":callback=rest_picker
			"Attack":callback=attack_picker
			"Check":callback=func():action.grab_focus();action.placeholder_text="Describe the ability check"
			"Cast":callback=func():cast_picker()
		var b=button(text,callback)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		controls.add_child(b)
	# Keep the bottom action input and roll button accessible on 1280x720.
	for child in body.get_child(0).get_children():
		if child is Label:
			child.clip_text=true
			child.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			child.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			child.add_theme_font_size_override("font_size",18 if child==clock else 22)
	if combat_view:
		arena.get_parent().custom_minimum_size.y=116
		for select in [target_choice,choice_kind,choice_action]:
			select.fit_to_longest_item=false
			select.clip_text=true
			select.custom_minimum_size.x=108
			select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if is_instance_valid(approach_button):approach_button.text="Approach";approach_button.custom_minimum_size.x=112
	journal.add_theme_font_size_override("normal_font_size",clampi(int(native.cfg.get("journal_size",18)),14,24))

func update_scene(data: Dictionary):
	super.update_scene(data)
	if combat_view:
		target_ids.append("player")
		target_choice.add_item("Self")
		if target_choice.selected<0:target_choice.select(0)
	var features=tab("Features")
	var p=data.player
	small_text(features,"Class: "+str(p.char_class)+"  •  Level "+str(int(p.level)))
	small_text(features,"Hit Dice: "+str(maxi(0,int(p.level)-int(p.get("hit_dice_spent",0))))+" / "+str(int(p.level)))
	if p.char_class=="Fighter":
		var wind=button("Second Wind",func():submit("I use Second Wind"))
		wind.disabled="Second Wind" in p.used_features or data.pending!=null or p.dead
		features.add_child(wind)
	if p.char_class=="Wizard" and not combat_view:
		var rest=button("Arcane Recovery",rest_picker)
		rest.disabled="Arcane Recovery" in p.used_features or p.dead or data.pending!=null
		features.add_child(rest)
	for e in data.get("effects",[]):
		if e is Dictionary:
			small_text(features,str(e.get("spell","Effect"))+" • "+str(maxi(0,int(e.get("expires",data.world_seconds))-int(data.world_seconds)))+"s remaining")
	if not combat_view:
		var cast=button("Cast a spell",func():cast_picker())
		cast.disabled=p.dead or data.pending!=null or (p.cantrips+p.prepared).is_empty()
		features.add_child(cast)
	var traits: Array=p.get("traits",[])
	for trait_name in traits:small_text(features,str(trait_name))

func combat_action():
	if choice_action.selected<0:return
	if str(scene_data.combat.get("awaiting_companion",""))!="":super.combat_action();return
	if choice_kind.selected==1:
		var selected=str(player_actions[choice_action.selected])
		var target=str(target_ids[target_choice.selected]) if target_choice.selected>=0 and target_choice.selected<target_ids.size() else ""
		cast_picker(selected,target)
		return
	super.combat_action()

func cast_picker(preselected: String="",preferred_target: String=""):
	if operation!="" or scene_data.player.dead or scene_data.get("pending")!=null:return
	var p=scene_data.player
	var names: Array=[]
	for sn in p.cantrips+p.prepared+p.spellbook:
		if sn not in names:names.append(sn)
	if names.is_empty():status.text="No spells known.";return
	var d=ConfirmationDialog.new()
	d.title="Cast a spell"
	var v=VBoxContainer.new();v.custom_minimum_size.x=470;d.add_child(v)
	var spell_pick=OptionButton.new()
	for sn in names:spell_pick.add_item(str(sn))
	spell_pick.select(names.find(preselected) if preselected in names else 0)
	v.add_child(label("Spell",17));v.add_child(spell_pick)
	var targets=OptionButton.new()
	var ids: Array=["player"]
	targets.add_item("Self")
	for id in scene_data.npcs:
		var n=scene_data.npcs[id]
		if n.location==scene_data.location and not n.dead:ids.append(id);targets.add_item(str(n.name))
	targets.select(ids.find(preferred_target) if preferred_target in ids else 0)
	v.add_child(label("Target / centre of spell area",17));v.add_child(targets)
	var levels=OptionButton.new();v.add_child(label("Spell slot",17));v.add_child(levels)
	var ritual=CheckBox.new();ritual.text="Cast as a ritual (+10 minutes)";v.add_child(ritual)
	var aim=LineEdit.new();aim.placeholder_text="Optional: describe affected area or creatures"
	v.add_child(aim)
	var info=label("",15);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;v.add_child(info)
	var refresh=func():
		var spell=native.spell_info(str(names[spell_pick.selected]))
		var base=int(spell.level)
		levels.clear()
		levels.add_item("Cantrip" if base==0 else "Base level "+str(base),base)
		if base>0:
			for slot in p.slots:
				if int(slot.level)>base and int(slot.used)<int(slot.total):levels.add_item("Level "+str(int(slot.level)),int(slot.level))
		levels.select(0)
		ritual.visible="ritual" in str(spell.casting_time).to_lower() and not combat_view
		ritual.button_pressed=false
		info.text=str(spell.range)+"  •  "+str(spell.duration)
	refresh.call()
	spell_pick.item_selected.connect(func(_i):refresh.call())
	add_child(d)
	d.confirmed.connect(func():
		var sn=str(names[spell_pick.selected])
		var id=str(ids[targets.selected])
		var target="myself" if id=="player" else str(scene_data.npcs[id].name)+" (ID "+id+")"
		var command="I cast "+sn+" targeting "+target
		if ritual.visible and ritual.button_pressed:command+=" as a ritual"
		elif levels.get_selected_id()>0:command+=" at level "+str(levels.get_selected_id())
		if aim.text.strip_edges()!="":command+=". Area: "+aim.text.strip_edges()
		d.queue_free();submit(command))
	d.canceled.connect(d.queue_free)
	d.popup_centered(Vector2i(520,360))

func rest_picker():
	if combat_view or scene_data.player.dead or scene_data.get("pending")!=null:return
	var p=scene_data.player
	var d=ConfirmationDialog.new();d.title="Rest"
	var v=VBoxContainer.new();v.custom_minimum_size.x=460;d.add_child(v)
	var kind=OptionButton.new()
	kind.add_item("Short rest • 1 hour",0);kind.add_item("Long rest • 8 hours",1)
	if p.char_class=="Wizard" and not "Arcane Recovery" in p.used_features:kind.add_item("Short rest with Arcane Recovery",2)
	v.add_child(kind)
	var hd=SpinBox.new();hd.min_value=0;hd.max_value=maxi(0,int(p.level)-int(p.get("hit_dice_spent",0)));hd.step=1
	v.add_child(label("Hit Dice to spend during short rest",16));v.add_child(hd)
	var slot=SpinBox.new();slot.min_value=1;slot.max_value=5;slot.step=1
	v.add_child(label("Arcane Recovery slot level (if selected)",16));v.add_child(slot)
	add_child(d)
	d.confirmed.connect(func():
		var command="I take a long rest" if kind.get_selected_id()==1 else "I take a short rest and recover level %d slots"%int(slot.value) if kind.get_selected_id()==2 else "I take a short rest and spend %d Hit Dice"%int(hd.value)
		d.queue_free();submit(command))
	d.canceled.connect(d.queue_free);d.popup_centered(Vector2i(500,280))

func roll_dialog():
	if roll_animation or operation!="" or not scene_data.get("pending") is Dictionary or scene_data.player.dead:return
	roll_animation=true
	operation="rolling animation"
	roll.disabled=true
	pending_button.disabled=true
	var art=pending_strip.get_child(0).get_child(0)
	art.pivot_offset=art.size/2.0
	var anim=create_tween()
	anim.tween_property(art,"rotation",TAU,0.26)
	await anim.finished
	if is_instance_valid(art):art.rotation=0
	operation=""
	roll_animation=false
	super.roll_dialog()

func settings_page(data: Dictionary):
	super.settings_page(data)
	var footer=HBoxContainer.new();body.add_child(footer)
	footer.add_child(button("Appearance",appearance_dialog))
	footer.add_child(button("Diagnostics",func():send("diagnostics")))
	footer.add_child(button("Import old save",legacy_file_picker))
	footer.add_child(button("DM prompts & content",func():send("dm_guidance")))

func guidance_dialog(data: Dictionary):
	clear()
	screen_name="dm_guidance"
	set_backdrop("ruins")
	forge_title("DM PROMPTS & CONTENT","Edit your table rules and campaign narration profiles")
	var editors: Dictionary={}
	var panel=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",panel_style())
	panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var tabs=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	panel.add_child(tabs)
	var table=guidance_tab(tabs,"Do / Don't")
	guidance_field(table,editors,data,"do","WHAT THE DM SHOULD DO",180)
	guidance_field(table,editors,data,"dont","WHAT THE DM SHOULD NOT DO",180)
	var content=guidance_tab(tabs,"Content profiles")
	var explanation=label("The campaign's selected Family, Standard or Mature profile determines which of these instructions the AI receives. These edit narration preferences, not provider safety settings.",16)
	explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)
	for profile in ["family","standard","mature"]:
		guidance_field(content,editors,data,profile,profile.capitalize(),92)
	var advanced=guidance_tab(tabs,"Advanced prompts")
	var description=label("Optional additional guidance for each AI layer. Existing saved guidance is preserved.",16)
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	advanced.add_child(description)
	for layer in ["Interpreter","Rules Lawyer","Storyteller"]:
		guidance_field(advanced,editors,data,layer,layer,92)
	var footer=HBoxContainer.new()
	footer.add_theme_constant_override("separation",10)
	body.add_child(footer)
	footer.add_child(button("Cancel",func():send("settings")))
	var spacer=Control.new()
	spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(button("Save changes",func():
		var values: Dictionary={}
		for key in editors:
			var value_text: String=editors[key].text
			if value_text.length()>12000:
				status.text="Field "+str(key)+" exceeds 12,000 characters."
				return
			values[key]=value_text
		send("save_guidance",values)))
	status=label("Local settings • Applied to subsequent AI requests • Preserved during updates",15)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)

func guidance_tab(tabs: TabContainer,title: String) -> VBoxContainer:
	var sc=ScrollContainer.new()
	sc.name=title.replace("/","and")
	sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	tabs.set_tab_title(tabs.get_tab_count()-1,title)
	var v=VBoxContainer.new()
	v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation",8)
	sc.add_child(v)
	return v

func guidance_field(parent: Container,editors: Dictionary,data: Dictionary,key: String,title: String,height: int):
	parent.add_child(label(title,18))
	var editor=TextEdit.new()
	editor.custom_minimum_size=Vector2(0,height)
	editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical=Control.SIZE_EXPAND_FILL
	editor.text=str(data.get(key,""))
	editor.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(editor)
	editors[key]=editor

func legacy_file_picker():
	var d=FileDialog.new()
	d.title="Import a legacy character or completed campaign (copy only)"
	d.access=FileDialog.ACCESS_FILESYSTEM
	d.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	d.filters=PackedStringArray(["*.json ; JSON saves"])
	add_child(d)
	d.file_selected.connect(func(path):
		d.queue_free()
		send("import_legacy",{"path":path}))
	d.canceled.connect(d.queue_free)
	d.popup_centered_ratio(0.72)

func appearance_dialog():
	var d=ConfirmationDialog.new();d.title="Appearance"
	var v=VBoxContainer.new();v.custom_minimum_size.x=400;d.add_child(v)
	var names=["varied","castle","forest","lake","ruins"]
	var bg=OptionButton.new()
	for name in names:bg.add_item(str(name).capitalize())
	bg.select(maxi(0,names.find(str(native.cfg.get("background","varied")))))
	v.add_child(label("Scenic background",17));v.add_child(bg)
	var size=SpinBox.new();size.min_value=14;size.max_value=24;size.step=1;size.value=int(native.cfg.get("journal_size",18))
	v.add_child(label("Journal text size",17));v.add_child(size)
	add_child(d)
	d.confirmed.connect(func():
		var args={"background":names[bg.selected],"journal_size":int(size.value)}
		d.queue_free()
		send("appearance",args))
	d.canceled.connect(d.queue_free);d.popup_centered(Vector2i(460,220))

func updates_page(data: Dictionary):
	clear()
	screen_name="updates"
	set_backdrop("ruins")
	forge_title("UPDATE CENTRE","Native release channel • Checksum-verified updates")
	var row=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(row)
	var left=panel_column(row,360)
	heading(left,"CONNECTED EDITION")
	small_text(left,"Installed version: "+str(data.installed))
	small_text(left,"Latest compatible: "+str(data.latest))
	update_choice=OptionButton.new();update_choice.fit_to_longest_item=false
	left.add_child(update_choice)
	var releases: Array=data.versions
	for entry in releases:update_choice.add_item("v"+str(entry.version))
	var right=panel_column(row,0);heading(right,"RELEASE NOTES")
	var sc=ScrollContainer.new();sc.size_flags_vertical=Control.SIZE_EXPAND_FILL;sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;right.add_child(sc)
	notes=label("Already up to date." if releases.is_empty() else "",18)
	notes.size_flags_horizontal=Control.SIZE_EXPAND_FILL;notes.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;sc.add_child(notes)
	if not releases.is_empty():
		update_choice.select(releases.size()-1)
		notes.text=str(releases[-1].notes)
		update_choice.item_selected.connect(func(i):notes.text=str(releases[i].notes))
	var install=button("Install selected version",func():
		if update_choice.selected>=0:
			var version=str(releases[update_choice.selected].version)
			confirm("Install v"+version+" and restart? Local saves and settings remain separate.",func():send("install_update",{"version":version})))
	install.disabled=releases.is_empty()
	left.add_child(install)
	left.add_child(button("Refresh versions",func():send("updates")))
	var footer=HBoxContainer.new();body.add_child(footer)
	footer.add_child(button("Main menu",menu))
	status=label("Select a compatible release. Updates are staged before installation.",15);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(status)
