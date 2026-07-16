extends PanelContainer
## Reusable library tile; action buttons are intentionally supplied by the caller.

const TOKENS := preload("res://ui/theme/design_tokens.gd")
var body: VBoxContainer

func configure(title_text: String, subtitle: String, metadata: String, accent: Color = TOKENS.ACCENT) -> VBoxContainer:
	add_theme_stylebox_override("panel", TOKENS.panel_style(TOKENS.SURFACE, accent))
	custom_minimum_size = Vector2(0, 190)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var title := Label.new()
	title.text = title_text
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", TOKENS.TEXT)
	body.add_child(title)
	var artist := Label.new()
	artist.text = subtitle
	artist.add_theme_font_size_override("font_size", 16)
	artist.add_theme_color_override("font_color", accent)
	body.add_child(artist)
	var meta := Label.new()
	meta.text = metadata
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override("font_size", 14)
	meta.add_theme_color_override("font_color", TOKENS.MUTED)
	body.add_child(meta)
	return body
