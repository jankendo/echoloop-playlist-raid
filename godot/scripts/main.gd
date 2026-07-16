extends Control
## Screen composition and input forwarding for the Phase 0–2 slice.

const GAMEPLAY_VIEW_SCRIPT := preload("res://scripts/ui/gameplay_view.gd")

var mode := "menu"
var paused := false
var capture_lane := -1
var session: GameSession
var gameplay_view: Node2D
var audio_player: AudioStreamPlayer
var content: Control
var hud_label: Label
var feedback_label: Label
var page_title: Label
var settings_service: Node
var audio_clock: Node
var input_timing: Node
var app_state: Node
var version_service: Node

func _ready() -> void:
	set_process_input(true)
	settings_service = get_node_or_null("/root/SettingsService")
	audio_clock = get_node_or_null("/root/AudioClock")
	input_timing = get_node_or_null("/root/InputTiming")
	app_state = get_node_or_null("/root/AppState")
	version_service = get_node_or_null("/root/VersionService")
	var job_service := get_node_or_null("/root/JobService")
	if job_service != null:
		job_service.job_updated.connect(_on_job_updated)
	_show_menu()

func _process(delta: float) -> void:
	if mode != "gameplay" or session == null or paused:
		return
	if audio_player != null and audio_player.playing and audio_clock != null and not audio_clock.is_fake_mode():
		audio_clock.update_from_player()
	else:
		if audio_clock != null:
			audio_clock.tick(delta)
	if audio_clock != null:
		session.advance(audio_clock.song_time_ms())
	if hud_label != null:
		var result := session.result_snapshot()
		hud_label.text = "SCORE %07d    COMBO %03d    ACC %.2f%%    CORE %d%%    INTEGRITY %d" % [int(result.score), int(result.combo), float(result.accuracy), int(session.boss_hp), int(session.integrity)]
	if session.is_finished():
		_show_results()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.is_echo():
		return
	var key := int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	if capture_lane >= 0 and event.pressed:
		if _set_lane_key(capture_lane, key):
			capture_lane = -1
			_show_settings()
		return
	if mode == "gameplay":
		if key == KEY_ESCAPE and event.pressed:
			_toggle_pause()
			return
		if key == KEY_R and event.pressed:
			_start_game()
			return
		var lane := _lane_for_key(key)
		if lane >= 0:
			var time_ms: float = audio_clock.song_time_ms() if audio_clock != null else 0.0
			if event.pressed:
				if not session.handle_corruption_input(lane, time_ms):
					var result := session.handle_lane_input(lane, time_ms, true)
					_on_judgement(result)
			else:
				_on_judgement(session.handle_lane_input(lane, time_ms, false))

func _show_menu() -> void:
	mode = "menu"
	paused = false
	_clear_screen()
	var box := _make_column(Vector2(120, 120), 640)
	_add_title(box, "ECHOLOOP: PLAYLIST RAID", "過去の自分と共演する、ローカル完結のリズム・ローグライト")
	_add_spacer(box, 26)
	_add_button(box, "PLAY TEST SONG", "合成テスト曲でVertical Sliceを開始", _start_game)
	_add_button(box, "SETTINGS", "キー、判定アシスト、表示を調整", _show_settings)
	_add_button(box, "DIAGNOSTICS", "ローカルPythonワーカーと環境を確認", _show_diagnostics)
	_add_button(box, "EXIT", "ゲームを終了", func() -> void: get_tree().quit())
	_add_spacer(box, 30)
	var note := Label.new()
	note.text = "D / F / J / K でレーン入力　　Esc: 一時停止　　R: リトライ"
	note.add_theme_color_override("font_color", Color("#8fa7c7"))
	note.add_theme_font_size_override("font_size", 16)
	box.add_child(note)

func _start_game() -> void:
	var loader := ChartLoader.new()
	var chart := loader.load_chart("res://data/test_chart.json")
	if chart.is_empty():
		_show_error("譜面を読み込めませんでした: " + loader.last_error)
		return
	mode = "gameplay"
	paused = false
	capture_lane = -1
	_clear_screen()
	session = GameSession.new()
	session.setup(chart, float(_setting("judgement_assist_ms", 0.0)))
	session.judgement_applied.connect(_on_judgement)
	session.corruption_spawned.connect(func(_item: Dictionary) -> void:
		if feedback_label != null:
			feedback_label.text = "CORRUPTION — ミスが次のフレーズに戻ってきた"
	)
	session.echo_triggered.connect(func(event: Dictionary) -> void:
		if feedback_label != null and str(event.get("effect", "")) == "PULSE_DAMAGE":
			feedback_label.text = "ECHO PULSE — 過去の自分が攻撃した"
	)
	gameplay_view = GAMEPLAY_VIEW_SCRIPT.new()
	gameplay_view.configure(session)
	add_child(gameplay_view)
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = load("res://audio/test_song.wav")
	add_child(audio_player)
	if audio_clock != null:
		audio_clock.configure(float(_setting("audio_offset_ms", 0.0)), float(_setting("visual_offset_ms", 0.0)), float(chart.duration_ms))
		audio_clock.start()
		audio_clock.set_fake_mode(false)
	if audio_player.stream != null:
		if audio_clock != null:
			audio_clock.attach_player(audio_player)
		audio_player.play()
	var top := _make_topbar()
	page_title = top.get_node("Title")
	page_title.text = "SYNTHETIC CRYSTAL PULSE  •  120 BPM  •  ECHOLOOP ONLINE"
	hud_label = top.get_node("Hud")
	feedback_label = top.get_node("Feedback")
	feedback_label.text = "入力を待っています — D F J K"

func _show_results() -> void:
	if mode == "results":
		return
	mode = "results"
	if audio_clock != null:
		audio_clock.stop()
	if audio_player != null:
		audio_player.stop()
	_clear_screen()
	var result := session.result_snapshot()
	if app_state != null:
		app_state.last_result = result
	var box := _make_column(Vector2(140, 100), 760)
	_add_title(box, "RESULTS / ECHO REPORT", "曲の最後まで到達しました。ここからすぐに再挑戦できます。")
	var stats := Label.new()
	stats.text = "RANK  %s\nSCORE %07d\nACCURACY  %.2f%%\nMAX COMBO  %d\n\nCRITICAL %d   PERFECT %d   GREAT %d   GOOD %d   MISS %d\nECHO DAMAGE %.1f   NORMAL DAMAGE %.1f\nHEALING %.1f   SHIELD %.1f\nCORRUPTION %d / BROKEN %d\n\n%s" % [str(result.rank), int(result.score), float(result.accuracy), int(result.max_combo), int(result.counts.CRITICAL), int(result.counts.PERFECT), int(result.counts.GREAT), int(result.counts.GOOD), int(result.counts.MISS), float(result.echo_damage), float(result.normal_damage), float(result.healing), float(result.shield_gained), int(result.corruptions), int(result.corruption_broken), "ASSIST ENABLED" if bool(result.assist) else "STANDARD TIMING"]
	stats.add_theme_color_override("font_color", Color("#dce9ff"))
	stats.add_theme_font_size_override("font_size", 20)
	box.add_child(stats)
	_add_spacer(box, 24)
	_add_button(box, "RETRY", "2秒以内にテスト曲を再開", _start_game)
	_add_button(box, "MAIN MENU", "曲選択へ戻る", _show_menu)

func _show_settings() -> void:
	mode = "settings"
	_clear_screen()
	var box := _make_column(Vector2(140, 100), 760)
	_add_title(box, "SETTINGS", "判定と表示を自分に合わせて調整できます。変更は保存されます。")
	var assist := Label.new()
	assist.name = "Assist"
	assist.text = "判定アシスト: %d ms" % int(_setting("judgement_assist_ms", 0))
	assist.add_theme_font_size_override("font_size", 19)
	box.add_child(assist)
	_add_button(box, "ASSIST OFF", "標準 ±22 / ±45 / ±80 / ±120 ms", func() -> void: _set_setting("judgement_assist_ms", 0); _show_settings())
	_add_button(box, "ASSIST +20ms", "初心者向けの余裕を追加", func() -> void: _set_setting("judgement_assist_ms", 20); _show_settings())
	_add_button(box, "ASSIST +40ms", "ワイド判定で練習", func() -> void: _set_setting("judgement_assist_ms", 40); _show_settings())
	_add_spacer(box, 12)
	var keys := Label.new()
	keys.text = "レーンキー:  1 [%s]   2 [%s]   3 [%s]   4 [%s]" % [_key_name(0), _key_name(1), _key_name(2), _key_name(3)]
	keys.add_theme_font_size_override("font_size", 18)
	box.add_child(keys)
	for lane in range(4):
		var target := lane
		_add_button(box, "CHANGE LANE %d" % (lane + 1), "押してから割り当てたいキーを入力", func() -> void: capture_lane = target; _show_settings())
	_add_button(box, "SAVE SETTINGS", "設定をuser://へアトミック保存", func() -> void: _save_settings(); _show_menu())
	_add_button(box, "BACK", "保存せず戻る", _show_menu)
	if capture_lane >= 0:
		var capture := Label.new()
		capture.text = "LANE %d の新しいキーを押してください" % (capture_lane + 1)
		capture.add_theme_color_override("font_color", Color("#ffcf5a"))
		box.add_child(capture)

func _show_diagnostics() -> void:
	mode = "diagnostics"
	_clear_screen()
	var box := _make_column(Vector2(140, 120), 820)
	_add_title(box, "DIAGNOSTICS", "外部通信なし。ローカルの実行環境とワーカーだけを確認します。")
	var info := Label.new()
	var product_version := "0.1.0-phase-0-2" if version_service == null else str(version_service.PRODUCT_VERSION)
	info.text = "Product: %s\nGodot: %s\nUser data: %s\nTest audio: res://audio/test_song.wav\nChart: res://data/test_chart.json" % [product_version, "4.7.1 Standard", "user://"]
	info.add_theme_font_size_override("font_size", 17)
	info.add_theme_color_override("font_color", Color("#c4d4ee"))
	box.add_child(info)
	var status := Label.new()
	status.name = "Status"
	status.text = "Worker: " + _job_status_message()
	status.add_theme_font_size_override("font_size", 18)
	box.add_child(status)
	_add_button(box, "RUN LOCAL HEALTH CHECK", "Python workerを非同期起動", _run_health_check)
	_add_button(box, "PLAY TEST TONE", "合成音源が読み込めることを確認", func() -> void: _start_audio_probe(status))
	_add_button(box, "BACK", "メインメニューへ戻る", _show_menu)

func _start_audio_probe(status: Label) -> void:
	var probe := AudioStreamPlayer.new()
	probe.stream = load("res://audio/test_song.wav")
	add_child(probe)
	if probe.stream == null:
		status.text = "Audio: failed to load test_song.wav"
	else:
		probe.play()
		status.text = "Audio: synthetic WAV playback started"

func _run_health_check() -> void:
	var job_service := get_node_or_null("/root/JobService")
	if job_service == null:
		_show_diagnostics()
		return
	job_service.start_health_check()

func _job_status_message() -> String:
	var job_service := get_node_or_null("/root/JobService")
	if job_service == null:
		return "service unavailable"
	return str(job_service.last_status.get("message", "idle"))

func _toggle_pause() -> void:
	paused = not paused
	if paused:
		if audio_clock != null:
			audio_clock.pause()
		feedback_label.text = "PAUSED — Escで再開 / Rでリトライ / D F J K"
	else:
		if audio_clock != null:
			audio_clock.resume()
		feedback_label.text = "RESUMED — D F J K"

func _on_judgement(result: Dictionary) -> void:
	if gameplay_view != null:
		gameplay_view.set_judgement(str(result.get("judgement", "")))
	if feedback_label != null:
		var judgement := str(result.get("judgement", ""))
		feedback_label.text = "%s   %+.1f ms" % [judgement, float(result.get("delta_ms", 0.0))] if judgement != "GHOST" else "GHOST TAP — コンボとレゾナンスが減少"

func _on_job_updated(status: Dictionary) -> void:
	if mode != "diagnostics":
		return
	var label := get_node_or_null("Content/Column/Status") as Label
	if label != null:
		label.text = "Worker: " + str(status.get("state", "")) + " — " + str(status.get("message", ""))

func _show_error(message: String) -> void:
	_clear_screen()
	var box := _make_column(Vector2(140, 160), 800)
	_add_title(box, "ERROR", message)
	_add_button(box, "BACK", "メインメニューへ戻る", _show_menu)

func _clear_screen() -> void:
	for child in get_children():
		if child != audio_player:
			child.queue_free()
	content = null
	hud_label = null
	feedback_label = null
	page_title = null

func _make_column(position: Vector2, width: float) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.name = "Column"
	panel.position = position
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_constant_override("separation", 12)
	content = Control.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	content.add_child(panel)
	return panel

func _make_topbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.position = Vector2(42, 28)
	bar.custom_minimum_size = Vector2(1800, 60)
	bar.add_theme_constant_override("separation", 24)
	content = Control.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	content.add_child(bar)
	var title := Label.new()
	title.name = "Title"
	title.custom_minimum_size = Vector2(700, 30)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#8edbff"))
	bar.add_child(title)
	var hud := Label.new()
	hud.name = "Hud"
	hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_color_override("font_color", Color("#dce9ff"))
	bar.add_child(hud)
	var feedback := Label.new()
	feedback.name = "Feedback"
	feedback.custom_minimum_size = Vector2(460, 30)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feedback.add_theme_font_size_override("font_size", 17)
	feedback.add_theme_color_override("font_color", Color("#ffcf5a"))
	bar.add_child(feedback)
	return bar

func _add_title(box: VBoxContainer, title_text: String, subtitle: String) -> void:
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#b9e9ff"))
	box.add_child(title)
	var sub := Label.new()
	sub.text = subtitle
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color("#8fa7c7"))
	box.add_child(sub)

func _add_button(box: VBoxContainer, label_text: String, hint: String, action: Callable) -> void:
	var button := Button.new()
	button.text = "%s    %s" % [label_text, hint]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(640, 52)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("#dce9ff"))
	button.pressed.connect(action)
	box.add_child(button)

func _add_spacer(box: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, height)
	box.add_child(spacer)

func _key_name(lane: int) -> String:
	var keys: Array = input_timing.lane_keys if input_timing != null else [KEY_D, KEY_F, KEY_J, KEY_K]
	return OS.get_keycode_string(int(keys[lane])) if lane < keys.size() else "?"

func _setting(key: String, fallback: Variant) -> Variant:
	return settings_service.get_value(key, fallback) if settings_service != null else fallback

func _set_setting(key: String, value: Variant) -> void:
	if settings_service != null:
		settings_service.set_value(key, value)

func _save_settings() -> void:
	if settings_service != null:
		settings_service.save_values()

func _lane_for_key(keycode: int) -> int:
	if input_timing != null:
		return input_timing.lane_for_key(keycode)
	return [KEY_D, KEY_F, KEY_J, KEY_K].find(keycode)

func _set_lane_key(lane: int, keycode: int) -> bool:
	return input_timing.set_lane_key(lane, keycode) if input_timing != null else false
