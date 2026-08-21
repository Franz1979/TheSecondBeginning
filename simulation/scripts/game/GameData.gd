class_name GameData
extends RefCounted

const DAYS_PER_YEAR := 365

var year: int = 0
var current_day: int = 0 # 0..DAYS_PER_YEAR-1

# Monotonic day count since year 0, day 0 — the single source of truth for "how long ago"
# comparisons (e.g. natural-event growth-bonus expiry) that must not reset/round at a year
# boundary the way a per-year counter would.
func get_absolute_day() -> int:
	return year * DAYS_PER_YEAR + current_day

# Advances the calendar by one day. Returns true if this tick rolled the
# year over (current_day wrapped back to 0, year incremented) — callers use
# this to decide whether to run the yearly simulation pipeline.
func advance_day() -> bool:
	current_day += 1
	if current_day >= DAYS_PER_YEAR:
		current_day = 0
		year += 1
		return true
	return false
