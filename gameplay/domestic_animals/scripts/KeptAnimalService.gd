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


# Scelta "Nessuna" (2026-11-16, richiesta utente): Building.kept_species = NO_SPECIES, la tettoia resta in piedi (per
# un'emergenza) ma non accetta animali; i cesti la ignorano (TrapService.has_live_catch_building). Si sceglie solo a
# edificio vuoto, come le altre.
const NO_SPECIES := "none"


static func accepts_none(building: Building) -> bool:
	return building != null and fixed_species(building) == "" and building.kept_species == NO_SPECIES


# Specie fissa dell'edificio (2026-11-16, conigliera passo 1): conigliera e pollaio tengono solo la specie che li sblocca
# (BuildingRules.required_domesticated_species), senza scelta nel pannello e solo da addomesticata. "" = specie da scegliere
# (la tettoia delle gabbie).
static func fixed_species(building: Building) -> String:
	if building == null or building.rules == null or building.rules.animal_capacity <= 0:
		return ""
	return building.rules.required_domesticated_species


# Specie scelta: quella fissa dell'edificio, altrimenti quella del pannello ("" = Qualunque, NO_SPECIES = Nessuna).
static func chosen_species(building: Building) -> String:
	if building == null:
		return ""
	var fixed := fixed_species(building)
	return fixed if fixed != "" else building.kept_species


# Specie che l'edificio può tenere (scelta nel pannello), come specie domestiche di arrivo. La tettoia delle gabbie: le
# prede piccole delle mandrie (AnimalRules.max_hunters == 1, la stessa regola dei lacci) che hanno una specie domestica.
# Conigliera e pollaio: solo la loro specie fissa.
static func selectable_species(building: Building) -> Array[String]:
	var result: Array[String] = []
	if building == null or building.rules == null or building.rules.animal_capacity <= 0:
		return result
	var fixed := fixed_species(building)
	if fixed != "":
		result.append(fixed)
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
	if building == null or accepts_none(building):
		return ""
	if chosen_species(building) != "":
		return chosen_species(building)
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
	if accepts_none(building):
		return false
	if not selectable_species(building).has(species):
		return false
	# Specie fissa (conigliera, pollaio): solo animali domestici, quindi solo a specie addomesticata.
	if fixed_species(building) != "" and not DomesticAnimalService.is_domesticated(game_data, species):
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
# `same_kind_as` (2026-11-16): solo edifici dello stesso tipo di quello (tettoia → tettoie, allevamento → allevamenti):
# lo spostamento istantaneo dei piccoli non porta mai in conigliera, ci si arriva col trasporto.
static func find_building_with_room(game_data: GameData, world: World, species: String, macro_coords: Vector2i,
		reserved: Array = [], same_kind_as: Building = null) -> Building:
	if world == null:
		return null
	var best: Building = null
	var best_distance := INF
	for building in world.buildings:
		if not has_room_for(game_data, building, species, reserved):
			continue
		if same_kind_as != null and (fixed_species(building) != "") != (fixed_species(same_kind_as) != ""):
			continue
		var distance := Vector2(Vector2i(building.macro_x, building.macro_y) - macro_coords).length()
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


# Cambia la specie scelta: solo a edificio vuoto e fra quelle ammesse ("" = Qualunque, NO_SPECIES = Nessuna). true se
# cambiata.
static func set_kept_species(game_data: GameData, building: Building, species: String) -> bool:
	if building == null or not DomesticAnimalService.get_kept_animals(game_data, building.id).is_empty():
		return false
	if fixed_species(building) != "":
		return false
	if species != "" and species != NO_SPECIES and not selectable_species(building).has(species):
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
# KeepAnimalAction.entries). "space": lo spazio nello zaino (peso da vivo, live_space).
static func make_entry(wild_species: String, species: String, is_male: bool, age_band: int, building_id: int,
		trap_name: String) -> Dictionary:
	return {"wild_species": wild_species, "species": species, "is_male": is_male, "age_band": age_band,
		"building_id": building_id, "space": live_space(species, age_band), "trap_name": trap_name}


# Peso da vivo nello zaino di un animale di `species` (specie domestica) nella fascia `age_band` (2026-11-16):
# DomesticAnimalRules.live_carry_space_young/_adult (vecchi come adulti); senza dato, la resa macellata (TrapService.prey_space).
static func live_space(species: String, age_band: int) -> float:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules != null:
		var space := rules.live_carry_space_young if age_band == GameTypes.AgeBand.YOUNG else rules.live_carry_space_adult
		if space > 0.0:
			return space
	return TrapService.prey_space(species, age_band)


# Spazio degli animali vivi in braccio di chi fa `task` (2026-11-16): catture dei cesti nel context e tappe KeepAnimalAction
# ancora da fare. Pesa nel cammino (HumanIndividual.get_walk_load_space).
static func carried_live_space(task: Task) -> float:
	if task == null:
		return 0.0
	var space := entries_space(task.context.get(TrapService.CONTEXT_LIVE_ANIMALS, []))
	for i in range(task.current_step_index, task.steps.size()):
		var step := task.steps[i]
		if step is KeepAnimalAction:
			space += entries_space((step as KeepAnimalAction).entries)
	return space


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


# Nasce l'individuo nella tettoia (arrivo, KeepAnimalAction): sempre selvatico, anche a specie addomesticata (2026-11-16,
# richiesta utente — un coniglio preso nel bosco non diventa domestico: lo diventano i figli nati in cattività). Data di
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
		building.id, true)
	if animal != null:
		animal.captured_day = today
		count_stat(game_data, species, "captured")
		# Unico animale della tettoia (2026-11-14): il trappoliere lascia cibo per 3 giorni.
		if DomesticAnimalService.get_kept_animals(game_data, building.id).size() == 1:
			AnimalFeederService.add_starter_food(game_data, building, animal)
	return animal


# Animali di `species` chiusi adesso in tutte le tettoie.
static func kept_count(game_data: GameData, species: String) -> int:
	var count := 0
	for animal in game_data.domestic_animals:
		if animal.species == species and animal.building_id >= 0:
			count += 1
	return count


# Soglia "Macella oltre" della specie (GameData.domestic_slaughter_above), 0 = ∞.
static func species_slaughter_above(game_data: GameData, species: String) -> int:
	return maxi(int(game_data.domestic_slaughter_above.get(species, 0)), 0)


static func set_species_slaughter_above(game_data: GameData, species: String, value: int) -> void:
	if value > 0:
		game_data.domestic_slaughter_above[species] = value
	else:
		game_data.domestic_slaughter_above.erase(species)


# Soglia "Macella oltre" della tettoia (Building.slaughter_above), 0 = ∞, mai oltre la capienza.
static func building_slaughter_above(building: Building) -> int:
	if building == null or building.slaughter_above <= 0:
		return 0
	return mini(building.slaughter_above, capacity(building))


# true se la specie si tiene nelle tettoie (si cattura viva: punti di cattura); il cane no, è sempre libero.
static func can_be_kept(rules: DomesticAnimalRules) -> bool:
	return rules != null and (rules.capture_points_adult_male > 0 or rules.capture_points_adult_female > 0
		or rules.capture_points_young > 0 or rules.capture_points_old > 0)


# Giorni concessi a una tettoia oltre la capienza, con una soglia impostata, prima che i più giovani in più scappino
# (2026-11-14, richiesta utente: tempo per macellare).
const OVER_CAPACITY_GRACE_DAYS := 10


# true se per `building` e la specie `species` c'è almeno una soglia "Macella oltre": allora i piccoli entrano anche oltre
# la capienza (DomesticAnimalLifeService).
static func has_slaughter_threshold(game_data: GameData, building: Building, species: String) -> bool:
	return building_slaughter_above(building) > 0 or species_slaughter_above(game_data, species) > 0


# Giorni che restano prima che i più giovani in più scappino; -1 se la tettoia non è in attesa.
static func over_capacity_days_left(game_data: GameData, building: Building) -> int:
	if building == null or building.over_capacity_since_day < 0:
		return -1
	return maxi(OVER_CAPACITY_GRACE_DAYS - (game_data.get_absolute_day() - building.over_capacity_since_day), 0)


# Statistiche della cattività (GameData.domestication_stats): "captured", "died", "born".
static func count_stat(game_data: GameData, species: String, stat: String) -> void:
	var counts: Dictionary = game_data.domestication_stats.get(species, {})
	counts[stat] = int(counts.get(stat, 0)) + 1
	game_data.domestication_stats[species] = counts


static func get_stat(game_data: GameData, species: String, stat: String) -> int:
	return int(Dictionary(game_data.domestication_stats.get(species, {})).get(stat, 0))
