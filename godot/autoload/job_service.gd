extends Node
## Asynchronous boundary to the local Python worker.

signal job_updated(status: Dictionary)

var last_status: Dictionary = {"state": "idle", "message": "No job started"}
var _job_dir := "user://jobs"

func start_health_check() -> void:
	var job_id := "health-" + str(Time.get_ticks_msec())
	var directory := _job_dir + "/" + job_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var request := {"schema_version": 1, "job_id": job_id, "job_type": "health_check", "output_dir": ProjectSettings.globalize_path(directory + "/output")}
	var request_file := directory + "/request.json"
	var status_file := directory + "/status.json"
	var log_file := directory + "/worker.jsonl"
	var file := FileAccess.open(request_file, FileAccess.WRITE)
	if file == null:
		_set_status({"state": "failed", "message": "request file could not be created"})
		return
	file.store_string(JSON.stringify(request, "  ") + "\n")
	file.close()
	var args := PackedStringArray(["-m", "echoloop_worker.cli", "--request", ProjectSettings.globalize_path(request_file), "--status", ProjectSettings.globalize_path(status_file), "--log", ProjectSettings.globalize_path(log_file)])
	var pid := OS.create_process("python", args, false)
	_set_status({"state": "running", "message": "health check started", "pid": pid, "status_path": status_file})

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
	last_status = value
	job_updated.emit(last_status)

