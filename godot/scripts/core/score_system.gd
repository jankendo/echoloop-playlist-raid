class_name ScoreSystem
extends RefCounted
## Deterministic score and lane statistics.

var score: int = 0
var combo: int = 0
var max_combo: int = 0
var resonance: float = 0.0
var counts: Dictionary = {"CRITICAL": 0, "PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0, "GHOST": 0}
var lane_counts: Array = [{"hit": 0, "total": 0}, {"hit": 0, "total": 0}, {"hit": 0, "total": 0}, {"hit": 0, "total": 0}]
var early_count: int = 0
var late_count: int = 0
var assist_used: bool = false

func register_note(lanes: Array) -> void:
	for lane in lanes:
		lane_counts[int(lane)].total += 1

func apply_judgement(judgement: String, delta_ms: float, lanes: Array, assist: bool = false) -> int:
	counts[judgement] = int(counts.get(judgement, 0)) + 1
	if assist:
		assist_used = true
	if judgement == "MISS":
		combo = 0
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
		for lane in lanes:
			lane_counts[int(lane)].hit += 1
		if delta_ms < -0.5:
			early_count += 1
		elif delta_ms > 0.5:
			late_count += 1
	var multiplier := mini(4, 1 + combo / 25)
	var gained := int(round(TimingJudge.score(judgement) * multiplier))
	score += gained
	resonance = clampf(resonance + TimingJudge.power(judgement) * 0.75 - (0.35 if judgement == "MISS" else 0.0), 0.0, 100.0)
	return gained

func register_ghost() -> void:
	counts["GHOST"] = int(counts.get("GHOST", 0)) + 1
	combo = maxi(0, combo - 2)
	resonance = maxf(0.0, resonance - 1.0)

func accuracy() -> float:
	var total := 0
	for key in ["CRITICAL", "PERFECT", "GREAT", "GOOD", "MISS"]:
		total += int(counts[key])
	if total == 0:
		return 0.0
	var points: float = counts.CRITICAL * 1.0 + counts.PERFECT * 0.9 + counts.GREAT * 0.7 + counts.GOOD * 0.4
	return points / float(total) * 100.0

func rank() -> String:
	var value := accuracy()
	if value >= 97.0:
		return "S"
	if value >= 90.0:
		return "A"
	if value >= 80.0:
		return "B"
	if value >= 65.0:
		return "C"
	return "D"

func snapshot() -> Dictionary:
	return {"score": score, "combo": combo, "max_combo": max_combo, "accuracy": accuracy(), "rank": rank(), "counts": counts.duplicate(true), "lane_counts": lane_counts.duplicate(true), "early": early_count, "late": late_count, "resonance": resonance, "assist": assist_used}
