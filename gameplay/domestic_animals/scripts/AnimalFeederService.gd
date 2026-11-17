class_name AnimalFeederService
extends RefCounted

# Mangiatoia degli edifici con animali (2026-11-13, punto 4, passo 2 — decisione utente "A"): come la saccoccia del cibo
# delle persone, SPAZIO e CALORIE, non un magazzino. Capienza in spazio (BuildingRules.feeder_space_capacity); alla
# consegna ogni unità di cibo occupa il suo spazio (SecondaryResourceRules.space_per_unit, Building.feeder_space_used) e
# diventa calorie per gli animali (animal_calories_per_unit se > 0, altrimenti calories_per_unit, Building.
# feeder_calories); la risorsa sparisce. Accetta solo i cibi della specie tenuta (DomesticAnimalRules.accepted_foods di
# KeptAnimalService.current_species): con "Qualunque" e nessun animale non accetta niente. Il contenuto è "di" una specie
# (Building.feeder_species): se la specie tenuta cambia, la mangiatoia si svuota e il cibo è perso, così il cambio di
# specie non serve a convertire il cibo. Consegna col Trasporto manuale (sotto); consumo nel passo dopo. Stateless,
# statico.
# CIBI COL NOME (2026-11-16, richiesta utente): ogni cibo resta separato (Building.feeder_foods, nome -> unità e
# deperimento 0..1); calorie e spazio sono i loro totali (_recompute). Deperimento come nei magazzini: ogni giorno +1 /
# day_durability del cibo (-1 o 0 = non deperisce), a 1 è marcito e sparisce (advance_decay_day). Gli animali mangiano
# prima il cibo più vicino a guastarsi, a parità nell'ordine della dieta.


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
	building.feeder_foods.clear()
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
# `decay`: deperimento del cibo portato (quello dello zaino), mescolato a quello già dentro.
static func deposit(game_data: GameData, building: Building, resource_name: String, quantity: int, decay: float = 0.0) -> int:
	sync_species(game_data, building)
	var units := mini(quantity, max_depositable(game_data, building, resource_name))
	if units <= 0:
		return 0
	building.feeder_species = KeptAnimalService.current_species(game_data, building)
	_ensure_foods(building)
	_add_food(building, resource_name, float(units), clampf(decay, 0.0, 1.0))
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
	_ensure_foods(building)
	var missing := daily_ration(game_data, animal) * STARTER_FOOD_DAYS - building.feeder_calories
	if missing <= 0.0:
		return
	var starter_food := _first_food_with_calories(accepted_foods(game_data, building))
	if starter_food == "":
		return
	var space_per_calorie := _unit_space(starter_food) / food_calories(starter_food)
	missing = minf(missing, maxf(float(capacity(building)) - building.feeder_space_used, 0.0) / space_per_calorie)
	if missing <= 0.0:
		return
	building.feeder_species = KeptAnimalService.current_species(game_data, building)
	_add_food(building, starter_food, missing / food_calories(starter_food), 0.0)
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
# Calorie al giorno su cui il WM calcola l'obiettivo della mangiatoia (2026-11-16, richiesta utente — prima gli animali
# presenti: a tettoia vuota l'obiettivo era zero e il primo animale arrivava a mangiatoia vuota). Con la specie scelta:
# tutti i posti della tettoia × la razione da adulto della specie, chiunque ci sia. Con "Qualunque": nulla a tettoia
# vuota (non si sa chi mangerà), gli animali presenti se ce ne sono (altrimenti morirebbero di fame).
static func target_daily_calories(game_data: GameData, building: Building) -> float:
	if building == null:
		return 0.0
	var species := KeptAnimalService.chosen_species(building)
	if species == KeptAnimalService.NO_SPECIES:
		return 0.0
	if species == "":
		return daily_calories_needed(game_data, building)
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null:
		return 0.0
	return float(KeptAnimalService.capacity(building)) * rules.daily_calories


# Calorie che la mangiatoia può tenere al massimo col cibo preferito della dieta che ha calorie (stima per il pannello:
# con cibi diversi lo spazio per caloria cambia). 0 = specie non decisa o nessun cibo con calorie.
static func max_calories(game_data: GameData, building: Building) -> float:
	for food in accepted_foods(game_data, building):
		if food_calories(food) > 0.0:
			return float(capacity(building)) / _unit_space(food) * food_calories(food)
	return 0.0


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
	_ensure_foods(building)
	var order := _eating_order(game_data, building)
	for animal in eaters:
		var ration := daily_ration(game_data, animal)
		if ration > 0.0 and building.feeder_calories + 0.0001 < ration:
			animal.days_without_food += 1
			var rules := DomesticAnimalCalculator.get_rules(animal.species)
			if rules != null and rules.max_days_without_food > 0 and animal.days_without_food > rules.max_days_without_food:
				starved.append(animal)
			continue
		_eat(building, order, ration)
		animal.days_without_food = 0
	return starved


# --- Cibi col nome (2026-11-16) ---

# Aggiunge `units` di `food` con deperimento `decay`, mescolato a quello già dentro in proporzione alle unità (come la
# media dei magazzini).
static func _add_food(building: Building, food: String, units: float, decay: float) -> void:
	if units <= 0.0:
		return
	var entry: Dictionary = building.feeder_foods.get(food, {"units": 0.0, "decay": 0.0})
	var old_units := float(entry["units"])
	entry["decay"] = (float(entry["decay"]) * old_units + decay * units) / (old_units + units)
	entry["units"] = old_units + units
	building.feeder_foods[food] = entry
	_recompute(building)


# Totali di calorie e spazio dai cibi dentro.
static func _recompute(building: Building) -> void:
	var calories_total := 0.0
	var space_total := 0.0
	for food in building.feeder_foods.keys():
		var units := float((building.feeder_foods[food] as Dictionary)["units"])
		calories_total += units * food_calories(String(food))
		space_total += units * _unit_space(String(food))
	building.feeder_calories = calories_total
	building.feeder_space_used = minf(space_total, float(capacity(building)))


# Vecchi salvataggi (prima del 2026-11-16): calorie senza nome -> il primo cibo della dieta della specie del contenuto.
static func _ensure_foods(building: Building) -> void:
	if not building.feeder_foods.is_empty() or building.feeder_calories <= 0.0001:
		return
	var rules := DomesticAnimalCalculator.get_rules(building.feeder_species) if building.feeder_species != "" else null
	var food := _first_food_with_calories(rules.accepted_foods if rules != null else ([] as Array[String]))
	if food == "":
		return
	building.feeder_foods[food] = {"units": building.feeder_calories / food_calories(food), "decay": 0.0}
	_recompute(building)


static func _first_food_with_calories(foods: Array[String]) -> String:
	for food in foods:
		if food_calories(food) > 0.0:
			return food
	return ""


# Cibi nell'ordine in cui si mangiano: prima il più vicino a guastarsi, a parità nell'ordine della dieta.
static func _eating_order(game_data: GameData, building: Building) -> Array[String]:
	var diet := accepted_foods(game_data, building)
	var foods: Array[String] = []
	for food in building.feeder_foods.keys():
		foods.append(String(food))
	foods.sort_custom(func(a: String, b: String) -> bool:
		var decay_a := float((building.feeder_foods[a] as Dictionary)["decay"])
		var decay_b := float((building.feeder_foods[b] as Dictionary)["decay"])
		if not is_equal_approx(decay_a, decay_b):
			return decay_a > decay_b
		var index_a := diet.find(a)
		var index_b := diet.find(b)
		return (index_a if index_a >= 0 else 999) < (index_b if index_b >= 0 else 999))
	return foods


# Toglie `calories` dai cibi nell'ordine `order`; i cibi finiti spariscono.
static func _eat(building: Building, order: Array[String], calories: float) -> void:
	var left := calories
	for food in order:
		if left <= 0.0001:
			break
		if not building.feeder_foods.has(food):
			continue
		var per_unit := food_calories(food)
		if per_unit <= 0.0:
			continue
		var entry: Dictionary = building.feeder_foods[food]
		var eaten_units := minf(float(entry["units"]), left / per_unit)
		entry["units"] = float(entry["units"]) - eaten_units
		left -= eaten_units * per_unit
		if float(entry["units"]) <= 0.0001:
			building.feeder_foods.erase(food)
	_recompute(building)


# Deperimento di un giorno in tutte le mangiatoie (DomesticAnimalLifeService.tick_day, prima del pasto): +1/day_durability
# per cibo; a 1 è marcito e sparisce.
static func advance_decay_day(world: World) -> void:
	if world == null:
		return
	for building in world.buildings:
		if building.feeder_foods.is_empty() and building.feeder_calories <= 0.0001:
			continue
		_ensure_foods(building)
		var changed := false
		for food in building.feeder_foods.keys():
			var rules := CaloricCalculator.get_caloric_source_rules(String(food))
			if rules == null or rules.day_durability <= 0:
				continue
			var entry: Dictionary = building.feeder_foods[food]
			entry["decay"] = float(entry["decay"]) + 1.0 / float(rules.day_durability)
			if float(entry["decay"]) >= 1.0:
				DebugLogging.print_event("[FEEDER] Edificio %d: %.1f %s marcito nella mangiatoia" % [building.id, float(entry["units"]), food])
				building.feeder_foods.erase(food)
				changed = true
		if changed:
			_recompute(building)


# Righe del pannello: un cibo per riga, nell'ordine in cui si mangia. {"food", "units", "calories", "freshness" 0..1}.
static func food_rows(game_data: GameData, building: Building) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if building == null or calories(game_data, building) <= 0.0:
		return rows
	_ensure_foods(building)
	for food in _eating_order(game_data, building):
		var entry: Dictionary = building.feeder_foods[food]
		rows.append({
			"food": food, "units": float(entry["units"]), "calories": float(entry["units"]) * food_calories(food),
			"freshness": clampf(1.0 - float(entry["decay"]), 0.0, 1.0),
		})
	return rows


# Spazio di un'unità di cibo nella mangiatoia (pubblica per la regola del WM).
static func unit_space(resource_name: String) -> float:
	return _unit_space(resource_name)
