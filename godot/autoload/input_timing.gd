extends Node
## Input mapping and judgement assist settings.

const DUO_MODE := "duo_2key"
const CLASSIC_MODE := "classic_4lane"

var gameplay_mode := DUO_MODE
var duo_keys: Array = [KEY_F, KEY_J]
var classic_keys: Array = [KEY_D, KEY_F, KEY_J, KEY_K]
var lane_keys: Array = [KEY_D, KEY_F, KEY_J, KEY_K]
var assist_ms: float = 0.0

func _ready() -> void:
	_sync_from_settings()

func _sync_from_settings() -> void:
	var settings := get_node_or_null("/root/SettingsService")
	if settings != null:
		gameplay_mode = str(settings.get_value("gameplay_mode", DUO_MODE))
		duo_keys = [int(settings.get_value("duo_left_key", KEY_F)), int(settings.get_value("duo_right_key", KEY_J))]
		classic_keys = Array(settings.get_value("classic_keys", settings.get_value("lane_keys", classic_keys))).duplicate()
		lane_keys = classic_keys.duplicate()
		assist_ms = float(settings.get_value("judgement_assist_ms", 0.0))

func lane_for_key(keycode: int) -> int:
	var active_keys := duo_keys if gameplay_mode == DUO_MODE else classic_keys
	for index in range(active_keys.size()):
		if int(active_keys[index]) == keycode:
			return index
	return -1

func input_lane_for_key(keycode: int) -> int:
	return lane_for_key(keycode)

func set_mode(value: String) -> bool:
	if value not in [DUO_MODE, CLASSIC_MODE]:
		return false
	gameplay_mode = value
	var settings := get_node_or_null("/root/SettingsService")
	if settings != null:
		settings.set_value("gameplay_mode", value)
	return true

func set_lane_key(lane: int, keycode: int) -> bool:
	var active_keys := duo_keys if gameplay_mode == DUO_MODE else classic_keys
	if lane < 0 or lane >= active_keys.size() or keycode == KEY_ESCAPE:
		return false
	if active_keys.has(keycode):
		return false
	active_keys[lane] = keycode
	if gameplay_mode == DUO_MODE:
		duo_keys = active_keys
	else:
		classic_keys = active_keys
		lane_keys = active_keys.duplicate()
	var settings := get_node_or_null("/root/SettingsService")
	if settings != null:
		if gameplay_mode == DUO_MODE:
			settings.set_value("duo_left_key", duo_keys[0])
			settings.set_value("duo_right_key", duo_keys[1])
		else:
			settings.set_value("classic_keys", classic_keys)
	return true
