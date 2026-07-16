class_name FourLaneToDuoProjector
extends RefCounted
## Deterministic runtime projection from legacy/classic lanes to DUO input lanes.

const DUO_MODE := "duo_2key"
const CLASSIC_MODE := "classic_4lane"

func project(chart: Dictionary, gameplay_mode: String = DUO_MODE) -> Dictionary:
	var runtime := chart.duplicate(true)
	if gameplay_mode == CLASSIC_MODE:
		runtime["gameplay_mode"] = CLASSIC_MODE
		runtime["notes"] = _annotate_classic(Array(runtime.get("notes", [])))
		return runtime
	runtime["gameplay_mode"] = DUO_MODE
	runtime["notes"] = _project_duo(Array(runtime.get("notes", [])))
	return runtime

func _annotate_classic(source: Array) -> Array:
	var result: Array = []
	for original in source:
		if not original is Dictionary:
			continue
		var note: Dictionary = original.duplicate(true)
		var source_lanes: Array = _source_lanes(note)
		note["input_lane"] = int(note.get("lane", source_lanes[0]))
		note["input_lanes"] = source_lanes.duplicate()
		note["semantic_lanes"] = _semantic_lanes(note, source_lanes)
		note["semantic_lane"] = int(note.semantic_lanes[0])
		result.append(note)
	return result

func _project_duo(source: Array) -> Array:
	var grouped: Dictionary = {}
	for original in source:
		if not original is Dictionary:
			continue
		var note: Dictionary = original.duplicate(true)
		var source_lanes: Array = _source_lanes(note)
		var input_lanes: Array = []
		for lane in source_lanes:
			var input_lane := 0 if int(lane) <= 1 else 1
			if not input_lanes.has(input_lane):
				input_lanes.append(input_lane)
		input_lanes.sort()
		var key := "%d|%s|%d" % [int(note.get("time_ms", 0)), ",".join(PackedStringArray(input_lanes.map(func(value: int) -> String: return str(value)))), int(note.get("phrase", 0))]
		if not grouped.has(key):
			grouped[key] = _new_projected_note(note, source_lanes, input_lanes)
		else:
			_merge_projected_note(grouped[key], note, source_lanes, input_lanes)
	var result: Array = grouped.values()
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.time_ms) != int(right.time_ms):
			return int(left.time_ms) < int(right.time_ms)
		return str(left.id) < str(right.id))
	_resolve_hold_conflicts(result)
	return result

func _new_projected_note(source: Dictionary, source_lanes: Array, input_lanes: Array) -> Dictionary:
	var note := source.duplicate(true)
	note["id"] = "duo-" + str(source.get("id", "note"))
	note["lane"] = int(input_lanes[0])
	note["lanes"] = input_lanes.duplicate()
	note["input_lane"] = int(input_lanes[0])
	note["input_lanes"] = input_lanes.duplicate()
	note["semantic_lanes"] = _semantic_lanes(source, source_lanes)
	note["semantic_lane"] = int(note.semantic_lanes[0])
	if input_lanes.size() > 1:
		note["type"] = "chord"
	elif str(source.get("type", "tap")) == "hold" and int(source.get("duration_ms", 0)) > 0:
		note["type"] = "hold"
	else:
		note["type"] = "tap"
	return note

func _merge_projected_note(target: Dictionary, source: Dictionary, source_lanes: Array, input_lanes: Array) -> void:
	var semantics: Array = Array(target.get("semantic_lanes", []))
	for lane in _semantic_lanes(source, source_lanes):
		if not semantics.has(lane):
			semantics.append(lane)
	semantics.sort()
	target["semantic_lanes"] = semantics
	target["semantic_lane"] = int(semantics[0])
	if input_lanes.size() > 1:
		target["type"] = "chord"
	elif str(source.get("type", "tap")) == "hold" and int(source.get("duration_ms", 0)) > int(target.get("duration_ms", 0)):
		target["type"] = "hold"
		target["duration_ms"] = int(source.get("duration_ms", 0))
	target["id"] = str(target.id) + "+" + str(source.get("id", "note"))

func _resolve_hold_conflicts(notes: Array) -> void:
	var active_hold: Dictionary = {}
	for index in range(notes.size()):
		var note: Dictionary = notes[index]
		var start := int(note.get("time_ms", 0))
		for input_lane in Array(note.get("input_lanes", [note.get("lane", 0)])):
			var lane := int(input_lane)
			if active_hold.has(lane):
				var previous_index := int(active_hold[lane])
				var previous: Dictionary = notes[previous_index]
				var previous_start := int(previous.get("time_ms", 0))
				var previous_end := previous_start + int(previous.get("duration_ms", 0))
				if start <= previous_end:
					var safe_duration := maxi(1, start - previous_start - 1)
					if safe_duration < int(previous.get("duration_ms", 0)):
						previous["duration_ms"] = safe_duration
						if safe_duration <= 1:
							previous["type"] = "tap"
			if str(note.get("type", "tap")) == "hold" and int(note.get("duration_ms", 0)) > 0:
				active_hold[lane] = index

func _source_lanes(note: Dictionary) -> Array:
	var lanes: Array = note.get("lanes", [note.get("lane", 0)])
	if lanes.is_empty():
		lanes = [note.get("lane", 0)]
	return lanes.map(func(value: Variant) -> int: return clampi(int(value), 0, 3))

func _semantic_lanes(note: Dictionary, fallback: Array) -> Array:
	var values: Array = note.get("semantic_lanes", note.get("semantic_lane", fallback))
	if not values is Array:
		values = [values]
	var result: Array = []
	for value in values:
		var lane := clampi(int(value), 0, 3)
		if not result.has(lane):
			result.append(lane)
	result.sort()
	return result if not result.is_empty() else [0]
