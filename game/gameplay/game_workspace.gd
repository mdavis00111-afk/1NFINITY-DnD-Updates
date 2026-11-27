extends VBoxContainer
## Presentation only: reads committed campaign data. Future controller may connect
## action_requested; composer stays disabled until an explicit controller binding.
signal action_requested(campaign_id: String, actor_id: String, text: String)

const CAT = preload("res://rules/catalog.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
const PORTRAIT = preload("res://players/portrait_art.gd")
const SHEET = preload("res://players/full_character_sheet.gd")
const DICE = preload("res://gameplay/manual_dice.gd")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const CORNER = preload("res://themes/parts/corner.png")
const ATLAS = preload("res://themes/parts/icons.png")
const FONT = preload("res://themes/fonts/EBGaramond.ttf")
const DOLL = preload("res://gameplay/paper_doll.svg")
const COMPASS = preload("res://gameplay/reference_compass.png")
const EMPTY_PARTY = preload("res://gameplay/reference_party.png")
const SHORTSWORD = preload("res://gameplay/reference_shortsword.png")
const BACKPACK = preload("res://gameplay/reference_backpack.png")
const PORTRAIT_FRAME = preload("res://themes/parts/portrait_empty.png")
const GOLD = Color("#ffd989")
const IVORY = Color("#fff0cf")
const ABILITIES = ["str","dex","con","int","wis","cha"]
const TABS = ["Inventory","Spells","Skills","Features","Notes"]
var cat = CAT.new()
var view: Dictionary = {}
var actor: Dictionary = {}
var campaign: Dictionary = {}
var items: Array = []
var leave_action: Callable
var settings_action: Callable
var retry_action: Callable
var pending = false
var data_error = ""
var right_content: VBoxContainer
var right_tabs: Dictionary = {}
var current_tab = "Inventory"
var selected_item = ""
var equipped_only = false
var inventory_detail: RichTextLabel
var inventory_cells: Dictionary = {}
var opening_button: Button
var status: Label
var composer: LineEdit
var send_button: Button
var dice_type: OptionButton
var dice_count: SpinBox
var dice_result: Label
var last_roll: Dictionary = {}
var log_scroll: ScrollContainer
var log_list: VBoxContainer
var left_panel: PanelContainer
var center_panel: PanelContainer
var right_panel: PanelContainer
var nav_bar: HBoxContainer
var icon_rects: Dictionary = {}

func configure(snapshot: Dictionary, metadata: Dictionary, on_leave: Callable, on_settings: Callable, on_retry: Callable, is_pending: bool, error: String = "") -> void:
	view = snapshot
	campaign = metadata
	actor = view.get("actor",{})
	items = view.get("inventory",[])
	leave_action = on_leave
	settings_action = on_settings
	retry_action = on_retry
	pending = is_pending
	data_error = error

func _ready() -> void:
	var local_theme = load("res://themes/master_theme.tres").duplicate() as Theme
	local_theme.default_font = FONT
	local_theme.default_font_size = 16
	theme = local_theme
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://themes/parts/icons.json"))
	if parsed is Dictionary:
		icon_rects = parsed
	cat.initialize()
	add_theme_constant_override("separation",5)
	build_header()
	var body = hbox(self,5)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left = frame(body,27.0,true)
	var center = frame(body,43.0,true)
	var right = frame(body,29.0,true)
	left_panel = left.get_parent() as PanelContainer
	center_panel = center.get_parent() as PanelContainer
	right_panel = right.get_parent() as PanelContainer
	left_panel.custom_minimum_size.x = 310
	center_panel.custom_minimum_size.x = 430
	right_panel.custom_minimum_size.x = 340
	build_left(left)
	build_center(center)
	build_right(right)

func box_style(lit: bool = false, margin: int = 6, opacity: float = 0.94) -> StyleBoxTexture:
	var style = StyleBoxTexture.new()
	style.texture = ACTIVE if lit else FRAME
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		style.set_texture_margin(side,22)
		style.set_content_margin(side,margin)
	style.modulate_color = Color(1,1,1,opacity)
	return style

func hbox(parent: Node, gap: int = 5) -> HBoxContainer:
	var node = HBoxContainer.new()
	node.add_theme_constant_override("separation",gap)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func vbox(parent: Node, gap: int = 4) -> VBoxContainer:
	var node = VBoxContainer.new()
	node.add_theme_constant_override("separation",gap)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func frame(parent: Node, ratio: float = 1.0, ornate: bool = false, lit: bool = false, padding: int = 6) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",box_style(lit,padding,0.80 if ornate else 0.87))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	if ornate:
		for i in range(4):
			var corner = TextureRect.new()
			corner.texture = CORNER
			corner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			corner.stretch_mode = TextureRect.STRETCH_SCALE
			corner.flip_h = (i & 1)==1
			corner.flip_v = i>=2
			corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var overlay = Control.new()
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(overlay)
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.add_child(corner)
			corner.set_anchors_and_offsets_preset([Control.PRESET_TOP_LEFT,Control.PRESET_TOP_RIGHT,Control.PRESET_BOTTOM_LEFT,Control.PRESET_BOTTOM_RIGHT][i])
			corner.offset_left = -24 if corner.flip_h else 0
			corner.offset_right = 0 if corner.flip_h else 24
			corner.offset_top = -24 if corner.flip_v else 0
			corner.offset_bottom = 0 if corner.flip_v else 24
			overlay.z_index = 2
	return vbox(panel)

func label(parent: Node, value: String, px: int = 16, color: Color = IVORY, centered: bool = false) -> Label:
	var out = Label.new()
	out.text = value
	out.add_theme_font_size_override("font_size",px)
	out.add_theme_color_override("font_color",color)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if centered:
		out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(out)
	return out

func one_line(parent: Node, value: String, px: int = 16, color: Color = IVORY, centered: bool = false) -> Label:
	var out = label(parent,value,px,color,centered)
	out.autowrap_mode = TextServer.AUTOWRAP_OFF
	out.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	out.tooltip_text = value
	return out

func glyph(key: String) -> Texture2D:
	if key=="shortsword": return SHORTSWORD
	if key=="backpack": return BACKPACK
	if key=="compass": return COMPASS
	if not icon_rects.has(key):
		return null
	var rect = icon_rects[key]
	var atlas = AtlasTexture.new()
	atlas.atlas = ATLAS
	atlas.region = Rect2(rect[0],rect[1],rect[2],rect[3])
	return atlas

func button(parent: Node, caption: String, callback: Callable, px: int = 16, image_id: String = "") -> Button:
	var b = Button.new()
	b.text = caption
	b.custom_minimum_size.y = 30
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = caption
	b.add_theme_font_size_override("font_size",px)
	b.add_theme_color_override("font_color",IVORY)
	b.add_theme_color_override("font_hover_color",GOLD)
	for state in ["normal","disabled","hover","pressed","focus"]:
		b.add_theme_stylebox_override(state,box_style(state in ["hover","pressed","focus"],4))
	if not image_id.is_empty():
		b.icon = glyph(image_id)
		b.add_theme_constant_override("icon_max_width",18)
	if callback.is_valid():
		b.pressed.connect(callback)
	parent.add_child(b)
	return b

func scroll(parent: Node, minimum: int = 48) -> ScrollContainer:
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = minimum
	parent.add_child(sc)
	return sc

func picture(parent: Node, texture: Texture2D, dimensions: Vector2, covered: bool = false) -> TextureRect:
	var out = TextureRect.new()
	out.texture = texture
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if covered else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	out.custom_minimum_size = dimensions
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(out)
	return out

func number(value: Variant, signed_value: bool = false) -> String:
	if value == null:
		return "—"
	if value is int or value is float:
		var n = str(int(value)) if float(value)==floor(float(value)) else str(value)
		return "+"+n if signed_value and float(value)>=0 else n
	return str(value)

func title_for(table: String, id: Variant) -> String:
	var key = str(id) if id != null else ""
	return "—" if key.is_empty() else cat.title(table,key)

func actor_portrait() -> Texture2D:
	return PORTRAIT.texture_for(str(actor.get("portrait",actor.get("draft",{}).get("portrait",""))))

func build_header() -> void:
	var header = frame(self,1.0,false,false,5)
	var row = hbox(header,8)
	var mark = picture(row,COMPASS,Vector2(42,42))
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var brand = vbox(row,0)
	brand.custom_minimum_size.x = 225
	brand.size_flags_horizontal = Control.SIZE_FILL
	one_line(brand,"1NFINITY D&D",28,GOLD)
	one_line(brand,"AI DUNGEON MASTER (5e)",15,GOLD)
	nav_bar = hbox(row,4)
	for caption in ["Game","Character","Inventory","Spells","Skills","Quest Log","Map","Campaign","Settings"]:
		var name_value = caption
		var b = button(nav_bar,caption,func(): navigate(name_value),16)
		b.custom_minimum_size.y = 35
		if caption=="Game":
			b.add_theme_stylebox_override("normal",box_style(true,4))

func navigate(destination: String) -> void:
	match destination:
		"Game": show_tab("Inventory")
		"Character": show_character()
		"Inventory","Spells","Skills": show_tab(destination)
		"Quest Log": show_quests()
		"Map": show_map()
		"Campaign": leave_action.call()
		"Settings": settings_action.call()

func stat(parent: Node, caption: String, value: String, icon_id: String = "", health: bool = false) -> void:
	var tile = frame(parent,1.0,false,false,3)
	if health:
		var max_hp = actor.get("combat",{}).get("hp_max")
		var current_hp = actor.get("combat",{}).get("hp_current")
		var bar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 9
		bar.max_value = maxf(1.0,float(max_hp)) if max_hp!=null else 1.0
		bar.value = float(current_hp) if current_hp!=null else 0.0
		var fill = StyleBoxFlat.new()
		fill.bg_color = Color("#aa2429")
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill",fill)
		tile.add_child(bar)
	var row = hbox(tile,4)
	if not icon_id.is_empty():
		picture(row,glyph(icon_id),Vector2(17,17))
	one_line(row,caption,15,GOLD)
	var val = one_line(row,value,16,IVORY,true)
	val.size_flags_stretch_ratio = 0.8

func build_left(parent: VBoxContainer) -> void:
	var top = hbox(parent,6)
	var portrait_frame = picture(top,PORTRAIT_FRAME,Vector2(117,149))
	portrait_frame.size_flags_horizontal = Control.SIZE_FILL
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_frame.stretch_mode = TextureRect.STRETCH_SCALE
	var image = picture(portrait_frame,actor_portrait(),Vector2.ZERO,true)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_left = 7
	image.offset_right = -7
	image.offset_top = 9
	image.offset_bottom = -9
	var mask = Shader.new()
	mask.code = "shader_type canvas_item; void fragment(){ vec2 p=UV*2.0-1.0; COLOR.a*=1.0-smoothstep(0.94,1.0,length(p)); }"
	var material_mask = ShaderMaterial.new()
	material_mask.shader = mask
	image.material = material_mask
	var info = vbox(top,2)
	info.size_flags_stretch_ratio = 1.7
	one_line(info,str(actor.get("name","Character unavailable")),24,GOLD,true)
	label(info,"Level "+number(actor.get("level"))+"  "+title_for("classes",actor.get("class_id"))+" ("+title_for("races",actor.get("race_id"))+")",14,GOLD,true)
	var combat = actor.get("combat",{})
	stat(info,"HP",number(combat.get("hp_current"))+" / "+number(combat.get("hp_max")),"health",true)
	stat(info,"AC",number(combat.get("armor_class")),"shield")
	stat(info,"Speed",number(combat.get("speed_feet"))+" ft.","speed")
	stat(info,"Initiative",number(combat.get("initiative"),true),"initiative")
	var abilities = frame(parent,1.0,false,false,3)
	var stats = hbox(abilities,1)
	for key in ABILITIES:
		var cell = frame(stats,1.0,false,false,2)
		one_line(cell,key.to_upper(),14,GOLD,true)
		one_line(cell,number(actor.get("ability_scores",{}).get(key)),20,IVORY,true)
		one_line(cell,"("+number(actor.get("ability_modifiers",{}).get(key),true)+")",14,IVORY,true)
	var bonuses = hbox(parent,3)
	stat(bonuses,"Proficiency",number(actor.get("proficiency_bonus"),true))
	stat(bonuses,"Passive Perception",number(combat.get("passive_perception")))
	var equipment = frame(parent,1.0,true,false,5)
	equipment.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var slots = hbox(equipment,3)
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left = vbox(slots,3)
	left.custom_minimum_size.x = 65
	left.size_flags_stretch_ratio = 0.65
	var middle = vbox(slots,2)
	middle.size_flags_stretch_ratio = 1.7
	var right = vbox(slots,3)
	right.custom_minimum_size.x = 65
	right.size_flags_stretch_ratio = 0.65
	var gear = actor.get("equipment",{})
	for slot in ["Head","Cloak","Body","Hands","Feet"]:
		slot_card(left,slot,str(gear.get("armor_id","")) if slot=="Body" else "")
	var doll = picture(middle,DOLL,Vector2(80,124))
	doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var weapons: Array = gear.get("weapon_ids",[])
	var weapon_caption: PackedStringArray = []
	for id in weapons:
		weapon_caption.append(title_for("equipment",id))
	var weapon = button(middle,"Weapon: "+(", ".join(weapon_caption) if not weapon_caption.is_empty() else "Empty"),func(): show_equipped_weapons(),14,item_icon(str(weapons[0])) if weapons.size()==1 else "")
	weapon.disabled = weapons.is_empty()
	weapon.tooltip_text = ", ".join(weapon_caption) if not weapons.is_empty() else "No equipped weapon"
	for slot in ["Neck","Ring","Accessory","Belt","Shield"]:
		slot_card(right,slot,str(gear.get("shield_id","")) if slot=="Shield" else "")
	var money = frame(parent,1.0,false,false,4)
	var coins: PackedStringArray = []
	for denomination in ["pp","gp","ep","sp","cp"]:
		if actor.get("coins",{}).has(denomination):
			coins.append(number(actor["coins"][denomination])+" "+denomination)
	one_line(money,"Coins: "+("  ·  ".join(coins) if not coins.is_empty() else "Not recorded"),15,GOLD)
	one_line(money,"Weight: "+number(actor.get("carried_weight_lb"))+" / "+number(actor.get("carrying_capacity_lb"))+" lb",16)

func slot_card(parent: Node, slot: String, id: String) -> void:
	var caption = slot+"\n"+(title_for("equipment",id) if not id.is_empty() else "Empty")
	var b = button(parent,caption,func(): inspect("equipment",id),13,"armor" if slot=="Body" and not id.is_empty() else ("shield" if slot=="Shield" and not id.is_empty() else ""))
	b.custom_minimum_size.y = 39
	b.disabled = id.is_empty()
	b.tooltip_text = caption

func show_equipped_weapons() -> void:
	var lines: PackedStringArray = []
	for id in actor.get("equipment",{}).get("weapon_ids",[]):
		lines.append(cat.describe("equipment",str(id)))
	popup_text("Equipped weapons","\n\n".join(lines))

func build_center(parent: VBoxContainer) -> void:
	var scene = frame(parent,1.0,true,false,3)
	var location = view.get("location",{})
	var scenery = picture(scene,STARTS.texture_for(str(campaign.get("thumbnail_id",campaign.get("start_id","road")))),Vector2(0,143),true)
	scenery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenery.clip_contents = true
	scenery.tooltip_text = "Provisional bundled scene illustration"
	var banner = frame(scenery,1.0,false,true,4)
	var banner_panel = banner.get_parent() as PanelContainer
	banner_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner_panel.offset_left = -123
	banner_panel.offset_right = 123
	banner_panel.offset_top = 0
	banner_panel.offset_bottom = 34
	var headline = hbox(banner,4)
	picture(headline,COMPASS,Vector2(25,25))
	one_line(headline,"AI Dungeon Master",21,GOLD,true)
	var location_band = frame(scenery,1.0,false,false,3)
	var band_panel = location_band.get_parent() as PanelContainer
	band_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band_panel.offset_top = -25
	one_line(location_band,str(campaign.get("title","Campaign"))+"  ·  "+str(location.get("name",campaign.get("location_name",campaign.get("start_name","Location unavailable")))),15,GOLD,true)
	var log = frame(parent,1.0,true,false,5)
	log.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll = scroll(log,120)
	log_list = vbox(log_scroll,6)
	for event in view.get("events",[]):
		var role = "System" if event.get("kind")=="campaign_created" else "DM"
		var entry = hbox(log_list,6)
		picture(entry,glyph("diamond" if role=="System" else "initiative"),Vector2(30,30))
		var words = vbox(entry,2)
		one_line(words,role+"  ·  Turn "+number(event.get("turn")),17,GOLD)
		label(words,str(event.get("text","")),17,IVORY)
		var divider = HSeparator.new()
		log_list.add_child(divider)
	if view.get("events",[]).is_empty():
		label(log_list,"No committed adventure events available.",16)
	if not data_error.is_empty():
		label(log_list,data_error,16,GOLD)
	log_scroll.set_deferred("scroll_vertical",2147483647)
	var actions = hbox(parent,4)
	if not campaign.get("opening_committed",false) and int(campaign.get("turn",0))==0:
		opening_button = button(actions,"Generate Opening",retry_action,15,"wand")
		opening_button.disabled = pending or not data_error.is_empty()
	button(actions,"Save & Exit",leave_action,15)
	status = label(parent,"Generating opening… Saved campaign is safe." if pending else "Turn controller pending — action submission unavailable.",14,GOLD)
	status.max_lines_visible = 2
	status.custom_minimum_size.y = 20
	var compose = hbox(parent,4)
	composer = LineEdit.new()
	composer.placeholder_text = "Type your action here… (turn controller pending)"
	composer.editable = false
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer.add_theme_stylebox_override("normal",box_style(false,5))
	composer.add_theme_stylebox_override("read_only",box_style(false,5))
	composer.custom_minimum_size.y = 34
	compose.add_child(composer)
	send_button = button(compose,"Send",func(): pass,16)
	send_button.size_flags_horizontal = Control.SIZE_FILL
	send_button.disabled = true
	send_button.tooltip_text = "Action resolution is not implemented. No action is submitted or saved."
	var dice = frame(parent,1.0,false,false,4)
	var controls = hbox(dice,4)
	var roll_label = one_line(controls,"Roll Dice",16,GOLD)
	roll_label.size_flags_horizontal = Control.SIZE_FILL
	dice_type = OptionButton.new()
	for sides in DICE.SIDES:
		dice_type.add_item("d"+str(sides))
		dice_type.set_item_metadata(dice_type.item_count-1,sides)
	dice_type.select(DICE.SIDES.find(20))
	controls.add_child(dice_type)
	dice_count = SpinBox.new()
	dice_count.min_value = 1
	dice_count.max_value = DICE.MAX_QUANTITY
	dice_count.step = 1
	dice_count.value = 1
	dice_count.custom_minimum_size.x = 58
	controls.add_child(dice_count)
	var roll_button = button(controls,"Roll",roll_dice,16)
	roll_button.size_flags_horizontal = Control.SIZE_FILL
	dice_result = one_line(controls,"Result: —",16)
	dice_result.size_flags_stretch_ratio = 2.0
	for tool in [["Log","initiative"],["Rules","focus"],["Clear","diamond"]]:
		var target = str(tool[0])
		var icon_button = button(controls,"",func(): dice_tool(target),14,str(tool[1]))
		icon_button.size_flags_horizontal = Control.SIZE_FILL
		icon_button.custom_minimum_size = Vector2(27,30)
		icon_button.tooltip_text = "Scroll to latest log" if target=="Log" else ("Open rules reference" if target=="Rules" else "Clear manual dice result")
	label(dice,"Manual only · not part of campaign resolution",12,GOLD)

func dice_tool(target: String) -> void:
	match target:
		"Log": log_scroll.set_deferred("scroll_vertical",2147483647)
		"Rules": show_reference_index("Rules (SRD)","rule-sections")
		"Clear":
			last_roll = {}
			dice_result.text = "Result: —"
			dice_result.tooltip_text = ""

func show_status(message: String) -> void:
	if is_instance_valid(status):
		status.text = message

func roll_dice() -> void:
	last_roll = DICE.roll(int(dice_type.get_item_metadata(dice_type.selected)),int(dice_count.value))
	if last_roll.is_empty():
		return
	var values: PackedStringArray = []
	for die in last_roll["values"]:
		values.append(str(die))
	var text = "Total "+str(last_roll["total"])+"  ["+", ".join(values)+"]"
	dice_result.text = text
	dice_result.tooltip_text = text
	if values.size()>4:
		popup_text("Manual dice — "+str(last_roll["quantity"])+"d"+str(last_roll["sides"]),text)

func build_right(parent: VBoxContainer) -> void:
	var switcher = hbox(parent,2)
	for name_value in TABS:
		var tab = name_value
		var b = button(switcher,tab,func(): show_tab(tab),14)
		right_tabs[tab] = b
	var section = frame(parent,1.0,true,false,4)
	section.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_content = vbox(section,3)
	right_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	show_tab("Inventory")
	var references = frame(parent,1.0,true,false,4)
	one_line(references,"✧  Quick References (5e)",19,GOLD)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",3)
	grid.add_theme_constant_override("v_separation",3)
	references.add_child(grid)
	for item in [["Actions","rule-sections","initiative"],["Conditions","conditions","shield"],["Rules (SRD)","rule-sections","focus"],["Combat","rule-sections","armor"],["Spells","spells","wand"],["Equipment","equipment","pack"]]:
		var caption = str(item[0])
		var table = str(item[1])
		button(grid,caption,func(): show_reference_index(caption,table),14,str(item[2]))
	var party = frame(parent,1.0,true,false,4)
	one_line(party,"✧  Party",20,GOLD)
	var cards = hbox(party,4)
	var card = frame(cards,1.0,false,true,3)
	var avatar = picture(card,actor_portrait(),Vector2(0,52),true)
	avatar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	one_line(card,str(actor.get("name","Player")),14,GOLD,true)
	one_line(card,"Lv "+number(actor.get("level")),13,IVORY,true)
	var c = actor.get("combat",{})
	var hp_strip = PanelContainer.new()
	var red = StyleBoxFlat.new()
	red.bg_color = Color("#801e24")
	red.border_color = GOLD
	red.set_border_width_all(1)
	red.set_corner_radius_all(3)
	hp_strip.add_theme_stylebox_override("panel",red)
	card.add_child(hp_strip)
	one_line(hp_strip,number(c.get("hp_current"))+" / "+number(c.get("hp_max")),14,IVORY,true)
	for i in range(3):
		var empty = frame(cards,1.0,false,false,3)
		var silhouette = picture(empty,EMPTY_PARTY,Vector2(0,52))
		silhouette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var add_slot = button(empty,"+ Add",func(): pass,14)
		add_slot.disabled = true
		add_slot.tooltip_text = "Party membership mechanics are not implemented."

func show_tab(tab: String) -> void:
	if not is_instance_valid(right_content):
		return
	current_tab = tab
	for key in right_tabs:
		right_tabs[key].add_theme_stylebox_override("normal",box_style(key==tab,4))
	for child in right_content.get_children():
		right_content.remove_child(child)
		child.queue_free()
	match tab:
		"Inventory": build_inventory()
		"Spells": build_spells()
		"Skills": build_skills()
		"Features": build_features()
		"Notes": build_notes()

func equipped(id: String) -> bool:
	var gear = actor.get("equipment",{})
	return id==str(gear.get("armor_id","")) or id==str(gear.get("shield_id","")) or id in gear.get("weapon_ids",[])

func item_icon(id: String) -> String:
	if id=="shortsword": return "shortsword"
	if id=="backpack": return "backpack"
	var rec = cat.get_record("equipment",id)
	if str(rec.get("armor_category",""))=="Shield":
		return "shield"
	if rec.has("armor_category"):
		return "armor"
	if id in ["backpack","explorers-pack","priests-pack","scholars-pack","dungeoneers-pack","burglar-pack","entertainers-pack","diplomats-pack"]:
		return "pack"
	if id in ["robes","clothes-common","clothes-fine","clothes-travelers"]:
		return "robe"
	return ""

func build_inventory() -> void:
	inventory_cells.clear()
	var header = hbox(right_content,3)
	one_line(header,"Backpack",20,GOLD)
	var filter = OptionButton.new()
	filter.add_item("All Items")
	filter.add_item("Equipped")
	filter.select(1 if equipped_only else 0)
	header.add_child(filter)
	filter.item_selected.connect(func(i: int): equipped_only=i==1; show_tab("Inventory"))
	var sc = scroll(right_content,145)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation",3)
	grid.add_theme_constant_override("v_separation",3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	var shown: Array = []
	for item in items:
		var id = str(item["item_id"])
		if equipped_only and not equipped(id):
			continue
		shown.append(item)
		var name_value = title_for("equipment",id)
		var caption = name_value+"\n×"+number(item.get("quantity"))+(" • E" if equipped(id) else "")
		var art_id = item_icon(id)
		var visible_caption = ("×"+number(item.get("quantity"))+(" E" if equipped(id) else "")) if not art_id.is_empty() else caption
		var cell = button(grid,visible_caption,func(): select_item(id),13,art_id)
		cell.custom_minimum_size = Vector2(43,44)
		cell.expand_icon = true
		cell.add_theme_constant_override("icon_max_width",26)
		cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		cell.tooltip_text = caption
		inventory_cells[id] = cell
	for i in range(maxi(0,18-shown.size())):
		var empty = button(grid,"",func(): pass,12)
		empty.custom_minimum_size = Vector2(43,44)
		empty.disabled = true
		empty.tooltip_text = "Empty display cell"
	var detail = frame(right_content,1.0,false,false,4)
	inventory_detail = RichTextLabel.new()
	inventory_detail.bbcode_enabled = false
	inventory_detail.custom_minimum_size.y = 79
	inventory_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_detail.add_theme_font_size_override("normal_font_size",15)
	detail.add_child(inventory_detail)
	if not inventory_cells.has(selected_item):
		selected_item = str(shown[0]["item_id"]) if not shown.is_empty() else ""
	select_item(selected_item)

func select_item(id: String) -> void:
	selected_item = id
	for key in inventory_cells:
		inventory_cells[key].add_theme_stylebox_override("normal",box_style(key==id,3))
	if id.is_empty():
		inventory_detail.text = "No items in this view."
		return
	var rec = cat.get_record("equipment",id)
	var text: PackedStringArray = [title_for("equipment",id)+("  ·  Equipped" if equipped(id) else "")]
	for item in items:
		if str(item.get("item_id"))==id:
			text.append("Quantity: "+number(item.get("quantity")))
			break
	if rec.is_empty():
		text.append("Catalogue details unavailable.")
	else:
		for key in ["equipment_category","weapon_category","armor_category","damage","properties","weight","cost"]:
			if rec.has(key):
				text.append(str(key).replace("_"," ").capitalize()+": "+readable(rec[key]))
	inventory_detail.text = "\n".join(text)

func readable(value: Variant) -> String:
	if value is Dictionary:
		if value.has("name"): return str(value["name"])
		var parts: PackedStringArray = []
		for key in value:
			if key not in ["index","url"]:
				parts.append(str(key).replace("_"," ").capitalize()+": "+readable(value[key]))
		return ", ".join(parts)
	if value is Array:
		var parts: PackedStringArray = []
		for entry in value: parts.append(readable(entry))
		return ", ".join(parts)
	return number(value)

func list_for_tab(caption: String) -> VBoxContainer:
	one_line(right_content,caption,20,GOLD)
	return vbox(scroll(right_content,145),3)

func reference_row(parent: Node, table: String, id: String, caption: String = "") -> void:
	button(parent,title_for(table,id) if caption.is_empty() else caption,func(): inspect(table,id),15)

func build_spells() -> void:
	var list = list_for_tab("Spellcasting")
	var sp = actor.get("spellcasting",{})
	if sp.get("save_dc")!=null:
		label(list,"Save DC "+number(sp.get("save_dc"))+"  ·  Attack "+number(sp.get("attack_bonus"),true),16,GOLD)
	var has_spells = false
	for level in sp.get("slots",{}):
		var slot = sp["slots"][level]
		if int(slot.get("maximum",0))>0:
			has_spells = true
			label(list,"Level "+str(level)+" slots: "+number(int(slot["maximum"])-int(slot.get("spent",0)))+" / "+number(slot["maximum"]),16)
	for group in [["cantrip_ids","Cantrips"],["racial_cantrip_ids","Racial cantrips"],["known_ids","Spellbook" if actor.get("class_id")=="wizard" else "Known spells"],["prepared_ids","Prepared spells"],["always_prepared_ids","Always prepared"]]:
		var ids = sp.get(group[0],[])
		if not ids.is_empty():
			has_spells = true
			label(list,str(group[1]),17,GOLD)
			for id in ids:
				reference_row(list,"spells",str(id))
	if not has_spells:
		label(list,"No spells recorded.",16)

func build_skills() -> void:
	var list = list_for_tab("Skills & Saving Throws")
	for rec in cat.rows("skills"):
		var id = str(rec["index"])
		var skill = actor.get("skills",{}).get(id,{})
		if skill.is_empty():
			continue
		var marker = "◆ " if skill.get("expertise",false) else ("◇ " if skill.get("proficient",false) else "   ")
		reference_row(list,"skills",id,marker+str(rec["name"])+"   "+number(skill.get("modifier"),true))
	for key in ABILITIES:
		label(list,key.to_upper()+" Save  "+number(actor.get("saving_throws",{}).get(key),true),16)

func build_features() -> void:
	var list = list_for_tab("Features & Resources")
	for group in [["traits","racial_trait_ids"],["features","class_feature_ids"]]:
		for id in actor.get(group[1],[]):
			reference_row(list,str(group[0]),str(id))
	var bg = actor.get("background_feature",{})
	if bg is Dictionary and not bg.is_empty():
		label(list,cat.human(bg),16)
	for key in actor.get("resources",{}):
		var resource = actor["resources"][key]
		label(list,str(key).replace("_"," ").capitalize()+": "+number(int(resource.get("max",0))-int(resource.get("spent",0)))+" / "+number(resource.get("max")),16,GOLD)
	for id in actor.get("combat",{}).get("conditions",[]):
		reference_row(list,"conditions",str(id))

func build_notes() -> void:
	var list = list_for_tab("Established local facts")
	var facts = view.get("location",{}).get("payload",{}).get("world_facts",[])
	if facts.is_empty():
		label(list,"No additional local facts committed.",16)
	for fact in facts:
		label(list,str(fact),16)
	for key in ["description","personality","ideal","bond","flaw","backstory","notes"]:
		var value = str(actor.get(key,""))
		if not value.is_empty():
			label(list,str(key).capitalize(),16,GOLD)
			label(list,value,16)

func popup_base(caption: String) -> AcceptDialog:
	var popup = AcceptDialog.new()
	popup.title = caption
	popup.get_ok_button().text = "Close"
	popup.confirmed.connect(popup.queue_free)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	return popup

func popup_text(caption: String, content: String) -> void:
	var popup = popup_base(caption)
	var text = TextEdit.new()
	text.editable = false
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.text = content
	text.custom_minimum_size = Vector2(620,350)
	popup.add_child(text)
	popup.popup_centered(Vector2i(660,420))

func inspect(table: String, id: String) -> void:
	if not id.is_empty():
		popup_text(cat.title(table,id),cat.describe(table,id))

func show_reference_index(caption: String, table: String) -> void:
	var popup = popup_base(caption)
	var root = VBoxContainer.new()
	root.custom_minimum_size = Vector2(680,420)
	popup.add_child(root)
	var search = LineEdit.new()
	search.placeholder_text = "Search "+caption
	root.add_child(search)
	var row = hbox(root,5)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list = ItemList.new()
	list.custom_minimum_size.x = 235
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(list)
	var detail = TextEdit.new()
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	var populate = func(query: String):
		list.clear()
		for rec in cat.rows(table):
			var name_value = str(rec.get("name",""))
			if not query.strip_edges().is_empty() and not name_value.to_lower().contains(query.to_lower()):
				continue
			list.add_item(name_value)
			list.set_item_metadata(list.item_count-1,str(rec.get("index","")))
		detail.text = "Select a reference entry." if list.item_count>0 else "No matching catalogue entries."
	search.text_changed.connect(populate)
	list.item_selected.connect(func(i: int): detail.text=cat.describe(table,str(list.get_item_metadata(i))))
	if caption in ["Actions","Combat"]:
		search.text = caption
		populate.call(caption)
		if list.item_count==0:
			search.text = ""
			populate.call("")
	else:
		populate.call("")
	popup.popup_centered(Vector2i(720,490))

func show_character() -> void:
	if actor.is_empty():
		popup_text("Character","Campaign character unavailable.")
		return
	var popup = popup_base("Campaign Character — read only")
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1000,530)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	popup.add_child(sc)
	var sheet = SHEET.new()
	sheet.configure(actor,func(caption: String,detail: String): popup_text(caption,detail))
	sheet.custom_minimum_size.x = 960
	sc.add_child(sheet)
	popup.popup_centered(Vector2i(1040,610))

func show_quests() -> void:
	var lines: PackedStringArray = []
	for quest in view.get("quests",[]):
		var payload = quest.get("payload",{})
		lines.append(str(payload.get("name",payload.get("title",quest["id"])))+" — "+str(quest["status"]))
		if not payload.is_empty():
			lines.append(cat.human(payload))
	popup_text("Quest Log","\n\n".join(lines) if not lines.is_empty() else "No committed quests yet. Quest mechanics are pending.")

func show_map() -> void:
	var lines: PackedStringArray = []
	for location in view.get("locations",[]):
		var text = str(location["name"])+" — "+str(location["kind"]).capitalize()
		if location.get("x")!=null and location.get("y")!=null:
			text += " ("+str(location["x"])+", "+str(location["y"])+")"
		else:
			text += " · coordinates not established"
		lines.append(text)
	popup_text("Known Locations","\n".join(lines) if not lines.is_empty() else "No committed locations. Map travel mechanics are pending.")
