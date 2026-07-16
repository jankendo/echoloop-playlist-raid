extends Control
## Lightweight waveform / beat / downbeat inspector for local SongPacks.

var analysis: Dictionary = {}

func configure(value: Dictionary) -> void:
	analysis = value.duplicate(true)
	custom_minimum_size = Vector2(900, 220)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b1323"), true)
	var peaks: Array = analysis.get("waveform_peaks", [])
	var beats: Array = analysis.get("beats_ms", [])
	var downbeats: Array = analysis.get("downbeats_ms", [])
	var duration := maxf(1.0, float(analysis.get("duration_ms", 1.0)))
	var mid_y := size.y * 0.54
	if peaks.size() > 1:
		var points := PackedVector2Array()
		for index in range(peaks.size()):
			var x := float(index) / float(peaks.size() - 1) * size.x
			var amplitude := float(peaks[index]) * size.y * 0.38
			points.append(Vector2(x, mid_y - amplitude))
		if points.size() > 1:
			draw_polyline(points, Color("#80d7ff"), 2.0, true)
	for value in beats:
		var x := float(value) / duration * size.x
		draw_line(Vector2(x, 20), Vector2(x, size.y - 20), Color("#6686a8", 0.42), 1.0)
	for value in downbeats:
		var x := float(value) / duration * size.x
		draw_line(Vector2(x, 10), Vector2(x, size.y - 10), Color("#ffcf5a", 0.9), 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(14, 24), "波形  拍線(細)  小節頭(太)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#dce9ff"))
