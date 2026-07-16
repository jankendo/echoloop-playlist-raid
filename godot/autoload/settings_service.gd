extends Node
## Validated defaults exposed to UI and gameplay.

const DEFAULTS: Dictionary = {
	"schema_version": 2,
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
	"gameplay_mode": "duo_2key",
	"duo_left_key": KEY_F,
	"duo_right_key": KEY_J,
	"classic_keys": [KEY_D, KEY_F, KEY_J, KEY_K],
	"lane_keys": [KEY_D, KEY_F, KEY_J, KEY_K],
	"window_mode": "windowed",
	"ui_scale": 1.0,
	"font_scale": 1.0,
	"reduced_motion": false,
	"high_contrast": false,
}

var values: Dictionary = DEFAULTS.duplicate(true)

func _ready() -> void:
	load_values()

func load_values() -> void:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		values = _migrate(save_service.load_settings(DEFAULTS))
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
	if key == "classic_keys":
		values["lane_keys"] = value
	elif key == "lane_keys":
		values["classic_keys"] = value
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

func _migrate(loaded: Dictionary) -> Dictionary:
	var migrated := DEFAULTS.duplicate(true)
	for key in loaded.keys():
		if migrated.has(key):
			migrated[key] = loaded[key]
	# Schema v1 stored all custom keys in lane_keys. Preserve those keys as the
	# optional classic layout while making F/J the new DUO default.
	if loaded.has("lane_keys") and not loaded.has("classic_keys"):
		migrated["classic_keys"] = Array(loaded.lane_keys).duplicate()
		migrated["lane_keys"] = Array(loaded.lane_keys).duplicate()
	migrated["schema_version"] = 2
	return migrated
