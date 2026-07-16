class_name ChartLoader
extends RefCounted
## Data-driven chart loader and defensive Phase 1–2 validator.

const BEAT_MAP_SCRIPT := preload("res://scripts/core/beat_map.gd")
const RUNTIME_ADAPTER_SCRIPT := preload("res://scripts/core/runtime_chart_adapter.gd")

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
	var schema_version := int(chart.get("schema_version", 0))
	if schema_version not in [1, 2]:
		return _fail("unsupported schema_version")
	for key in ["chart_id", "duration_ms", "phrases", "notes"]:
		if not chart.has(key):
			return _fail("missing chart field: " + key)
	if schema_version == 1 and (not chart.has("seed") or not chart.has("bpm") or not chart.has("beats_per_bar")):
		return _fail("schema v1 timing fields are missing")
	if schema_version == 1 and (float(chart.bpm) <= 0.0 or int(chart.beats_per_bar) != 4):
		return _fail("invalid tempo, meter, or duration")
	if schema_version == 2:
		var timing: Dictionary = chart.get("timing", {})
		if timing.is_empty() or not timing.has("beats_ms") or Array(timing.beats_ms).is_empty():
			return _fail("schema v2 timing map is missing")
	if int(chart.duration_ms) <= 0 or chart.phrases.is_empty() or chart.notes.is_empty():
		return _fail("chart must contain phrases and notes")
	if schema_version == 2:
		var timing_data: Dictionary = chart.get("timing", {})
		var beats: Array = timing_data.get("beats_ms", [])
		for index in range(beats.size()):
			if float(beats[index]) < 0.0 or (index > 0 and float(beats[index]) <= float(beats[index - 1])):
				return _fail("schema v2 beats must be strictly increasing")
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

func load_runtime_chart(path: String, gameplay_mode: String = "duo_2key") -> Dictionary:
	var chart := load_chart(path)
	return normalize(chart, gameplay_mode) if not chart.is_empty() else {}

func normalize(chart: Dictionary, gameplay_mode: String = "duo_2key") -> Dictionary:
	if chart.is_empty() or not validate(chart):
		return {}
	var runtime := chart.duplicate(true)
	var beats: Array = []
	var downbeats: Array = []
	var segments: Array = []
	var meter := 4
	if int(chart.get("schema_version", 1)) == 2:
		var timing: Dictionary = chart.get("timing", {})
		beats = timing.get("beats_ms", []).duplicate()
		downbeats = timing.get("downbeats_ms", []).duplicate()
		segments = timing.get("tempo_segments", []).duplicate(true)
		meter = int(timing.get("beats_per_bar", 4))
	else:
		meter = int(chart.get("beats_per_bar", 4))
		var interval := 60000.0 / float(chart.get("bpm", 120.0))
		var cursor := 0.0
		while cursor <= float(chart.duration_ms):
			beats.append(cursor)
			if beats.size() % meter == 1:
				downbeats.append(cursor)
			cursor += interval
		segments = [{"start_ms": 0.0, "end_ms": float(chart.duration_ms), "bpm": float(chart.get("bpm", 120.0))}]
	var beat_map = BEAT_MAP_SCRIPT.new()
	if not beat_map.configure(beats, downbeats, segments, meter, chart.phrases):
		last_error = "invalid BeatMap: " + beat_map.last_error
		return {}
	runtime["beats"] = beats
	runtime["downbeats"] = downbeats
	runtime["beat_map"] = beat_map
	runtime["beats_per_bar"] = meter
	runtime["bpm"] = float(chart.get("bpm", chart.get("timing", {}).get("bpm_summary", 120.0)))
	return RUNTIME_ADAPTER_SCRIPT.new().adapt(runtime, gameplay_mode)

func _fail(message: String) -> bool:
	last_error = message
	return false
