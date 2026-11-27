extends Button
## All navigation uses the actual specimen-derived color bitmap font.
const FLOURISH = preload("res://themes/gold_flourish.svg")
var flourish: TextureRect

func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(300, 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 27)
	add_theme_constant_override("outline_size", 0)
	flourish = TextureRect.new()
	flourish.texture = FLOURISH
	flourish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flourish.stretch_mode = TextureRect.STRETCH_SCALE
	flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flourish)
	mouse_entered.connect(refresh_glow)
	mouse_exited.connect(refresh_glow)
	focus_entered.connect(refresh_glow)
	focus_exited.connect(refresh_glow)
	resized.connect(layout_flourish)
	layout_flourish()
	refresh_glow()

func layout_flourish() -> void:
	var text_width = get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
	flourish.position = Vector2(-16, size.y - 13)
	flourish.size = Vector2(minf(size.x + 16, text_width + 32), 20)

func refresh_glow() -> void:
	var lit = not disabled and (is_hovered() or has_focus())
	flourish.visible = lit
	self_modulate = Color(1.18, 1.13, 1.05, 1.0) if lit else Color.WHITE
