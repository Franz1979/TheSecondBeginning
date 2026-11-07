class_name HomeSoupService
extends RefCounted

# Zuppa di casa (2026-11-07, richiesta utente — Vasellame, ciotola). Non è un prodotto: è un modo di mangiare della
# famiglia. Ogni casa riscaldabile (oggi la Capanna, HouseHeatingService.is_heatable) ha al massimo una pentola. Quando è
# cotta vale sempre POT_CALORIES e si divide in parti uguali tra gli abitanti di quel momento (Building.soup_shares: id
# dell'abitante -> calorie della sua parte). Ogni abitante prende tutta la sua parte in un solo viaggio, con le regole del
# rifornimento di cibo (prima la riserva del corpo, poi la saccoccia). Freschezza (Building.soup_freshness, 1 alla
# cottura): cala ogni giorno di 1/FRESH_DAYS_FIRE se la casa quel giorno è scaldata (il fuoco tiene la pentola calda),
# altrimenti di 1/FRESH_DAYS; a zero le parti non prese vanno a male (expire_daily). 2026-11-07, richiesta utente.
#
# Passo 2 (cottura): voce di SVAGO "Cucina la zuppa" (cook_soup.tres, IdleTaskAssignmentService), estratta a sorte come
# le altre. Possibile (plan_cooking) per chi abita in una Capanna senza una zuppa buona, con il fuoco (has_fire) e, sommando
# tutti i magazzini, SOUP_BONES ossa (zuppa di midollo: solo ossa, 2026-11-07, richiesta utente — prima anche cibo di
# stagione, tolto perché il villaggio lo mangiava prima) e, se in casa non c'è, la ciotola, raccoglibili in al massimo MAX_STOPS magazzini (2026-11-07, richiesta utente). Giro: tappe ai magazzini
# (TakeSoupIngredientsAction: prende quello che manca, CONTEXT_MISSING; se manca ancora qualcosa la tappa successiva si
# aggiunge al compito, insert_next_stop) -> casa (CookSoupAction: ciotola nel deposito di casa, dove resta, un uso in meno
# a ogni cottura; legna COOK_FUEL se la casa oggi non è scaldata; skill "produce").
# La ciotola nel deposito della Capanna è accettata e riservata come il vestiario (HouseWardrobeService.SOUP_BOWL).
# Passo 3 (mangiare, 2026-11-07): nel rifornimento di cibo (NeedTaskAssignmentService.build_restock_task) chi ha la sua
# parte in una pentola buona di casa va a casa invece che al magazzino, se la casa non è più lontana e tutta la parte ci sta
# (fits_whole_share); RestockPouchAction con SourceKind.SOUP la prende (take_share). Chi cucina prende la sua subito. La
# zuppa non è una risorsa: nella saccoccia sono calorie e spazio (SPACE_PER_CALORIE), con felicità e salute proprie
# (EAT_*_PER_100_CALORIES, come SecondaryResourceRules.eat_*). Senza stato.

const POT_CALORIES: float = 150.0
const FRESH_DAYS: int = 3
const FRESH_DAYS_FIRE: int = 10
const FRESHNESS_EPSILON: float = 0.001
const BONE := "bone"
# Ossa bollite per midollo e grasso: 5 fanno tutta la pentola (POT_CALORIES).
const SOUP_BONES: int = 5
const BOWL := HouseWardrobeService.SOUP_BOWL
# Spazio nella saccoccia: come la carne cotta (5 ogni 100 calorie).
const SPACE_PER_CALORIE: float = 0.05
# Felicità e salute ogni 100 calorie prese (2026-11-07, richiesta utente: più della carne affumicata, 15/10 — pasto caldo
# di casa, midollo e grasso).
const EAT_HAPPINESS_PER_100_CALORIES: float = 20.0
const EAT_HEALTH_PER_100_CALORIES: float = 15.0
const SHARE_EPSILON: float = 0.01
# Cottura: durata in giorni di gioco per chi parte da zero (la skill "produce" la accorcia, CookSoupAction) e legna
# consumata se la casa oggi non è scaldata (stessa regola del riscaldamento: prima l'anticipo, poi un pezzo intero,
# HouseHeatingService.spend_fuel).
const COOK_DAYS: float = 0.5
const COOK_FUEL: float = 0.5
const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/cook_soup.tres"
const CONTEXT_SOURCE_POSITION := "soup_source_position"
const CONTEXT_SOURCE_BUILDING := "soup_source_building"
const CONTEXT_INGREDIENTS := "soup_ingredients"
# Quello che manca ancora da prendere (nome -> pezzi, ciotola compresa), le tappe fatte e la richiesta della tappa
# successiva (letta da HumanIndividualActionService dopo la presa).
const CONTEXT_MISSING := "soup_missing"
const CONTEXT_STOPS := "soup_stops"
const CONTEXT_PENDING_NEXT_STOP := "soup_pending_next_stop"
const MAX_STOPS: int = 3
const CONTEXT_HOUSE_POSITION := "soup_house_position"
const CONTEXT_HOUSE_BUILDING := "soup_house_building"


# true se in `building` si può cuocere la zuppa: casa riscaldabile.
static func is_soup_house(building: Building) -> bool:
	return building != null and building.rules != null and HouseHeatingService.is_heatable(building.rules)


# true se `building` ha una pentola buona adesso con almeno una parte da prendere.
static func has_soup(building: Building) -> bool:
	return is_soup_house(building) and building.soup_freshness > FRESHNESS_EPSILON and not building.soup_shares.is_empty()


# Freschezza persa in un giorno: col fuoco acceso (casa scaldata oggi) 1/FRESH_DAYS_FIRE, altrimenti 1/FRESH_DAYS.
static func _daily_loss(building: Building) -> float:
	return 1.0 / float(FRESH_DAYS_FIRE if building.heated_today else FRESH_DAYS)


# Giorni in cui la pentola è ancora buona al ritmo di oggi (fuoco acceso o spento), contando oggi (0 = nessuna zuppa).
static func days_left(building: Building) -> int:
	if not has_soup(building):
		return 0
	return maxi(ceili(building.soup_freshness / _daily_loss(building) - FRESHNESS_EPSILON), 1)


# Pentola appena cotta in `building`: POT_CALORIES divise tra gli abitanti `resident_ids`, freschezza piena.
static func fill_pot(building: Building, resident_ids: Array[int]) -> void:
	clear_pot(building)
	if resident_ids.is_empty():
		return
	var share := POT_CALORIES / float(resident_ids.size())
	for resident_id in resident_ids:
		building.soup_shares[resident_id] = share
	building.soup_freshness = 1.0
	building.soup_portions_total = resident_ids.size()


# Una volta al giorno (GameTimeService, dopo il riscaldamento del giorno): la freschezza cala (_daily_loss); pentole andate
# a male o finite vuotate. Ritorna le case cambiate (per ridisegnarle).
static func expire_daily(world: World) -> Array[Building]:
	var changed: Array[Building] = []
	if world == null:
		return changed
	for building in world.buildings:
		if building.soup_freshness <= 0.0:
			continue
		building.soup_freshness -= _daily_loss(building)
		if building.soup_freshness <= FRESHNESS_EPSILON or building.soup_shares.is_empty() or building.is_demolished:
			clear_pot(building)
			changed.append(building)
	return changed


static func clear_pot(building: Building) -> void:
	building.soup_shares.clear()
	building.soup_freshness = 0.0
	building.soup_portions_total = 0


# --- Passo 3: mangiare ---

# Calorie della parte di `individual` ancora nella pentola di `house` (0 = nessuna).
static func share_of(individual: HumanIndividual, house: Building) -> float:
	if house == null or individual == null or not has_soup(house):
		return 0.0
	return float(house.soup_shares.get(individual.id, 0.0))


# Quanto della sua parte `individual` può prendere adesso: {"share", "body" (calorie alla riserva del corpo, fino al
# pieno), "pouch" (calorie nella saccoccia: spazio libero e tetto di autonomia del rifornimento)}; {} se niente parte.
static func plan_share(individual: HumanIndividual, house: Building) -> Dictionary:
	var share := share_of(individual, house)
	if share <= 0.0:
		return {}
	var body := minf(share, maxf(individual.body_calories_capacity - individual.body_calories, 0.0))
	var pouch_room := maxf(individual.food_space_capacity - individual.food_space_used, 0.0) / SPACE_PER_CALORIE
	var cap := HumanIndividualActionService.get_restock_pouch_calorie_cap(individual)
	if not is_inf(cap):
		pouch_room = minf(pouch_room, maxf(cap - individual.food_calories_held, 0.0))
	return {"share": share, "body": body, "pouch": minf(share - body, pouch_room)}


# true se tutta la parte di `individual` ci sta adesso (riserva del corpo + saccoccia).
static func fits_whole_share(individual: HumanIndividual, house: Building) -> bool:
	var plan := plan_share(individual, house)
	return not plan.is_empty() and float(plan["body"]) + float(plan["pouch"]) >= float(plan["share"]) - SHARE_EPSILON


# Casa da cui `individual` può rifornirsi con la zuppa (la sua, con una pentola buona e tutta la sua parte che ci sta);
# null altrimenti. La scelta tra casa e magazzino la fa NeedTaskAssignmentService.build_restock_task.
static func restock_house(individual: HumanIndividual, world: World) -> Building:
	var house := home_of(world, individual)
	return house if house != null and fits_whole_share(individual, house) else null


# Prende la parte di `individual` da `house`, fin dove ci sta (prima la riserva del corpo, poi la saccoccia): quello che non
# ci sta resta nella pentola. Felicità e salute su quanto preso. Ritorna le calorie prese.
static func take_share(individual: HumanIndividual, house: Building) -> float:
	var plan := plan_share(individual, house)
	if plan.is_empty():
		return 0.0
	var body := float(plan["body"])
	var pouch := float(plan["pouch"])
	var taken := body + pouch
	if taken <= SHARE_EPSILON:
		return 0.0
	var happiness_before := individual.current_happiness
	var health_before := individual.current_health
	individual.body_calories += body
	individual.food_calories_held += pouch
	individual.food_space_used += pouch * SPACE_PER_CALORIE
	HumanFoodPouchService.clamp_to_capacity(individual)
	individual.current_happiness = clampf(individual.current_happiness + taken * EAT_HAPPINESS_PER_100_CALORIES / 100.0, 0.0, maxf(individual.max_happiness, 0.0))
	individual.current_health = clampf(individual.current_health + taken * EAT_HEALTH_PER_100_CALORIES / 100.0, 0.0, maxf(individual.max_health, 0.0))
	var left := float(plan["share"]) - taken
	if left <= SHARE_EPSILON:
		house.soup_shares.erase(individual.id)
	else:
		house.soup_shares[individual.id] = left
	_log(individual, "prende la sua parte nella casa #%d: %.0f calorie (riserva %.0f, saccoccia %.0f)%s; felicità %+.1f, salute %+.1f; parti rimaste %d." % [
		house.id, taken, body, pouch, (", %.0f restano nella pentola" % left) if left > SHARE_EPSILON else "",
		individual.current_happiness - happiness_before, individual.current_health - health_before, house.soup_shares.size()
	])
	return taken


# --- Passo 2: la cottura ---

# Capanna di `individual` dove si può cucinare (completa, in servizio), altrimenti null.
static func home_of(world: World, individual: HumanIndividual) -> Building:
	if world == null or individual == null or individual.house_id == -1:
		return null
	for building in world.buildings:
		if building.id != individual.house_id:
			continue
		if is_soup_house(building) and building.is_complete and not building.is_demolished and not building.is_out_of_service():
			return building
		return null
	return null


static func has_bowl(house: Building) -> bool:
	return int((house.stored_resources.get(BOWL, {}) as Dictionary).get("quantity", 0)) > 0


# true se c'è il fuoco per cucinare: in autunno e inverno la casa scaldata oggi; altrimenti anticipo + legna nel deposito
# di casa per COOK_FUEL (HouseHeatingService.can_cover_fuel).
static func has_fire(house: Building) -> bool:
	return _uses_heating_fire(house) or HouseHeatingService.can_cover_fuel(house, COOK_FUEL)


static func _uses_heating_fire(house: Building) -> bool:
	return HouseHeatingService.is_cold_season(HumanVitalsInteractionService.current_season()) and house.heated_today


# Abitanti di `house` adesso (id) che hanno una parte di zuppa. I neonati no (2026-11-07, richiesta utente): non mangiano
# e non fanno il rifornimento, la loro parte andava a male; la pentola si divide tra gli altri.
static func resident_ids(house: Building) -> Array[int]:
	var ids: Array[int] = []
	var game_data: GameData = GameSettings.active_game_data
	for member in GameSettings.active_human_individuals:
		if member.house_id == house.id and GameContext.age_band_for(member, game_data) != HumanTypes.AgeBand.INFANT:
			ids.append(member.id)
	return ids


# Cottura possibile per `individual` adesso: {"house", "source" (prima tappa), "ingredients" (nome -> pezzi: le ossa),
# "take_bowl"}; {} se manca qualcosa. Il percorso (_route) deve raccogliere tutto in al massimo MAX_STOPS magazzini. `verbose` (tasto M di debug): scrive nel log il motivo del no.
static func plan_cooking(individual: HumanIndividual, world: World, verbose: bool = false) -> Dictionary:
	var house := home_of(world, individual)
	if house == null:
		return _no(verbose, individual, "non abita in una Capanna completa e in servizio")
	if has_soup(house):
		return _no(verbose, individual, "nella casa #%d c'è già una zuppa buona (%d giorni)" % [house.id, days_left(house)])
	if not has_fire(house):
		return _no(verbose, individual, "niente fuoco nella casa #%d: non scaldata oggi e legna %.1f + anticipo %.1f < %.1f" % [
			house.id, ProductionService.get_available_fuel(house), house.heating_fuel_credit, COOK_FUEL
		])
	var take_bowl := not has_bowl(house)
	var free_kinds := HumanIndividual.MAX_CARRIED_VARIETIES - individual.carried_resources.size() - 1 - (1 if take_bowl else 0)
	if free_kinds < 0:
		return _no(verbose, individual, "zaino con troppi tipi di oggetti (%s)" % str(individual.carried_resources.keys()))
	var wanted: Array[String] = [BONE]
	if take_bowl:
		wanted.append(BOWL)
	var totals: Dictionary = {}
	for building in world.buildings:
		if not _is_source(building):
			continue
		var stock := _stock_at(building, wanted)
		for resource_name in stock.keys():
			totals[resource_name] = int(totals.get(resource_name, 0)) + int(stock[resource_name])
	if int(totals.get(BONE, 0)) < SOUP_BONES:
		return _no(verbose, individual, "ossa nei magazzini %d < %d" % [int(totals.get(BONE, 0)), SOUP_BONES])
	if take_bowl and int(totals.get(BOWL, 0)) < 1:
		return _no(verbose, individual, "in casa non c'è la ciotola e nei magazzini nemmeno")
	var ingredients := {BONE: SOUP_BONES}
	if _carry_space(ingredients, take_bowl) > individual.max_carry_capacity - individual.get_carried_space() + FoodSelectionService.UNIT_FIT_EPSILON:
		return _no(verbose, individual, "non ci sta nello zaino: %.1f su %.1f liberi" % [
			_carry_space(ingredients, take_bowl), individual.max_carry_capacity - individual.get_carried_space()
		])
	var needs := ingredients.duplicate()
	if take_bowl:
		needs[BOWL] = 1
	var route := _route(individual, world, needs)
	if route.is_empty():
		return _no(verbose, individual, "servirebbero più di %d magazzini (o uno non è raggiungibile) per %s" % [MAX_STOPS, str(needs)])
	if verbose or (DebugLogging.ENABLED and DebugLogging.SHOW_SOUP_LOGS):
		var stops: Array[String] = []
		for stop in route:
			stops.append("%s #%d" % [stop.building_type_name, stop.id])
		_log(individual, "può cucinare nella casa #%d: %s%s, giro previsto %s." % [
			house.id, str(ingredients), " + ciotola" if take_bowl else "", " -> ".join(stops)
		])
	return {"house": house, "source": route[0], "ingredients": ingredients, "take_bowl": take_bowl}


const TASK_NAME := "task_cook_soup_name"


static func is_cook_task(task: Task) -> bool:
	return task != null and task.task_name == TASK_NAME


# Log di debug (2026-11-07, richiesta utente): una cottura che finisce senza zuppa — sostituita da un altro compito o
# fermata — con cosa ha nello zaino, la tappa a cui era e chi l'ha chiusa (le chiamate che hanno portato qui).
static func log_interrupted(individual: HumanIndividual, task: Task, how: String) -> void:
	if not (DebugLogging.ENABLED and DebugLogging.SHOW_SOUP_LOGS) or not is_cook_task(task) or task.is_finished():
		return
	var callers: Array[String] = []
	var stack := get_stack()
	for i in range(1, mini(stack.size(), 8)):
		callers.append("%s:%d %s" % [String(stack[i]["source"]).get_file(), int(stack[i]["line"]), String(stack[i]["function"])])
	# Sospendibile (2026-11-07, cook_soup.tres is_suspendable): un bisogno la mette in coda col suo carico e riparte dopo.
	_log(individual, "cottura %s allo step %d/%d (tappe %d): %s; zaino %s. Chiamate: %s" % [
		"sospesa in coda (riparte dopo)" if task.is_suspendable and how != "fermata" else "interrotta",
		task.current_step_index + 1, task.steps.size(), int(task.context.get(CONTEXT_STOPS, 1)), how,
		str(individual.carried_resources.keys()), " <- ".join(callers)
	])


static func _no(verbose: bool, individual: HumanIndividual, reason: String) -> Dictionary:
	if verbose:
		_log(individual, "non può cucinare: " + reason + ".")
	return {}


static func _log(individual: HumanIndividual, message: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_SOUP_LOGS:
		print("[SOUP] #%d %s: %s" % [individual.id, individual.name, message])


# Magazzino da cui si può prendere (completo, in servizio, non macerie).
static func _is_source(building: Building) -> bool:
	return building.is_complete and not building.is_demolished and not building.is_out_of_service() \
		and not WasteDisposalService.is_debris_source(building)


# Pezzi prelevabili in automatico in `building` per ognuno dei nomi `names` (senza le riserve delle case).
static func _stock_at(building: Building, names: Array) -> Dictionary:
	var stock: Dictionary = {}
	for resource_name in names:
		var found := WarehouseSelectionService.get_matching_stock(building, String(resource_name), 1)
		if found.has(String(resource_name)):
			stock[String(resource_name)] = int(found[String(resource_name)])
	return stock


# Magazzino più vicino a `origin` (riferimento di `individual`) che ha almeno una delle cose in `needs`; null se nessuno.
static func _nearest_with(individual: HumanIndividual, world: World, origin: Vector2, needs: Dictionary, excluded: Array) -> Building:
	var names := needs.keys()
	var has_some := func(building: Building) -> bool:
		return _is_source(building) and not _stock_at(building, names).is_empty()
	return SpatialSelectionService.find_nearest(
		world.buildings, origin, individual.home_macro_coords, has_some, excluded, PathfindingService.reachability_for(individual)
	) as Building


# Percorso di raccolta: dal punto dell'individuo il magazzino più vicino con qualcosa che manca, poi il più vicino da lì,
# finché manca qualcosa (al massimo MAX_STOPS). [] se non basta.
static func _route(individual: HumanIndividual, world: World, needs: Dictionary) -> Array[Building]:
	var remaining := needs.duplicate()
	var stops: Array[Building] = []
	var excluded: Array = []
	var origin := individual.position
	while not remaining.is_empty() and stops.size() < MAX_STOPS:
		var building := _nearest_with(individual, world, origin, remaining, excluded)
		if building == null:
			return []
		var stock := _stock_at(building, remaining.keys())
		for resource_name in stock.keys():
			var left := int(remaining[resource_name]) - int(stock[resource_name])
			if left <= 0:
				remaining.erase(resource_name)
			else:
				remaining[resource_name] = left
		stops.append(building)
		excluded.append(building.id)
		origin = TaskBuilderService.building_arrival_point(individual, building)
	if not remaining.is_empty():
		return []
	return stops


static func _carry_space(ingredients: Dictionary, take_bowl: bool) -> float:
	var total := 0.0
	for resource_name in ingredients.keys():
		var rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if rules != null:
			total += rules.space_per_unit * float(ingredients[resource_name])
	if take_bowl:
		var bowl_rules := CaloricCalculator.get_caloric_source_rules(BOWL)
		if bowl_rules != null:
			total += bowl_rules.space_per_unit
	return total


# Compito "Cucina la zuppa" dal piano di plan_cooking (prima tappa; le altre si aggiungono strada facendo); null se non si
# può costruire.
static func build_cook_task(individual: HumanIndividual, plan: Dictionary) -> Task:
	if plan.is_empty():
		return null
	var source: Building = plan["source"]
	var house: Building = plan["house"]
	var missing: Dictionary = (plan["ingredients"] as Dictionary).duplicate()
	if bool(plan["take_bowl"]):
		missing[BOWL] = 1
	var context := {
		CONTEXT_SOURCE_POSITION: TaskBuilderService.building_arrival_point(individual, source),
		CONTEXT_SOURCE_BUILDING: source,
		CONTEXT_INGREDIENTS: plan["ingredients"],
		CONTEXT_MISSING: missing,
		CONTEXT_STOPS: 1,
		CONTEXT_HOUSE_POSITION: TaskBuilderService.building_arrival_point(individual, house),
		CONTEXT_HOUSE_BUILDING: house,
	}
	var task := TaskFactory.build_task(TaskDefinitionCache.get_definition(TASK_DEFINITION_PATH), context)
	# Non richiamabile al lavoro (2026-11-07, richiesta utente): estratta dallo svago (cook_soup.tres resta uno svago per il
	# sorteggio) o partita col tasto M, la cottura smette subito di essere uno svago (Task.is_idle_activity, salvato con la
	# Task), così il coordinatore non la chiama (CoordinatorService._call_idle_individuals). Bisogni ed emergenze la
	# interrompono come ogni altro compito.
	if task != null:
		task.is_idle_activity = false
	return task


# TakeSoupIngredientsAction: dal magazzino `source` quello che manca ancora (CONTEXT_MISSING), fin dove c'è e ci sta nello
# zaino. Se manca ancora qualcosa chiede la tappa successiva (CONTEXT_PENDING_NEXT_STOP) o, finite le tappe, chiude il
# compito: quello già preso torna in magazzino come carico senza proprietario.
static func take_at_stop(individual: HumanIndividual, source: Building, context: Dictionary) -> void:
	var missing: Dictionary = context.get(CONTEXT_MISSING, {})
	if source != null and _is_source(source):
		var stock := _stock_at(source, missing.keys())
		for key in stock.keys():
			var resource_name := String(key)
			var wanted := mini(int(missing[resource_name]), int(stock[resource_name]))
			var taken := _take_one(individual, source, resource_name, wanted)
			var left := int(missing[resource_name]) - taken
			if left <= 0:
				missing.erase(resource_name)
			else:
				missing[resource_name] = left
	context[CONTEXT_MISSING] = missing
	_log(individual, "tappa %d a %s: zaino %s, manca ancora %s." % [
		int(context.get(CONTEXT_STOPS, 1)), ("%s #%d" % [source.building_type_name, source.id]) if source != null else "magazzino sparito",
		str(individual.carried_resources.keys()), str(missing) if not missing.is_empty() else "niente"
	])
	if missing.is_empty():
		return
	if int(context.get(CONTEXT_STOPS, 1)) >= MAX_STOPS:
		_log(individual, "tappe finite (%d): rinuncia, quello che ha torna al magazzino." % MAX_STOPS)
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "soup_no_ingredients"
		return
	context[CONTEXT_PENDING_NEXT_STOP] = true


# Preleva fino a `wanted` pezzi di `resource_name` da `source` nello zaino, uno spazio alla volta; ritorna quanti.
static func _take_one(individual: HumanIndividual, source: Building, resource_name: String, wanted: int) -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var space := rules.space_per_unit if rules != null else 0.0
	var free := individual.max_carry_capacity - individual.get_carried_space() + FoodSelectionService.UNIT_FIT_EPSILON
	var fitting := wanted if space <= 0.0 else mini(wanted, int(floor(free / space)))
	if fitting <= 0 or not individual.can_carry_variety(resource_name):
		return 0
	if resource_name == BOWL:
		var units: Array = BuildingStorageService.withdraw_tool_units_auto(source, BOWL, 1)
		if units.is_empty():
			return 0
		if not individual.add_carried_tool_instance(BOWL, units[0]):
			BuildingStorageService.store_tool_instance(source, BOWL, units[0])
			return 0
		return 1
	var decay := float((source.stored_resources.get(resource_name, {}) as Dictionary).get("decay_fraction", 0.0))
	var withdrawn := BuildingStorageService.withdraw_auto(source, resource_name, fitting)
	if withdrawn <= 0:
		return 0
	var carried := individual.add_carried_resource(resource_name, withdrawn, decay)
	if carried < withdrawn:
		BuildingStorageService.store(source, resource_name, withdrawn - carried, decay)
	return carried


# Tappa successiva (HumanIndividualActionService, dopo una presa con CONTEXT_PENDING_NEXT_STOP): il magazzino più vicino
# con qualcosa che manca ancora, aggiunto subito dopo lo step corrente (cammino + presa). Nessuno: compito chiuso.
static func insert_next_stop(individual: HumanIndividual, task: Task, world: World) -> void:
	var missing: Dictionary = task.context.get(CONTEXT_MISSING, {})
	var current := task.get_current_action() as TakeSoupIngredientsAction
	var excluded: Array = [current.source_building.id] if current != null and current.source_building != null else []
	var building := _nearest_with(individual, world, individual.position, missing, excluded)
	if building == null:
		_log(individual, "nessun magazzino ha ancora %s: rinuncia, quello che ha torna al magazzino." % str(missing))
		task.context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "soup_no_ingredients"
		return
	task.context[CONTEXT_STOPS] = int(task.context.get(CONTEXT_STOPS, 1)) + 1
	_log(individual, "tappa successiva: %s #%d." % [building.building_type_name, building.id])
	var new_steps: Array[Action] = [
		WalkAction.new(TaskBuilderService.building_arrival_point(individual, building)), TakeSoupIngredientsAction.new(building),
	]
	var descriptions: Array[String] = ["task_cook_soup_step_walk_source", "task_cook_soup_step_take"]
	task.insert_steps_after_current(new_steps, descriptions)


# CookSoupAction a fine cottura: la ciotola portata va nel deposito di casa (se in casa non ce n'è già una), poi ossa e cibo
# dallo zaino, un uso della ciotola, la legna se serve, e la pentola piena per gli abitanti di adesso. "" se riuscito,
# altrimenti il motivo (la Task si chiude; quello che resta nello zaino torna in magazzino come carico senza proprietario).
static func cook(individual: HumanIndividual, house: Building, ingredients: Dictionary) -> String:
	var failure := _cook(individual, house, ingredients)
	if failure != "":
		_log(individual, "cottura fallita: %s (zaino %s)." % [failure, str(individual.carried_resources.keys())])
	return failure


static func _cook(individual: HumanIndividual, house: Building, ingredients: Dictionary) -> String:
	if house == null or house.is_demolished or house.is_out_of_service() or not is_soup_house(house):
		return "no_house"
	if has_soup(house):
		return "already_cooked"
	if not has_bowl(house) and individual.get_carried_quantity(BOWL) > 0:
		var units: Array = individual.take_carried_tool_units(BOWL, 1)
		if not units.is_empty() and not BuildingStorageService.store_tool_instance(house, BOWL, units[0]):
			individual.add_carried_tool_instance(BOWL, units[0])
	if not has_bowl(house):
		return "no_bowl"
	for resource_name in ingredients.keys():
		if individual.get_carried_quantity(String(resource_name)) < int(ingredients[resource_name]):
			return "no_ingredients"
	if not has_fire(house):
		return "no_fire"
	for resource_name in ingredients.keys():
		individual.remove_carried_resource(String(resource_name), int(ingredients[resource_name]))
	# Un uso della ciotola: a zero si rompe e sparisce.
	var bowl := BuildingStorageService.take_stored_tool_unit(house, BOWL)
	var bowl_left := -1
	if not bowl.is_empty():
		var uses_left := ToolInstance.get_remaining_uses(bowl) - 1
		bowl_left = maxi(uses_left, 0)
		if uses_left > 0:
			bowl[ToolInstance.KEY_REMAINING_USES] = uses_left
			BuildingStorageService.store_tool_instance(house, BOWL, bowl)
	if not _uses_heating_fire(house):
		HouseHeatingService.spend_fuel(house, COOK_FUEL)
	fill_pot(house, resident_ids(house))
	_log(individual, "zuppa cotta nella casa #%d con %s: %d parti da %.0f calorie, ciotola %s, legna %s." % [
		house.id, str(ingredients), house.soup_portions_total, POT_CALORIES / float(maxi(house.soup_portions_total, 1)),
		("%d usi rimasti" % bowl_left) if bowl_left > 0 else ("rotta" if bowl_left == 0 else "?"),
		"dal riscaldamento" if _uses_heating_fire(house) else "%.1f (anticipo rimasto %.1f)" % [COOK_FUEL, house.heating_fuel_credit],
	])
	# Chi cucina prende subito la sua parte (2026-11-07, richiesta utente): è lì davanti.
	take_share(individual, house)
	return ""
