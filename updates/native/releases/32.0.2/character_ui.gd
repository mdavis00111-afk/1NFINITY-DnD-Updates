extends "res://main.gd"
## Four-stage character forge. Selection data is independent of page visibility.
const ABILITIES = ["STR","DEX","CON","INT","WIS","CHA"]
const STAGES = ["Identity","Abilities & skills","Equipment","Spellbook"]
var forge_pages: Array = []
var forge_step = 0
var forge_progress: Label
var forge_back: Button
var forge_next: Button
var forge_save: Button
var forge_portrait: TextureRect
var forge_summary: Label
var forge_kit: Label
var forge_style: VBoxContainer
var forge_spell_note: Label
var forge_scores: Label
var forge_groups: Dictionary = {}
var forge_selected: Dictionary = {}
var forge_limits: Dictionary = {}

func _ready():
	super._ready()
	for kind in ["LineEdit","TextEdit","OptionButton","PopupMenu"]:
		for state_name in ["normal","focus","hover","pressed","panel","read_only","disabled"]:
			var s = StyleBoxFlat.new()
			s.bg_color = Color("102326")
			s.border_color = Color("ba9358") if state_name=="focus" else Color("62543b")
			s.set_border_width_all(1)
			s.set_corner_radius_all(4)
			for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: s.set_content_margin(side,8)
			theme.set_stylebox(state_name,kind,s)
		theme.set_color("font_color",kind,Color("f3e6cc"))
	theme.set_color("font_color","CheckBox",Color("f3e6cc"))
	theme.set_color("font_disabled_color","CheckBox",Color("8b958f"))

func forge_panel(parent: Container, width: int=0) -> VBoxContainer:
	var p = PanelContainer.new()
	var s = panel_style()
	s.bg_color = Color("102326")
	s.border_color = Color("b08a50")
	p.add_theme_stylebox_override("panel",s)
	p.custom_minimum_size.x=width
	if width==0: p.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	p.size_flags_vertical=Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var c=VBoxContainer.new()
	c.add_theme_constant_override("separation",10)
	p.add_child(c)
	return c

func forge_heading(parent: Container, title: String, subtitle: String):
	var h=label(title,30)
	h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(h)
	var sub=label(subtitle,16)
	sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(sub)

func forge_scroll(parent: Container) -> VBoxContainer:
	var sc=ScrollContainer.new()
	sc.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v=VBoxContainer.new()
	v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation",10)
	sc.add_child(v)
	return v

func forge_group(parent: Container,key: String):
	var p=PanelContainer.new()
	p.add_theme_stylebox_override("panel",panel_style())
	p.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var c=VBoxContainer.new()
	c.add_theme_constant_override("separation",5)
	p.add_child(c)
	forge_groups[key]=c
	forge_selected[key]=[]
	forge_limits[key]=0

func creator():
	clear()
	screen_name="forge"
	set_backdrop("forest")
	form.clear()
	forge_pages.clear()
	forge_groups.clear()
	forge_selected.clear()
	forge_limits.clear()
	forge_step=0
	forge_heading(body,"✦  Forge an adventurer  ✦","1NFINITY D&D  •  2014 Basic Rules")
	forge_progress=label("",18)
	forge_progress.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(forge_progress)
	var row=HBoxContainer.new()
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",16)
	body.add_child(row)
	var side=forge_panel(row,230)
	heading(side,"YOUR ADVENTURER")
	forge_portrait=hero_portrait({"race":"Human","char_class":"Wizard","gender":"Female"},Vector2(188,228))
	side.add_child(forge_portrait)
	forge_summary=label("",16)
	forge_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	side.add_child(forge_summary)
	var center=forge_panel(row)
	for title in STAGES:
		var page=VBoxContainer.new()
		page.size_flags_vertical=Control.SIZE_EXPAND_FILL
		center.add_child(page)
		heading(page,title.to_upper())
		forge_pages.append(page)
	var identity=forge_scroll(forge_pages[0])
	field(identity,"name","Character name")
	var grid=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",18)
	identity.add_child(grid)
	for pair in [["race","Race",roster_data.races],["class","Class",roster_data.classes],["background","Background",roster_data.backgrounds],["gender","Gender",["Female","Male","Non-binary","Other","Prefer not to say"]],["level","Level",range(1,21)]]:
		var cell=VBoxContainer.new()
		cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		choice(cell,pair[0],pair[1],pair[2])
	field(identity,"description","Description")
	var abilities=forge_scroll(forge_pages[1])
	var tools=HBoxContainer.new()
	abilities.add_child(tools)
	tools.add_child(button("Standard array",func(): forge_set_scores([15,14,13,12,10,8])))
	tools.add_child(button("Point buy",func(): forge_set_scores([8,8,8,8,8,8])))
	var scores_grid=GridContainer.new()
	scores_grid.columns=3
	scores_grid.add_theme_constant_override("h_separation",14)
	abilities.add_child(scores_grid)
	for a in ABILITIES:
		var c=VBoxContainer.new()
		c.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		scores_grid.add_child(c)
		field(c,a,a,str({"STR":10,"DEX":14,"CON":13,"INT":15,"WIS":12,"CHA":8}[a]))
		form[a].max_length=2
	forge_scores=label("",15)
	forge_scores.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	abilities.add_child(forge_scores)
	forge_group(abilities,"skills")
	forge_group(abilities,"expertise")
	forge_style=VBoxContainer.new()
	abilities.add_child(forge_style)
	choice(forge_style,"style","Fighting style",[""]+roster_data.styles)
	var gear=forge_scroll(forge_pages[2])
	choice(gear,"kit","Starting equipment package",["A","B"])
	forge_kit=label("",17)
	forge_kit.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	gear.add_child(forge_kit)
	var magic=forge_scroll(forge_pages[3])
	forge_spell_note=label("",16)
	forge_spell_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	magic.add_child(forge_spell_note)
	forge_group(magic,"cantrips")
	forge_group(magic,"spellbook")
	forge_group(magic,"prepared")
	var footer=HBoxContainer.new()
	footer.add_theme_constant_override("separation",12)
	body.add_child(footer)
	footer.add_child(button("Cancel",func(): screen_name="roster"; roster_page()))
	forge_back=button("Back",func(): forge_show(forge_step-1))
	footer.add_child(forge_back)
	var spacer=Control.new()
	spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	forge_next=button("Next",func(): forge_show(forge_step+1))
	footer.add_child(forge_next)
	forge_save=button("Save character",forge_commit)
	footer.add_child(forge_save)
	status=label("",16)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	for k in ["race","class","background","gender","level","kit","style"]:
		form[k].item_selected.connect(func(_i): forge_refresh())
	form["name"].text_changed.connect(func(_s): forge_validate())
	for a in ABILITIES:
		form[a].text_changed.connect(func(_s): forge_refresh())
	forge_refresh()
	forge_show(0)

func forge_show(index: int):
	forge_step=clampi(index,0,3)
	for i in range(forge_pages.size()):
		forge_pages[i].visible=i==forge_step
	var titles: Array=[]
	for i in range(STAGES.size()):
		titles.append(("◆ " if i==forge_step else "◇ ")+str(i+1)+". "+STAGES[i])
	forge_progress.text="     ".join(titles)
	forge_back.disabled=forge_step==0
	forge_next.visible=forge_step<3
	forge_save.visible=forge_step==3
	forge_validate()

func forge_set_scores(values: Array):
	for i in range(ABILITIES.size()):
		form[ABILITIES[i]].text=str(values[i])
	forge_refresh()

func forge_spec() -> Dictionary:
	var scores: Dictionary={}
	for a in ABILITIES: scores[a]=int(val(a))
	return {"name":val("name"),"race":val("race"),"char_class":val("class"),"background":val("background"),"gender":val("gender"),"description":val("description"),"level":int(val("level")),"base_scores":scores,"kit":val("kit"),"skill_profs":forge_selected.skills.duplicate(),"fighting_style":val("style"),"expertise":forge_selected.expertise.duplicate(),"cantrips":forge_selected.cantrips.duplicate(),"spellbook":forge_selected.spellbook.duplicate(),"prepared":forge_selected.prepared.duplicate()}

func forge_render(key: String,title: String,options: Array,limit: int,optional: bool=false):
	var col=forge_groups[key]
	for child in col.get_children():
		col.remove_child(child)
		child.queue_free()
	forge_limits[key]=limit
	var kept: Array=[]
	for name in forge_selected[key]:
		if name in options and kept.size()<limit: kept.append(name)
	forge_selected[key]=kept
	col.get_parent().visible=limit>0
	if limit<=0: return
	col.add_child(label("%s   •   %d / %d %s"%[title,kept.size(),limit,"maximum" if optional else "required"],19))
	var grid=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",16)
	col.add_child(grid)
	for name in options:
		var tick=CheckBox.new()
		tick.text=str(name)
		tick.button_pressed=name in kept
		tick.disabled=kept.size()>=limit and not tick.button_pressed
		tick.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if key in ["cantrips","spellbook","prepared"]:
			var sp=native.spell_info(str(name))
			tick.tooltip_text=str(sp.get("description",sp.get("text","Level "+str(int(sp.get("level",0))))))
		grid.add_child(tick)
		tick.toggled.connect(forge_toggle.bind(key,str(name)))

func forge_toggle(on: bool,key: String,name: String):
	var selected: Array=forge_selected[key]
	if on and not name in selected and selected.size()<int(forge_limits[key]):
		selected.append(name)
	elif not on:
		selected.erase(name)
	forge_refresh.call_deferred()

func forge_refresh():
	if screen_name!="forge" or not is_instance_valid(forge_save) or not form.has("class"): return
	var cls=val("class")
	var ci=native.book.classes[cls]
	var ri=native.book.races[val("race")]
	var bi=native.book.backgrounds[val("background")]
	var level=int(val("level"))
	var granted: Array=ri.skills.duplicate()+bi.skills
	var eligible: Array=[]
	for name in ci.skills:
		if not name in granted: eligible.append(name)
	forge_render("skills","Choose class skills",eligible,int(ci.skill_count))
	var trained: Array=[]
	for name in granted+forge_selected.skills:
		if not name in trained: trained.append(name)
	forge_render("expertise","Choose expertise",trained,2 if cls=="Rogue" else 0)
	forge_style.visible=cls=="Fighter"
	var cantrips: Array=[]
	var leveled: Array=[]
	if ci.casting!=null:
		for sp in roster_data.spells:
			if not cls in sp.get("classes",[]): continue
			if int(sp.level)==0: cantrips.append(sp.name)
			elif int(sp.level)<=mini(9,ceili(level/2.0)): leveled.append(sp.name)
	forge_render("cantrips","Cantrips",cantrips,3+int(level>=4)+int(level>=10) if ci.casting!=null else 0)
	forge_render("spellbook","Wizard spellbook",leveled,6+2*(level-1) if cls=="Wizard" else 0)
	var prepared_limit=0
	if ci.casting!=null:
		prepared_limit=maxi(1,native.mod(int(val(str(ci.casting)))+int(ri.bonus.get(ci.casting,0)))+level)
	forge_render("prepared","Prepared spells",forge_selected.spellbook.duplicate() if cls=="Wizard" else leveled,prepared_limit,true)
	forge_spell_note.text="This class does not use spells. Finish and save your adventurer." if ci.casting==null else "Select the required cantrips and spellbook entries. Prepare spells from the available list."
	var kit=native.book.kits[cls][val("kit")]
	var gear: Array=[]
	for slot in kit[0]:
		if kit[0][slot]!=null: gear.append(str(slot).replace("_"," ").capitalize()+": "+str(kit[0][slot]))
	for item in kit[1]:
		gear.append(str(item)+" × "+str(int(kit[1][item])))
	forge_kit.text="PACKAGE "+val("kit")+"\n\n"+"\n".join(gear)+"\n\nBackground equipment and "+str(int(bi.gold))+" gp included."
	var points=0
	var valid_points=true
	var finals: Array=[]
	for a in ABILITIES:
		var base=int(val(a))
		if base<8 or base>15: valid_points=false
		else: points+=[0,1,2,3,4,5,7,9][base-8]
		finals.append(a+" "+str(base+int(ri.bonus.get(a,0))))
	forge_scores.text="Point buy: "+(str(points)+" / 27" if valid_points else "use scores 8–15")+"     •     Final scores: "+", ".join(finals)+"\nGranted skills: "+(", ".join(granted) if not granted.is_empty() else "None")
	var image_path="res://art/portraits/cinematic_"+val("race").to_lower().replace(" ","_")+"_"+cls.to_lower()+"_"+val("gender").to_lower()+".webp"
	if not ResourceLoader.exists(image_path):
		image_path="res://art/portraits/cinematic_"+val("race").to_lower().replace(" ","_")+"_"+cls.to_lower()+"_female.webp"
	forge_portrait.texture=load(image_path) if ResourceLoader.exists(image_path) else null
	forge_validate()

func forge_validate():
	if screen_name!="forge" or not is_instance_valid(forge_save): return
	var result: Dictionary=native.build_player(forge_spec())
	forge_save.disabled=result.has("error")
	var ri=native.book.races[val("race")]
	var ci=native.book.classes[val("class")]
	var level=int(val("level"))
	var con=native.mod(int(val("CON"))+int(ri.bonus.get("CON",0)))
	var hd=int(ci.hit_die)
	var hp=maxi(1,hd+con)+(level-1)*maxi(1,floori(hd/2.0)+1+con)+int(ri.get("hp_per_level",0))*level
	forge_summary.text=(val("name") if not val("name").strip_edges().is_empty() else "Unnamed adventurer")+"\n"+val("race")+" • "+val("class")+"\nLevel "+str(level)+"\n\nHP "+str(hp)+"  •  Speed "+str(int(ri.speed))+" ft\nSkills "+str(forge_selected.skills.size())+" / "+str(forge_limits.skills)+"\nCantrips "+str(forge_selected.cantrips.size())+" / "+str(forge_limits.cantrips)+"\nPrepared "+str(forge_selected.prepared.size())+" / "+str(forge_limits.prepared)
	status.text=str(result.error) if result.has("error") else "Ready to save • HP %d • AC %d"%[int(result.hp),int(result.ac)]

func forge_commit():
	var spec=forge_spec()
	var result: Dictionary=native.build_player(spec)
	if result.has("error"):
		status.text=str(result.error)
		return
	screen_name="roster"
	send("create_character",{"spec":spec})

func settings_page(data: Dictionary):
	clear()
	screen_name="settings"
	form.clear()
	set_backdrop("castle")
	forge_heading(body,"✦  Settings  ✦","Configure your Dungeon Master and display")
	var center=CenterContainer.new()
	center.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var panel=PanelContainer.new()
	panel.custom_minimum_size.x=540
	panel.add_theme_stylebox_override("panel",panel_style())
	center.add_child(panel)
	var v=VBoxContainer.new()
	v.add_theme_constant_override("separation",12)
	panel.add_child(v)
	heading(v,"DUNGEON MASTER")
	field(v,"key","Gemini API key")
	form["key"].secret=true
	form["key"].placeholder_text="Enter a new key to replace the saved key"
	field(v,"model","Gemini model",str(data.get("model","gemini-3.5-flash-lite")))
	v.add_child(button("Save settings",func(): send("key",{"key":val("key"),"model":val("model")})))
	heading(v,"DISPLAY")
	v.add_child(button("Toggle fullscreen",func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)))
	v.add_child(button("Back to main menu",menu))
	status=label("API key configured" if data.get("connected",false) else "API key required for gameplay",16)
	body.add_child(status)
