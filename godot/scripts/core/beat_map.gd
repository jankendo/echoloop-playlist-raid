class_name BeatMap
extends RefCounted
## Explicit musical-time mapping for fixed and variable tempo charts.

var beats_ms: Array[float] = []
var downbeats_ms: Array[float] = []
var tempo_segments: Array = []
var beats_per_bar: int = 4
var phrases: Array = []
var last_error: String = ""

func configure(beats: Array, downbeats: Array = [], segments: Array = [], meter: int = 4, phrase_data: Array = []) -> bool:
	last_error = ""
	beats_ms.clear()
	downbeats_ms.clear()
	tempo_segments = segments.duplicate(true)
	beats_per_bar = meter
	phrases = phrase_data.duplicate(true)
	for value in beats:
		beats_ms.append(float(value))
	for value in downbeats:
		downbeats_ms.append(float(value))
	if beats_per_bar < 1 or beats_per_bar > 12:
		return _fail("meter must be between 1 and 12")
	if beats_ms.is_empty():
		return _fail("beats_ms must not be empty")
	for index in range(beats_ms.size()):
		if is_nan(beats_ms[index]) or is_inf(beats_ms[index]) or beats_ms[index] < 0.0:
			return _fail("beat time is invalid")
		if index > 0 and beats_ms[index] - beats_ms[index - 1] < 1.0:
			return _fail("beats must be strictly increasing")
	for value in downbeats_ms:
		if is_nan(value) or is_inf(value) or value < 0.0:
			return _fail("downbeat time is invalid")
	return true

func time_to_beat(time_ms: float) -> float:
	if beats_ms.is_empty():
		return 0.0
	if beats_ms.size() == 1:
		return (time_ms - beats_ms[0]) / _fallback_interval()
	if time_ms <= beats_ms[0]:
		return (time_ms - beats_ms[0]) / (beats_ms[1] - beats_ms[0])
	for index in range(1, beats_ms.size()):
		if time_ms <= beats_ms[index]:
			var left := beats_ms[index - 1]
			return float(index - 1) + (time_ms - left) / (beats_ms[index] - left)
	var last_interval := beats_ms[-1] - beats_ms[-2]
	return float(beats_ms.size() - 1) + (time_ms - beats_ms[-1]) / last_interval

func beat_to_time(beat_position: float) -> float:
	if beats_ms.is_empty():
		return 0.0
	if beats_ms.size() == 1:
		return beats_ms[0] + beat_position * _fallback_interval()
	if beat_position <= 0.0:
		return beats_ms[0] + beat_position * (beats_ms[1] - beats_ms[0])
	var lower := int(floor(beat_position))
	if lower >= beats_ms.size() - 1:
		return beats_ms[-1] + (beat_position - float(beats_ms.size() - 1)) * (beats_ms[-1] - beats_ms[-2])
	var fraction := beat_position - float(lower)
	return lerpf(beats_ms[lower], beats_ms[lower + 1], fraction)

func phrase_relative_to_time(phrase_index: int, relative_beat: float) -> float:
	var phrase := _phrase(phrase_index)
	if phrase.is_empty():
		return beat_to_time(relative_beat)
	return beat_to_time(time_to_beat(float(phrase.get("start_ms", 0.0))) + relative_beat)

func time_to_phrase_relative(phrase_index: int, time_ms: float) -> float:
	var phrase := _phrase(phrase_index)
	if phrase.is_empty():
		return time_to_beat(time_ms)
	return time_to_beat(time_ms) - time_to_beat(float(phrase.get("start_ms", 0.0)))

func downbeat_time(index: int) -> float:
	if downbeats_ms.is_empty():
		return beat_to_time(float(index * beats_per_bar))
	return downbeats_ms[clampi(index, 0, downbeats_ms.size() - 1)]

func bar_time(index: int) -> float:
	return downbeat_time(index)

func normalized_phrase_phase(phrase_index: int, relative_beat: float) -> float:
	var phrase := _phrase(phrase_index)
	var count := float(phrase.get("beat_count", beats_per_bar * 4)) if not phrase.is_empty() else float(beats_per_bar * 4)
	return clampf(relative_beat / maxf(1.0, count), 0.0, 1.0)

func phrase_beat_from_normalized(phrase_index: int, normalized_phase: float) -> float:
	var phrase := _phrase(phrase_index)
	var count := float(phrase.get("beat_count", beats_per_bar * 4)) if not phrase.is_empty() else float(beats_per_bar * 4)
	return clampf(normalized_phase, 0.0, 1.0) * count

func _fallback_interval() -> float:
	return 60000.0 / 120.0

func _phrase(index: int) -> Dictionary:
	for phrase in phrases:
		if int(phrase.get("id", -1)) == index:
			return phrase
	return {}

func _fail(message: String) -> bool:
	last_error = message
	return false
