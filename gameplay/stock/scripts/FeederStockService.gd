class_name FeederStockService
extends RefCounted

# Regola del gestore scorte "Rifornisci le mangiatoie" (2026-11-14, richiesta utente — punto 4). Un numero per specie dal
# 2026-11-17 (pannello Animali, species_days; prima uno per il villaggio nelle regole del WM), i giorni di cibo da tenere
# nelle mangiatoie (0 = nessun rifornimento); la singola tettoia può
# avere il suo (Building.feeder_days_override: -1 = regola generale, 0 = esclusa, > 0 = giorni suoi). A ogni Inventario,
# per ogni edificio con mangiatoia: obiettivo = calorie al giorno × giorni. Dal 2026-11-16 (richiesta utente) le calorie
# al giorno sono quelle di tutti i posti della tettoia per la specie scelta (AnimalFeederService.target_daily_calories),
# non più degli animali presenti: la mangiatoia è pronta prima che arrivi il primo; con "Qualunque" niente a tettoia vuota. Se la mangiatoia (con quanto già in viaggio e gli ordini aperti)
# sta sotto l'obiettivo, ordini "transport" deposito → mangiatoia, scelti così:
# - cibi nell'ordine della dieta della specie (DomesticAnimalRules.accepted_foods = preferenza);
# - da tutta la scorta del villaggio: il minimo del gestore scorte non si tiene da parte (2026-11-15, richiesta utente —
#   il minimo è la soglia che fa partire le raccolte, non una riserva; stessa scelta della zuppa);
# - se ci si muove, almeno uno zaino pieno (decisione utente "B", spazio medio dei portatori) anche oltre l'obiettivo,
#   fin dove c'è posto nella mangiatoia: niente viaggi a zaino semivuoto con pochi animali;
# - senza nessun cibo disponibile, un avviso in campanella (StockRuntimeState.feeder_warnings).
# Il WM non raccoglie cibo apposta per gli animali. Un ordine aperto per mangiatoia e cibo; gli ordini non serviti più si
# tolgono. Senza stato.

const FEEDER_TARGET_KEY := "feeder_target_id"
const FEEDER_FOOD_KEY := "feeder_food"
const DEFAULT_DAYS := 5


# Edificio che la regola serve: mangiatoia, finito, in piedi, in servizio.
static func is_served(building: Building) -> bool:
	return AnimalFeederService.has_feeder(building) and not building.is_out_of_service()


# Giorni voluti in `building`: i suoi (0 = escluso), altrimenti quelli della specie tenuta (pannello Animali).
static func days_for(building: Building, game_data: GameData) -> int:
	if building.feeder_days_override >= 0:
		return building.feeder_days_override
	return species_days(game_data, KeptAnimalService.current_species(game_data, building))


# Giorni della specie (2026-11-17, richiesta utente — pannello Animali); senza valore il default GameData.stock_feeder_days.
static func species_days(game_data: GameData, species: String) -> int:
	if game_data == null:
		return 0
	return maxi(int(game_data.stock_feeder_days_by_species.get(species, game_data.stock_feeder_days)), 0)


static func set_species_days(game_data: GameData, species: String, days: int) -> void:
	game_data.stock_feeder_days_by_species[species] = maxi(days, 0)


# true se il WM è sbloccato: solo allora il pannello della tettoia mostra i giorni.
static func is_rule_available() -> bool:
	return WaterShelterStockService.is_rule_available()


# Cibo in viaggio verso le mangiatoie: id -> {"calories", "space"} dai trasporti con FEEDER_TARGET_KEY (il residuo più
# alto per individuo e cibo: i viaggi ripetuti portano lo stesso residuo).
static func traveling(individuals: Array) -> Dictionary:
	var result: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var best: Dictionary = {}
		for task in JobWorkScanService.open_tasks(individual):
			if not task.context.has(FEEDER_TARGET_KEY):
				continue
			var key := "%d|%s" % [int(task.context[FEEDER_TARGET_KEY]), String(task.context.get(FEEDER_FOOD_KEY, ""))]
			best[key] = maxi(int(best.get(key, 0)), int(task.context.get("transport_requested_remaining", 0)))
		for key in best.keys():
			var parts := String(key).split("|")
			var target_id := int(parts[0])
			var entry: Dictionary = result.get(target_id, {"calories": 0.0, "space": 0.0})
			entry["calories"] = float(entry["calories"]) + float(best[key]) * AnimalFeederService.food_calories(parts[1])
			entry["space"] = float(entry["space"]) + float(best[key]) * AnimalFeederService.unit_space(parts[1])
			result[target_id] = entry
	return result


# Ordini da togliere (id), da creare ({FEEDER_TARGET_KEY, FEEDER_FOOD_KEY, "quantity", "building"}) e avvisi (id degli
# edifici senza cibo da ricevere). `open_orders`: ordini del cassetto con FEEDER_TARGET_KEY non presi; `in_transit`:
# traveling(); `stock`: scorta del villaggio; `load_space`: uno zaino pieno.
static func plan_orders(world: World, game_data: GameData, open_orders: Array, in_transit: Dictionary, stock: Dictionary,
		load_space: float) -> Dictionary:
	var result := {"remove": [], "create": [], "warnings": []}
	var open_by_target: Dictionary = {}
	for order in open_orders:
		var target_id := int(order.get(FEEDER_TARGET_KEY, -1))
		if not open_by_target.has(target_id):
			open_by_target[target_id] = []
		(open_by_target[target_id] as Array).append(order)
	# Cibo già promesso agli ordini aperti: non è più disponibile per altri.
	var promised: Dictionary = {}
	for order in open_orders:
		var food := String(order.get(FEEDER_FOOD_KEY, ""))
		promised[food] = int(promised.get(food, 0)) + int(order.get("quantity", 0))
	var served: Dictionary = {}
	if world != null and game_data != null:
		for building in world.buildings:
			if not AnimalFeederService.has_feeder(building):
				continue
			if building.is_out_of_service():
				continue
			var days := days_for(building, game_data)
			var need := AnimalFeederService.target_daily_calories(game_data, building)
			if days <= 0 or need <= 0.0 or AnimalFeederService.accepted_foods(game_data, building).is_empty():
				continue
			served[building.id] = true
			var open: Array = open_by_target.get(building.id, [])
			var traveling_entry: Dictionary = in_transit.get(building.id, {"calories": 0.0, "space": 0.0})
			var have := AnimalFeederService.calories(game_data, building) + float(traveling_entry["calories"])
			var space_taken := AnimalFeederService.space_used(game_data, building) + float(traveling_entry["space"])
			for order in open:
				var food := String(order.get(FEEDER_FOOD_KEY, ""))
				have += float(order.get("quantity", 0)) * AnimalFeederService.food_calories(food)
				space_taken += float(order.get("quantity", 0)) * AnimalFeederService.unit_space(food)
			var missing := need * float(days) - have
			if missing <= 0.0:
				# Arrivata all'obiettivo: gli ordini aperti restano finché non sono presi (porteranno lo zaino pieno).
				continue
			if not open.is_empty():
				continue
			var created := _plan_loads(building, game_data, missing, float(AnimalFeederService.capacity(building)) - space_taken,
				load_space, stock, promised)
			if created.is_empty():
				(result["warnings"] as Array).append(building.id)
			else:
				# Una riga per rifornimento deciso: su che basi (2026-11-16, richiesta utente).
				var loads: Array[String] = []
				for order_load in created:
					loads.append("%d %s" % [int(order_load["quantity"]), String(order_load[FEEDER_FOOD_KEY])])
				DebugLogging.print_feeder("[FEEDER] Riempio %s #%d: %d giorni × %.0f cal/giorno (%d posti) = %.0f; dentro %.0f, in viaggio %.0f -> mancano %.0f. Ordini: %s." % [
					building.building_type_name, building.id, days, need, KeptAnimalService.capacity(building), need * float(days),
					AnimalFeederService.calories(game_data, building), float(traveling_entry["calories"]), missing, ", ".join(loads)])
			(result["create"] as Array).append_array(created)
	for target_id in open_by_target.keys():
		if not served.has(int(target_id)):
			for order in open_by_target[target_id]:
				(result["remove"] as Array).append(int(order["id"]))
	return result


# Cibi per una mangiatoia: nell'ordine della dieta, finché coprono `missing` calorie e almeno uno zaino
# pieno (`load_space`), entro lo spazio libero `room`. Aggiorna `promised`.
static func _plan_loads(building: Building, game_data: GameData, missing: float, room: float, load_space: float,
		stock: Dictionary, promised: Dictionary) -> Array:
	var created: Array = []
	var load_left := load_space
	for food in AnimalFeederService.accepted_foods(game_data, building):
		if missing <= 0.0 and load_left <= 0.0:
			break
		var calories := AnimalFeederService.food_calories(food)
		var space := AnimalFeederService.unit_space(food)
		if calories <= 0.0 or room < space:
			continue
		var available := int(stock.get(food, 0)) - int(promised.get(food, 0))
		if available <= 0:
			continue
		var for_need := ceili(maxf(missing, 0.0) / calories - 0.000001)
		var for_load := floori(maxf(load_left, 0.0) / space + 0.000001)
		var units := mini(mini(maxi(for_need, for_load), available), floori(room / space + 0.000001))
		if units <= 0:
			continue
		created.append({FEEDER_TARGET_KEY: building.id, FEEDER_FOOD_KEY: food, "quantity": units, "building": building})
		promised[food] = int(promised.get(food, 0)) + units
		missing -= float(units) * calories
		load_left -= float(units) * space
		room -= float(units) * space
	return created


# Sorgente per portare `food` alla mangiatoia `target`: il magazzino più vicino a `worker` (null = chiunque) che lo ha.
static func pick_source(world: World, target: Building, food: String, worker: HumanIndividual) -> Building:
	if world == null or target == null:
		return null
	var origin := worker.position if worker != null else Vector2.ZERO
	var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
	var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
	return WarehouseSelectionService.find_source_for_retrieval(world, origin, origin_macro, food, [target.id], 1, -1, reachability)
