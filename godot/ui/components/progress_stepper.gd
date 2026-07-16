extends HBoxContainer
## Small, high-contrast import progress indicator.

const TOKENS := preload("res://ui/theme/design_tokens.gd")
var _steps: Array[Label] = []

func configure(labels: Array[String], current: int = 0) -> void:
	for child in get_children():
		child.queue_free()
	_steps.clear()
	add_theme_constant_override("separation", 10)
	for index in range(labels.size()):
		var label := Label.new()
		label.text = "%02d  %s" % [index + 1, labels[index]]
		label.add_theme_font_size_override("font_size", 15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_steps.append(label)
		add_child(label)
	set_current(current)

func set_current(current: int) -> void:
	for index in range(_steps.size()):
		_steps[index].add_theme_color_override("font_color", TOKENS.ACCENT if index == current else TOKENS.MUTED)
