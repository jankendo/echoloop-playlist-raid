extends Node
## Visual and audio accessibility facade.

func background_dim() -> float:
	var settings := get_node_or_null("/root/SettingsService")
	return float(settings.get_value("background_dim", 0.72)) if settings != null else 0.72

func flash_reduced() -> bool:
	var settings := get_node_or_null("/root/SettingsService")
	return bool(settings.get_value("flash_reduction", true)) if settings != null else true

func echo_volume() -> float:
	var settings := get_node_or_null("/root/SettingsService")
	return float(settings.get_value("echo_volume", 0.35)) if settings != null else 0.35
