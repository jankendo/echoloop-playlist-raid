extends Control
## First-run DUO tutorial; it never touches the chart or score.

signal accepted
signal skipped

const TOKENS := preload("res://ui/theme/design_tokens.gd")
const BUTTON_SCRIPT := preload("res://ui/components/primary_button.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.10, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	panel.add_theme_stylebox_override("panel", TOKENS.panel_style(TOKENS.SURFACE_RAISED, TOKENS.ACCENT))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title := Label.new()
	title.text = "DUO MODE / QUICK TUTORIAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", TOKENS.ACCENT)
	column.add_child(title)
	var body := Label.new()
	body.text = "F  LEFT         J  RIGHT\n\nF+J を同時に押すと CHORD。\nEscでPAUSE、R長押しでQUICK RETRY。\n音楽の意味は色とアイコン、入力位置はF/Jで示します。"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", TOKENS.TEXT)
	column.add_child(body)
	_add_button(column, "START TUTORIAL", "この説明を閉じてゲームを始める", func() -> void: accepted.emit(), true)
	_add_button(column, "SKIP", "説明を閉じてすぐにゲームを始める", func() -> void: skipped.emit())
	hide()

func show_tutorial() -> void:
	show()
	var button := get_node_or_null("CenterContainer/PanelContainer/VBoxContainer/StartTutorial") as Button
	if button != null:
		button.grab_focus()

func _add_button(parent: VBoxContainer, label_text: String, hint: String, action: Callable, primary: bool = false) -> void:
	var button: Button = BUTTON_SCRIPT.new()
	button.name = label_text.replace(" ", "")
	button.configure(label_text, hint, action, primary)
	parent.add_child(button)
