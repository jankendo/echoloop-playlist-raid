class_name GameSession
extends RefCounted
## Pure-ish gameplay state used by the scene and headless tests.

signal judgement_applied(result: Dictionary)
signal phrase_changed(index: int)
signal echo_triggered(event: Dictionary)
signal corruption_spawned(item: Dictionary)

var chart: Dictionary = {}
var notes: Array = []
var judged: Dictionary = {}
var hold_state: Dictionary = {}
var current_time_ms: float = 0.0
var current_phrase: int = 0
var previous_phrase: int = 0
var score_system := ScoreSystem.new()
var echo_system := EchoSystem.new()
var boss_max_hp: float = 100.0
var boss_hp: float = 100.0
var integrity: float = 100.0
var shield: float = 0.0
var total_echo_damage: float = 0.0
var total_normal_damage: float = 0.0
var total_heal: float = 0.0
var total_shield: float = 0.0
var corruption_count: int = 0
var corruption_broken: int = 0
var _assist_ms: float = 0.0
var gameplay_mode := "duo_2key"

func setup(chart_data: Dictionary, assist_ms: float = 0.0, requested_mode: String = "duo_2key") -> bool:
	gameplay_mode = requested_mode if requested_mode in ["duo_2key", "classic_4lane"] else "duo_2key"
	chart = ChartLoader.new().normalize(chart_data, gameplay_mode)
	if chart.is_empty():
		return false
	notes = chart.get("notes", []).duplicate(true)
	_assist_ms = assist_ms
	boss_max_hp = 100.0
	boss_hp = boss_max_hp
	_integrity_reset()
	for note in notes:
		var lanes: Array = note.get("lanes", [note.lane])
		score_system.register_note(lanes)
	return not notes.is_empty()

func advance(time_ms: float) -> void:
	current_time_ms = maxf(current_time_ms, time_ms)
	_auto_miss_overdue_notes()
	var phrase := phrase_for_time(current_time_ms)
	if phrase != current_phrase:
		for index in range(current_phrase, phrase):
			_finalize_phrase(index)
		current_phrase = phrase
		phrase_changed.emit(current_phrase)
	var phrase_data := _phrase(current_phrase)
	if phrase_data.is_empty():
		return
	var beat_map = chart.get("beat_map")
	var phase: float = float(beat_map.time_to_phrase_relative(current_phrase, current_time_ms))
	var phrase_beat_count := _phrase_beat_count(current_phrase)
	for replay in echo_system.replay_events(current_phrase, phase, float(phrase_data.start_ms), beat_map, phrase_beat_count):
		_apply_echo(replay)
	for corruption in echo_system.corruption_for_phrase(current_phrase):
		if not bool(corruption.get("announced", false)):
			corruption.announced = true
			corruption_spawned.emit(corruption)
	if current_time_ms > float(phrase_data.end_ms) + 150.0:
		echo_system.expire_phrase(current_phrase)

func handle_lane_input(lane: int, input_time_ms: float, pressed: bool = true) -> Dictionary:
	var max_lane := 1 if gameplay_mode == "duo_2key" else 3
	if lane < 0 or lane > max_lane:
		return {"judgement": "GHOST", "lane": lane}
	if not pressed:
		return _release_hold(lane, input_time_ms)
	return handle_input_lanes([lane], input_time_ms)

func handle_input_lanes(input_lanes: Array, input_time_ms: float) -> Dictionary:
	var pressed_lanes: Array = []
	for value in input_lanes:
		var lane := int(value)
		if lane >= 0 and lane <= (1 if gameplay_mode == "duo_2key" else 3) and not pressed_lanes.has(lane):
			pressed_lanes.append(lane)
	pressed_lanes.sort()
	if pressed_lanes.is_empty():
		score_system.register_ghost()
		return {"judgement": "GHOST", "lane": -1}
	var candidate := _find_candidate(pressed_lanes, input_time_ms)
	if candidate.is_empty():
		if _has_pending_chord(pressed_lanes, input_time_ms):
			return {"judgement": "PENDING", "lane": pressed_lanes[0], "input_lanes": pressed_lanes}
		score_system.register_ghost()
		return {"judgement": "GHOST", "lane": pressed_lanes[0], "input_lanes": pressed_lanes}
	var note: Dictionary = candidate.note
	var delta_ms := input_time_ms - float(note.time_ms)
	var judgement := TimingJudge.classify(delta_ms, _assist_ms)
	if judged.has(note.id):
		return {"judgement": "GHOST", "lane": pressed_lanes[0], "input_lanes": pressed_lanes}
	judged[note.id] = true
	var note_input_lanes: Array = note.get("lanes", [note.lane])
	score_system.apply_judgement(judgement, delta_ms, note_input_lanes, _assist_ms > 0.0)
	if judgement == "MISS":
		_register_miss(note, int(note.get("input_lane", note_input_lanes[0])))
	else:
		var phrase_data := _phrase(int(note.phrase))
		var beat_map = chart.get("beat_map")
		var note_phase: float = float(beat_map.time_to_phrase_relative(int(note.phrase), float(note.time_ms)))
		for semantic_lane in Array(note.get("semantic_lanes", [note.get("semantic_lane", note.get("lane", 0))])):
			echo_system.record_success(int(note.phrase), float(phrase_data.start_ms), float(note.time_ms), int(note.get("input_lane", note_input_lanes[0])), str(note.type), str(note.id) + ":" + str(semantic_lane), judgement, int(note.get("duration_ms", 0)), str(note.get("chord_group_id", "")), _phrase_beat_count(int(note.phrase)), note_phase, int(semantic_lane))
		var attack := 1.25 * TimingJudge.power(judgement)
		boss_hp = maxf(0.0, boss_hp - attack)
		total_normal_damage += attack
		if str(note.type) == "hold":
			hold_state[note.id] = {"started": true, "end_ms": int(note.time_ms) + int(note.duration_ms), "lane": int(note.get("input_lane", note_input_lanes[0]))}
	var result := {"judgement": judgement, "delta_ms": delta_ms, "lane": pressed_lanes[0], "input_lanes": pressed_lanes, "semantic_lanes": note.get("semantic_lanes", []), "note_id": note.id, "score": TimingJudge.score(judgement)}
	judgement_applied.emit(result)
	return result

func handle_corruption_input(lane: int, input_time_ms: float) -> bool:
	for item in echo_system.corruption_for_phrase(current_phrase):
		var phrase_data := _phrase(current_phrase)
		var beat_map = chart.get("beat_map")
		var target_phase := float(item.get("beat_phase", 0.0))
		var source_count := float(item.get("source_phrase_beat_count", 0.0))
		if source_count > 0.0 and not is_equal_approx(source_count, _phrase_beat_count(current_phrase)):
			target_phase = float(item.get("normalized_phase", 0.0)) * _phrase_beat_count(current_phrase)
		var target_time: float = float(beat_map.phrase_relative_to_time(current_phrase, target_phase))
		if int(item.get("input_lane", item.get("lane", -1))) == lane and absf(input_time_ms - target_time) <= 120.0:
			echo_system.resolve_corruption(item, true)
			corruption_broken += 1
			return true
	return false

func phrase_for_time(time_ms: float) -> int:
	for phrase in chart.get("phrases", []):
		if time_ms >= float(phrase.start_ms) and time_ms < float(phrase.end_ms):
			return int(phrase.id)
	return maxi(0, chart.get("phrases", []).size() - 1)

func is_finished() -> bool:
	return current_time_ms >= float(chart.get("duration_ms", 0))

func result_snapshot() -> Dictionary:
	var result := score_system.snapshot()
	result.merge({"boss_hp": boss_hp, "boss_max_hp": boss_max_hp, "integrity": integrity, "shield": shield, "echo_damage": total_echo_damage, "normal_damage": total_normal_damage, "healing": total_heal, "shield_gained": total_shield, "corruptions": corruption_count, "corruption_broken": corruption_broken, "cleared": boss_hp <= 0.0 and integrity > 0.0})
	return result

func _find_candidate(input_lanes: Array, input_time_ms: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for note in notes:
		var note_lanes: Array = note.get("input_lanes", note.get("lanes", [note.get("lane", -1)]))
		if judged.has(note.id) or not _same_lanes(note_lanes, input_lanes):
			continue
		var distance := absf(input_time_ms - float(note.time_ms))
		if distance < best_distance and distance <= TimingJudge.GOOD_MS + _assist_ms:
			best_distance = distance
			best = {"note": note}
	return best

func _has_pending_chord(input_lanes: Array, input_time_ms: float) -> bool:
	if input_lanes.size() >= 2:
		return false
	for note in notes:
		if judged.has(note.id) or str(note.get("type", "")) != "chord":
			continue
		var note_lanes: Array = note.get("input_lanes", note.get("lanes", []))
		if input_lanes.size() < note_lanes.size() and input_lanes.all(func(value: Variant) -> bool: return note_lanes.has(value)) and absf(input_time_ms - float(note.time_ms)) <= TimingJudge.GOOD_MS + _assist_ms:
			return true
	return false

func _auto_miss_overdue_notes() -> void:
	for note in notes:
		if judged.has(note.id):
			continue
		if current_time_ms > float(note.time_ms) + TimingJudge.GOOD_MS + _assist_ms:
			_register_miss(note, int(note.get("input_lane", note.get("lane", 0))))

func _register_miss(note: Dictionary, lane: int) -> void:
	if judged.has(note.id):
		return
	judged[note.id] = true
	score_system.apply_judgement("MISS", 121.0, note.get("lanes", [lane]), _assist_ms > 0.0)
	_apply_integrity_damage(6.0)
	corruption_count += 1
	var phrase_index := int(note.phrase)
	var beat_map = chart.get("beat_map")
	var phrase_data := _phrase(phrase_index)
	echo_system.record_miss(phrase_index, beat_map.time_to_phrase_relative(phrase_index, float(note.time_ms)), lane, str(note.id), _phrase_beat_count(phrase_index), int(note.get("semantic_lane", lane)))
	judgement_applied.emit({"judgement": "MISS", "delta_ms": 121.0, "lane": lane, "note_id": note.id, "semantic_lane": int(note.get("semantic_lane", lane)), "score": 0})

func _release_hold(lane: int, input_time_ms: float) -> Dictionary:
	for note_id in hold_state.keys():
		var state: Dictionary = hold_state[note_id]
		if int(state.lane) != lane or bool(state.get("completed", false)):
			continue
		var delta := input_time_ms - float(state.end_ms)
		state.completed = true
		hold_state[note_id] = state
		if delta <= 100.0:
			return {"judgement": "HOLD_RELEASE", "delta_ms": delta, "lane": lane, "note_id": note_id}
		return {"judgement": "HOLD_PARTIAL", "delta_ms": delta, "lane": lane, "note_id": note_id}
	score_system.register_ghost()
	return {"judgement": "GHOST", "lane": lane}

func _finalize_phrase(index: int) -> void:
	echo_system.finalize_phrase(index)
	var phrase_data := _phrase(index)
	var chorus := echo_system.maybe_chorus(index, str(phrase_data.get("section", "")))
	if bool(chorus.triggered):
		_apply_echo({"effect": "PULSE_DAMAGE", "power": chorus.power, "lane": 0, "chorus": true})

func _apply_echo(replay: Dictionary) -> void:
	var amount := float(replay.get("power", 0.0))
	match str(replay.get("effect", "")):
		"PULSE_DAMAGE":
			var damage := 2.5 * amount
			boss_hp = maxf(0.0, boss_hp - damage)
			total_echo_damage += damage
		"WEIGHT_SHIELD":
			shield = minf(100.0, shield + 3.0 * amount)
			total_shield += 3.0 * amount
		"VOICE_HEAL":
			var healed := minf(100.0 - integrity, 2.0 * amount)
			integrity += healed
			total_heal += healed
		"FIELD_RESONANCE":
			score_system.resonance = minf(100.0, score_system.resonance + 4.0 * amount)
	echo_triggered.emit(replay)

func _apply_integrity_damage(amount: float) -> void:
	var blocked := minf(shield, amount)
	shield -= blocked
	integrity = maxf(0.0, integrity - (amount - blocked))

func _phrase(index: int) -> Dictionary:
	for phrase in chart.get("phrases", []):
		if int(phrase.id) == index:
			return phrase
	return {}

func _phrase_beat_count(index: int) -> float:
	var phrase := _phrase(index)
	if phrase.has("beat_count"):
		return maxf(1.0, float(phrase.beat_count))
	var beat_map = chart.get("beat_map")
	return maxf(1.0, beat_map.time_to_beat(float(phrase.end_ms)) - beat_map.time_to_beat(float(phrase.start_ms)))

func _integrity_reset() -> void:
	integrity = 100.0
	shield = 0.0
	current_time_ms = 0.0
	current_phrase = 0
	previous_phrase = 0
	judged.clear()
	hold_state.clear()
	echo_system = EchoSystem.new()
	score_system = ScoreSystem.new()
	boss_hp = boss_max_hp
	total_echo_damage = 0.0
	total_normal_damage = 0.0
	total_heal = 0.0
	total_shield = 0.0
	corruption_count = 0
	corruption_broken = 0

func _same_lanes(left: Array, right: Array) -> bool:
	var normalized_left := left.duplicate()
	var normalized_right := right.duplicate()
	normalized_left.sort()
	normalized_right.sort()
	return normalized_left == normalized_right
