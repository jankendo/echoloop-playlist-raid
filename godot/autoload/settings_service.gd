extends Node
## Validated defaults exposed to UI and gameplay.

const DEFAULTS: Dictionary = {
	"schema_version": 1,
	"master_volume": 0.80,
	"music_volume": 0.75,
	"sfx_volume": 0.70,
	"echo_volume": 0.35,
	"note_speed": 1.0,
	"background_dim": 0.72,
	"screen_shake": 0.25,
	"flash_reduction": true,
	"judgement_assist_ms": 0,
	"audio_offset_ms": 0.0,
	"visual_offset_ms": 0.0,
	"lane_keys": [KEY_D, KEY_F, KEY_J, KEY_K],
	"window_mode": "windowed",
	"ui_scale": 1.0,
}

var values: Dictionary = DEFAULTS.duplicate(true)

func _ready() -> void:
	load_values()

func load_values() -> void:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		values = save_service.load_settings(DEFAULTS)
	else:
		values = DEFAULTS.duplicate(true)
	_apply_display_mode()

func save_values() -> bool:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		return save_service.save_settings(values)
	return false

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = value
	if key == "window_mode":
		_apply_display_mode()

func get_value(key: String, fallback: Variant = null) -> Variant:
	return values.get(key, fallback)

func _apply_display_mode() -> void:
	var mode: String = str(values.get("window_mode", "windowed"))
	if mode == "borderless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
