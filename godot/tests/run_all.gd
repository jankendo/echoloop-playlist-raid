extends SceneTree
## Dependency-free headless regression runner for core gameplay contracts.

var failures: Array[String] = []

func _init() -> void:
	_test_timing()
	_test_score()
	_test_chart()
	_test_echo()
	_test_corruption()
	_test_session()
	if failures.is_empty():
		print("ECHOLOOP Godot tests: PASS (6 suites)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ECHOLOOP Godot tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _test_timing() -> void:
	var judge = load("res://scripts/core/timing_judge.gd")
	_check(judge.classify(0.0) == "CRITICAL", "timing zero")
	_check(judge.classify(22.0) == "CRITICAL", "critical boundary")
	_check(judge.classify(22.1) == "PERFECT", "critical after boundary")
	_check(judge.classify(-45.0) == "PERFECT", "perfect early boundary")
	_check(judge.classify(80.1) == "GOOD", "great after boundary")
	_check(judge.classify(120.1) == "MISS", "miss after boundary")
	_check(judge.classify(130.0, 20.0) == "GOOD", "assist width")

	var clock = load("res://autoload/audio_clock.gd").new()
	clock.configure(10.0, 25.0, 1000.0)
	clock.start()
	clock.tick(0.25)
	clock.tick(-1.0)
	_check(clock.song_time_ms() >= 250.0, "fake clock monotonic")
	_check(is_equal_approx(clock.visual_time_ms(), clock.song_time_ms() + 25.0), "visual offset separated")
	clock.pause()
	var paused: float = clock.song_time_ms()
	clock.tick(1.0)
	_check(is_equal_approx(clock.song_time_ms(), paused), "clock pause")
	clock.resume()
	clock.seek(800.0)
	_check(is_equal_approx(clock.song_time_ms(), 800.0), "clock seek")

func _test_score() -> void:
	var score = load("res://scripts/core/score_system.gd").new()
	score.register_note([0])
	score.apply_judgement("CRITICAL", -1.0, [0])
	score.apply_judgement("MISS", 121.0, [0])
	_check(score.max_combo == 1, "score max combo")
	_check(score.combo == 0, "miss resets combo")
	_check(score.counts.CRITICAL == 1 and score.counts.MISS == 1, "score counts")
	_check(score.rank() == "C" or score.rank() == "D", "rank exists")

func _test_chart() -> void:
	var loader = load("res://scripts/core/chart_loader.gd").new()
	var chart: Dictionary = loader.load_chart("res://data/test_chart.json")
	_check(not chart.is_empty(), "fixture chart loads: " + loader.last_error)
	_check(chart.notes.size() >= 50, "fixture chart has notes")
	var invalid := chart.duplicate(true)
	invalid.notes[0].time_ms = -1
	_check(not loader.validate(invalid), "invalid chart rejected")

func _test_echo() -> void:
	var echo = load("res://scripts/core/echo_system.gd").new()
	echo.record_success(0, 0.0, 1000.0, 0, "tap", "n1", "PERFECT")
	echo.finalize_phrase(0)
	_check(echo.active_echoes.size() == 1, "echo created at phrase end")
	_check(echo.replay_events(0, 2.0, 0.0).is_empty(), "echo does not replay in source phrase")
	_check(echo.replay_events(1, 2.0, 8000.0).size() == 1, "echo replays next phrase")
	for index in range(1, 5):
		echo.record_success(index, index * 8000.0, index * 8000.0, index % 4, "tap", "n%d" % index, "GREAT")
		echo.finalize_phrase(index)
	_check(echo.active_echoes.size() <= 3, "echo cap")
	_check(echo.chorus_memory > 0.0, "chorus memory")

func _test_corruption() -> void:
	var echo = load("res://scripts/core/echo_system.gd").new()
	echo.record_miss(0, 3.5, 2, "miss-1")
	_check(echo.corruption_for_phrase(1).size() == 1, "corruption next phrase")
	var item: Dictionary = echo.corruption_for_phrase(1)[0]
	echo.resolve_corruption(item, false)
	_check(echo.corruption_for_phrase(1).is_empty(), "failed corruption is resolved")
	_check(echo.corruption_queue.size() == 1, "corruption does not multiply")

func _test_session() -> void:
	var loader = load("res://scripts/core/chart_loader.gd").new()
	var chart: Dictionary = loader.load_chart("res://data/test_chart.json")
	var session = load("res://scripts/core/game_session.gd").new()
	_check(session.setup(chart), "session setup")
	var first: Dictionary = chart.notes[0]
	var result: Dictionary = session.handle_lane_input(int(first.lane), float(first.time_ms))
	_check(str(result.judgement) != "GHOST", "known note judged")
	session.advance(8001.0)
	_check(session.current_phrase == 1, "phrase advances")
	_check(session.echo_system.active_echoes.size() >= 1, "session finalizes echo")
	_check(session.result_snapshot().has("integrity"), "session result snapshot")
