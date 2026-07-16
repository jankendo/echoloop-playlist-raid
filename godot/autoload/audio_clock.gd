extends Node
## Absolute-time music clock with monotonic and fake-clock contracts.

signal song_finished

var _player: AudioStreamPlayer
var _time_ms: float = 0.0
var _last_time_ms: float = 0.0
var _running: bool = false
var _paused: bool = false
var _fake: bool = true
var audio_offset_ms: float = 0.0
var visual_offset_ms: float = 0.0
var duration_ms: float = 0.0
var _finish_emitted: bool = false

func set_fake_mode(enabled: bool) -> void:
	_fake = enabled

func is_fake_mode() -> bool:
	return _fake

func attach_player(player: AudioStreamPlayer) -> void:
	_player = player
	_fake = false

func configure(offset_ms: float, visual_ms: float, duration: float) -> void:
	audio_offset_ms = offset_ms
	visual_offset_ms = visual_ms
	duration_ms = duration

func start(start_ms: float = 0.0) -> void:
	_time_ms = start_ms
	_last_time_ms = start_ms
	_running = true
	_paused = false
	_finish_emitted = false

func pause() -> void:
	_paused = true

func resume() -> void:
	_paused = false

func seek(time_ms: float) -> void:
	_time_ms = max(0.0, time_ms)
	_last_time_ms = _time_ms
	_finish_emitted = false

func stop() -> void:
	_running = false
	_paused = false
	if _player != null:
		_player.stop()

func tick(delta: float) -> void:
	if not _running or _paused or not _fake:
		return
	_update_time(_time_ms + delta * 1000.0)

func update_from_player() -> void:
	if not _running or _paused or _player == null or not _player.playing:
		return
	var candidate := (_player.get_playback_position() * 1000.0) + AudioServer.get_time_since_last_mix() * 1000.0 - AudioServer.get_output_latency() * 1000.0 + audio_offset_ms
	_update_time(candidate)

func song_time_ms() -> float:
	return _time_ms

func visual_time_ms() -> float:
	return _time_ms + visual_offset_ms

func is_finished() -> bool:
	return duration_ms > 0.0 and _time_ms >= duration_ms

func _update_time(candidate: float) -> void:
	_time_ms = max(_last_time_ms, candidate)
	_last_time_ms = _time_ms
	if is_finished() and not _finish_emitted:
		_finish_emitted = true
		song_finished.emit()
