extends Node
## JSON Lines application logging without media or secrets.

var log_path := "user://logs/app.jsonl"

func _ready() -> void:
	info("app_started", {"product": "ECHOLOOP: PLAYLIST RAID"})

func info(event_name: String, fields: Dictionary = {}) -> void:
	_write("info", event_name, fields)

func warn(event_name: String, fields: Dictionary = {}) -> void:
	_write("warn", event_name, fields)

func error(event_name: String, fields: Dictionary = {}) -> void:
	_write("error", event_name, fields)

func _write(level: String, event_name: String, fields: Dictionary) -> void:
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	var safe := {"timestamp": Time.get_datetime_string_from_system(true), "level": level, "event": event_name}
	for key in fields.keys():
		if str(key) not in ["token", "cookie", "audio_bytes"]:
			safe[key] = fields[key]
	file.store_string(JSON.stringify(safe) + "\n")
	file.close()

