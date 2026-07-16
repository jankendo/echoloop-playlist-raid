class_name TimingJudge
extends RefCounted
## Pure timing judgement. Widths stay fixed; assist widens them explicitly.

const CRITICAL_MS := 22.0
const PERFECT_MS := 45.0
const GREAT_MS := 80.0
const GOOD_MS := 120.0

static func classify(delta_ms: float, assist_ms: float = 0.0) -> String:
	var distance := absf(delta_ms)
	if distance <= CRITICAL_MS + assist_ms:
		return "CRITICAL"
	if distance <= PERFECT_MS + assist_ms:
		return "PERFECT"
	if distance <= GREAT_MS + assist_ms:
		return "GREAT"
	if distance <= GOOD_MS + assist_ms:
		return "GOOD"
	return "MISS"

static func is_positive(judgement: String) -> bool:
	return judgement != "MISS"

static func power(judgement: String) -> float:
	return {"CRITICAL": 1.0, "PERFECT": 0.9, "GREAT": 0.7, "GOOD": 0.4}.get(judgement, 0.0)

static func score(judgement: String) -> int:
	return {"CRITICAL": 1000, "PERFECT": 900, "GREAT": 700, "GOOD": 400, "MISS": 0}.get(judgement, 0)

static func direction(delta_ms: float) -> String:
	if absf(delta_ms) < 0.5:
		return "ON_TIME"
	return "EARLY" if delta_ms < 0.0 else "LATE"

