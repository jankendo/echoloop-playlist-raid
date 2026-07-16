extends Control
## Screen composition and input forwarding for the offline Phase 3 slice.

const GAMEPLAY_VIEW_SCRIPT := preload("res://scripts/ui/gameplay_view.gd")
const BEAT_CHECK_VIEW_SCRIPT := preload("res://scripts/ui/beat_check_view.gd")

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
var import_source_path := ""
var import_column: VBoxContainer
var import_selected_label: Label
var import_status_label: Label
var import_action_button: Button
var imported_song_uuid := ""
var youtube_url_input: LineEdit
var youtube_rights_check: CheckBox
var youtube_status_label: Label
var youtube_search_input: LineEdit
var youtube_entries_list: ItemList
var youtube_entries: Array = []
var youtube_sort_option: OptionButton

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
	_add_button(box, "IMPORT LOCAL AUDIO", "PC内のWAV / MP3 / M4A / OGG / FLACを解析", _show_import_local_audio)
	_add_button(box, "IMPORT YOUTUBE", "権利確認済みのYouTube音源を取り込む", _show_youtube_import)
	_add_button(box, "SONG LIBRARY", "登録曲を選択、拍確認、再生成", _show_song_library)
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
	var stream: AudioStream = load("res://audio/test_song.wav")
	_start_chart_game(chart, stream, "SYNTHETIC CRYSTAL PULSE  •  120 BPM  •  ECHOLOOP ONLINE")

func _start_local_game(song_uuid: String) -> void:
	var library := get_node_or_null("/root/SongLibrary")
	if library == null:
		_show_error("登録曲ライブラリを読み込めませんでした")
		return
	var chart_path: String = library.chart_path(song_uuid, "normal")
	var loader := ChartLoader.new()
	var chart := loader.load_chart(chart_path)
	if chart.is_empty():
		_show_error("登録曲の譜面を読み込めませんでした: " + loader.last_error)
		return
	var playback_path: String = library.playback_path(song_uuid)
	var stream: AudioStream = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(playback_path))
	if stream == null:
		_show_error("登録曲の再生音源を読み込めませんでした。SongPackを再解析してください。")
		return
	_start_chart_game(chart, stream, "LOCAL SONG  •  %s" % song_uuid)

func _start_chart_game(chart: Dictionary, stream: AudioStream, title_text: String) -> void:
	mode = "gameplay"
	paused = false
	capture_lane = -1
	if audio_player != null:
		audio_player.stop()
		audio_player.queue_free()
		audio_player = null
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
	audio_player.stream = stream
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
	page_title.text = title_text
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

func _show_import_local_audio() -> void:
	mode = "import"
	import_source_path = ""
	imported_song_uuid = ""
	import_action_button = null
	_clear_screen()
	var box := _make_column(Vector2(120, 90), 900)
	import_column = box
	_add_title(box, "IMPORT LOCAL AUDIO", "音源はPC内だけで処理します。元ファイルは変更せず、ネットワークへ送信しません。")
	var help := Label.new()
	help.text = "対応形式: WAV / MP3 / M4A / AAC / OGG / OPUS / FLAC\n最短30秒、最長15分、最大1GB。URLや動画ストリームは登録できません。"
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color("#c4d4ee"))
	box.add_child(help)
	var selected := Label.new()
	selected.name = "Selected"
	selected.text = "音源がまだ選択されていません"
	selected.add_theme_font_size_override("font_size", 18)
	selected.add_theme_color_override("font_color", Color("#8edbff"))
	box.add_child(selected)
	import_selected_label = selected
	import_status_label = Label.new()
	import_status_label.name = "ImportStatus"
	import_status_label.text = "次へ: ファイルを選択してください"
	import_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	import_status_label.add_theme_font_size_override("font_size", 18)
	box.add_child(import_status_label)
	_add_button(box, "CHOOSE AUDIO FILE", "FileDialogでPC内の音源を選択", _choose_import_file)
	_add_button(box, "CANCEL JOB", "解析中の処理を安全に停止", _cancel_import_job)
	_add_button(box, "BACK", "メインメニューへ戻る", _show_menu)

func _choose_import_file() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "ローカル音源を選択"
	dialog.filters = PackedStringArray(["*.wav, *.mp3, *.m4a, *.aac, *.ogg, *.opus, *.flac ; Audio files"])
	dialog.file_selected.connect(_on_import_file_selected)
	add_child(dialog)
	dialog.popup_centered_ratio(0.78)

func _on_import_file_selected(path: String) -> void:
	import_source_path = path
	if import_selected_label != null:
		import_selected_label.text = "選択中: " + path.get_file()
	var job_service := get_node_or_null("/root/JobService")
	if job_service == null:
		if import_status_label != null:
			import_status_label.text = "Python workerが利用できません。診断画面で環境を確認してください。"
		return
	job_service.start_local_audio_probe(path)
	if import_status_label != null:
		import_status_label.text = "音源を確認しています…"

func _cancel_import_job() -> void:
	var job_service := get_node_or_null("/root/JobService")
	if job_service != null:
		job_service.cancel_current_job()
	if import_status_label != null:
		import_status_label.text = "キャンセルを依頼しました。処理の終了を待っています。"

func _start_import_analysis() -> void:
	if import_source_path.is_empty():
		return
	var job_service := get_node_or_null("/root/JobService")
	if job_service != null:
		job_service.start_local_audio_analysis(import_source_path)
	if import_status_label != null:
		import_status_label.text = "音源を解析しています。画面は操作できます。"

func _show_youtube_import() -> void:
	mode = "youtube"
	_clear_screen()
	var box := _make_column(Vector2(110, 80), 1100)
	_add_title(box, "IMPORT YOUTUBE", "URLを解析してから、利用権限を確認した音声だけをSongPackへ保存します。Cookieやログイン情報は使いません。")
	var help := Label.new()
	help.text = "動画URLまたはプレイリストURLを入力してください。動画は音声のみを一時UUIDフォルダへ取得し、Phase 3の解析・譜面生成へ渡します。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color("#c4d4ee"))
	box.add_child(help)
	youtube_url_input = LineEdit.new()
	youtube_url_input.name = "YoutubeUrl"
	youtube_url_input.placeholder_text = "https://www.youtube.com/watch?v=... または /playlist?list=..."
	youtube_url_input.custom_minimum_size = Vector2(900, 48)
	youtube_url_input.add_theme_font_size_override("font_size", 18)
	box.add_child(youtube_url_input)
	youtube_rights_check = CheckBox.new()
	youtube_rights_check.text = "この音源を保存・解析する権利または明示的な許諾があります"
	youtube_rights_check.add_theme_font_size_override("font_size", 17)
	box.add_child(youtube_rights_check)
	youtube_status_label = Label.new()
	youtube_status_label.text = "先に動画またはプレイリストをprobeしてください。"
	youtube_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	youtube_status_label.add_theme_font_size_override("font_size", 18)
	box.add_child(youtube_status_label)
	_add_button(box, "PROBE VIDEO", "メタデータと権利確認前のプレビュー", func() -> void: _probe_youtube(false))
	_add_button(box, "PROBE PLAYLIST", "flat一覧を取得して選択・検索・並べ替え", func() -> void: _probe_youtube(true))
	_add_button(box, "CANCEL JOB", "取得・解析中の処理を安全に停止", _cancel_youtube_job)
	_add_button(box, "BACK", "メインメニューへ戻る", _show_menu)

func _probe_youtube(playlist: bool) -> void:
	if youtube_url_input == null or youtube_url_input.text.strip_edges().is_empty():
		_show_youtube_error("YouTubeのURLを入力してください")
		return
	var job_service := get_node_or_null("/root/JobService")
	if job_service == null:
		_show_youtube_error("Python workerが利用できません。DIAGNOSTICSで環境を確認してください")
		return
	if playlist:
		job_service.start_youtube_playlist_probe(youtube_url_input.text.strip_edges())
	else:
		job_service.start_youtube_probe(youtube_url_input.text.strip_edges())
	if youtube_status_label != null:
		youtube_status_label.text = "YouTubeのメタデータを確認しています…"

func _cancel_youtube_job() -> void:
	var job_service := get_node_or_null("/root/JobService")
	if job_service != null:
		job_service.cancel_current_job()
	if youtube_status_label != null:
		youtube_status_label.text = "キャンセルを依頼しました。処理の終了を待っています。"

func _show_youtube_preview(metadata: Dictionary) -> void:
	if youtube_status_label == null:
		return
	youtube_status_label.text = "タイトル: %s\n作者: %s\n長さ: %.1f秒\n取得元: %s / ID: %s\nThumbnail: %s\n\n権利確認チェックを入れてからIMPORTしてください。" % [str(metadata.get("title", "")), str(metadata.get("artist", "")), float(metadata.get("duration_seconds", 0.0)), str(metadata.get("extractor", "")), str(metadata.get("source_id", "")), str(metadata.get("thumbnail", "(なし)"))]
	if youtube_entries_list == null:
		var box := _youtube_box()
		if box != null:
			_add_button(box, "IMPORT AUDIO", "この動画の音声を解析してSongPackへ保存", _start_youtube_import)

func _start_youtube_import() -> void:
	if youtube_url_input == null or youtube_url_input.text.strip_edges().is_empty():
		_show_youtube_error("先にURLを入力してください")
		return
	if youtube_rights_check == null or not youtube_rights_check.button_pressed:
		_show_youtube_error("利用権限の確認にチェックを入れてください")
		return
	var job_service := get_node_or_null("/root/JobService")
	if job_service != null:
		job_service.start_youtube_import(youtube_url_input.text.strip_edges(), true)
	if youtube_status_label != null:
		youtube_status_label.text = "音声を取得し、ローカル解析しています…"

func _start_youtube_batch_import() -> void:
	if youtube_rights_check == null or not youtube_rights_check.button_pressed:
		_show_youtube_error("プレイリスト内の選択曲すべてについて利用権限を確認してください")
		return
	var selected: Array = []
	if youtube_entries_list != null:
		for index in youtube_entries_list.get_selected_items():
			var item: Variant = youtube_entries_list.get_item_metadata(index)
			if item is Dictionary:
				selected.append(str(item.get("source_id", "")))
	var job_service := get_node_or_null("/root/JobService")
	if job_service != null:
		var sort_mode := "index" if youtube_sort_option == null else str(youtube_sort_option.get_item_metadata(youtube_sort_option.selected))
		job_service.start_youtube_batch_import(youtube_url_input.text.strip_edges(), selected, true, sort_mode)
	if youtube_status_label != null:
		youtube_status_label.text = "選択した曲を順番に取得しています。完了済みは再開時にスキップします。"

func _rebuild_youtube_entries() -> void:
	if youtube_entries_list == null:
		return
	youtube_entries_list.clear()
	var query := "" if youtube_search_input == null else youtube_search_input.text.strip_edges().to_lower()
	for entry in youtube_entries:
		var title := str(entry.get("title", ""))
		if not query.is_empty() and not title.to_lower().contains(query):
			continue
		var duration := float(entry.get("duration_seconds", 0.0))
		youtube_entries_list.add_item("%s  [%.0fs]  %s" % [str(entry.get("playlist_index", "-")), duration, title])
		youtube_entries_list.set_item_metadata(youtube_entries_list.get_item_count() - 1, entry)

func _show_youtube_playlist(result: Dictionary) -> void:
	youtube_entries = Array(result.get("entries", []))
	if youtube_status_label != null:
		youtube_status_label.text = "プレイリスト: %s / %d曲。検索・選択・並べ替えを行い、権利確認後に一括取り込みできます。" % [str(result.get("title", "")), youtube_entries.size()]
	youtube_search_input = LineEdit.new()
	youtube_search_input.placeholder_text = "タイトル検索"
	youtube_search_input.text_changed.connect(func(_value: String) -> void: _rebuild_youtube_entries())
	if youtube_status_label != null:
		var box := _youtube_box()
		if box != null:
			box.add_child(youtube_search_input)
	youtube_sort_option = OptionButton.new()
	youtube_sort_option.add_item("プレイリスト順")
	youtube_sort_option.set_item_metadata(0, "index")
	youtube_sort_option.add_item("タイトル順")
	youtube_sort_option.set_item_metadata(1, "title")
	youtube_sort_option.add_item("長さ順")
	youtube_sort_option.set_item_metadata(2, "duration")
	if youtube_status_label != null:
		var box := _youtube_box()
		if box != null:
			box.add_child(youtube_sort_option)
	youtube_entries_list = ItemList.new()
	youtube_entries_list.select_mode = ItemList.SELECT_MULTI
	youtube_entries_list.custom_minimum_size = Vector2(900, 260)
	if youtube_status_label != null:
		var box := _youtube_box()
		if box != null:
			box.add_child(youtube_entries_list)
	_rebuild_youtube_entries()
	if youtube_status_label != null:
		var box := _youtube_box()
		if box != null:
			_add_button(box, "IMPORT SELECTED", "権利確認済みの選択曲をatomic/resume一括取り込み", _start_youtube_batch_import)

func _youtube_box() -> VBoxContainer:
	return youtube_status_label.get_parent() as VBoxContainer if youtube_status_label != null else null

func _show_youtube_error(message: String) -> void:
	if youtube_status_label != null:
		youtube_status_label.text = "エラー: " + message

func _show_song_library() -> void:
	mode = "library"
	_clear_screen()
	var box := _make_column(Vector2(110, 80), 980)
	_add_title(box, "SONG LIBRARY", "テスト曲と、user://へ登録したローカルSongPackをオフラインで選べます。")
	var library := get_node_or_null("/root/SongLibrary")
	if library == null:
		_add_title(box, "LIBRARY UNAVAILABLE", "SongLibraryサービスを読み込めませんでした")
		_add_button(box, "BACK", "メインメニューへ戻る", _show_menu)
		return
	var songs: Array = library.list_local_songs()
	for song in songs:
		var song_id := str(song.get("song_uuid", song.get("song_id", "test")))
		var title := str(song.get("title", "Untitled"))
		var artist := str(song.get("artist", "Local Audio"))
		var is_test: bool = song_id == "test" or not song.has("pack_path")
		var meta := Label.new()
		meta.text = "%s — %s\nBPM %s / %sms / backend %s" % [title, artist, str(song.get("bpm", "120")), str(song.get("duration_ms", "?")), str(song.get("backend", "fixture"))]
		meta.add_theme_font_size_override("font_size", 18)
		meta.add_theme_color_override("font_color", Color("#c4d4ee"))
		box.add_child(meta)
		if is_test:
			_add_button(box, "PLAY TEST SONG", "固定譜面を開始", _start_game)
		else:
			var local_id := song_id
			_add_button(box, "PLAY", "Normal譜面を開始", func() -> void: _start_local_game(local_id))
			_add_button(box, "BEAT CHECK", "拍・小節頭・BPM・offsetを確認", func() -> void: _show_beat_check(local_id))
			_add_button(box, "REGENERATE CHARTS", "user_override.jsonから譜面を再生成", func() -> void: _regenerate_song(local_id))
			_add_button(box, "REMOVE", "SongPackだけを削除（元音源は削除しない）", func() -> void: _confirm_remove_song(local_id))
		_add_spacer(box, 10)
	_add_button(box, "BACK", "メインメニューへ戻る", _show_menu)

func _regenerate_song(song_uuid: String) -> void:
	var library := get_node_or_null("/root/SongLibrary")
	var job_service := get_node_or_null("/root/JobService")
	if library != null and job_service != null:
		job_service.start_chart_regeneration(song_uuid, library.get_song_pack_root())
	_show_song_library()

func _confirm_remove_song(song_uuid: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "SongPackを削除"
	dialog.dialog_text = "登録情報だけを削除します。元の音源ファイルは削除しません。\n本当に削除しますか？"
	dialog.confirmed.connect(func() -> void:
		var library := get_node_or_null("/root/SongLibrary")
		if library != null:
			library.remove_song_pack(song_uuid)
		_show_song_library()
	)
	add_child(dialog)
	dialog.popup_centered()

func _show_beat_check(song_uuid: String) -> void:
	mode = "beat_check"
	_clear_screen()
	var box := _make_column(Vector2(110, 90), 1000)
	_add_title(box, "BEAT CHECK", "解析元analysis.jsonは変更せず、修正値だけuser_override.jsonへ保存します。")
	var library := get_node_or_null("/root/SongLibrary")
	if library == null:
		_add_button(box, "BACK", "曲一覧へ戻る", _show_song_library)
		return
	var analysis_path: String = str(library.chart_path(song_uuid, "normal")).get_base_dir().get_base_dir() + "/analysis.json"
	var file := FileAccess.open(analysis_path, FileAccess.READ)
	var analysis: Dictionary = JSON.parse_string(file.get_as_text()) if file != null else {}
	var info := Label.new()
	info.text = "BPM %.2f / meter %s / backend %s / confidence %.2f\nbeats %d / downbeats %d / sections %d\n波形ピーク %d点" % [float(analysis.get("bpm_summary", 0.0)), str(analysis.get("meter", "?")), str(analysis.get("beat_backend", "?")), float(analysis.get("confidence", 0.0)), Array(analysis.get("beats_ms", [])).size(), Array(analysis.get("downbeats_ms", [])).size(), Array(analysis.get("sections", [])).size(), Array(analysis.get("waveform_peaks", [])).size()]
	info.add_theme_font_size_override("font_size", 20)
	info.add_theme_color_override("font_color", Color("#dce9ff"))
	box.add_child(info)
	var waveform = BEAT_CHECK_VIEW_SCRIPT.new()
	waveform.configure(analysis)
	box.add_child(waveform)
	_add_button(box, "PLAY PREVIEW", "登録音源をオフライン再生", func() -> void: _play_local_preview(song_uuid))
	_add_button(box, "STOP PREVIEW", "再生を停止", _stop_preview)
	_add_button(box, "BPM HALF", "修正値を保存して4譜面を再生成", func() -> void: _save_override_and_regenerate(song_uuid, {"bpm_multiplier": 0.5}))
	_add_button(box, "BPM DOUBLE", "修正値を保存して4譜面を再生成", func() -> void: _save_override_and_regenerate(song_uuid, {"bpm_multiplier": 2.0}))
	_add_button(box, "OFFSET -10ms", "拍を10ms早める", func() -> void: _save_override_and_regenerate(song_uuid, {"beat_offset_ms": -10.0}))
	_add_button(box, "OFFSET +10ms", "拍を10ms遅らせる", func() -> void: _save_override_and_regenerate(song_uuid, {"beat_offset_ms": 10.0}))
	_add_button(box, "BACK", "曲一覧へ戻る", _show_song_library)

func _play_local_preview(song_uuid: String) -> void:
	_stop_preview()
	var library := get_node_or_null("/root/SongLibrary")
	if library == null:
		return
	var stream: AudioStream = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(library.playback_path(song_uuid)))
	if stream == null:
		return
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = stream
	add_child(audio_player)
	audio_player.play()

func _stop_preview() -> void:
	if audio_player != null:
		audio_player.stop()
		audio_player.queue_free()
		audio_player = null

func _save_override_and_regenerate(song_uuid: String, changes: Dictionary) -> void:
	var library := get_node_or_null("/root/SongLibrary")
	if library == null:
		return
	var override_path: String = str(library.chart_path(song_uuid, "normal")).get_base_dir().get_base_dir() + "/user_override.json"
	var previous: Dictionary = {}
	var file := FileAccess.open(override_path, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			previous = parsed
	previous.merge(changes)
	previous["updated_at"] = Time.get_datetime_string_from_system(true)
	var temporary := override_path + ".tmp"
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(previous, "  ") + "\n")
		output.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(override_path))
	_regenerate_song(song_uuid)

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
	_add_button(box, "VERIFY TOOLCHAIN", "Godot / Python / Deno / FFmpeg / CUDA / modelsを検査", _run_toolchain_verify)
	_add_button(box, "EXPORT ENVIRONMENT REPORT", "秘密情報を除いた実行環境JSONを保存", _export_environment_report)
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

func _run_toolchain_verify() -> void:
	var status := get_node_or_null("Content/Column/Status") as Label
	var script := ProjectSettings.globalize_path("res://../tools/verify_toolchain.ps1")
	var pid := OS.create_process("pwsh", PackedStringArray(["-NoProfile", "-File", script]), false)
	if status != null:
		status.text = "Toolchain verifyを起動しました。PID %d。詳細はDIAGNOSTICSログと.runtime/reportsを確認してください。" % pid

func _export_environment_report() -> void:
	var status := get_node_or_null("Content/Column/Status") as Label
	var script := ProjectSettings.globalize_path("res://../tools/export_environment_report.ps1")
	var pid := OS.create_process("pwsh", PackedStringArray(["-NoProfile", "-File", script]), false)
	if status != null:
		status.text = "環境レポートを出力中です。PID %d。" % pid

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
	if mode == "import":
		if import_status_label != null:
			var stage := str(status.get("stage", status.get("message", "")))
			var state := str(status.get("state", ""))
			var progress := float(status.get("progress", 0.0)) * 100.0
			import_status_label.text = "%s — %s (%.0f%%)" % [state, stage, progress]
		if str(status.get("state", "")) == "completed":
			if str(status.get("job_type", "")) == "probe_local_audio":
				var probe: Dictionary = status.get("result", {})
				if import_status_label != null:
					import_status_label.text = "形式 %s / %.1f秒 / %skHz / %sch / SHA-256 %s" % [str(probe.get("format", "?")), float(probe.get("duration", 0.0)), str(float(probe.get("sample_rate", 0)) / 1000.0), str(probe.get("channels", "?")), str(probe.get("audio_sha256", "")).left(12)]
				if import_action_button == null:
					import_action_button = Button.new()
					import_action_button.text = "ANALYZE AUDIO    拍・構造・4難易度譜面を生成"
					import_action_button.custom_minimum_size = Vector2(640, 52)
					import_action_button.pressed.connect(_start_import_analysis)
					if import_column != null:
						import_column.add_child(import_action_button)
			elif str(status.get("job_type", "")) == "analyze_local_audio":
				imported_song_uuid = str(status.get("result", {}).get("song_uuid", ""))
				if not imported_song_uuid.is_empty():
					if import_column != null:
						_add_button(import_column, "PLAY GENERATED SONG", "Normal譜面を登録曲として開始", func() -> void: _start_local_game(imported_song_uuid))
						_add_button(import_column, "MAIN MENU", "登録曲はuser://へ保存済み", _show_menu)
			return
	if mode == "youtube":
		var state := str(status.get("state", ""))
		if youtube_status_label != null and state == "running":
			youtube_status_label.text = "%s — %s (%.0f%%)" % [state, str(status.get("stage", status.get("message", ""))), float(status.get("progress", 0.0)) * 100.0]
		if state == "failed":
			_show_youtube_error("%s: %s" % [str(status.get("error_code", "unknown")), str(status.get("message", ""))])
		elif state == "completed":
			var job_type := str(status.get("job_type", ""))
			var result: Dictionary = status.get("result", {})
			if job_type == "probe_youtube":
				_show_youtube_preview(result.get("metadata", {}))
			elif job_type == "probe_youtube_playlist":
				_show_youtube_playlist(result)
			elif job_type == "import_youtube":
				imported_song_uuid = str(result.get("song_uuid", ""))
				if youtube_status_label != null:
					youtube_status_label.text = "取り込み完了: %s。SONG LIBRARYからオフライン再生できます。" % imported_song_uuid
				if imported_song_uuid != "":
					var box := _youtube_box()
					if box != null:
						_add_button(box, "PLAY IMPORTED SONG", "生成したNormal譜面を再生", func() -> void: _start_local_game(imported_song_uuid))
		return
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
	import_selected_label = null
	import_column = null
	import_status_label = null
	import_action_button = null
	youtube_url_input = null
	youtube_rights_check = null
	youtube_status_label = null
	youtube_search_input = null
	youtube_entries_list = null
	youtube_sort_option = null

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
