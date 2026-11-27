extends Button
## Shared text-only menu control. Native focus/activation retained.
const FLOURISH = preload("res://themes/gold_flourish.svg")
var flourish: TextureRect
var glow_text: Label

func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(400, 52)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 32)
	flourish = TextureRect.new()
	flourish.texture = FLOURISH
	flourish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flourish.stretch_mode = TextureRect.STRETCH_SCALE
	flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flourish)
	glow_text = Label.new()
	glow_text.text = text
	glow_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glow_text.add_theme_font_size_override("font_size", 32)
	glow_text.add_theme_color_override("font_color", Color(1.0, 0.96, 0.80))
	glow_text.add_theme_color_override("font_shadow_color", Color(1.0, 0.56, 0.12, 0.48))
	glow_text.add_theme_constant_override("shadow_offset_x", 0)
	glow_text.add_theme_constant_override("shadow_offset_y", 0)
	glow_text.add_theme_constant_override("shadow_outline_size", 7)
	add_child(glow_text)
	glow_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_entered.connect(refresh_glow)
	mouse_exited.connect(refresh_glow)
	focus_entered.connect(refresh_glow)
	focus_exited.connect(refresh_glow)
	resized.connect(layout_flourish)
	layout_flourish()
	refresh_glow()

func layout_flourish() -> void:
	var text_width = get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	flourish.position = Vector2(-16, size.y - 19)
	flourish.size = Vector2(minf(size.x + 16, text_width + 32), 26)

func refresh_glow() -> void:
	var lit = not disabled and (is_hovered() or has_focus())
	flourish.visible = lit
	glow_text.visible = lit
	if lit:
		add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	else:
		remove_theme_color_override("font_hover_color")
		remove_theme_color_override("font_focus_color")
		remove_theme_color_override("font_outline_color")
