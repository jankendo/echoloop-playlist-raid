extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("main scene could not load")
		quit(1)
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	await process_frame
	if not is_instance_valid(instance):
		push_error("main scene instance was freed")
		quit(1)
		return
	print("ECHOLOOP boot smoke: PASS")
	quit(0)

