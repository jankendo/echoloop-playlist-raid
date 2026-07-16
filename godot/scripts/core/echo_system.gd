class_name EchoSystem
extends RefCounted
## Phrase-relative EchoTracks and non-recursive Corruption.

const MAX_ECHOES := 3
const LIFETIME_PHRASES := 3

var active_echoes: Array = []
var chorus_memory: float = 0.0
var corruption_queue: Array = []
var replayed_keys: Dictionary = {}
var chorus_used_phrases: Dictionary = {}

func record_success(phrase_index: int, phrase_start_ms: float, beat_ms: float, lane: int, event_type: String, note_id: String, judgement: String, hold_duration_ms: int = 0, chord_group_id: String = "") -> void:
	var phase := maxf(0.0, (beat_ms - phrase_start_ms) / 500.0)
	var event := {"beat_phase": phase, "lane": lane, "event_type": event_type, "judgement": judgement, "power": TimingJudge.power(judgement), "source_note_id": note_id, "hold_duration_ms": hold_duration_ms, "chord_group_id": chord_group_id}
	var bucket := _find_or_create_recording(phrase_index)
	bucket.events.append(event)

func record_miss(phrase_index: int, phase: float, lane: int, note_id: String) -> void:
	corruption_queue.append({"source_phrase": phrase_index, "target_phrase": phrase_index + 1, "beat_phase": phase, "lane": lane, "source_note_id": note_id, "resolved": false})

func finalize_phrase(phrase_index: int) -> void:
	var recording: Variant = _find_recording(phrase_index)
	if recording == null or recording.events.is_empty():
		return
	var echo := {"source_phrase": phrase_index, "expires_after": phrase_index + LIFETIME_PHRASES, "events": recording.events.duplicate(true), "power": _total_power(recording.events), "pulses": 0}
	active_echoes.append(echo)
	if active_echoes.size() > MAX_ECHOES:
		var expired: Dictionary = active_echoes.pop_front()
		chorus_memory += float(expired.power)

func replay_events(phrase_index: int, phase: float, phrase_start_ms: float, beat_duration_ms: float = 500.0) -> Array:
	var output: Array = []
	for echo in active_echoes:
		if phrase_index <= int(echo.source_phrase):
			continue
		if phrase_index > int(echo.expires_after):
			continue
		for event in echo.events:
			var key := str(echo.source_phrase) + ":" + str(event.source_note_id) + ":" + str(phrase_index)
			if replayed_keys.has(key):
				continue
			if absf(float(event.beat_phase) - phase) <= 0.035:
				replayed_keys[key] = true
				echo.pulses = int(echo.pulses) + 1
				output.append({"lane": event.lane, "effect": lane_effect(int(event.lane)), "power": event.power, "source_phrase": echo.source_phrase, "time_ms": phrase_start_ms + float(event.beat_phase) * beat_duration_ms})
	return output

func corruption_for_phrase(phrase_index: int) -> Array:
	var result: Array = []
	for item in corruption_queue:
		if int(item.target_phrase) == phrase_index and not bool(item.resolved):
			result.append(item)
	return result

func resolve_corruption(item: Dictionary, success: bool) -> void:
	item.resolved = true
	item["success"] = success
	if success:
		chorus_memory += 0.15

func expire_phrase(phrase_index: int) -> void:
	for item in corruption_queue:
		if int(item.target_phrase) <= phrase_index:
			item.resolved = true
	for echo in active_echoes:
		if phrase_index > int(echo.expires_after):
			chorus_memory += float(echo.power)
	active_echoes = active_echoes.filter(func(value: Dictionary) -> bool: return phrase_index <= int(value.expires_after))

func maybe_chorus(phrase_index: int, section: String) -> Dictionary:
	if section != "chorus" or chorus_used_phrases.has(phrase_index) or chorus_memory <= 0.0:
		return {"triggered": false, "power": 0.0}
	chorus_used_phrases[phrase_index] = true
	var power := chorus_memory
	chorus_memory = 0.0
	return {"triggered": true, "power": power}

func lane_effect(lane: int) -> String:
	return ["PULSE_DAMAGE", "WEIGHT_SHIELD", "VOICE_HEAL", "FIELD_RESONANCE"][clampi(lane, 0, 3)]

func _find_or_create_recording(phrase_index: int) -> Dictionary:
	var existing: Variant = _find_recording(phrase_index)
	if existing != null:
		return existing
	var created := {"phrase": phrase_index, "events": []}
	_recordings.append(created)
	return created

var _recordings: Array = []

func _find_recording(phrase_index: int) -> Variant:
	for recording in _recordings:
		if int(recording.phrase) == phrase_index:
			return recording
	return null

func _total_power(events: Array) -> float:
	var total := 0.0
	for event in events:
		total += float(event.power)
	return total
