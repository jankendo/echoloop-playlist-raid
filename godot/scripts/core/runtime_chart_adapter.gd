class_name RuntimeChartAdapter
extends RefCounted
## Single runtime boundary for schema v1/v2 charts and input modes.

const DUO_MODE := "duo_2key"
const PROJECTOR_SCRIPT := preload("res://scripts/core/four_lane_to_duo_projector.gd")

func adapt(chart: Dictionary, gameplay_mode: String = DUO_MODE) -> Dictionary:
	return PROJECTOR_SCRIPT.new().project(chart, gameplay_mode)
