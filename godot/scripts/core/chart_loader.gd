class_name ChartLoader
extends RefCounted
## Data-driven chart loader and defensive Phase 1–2 validator.

var last_error: String = ""

func load_chart(path: String) -> Dictionary:
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "chart file not found: " + path
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		last_error = "chart root must be an object"
		return {}
	if not validate(parsed):
		return {}
	return parsed

func validate(chart: Dictionary) -> bool:
	if int(chart.get("schema_version", 0)) != 1:
		return _fail("unsupported schema_version")
	for key in ["chart_id", "seed", "bpm", "beats_per_bar", "duration_ms", "phrases", "notes"]:
		if not chart.has(key):
			return _fail("missing chart field: " + key)
	if float(chart.bpm) <= 0.0 or int(chart.beats_per_bar) != 4 or int(chart.duration_ms) <= 0:
		return _fail("invalid tempo, meter, or duration")
	if chart.phrases.is_empty() or chart.notes.is_empty():
		return _fail("chart must contain phrases and notes")
	var previous_time := -1
	var note_ids: Dictionary = {}
	for note in chart.notes:
		if not note is Dictionary:
			return _fail("note must be an object")
		for key in ["id", "type", "lane", "time_ms", "phrase"]:
			if not note.has(key):
				return _fail("note missing field: " + key)
		if note_ids.has(note.id):
			return _fail("duplicate note id: " + str(note.id))
		note_ids[note.id] = true
		var note_time := int(note.time_ms)
		if note_time < 0 or note_time > int(chart.duration_ms):
			return _fail("note time outside song: " + str(note.id))
		if note_time < previous_time:
			return _fail("notes must be sorted by time")
		previous_time = note_time
		if int(note.lane) < 0 or int(note.lane) > 3:
			return _fail("lane outside 0..3: " + str(note.id))
		if str(note.type) not in ["tap", "hold", "chord"]:
			return _fail("unsupported note type: " + str(note.type))
		if str(note.type) == "hold" and int(note.get("duration_ms", 0)) <= 0:
			return _fail("hold requires positive duration: " + str(note.id))
		if str(note.type) == "chord":
			var lanes: Array = note.get("lanes", [])
			if lanes.size() < 2 or lanes.size() > 4 or lanes.size() != lanes.duplicate().size():
				return _fail("chord lanes are invalid: " + str(note.id))
	return true

func _fail(message: String) -> bool:
	last_error = message
	return false

