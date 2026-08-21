class_name SeasonProgressBar
extends Control

# Purely decorative: shows which season/day of the year the calendar is
# currently passing through. Does not gate or trigger any simulation —
# growth/encroachment/mortality/migration/natural events still all fire
# together at the year rollover, unchanged.

const BAR_HEIGHT := 18.0

# Same saturation/value pair for every season — only the hue changes — so the
# "lit vs muted" contrast is tuned in one place instead of 8 hand-picked hexes.
const BRIGHT_SATURATION := 0.70
const BRIGHT_VALUE := 0.90
const DIM_SATURATION := 0.22
const DIM_VALUE := 0.50

const SEASON_HUES := {
	GameTypes.Season.WINTER: 0.58, # cool blue
	GameTypes.Season.SPRING: 0.32, # green
	GameTypes.Season.SUMMER: 0.13, # gold/yellow
	GameTypes.Season.AUTUMN: 0.05, # burnt orange
}

const SEASON_TR_KEYS := {
	GameTypes.Season.WINTER: "season_winter",
	GameTypes.Season.SPRING: "season_spring",
	GameTypes.Season.SUMMER: "season_summer",
	GameTypes.Season.AUTUMN: "season_autumn",
}

var _current_day: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_current_day(day: int) -> void:
	_current_day = day
	queue_redraw()

# Segments laid out edge-to-edge (no gap between seasons), each width
# proportional to its share of the 365-day year. Shared by _draw() and
# _get_tooltip() so the hover hit-test can never disagree with what's drawn.
func _segment_bounds() -> Array:
	var bounds: Array = []
	var x := 0.0
	for season in SeasonCalculator.SEASON_ORDER:
		var season_length: int = SeasonCalculator.SEASON_LENGTHS[season]
		var width := size.x * (float(season_length) / float(GameData.DAYS_PER_YEAR))
		bounds.append({"season": season, "x": x, "width": width})
		x += width
	return bounds

func _draw() -> void:
	if size.x <= 0.0:
		return

	for segment in _segment_bounds():
		var season: GameTypes.Season = segment["season"]
		var seg_x: float = segment["x"]
		var seg_width: float = segment["width"]

		var season_range := SeasonCalculator.get_season_day_range(season)
		var season_start: int = season_range.x
		var season_length: int = season_range.y
		var days_elapsed: int = clampi(_current_day - season_start, 0, season_length)
		var elapsed_fraction := float(days_elapsed) / float(season_length)

		var hue: float = SEASON_HUES[season]
		var dim_color := Color.from_hsv(hue, DIM_SATURATION, DIM_VALUE)
		var bright_color := Color.from_hsv(hue, BRIGHT_SATURATION, BRIGHT_VALUE)

		draw_rect(Rect2(seg_x, 0.0, seg_width, size.y), dim_color)
		var elapsed_width := seg_width * elapsed_fraction
		if elapsed_width > 0.0:
			draw_rect(Rect2(seg_x, 0.0, elapsed_width, size.y), bright_color)

func _get_tooltip(at_position: Vector2) -> String:
	var bounds := _segment_bounds()
	for i in range(bounds.size()):
		var segment: Dictionary = bounds[i]
		var is_last := i == bounds.size() - 1
		if at_position.x < segment["x"] + segment["width"] or is_last:
			return tr(SEASON_TR_KEYS[segment["season"]])
	return ""
