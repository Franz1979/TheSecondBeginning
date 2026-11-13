class_name KeptAnimalService
extends RefCounted

# Animali tenuti negli edifici (2026-11-12, richiesta utente — addomesticazione per cattura viva, passo B1). Oggi la tettoia
# delle gabbie (BuildingRules.animal_capacity > 0); domani recinto, stalla, pollaio. Gli animali sono DomesticAnimal con
# building_id = Building.id (DomesticAnimalService.add_kept_animal / get_kept_animals). La specie dell'edificio è
# Building.kept_species ("" = Qualunque: la fissa il primo animale che entra, finché l'edificio non torna vuoto); si cambia
# solo a edificio vuoto. Una sola specie per edificio. Stateless, statico.


# Specie domestica di arrivo per una selvatica (DomesticAnimalRules.wild_species_name): "rabbit" -> "domestic_rabbit".
# "" se nessuna specie domestica viene da lì.
static func domestic_species_for_wild(wild_species: String) -> String:
	for species in DomesticAnimalCalculator.list_species():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules != null and rules.wild_species_name == wild_species:
			return species
	return ""


# Specie che l'edificio può tenere (scelta nel pannello), come specie domestiche di arrivo. La tettoia delle gabbie: le
# prede piccole delle mandrie (AnimalRules.max_hunters == 1, la stessa regola dei lacci) che hanno una specie domestica.
static func selectable_species(building: Building) -> Array[String]:
	var result: Array[String] = []
	if building == null or building.rules == null or building.rules.animal_capacity <= 0:
		return result
	for wild_species in WildFaunaService.herd_species():
		var wild_rules := AnimalCalculator.get_animal_rules(wild_species)
		if wild_rules == null or wild_rules.max_hunters > 1:
			continue
		var domestic := domestic_species_for_wild(wild_species)
		if domestic != "" and not result.has(domestic):
			result.append(domestic)
	return result


# Specie tenuta adesso: quella scelta, altrimenti quella del primo animale dentro, altrimenti quella del primo posto
# prenotato (`reserved`, voci make_entry), altrimenti "" (vuota e Qualunque).
static func current_species(game_data: GameData, building: Building, reserved: Array = []) -> String:
	if building == null:
		return ""
	if building.kept_species != "":
		return building.kept_species
	var animals := DomesticAnimalService.get_kept_animals(game_data, building.id)
	if not animals.is_empty():
		return animals[0].species
	for entry in reserved:
		if int(entry.get("building_id", -1)) == building.id:
			return String(entry.get("species", ""))
	return ""


static func capacity(building: Building) -> int:
	return building.rules.animal_capacity if building != null and building.rules != null else 0


# true se l'edificio, finito, ha un posto libero per un animale di `species` (specie domestica). `reserved`: posti già
# prenotati da chi porta un animale (reservations, voci make_entry): occupano un posto e fissano la specie.
static func has_room_for(game_data: GameData, building: Building, species: String, reserved: Array = []) -> bool:
	if building == null or not building.is_complete or capacity(building) <= 0 or building.is_out_of_service():
		return false
	if not selectable_species(building).has(species):
		return false
	var current := current_species(game_data, building, reserved)
	if current != "" and current != species:
		return false
	var taken := DomesticAnimalService.get_kept_animals(game_data, building.id).size()
	for entry in reserved:
		if int(entry.get("building_id", -1)) == building.id:
			taken += 1
	return taken < capacity(building)


# Edificio con posto per `species`, il più vicino a `macro_coords` (prima quelli della stessa macrocella). null se nessuno.
static func find_building_with_room(game_data: GameData, world: World, species: String, macro_coords: Vector2i,
		reserved: Array = []) -> Building:
	if world == null:
		return null
	var best: Building = null
	var best_distance := INF
	for building in world.buildings:
		if not has_room_for(game_data, building, species, reserved):
			continue
		var distance := Vector2(Vector2i(building.macro_x, building.macro_y) - macro_coords).length()
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


# Cambia la specie scelta: solo a edificio vuoto e fra quelle ammesse ("" = Qualunque). true se cambiata.
static func set_kept_species(game_data: GameData, building: Building, species: String) -> bool:
	if building == null or not DomesticAnimalService.get_kept_animals(game_data, building.id).is_empty():
		return false
	if species != "" and not selectable_species(building).has(species):
		return false
	building.kept_species = species
	return true


# Nome mostrato di un animale tenuto: la selvatica d'origine finché non è addomesticato ("Coniglio"), poi la domestica.
static func display_name(animal: DomesticAnimal) -> String:
	return species_display_name(animal.species, animal.is_wild)


static func species_display_name(species: String, wild: bool) -> String:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null:
		return species
	if wild and rules.wild_species_name != "":
		return GameContext.tr_text("animal_species_%s" % rules.wild_species_name)
	return GameContext.tr_text(rules.display_name)


# --- Trasporto dai cesti (passo B2, 2026-11-12) ---

# Voce di un animale vivo portato in braccio verso la tettoia `building_id` (TrapService.CONTEXT_LIVE_ANIMALS e
# KeepAnimalAction.entries). "space": lo spazio nello zaino (la sua carne, TrapService.prey_space).
static func make_entry(wild_species: String, species: String, is_male: bool, age_band: int, building_id: int,
		trap_name: String) -> Dictionary:
	return {"wild_species": wild_species, "species": species, "is_male": is_male, "age_band": age_band,
		"building_id": building_id, "space": TrapService.prey_space(wild_species, age_band), "trap_name": trap_name}


# Posti prenotati: gli animali in braccio di tutti (context dei giri e tappe KeepAnimalAction ancora da fare), tranne
# quelli di `excluded` (la tappa che li sta sistemando). Si ricavano dalle Task aperte: una Task abbandonata li libera.
static func reservations(individuals: Array[HumanIndividual], excluded: Action = null) -> Array:
	var result: Array = []
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			result.append_array(task.context.get(TrapService.CONTEXT_LIVE_ANIMALS, []))
			for i in range(task.current_step_index, task.steps.size()):
				var step := task.steps[i]
				if step is KeepAnimalAction and step != excluded:
					result.append_array((step as KeepAnimalAction).entries)
	return result


# Spazio nello zaino degli animali in braccio `entries`.
static func entries_space(entries: Array) -> float:
	var space := 0.0
	for entry in entries:
		space += float(entry.get("space", 0.0))
	return space


# Punti addomesticazione per l'animale `entry` arrivato vivo in tettoia (DomesticAnimalRules.capture_points_*).
static func capture_points(entry: Dictionary) -> int:
	var rules := DomesticAnimalCalculator.get_rules(String(entry.get("species", "")))
	if rules == null:
		return 0
	match int(entry.get("age_band", GameTypes.AgeBand.ADULT)):
		GameTypes.AgeBand.YOUNG:
			return rules.capture_points_young
		GameTypes.AgeBand.OLD:
			return rules.capture_points_old
	return rules.capture_points_adult_male if bool(entry.get("is_male", false)) else rules.capture_points_adult_female


# Nasce l'individuo nella tettoia (arrivo, KeepAnimalAction): selvatico finché la specie non è addomesticata. Data di
# nascita stimata a metà della sua fascia d'età (la trappola segna solo la fascia).
static func keep_animal(game_data: GameData, building: Building, entry: Dictionary) -> DomesticAnimal:
	var species := String(entry.get("species", ""))
	var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
	var age_years := 1.0
	if wild_rules != null:
		match int(entry.get("age_band", GameTypes.AgeBand.ADULT)):
			GameTypes.AgeBand.YOUNG:
				age_years = wild_rules.youth_duration_years * 0.5
			GameTypes.AgeBand.OLD:
				age_years = wild_rules.youth_duration_years + wild_rules.adult_duration_years + 0.5
			_:
				age_years = wild_rules.youth_duration_years + wild_rules.adult_duration_years * 0.5
	var today := game_data.get_absolute_day()
	var birth_day := today - int(age_years * GameData.DAYS_PER_YEAR)
	var animal := DomesticAnimalService.add_kept_animal(game_data, species, bool(entry.get("is_male", false)), birth_day,
		building.id, not DomesticAnimalService.is_domesticated(game_data, species))
	if animal != null:
		animal.captured_day = today
		count_stat(game_data, species, "captured")
	return animal


# Statistiche della cattività (GameData.domestication_stats): "captured", "died", "born".
static func count_stat(game_data: GameData, species: String, stat: String) -> void:
	var counts: Dictionary = game_data.domestication_stats.get(species, {})
	counts[stat] = int(counts.get(stat, 0)) + 1
	game_data.domestication_stats[species] = counts


static func get_stat(game_data: GameData, species: String, stat: String) -> int:
	return int(Dictionary(game_data.domestication_stats.get(species, {})).get(stat, 0))
