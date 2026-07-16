extends Node
## Input mapping and judgement assist settings.

var lane_keys: Array = [KEY_D, KEY_F, KEY_J, KEY_K]
var assist_ms: float = 0.0

func _ready() -> void:
	_sync_from_settings()

func _sync_from_settings() -> void:
	var settings := get_node_or_null("/root/SettingsService")
	if settings != null:
		lane_keys = settings.get_value("lane_keys", lane_keys)
		assist_ms = float(settings.get_value("judgement_assist_ms", 0.0))

func lane_for_key(keycode: int) -> int:
	for index in range(lane_keys.size()):
		if int(lane_keys[index]) == keycode:
			return index
	return -1

func set_lane_key(lane: int, keycode: int) -> bool:
	if lane < 0 or lane >= 4 or keycode == KEY_ESCAPE:
		return false
	if lane_keys.has(keycode):
		return false
	lane_keys[lane] = keycode
	var settings := get_node_or_null("/root/SettingsService")
	if settings != null:
		settings.set_value("lane_keys", lane_keys)
	return true
