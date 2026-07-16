class_name DesignTokens
extends RefCounted
## Shared POP UI tokens. Keep gameplay readability above decoration.

const BACKGROUND := Color("#080d1d")
const SURFACE := Color("#111a31")
const SURFACE_RAISED := Color("#182642")
const SURFACE_HOVER := Color("#213456")
const TEXT := Color("#edf5ff")
const MUTED := Color("#9eb1d0")
const ACCENT := Color("#62dfff")
const ACCENT_ALT := Color("#c98cff")
const SUCCESS := Color("#65e2a4")
const WARNING := Color("#ffd166")
const DANGER := Color("#ff6688")
const DUO_LEFT := Color("#55d8ff")
const DUO_RIGHT := Color("#c783ff")

static func button_style(background: Color, border: Color, width: float = 2.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(int(width))
	style.set_corner_radius_all(14)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style

static func panel_style(background: Color = SURFACE, border: Color = Color("#2b456d")) -> StyleBoxFlat:
	var style := button_style(background, border, 1.0)
	style.set_corner_radius_all(18)
	return style
