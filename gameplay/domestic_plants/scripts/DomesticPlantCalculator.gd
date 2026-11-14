class_name DomesticPlantCalculator
extends RefCounted

# Caricatore delle specie vegetali da addomesticare (2026-11-13, punto 2): stesso schema di DomesticAnimalCalculator, una
# specie nuova compare da sola appena si aggiunge il suo .tres. Anche i punti guadagnati raccogliendo e cucinando.

const DATA_DIR := "res://gameplay/domestic_plants/data/"

static var _rules_cache: Dictionary = {}


static func get_rules(species_name: String) -> DomesticPlantRules:
	if _rules_cache.has(species_name):
		return _rules_cache[species_name]
	var path := DATA_DIR + species_name + ".tres"
	var rules: DomesticPlantRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as DomesticPlantRules
	_rules_cache[species_name] = rules
	return rules


static func list_species() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var resource_file := file_name.trim_suffix(".remap")
		if not dir.current_is_dir() and resource_file.ends_with(".tres") and not names.has(resource_file.get_basename()):
			names.append(resource_file.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


# Unità raccolte in attesa nel context della Task: {specie: unità}. Convertite in punti a fine tappa
# (HumanIndividualActionService, units_to_points) prima di CONTEXT_PENDING_DOMESTICATION_POINTS.
const CONTEXT_PENDING_HARVEST_UNITS := "pending_plant_harvest_units"


# Annota nel context `quantity` unità di `resource_name` raccolte da terra, per ogni specie che la usa.
static func add_harvest(context: Dictionary, resource_name: String, quantity: int) -> void:
	if quantity <= 0:
		return
	for species in list_species():
		var rules := get_rules(species)
		if rules == null or rules.harvest_resource_name != resource_name or rules.harvested_units_per_point <= 0:
			continue
		var pending: Dictionary = context.get(CONTEXT_PENDING_HARVEST_UNITS, {})
		pending[species] = int(pending.get(species, 0)) + quantity
		context[CONTEXT_PENDING_HARVEST_UNITS] = pending


# Unità raccolte -> punti interi ({specie: punti}), col resto conservato in GameData.domestication_harvest_units.
# Una specie già addomesticata non accumula più.
static func units_to_points(game_data: GameData, units: Dictionary) -> Dictionary:
	var points: Dictionary = {}
	if game_data == null:
		return points
	for species in units.keys():
		var rules := get_rules(String(species))
		if rules == null or rules.harvested_units_per_point <= 0 or game_data.domesticated_species.has(String(species)):
			continue
		var total := int(game_data.domestication_harvest_units.get(species, 0)) + int(units[species])
		var whole := total / rules.harvested_units_per_point
		game_data.domestication_harvest_units[String(species)] = total - whole * rules.harvested_units_per_point
		whole = capped_wild_points(game_data, String(species), whole)
		if whole > 0:
			points[String(species)] = whole
	return points


# Punti da raccolta e zuppa ridotti al tetto della specie (2026-11-15, DomesticPlantRules.wild_points_cap): mai oltre il
# tetto contando i punti già fatti; 0 se il tetto è già raggiunto. Senza tetto: `points` invariati.
static func capped_wild_points(game_data: GameData, species: String, points: int) -> int:
	var rules := get_rules(species)
	if rules == null or rules.wild_points_cap <= 0 or game_data == null:
		return points
	return clampi(rules.wild_points_cap - DomesticationPointsService.get_points(game_data, species), 0, points)


# Punti per un pasto cucinato con `ingredients` (nome -> pezzi): {specie: punti}.
static func meal_points(ingredients: Dictionary) -> Dictionary:
	var points: Dictionary = {}
	for species in list_species():
		var rules := get_rules(species)
		if rules != null and rules.points_per_meal > 0 and int(ingredients.get(rules.harvest_resource_name, 0)) > 0:
			var meal := capped_wild_points(GameSettings.active_game_data, species, rules.points_per_meal)
			if meal > 0:
				points[species] = meal
	return points


# Punti per `count` pezzi prodotti di `resource_name` (ProduceAction): {specie: punti}, dentro il tetto.
static func product_points(resource_name: String, count: int) -> Dictionary:
	var points: Dictionary = {}
	if count <= 0:
		return points
	for species in list_species():
		var rules := get_rules(species)
		if rules == null or rules.points_per_product <= 0 or rules.product_resource_name != resource_name:
			continue
		if GameSettings.active_game_data != null and GameSettings.active_game_data.domesticated_species.has(species):
			continue
		var earned := capped_wild_points(GameSettings.active_game_data, species, rules.points_per_product * count)
		if earned > 0:
			points[species] = earned
	return points


# Somma `extra` ({specie: punti}) nei punti in attesa del context (HumanIndividualActionService.
# CONTEXT_PENDING_DOMESTICATION_POINTS): la scena li assegna a fine tappa, con l'eventuale scoperta.
static func add_pending_points(context: Dictionary, extra: Dictionary) -> void:
	if extra.is_empty():
		return
	var pending: Dictionary = context.get(HumanIndividualActionService.CONTEXT_PENDING_DOMESTICATION_POINTS, {})
	for species in extra.keys():
		pending[species] = int(pending.get(species, 0)) + int(extra[species])
	context[HumanIndividualActionService.CONTEXT_PENDING_DOMESTICATION_POINTS] = pending
