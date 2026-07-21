class_name SeasonCalculator
extends RefCounted

# Even 91/91/91/92 split of the 365-day year (GameData.DAYS_PER_YEAR) — no
# astronomical precision intended. Kept here rather than inline in the UI so
# that a future seasons-aware simulation pass (see natural-events roadmap)
# reuses the same day<->season mapping instead of redefining it.
const SEASON_ORDER := [
	GameTypes.Season.WINTER,
	GameTypes.Season.SPRING,
	GameTypes.Season.SUMMER,
	GameTypes.Season.AUTUMN,
]

const SEASON_LENGTHS := {
	GameTypes.Season.WINTER: 91,
	GameTypes.Season.SPRING: 91,
	GameTypes.Season.SUMMER: 91,
	GameTypes.Season.AUTUMN: 92,
}

# Which season `day` (0..GameData.DAYS_PER_YEAR-1) falls into.
static func get_season_for_day(day: int) -> GameTypes.Season:
	var cursor := 0
	for season in SEASON_ORDER:
		cursor += SEASON_LENGTHS[season]
		if day < cursor:
			return season
	return SEASON_ORDER[SEASON_ORDER.size() - 1]

# (start_day, length) of `season` within the year — start_day is 0-indexed.
static func get_season_day_range(season: GameTypes.Season) -> Vector2i:
	var cursor := 0
	for s in SEASON_ORDER:
		if s == season:
			return Vector2i(cursor, SEASON_LENGTHS[s])
		cursor += SEASON_LENGTHS[s]
	return Vector2i(0, 0)

# Last day (0-indexed) belonging to `season` — used by WorldTimeService to trigger the
# end-of-season simulation checkpoints (e.g. growth+encroachment at end of spring).
static func get_season_end_day(season: GameTypes.Season) -> int:
	var range := get_season_day_range(season)
	return range.x + range.y - 1
