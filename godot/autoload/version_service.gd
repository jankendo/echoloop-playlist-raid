extends Node
## Product and data versions exposed to diagnostics.

const PRODUCT_VERSION := "0.5.0-phase-4.2"
const CHART_SCHEMA_VERSION := 1
const SETTINGS_SCHEMA_VERSION := 2

func summary() -> Dictionary:
	return {"product": "ECHOLOOP: PLAYLIST RAID", "version": PRODUCT_VERSION, "godot": "4.7.1", "chart_schema": CHART_SCHEMA_VERSION}
