extends Node
## Asynchronous boundary to the local Python worker.

signal job_updated(status: Dictionary)

var last_status: Dictionary = {"state": "idle", "message": "No job started"}
var _job_dir := "user://jobs"
var _current_cancel_file := ""

func start_health_check() -> void:
	start_job("health_check", {})

func start_local_audio_probe(source_path: String) -> void:
	start_job("probe_local_audio", {"source_path": source_path, "project_root": _workspace_root()})

func start_local_audio_analysis(source_path: String, title: String = "", artist: String = "", backend: String = "auto") -> void:
	start_job("analyze_local_audio", {"source_path": source_path, "title": title, "artist": artist, "backend": backend, "project_root": _workspace_root(), "store_root": ProjectSettings.globalize_path("user://echoloop-data")})

func start_chart_regeneration(song_uuid: String, store_root: String) -> void:
	start_job("regenerate_charts", {"song_uuid": song_uuid, "store_root": store_root})

func start_youtube_probe(url: String) -> void:
	start_job("probe_youtube", _youtube_payload(url))

func start_youtube_playlist_probe(url: String) -> void:
	start_job("probe_youtube_playlist", _youtube_payload(url))

func start_youtube_import(url: String, rights_confirmed: bool) -> void:
	var payload := _youtube_payload(url)
	payload["rights_confirmed"] = rights_confirmed
	payload["store_root"] = ProjectSettings.globalize_path("user://echoloop-data")
	start_job("import_youtube", payload)

func start_youtube_batch_import(url: String, entries: Array, rights_confirmed: bool, sort_mode: String = "index") -> void:
	var payload := _youtube_payload(url)
	payload["entries"] = entries
	payload["sort"] = sort_mode
	payload["rights_confirmed"] = rights_confirmed
	payload["store_root"] = ProjectSettings.globalize_path("user://echoloop-data")
	start_job("import_youtube_batch", payload)

func _youtube_payload(url: String) -> Dictionary:
	return {"url": url, "project_root": _workspace_root()}

func cancel_current_job() -> void:
	if _current_cancel_file.is_empty():
		return
	var file := FileAccess.open(_current_cancel_file, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("cancel\n")
	file.close()

func start_job(job_type: String, payload: Dictionary) -> void:
	var job_id := job_type + "-" + str(Time.get_ticks_msec())
	var directory := _job_dir + "/" + job_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var cancel_path := directory + "/cancel"
	_current_cancel_file = ProjectSettings.globalize_path(cancel_path)
	var request := {"schema_version": 2 if job_type != "health_check" else 1, "job_id": job_id, "job_type": job_type, "output_dir": ProjectSettings.globalize_path(directory + "/output"), "cancel_file": _current_cancel_file, "payload": payload}
	var request_file := directory + "/request.json"
	var status_file := directory + "/status.json"
	var log_file := directory + "/worker.jsonl"
	var file := FileAccess.open(request_file, FileAccess.WRITE)
	if file == null:
		_set_status({"state": "failed", "message": "request file could not be created"})
		return
	file.store_string(JSON.stringify(request, "  ") + "\n")
	file.close()
	var python_path := _worker_python()
	var args := PackedStringArray(["-m", "echoloop_worker.cli", "--request", ProjectSettings.globalize_path(request_file), "--status", ProjectSettings.globalize_path(status_file), "--log", ProjectSettings.globalize_path(log_file)])
	var pid := OS.create_process(python_path, args, false)
	_set_status({"schema_version": request.schema_version, "state": "running", "job_type": job_type, "message": "job started", "pid": pid, "status_path": status_file, "cancel_file": _current_cancel_file})

func _worker_python() -> String:
	var current_path := _workspace_root().path_join(".runtime/current.json")
	var file := FileAccess.open(current_path, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			var python: String = str(parsed.get("python", {}).get("Python", ""))
			if not python.is_empty() and FileAccess.file_exists(python):
				return python
	return "python"

func _workspace_root() -> String:
	return ProjectSettings.globalize_path("res://..").simplify_path()

func _process(_delta: float) -> void:
	if str(last_status.get("state", "")) != "running":
		return
	var status_path := str(last_status.get("status_path", ""))
	if status_path.is_empty() or not FileAccess.file_exists(status_path):
		return
	var file := FileAccess.open(status_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_set_status(parsed)

func _set_status(value: Dictionary) -> void:
	var merged := value.duplicate(true)
	for key in ["status_path", "cancel_file", "pid"]:
		if not merged.has(key) and last_status.has(key):
			merged[key] = last_status[key]
	last_status = merged
	job_updated.emit(last_status)
