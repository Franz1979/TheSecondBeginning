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

# Finestra di visibilità dei marker "morto" da mortalità naturale (vedi IndividualVegetationService/
# NaturalMortalityVisualService/WorldTimeService._clear_natural_death_markers): dal giorno del
# checkpoint di mortalità (fine autunno = year rollover, osservato come day 0 del nuovo anno) fino
# al giorno del checkpoint di growth (fine primavera) incluso — da lì in poi growth rioccupa gli
# slot e i marker vengono azzerati in blocco. Copre WINTER+SPRING per intero, contigui da day 0.
static func is_within_natural_death_visibility_window(day: int) -> bool:
	return day <= get_season_end_day(GameTypes.Season.SPRING)

# True se `day` è uno dei giorni su cui WorldTimeService._run_seasonal_checkpoints fa scattare
# almeno un checkpoint stagionale (inizio o fine di una stagione) — funzione pura, nessun accesso a
# World/GameData, così i log diagnostici (vedi DebugLogging.SHOW_DAILY_TIMING_LOGS e
# is_near_seasonal_checkpoint sotto) possono chiedere "oggi/ieri/domani è un giorno di checkpoint?"
# senza rieseguire nulla. Rispecchia esattamente i confronti su `day` già presenti in
# _run_seasonal_checkpoints: inizio di ciascuna stagione, più fine di WINTER/SPRING/SUMMER — la
# fine di AUTUMN non serve un confronto a parte, coincide sempre con day==0 (inizio WINTER) per
# via del wraparound di GameData.advance_day, già coperto dal primo controllo.
static func is_seasonal_checkpoint_day(day: int) -> bool:
	for season in SEASON_ORDER:
		if day == get_season_day_range(season).x:
			return true
	return (
		day == get_season_end_day(GameTypes.Season.WINTER)
		or day == get_season_end_day(GameTypes.Season.SPRING)
		or day == get_season_end_day(GameTypes.Season.SUMMER)
	)

# True se `day`, il giorno precedente o il giorno successivo (con wraparound sul confine
# dell'anno) è un giorno di checkpoint stagionale — usata per limitare i log diagnostici
# giornalieri (troppo rumorosi ad ogni giorno) ai soli dintorni di un cambio stagione: 3 giorni
# comunque mostrati per ogni giorno di checkpoint isolato, o una finestra continua un po' più larga
# quando due giorni di checkpoint sono adiacenti (es. fine WINTER/inizio SPRING).
static func is_near_seasonal_checkpoint(day: int) -> bool:
	var previous_day := (day - 1 + GameData.DAYS_PER_YEAR) % GameData.DAYS_PER_YEAR
	var next_day := (day + 1) % GameData.DAYS_PER_YEAR
	return (
		is_seasonal_checkpoint_day(previous_day)
		or is_seasonal_checkpoint_day(day)
		or is_seasonal_checkpoint_day(next_day)
	)

# Stagione immediatamente precedente a `season` nel ciclo (WINTER->AUTUMN dell'anno prima).
# Usata dai checkpoint di inizio stagione che devono confrontare il moltiplicatore nuovo con
# quello della stagione appena conclusa (vedi CaloricCalculator.update_secondary_resource_stock).
static func get_previous_season(season: GameTypes.Season) -> GameTypes.Season:
	var index := SEASON_ORDER.find(season)
	return SEASON_ORDER[(index - 1 + SEASON_ORDER.size()) % SEASON_ORDER.size()]
