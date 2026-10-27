class_name DomesticationPointsService
extends RefCounted

# Punti addomesticazione per specie domestica (addomesticazione passo 1, 2026-10-26, richiesta utente): come i
# pensieri per le idee, ma ogni specie accumula in parallelo verso la propria soglia
# (DomesticAnimalRules.domestication_points_required). Unico punto che scrive GameData.domestication_points.
# Il primo superamento della soglia (passo 2) segna la specie in GameData.domesticated_species e lo comunica alla
# scena con effects.animal_domesticated (-> scoperta ANIMAL_DOMESTICATED); il primo animale vero arriva al passo 4.


# amount può essere negativo (lupi feriti o uccisi, passi futuri). Punti interi, mai sotto zero e senza tetto:
# l'eccedenza oltre la soglia porterà altri animali. false = nulla cambiato (specie inesistente, idea non nota o selvatica
# non incontrata).
# effects null = nessuna scoperta (il superamento resta comunque registrato).
static func add_points(game_data: GameData, folk: Folk, species: String, amount: int, effects: GameEffects = null) -> bool:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null:
		push_warning("DomesticationPointsService: specie domestica '%s' inesistente" % species)
		return false
	# Specie con idea richiesta (passo 3a): servono l'idea e l'incontro con la selvatica. Il cane (nessuna idea) accumula
	# sempre: è addomesticando il lupo che nasce l'idea.
	if rules.required_idea_id != "":
		if folk == null or not folk.completed_ideas.has(rules.required_idea_id):
			return false
		if not DomesticationEncounterService.is_encountered(game_data, rules.wild_species_name):
			return false
	var points := maxi(get_points(game_data, species) + amount, 0)
	game_data.domestication_points[species] = points
	print("[DOMESTICATION] %s %d/%d (%+d)" % [species, points, rules.domestication_points_required, amount])
	if points >= rules.domestication_points_required and not game_data.domesticated_species.has(species):
		game_data.domesticated_species.append(species)
		print("[DOMESTICATION] %s addomesticato per la prima volta" % species)
		if effects != null:
			effects.animal_domesticated(species)
	return true


static func get_points(game_data: GameData, species: String) -> int:
	return int(game_data.domestication_points.get(species, 0))


# Avanzamento verso la soglia, 0..1 (servirà per l'aggressività del lupo: 1 - progresso).
static func get_progress(game_data: GameData, species: String) -> float:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null or rules.domestication_points_required <= 0:
		return 0.0
	return clampf(float(get_points(game_data, species)) / float(rules.domestication_points_required), 0.0, 1.0)
