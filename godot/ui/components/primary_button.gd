extends Button
## Accessible, keyboard-first POP button used by every non-gameplay screen.

const TOKENS := preload("res://ui/theme/design_tokens.gd")

func configure(label_text: String, hint: String, action: Callable, primary: bool = false) -> void:
	text = label_text
	tooltip_text = hint
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(0, 58)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 18)
	add_theme_color_override("font_color", TOKENS.TEXT)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_stylebox_override("normal", TOKENS.button_style(TOKENS.SURFACE_RAISED, TOKENS.ACCENT if primary else Color("#2b456d")))
	add_theme_stylebox_override("hover", TOKENS.button_style(TOKENS.SURFACE_HOVER, TOKENS.ACCENT))
	add_theme_stylebox_override("pressed", TOKENS.button_style(TOKENS.SURFACE, TOKENS.ACCENT_ALT))
	add_theme_stylebox_override("focus", TOKENS.button_style(TOKENS.SURFACE_HOVER, TOKENS.WARNING, 3.0))
	if action.is_valid():
		pressed.connect(action)
