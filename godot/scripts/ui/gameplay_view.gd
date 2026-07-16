extends Node2D
## Procedural neon lane renderer. It owns no judgement state.

var session: GameSession
var current_time_ms: float = 0.0
var status_text: String = ""
var last_judgement: String = ""
var judgement_flash: float = 0.0
var corruption_flash: float = 0.0

const LANE_COLORS := [Color("#ff5e7a"), Color("#ffcf5a"), Color("#58d6ff"), Color("#b68cff")]
const LANE_SYMBOLS := ["◈", "▣", "✦", "△"]
const DUO_COLORS := [Color("#55d8ff"), Color("#c783ff")]
const DUO_LABELS := ["F  / LEFT", "J  / RIGHT"]

func configure(value: GameSession) -> void:
	session = value

func set_judgement(value: String) -> void:
	last_judgement = value
	judgement_flash = 0.22

func set_status(value: String) -> void:
	status_text = value

func _process(delta: float) -> void:
	if session != null:
		current_time_ms = session.current_time_ms
	judgement_flash = maxf(0.0, judgement_flash - delta)
	corruption_flash = maxf(0.0, corruption_flash - delta)
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	var dim := float(_setting("background_dim", 0.72))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.035, 0.075, 1.0))
	for band in range(8):
		var y := 90.0 + band * 92.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.11, 0.16, 0.30, 0.16 * (1.0 - dim * 0.4)), 1.0)
	var duo_mode := session != null and session.gameplay_mode == "duo_2key"
	var lane_count := 2 if duo_mode else 4
	var left := size.x * (0.24 if duo_mode else 0.18)
	var lane_width := size.x * (0.25 if duo_mode else 0.16)
	var hit_y := size.y * 0.78
	for lane in range(lane_count):
		var x := left + lane * lane_width
		var color: Color = DUO_COLORS[lane] if duo_mode else LANE_COLORS[lane]
		draw_rect(Rect2(x, 100, lane_width - 8, hit_y - 100), Color(color, 0.035), true)
		var border_alpha := 0.65 if bool(_setting("high_contrast", false)) else 0.30
		draw_line(Vector2(x, 100), Vector2(x, hit_y + 24), Color(color, border_alpha), 2.0)
		draw_line(Vector2(x + lane_width - 8, 100), Vector2(x + lane_width - 8, hit_y + 24), Color(color, border_alpha), 2.0)
		var lane_label: String = DUO_LABELS[lane] if duo_mode else "%s  %s" % [["D", "F", "J", "K"][lane], LANE_SYMBOLS[lane]]
		draw_string(ThemeDB.fallback_font, Vector2(x + lane_width * 0.5 - 55, hit_y + 58), lane_label, HORIZONTAL_ALIGNMENT_CENTER, 110, 18 if duo_mode else 16, color)
		draw_line(Vector2(x + 10, hit_y), Vector2(x + lane_width - 18, hit_y), Color(color, 0.9), 4.0)
	if session == null:
		return
	var speed := float(_setting("note_speed", 1.0))
	for note in session.notes:
		if session.judged.has(note.id):
			continue
		var time_delta := float(note.time_ms) - current_time_ms
		var note_y := hit_y - time_delta * 0.32 * speed
		if note_y < 70.0 or note_y > size.y + 60.0:
			continue
		var input_lanes: Array = note.get("input_lanes", note.get("lanes", [note.lane]))
		var semantic_lanes: Array = note.get("semantic_lanes", [note.get("semantic_lane", 0)])
		for lane_index in range(input_lanes.size()):
			var semantic_lane := int(semantic_lanes[min(lane_index, semantic_lanes.size() - 1)])
			_draw_note(int(input_lanes[lane_index]), note_y, str(note.type), bool(note.get("accent", false)), left, lane_width, semantic_lane)
		if str(note.type) == "hold":
			var end_y := hit_y - (float(note.time_ms) + float(note.duration_ms) - current_time_ms) * 0.32 * speed
			var lane := int(note.get("input_lane", note.get("lane", 0)))
			var x := left + lane * lane_width + lane_width * 0.5 - 5.0
			var hold_color: Color = DUO_COLORS[lane] if duo_mode else LANE_COLORS[clampi(lane, 0, 3)]
			draw_line(Vector2(x, note_y), Vector2(x, end_y), Color(hold_color, 0.35), 10.0)
	for item in session.echo_system.corruption_for_phrase(session.current_phrase):
		if bool(item.get("resolved", false)):
			continue
		var phrase: Dictionary = session.chart.phrases[session.current_phrase]
		var beat_map = session.chart.get("beat_map")
		var target_phase := float(item.get("beat_phase", 0.0))
		var source_count := float(item.get("source_phrase_beat_count", 0.0))
		var target_count := float(phrase.get("beat_count", 16.0))
		if source_count > 0.0 and not is_equal_approx(source_count, target_count):
			target_phase = float(item.get("normalized_phase", 0.0)) * target_count
		var target: float = float(beat_map.phrase_relative_to_time(session.current_phrase, target_phase))
		var y := hit_y - (target - current_time_ms) * 0.32 * speed
		if y > 60.0 and y < size.y:
			var cx := left + int(item.get("input_lane", item.get("lane", 0))) * lane_width + lane_width * 0.5
			draw_arc(Vector2(cx, y), 17.0 + corruption_flash * 8.0, 0.0, TAU, 24, Color("#ff406d"), 4.0)
			draw_line(Vector2(cx - 10, y - 10), Vector2(cx + 10, y + 10), Color("#ff406d"), 3.0)
			draw_line(Vector2(cx + 10, y - 10), Vector2(cx - 10, y + 10), Color("#ff406d"), 3.0)
	_draw_core(size)
	_draw_echoes(size)
	if judgement_flash > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 75, size.y * 0.87), last_judgement, HORIZONTAL_ALIGNMENT_CENTER, 150, 30, Color(1.0, 1.0, 1.0, judgement_flash / 0.22))

func _draw_note(lane: int, y: float, note_type: String, accent: bool, left: float, lane_width: float, semantic_lane: int = 0) -> void:
	var x := left + lane * lane_width + lane_width * 0.5
	var duo_mode := session != null and session.gameplay_mode == "duo_2key"
	var color: Color = LANE_COLORS[clampi(semantic_lane, 0, 3)]
	if duo_mode:
		color = DUO_COLORS[clampi(lane, 0, 1)]
	var radius := 18.0 if not accent else 23.0
	if note_type == "chord":
		draw_arc(Vector2(x, y), radius, 0.0, TAU, 24, Color(color, 0.82), 5.0)
		draw_circle(Vector2(x, y), radius * 0.52, Color(color, 0.22))
	else:
		draw_rect(Rect2(x - radius, y - 10, radius * 2.0, 20), Color(color, 0.82), true)
		draw_line(Vector2(x - radius, y - 10), Vector2(x + radius, y - 10), Color.WHITE, 2.0)
	if duo_mode:
		draw_string(ThemeDB.fallback_font, Vector2(x - radius, y + 6), LANE_SYMBOLS[clampi(semantic_lane, 0, 3)], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 13, Color.WHITE)

func _draw_core(size: Vector2) -> void:
	var center := Vector2(size.x * 0.92, size.y * 0.34)
	var hp_ratio := session.boss_hp / maxf(1.0, session.boss_max_hp)
	draw_circle(center, 72.0, Color(0.08, 0.25, 0.48, 0.18))
	var pulse := 0.0 if bool(_setting("reduced_motion", false)) else sin(current_time_ms * 0.004) * 3.0
	draw_arc(center, 58.0 + pulse, 0.0, TAU, 32, Color("#65dbff"), 5.0)
	draw_circle(center, 30.0, Color(0.25, 0.65, 1.0, 0.18 + hp_ratio * 0.28))
	draw_string(ThemeDB.fallback_font, center + Vector2(-55, 105), "LIFT CORE", HORIZONTAL_ALIGNMENT_CENTER, 110, 16, Color("#87c7ff"))
	draw_rect(Rect2(center.x - 70, center.y + 118, 140, 8), Color("#1b2b4b"), true)
	draw_rect(Rect2(center.x - 70, center.y + 118, 140 * hp_ratio, 8), Color("#65dbff"), true)

func _draw_echoes(size: Vector2) -> void:
	var index := 0
	for echo in session.echo_system.active_echoes:
		var alpha := 0.32 - index * 0.06
		var center := Vector2(size.x * 0.08 + index * 44.0, size.y * 0.35)
		draw_arc(center, 28.0 + sin(current_time_ms * 0.003 + index) * 4.0, 0.0, TAU, 24, Color(0.35, 0.85, 1.0, alpha), 3.0)
		draw_line(center + Vector2(-20, 18), center + Vector2(20, -18), Color(0.55, 0.90, 1.0, alpha), 2.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-24, 50), "ECHO %d" % (index + 1), HORIZONTAL_ALIGNMENT_CENTER, 48, 11, Color(0.7, 0.9, 1.0, alpha + 0.1))
		index += 1
	if session.echo_system.chorus_memory > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.03, size.y * 0.64), "CHORUS MEMORY %.1f" % session.echo_system.chorus_memory, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#d5a6ff"))

func _setting(key: String, fallback: Variant) -> Variant:
	var service := get_node_or_null("/root/SettingsService")
	return service.get_value(key, fallback) if service != null else fallback
