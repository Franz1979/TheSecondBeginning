class_name AnimalFeederService
extends RefCounted

# Mangiatoia degli edifici con animali (2026-11-13, punto 4, passo 2 — decisione utente "A"): come la saccoccia del cibo
# delle persone, SPAZIO e CALORIE, non un magazzino. Capienza in spazio (BuildingRules.feeder_space_capacity); alla
# consegna ogni unità di cibo occupa il suo spazio (SecondaryResourceRules.space_per_unit, Building.feeder_space_used) e
# diventa calorie per gli animali (animal_calories_per_unit se > 0, altrimenti calories_per_unit, Building.
# feeder_calories); la risorsa sparisce. Accetta solo i cibi della specie tenuta (DomesticAnimalRules.accepted_foods di
# KeptAnimalService.current_species): con "Qualunque" e nessun animale non accetta niente. Il contenuto è "di" una specie
# (Building.feeder_species): se la specie tenuta cambia, la mangiatoia si svuota e il cibo è perso, così il cambio di
# specie non serve a convertire il cibo. Niente deperimento. Consegna col Trasporto manuale (sotto); consumo nel passo dopo. Stateless,
# statico.


# Spazio della mangiatoia (0 = nessuna).
static func capacity(building: Building) -> int:
	return building.rules.feeder_space_capacity if building != null and building.rules != null else 0


# true per un edificio finito, in piedi, con una mangiatoia.
static func has_feeder(building: Building) -> bool:
	return building != null and capacity(building) > 0 and building.is_complete and not building.is_demolished


# Calorie di un'unità di `resource_name` mangiata da un animale.
static func food_calories(resource_name: String) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null:
		return 0.0
	return rules.animal_calories_per_unit if rules.animal_calories_per_unit > 0.0 else rules.calories_per_unit


# Cibi della specie tenuta adesso ([] se non è decisa).
static func accepted_foods(game_data: GameData, building: Building) -> Array[String]:
	var species := KeptAnimalService.current_species(game_data, building)
	var rules := DomesticAnimalCalculator.get_rules(species) if species != "" else null
	return rules.accepted_foods if rules != null else ([] as Array[String])


# true se il contenuto è di un'altra specie rispetto a quella tenuta adesso (vale come vuoto, si svuoterà: sync_species).
static func _belongs_to_other_species(game_data: GameData, building: Building) -> bool:
	var species := KeptAnimalService.current_species(game_data, building)
	return species != "" and building.feeder_species != "" and building.feeder_species != species


# Calorie nella mangiatoia che valgono per la specie tenuta adesso.
static func calories(game_data: GameData, building: Building) -> float:
	if building == null or _belongs_to_other_species(game_data, building):
		return 0.0
	return building.feeder_calories


# Spazio occupato che vale per la specie tenuta adesso.
static func space_used(game_data: GameData, building: Building) -> float:
	if building == null or _belongs_to_other_species(game_data, building):
		return 0.0
	return building.feeder_space_used


# Allinea la mangiatoia alla specie tenuta: specie cambiata -> svuotata, cibo perso. Con la specie non decisa resta com'è
# (se poi arriva la stessa specie, il contenuto resta buono).
static func sync_species(game_data: GameData, building: Building) -> void:
	if building == null:
		return
	var species := KeptAnimalService.current_species(game_data, building)
	if species == "" or species == building.feeder_species:
		return
	if building.feeder_calories > 0.0:
		DebugLogging.print_event("[FEEDER] Edificio %d: specie cambiata da '%s' a '%s', mangiatoia svuotata (%.1f calorie perse)" % [
			building.id, building.feeder_species, species, building.feeder_calories])
	building.feeder_species = species
	building.feeder_calories = 0.0
	building.feeder_space_used = 0.0


# --- Consegna col Trasporto (2026-11-14, richiesta utente: prima il riempimento manuale) ---
# TaskBuilderService.transport_trip_target (quanto portare a ogni viaggio, 0 = comando rifiutato) e UnloadAction (lo
# scarico). L'avanzo che non ci sta segue il reinstradamento di sempre.

# true se la mangiatoia di `building` accetta `resource_name` adesso (specie decisa, cibo della sua dieta, con calorie).
static func accepts(game_data: GameData, building: Building, resource_name: String) -> bool:
	return has_feeder(building) and accepted_foods(game_data, building).has(resource_name) and food_calories(resource_name) > 0.0


# Unità di `resource_name` che ci stanno ancora in spazio (unità intere). Un cibo senza spazio (space_per_unit 0) occupa
# comunque 1 per unità, così la mangiatoia ha un limite.
static func max_depositable(game_data: GameData, building: Building, resource_name: String) -> int:
	if not accepts(game_data, building, resource_name):
		return 0
	var room := float(capacity(building)) - space_used(game_data, building)
	return maxi(floori(room / _unit_space(resource_name) + 0.000001), 0)


# Versa fino a `quantity` unità di `resource_name`; ritorna quante ne sono entrate. Lo zaino lo svuota chi chiama.
static func deposit(game_data: GameData, building: Building, resource_name: String, quantity: int) -> int:
	sync_species(game_data, building)
	var units := mini(quantity, max_depositable(game_data, building, resource_name))
	if units <= 0:
		return 0
	building.feeder_species = KeptAnimalService.current_species(game_data, building)
	building.feeder_space_used = minf(building.feeder_space_used + float(units) * _unit_space(resource_name), float(capacity(building)))
	building.feeder_calories += float(units) * food_calories(resource_name)
	DebugLogging.print_event("[FEEDER] Edificio %d: +%d %s, mangiatoia %.1f/%d spazio, %.1f calorie" % [building.id, units, resource_name,
		building.feeder_space_used, capacity(building), building.feeder_calories])
	return units


# Scorta del trappoliere (2026-11-14, richiesta utente): quando deposita un animale in una tettoia che resta con quel solo
# animale, la mangiatoia arriva ad almeno STARTER_FOOD_DAYS giorni della sua razione. Il cibo compare (nessun magazzino),
# con lo spazio del primo cibo della dieta che ha calorie, entro lo spazio libero.
const STARTER_FOOD_DAYS := 3


static func add_starter_food(game_data: GameData, building: Building, animal: DomesticAnimal) -> void:
	if animal == null or not has_feeder(building):
		return
	sync_species(game_data, building)
	var missing := daily_ration(game_data, animal) * STARTER_FOOD_DAYS - building.feeder_calories
	if missing <= 0.0:
		return
	var space_per_calorie := 0.0
	for food in accepted_foods(game_data, building):
		if food_calories(food) > 0.0:
			space_per_calorie = _unit_space(food) / food_calories(food)
			break
	if space_per_calorie <= 0.0:
		return
	missing = minf(missing, maxf(float(capacity(building)) - building.feeder_space_used, 0.0) / space_per_calorie)
	if missing <= 0.0:
		return
	building.feeder_calories += missing
	building.feeder_space_used += missing * space_per_calorie
	DebugLogging.print_event("[FEEDER] Edificio %d: scorta del trappoliere, +%.1f calorie (%d giorni per %s)" % [building.id, missing,
		STARTER_FOOD_DAYS, animal.species])


static func _unit_space(resource_name: String) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules.space_per_unit if rules != null and rules.space_per_unit > 0.0 else 1.0


# --- Chi mangia dalla mangiatoia (2026-11-14, regola del WM; servirà anche alla fame) ---

# true se `animal`, chiuso in un edificio, mangia adesso dal villaggio: sempre in addomesticazione (selvatico), d'inverno
# da addomesticato (il resto dell'anno si arrangia).
static func eats_now(game_data: GameData, animal: DomesticAnimal) -> bool:
	if animal == null or animal.building_id < 0:
		return false
	if animal.is_wild:
		return true
	return SeasonCalculator.get_season_for_day(game_data.current_day) == GameTypes.Season.WINTER


# Calorie al giorno degli animali di `building` che mangiano adesso (DomesticAnimalRules.daily_calories, i piccoli metà).
static func daily_calories_needed(game_data: GameData, building: Building) -> float:
	if game_data == null or building == null:
		return 0.0
	var today := game_data.get_absolute_day()
	var total := 0.0
	for animal in DomesticAnimalService.get_kept_animals(game_data, building.id):
		if not eats_now(game_data, animal):
			continue
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null:
			continue
		var young := animal.get_age_band(today, DomesticAnimalCalculator.get_wild_rules(animal.species)) == GameTypes.AgeBand.YOUNG
		total += rules.daily_calories * (0.5 if young else 1.0)
	return total


# Razione di oggi di `animal` (DomesticAnimalRules.daily_calories, i giovani il 50%).
static func daily_ration(game_data: GameData, animal: DomesticAnimal) -> float:
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	if rules == null:
		return 0.0
	var young := animal.get_age_band(game_data.get_absolute_day(), DomesticAnimalCalculator.get_wild_rules(animal.species)) == GameTypes.AgeBand.YOUNG
	return rules.daily_calories * (0.5 if young else 1.0)


# Pasto del giorno (2026-11-14, fame — DomesticAnimalLifeService.tick_day): gli animali di `building` che mangiano adesso
# prendono la loro razione intera dalla mangiatoia; prima chi è digiuno da più giorni, così il cibo gira. Chi non la trova
# conta un giorno in più senza cibo, chi mangia (o non mangia dal villaggio) torna a 0. Lo spazio scende in proporzione
# alle calorie, come nella saccoccia. Ritorna gli animali oltre max_days_without_food (li uccide chi chiama).
static func feed_day(game_data: GameData, building: Building, animals: Array) -> Array[DomesticAnimal]:
	var starved: Array[DomesticAnimal] = []
	if building == null:
		return starved
	sync_species(game_data, building)
	var eaters: Array[DomesticAnimal] = []
	for animal: DomesticAnimal in animals:
		if eats_now(game_data, animal):
			eaters.append(animal)
		else:
			animal.days_without_food = 0
	eaters.sort_custom(func(a: DomesticAnimal, b: DomesticAnimal) -> bool:
		return a.days_without_food > b.days_without_food if a.days_without_food != b.days_without_food else a.id < b.id)
	var before := building.feeder_calories
	for animal in eaters:
		var ration := daily_ration(game_data, animal)
		if ration > 0.0 and building.feeder_calories + 0.0001 < ration:
			animal.days_without_food += 1
			var rules := DomesticAnimalCalculator.get_rules(animal.species)
			if rules != null and rules.max_days_without_food > 0 and animal.days_without_food > rules.max_days_without_food:
				starved.append(animal)
			continue
		building.feeder_calories = maxf(building.feeder_calories - ration, 0.0)
		animal.days_without_food = 0
	if before > 0.0:
		building.feeder_space_used *= building.feeder_calories / before
	if building.feeder_calories <= 0.0001:
		building.feeder_calories = 0.0
		building.feeder_space_used = 0.0
	return starved


# Spazio di un'unità di cibo nella mangiatoia (pubblica per la regola del WM).
static func unit_space(resource_name: String) -> float:
	return _unit_space(resource_name)
