extends Node
## Versioned, atomic user:// settings persistence.

const SETTINGS_PATH := "user://settings.json"
const BACKUP_PATH := "user://settings.json.bak"

func save_settings(values: Dictionary) -> bool:
	var payload := values.duplicate(true)
	payload["schema_version"] = 1
	var json_text := JSON.stringify(payload, "  ")
	var temporary := "user://settings.json.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json_text + "\n")
	file.close()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SETTINGS_PATH), ProjectSettings.globalize_path(BACKUP_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(SETTINGS_PATH))
	var log_service := get_node_or_null("/root/LogService")
	if log_service != null:
		log_service.info("settings_saved")
	return true

func load_settings(defaults: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return defaults.duplicate(true)
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return defaults.duplicate(true)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		_quarantine_corrupt()
		return defaults.duplicate(true)
	var merged := defaults.duplicate(true)
	for key in defaults.keys():
		if parsed.has(key):
			merged[key] = parsed[key]
	return merged

func _quarantine_corrupt() -> void:
	var stamp := str(Time.get_unix_time_from_system())
	var corrupt_path := ProjectSettings.globalize_path(SETTINGS_PATH + "." + stamp + ".corrupt")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SETTINGS_PATH), corrupt_path)
	var log_service := get_node_or_null("/root/LogService")
	if log_service != null:
		log_service.warn("settings_quarantined", {"path": corrupt_path})
