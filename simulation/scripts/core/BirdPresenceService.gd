class_name BirdPresenceService
extends RefCounted

# Presenza degli uccelli su una microcella (2026-11-07). Niente popolazione salvata né semina: un indice 0..1 calcolato
# solo quando serve (clic di ispezione, e in futuro una volta al piazzamento della rete), mai a ogni giorno.
# indice = 0 se la microcella non ha alberi/arbusti, altrimenti copertura legnosa attorno × bioma × stagione − disturbo locale (0 finché non c'è la rete).
# Con la vegetazione a richiesta cambierà solo _woody_cover_around (una lettura del rumore invece dei lotti).

enum Level { NONE, FEW, SOME, MANY }

const RULES_PATH := "res://simulation/data/bird_presence/bird_presence.tres"
const MICRO_GRID_SIDE := 100 # microcelle per lato di una macrocella (MacroCellState.TOTAL_SPACE = 100×100)

static var _rules: BirdPresenceRules = null


static func get_rules() -> BirdPresenceRules:
	if _rules == null:
		_rules = load(RULES_PATH) as BirdPresenceRules
	return _rules


static func get_presence_index(macro_state: MacroCellState, biome: GameTypes.Biome, season: GameTypes.Season, lot: Vector2i, disturbance: float = 0.0) -> float:
	return apply_season(get_site_index(macro_state, biome, lot), season, disturbance)


# Parte fissa dell'indice (piante attorno × bioma), senza stagione né disturbo: calcolata una volta e salvata sulla
# trappola al montaggio (PlacedTrap.site_index).
static func get_site_index(macro_state: MacroCellState, biome: GameTypes.Biome, lot: Vector2i) -> float:
	var rules := get_rules()
	if rules == null or macro_state == null:
		return 0.0
	# Uccelli solo dove ci sono alberi o arbusti (2026-11-07, richiesta utente): nel prato nessuno. Il quadrato
	# attorno dice poi quanto è fitto (cespuglio isolato = pochi, bosco = molti).
	if not BuildingSiteClearingService.has_woody_vegetation(macro_state, lot):
		return 0.0
	var cover := _woody_cover_around(macro_state, lot, rules.cover_radius)
	var value := minf(cover / maxf(rules.full_cover_ratio, 0.001), 1.0)
	return value * float(rules.multiplier_by_biome.get(biome, 1.0))


# Indice del momento da quello fisso del posto: × stagione − disturbo, tra 0 e 1.
static func apply_season(site_index: float, season: GameTypes.Season, disturbance: float = 0.0) -> float:
	var rules := get_rules()
	if rules == null:
		return 0.0
	return clampf(site_index * float(rules.multiplier_by_season.get(season, 1.0)) - disturbance, 0.0, 1.0)


# Livello da un indice già calcolato (stesse soglie di get_presence_level).
static func level_for_index(index: float) -> Level:
	var rules := get_rules()
	if rules == null:
		return Level.NONE
	if index >= rules.many_threshold:
		return Level.MANY
	if index >= rules.some_threshold:
		return Level.SOME
	if index >= rules.few_threshold:
		return Level.FEW
	return Level.NONE


static func get_presence_level(macro_state: MacroCellState, biome: GameTypes.Biome, season: GameTypes.Season, lot: Vector2i, disturbance: float = 0.0) -> Level:
	return level_for_index(get_presence_index(macro_state, biome, season, lot, disturbance))


# Quota di microcelle con alberi o arbusti vivi nel quadrato di raggio `radius` attorno a `lot` (l'erba non conta).
# Ai bordi della macrocella conta solo la parte dentro. Unico punto da cambiare con la vegetazione a richiesta.
static func _woody_cover_around(macro_state: MacroCellState, lot: Vector2i, radius: int) -> float:
	var total := 0
	var woody := 0
	for dy in range(-radius, radius + 1):
		var y := lot.y + dy
		if y < 0 or y >= MICRO_GRID_SIDE:
			continue
		for dx in range(-radius, radius + 1):
			var x := lot.x + dx
			if x < 0 or x >= MICRO_GRID_SIDE:
				continue
			total += 1
			if BuildingSiteClearingService.has_woody_vegetation(macro_state, Vector2i(x, y)):
				woody += 1
	return float(woody) / float(total) if total > 0 else 0.0
