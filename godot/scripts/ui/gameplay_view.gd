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
	var left := size.x * 0.18
	var lane_width := size.x * 0.16
	var hit_y := size.y * 0.78
	for lane in range(4):
		var x := left + lane * lane_width
		var color: Color = LANE_COLORS[lane]
		draw_rect(Rect2(x, 100, lane_width - 8, hit_y - 100), Color(color, 0.035), true)
		draw_line(Vector2(x, 100), Vector2(x, hit_y + 24), Color(color, 0.30), 2.0)
		draw_line(Vector2(x + lane_width - 8, 100), Vector2(x + lane_width - 8, hit_y + 24), Color(color, 0.30), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(x + lane_width * 0.5 - 10, hit_y + 58), LANE_SYMBOLS[lane], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)
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
		var lanes: Array = note.get("lanes", [note.lane])
		for lane in lanes:
			_draw_note(int(lane), note_y, str(note.type), bool(note.get("accent", false)), left, lane_width)
		if str(note.type) == "hold":
			var end_y := hit_y - (float(note.time_ms) + float(note.duration_ms) - current_time_ms) * 0.32 * speed
			var lane := int(note.lane)
			var x := left + lane * lane_width + lane_width * 0.5 - 5.0
			draw_line(Vector2(x, note_y), Vector2(x, end_y), Color(LANE_COLORS[lane], 0.35), 10.0)
	for item in session.echo_system.corruption_for_phrase(session.current_phrase):
		if bool(item.get("resolved", false)):
			continue
		var phrase: Dictionary = session.chart.phrases[session.current_phrase]
		var target := float(phrase.start_ms) + float(item.beat_phase) * 500.0
		var y := hit_y - (target - current_time_ms) * 0.32 * speed
		if y > 60.0 and y < size.y:
			var cx := left + int(item.lane) * lane_width + lane_width * 0.5
			draw_arc(Vector2(cx, y), 17.0 + corruption_flash * 8.0, 0.0, TAU, 24, Color("#ff406d"), 4.0)
			draw_line(Vector2(cx - 10, y - 10), Vector2(cx + 10, y + 10), Color("#ff406d"), 3.0)
			draw_line(Vector2(cx + 10, y - 10), Vector2(cx - 10, y + 10), Color("#ff406d"), 3.0)
	_draw_core(size)
	_draw_echoes(size)
	if judgement_flash > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 75, size.y * 0.87), last_judgement, HORIZONTAL_ALIGNMENT_CENTER, 150, 30, Color(1.0, 1.0, 1.0, judgement_flash / 0.22))

func _draw_note(lane: int, y: float, note_type: String, accent: bool, left: float, lane_width: float) -> void:
	var x := left + lane * lane_width + lane_width * 0.5
	var color: Color = LANE_COLORS[lane]
	var radius := 18.0 if not accent else 23.0
	if note_type == "chord":
		draw_arc(Vector2(x, y), radius, 0.0, TAU, 24, Color(color, 0.82), 5.0)
		draw_circle(Vector2(x, y), radius * 0.52, Color(color, 0.22))
	else:
		draw_rect(Rect2(x - radius, y - 10, radius * 2.0, 20), Color(color, 0.82), true)
		draw_line(Vector2(x - radius, y - 10), Vector2(x + radius, y - 10), Color.WHITE, 2.0)

func _draw_core(size: Vector2) -> void:
	var center := Vector2(size.x * 0.92, size.y * 0.34)
	var hp_ratio := session.boss_hp / maxf(1.0, session.boss_max_hp)
	draw_circle(center, 72.0, Color(0.08, 0.25, 0.48, 0.18))
	draw_arc(center, 58.0 + sin(current_time_ms * 0.004) * 3.0, 0.0, TAU, 32, Color("#65dbff"), 5.0)
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
