class_name DomesticationPointsService
extends RefCounted

# Punti addomesticazione per specie domestica (addomesticazione passo 1, 2026-10-26, richiesta utente): come i
# pensieri per le idee, ma ogni specie accumula in parallelo verso la propria soglia
# (DomesticAnimalRules.domestication_points_required). Unico punto che scrive GameData.domestication_points.
# Il primo superamento della soglia (passo 2) segna la specie in GameData.domesticated_species e lo comunica alla
# scena con effects.animal_domesticated (-> scoperta ANIMAL_DOMESTICATED); il primo animale vero arriva al passo 4.


# amount può essere negativo (lupi feriti o uccisi, passi futuri). Punti interi, mai sotto zero. Specie già addomesticata
# (2026-11-16, richiesta utente, come già per le piante): i punti restano fermi, né in più né in meno. false = nulla
# cambiato (specie inesistente, idea non nota o già addomesticata).
# effects null = nessuna scoperta (il superamento resta comunque registrato).
# reason: motivo per il log [DOMESTICATION POINTS] (2026-11-17, DebugLogging.SHOW_DOMESTICATION_POINTS_LOGS).
static func add_points(game_data: GameData, folk: Folk, species: String, amount: int, effects: GameEffects = null,
		reason: String = "") -> bool:
	var rules := DomesticAnimalCalculator.get_rules(species)
	# Pianta (2026-11-13, ramo delle piante: l'orzo): stesso registro, nessuna idea richiesta, niente punti dopo la soglia.
	var plant_rules := DomesticPlantCalculator.get_rules(species) if rules == null else null
	if rules == null and plant_rules == null:
		push_warning("DomesticationPointsService: specie domestica '%s' inesistente" % species)
		return false
	if game_data.domesticated_species.has(species):
		return false
	# Specie con idea richiesta (passo 3a): serve l'idea. Il cane (nessuna idea) accumula sempre: è addomesticando il lupo
	# che nasce l'idea. Regola del primo incontro tolta il 2026-11-12 (sarà la prima cattura viva a sbloccare la specie).
	if rules != null and rules.required_idea_id != "":
		if folk == null or not folk.completed_ideas.has(rules.required_idea_id):
			return false
	var required := rules.domestication_points_required if rules != null else plant_rules.domestication_points_required
	var before := get_points(game_data, species)
	var points := maxi(before + amount, 0)
	game_data.domestication_points[species] = points
	# Solo animali (le piante dell'orto delle prove darebbero una riga al giorno).
	if rules != null and DebugLogging.ENABLED and DebugLogging.SHOW_DOMESTICATION_POINTS_LOGS:
		print("[DOMESTICATION POINTS] anno=%d giorno=%d %s: %d -> %d (%+d) %s" % [
			game_data.year, game_data.current_day, species, before, points, amount, reason])
	DebugLogging.print_event("[DOMESTICATION] %s %d/%d (%+d)" % [species, points, required, amount])
	if points >= required and not game_data.domesticated_species.has(species):
		game_data.domesticated_species.append(species)
		game_data.domestication_years[species] = game_data.year
		DebugLogging.print_event("[DOMESTICATION] %s addomesticato per la prima volta" % species)
		if effects != null:
			effects.animal_domesticated(species)
	return true


# Specie scoperta (2026-11-12, passo C): visibile nel pannello. Il cane (nessuna idea richiesta) sempre; le altre dal
# primo animale vivo in tettoia (discover_species), o se già addomesticate.
static func is_discovered(game_data: GameData, species: String) -> bool:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null:
		# Piante (2026-11-13): sempre note, la carta c'è dal primo punto.
		return DomesticPlantCalculator.get_rules(species) != null
	return rules.required_idea_id == "" or game_data.discovered_domestic_species.has(species) \
		or game_data.domesticated_species.has(species)


# Scopre la specie (primo animale vivo in tettoia, o "+100" di debug) con una notifica. true se è nuova.
static func discover_species(game_data: GameData, species: String, effects: GameEffects = null) -> bool:
	if is_discovered(game_data, species):
		return false
	var rules := DomesticAnimalCalculator.get_rules(species)
	game_data.discovered_domestic_species.append(species)
	DebugLogging.print_event("[DOMESTICATION] specie scoperta: %s" % species)
	if effects != null:
		effects.notify(NotificationTypes.NotificationPopupType.DOMESTIC_SPECIES_DISCOVERED,
			GameContext.tr_text("domestication_species_discovered").format({
				"species": GameContext.tr_text("animal_species_" + rules.wild_species_name),
				"domestic": GameContext.tr_text(rules.display_name),
			}), true)
	return true


static func get_points(game_data: GameData, species: String) -> int:
	return int(game_data.domestication_points.get(species, 0))


# Avanzamento verso la soglia, 0..1 (servirà per l'aggressività del lupo: 1 - progresso).
static func get_progress(game_data: GameData, species: String) -> float:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null or rules.domestication_points_required <= 0:
		return 0.0
	return clampf(float(get_points(game_data, species)) / float(rules.domestication_points_required), 0.0, 1.0)
