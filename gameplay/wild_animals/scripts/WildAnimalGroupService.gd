class_name WildAnimalGroupService
extends RefCounted

# Gruppi di animali selvatici seguiti uno per uno (2026-10-26, richiesta utente) — stateless, come VisitorService per i
# gruppi umani. Crea i gruppi (uno per ogni WildAnimalGroupRules in DATA_DIR) appena esiste un magazzino,
# e li trova; ogni giorno li fa evolvere (tick_day: nascite, morti, partenze). Unico punto che aggiunge o toglie
# gruppi e animali in GameData.wild_animal_groups. Dati simulati ma coerenti, niente realismo pieno.

const DATA_DIR := "res://gameplay/wild_animals/data/groups/"
# I file si chiamano {species}_group.tres, per non confonderli con i file della specie (simulation/data/animals/).
const FILE_SUFFIX := "_group.tres"

static var _rules_cache: Dictionary = {}


static func get_rules(species: String) -> WildAnimalGroupRules:
	if _rules_cache.has(species):
		return _rules_cache[species]
	var path := DATA_DIR + species + FILE_SUFFIX
	var rules: WildAnimalGroupRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as WildAnimalGroupRules
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
		if resource_file.ends_with(FILE_SUFFIX):
			var species := resource_file.trim_suffix(FILE_SUFFIX)
			if not names.has(species):
				names.append(species)
	names.sort()
	return names


static func find_group(game_data: GameData, species: String) -> WildAnimalGroup:
	for group in game_data.wild_animal_groups:
		if group.species == species:
			return group
	return null


# Giornaliero (GameSimulation.tick_day): appena esiste un magazzino (find_anchor_storage; dal 2026-10-28, richiesta
# utente — prima serviva un villaggio con centro), crea i gruppi mancanti. Copre sia il primo magazzino sia le partite in
# corso caricate (entro un giorno).
static func ensure_groups(ctx: GameContext) -> void:
	if ctx.game_data == null or ctx.world == null:
		return
	if find_anchor_storage(ctx.world) == null:
		return
	for species in list_species():
		if find_group(ctx.game_data, species) == null:
			var group := create_group(ctx.game_data, species)
			if group != null:
				ctx.game_data.wild_animal_groups.append(group)
				print("[WILD ANIMAL GROUPS] gruppo #%d di %s creato: %d animali" % [group.id, species, group.animals.size()])


# Il magazzino che attira gli animali (2026-10-28, richiesta utente: basta un magazzino): il primo edificio di deposito
# completo e in servizio (WarehouseManagerService.is_storage_building), esclusa la Fossa dei rifiuti. null se nessuno.
# Le probabilità di visita dipenderanno da altri fattori (fosse, abitanti): questo è solo il requisito.
static func find_anchor_storage(world: World) -> Building:
	for building in world.buildings:
		if WarehouseManagerService.is_storage_building(building) and not WasteDisposalService.is_pit(building):
			return building
	return null


static func create_group(game_data: GameData, species: String) -> WildAnimalGroup:
	var rules := get_rules(species)
	if rules == null:
		push_warning("WildAnimalGroupService: regole '%s' inesistenti" % species)
		return null
	var wild_rules := AnimalCalculator.get_animal_rules(rules.wild_species_name)
	var youth_years := wild_rules.youth_duration_years if wild_rules != null else 2
	var adult_years := wild_rules.adult_duration_years if wild_rules != null else 6
	var today := game_data.get_absolute_day()
	var group := WildAnimalGroup.new()
	group.id = game_data.next_wild_animal_group_id
	game_data.next_wild_animal_group_id += 1
	group.species = species
	if rules.initial_breeding_pair:
		group.breeding_male_id = _add_animal(group, true, today,
			randi_range(youth_years, youth_years + adult_years - 1), rules.initial_aggression).id
		group.breeding_female_id = _add_animal(group, false, today,
			randi_range(youth_years, youth_years + adult_years - 1), rules.initial_aggression).id
	for i in range(rules.initial_extra_adults):
		_add_animal(group, randf() < 0.5, today, randi_range(youth_years, youth_years + adult_years - 1),
			rules.initial_aggression)
	for i in range(rules.initial_young):
		_add_animal(group, randf() < 0.5, today, randi_range(1, maxi(youth_years - 1, 1)), rules.initial_aggression)
	for i in range(rules.initial_cubs):
		_add_animal(group, randf() < 0.5, today, 0, rules.initial_aggression)
	return group


# Età in anni compiuti più un giorno a caso dell'anno, così due animali della stessa età non nascono lo stesso giorno.
static func _add_animal(group: WildAnimalGroup, is_male: bool, today: int, age_years: int,
		aggression: float) -> WildAnimal:
	var animal := WildAnimal.new()
	animal.id = group.next_animal_id
	group.next_animal_id += 1
	animal.is_male = is_male
	animal.birth_day = today - age_years * GameData.DAYS_PER_YEAR - randi_range(0, GameData.DAYS_PER_YEAR - 1)
	animal.aggression = aggression
	group.animals.append(animal)
	return animal


# Giornaliero (GameSimulation.tick_day, dopo ensure_groups), richiesta utente 2026-10-27. Per ogni gruppo, in ordine:
# morti per vecchiaia → rimpiazzo della coppia → cucciolata (primo giorno della stagione delle nascite) → partenze
# oltre il tetto. Pochi animali per gruppo: il giro giornaliero non costa nulla.
static func tick_day(ctx: GameContext) -> void:
	if ctx.game_data == null:
		return
	for group in ctx.game_data.wild_animal_groups:
		var rules := get_rules(group.species)
		var wild_rules := AnimalCalculator.get_animal_rules(rules.wild_species_name) if rules != null else null
		if wild_rules == null:
			continue
		var today := ctx.game_data.get_absolute_day()
		_remove_dead_of_old_age(group, wild_rules, today)
		_ensure_breeding_pair(group, rules, wild_rules, today)
		_give_birth_if_season(ctx.game_data, group, rules, wild_rules, today)
		_disperse_over_cap(group, rules, wild_rules, today)


# Muoiono solo i vecchi, a fine fascia "vecchio" (youth + adult + old anni della specie).
static func _remove_dead_of_old_age(group: WildAnimalGroup, wild_rules: AnimalRules, today: int) -> void:
	var max_age := wild_rules.youth_duration_years + wild_rules.adult_duration_years + wild_rules.old_duration_years
	for animal in group.animals.duplicate():
		if animal.get_age_years(today) >= max_age:
			group.animals.erase(animal)
			print("[WILD ANIMAL GROUPS] %s #%d morto di vecchiaia (%d anni)" % [
				group.species, animal.id, animal.get_age_years(today)])


# Manca un riproduttore: lo rimpiazza l'adulto (o vecchio) più giovane dello stesso sesso, per coppie più stabili; se
# non c'è, il branco ingloba un solitario: un adulto da fuori con l'aggressività iniziale. Copre anche i salvataggi
# senza coppia registrata.
static func _ensure_breeding_pair(group: WildAnimalGroup, rules: WildAnimalGroupRules, wild_rules: AnimalRules,
		today: int) -> void:
	for is_male: bool in [true, false]:
		var current_id := group.breeding_male_id if is_male else group.breeding_female_id
		if group.find_animal(current_id) != null:
			continue
		var replacement: WildAnimal = null
		for animal in group.animals:
			if animal.is_male != is_male or animal.get_age_band(today, wild_rules) == GameTypes.AgeBand.YOUNG:
				continue
			if replacement == null or animal.birth_day > replacement.birth_day:
				replacement = animal
		var origin := "dal gruppo"
		if replacement == null:
			replacement = _add_animal(group, is_male, today, wild_rules.youth_duration_years + randi_range(0, 2),
				rules.initial_aggression)
			origin = "solitario inglobato"
		if is_male:
			group.breeding_male_id = replacement.id
		else:
			group.breeding_female_id = replacement.id
		print("[WILD ANIMAL GROUPS] %s #%d nuovo riproduttore %s (%s)" % [
			group.species, replacement.id, "maschio" if is_male else "femmina", origin])


# Una cucciolata all'anno, dal primo giorno della stagione delle nascite della specie (AnimalRules.birth_season).
# I cuccioli partono dalla media dell'aggressività dei genitori: se la coppia si abitua al villaggio, anche i figli.
static func _give_birth_if_season(game_data: GameData, group: WildAnimalGroup, rules: WildAnimalGroupRules,
		wild_rules: AnimalRules, today: int) -> void:
	if group.last_litter_year == game_data.year:
		return
	if SeasonCalculator.get_season_for_day(game_data.current_day) != wild_rules.birth_season:
		return
	var father := group.find_animal(group.breeding_male_id)
	var mother := group.find_animal(group.breeding_female_id)
	if father == null or mother == null:
		return
	group.last_litter_year = game_data.year
	var aggression := (father.aggression + mother.aggression) / 2.0
	var litter := randi_range(rules.litter_min, rules.litter_max)
	for i in range(litter):
		var cub := _add_animal(group, randf() < 0.5, today, 0, aggression)
		cub.birth_day = today
	print("[WILD ANIMAL GROUPS] %s: nati %d cuccioli (aggressività %d), gruppo di %d" % [
		group.species, litter, roundi(aggression), group.animals.size()])


# Oltre il tetto se ne vanno i giovani più grandi (mai i riproduttori); senza giovani, l'adulto non riproduttore più
# anziano.
static func _disperse_over_cap(group: WildAnimalGroup, rules: WildAnimalGroupRules, wild_rules: AnimalRules,
		today: int) -> void:
	while group.animals.size() > rules.max_group_size:
		var leaving: WildAnimal = null
		var leaving_is_young := false
		for animal in group.animals:
			if animal.id == group.breeding_male_id or animal.id == group.breeding_female_id:
				continue
			var is_young := animal.get_age_band(today, wild_rules) == GameTypes.AgeBand.YOUNG
			if leaving == null or (is_young and not leaving_is_young) \
					or (is_young == leaving_is_young and animal.birth_day < leaving.birth_day):
				leaving = animal
				leaving_is_young = is_young
		if leaving == null:
			return
		group.animals.erase(leaving)
		print("[WILD ANIMAL GROUPS] %s #%d lascia il gruppo (%d anni), restano %d" % [
			group.species, leaving.id, leaving.get_age_years(today), group.animals.size()])


# DEBUG — una riga per animale (★ riproduttore, sesso, età, fascia, aggressività), per il tooltip della DebugBar.
static func debug_lines(game_data: GameData, group: WildAnimalGroup) -> PackedStringArray:
	var lines: PackedStringArray = []
	var rules := get_rules(group.species)
	var wild_rules := AnimalCalculator.get_animal_rules(rules.wild_species_name) if rules != null else null
	var today := game_data.get_absolute_day()
	for animal in group.animals:
		var breeder := " ★" if animal.id == group.breeding_male_id or animal.id == group.breeding_female_id else ""
		lines.append("#%d%s %s, %d anni (%s), aggressività %d" % [
			animal.id, breeder, "M" if animal.is_male else "F", animal.get_age_years(today),
			GameTypes.AgeBand.keys()[animal.get_age_band(today, wild_rules)], roundi(animal.aggression)
		])
	return lines
