extends Node
## Offline test-song and SongPack library boundary.

const SONG_DATA_ROOT := "user://echoloop-data"
var test_manifest: Dictionary = {}

func _ready() -> void:
	var file := FileAccess.open("res://data/test_manifest.json", FileAccess.READ)
	if file != null:
		test_manifest = JSON.parse_string(file.get_as_text())

func get_test_song() -> Dictionary:
	return test_manifest.duplicate(true)

func list_local_songs() -> Array:
	var result: Array = []
	if not test_manifest.is_empty():
		result.append(get_test_song())
	var directory := DirAccess.open(SONG_DATA_ROOT + "/songs")
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and not entry.begins_with("."):
			var manifest_path := SONG_DATA_ROOT + "/songs/" + entry + "/manifest.json"
			var file := FileAccess.open(manifest_path, FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				if parsed is Dictionary:
					parsed["song_uuid"] = entry
					parsed["pack_path"] = SONG_DATA_ROOT + "/songs/" + entry
					result.append(parsed)
		entry = directory.get_next()
	directory.list_dir_end()
	return result

func get_song_pack_root() -> String:
	return ProjectSettings.globalize_path(SONG_DATA_ROOT)

func chart_path(song_uuid: String, difficulty: String) -> String:
	return SONG_DATA_ROOT + "/songs/" + song_uuid + "/charts/" + difficulty + ".json"

func playback_path(song_uuid: String) -> String:
	return SONG_DATA_ROOT + "/songs/" + song_uuid + "/playback.ogg"

func remove_song_pack(song_uuid: String) -> bool:
	var pack_path := (SONG_DATA_ROOT + "/songs/" + song_uuid).simplify_path()
	if not pack_path.begins_with(SONG_DATA_ROOT + "/songs/"):
		return false
	return _remove_recursive(ProjectSettings.globalize_path(pack_path))

func _remove_recursive(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if directory.current_is_dir():
				if not _remove_recursive(child):
					directory.list_dir_end()
					return false
			elif DirAccess.remove_absolute(child) != OK:
				directory.list_dir_end()
				return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK
