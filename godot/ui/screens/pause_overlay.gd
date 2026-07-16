extends Control
## Pause overlay with explicit lifecycle actions and a safe return confirmation.

signal resumed
signal restarted
signal song_selected
signal returned_to_title
signal settings_requested

const TOKENS := preload("res://ui/theme/design_tokens.gd")
const BUTTON_SCRIPT := preload("res://ui/components/primary_button.gd")

var summary_label: Label
var _confirm: ConfirmationDialog

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.10, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", TOKENS.panel_style(TOKENS.SURFACE_RAISED, TOKENS.ACCENT_ALT))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TOKENS.ACCENT)
	column.add_child(title)
	summary_label = Label.new()
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_font_size_override("font_size", 17)
	summary_label.add_theme_color_override("font_color", TOKENS.TEXT)
	column.add_child(summary_label)
	_add_button(column, "RESUME", "Escでゲームへ戻る", func() -> void: resumed.emit(), true)
	_add_button(column, "RESTART SONG", "現在の曲を先頭から再開", func() -> void: restarted.emit())
	_add_button(column, "SONG SELECT", "曲選択へ戻る。現在のプレイは保存しません", func() -> void: song_selected.emit())
	_add_button(column, "RETURN TO TITLE", "タイトルへ戻る。現在のプレイは保存しません", _ask_return_to_title)
	_add_button(column, "SETTINGS", "設定画面を開く", func() -> void: settings_requested.emit())
	var help := Label.new()
	help.text = "Esc: Resume   R長押し: Quick Retry   F/J: DUO input"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", TOKENS.MUTED)
	column.add_child(help)
	hide()

func show_snapshot(title_text: String, artist: String, time_text: String, score: int, combo: int) -> void:
	summary_label.text = "%s\n%s\n%s\nSCORE %07d   COMBO %03d" % [title_text, artist, time_text, score, combo]
	show()
	var resume := find_child("Resume", true, false) as Button
	if resume != null:
		resume.grab_focus()

func _add_button(parent: VBoxContainer, label_text: String, hint: String, action: Callable, primary: bool = false) -> void:
	var button: Button = BUTTON_SCRIPT.new()
	button.name = label_text.replace(" ", "")
	button.configure(label_text, hint, action, primary)
	parent.add_child(button)

func _ask_return_to_title() -> void:
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.title = "RETURN TO TITLE"
		_confirm.dialog_text = "現在のプレイ結果は保存されません。\nSongPackと設定は保持されます。タイトルへ戻りますか？"
		_confirm.ok_button_text = "RETURN TO TITLE"
		_confirm.cancel_button_text = "CANCEL"
		_confirm.confirmed.connect(func() -> void: returned_to_title.emit())
		add_child(_confirm)
	_confirm.popup_centered()
	_confirm.get_cancel_button().grab_focus()
