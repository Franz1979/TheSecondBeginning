class_name VillageCohesionService
extends RefCounted

# Coesione (2026-10-14, richiesta utente — vedi docs/design/socialita_teaching.md): quanto un villaggio è unito, 0–100,
# sale e scende. Stato in Village.cohesion (salvato); quella della popolazione è la media semplice dei villaggi, calcolata
# (get_folk_cohesion). Non è un'influenza: niente raggi, niente InfluenceType, non si somma. Servizio senza stato, unico
# punto che la modifica.
#
# Regole:
#   - nasce a INITIAL_COHESION (Village.cohesion, anche per i villaggi dei salvataggi precedenti);
#   - calo annuale proporzionale a fine anno (apply_annual_decay): coesione / DECAY_DIVISOR (0 → 0, 50 → 1, 100 → 2),
#     per ora senza moltiplicatori;
#   - eventi a somma diretta (add): talk TALK_GAIN, idea scoperta IDEA_GAIN, banchetto (futuro) +0.1;
#   - nuovi arrivati (add_newcomers): media pesata con NEWCOMER_COHESION, contando solo chi non è INFANT o CHILD.
# Effetti sul gioco (lealtà, abbandoni…) non ancora: per ora solo il valore e le statistiche.

const MIN_COHESION := 0.0
const MAX_COHESION := 100.0
const INITIAL_COHESION := 50.0
const DECAY_DIVISOR := 50.0
const TALK_GAIN := 0.01
const IDEA_GAIN := 1.0
const NEWCOMER_COHESION := 20.0


static func add(village: Village, amount: float, reason: String = "") -> void:
	if village == null or amount == 0.0:
		return
	var before := village.cohesion
	village.cohesion = clampf(village.cohesion + amount, MIN_COHESION, MAX_COHESION)
	_log(village, "%s %+.2f: %.2f -> %.2f" % [reason, amount, before, village.cohesion])


# Chi entra nel villaggio (famiglia di visitatori accettata): (abitanti × coesione + nuovi × NEWCOMER_COHESION) /
# (abitanti + nuovi), contando solo i non INFANT e non CHILD. `individuals` = i vivi PRIMA dell'ingresso dei nuovi.
static func add_newcomers(
	village: Village, newcomers: Array[HumanIndividual], individuals: Array[HumanIndividual], game_data: GameData
) -> void:
	if village == null or game_data == null:
		return
	var new_count := 0
	for newcomer in newcomers:
		if _counts(newcomer, game_data):
			new_count += 1
	if new_count == 0:
		return
	var resident_count := 0
	for individual in individuals:
		if individual.village_ref == village and not newcomers.has(individual) and _counts(individual, game_data):
			resident_count += 1
	var before := village.cohesion
	village.cohesion = clampf(
		(float(resident_count) * village.cohesion + float(new_count) * NEWCOMER_COHESION) / float(resident_count + new_count),
		MIN_COHESION, MAX_COHESION
	)
	_log(village, "%d nuovi arrivati (%d abitanti contati): %.2f -> %.2f" % [new_count, resident_count, before, village.cohesion])


# Calo di fine anno, proporzionale al valore.
static func apply_annual_decay(folk: Folk) -> void:
	if folk == null:
		return
	for village in folk.villages:
		add(village, -village.cohesion / DECAY_DIVISOR, "calo annuale")


# Media semplice delle coesioni dei villaggi; 0 senza villaggi.
static func get_folk_cohesion(folk: Folk) -> float:
	if folk == null or folk.villages.is_empty():
		return 0.0
	var total := 0.0
	for village in folk.villages:
		total += village.cohesion
	return total / float(folk.villages.size())


static func _counts(individual: HumanIndividual, game_data: GameData) -> bool:
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, float(game_data.year - individual.birth_year_virtual)
	)
	return age_band != HumanTypes.AgeBand.INFANT and age_band != HumanTypes.AgeBand.CHILD


static func _log(village: Village, text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_COHESION_LOGS:
		print("[COESIONE] %s: %s" % [village.get_display_name(), text])
