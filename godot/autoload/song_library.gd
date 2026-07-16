extends Node
## Minimal local song package boundary; remote imports are intentionally absent in Phase 0–2.

var test_manifest: Dictionary = {}

func _ready() -> void:
	var file := FileAccess.open("res://data/test_manifest.json", FileAccess.READ)
	if file != null:
		test_manifest = JSON.parse_string(file.get_as_text())

func get_test_song() -> Dictionary:
	return test_manifest.duplicate(true)

func list_local_songs() -> Array:
	return [get_test_song()] if not test_manifest.is_empty() else []

