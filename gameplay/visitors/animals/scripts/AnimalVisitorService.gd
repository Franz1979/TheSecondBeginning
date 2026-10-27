class_name AnimalVisitorService
extends RefCounted

# Gruppi di animali che frequentano il villaggio (2026-10-26, richiesta utente) — stateless, come VisitorService per i
# gruppi umani. Crea i gruppi (uno per ogni AnimalVisitorRules in DATA_DIR) appena esiste un villaggio con centro,
# e li trova. Unico punto che aggiunge gruppi a GameData.animal_visitor_groups. Nessun comportamento qui.

const DATA_DIR := "res://gameplay/visitors/animals/data/"

static var _rules_cache: Dictionary = {}


static func get_rules(species: String) -> AnimalVisitorRules:
	if _rules_cache.has(species):
		return _rules_cache[species]
	var path := DATA_DIR + species + ".tres"
	var rules: AnimalVisitorRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as AnimalVisitorRules
	_rules_cache[species] = rules
	return rules


static func list_species() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return names
	for file_name in dir.get_files():
		# Build esportate: "*.tres.remap", come AnimalCalculator.list_species_names.
		var resource_file := String(file_name).trim_suffix(".remap")
		if resource_file.get_extension() == "tres" and not names.has(resource_file.get_basename()):
			names.append(resource_file.get_basename())
	names.sort()
	return names


static func find_group(game_data: GameData, species: String) -> AnimalVisitorGroup:
	for group in game_data.animal_visitor_groups:
		if group.species == species:
			return group
	return null


# Giornaliero (GameSimulation.tick_day): appena esiste un villaggio con centro, crea i gruppi mancanti. Copre sia la
# fondazione del villaggio sia le partite in corso caricate (entro un giorno).
static func ensure_groups(ctx: GameContext) -> void:
	if ctx.game_data == null or ctx.folk == null:
		return
	if not ctx.folk.villages.any(func(village: Village) -> bool: return village.center_building_id != -1):
		return
	for species in list_species():
		if find_group(ctx.game_data, species) == null:
			var group := create_group(ctx.game_data, species)
			if group != null:
				ctx.game_data.animal_visitor_groups.append(group)
				print("[ANIMAL VISITORS] gruppo #%d di %s creato: %d animali" % [group.id, species, group.animals.size()])


static func create_group(game_data: GameData, species: String) -> AnimalVisitorGroup:
	var rules := get_rules(species)
	if rules == null:
		push_warning("AnimalVisitorService: regole '%s' inesistenti" % species)
		return null
	var wild_rules := AnimalCalculator.get_animal_rules(rules.wild_species_name)
	var youth_years := wild_rules.youth_duration_years if wild_rules != null else 2
	var adult_years := wild_rules.adult_duration_years if wild_rules != null else 6
	var today := game_data.get_absolute_day()
	var group := AnimalVisitorGroup.new()
	group.id = game_data.next_animal_visitor_group_id
	game_data.next_animal_visitor_group_id += 1
	group.species = species
	if rules.initial_breeding_pair:
		_add_animal(group, true, today, randi_range(youth_years, youth_years + adult_years - 1),
			rules.adult_aggression_min, rules.adult_aggression_max)
		_add_animal(group, false, today, randi_range(youth_years, youth_years + adult_years - 1),
			rules.adult_aggression_min, rules.adult_aggression_max)
	for i in range(rules.initial_extra_adults):
		_add_animal(group, randf() < 0.5, today, randi_range(youth_years, youth_years + adult_years - 1),
			rules.adult_aggression_min, rules.adult_aggression_max)
	for i in range(rules.initial_young):
		_add_animal(group, randf() < 0.5, today, randi_range(1, maxi(youth_years - 1, 1)),
			rules.young_aggression_min, rules.young_aggression_max)
	for i in range(rules.initial_cubs):
		_add_animal(group, randf() < 0.5, today, 0, rules.cub_aggression_min, rules.cub_aggression_max)
	return group


# Età in anni compiuti più un giorno a caso dell'anno, così due animali della stessa età non nascono lo stesso giorno.
static func _add_animal(group: AnimalVisitorGroup, is_male: bool, today: int, age_years: int,
		aggression_min: float, aggression_max: float) -> void:
	var animal := AnimalVisitor.new()
	animal.id = group.next_animal_id
	group.next_animal_id += 1
	animal.is_male = is_male
	animal.birth_day = today - age_years * GameData.DAYS_PER_YEAR - randi_range(0, GameData.DAYS_PER_YEAR - 1)
	animal.aggression = randf_range(aggression_min, aggression_max)
	group.animals.append(animal)


# DEBUG — una riga per animale (sesso, età, fascia, aggressività), per il tooltip della DebugBar.
static func debug_lines(game_data: GameData, group: AnimalVisitorGroup) -> PackedStringArray:
	var lines: PackedStringArray = []
	var rules := get_rules(group.species)
	var wild_rules := AnimalCalculator.get_animal_rules(rules.wild_species_name) if rules != null else null
	var today := game_data.get_absolute_day()
	for animal in group.animals:
		lines.append("#%d %s, %d anni (%s), aggressività %d" % [
			animal.id, "M" if animal.is_male else "F", animal.get_age_years(today),
			GameTypes.AgeBand.keys()[animal.get_age_band(today, wild_rules)], roundi(animal.aggression)
		])
	return lines
