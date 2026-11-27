extends VBoxContainer
const ICONS = preload("res://themes/parts/icons.png")
const FRAME = preload("res://themes/parts/frame.png")
const CORNER = preload("res://themes/parts/corner.png")
const RULES = preload("res://rules/mechanics.gd")
var rects: Dictionary = {}

func _ready() -> void:
	rects = JSON.parse_string(FileAccess.get_file_as_string("res://themes/parts/icons.json"))
	display({})

func label_text(value: String, size_px: int = 19) -> Label:
	var l = Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size",size_px)
	return l

func icon_named(key: String) -> TextureRect:
	var icon = TextureRect.new()
	if rects.has(key):
		var r = rects[key]
		var atlas = AtlasTexture.new()
		atlas.atlas = ICONS
		atlas.region = Rect2(r[0],r[1],r[2],r[3])
		icon.texture = atlas
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28,28)
	return icon

func panel(parent: Container, title_text: String, icon_key: String = "") -> VBoxContainer:
	var backing = PanelContainer.new()
	backing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dark = StyleBoxFlat.new()
	dark.bg_color = Color(0.025,0.05,0.09,0.94)
	backing.add_theme_stylebox_override("panel", dark)
	parent.add_child(backing)
	var frame = PanelContainer.new()
	var style = StyleBoxTexture.new()
	style.texture = FRAME
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(edge, 20)
		style.set_content_margin(edge, 12)
	frame.add_theme_stylebox_override("panel",style)
	backing.add_child(frame)
	var v = VBoxContainer.new()
	frame.add_child(v)
	var row = HBoxContainer.new()
	v.add_child(row)
	if not icon_key.is_empty():
		row.add_child(icon_named(icon_key))
	row.add_child(label_text(title_text,22))
	return v

func display(data: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var title_row = HBoxContainer.new()
	add_child(title_row)
	var ornament = TextureRect.new()
	ornament.texture = CORNER
	ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ornament.custom_minimum_size = Vector2(44,44)
	title_row.add_child(ornament)
	title_row.add_child(label_text("Character Sheet — Draft",30))
	add_child(label_text("%s    %s    %s    Level 1" % [data.get("name","Unnamed"),data.get("race","—"),data.get("class","—")]))
	var stats = HBoxContainer.new()
	add_child(stats)
	for record in [["Armor Class","armor","unarmored_ac"],["Hit Points","health","hp"],["Initiative","initiative","initiative"],["Speed","speed","speed"]]:
		var p = panel(stats,record[0],record[1])
		p.add_child(label_text(str(data.get(record[2],"—")),26))
	var columns = HBoxContainer.new()
	add_child(columns)
	var abilities = panel(columns,"Ability Scores")
	var saves = panel(columns,"Saving Throws")
	for key in RULES.ABILITIES:
		abilities.add_child(label_text("%s    %s    %s" % [key,data.get("scores",{}).get(key,"—"),data.get("modifiers",{}).get(key,"—")]))
		saves.add_child(label_text("%s    %s" % [key,data.get("saves",{}).get(key,"—")]))
	var skills = panel(columns,"Skills","diamond")
	for key in RULES.SKILLS:
		skills.add_child(label_text(key + "    —",17))
	for entry in [["Attacks","initiative"],["Equipment","shield"],["Inventory","pack"],["Spells","wand"],["Features & Traits","star"]]:
		var p = panel(self,entry[0],entry[1])
		p.add_child(label_text("Pending choices",17))
	if data.has("roll_history"):
		var log_line = label_text("Dice: " + str(data["roll_history"]) if not data["roll_history"].is_empty() else "Standard array",17)
		log_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(log_line)
	add_child(label_text("Draft only: background, proficiencies, gear and spells not finalized.",17))
