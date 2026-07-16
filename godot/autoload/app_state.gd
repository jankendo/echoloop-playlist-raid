extends Node
## Small application state container. Gameplay state lives in GameSession.

signal screen_changed(screen_name: String)

var current_screen: String = "menu"
var active_song_id: String = ""
var last_result: Dictionary = {}

func go_to(screen_name: String) -> void:
	current_screen = screen_name
	screen_changed.emit(screen_name)

