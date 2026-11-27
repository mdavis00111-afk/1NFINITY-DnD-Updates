extends VBoxContainer
## Presentation only: reads committed campaign data. C1 uses ui_intents.gd
## and an explicit trusted callback. Legacy signal retained but never emitted.
signal action_requested(campaign_id: String, actor_id: String, text: String)

const CAT = preload("res://rules/catalog.gd")
const STARTS = preload("res://campaigns/campaign_starts.gd")
const PORTRAIT = preload("res://players/portrait_art.gd")
const SHEET = preload("res://players/full_character_sheet.gd")
const DICE = preload("res://gameplay/manual_dice.gd")
const DISPLAY = preload("res://gameplay/display_values.gd")
const INTENTS = preload("res://gameplay/ui_intents.gd")
const WORLD = preload("res://world/world_store.gd")
const MAP_WINDOW = preload("res://cartography/map_window.gd")
const FRAME = preload("res://themes/parts/panel_gold.png")
const ACTIVE = preload("res://themes/parts/panel_active.png")
const CORNER = preload("res://themes/parts/corner.png")
const ATLAS = preload("res://themes/parts/icons.png")
const FONT = preload("res://themes/fonts/EBGaramond.ttf")
const DOLL = preload("res://gameplay/paper_doll.svg")
const COMPASS = preload("res://gameplay/reference_compass.png")
const EMPTY_PARTY = preload("res://gameplay/reference_party.png")
const SLOT_ATLAS = preload("res://gameplay/reference_slots.png")
const SLOT_NAMES = ["Head","Cloak","Body","Hands","Feet","Neck","Ring","Accessory","Belt","Shield"]
const SHORTSWORD = preload("res://gameplay/reference_shortsword.png")
const BACKPACK = preload("res://gameplay/reference_backpack.png")
const PORTRAIT_FRAME = preload("res://themes/parts/portrait_empty.png")
const GOLD = Color("#ffd989")
const IVORY = Color("#fff0cf")
const ABILITIES = ["str","dex","con","int","wis","cha"]
const TABS = ["Inventory","Spells","Skills","Features","Notes"]
var cat = CAT.new()
var intents = INTENTS.new()
var intent_buttons: Array = []
var popup_status_labels: Array = []
var inventory_actions: HBoxContainer
var last_chat_request_id = ""
var development_controller: Node
var local_pending_id=""
var local_pending_text=""
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

func configure(snapshot: Dictionary, metadata: Dictionary, on_leave: Callable, on_settings: Callable, on_retry: Callable, is_pending: bool, error: String = "", intent_handler: Callable = Callable()) -> void:
	intents.configure(snapshot,intent_handler)
	view = snapshot
	campaign = view.get("campaign",metadata)
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
	build_workspace()
	if is_instance_valid(development_controller):
		composer.text=str(extension().get("draft",""))

func build_workspace() -> void:
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
	refresh_intent_controls()

# Called only by the trusted future controller with a fresh, committed full view.
# Do not reconstruct the adapter or clear a request lock on ordinary redraws.
func apply_authoritative_view(snapshot: Dictionary) -> bool:
	if not intents.accept_view(snapshot):
		show_status(intents.last_error)
		refresh_intent_controls()
		return false
	var draft = composer.text if is_instance_valid(composer) else ""
	var focused=is_instance_valid(composer) and composer.has_focus()
	var caret=composer.caret_column if is_instance_valid(composer) else 0
	if is_instance_valid(development_controller):
		var ext=snapshot.get("interaction_extension",{})
		if not local_pending_id.is_empty() and (local_pending_id in ext.get("accepted_request_ids",[]) or ext.get("request_history",[]).any(func(row): return row.get("request_id")==local_pending_id)):
			if not local_pending_text.is_empty() and draft==local_pending_text:
				draft=""
			local_pending_id=""
			local_pending_text=""
	var previous_dice = last_roll.duplicate(true)
	var previous_dice_text = dice_result.text if is_instance_valid(dice_result) else "Result: —"
	var previous_dice_tip = dice_result.tooltip_text if is_instance_valid(dice_result) else ""
	var previous_die = dice_type.selected if is_instance_valid(dice_type) else DICE.SIDES.find(20)
	var previous_count = dice_count.value if is_instance_valid(dice_count) else 1.0
	if not last_chat_request_id.is_empty() and intents.interaction.get("settled_request_id")==last_chat_request_id:
		if intents.interaction.get("settled_status")=="committed":
			draft = ""
		if intents.interaction.get("settled_status") in ["committed","rejected","cancelled"]:
			last_chat_request_id = ""
	view = intents.snapshot
	campaign = view["campaign"]
	actor = view["actor"]
	items = view.get("inventory",[])
	pending = false
	data_error = ""
	for child in get_children():
		remove_child(child)
		child.queue_free()
	right_tabs.clear()
	inventory_cells.clear()
	intent_buttons.clear()
	popup_status_labels.clear()
	build_workspace()
	composer.text = draft
	composer.caret_column=mini(caret,draft.length())
	if focused and composer.editable:
		composer.grab_focus.call_deferred()
	last_roll = previous_dice
	dice_type.select(previous_die)
	dice_count.value = previous_count
	dice_result.text = previous_dice_text
	dice_result.tooltip_text = previous_dice_tip
	show_status(str(extension().get("status_text","Campaign view refreshed.")) if is_instance_valid(development_controller) else str(intents.interaction.get("status_text","Campaign view refreshed.")))
	return true

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
		if not is_finite(float(value)):
			return "—"
		var n = str(int(value)) if float(value)==floor(float(value)) else str(value)
		return "+"+n if signed_value and float(value)>=0 else n
	return str(value)

func title_for(table: String, id: Variant) -> String:
	var key = str(id) if id != null else ""
	return "—" if key.is_empty() else cat.title(table,key)

func actor_portrait() -> Texture2D:
	return EMPTY_PARTY if actor.is_empty() else PORTRAIT.texture_for(str(actor.get("portrait","")))

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
		"Campaign": request_leave()
		"Settings": request_settings()

func request_leave() -> void:
	if is_instance_valid(development_controller) and not development_controller.save_draft(composer.text if is_instance_valid(composer) else "").get("ok",false):
		show_status("Draft save unconfirmed; retry before leaving.")
		return
	if not intents.outstanding_id.is_empty() or not local_pending_id.is_empty():
		show_status("A request needs reconciliation before leaving the workspace.")
		return
	if leave_action.is_valid():
		leave_action.call()

func request_settings() -> void:
	if is_instance_valid(development_controller) and not development_controller.save_draft(composer.text if is_instance_valid(composer) else "").get("ok",false):
		show_status("Draft save unconfirmed; retry before leaving.")
		return
	if not intents.outstanding_id.is_empty() or not local_pending_id.is_empty():
		show_status("A request needs reconciliation before changing settings.")
		return
	if settings_action.is_valid():
		settings_action.call()

func stat(parent: Node, caption: String, value: String, icon_id: String = "", health: bool = false) -> void:
	var tile = frame(parent,1.0,false,false,3)
	var row: HBoxContainer
	if health:
		var max_hp = actor.get("combat",{}).get("hp_max")
		var current_hp = actor.get("combat",{}).get("hp_current")
		var bar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 27
		bar.max_value = maxf(1.0,float(max_hp)) if max_hp!=null else 1.0
		bar.value = float(current_hp) if current_hp!=null else 0.0
		var fill = StyleBoxFlat.new()
		fill.bg_color = Color("#a6262c")
		fill.set_corner_radius_all(4)
		var background = StyleBoxFlat.new()
		background.bg_color = Color("#301a2c")
		background.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill",fill)
		bar.add_theme_stylebox_override("background",background)
		tile.add_child(bar)
		row = hbox(bar,4)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 4
		row.offset_right = -4
	else:
		row = hbox(tile,4)
	if not icon_id.is_empty():
		var symbol = picture(row,glyph(icon_id),Vector2(17,17))
		symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	one_line(row,caption,15,GOLD)
	var val = one_line(row,value,16,IVORY)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Values must retain their natural width; the caption receives remaining space.
	# Equal expanding labels clipped Passive Perception and long HP totals.
	val.size_flags_horizontal = Control.SIZE_SHRINK_END
	val.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING

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
	var race_name = title_for("subraces",actor.get("subrace_id")) if not str(actor.get("subrace_id","")).is_empty() else title_for("races",actor.get("race_id"))
	label(info,"Level "+number(actor.get("level"))+"  "+title_for("classes",actor.get("class_id"))+" ("+race_name+")",14,GOLD,true)
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
	if not intents.interaction.is_empty():
		weapon_caption.clear()
		var shown_instances = {}
		for hand in ["main_hand","off_hand"]:
			var hand_item = intents.instance(str(intents.interaction["slot_assignments"].get(hand,"")))
			if not hand_item.is_empty() and not shown_instances.has(hand_item["instance_id"]):
				weapon_caption.append(str(hand_item["name"]))
				shown_instances[hand_item["instance_id"]] = true
	var weapon = button(middle,"Weapon: "+(", ".join(weapon_caption) if not weapon_caption.is_empty() else "Empty"),func(): show_equipped_weapons(),14,item_icon(str(weapons[0])) if weapons.size()==1 else "")
	weapon.tooltip_text = "Inspect or choose main/off hand equipment"
	for slot in ["Neck","Ring","Accessory","Belt","Shield"]:
		slot_card(right,slot,str(gear.get("shield_id","")) if slot=="Shield" else "")
	var money = frame(parent,1.0,false,false,4)
	var coins: PackedStringArray = []
	for denomination in ["pp","gp","ep","sp","cp"]:
		if actor.get("coins",{}).has(denomination):
			coins.append(number(actor["coins"][denomination])+" "+denomination)
	one_line(money,"Coins: "+("  ·  ".join(coins) if not coins.is_empty() else "Not recorded"),15,GOLD)
	var weight_label = one_line(money,"Weight: "+DISPLAY.load_text(actor),16)
	var missing = actor.get("weight_projection",{}).get("missing",[])
	if not missing.is_empty():
		weight_label.tooltip_text += "\nUnknown weight/amount: "+", ".join(missing)
	var warnings = actor.get("display_warnings",[])
	if not warnings.is_empty():
		equipment.tooltip_text = "Stored equipment inconsistencies; statistics not recalculated.\n"+"\n".join(warnings)
		weapon.tooltip_text += "\n"+"\n".join(warnings)

func slot_card(parent: Node, slot: String, id: String) -> void:
	var slot_id = slot.to_lower()
	var caption = title_for("equipment",id) if not id.is_empty() else "Empty"
	var occupied = not id.is_empty()
	if not intents.interaction.is_empty():
		var assigned = intents.instance(str(intents.interaction["slot_assignments"].get(slot_id,"")))
		occupied = not assigned.is_empty()
		caption = str(assigned["name"]) if occupied else "Empty"
	if is_instance_valid(development_controller) and intents.interaction.is_empty():
		caption=current_slot_text(slot_id)
		occupied=caption not in ["Unresolved","Not established"]
	var b = button(parent,caption,func(): show_slot(slot_id),12,"armor" if slot=="Body" and occupied else ("shield" if slot=="Shield" and occupied else ""))
	b.custom_minimum_size.y = 40
	b.tooltip_text = slot+" — "+caption+" · Inspect / choose owned equipment"
	if not occupied:
		var atlas = AtlasTexture.new()
		atlas.atlas = SLOT_ATLAS
		atlas.region = Rect2(SLOT_NAMES.find(slot)*28,0,28,28)
		b.icon = atlas
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width",20)

func show_equipped_weapons() -> void:
	var popup = popup_base("Hands & equipped weapons")
	var col = vbox(popup,6)
	col.custom_minimum_size = Vector2(560,0)
	if intents.interaction.is_empty():
		var lines: PackedStringArray = []
		for id in actor.get("equipment",{}).get("weapon_ids",[]):
			lines.append(title_for("equipment",id))
		label(col,"Recorded weapons: "+(", ".join(lines) if not lines.is_empty() else "None recorded"))
		label(col,"Legacy equipment has no hand assignment. Inspect compatible owned weapons; changing hands needs the authoritative equipment handler.",15,GOLD)
	else:
		for hand in ["main_hand","off_hand","shield"]:
			var assigned = intents.instance(str(intents.interaction["slot_assignments"].get(hand,"")))
			label(col,hand.replace("_"," ").capitalize()+": "+str(assigned.get("name","Empty")))
	for hand in ["main_hand","off_hand","shield"]:
		var key = hand
		button(col,key.replace("_"," ").capitalize(),func(): popup.queue_free(); show_slot(key))
	popup.popup_centered(Vector2i(600,260))

func display_items() -> Array:
	# Legacy stacks are for inspection only. C2 supplies actual stable IDs.
	return extension()["inventory_instances"] if is_instance_valid(development_controller) and extension().has("inventory_instances") else (intents.interaction["inventory_instances"] if not intents.interaction.is_empty() else items)

func item_key(row: Dictionary) -> String:
	return str(row.get("instance_id",row.get("item_id","")))

func item_definition(row: Dictionary) -> String:
	return str(row.get("definition_id",row.get("item_id","")))

func item_name(row: Dictionary) -> String:
	return str(row.get("name",title_for("equipment",item_definition(row))))

func display_item(key: String) -> Dictionary:
	for row in display_items():
		if item_key(row)==key:
			return row
	return {}

func item_description(row: Dictionary) -> String:
	if row.is_empty():
		return "No item selected."
	if row.has("description"):
		return str(row["description"])
	return cat.describe("equipment",item_definition(row))

func legacy_slots(row: Dictionary) -> Array:
	var rec = cat.get_record("equipment",item_definition(row))
	if rec.get("armor_category")=="Shield":
		return ["shield"]
	if rec.get("armor_category") in ["Light","Medium","Heavy"]:
		return ["body"]
	if rec.has("weapon_category"):
		# Read catalogue physical property only; no proficiency, attack or
		# offhand legality decision is made by this legacy display.
		for prop in rec.get("properties",[]):
			if prop is Dictionary and prop.get("index")=="two-handed":
				return ["main_hand"]
		return ["main_hand","off_hand"]
	return []

func slot_options(slot: String) -> Array:
	var options: Array = []
	for row in display_items():
		if intents.interaction.is_empty():
			if slot in legacy_slots(row):
				options.append({"row":row,"option":{},"kind":""})
			continue
		for opt in row.get("equip_options",[]):
			if opt.get("slot")==slot:
				options.append({"row":row,"option":opt,"kind":"equip" if opt["replace_instance_ids"].is_empty() else "swap"})
	return options

func current_slot_text(slot: String) -> String:
	if is_instance_valid(development_controller) and intents.interaction.is_empty():
		for assignment in extension().get("known_slot_assignments",[]):
			if assignment["slot"]==slot:
				return item_name(display_item(assignment["instance_id"]))
		return "Unresolved" if not extension().get("equipment_review",[]).is_empty() else "Not established"
	if not intents.interaction.is_empty():
		var row = intents.instance(str(intents.interaction["slot_assignments"].get(slot,"")))
		return str(row.get("name","Empty"))
	var gear = actor.get("equipment",{})
	if slot in ["main_hand","off_hand"]:
		var labels: PackedStringArray = []
		for id in gear.get("weapon_ids",[]):
			labels.append(title_for("equipment",id))
		return "Hand not recorded; weapons: "+(", ".join(labels) if not labels.is_empty() else "None")
	var key = "armor_id" if slot=="body" else ("shield_id" if slot=="shield" else "")
	if key.is_empty():
		return "No slot assignment recorded"
	var id = str(gear.get(key,""))
	return title_for("equipment",id) if not id.is_empty() else "Empty"

func show_slot(slot: String, preferred_id: String = "") -> void:
	if not slot in INTENTS.SLOTS:
		return
	var popup = popup_base(slot.replace("_"," ").capitalize()+" equipment")
	var col = vbox(popup,5)
	col.custom_minimum_size = Vector2(650,0)
	label(col,"Current: "+current_slot_text(slot),19,GOLD)
	label(col,"Owned compatible items · select an item or grip",15,GOLD)
	var row_box = hbox(col,6)
	row_box.custom_minimum_size.y = 270
	var list = ItemList.new()
	list.custom_minimum_size.x = 245
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row_box.add_child(list)
	var detail = TextEdit.new()
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(detail)
	var options = slot_options(slot)
	var selected = {"index":-1}
	var actions = hbox(col,5)
	var equip_button = button(actions,"Equip / Swap",func():
		var index = int(selected["index"])
		if index<0 or index>=options.size():
			return
		var candidate = options[index]
		var opt = candidate["option"]
		if opt.is_empty():
			return
		var args = {"instance_id":candidate["row"]["instance_id"],"slot":slot,"grip":opt["grip"]}
		if candidate["kind"]=="swap":
			args["replace_instance_ids"] = opt["replace_instance_ids"].duplicate()
		request_intent(candidate["kind"],args)
		if not intents.outstanding_id.is_empty():
			popup.queue_free()
	,16)
	track_intent(equip_button,"equip",false,"Select an offered compatible instance.")
	var current_id = intents.interaction.get("slot_assignments",{}).get(slot)
	var unequip = intent_button(actions,"Unequip","unequip",{"instance_id":current_id,"slot":slot},current_id!=null,"Current instance assignment required.")
	unequip.tooltip_text = "Unequip the current item via the controller. "+unequip.tooltip_text
	var show_option = func(index: int):
		selected["index"] = index
		var candidate = options[index]
		var item = candidate["row"]
		var opt = candidate["option"]
		var lines: PackedStringArray = [item_name(item),"Owned quantity: "+number(item.get("quantity")),item_description(item)]
		if opt.is_empty():
			lines.append("Legacy stack: grip, proficiency, attunement, hand conflicts and action timing require C2/C3. Inspection only.")
			track_intent(equip_button,"equip",false,"Legacy inventory stack; stable instance required.")
			equip_button.text = "Equip / Swap"
		else:
			lines.append("Grip: "+str(opt["grip"]).replace("_"," "))
			var displaced: PackedStringArray = []
			for other in opt["replace_instance_ids"]:
				displaced.append(str(intents.instance(other).get("name","Owned item")))
			if not displaced.is_empty():
				lines.append("Atomic swap displaces: "+", ".join(displaced))
			if not str(opt["warning"]).is_empty():
				lines.append(str(opt["warning"]))
			equip_button.text = "Swap" if candidate["kind"]=="swap" else "Equip"
			track_intent(equip_button,candidate["kind"],opt["available"],str(opt["warning"]))
		detail.text = "\n\n".join(lines)
	for candidate in options:
		var item = candidate["row"]
		var opt = candidate["option"]
		var caption = item_name(item)+" ×"+number(item.get("quantity"))
		if not opt.is_empty():
			caption += " · "+str(opt["grip"]).replace("_"," ")
		list.add_item(caption)
	list.item_selected.connect(show_option)
	if options.is_empty():
		detail.text = "No compatible owned items are recorded for this slot. No item or assignment will be invented."
	else:
		var index = 0
		for i in range(options.size()):
			if item_key(options[i]["row"])==preferred_id:
				index = i
				break
		list.select(index)
		show_option.call(index)
	popup_status(col)
	popup.popup_centered(Vector2i(690,440))

func equip_from_inventory(id: String) -> void:
	var item = display_item(id)
	if item.is_empty():
		return
	var popup = popup_base("Equip "+item_name(item))
	var col = vbox(popup,5)
	col.custom_minimum_size.x = 410
	var slots: Array = []
	if intents.interaction.is_empty():
		slots = legacy_slots(item)
	else:
		for opt in item.get("equip_options",[]):
			if not opt["slot"] in slots:
				slots.append(opt["slot"])
	if slots.is_empty():
		label(col,"No compatible slot is recorded. Equipment compatibility requires an authoritative item definition.")
	for slot in slots:
		var key = str(slot)
		button(col,key.replace("_"," ").capitalize(),func(): popup.queue_free(); show_slot(key,id))
	label(col,"No equipment changes occur until the controller resolves and commits the selected intent.",14,GOLD)
	popup.popup_centered(Vector2i(450,260))

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
	one_line(location_band,str(campaign.get("title","Campaign"))+"  ·  "+str(location.get("name","Location unavailable")),15,GOLD,true)
	var log = frame(parent,1.0,true,false,5)
	log.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll = scroll(log,120)
	log_list = vbox(log_scroll,6)
	for event in view.get("events",[]):
		if not event.get("kind") in ["campaign_created","narration","player_action","mechanical_summary"] or not event.get("text") is String:
			continue
		var role = "System" if event.get("kind") in ["campaign_created","mechanical_summary"] else ("Player" if event.get("kind")=="player_action" else "DM")
		var entry = hbox(log_list,6)
		picture(entry,actor_portrait() if role=="Player" else glyph("diamond" if role=="System" else "initiative"),Vector2(30,30))
		var words = vbox(entry,2)
		one_line(words,role+"  ·  Turn "+number(event.get("turn")),17,GOLD)
		label(words,str(event.get("text","")),17,IVORY)
		var divider = HSeparator.new()
		log_list.add_child(divider)
	if view.get("events",[]).is_empty():
		label(log_list,"No committed adventure events available.",16)
	if is_instance_valid(development_controller) and not str(extension().get("reviewed_preview","")).is_empty():
		label(log_list,"DM · Critically reviewed preview — world reconciliation pending",15,GOLD)
		label(log_list,str(extension()["reviewed_preview"]),17,IVORY)
	if not data_error.is_empty():
		label(log_list,data_error,16,GOLD)
	log_scroll.set_deferred("scroll_vertical",2147483647)
	var actions = hbox(parent,4)
	if view.get("opening_available",false) and not is_instance_valid(development_controller):
		opening_button = button(actions,"Generate Opening",retry_action,15,"wand")
		opening_button.disabled = pending or not data_error.is_empty()
	button(actions,"Turn / Retry",show_turn_controls,15)
	if is_instance_valid(development_controller):
		button(actions,"World",show_world_menu,15)
	var save_exit = button(actions,"Save & Exit",request_leave,15)
	save_exit.tooltip_text = "Committed campaign data and accepted work are saved. Manual dice are not saved." if is_instance_valid(development_controller) else "Committed campaign data is already saved. Pending opening generation is canceled; manual dice are not saved."
	var status_text = str(extension().get("status_text","Development controller pending.")) if is_instance_valid(development_controller) else str(intents.interaction.get("status_text","Turn controller pending — action submission unavailable."))
	if not data_error.is_empty():
		status_text = "Campaign data unavailable. Return to Campaign and reopen."
	elif pending:
		status_text = "Generating opening… Saved campaign is safe."
	status = label(parent,status_text,14,GOLD)
	status.max_lines_visible = 2
	status.custom_minimum_size.y = 20
	var compose = hbox(parent,4)
	composer = LineEdit.new()
	composer.placeholder_text = "Type your action here… (turn controller pending)"
	composer.editable = false
	composer.max_length = 2000
	composer.text_submitted.connect(func(_value: String): submit_chat())
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer.add_theme_stylebox_override("normal",box_style(false,5))
	composer.add_theme_stylebox_override("read_only",box_style(false,5))
	composer.custom_minimum_size.y = 34
	compose.add_child(composer)
	send_button = button(compose,"Send",submit_chat,16)
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
	dice_result.custom_minimum_size.x = 68
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

func can_intent(kind: String) -> bool:
	if is_instance_valid(development_controller):
		if pending or not data_error.is_empty() or not local_pending_id.is_empty() or not intents.outstanding_id.is_empty():
			return false
		if kind=="chat":
			return extension().get("phase")=="idle" or extension().get("can_queue",false)
		return extension().get("phase")=="idle" and kind in extension().get("supported_intents",[])
	return not pending and data_error.is_empty() and intents.available(kind)

func intent_reason(kind: String) -> String:
	if pending or not data_error.is_empty():
		return "Campaign busy or unavailable."
	return intents.reason(kind)

func track_intent(control: Button,kind: String,local_allowed: bool = true,local_reason: String = "") -> void:
	# A selection may change Equip to Swap, or change cast availability.
	# Replace its previous binding rather than leave a stale enabled button.
	for i in range(intent_buttons.size()-1,-1,-1):
		var previous = intent_buttons[i]["button"]
		if not is_instance_valid(previous) or previous==control:
			intent_buttons.remove_at(i)
	intent_buttons.append({"button":control,"kind":kind,"allowed":local_allowed,"reason":local_reason})
	control.disabled = not local_allowed or not can_intent(kind)
	control.tooltip_text = local_reason if not local_allowed else intent_reason(kind)

func intent_button(parent: Node,caption: String,kind: String,args: Dictionary,local_allowed: bool = true,local_reason: String = "") -> Button:
	var b = button(parent,caption,func(): request_intent(kind,args),15)
	track_intent(b,kind,local_allowed,local_reason)
	return b

func popup_status(parent: Node) -> void:
	var note = label(parent,"Controller not connected — inspection only." if not intents.handler.is_valid() else "Intents are resolved by the controller; no optimistic updates.",14,GOLD)
	popup_status_labels.append(note)

func refresh_intent_controls() -> void:
	var live: Array = []
	for binding in intent_buttons:
		var control = binding["button"]
		if is_instance_valid(control) and not control.is_queued_for_deletion():
			control.disabled = not binding["allowed"] or not can_intent(binding["kind"])
			control.tooltip_text = binding["reason"] if not binding["allowed"] else intent_reason(binding["kind"])
			live.append(binding)
	intent_buttons = live
	if is_instance_valid(composer):
		composer.editable = is_instance_valid(development_controller) or can_intent("chat")
		composer.placeholder_text = "Type your action here…" if composer.editable else "Type your action here… (controller unavailable)"
	if is_instance_valid(send_button):
		send_button.disabled = not can_intent("chat")
		send_button.text="Queue" if is_instance_valid(development_controller) and extension().get("can_queue",false) else "Send"
		send_button.tooltip_text = "One durable next action; resolves only after settlement." if is_instance_valid(development_controller) else intent_reason("chat")

func request_intent(kind: String,args: Dictionary) -> Dictionary:
	var reply: Dictionary
	if is_instance_valid(development_controller):
		reply=dev_submit(kind,args,"1") if can_intent(kind) else {"ok":false,"message":"Action unavailable or previous work pending."}
	else:
		reply = intents.request(kind,args) if can_intent(kind) else {"ok":false,"message":intent_reason(kind)}
	var message = str(reply.get("message","Request unavailable."))
	show_status(message)
	var live: Array = []
	for note in popup_status_labels:
		if is_instance_valid(note) and not note.is_queued_for_deletion():
			note.text = message
			live.append(note)
	popup_status_labels = live
	refresh_intent_controls()
	return reply

func submit_chat() -> void:
	if not is_instance_valid(composer):
		return
	var sent=request_intent("chat",{"text":composer.text})
	if is_instance_valid(development_controller):
		if sent.get("ok",false):
			composer.clear() # Exact original text already persisted in journal.
		return
	if not intents.outstanding_id.is_empty():
		last_chat_request_id = intents.outstanding_id
	# Preserve original text until matching committed settlement.

func show_turn_controls() -> void:
	if is_instance_valid(development_controller):
		show_processing()
		return
	var popup = popup_base("Turn status")
	var col = vbox(popup,6)
	col.custom_minimum_size.x = 470
	label(col,str(intents.interaction.get("status_text","Turn controller not connected.")),18,GOLD)
	label(col,"Retry uses the same active turn. A committed receipt is never rolled again.",15)
	var active_id = intents.interaction.get("active_turn_id")
	intent_button(col,"Retry active turn","retry",{"turn_id":active_id},active_id!=null,"No active turn recorded.")
	intent_button(col,"Cancel / reconcile active turn","cancel",{"turn_id":active_id},active_id!=null,"No active turn recorded.")
	popup_status(col)
	popup.popup_centered(Vector2i(510,250))

func roll_dice() -> void:
	last_roll = DICE.roll(int(dice_type.get_item_metadata(dice_type.selected)),int(dice_count.value))
	if last_roll.is_empty():
		return
	var values: PackedStringArray = []
	for die in last_roll["values"]:
		values.append(str(die))
	var text = "Total "+str(last_roll["total"])+"  ["+", ".join(values)+"]"
	var font = dice_result.get_theme_font("font")
	var text_width = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,dice_result.get_theme_font_size("font_size")).x
	var needs_detail = values.size()>4 or text_width>dice_result.size.x
	dice_result.text = "Total "+str(last_roll["total"]) if needs_detail else text
	dice_result.tooltip_text = text
	if needs_detail:
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
	show_tab(current_tab if current_tab in TABS else "Inventory")
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
	one_line(card,str(actor.get("name","Unavailable")),14,GOLD,true)
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
	var members: Array = intents.interaction.get("party_members",[])
	for i in range(3):
		var slot = frame(cards,1.0,false,false,3)
		if i<members.size():
			if i==2 and members.size()>3:
				picture(slot,EMPTY_PARTY,Vector2(0,52))
				button(slot,"+"+str(members.size()-2)+" party",show_party_roster,13)
			else:
				var member = members[i]
				var portrait = picture(slot,PORTRAIT.texture_for(str(member.get("portrait",""))),Vector2(0,52),true)
				portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				one_line(slot,str(member["name"]),14,GOLD,true)
				one_line(slot,"Lv "+number(member.get("level")),13,IVORY,true)
				one_line(slot,number(member.get("hp_current"))+" / "+number(member.get("hp_max")),14,IVORY,true)
		else:
			var silhouette = picture(slot,EMPTY_PARTY,Vector2(0,52))
			silhouette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var add_slot = button(slot,"+ Add",show_party_picker,14)
			var offered = false
			for candidate in intents.interaction.get("party_candidates",[]):
				if candidate.get("available",false):
					offered = true
			track_intent(add_slot,"party_add",offered,"No authoritative party candidate offered.")

func show_party_roster() -> void:
	var lines: PackedStringArray = [str(actor.get("name","Player"))]
	for member in intents.interaction.get("party_members",[]):
		lines.append(str(member["name"])+" · Level "+number(member.get("level"))+" · HP "+number(member.get("hp_current"))+" / "+number(member.get("hp_max")))
	popup_text("Party roster","\n".join(lines))

func show_party_picker() -> void:
	var popup = popup_base("Known party candidates")
	var col = vbox(popup,5)
	col.custom_minimum_size.x = 470
	var list = vbox(scroll(col,170),4)
	for candidate in intents.interaction.get("party_candidates",[]):
		var row = candidate
		intent_button(list,str(row["name"]),"party_add",{"member_actor_id":row["actor_id"]},row["available"],str(row["warning"]))
	if intents.interaction.get("party_candidates",[]).is_empty():
		label(list,"No disclosed eligible party candidate recorded.")
	label(col,"Adding a party member requires controller validation; no NPC or companion is created here.",15,GOLD)
	popup_status(col)
	popup.popup_centered(Vector2i(510,330))

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
	if is_instance_valid(development_controller) and intents.interaction.is_empty():
		return extension().get("known_slot_assignments",[]).any(func(row): return row["instance_id"]==id)
	if not intents.interaction.is_empty():
		return id in intents.interaction["slot_assignments"].values()
	for item in items:
		if str(item.get("item_id",""))==id:
			return item.get("equipped")==true
	return false

func item_icon(id: String) -> String:
	if id=="shortsword": return "shortsword"
	if id=="backpack": return "backpack"
	var rec = cat.get_record("equipment",id)
	if str(rec.get("armor_category",""))=="Shield":
		return "shield"
	if rec.has("armor_category"):
		return "armor"
	if id in ["backpack","explorers-pack","priests-pack","scholars-pack","dungeoneers-pack","burglars-pack","entertainers-pack","diplomats-pack"]:
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
	for item in display_items():
		var id = item_key(item)
		if equipped_only and not equipped(id):
			continue
		shown.append(item)
		var name_value = item_name(item)
		var caption = name_value+"\n×"+number(item.get("quantity"))+(" • E" if equipped(id) else "")
		var art_id = item_icon(item_definition(item))
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
		selected_item = item_key(shown[0]) if not shown.is_empty() else ""
	inventory_actions = hbox(detail,3)
	select_item(selected_item)

func select_item(id: String) -> void:
	selected_item = id
	for key in inventory_cells:
		inventory_cells[key].add_theme_stylebox_override("normal",box_style(key==id,3))
	if is_instance_valid(inventory_actions):
		for child in inventory_actions.get_children():
			inventory_actions.remove_child(child)
			child.queue_free()
	var item = display_item(id)
	if item.is_empty():
		inventory_detail.text = "No items in this view."
		return
	var definition = item_definition(item)
	var rec = cat.get_record("equipment",definition)
	var text: PackedStringArray = [item_name(item)+("  ·  Equipped" if equipped(id) else ""),"Quantity: "+number(item.get("quantity"))]
	if item.has("instance_id"):
		# C2 owns custom definitions, instance modifications and actual weight.
		text.append(item_description(item))
		var unit = item.get("unit_weight_lb")
		if DISPLAY.numeric(unit) and float(unit)>=0:
			text.append("Unit weight: "+DISPLAY.weight_number(unit)+" lb")
			text.append("Stack weight: "+DISPLAY.weight_number(float(unit)*int(item["quantity"]))+" lb")
		else:
			text.append("Unit weight: not recorded")
	elif rec.is_empty():
		text.append("Catalogue details unavailable.")
	else:
		for key in ["equipment_category","weapon_category","armor_category","armor_class","damage","properties","range"]:
			if rec.has(key):
				text.append(str(key).replace("_"," ").capitalize()+": "+readable(rec[key]))
		var unit = DISPLAY.unit_weight(cat,definition)
		text.append("Unit weight: "+DISPLAY.weight_number(unit)+" lb" if unit!=null else "Unit weight: not recorded")
		if unit!=null:
			text.append("Stack weight: "+DISPLAY.weight_number(float(unit)*int(item["quantity"]))+" lb")
		if rec.has("cost") and rec["cost"]!=null:
			var lot = int(DISPLAY.AMMO_LOTS.get(definition,1))
			text.append("Catalogue cost: "+readable(rec["cost"])+(" per "+str(lot) if lot>1 else ""))
	for key in ["charges","attunement_status","public_warning"]:
		if item.has(key):
			text.append(key.replace("_"," ").capitalize()+": "+readable(item[key]))
	inventory_detail.text = "\n".join(text)
	if is_instance_valid(inventory_actions):
		button(inventory_actions,"Equip",func(): equip_from_inventory(id),14)
		var use = button(inventory_actions,"Use",func(): item_quantity_popup(id,"item_use"),14)
		var drop = button(inventory_actions,"Drop",func(): item_quantity_popup(id,"item_drop"),14)
		# Open inspection even when unbound. The confirm button carries the gate.
		use.tooltip_text = "Inspect use intention · "+intent_reason("item_use")
		drop.tooltip_text = "Inspect drop intention · "+intent_reason("item_drop")
		button(inventory_actions,"More",func(): show_item_more(id),14)

func item_quantity_popup(id: String,kind: String) -> void:
	var item = display_item(id)
	if item.is_empty():
		return
	var popup = popup_base(("Use " if kind=="item_use" else "Drop ")+item_name(item))
	var col = vbox(popup,5)
	col.custom_minimum_size.x = 450
	label(col,item_description(item),15)
	var row = hbox(col,5)
	label(row,"Quantity (owned "+number(item.get("quantity"))+")")
	var quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = maxi(1,int(item.get("quantity",1)))
	quantity.step = 1
	quantity.value = 1
	row.add_child(quantity)
	var target: OptionButton
	if kind=="item_use":
		if is_instance_valid(development_controller):
			target=target_picker(col)
			quantity.max_value=1
		else:
			label(col,"Target not selected. The controller may request an explicit target or other decision.",14,GOLD)
	var confirm = button(col,"Submit "+("use" if kind=="item_use" else "drop")+" intention",func():
		var args = {"instance_id":item.get("instance_id"),"quantity":int(quantity.value)}
		if kind=="item_use":
			args["target_id"] = selected_target(target)
		if kind=="item_use" and is_instance_valid(development_controller) and args["target_id"]==null:
			show_status("Select an explicit supported target.")
			return
		request_intent(kind,args)
	,16)
	var supported=item.has("instance_id")
	if kind=="item_use" and is_instance_valid(development_controller):
		supported=supported and item_definition(item) in ["magic:potion-of-healing-common","magic:potion-of-healing-greater","magic:potion-of-healing-superior","magic:potion-of-healing-supreme","rations-1-day"]
	track_intent(confirm,kind,supported,"Stable owned instance and supported effect required.")
	popup_status(col)
	popup.popup_centered(Vector2i(490,320))

func show_item_more(id: String) -> void:
	var item = display_item(id)
	if item.is_empty():
		return
	var popup = popup_base(item_name(item))
	var col = vbox(popup,5)
	col.custom_minimum_size.x = 530
	var detail = TextEdit.new()
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.custom_minimum_size.y = 200
	detail.text = item_description(item)
	col.add_child(detail)
	var assignment = str(item.get("attunement_status","unknown"))
	label(col,"Attunement: "+assignment.replace("_"," ").capitalize(),16,GOLD)
	var row = hbox(col,4)
	intent_button(row,"Attune","attune",{"instance_id":item.get("instance_id")},assignment=="unattuned","Attunement eligibility not recorded.")
	intent_button(row,"End attunement","unattune",{"instance_id":item.get("instance_id")},assignment=="attuned","No recorded attunement.")
	button(col,"Choose equipment slot",func(): popup.queue_free(); equip_from_inventory(id))
	popup_status(col)
	popup.popup_centered(Vector2i(570,370))

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
	if sp.get("save_dc")!=null or sp.get("attack_bonus")!=null:
		label(list,"Class Save DC "+number(sp.get("save_dc"))+"  ·  Attack "+number(sp.get("attack_bonus"),true),16,GOLD)
	var racial = DISPLAY.racial_spell_text(actor)
	if not racial.is_empty():
		label(list,racial,15,GOLD)
	var has_spells = false
	for level in sp.get("slots",{}):
		var slot = sp["slots"][level]
		if slot.get("maximum")!=0 or slot.get("spent")!=0:
			has_spells = true
			var slot_kind = " pact slots: " if sp.get("pact_magic",false) else " slots: "
			label(list,"Level "+str(level)+slot_kind+DISPLAY.remaining_text(slot.get("maximum"),slot.get("spent")),16)
	for group in [["cantrip_ids","Cantrips"],["racial_cantrip_ids","Racial cantrips"],["known_ids","Spellbook" if actor.get("class_id")=="wizard" else "Known spells"],["prepared_ids","Prepared spells"],["always_prepared_ids","Always prepared"]]:
		var ids = sp.get(group[0],[])
		if not ids.is_empty():
			has_spells = true
			label(list,str(group[1]),17,GOLD)
			for id in ids:
				var spell_id = str(id)
				button(list,title_for("spells",spell_id),func(): show_spell(spell_id),15)
	var additional: Array = []
	for opt in intents.interaction.get("preparation_options",[])+intents.interaction.get("spell_options",[]):
		var id = str(opt["spell_id"])
		if not intents.owns_spell(id) and not id in additional:
			additional.append(id)
	if not additional.is_empty():
		label(list,"Additional offered spell choices",17,GOLD)
		for id in additional:
			var spell_id = str(id)
			button(list,title_for("spells",spell_id),func(): show_spell(spell_id),15)
	if not has_spells and additional.is_empty():
		label(list,"No spells recorded.",16)

func show_spell(id: String) -> void:
	var popup = popup_base(title_for("spells",id))
	var col = vbox(popup,5)
	col.custom_minimum_size.x = 640
	var detail = TextEdit.new()
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.custom_minimum_size.y = 230
	detail.text = cat.describe("spells",id)
	col.add_child(detail)
	var sp = actor.get("spellcasting",{})
	var sources: PackedStringArray = []
	for group in [["cantrip_ids","Class cantrip"],["racial_cantrip_ids","Racial cantrip"],["known_ids","Known"],["prepared_ids","Prepared"],["always_prepared_ids","Always prepared"]]:
		if id in sp.get(group[0],[]):
			sources.append(group[1])
	label(col,"Recorded sources: "+(", ".join(sources) if not sources.is_empty() else "Preparation choice"),15,GOLD)
	var prep_row = hbox(col,4)
	for kind in ["spell_prepare","spell_unprepare"]:
		var offer = intents.preparation_option(id,kind)
		if is_instance_valid(development_controller):
			var prep_kind=kind
			var action=button(prep_row,"Prepare" if kind=="spell_prepare" else "Unprepare",func(): popup.queue_free(); show_preparation(prep_kind,id),15)
			action.disabled=not offer.get("available",false) or not can_choice(kind)
		else:
			intent_button(prep_row,"Prepare" if kind=="spell_prepare" else "Unprepare",kind,{"spell_id":id},offer.get("available",false),str(offer.get("warning","Preparation eligibility requires the handler.")))
	var cast_row = hbox(col,4)
	var cast_choices = OptionButton.new()
	cast_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_row.add_child(cast_choices)
	var options: Array = []
	for opt in intents.interaction.get("spell_options",[]):
		if opt.get("spell_id")==id:
			options.append(opt)
			var text = str(opt["source"]).replace("_"," ").capitalize()+" · "+("Slotless" if opt["slot_level"]==0 else "Level "+str(opt["slot_level"]))
			cast_choices.add_item(text)
			cast_choices.set_item_disabled(cast_choices.item_count-1,not opt["available"])
	var target: OptionButton
	if is_instance_valid(development_controller):
		target=target_picker(col)
	var cast_note = label(col,"Select an explicit target; supported self healing only." if is_instance_valid(development_controller) else "Target is unselected; controller resolves or asks for required choices.",14,GOLD)
	var cast = button(cast_row,"Cast",func():
		var index = cast_choices.selected
		if index<0 or index>=options.size():
			return
		var opt = options[index]
		var target_id=selected_target(target)
		if is_instance_valid(development_controller) and target_id==null:
			show_status("Select the supported self target.")
			return
		request_intent("spell_cast",{"spell_id":id,"source":opt["source"],"slot_level":opt["slot_level"],"target_id":target_id})
		if not intents.outstanding_id.is_empty():
			popup.queue_free()
	,16)
	var update = func(index: int):
		if index<0 or index>=options.size():
			track_intent(cast,"spell_cast",false,"No authoritative cast options recorded.")
			cast_note.text = "No authoritative cast options recorded."
			return
		var opt = options[index]
		track_intent(cast,"spell_cast",opt["available"],str(opt["warning"]))
		cast_note.text = str(opt["warning"]) if not str(opt["warning"]).is_empty() else "Target unselected; controller may request explicit targeting."
	cast_choices.item_selected.connect(update)
	if options.is_empty():
		cast_choices.add_item("Cast options unavailable")
		cast_choices.disabled = true
		update.call(-1)
	else:
		var first = 0
		for i in range(options.size()):
			if options[i]["available"]:
				first = i
				break
		cast_choices.select(first)
		update.call(first)
	popup_status(col)
	popup.popup_centered(Vector2i(680,470))

func build_skills() -> void:
	var list = list_for_tab("Skills & Saving Throws")
	var skill_ids = actor.get("skills",{}).keys()
	skill_ids.sort()
	for raw_id in skill_ids:
		var id = str(raw_id)
		var skill = actor.get("skills",{}).get(id,{})
		if skill.is_empty():
			continue
		var marker = "✦ " if skill.get("expertise",false) else ("◆ " if skill.get("proficient",false) else "◇ ")
		button(list,marker+title_for("skills",id)+"   "+number(skill.get("modifier"),true),func(): show_check("skill_check",id),15)
	for key in ABILITIES:
		var marker = "◆ " if "saving-throw-"+key in actor.get("proficiency_ids",[]) else "◇ "
		var ability = key
		button(list,marker+key.to_upper()+" Save  "+number(actor.get("saving_throws",{}).get(key),true),func(): show_check("saving_throw",ability),15)
	label(list,"✦ Expertise · ◆ Proficient · ◇ Not proficient",13,GOLD)
	label(list,"Ability checks",17,GOLD)
	for key in ABILITIES:
		var ability = key
		button(list,key.to_upper()+"  "+number(actor.get("ability_modifiers",{}).get(key),true),func(): show_check("ability_check",ability),15)

func show_check(kind: String,id: String) -> void:
	var caption = title_for("skills",id) if kind=="skill_check" else id.to_upper()+(" saving throw" if kind=="saving_throw" else " ability check")
	var popup = popup_base(caption)
	var col = vbox(popup,6)
	col.custom_minimum_size.x = 480
	if kind=="skill_check":
		label(col,cat.describe("skills",id),15)
		label(col,"Recorded modifier: "+number(actor.get("skills",{}).get(id,{}).get("modifier"),true),16,GOLD)
	else:
		var data = actor.get("saving_throws",{}) if kind=="saving_throw" else actor.get("ability_modifiers",{})
		label(col,"Recorded modifier: "+number(data.get(id),true),16,GOLD)
	label(col,"Submit a check intention. The controller determines whether a roll is called for, the circumstances, DC and outcome. No local mechanical roll.",15)
	var args = {"skill_id":id} if kind=="skill_check" else {"ability":id}
	intent_button(col,"Request "+("saving throw" if kind=="saving_throw" else "check"),kind,args)
	popup_status(col)
	popup.popup_centered(Vector2i(520,300))

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
		var resource_id = str(key)
		button(list,resource_id.replace("_"," ").capitalize()+": "+DISPLAY.remaining_text(resource.get("max"),resource.get("spent")),func(): show_resource(resource_id),16)
	for id in actor.get("combat",{}).get("conditions",[]):
		reference_row(list,"conditions",str(id))
	button(list,"Rest & advancement",show_character_actions,16)

func show_resource(id: String) -> void:
	var resource = actor.get("resources",{}).get(id,{})
	if resource.is_empty():
		return
	var popup = popup_base(id.replace("_"," ").capitalize())
	var col = vbox(popup,5)
	col.custom_minimum_size.x = 430
	label(col,"Remaining: "+DISPLAY.remaining_text(resource.get("max"),resource.get("spent")),19,GOLD)
	var maximum = resource.get("max")
	var spent = resource.get("spent")
	var known = DISPLAY.nonnegative_integer(maximum) and DISPLAY.nonnegative_integer(spent) and float(spent)<=float(maximum)
	var remaining = int(maximum)-int(spent) if known else 0
	var quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = maxi(1,remaining)
	quantity.value = 1
	col.add_child(quantity)
	var target: OptionButton
	if is_instance_valid(development_controller):
		target=target_picker(col)
	var use = button(col,"Request resource use",func():
		if is_instance_valid(development_controller):
			var chosen=selected_target(target)
			if chosen==null:
				show_status("Choose self explicitly.")
				return
			dev_submit("resource_use",{"resource_id":id,"quantity":int(quantity.value),"target_id":chosen},"2")
		else:
			request_intent("resource_use",{"resource_id":id,"quantity":int(quantity.value)})
	,16)
	track_intent(use,"resource_use",known and remaining>0 and (not is_instance_valid(development_controller) or id in ["second_wind","lay_on_hands"]),"No available supported resource quantity established.")
	label(col,"No manual counter adjustment; effects, timing and costs require resolution.",14,GOLD)
	popup_status(col)
	popup.popup_centered(Vector2i(470,250))

func show_character_actions() -> void:
	var popup = popup_base("Character actions")
	var col = vbox(popup,5)
	col.custom_minimum_size.x = 460
	label(col,"Rest, recovery and advancement",19,GOLD)
	if is_instance_valid(development_controller):
		button(col,"Short rest · choose hit dice",func(): popup.queue_free(); show_rest("short"))
		button(col,"Long rest · choose preparation",func(): popup.queue_free(); show_rest("long"))
	else:
		intent_button(col,"Request short rest","rest",{"rest_kind":"short"})
		intent_button(col,"Request long rest","rest",{"rest_kind":"long"})
	intent_button(col,"Review level-up eligibility","level_up",{})
	label(col,"The controller validates time, safety, resources, class features and advancement. No manual HP, spell slot, XP or coin changes.",15)
	popup_status(col)
	popup.popup_centered(Vector2i(500,300))

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
	var popup = popup_base("Campaign Character")
	var col = vbox(popup,3)
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1000,495)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(sc)
	var sheet = SHEET.new()
	sheet.configure(actor,func(caption: String,detail: String): popup_text(caption,detail),true)
	sheet.custom_minimum_size.x = 960
	sc.add_child(sheet)
	button(col,"Rest & advancement",func(): popup.queue_free(); show_character_actions())
	popup.popup_centered(Vector2i(1040,610))

func show_quests() -> void:
	var popup = popup_base("Quest Log")
	var col = vbox(popup,5)
	col.custom_minimum_size = Vector2(630,0)
	var rows: Array = []
	if is_instance_valid(development_controller):
		rows=extension().get("public_quests",[])
		label(col,"Disclosed campaign quests",19,GOLD)
	elif not intents.interaction.is_empty():
		rows = intents.interaction["public_quests"]
		label(col,"Disclosed campaign quests",19,GOLD)
	else:
		# The old gameplay_view includes raw quest payloads without a disclosure
		# proof. Do not render them. B4 already offers verified local public rows.
		var public_view = WORLD.new().public_context(str(campaign.get("id","")),[])
		if public_view.get("ok",false) and public_view.get("campaign_id")==campaign.get("id"):
			rows = public_view.get("local_quests",[])
			label(col,"Disclosed local quests · legacy read model (bounded current location)",17,GOLD)
		else:
			label(col,"Public quest projection unavailable. No private quest data displayed.",16,GOLD)
	var row_box = hbox(col,5)
	row_box.custom_minimum_size.y = 260
	var list = ItemList.new()
	list.custom_minimum_size.x = 250
	row_box.add_child(list)
	var detail = TextEdit.new()
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(detail)
	var selection = {"id":""}
	var pursue = button(col,"Discuss / pursue selected quest",func():
		request_intent("quest_interact",{"quest_id":selection["id"]})
		if not intents.outstanding_id.is_empty():
			popup.queue_free()
	)
	track_intent(pursue,"quest_interact",false,"Select a disclosed quest.")
	var choose = func(index: int):
		var quest = rows[index]
		selection["id"] = str(quest["id"])
		detail.text = str(quest["title"])+"\n"+str(quest["status"]).capitalize()+"\n\n"+str(quest.get("description",""))+"\n\nSource event: "+number(quest.get("source_event_id"))
		track_intent(pursue,"quest_interact",not intents.interaction.is_empty(),"A current authoritative campaign quest view is required.")
	for quest in rows:
		list.add_item(str(quest["title"])+" · "+str(quest["status"]))
	list.item_selected.connect(choose)
	if rows.is_empty():
		detail.text = "No disclosed quests in the available projection."
	else:
		list.select(0)
		choose.call(0)
	if is_instance_valid(development_controller):
		button(col,"Selected quest history",func(): show_story_history(selection["id"]))
	label(col,"Quest intentions never mark a quest complete or invent a reward.",14,GOLD)
	popup_status(col)
	popup.popup_centered(Vector2i(670,430))

func map_intention(packet: Dictionary) -> Dictionary:
	var revision=int(extension().get("revision",intents.revision)) if is_instance_valid(development_controller) else intents.revision
	if not INTENTS.exact_keys(packet,["kind","campaign_id","expected_revision","destination_id"]) or packet.get("kind")!="travel_intention" or packet.get("campaign_id")!=intents.campaign_id or packet.get("expected_revision")!=revision:
		return {"ok":false,"message":"Map and campaign revisions differ. Refresh the authoritative workspace before travel."}
	if is_instance_valid(development_controller):
		for child in get_children():
			if child is Window and child.has_method("request_travel"):
				child.queue_free()
		show_travel.call_deferred(packet["destination_id"],revision)
		return {"ok":false,"locked":false,"message":"Choose a known route and pace; no movement submitted."}
	var result = request_intent("travel",{"destination_id":packet["destination_id"]})
	result["locked"] = not intents.outstanding_id.is_empty()
	return result

func show_map() -> void:
	var popup = MAP_WINDOW.new()
	# No live controller is passed by main. C4 must explicitly bind it.
	var handler = Callable(self,"map_intention") if can_intent("travel") else Callable()
	popup.configure(str(campaign.get("id","")),str(campaign.get("title","Campaign")),handler,int(extension().get("revision",intents.revision)) if is_instance_valid(development_controller) else intents.revision)
	add_child(popup)
	var extent = get_viewport().get_visible_rect().size
	popup.popup_centered(Vector2i(maxf(940,extent.x-36),maxf(610,extent.y-36)))

# C4 development-only interface. No production caller binds this Node.
func bind_development_controller(controller: Node) -> void:
	development_controller=controller

func extension() -> Dictionary:
	return view.get("interaction_extension",{})

func can_choice(kind: String) -> bool:
	return is_instance_valid(development_controller) and extension().get("phase")=="idle" and kind in extension().get("choice_tools",[]) and local_pending_id.is_empty()

func dev_submit(kind: String,args: Dictionary,version: String="2") -> Dictionary:
	if not is_instance_valid(development_controller) or not local_pending_id.is_empty() or (version=="2" and not can_choice(kind)):
		return {"ok":false,"message":"Controller or choice unavailable."}
	var rid=Crypto.new().generate_random_bytes(16).hex_encode()
	var packet={"schema_version":version,"campaign_id":campaign["id"],"actor_id":actor["id"],"expected_revision":extension().get("revision"),"request_id":rid,"kind":kind,"args":args.duplicate(true)}
	local_pending_id=rid
	local_pending_text=str(args.get("text",""))
	var reply=development_controller.submit(packet)
	if not reply is Dictionary or reply.get("request_id")!=rid or not reply.get("ok") is bool:
		show_status("Delivery unconfirmed. Recover in Turn / Retry.")
		return {"ok":false,"message":"Delivery unconfirmed."}
	if not reply["ok"]:
		local_pending_id=""
		local_pending_text=""
	show_status(reply["message"])
	refresh_intent_controls()
	return reply

func target_picker(parent: Node) -> OptionButton:
	label(parent,"Target",15,GOLD)
	var target=OptionButton.new()
	target.add_item("Choose target…")
	target.set_item_metadata(0,null)
	target.add_item(str(actor.get("name","Character"))+" (self)")
	target.set_item_metadata(1,actor["id"])
	for individual in extension().get("public_actors",[]):
		target.add_item(str(individual["name"])+" — other-target effects unsupported")
		target.set_item_disabled(target.item_count-1,true)
	target.select(0)
	parent.add_child(target)
	return target

func selected_target(target: OptionButton) -> Variant:
	return target.get_item_metadata(target.selected) if is_instance_valid(target) and target.selected>=0 else null

func show_processing() -> void:
	var popup=popup_base("Turn and processing")
	var col=vbox(popup,6)
	col.custom_minimum_size.x=530
	label(col,str(extension().get("status_text","Controller ready.")),18,GOLD)
	label(col,"Committed effects remain saved. Pending prose and deferred work are separate.",15)
	var queued=str(extension().get("queued_text",""))
	if not queued.is_empty():
		label(col,"Saved next action: "+queued,16,GOLD)
		var resume=button(col,"Resume queued action when settled",func():
			var result=development_controller.resume_queue()
			if not result.get("ok",false): show_status(str(result.get("error","Queue unavailable.")))
			popup.queue_free()
		)
		resume.disabled=not extension().get("queue_wait",false)
		button(col,"Return queued text to draft",func():
			var result=development_controller.discard_queue()
			if result.get("ok",false):
				composer.text=queued
			popup.queue_free()
		)
	var last=extension().get("last_terminal",{})
	if last.get("status") in ["rejected","cancelled"] and not str(last.get("text","")).is_empty():
		button(col,"Restore last unresolved text",func(): composer.text=last["text"]; popup.queue_free())
	button(col,"Retry / recover current request",func():
		if not local_pending_id.is_empty():
			var found=development_controller.request_status(local_pending_id)
			if found.get("ok",false):
				local_pending_id=""
				local_pending_text=""
				development_controller.refresh()
		else:
			var result=development_controller.retry()
			if not result.get("ok",false):
				show_status(str(result.get("error","Retry unavailable.")))
		popup.queue_free()
	)
	button(col,"Cancel uncommitted request",func():
		var result=development_controller.cancel()
		if not result.get("ok",false): show_status(str(result.get("error","Cancellation unavailable.")))
		popup.queue_free()
	)
	button(col,"Skip optional deferred story proposals",func():
		var result=development_controller.skip_deferred()
		if not result.get("ok",false): show_status(str(result.get("error","No optional work available.")))
		popup.queue_free()
	)
	if development_controller.has_method("settle_verified_only"):
		button(col,"Continue with verified outcome only",func():
			var result=development_controller.settle_verified_only()
			if not result.get("ok",false): show_status(str(result.get("error","Recovery unavailable.")))
			popup.queue_free())
	popup.popup_centered(Vector2i(580,460))

func show_world_menu() -> void:
	var popup=popup_base("Campaign records")
	var col=vbox(popup,6)
	col.custom_minimum_size.x=400
	button(col,"NPCs and enemies",func(): popup.queue_free(); show_public_actors())
	button(col,"Available loot",func(): popup.queue_free(); show_loot())
	button(col,"Campaign overview and persistent factors",func(): popup.queue_free(); show_overview())
	if not extension().get("equipment_review",[]).is_empty():
		button(col,"Review legacy equipment assignments",func(): popup.queue_free(); show_legacy_review())
	button(col,"Quest journal",func(): popup.queue_free(); show_quests())
	popup.popup_centered(Vector2i(460,330))

func show_public_actors() -> void:
	var popup=popup_base("Disclosed NPCs and enemies")
	var col=vbox(popup,5)
	col.custom_minimum_size.x=590
	var list=vbox(scroll(col,270),4)
	for individual in extension().get("public_actors",[]):
		var row=individual
		button(list,str(row["name"])+" · "+str(row["kind"]).capitalize()+" · "+str(row["occupation"]),func():
			var response=development_controller.enquiry("actor_sheet",{"actor_id":row["actor_id"]})
			if not response.get("ok",false):
				popup_text("Sheet unavailable",str(response.get("error","Not disclosed.")))
				return
			var actors=response.get("data",{}).get("actors",[])
			if actors.size()!=1:
				popup_text("Sheet unavailable","No disclosed sheet.")
				return
			var sheet=actors[0]
			popup_text(str(sheet.get("name","Actor")),str(sheet.get("occupation",""))+"\n"+("Disclosed sheet:\n"+readable(sheet["sheet"]) if sheet.get("sheet") is Dictionary else "Descriptive identity only; mechanics not disclosed."))
		,16)
	if extension().get("public_actors",[]).is_empty():
		label(list,"No disclosed local actors in this projection.")
	popup.popup_centered(Vector2i(630,360))

func show_loot() -> void:
	var popup=popup_base("Available loot")
	var col=vbox(popup,5)
	col.custom_minimum_size.x=520
	var list=vbox(scroll(col,240),4)
	for container in extension().get("loot_containers",[]):
		var row=container
		button(list,str(row["name"])+" · "+str(row["source_kind"])+" · "+str(row["items"].size())+" item stacks",func(): popup.queue_free(); show_loot_container(row))
	if extension().get("loot_containers",[]).is_empty():
		label(list,"No disclosed eligible loot at the current location.")
	popup.popup_centered(Vector2i(560,320))

func show_loot_container(container: Dictionary) -> void:
	var popup=popup_base(str(container["name"]))
	var col=vbox(popup,5)
	col.custom_minimum_size.x=580
	label(col,"Source: "+str(container["source_kind"])+" · event "+number(container["source_event_id"]),15,GOLD)
	var list=vbox(scroll(col,260),4)
	var selected: Array=[]
	for item in container["items"]:
		var row=hbox(list,5)
		label(row,item_name(item)+" · available "+number(item["quantity"]),16)
		var amount=SpinBox.new()
		amount.min_value=0
		amount.max_value=int(item["quantity"])
		amount.step=1
		row.add_child(amount)
		selected.append({"instance_id":item["instance_id"],"control":amount})
	var money: Dictionary={}
	for denom in ["cp","sp","ep","gp","pp"]:
		var row=hbox(list,4)
		label(row,denom.to_upper()+" · available "+number(container["coins"].get(denom)),15)
		var amount=SpinBox.new()
		amount.min_value=0
		amount.max_value=int(container["coins"].get(denom,0))
		amount.step=1
		row.add_child(amount)
		money[denom]=amount
	var actions=hbox(col,4)
	var take=button(actions,"Pick up selected",func():
		var picks: Array=[]
		var coins: Dictionary={}
		for entry in selected:
			if entry["control"].value>0:
				picks.append({"instance_id":entry["instance_id"],"quantity":int(entry["control"].value)})
		for denom in money:
			coins[denom]=int(money[denom].value)
		dev_submit("loot_pickup",{"container_id":container["container_id"],"source_event_id":container["source_event_id"],"items":picks,"coins":coins})
	)
	take.disabled=not can_choice("loot_pickup")
	var all=button(actions,"Take all",func(): dev_submit("loot_take_all",{"container_id":container["container_id"],"source_event_id":container["source_event_id"]}))
	all.disabled=not can_choice("loot_take_all")
	label(col,"Transfers are atomic; capacity and eligibility are checked by C3.",14,GOLD)
	popup.popup_centered(Vector2i(620,430))

func show_overview() -> void:
	var result=development_controller.enquiry("overview",{})
	if not result.get("ok",false):
		popup_text("Campaign overview unavailable",str(result.get("error","Refresh required.")))
		return
	var overview=result["data"]
	var popup=popup_base("Campaign overview")
	var col=vbox(popup,5)
	col.custom_minimum_size.x=660
	label(col,str(overview.get("title","Campaign"))+" · "+str(overview.get("current_location","Unknown")),20,GOLD)
	var list=vbox(scroll(col,380),6)
	for record in overview.get("overview",[]):
		label(list,str(record["title"]),18,GOLD)
		label(list,str(record["description"]),16)
	label(list,"Persistent story factors",18,GOLD)
	for record in overview.get("persistent_factors",[]):
		var selected=record
		button(list,str(record["kind"]).capitalize()+" · "+str(record["title"])+" · "+str(record["status"]),func(): show_story_history(selected["id"]))
	label(list,"Recent committed events",18,GOLD)
	for event in overview.get("recent_events",[]):
		label(list,str(event.get("text","")),15)
	popup.popup_centered(Vector2i(700,500))

func show_story_history(id: String) -> void:
	if id.is_empty():
		return
	var result=development_controller.enquiry("story_history",{"record_id":id})
	if not result.get("ok",false):
		popup_text("History unavailable",str(result.get("error","Not disclosed.")))
		return
	var lines: PackedStringArray=[]
	for record in result["data"].get("history",[]):
		lines.append("Event "+number(record["event_id"])+" · "+str(record["status"])+"\n"+str(record.get("title",""))+"\n"+str(record.get("description","")))
	if result["data"].get("truncated",false):
		lines.append("Older entries outside this bounded view.")
	popup_text("Persistent history","\n\n".join(lines) if not lines.is_empty() else "No disclosed history recorded.")

func preparation_choices(parent: Node,forced_kind: String="",spell_id: String="") -> Array:
	var choices: Array=[]
	var role=str(actor.get("class_id",""))
	var sp=actor.get("spellcasting",{})
	if not role in ["cleric","druid","wizard"]:
		return choices
	var list=vbox(scroll(parent,230),3)
	for spell in cat.rows("spells"):
		var id=str(spell.get("index",""))
		var level=spell.get("level")
		if not INTENTS.integer(level,1,9) or not role in cat.references(spell.get("classes",[])) or int(sp.get("slots",{}).get(str(int(level)),{}).get("maximum",0))<1 or id in sp.get("always_prepared_ids",[]) or (role=="wizard" and not id in sp.get("known_ids",[])):
			continue
		var check=CheckBox.new()
		check.text=title_for("spells",id)+" · level "+str(int(level))
		check.button_pressed=id in sp.get("prepared_ids",[])
		if id==spell_id and not forced_kind.is_empty():
			check.button_pressed=forced_kind=="spell_prepare"
			check.disabled=true
		list.add_child(check)
		choices.append({"id":id,"control":check})
	return choices

func selected_preparation(choices: Array) -> Array:
	var result: Array=[]
	for row in choices:
		if row["control"].button_pressed:
			result.append(row["id"])
	return result

func show_preparation(kind: String,id: String) -> void:
	var popup=popup_base("Complete prepared spell list")
	var col=vbox(popup,4)
	col.custom_minimum_size.x=490
	label(col,"Choose all prepared spells. Requires verified immediate long-rest window.",15,GOLD)
	var choices=preparation_choices(col,kind,id)
	var confirm=button(col,"Submit complete list",func(): dev_submit(kind,{"spell_id":id,"prepared_ids":selected_preparation(choices)}))
	confirm.disabled=choices.is_empty() or not can_choice(kind)
	popup.popup_centered(Vector2i(530,400))

func show_rest(kind: String) -> void:
	var popup=popup_base(kind.capitalize()+" rest")
	var col=vbox(popup,5)
	col.custom_minimum_size.x=490
	var combat=actor.get("combat",{})
	var dice=SpinBox.new()
	dice.min_value=0
	dice.max_value=clampi(int(combat.get("hit_dice_total",0))-int(combat.get("hit_dice_spent",0)),0,1) if kind=="short" else 0
	dice.step=1
	label(col,"Hit dice to spend (supported level-one slice)",15,GOLD)
	col.add_child(dice)
	var prepare=CheckBox.new()
	prepare.text="Choose a new complete prepared list"
	var choices: Array=[]
	col.add_child(prepare)
	prepare.visible=kind=="long" and actor.get("class_id") in ["cleric","druid","wizard"]
	if prepare.visible:
		choices=preparation_choices(col)
	var confirm=button(col,"Submit rest intention",func(): dev_submit("rest",{"rest_kind":kind,"hit_dice":int(dice.value),"prepared_ids":selected_preparation(choices) if prepare.button_pressed else null}))
	confirm.disabled=not can_choice("rest")
	label(col,"Safety, supplies, elapsed time and eligibility require trusted review.",14,GOLD)
	popup.popup_centered(Vector2i(530,410 if not choices.is_empty() else 250))

func show_travel(destination: String,revision: int) -> void:
	if revision!=extension().get("revision"):
		show_status("Map selection stale.")
		return
	var result=development_controller.routes_to(destination,revision)
	if not result.get("ok",false) or result.get("routes",[]).is_empty():
		popup_text("Travel unavailable","No established visible route to this destination. No movement has occurred.")
		return
	var popup=popup_base("Choose travel route")
	var col=vbox(popup,6)
	col.custom_minimum_size.x=480
	var routes=OptionButton.new()
	for route in result["routes"]:
		routes.add_item(str(route["name"])+" · "+number(route.get("distance_miles"))+" miles")
		routes.set_item_metadata(routes.item_count-1,route["id"])
	routes.select(-1)
	col.add_child(routes)
	var pace=OptionButton.new()
	for name_value in ["slow","normal","fast"]:
		pace.add_item(name_value.capitalize())
		pace.set_item_metadata(pace.item_count-1,name_value)
	pace.select(-1)
	col.add_child(pace)
	var fast=CheckBox.new()
	fast.text="Fast travel (requires prior actual traversal)"
	col.add_child(fast)
	var go=button(col,"Submit route intention",func():
		if routes.selected<0 or pace.selected<0:
			show_status("Choose route and pace explicitly.")
			return
		dev_submit("travel",{"route_id":routes.get_item_metadata(routes.selected),"destination_id":destination,"pace":pace.get_item_metadata(pace.selected),"fast_travel":fast.button_pressed,"text":"Travel to the selected destination."})
	)
	go.disabled=not can_choice("travel")
	popup.popup_centered(Vector2i(520,300))

func show_legacy_review() -> void:
	var popup=popup_base("Review existing equipment assignments")
	var col=vbox(popup,5)
	col.custom_minimum_size.x=580
	label(col,"Choose the recorded hand/slot for each already-equipped item. This is not new equipment.",15,GOLD)
	var choices: Array=[]
	for review in extension().get("equipment_review",[]):
		var item=display_item(review["instance_id"])
		label(col,item_name(item)+" · "+str(review.get("reason","")),15)
		var picker=OptionButton.new()
		for opt in item.get("equip_options",[]):
			if opt["slot"] in ["body","shield","main_hand","off_hand"]:
				picker.add_item(str(opt["slot"])+" / "+str(opt["grip"]))
				picker.set_item_metadata(picker.item_count-1,{"instance_id":item["instance_id"],"slot":opt["slot"],"grip":opt["grip"]})
		picker.select(-1)
		col.add_child(picker)
		choices.append(picker)
	var confirm=button(col,"Reconcile all existing assignments",func():
		var rows: Array=[]
		for picker in choices:
			if picker.selected<0:
				show_status("Choose every unresolved assignment.")
				return
			rows.append(picker.get_item_metadata(picker.selected))
		dev_submit("reconcile_legacy_slots",{"assignments":rows})
	)
	confirm.disabled=not can_choice("reconcile_legacy_slots") or choices.is_empty()
	popup.popup_centered(Vector2i(630,390))
