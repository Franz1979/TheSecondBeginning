class_name BeddingStockService
extends RefCounted

# Regola del gestore scorte "Lettiera" (2026-11-17, richiesta utente — conigliera): come "Rifornisci le mangiatoie"
# (FeederStockService). Un numero per specie (pannello Animali, species_days), i giorni di paglia da tenere nelle lettiere
# (0 = nessun rifornimento); il singolo edificio può avere il suo (Building.bedding_days_override: -1 = valore della
# generale, 0 = escluso, > 0 = giorni suoi). A ogni Inventario, per ogni edificio con lettiera: obiettivo = paglia al giorno
# di tutti i posti (BeddingService.target_daily_use) × giorni, mai oltre la capienza. Se la lettiera (con quanto già in
# viaggio e gli ordini aperti) sta sotto, un ordine "transport" magazzino → lettiera, da tutta la scorta del villaggio e
# almeno uno zaino pieno fin dove c'è posto; senza paglia un avviso in campanella (StockRuntimeState.bedding_warnings). Il
# lavoro sta nella riga Allevamento e fa crescere solo Allevamento (come le mangiatoie). Senza stato.

const BEDDING_TARGET_KEY := "bedding_target_id"
const DEFAULT_DAYS := 20


static func is_served(building: Building) -> bool:
	return BeddingService.has_bedding(building) and not building.is_out_of_service()


# Giorni voluti in `building`: i suoi (0 = escluso), altrimenti quelli della specie tenuta (pannello Animali).
static func days_for(building: Building, game_data: GameData) -> int:
	if building.bedding_days_override >= 0:
		return building.bedding_days_override
	return species_days(game_data, KeptAnimalService.current_species(game_data, building))


# Giorni della specie (2026-11-17, pannello Animali); senza valore il default GameData.stock_bedding_days.
static func species_days(game_data: GameData, species: String) -> int:
	if game_data == null:
		return 0
	return maxi(int(game_data.stock_bedding_days_by_species.get(species, game_data.stock_bedding_days)), 0)


static func set_species_days(game_data: GameData, species: String, days: int) -> void:
	game_data.stock_bedding_days_by_species[species] = maxi(days, 0)


# true se il WM è sbloccato: solo allora il pannello dell'edificio mostra i giorni.
static func is_rule_available() -> bool:
	return WaterShelterStockService.is_rule_available()


# Paglia in viaggio verso le lettiere: id -> unità (il residuo più alto per individuo: i viaggi ripetuti portano lo stesso).
static func traveling(individuals: Array) -> Dictionary:
	var result: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var best: Dictionary = {}
		for task in JobWorkScanService.open_tasks(individual):
			if not task.context.has(BEDDING_TARGET_KEY):
				continue
			var target_id := int(task.context[BEDDING_TARGET_KEY])
			best[target_id] = maxi(int(best.get(target_id, 0)), int(task.context.get("transport_requested_remaining", 0)))
		for target_id in best.keys():
			result[target_id] = int(result.get(target_id, 0)) + int(best[target_id])
	return result


# Ordini da togliere (id), da creare ({BEDDING_TARGET_KEY, "quantity", "building"}) e avvisi (id degli edifici senza paglia
# da ricevere). `open_orders`: ordini del cassetto con BEDDING_TARGET_KEY non presi; `in_transit`: traveling(); `stock`:
# scorta del villaggio; `load_space`: uno zaino pieno.
static func plan_orders(world: World, game_data: GameData, open_orders: Array, in_transit: Dictionary, stock: Dictionary,
		load_space: float) -> Dictionary:
	var result := {"remove": [], "create": [], "warnings": []}
	var open_by_target: Dictionary = {}
	var promised := 0
	for order in open_orders:
		var target_id := int(order.get(BEDDING_TARGET_KEY, -1))
		if not open_by_target.has(target_id):
			open_by_target[target_id] = []
		(open_by_target[target_id] as Array).append(order)
		promised += int(order.get("quantity", 0))
	var served: Dictionary = {}
	if world != null and game_data != null:
		var unit_space := _unit_space()
		for building in world.buildings:
			if not is_served(building):
				continue
			var days := days_for(building, game_data)
			var need := BeddingService.target_daily_use(game_data, building)
			if days <= 0 or need <= 0.0:
				continue
			served[building.id] = true
			var open: Array = open_by_target.get(building.id, [])
			var have := building.bedding_straw + float(in_transit.get(building.id, 0))
			for order in open:
				have += float(order.get("quantity", 0))
			var capacity := float(BeddingService.capacity(building))
			var for_need := ceili(minf(need * float(days), capacity) - have - 0.000001)
			if for_need <= 0 or not open.is_empty():
				continue
			var room := floori(capacity - have + 0.000001)
			var available := int(stock.get(BeddingService.RESOURCE, 0)) - promised
			if available <= 0:
				(result["warnings"] as Array).append(building.id)
				continue
			var for_load := floori(maxf(load_space, 0.0) / unit_space + 0.000001)
			var units := mini(mini(maxi(for_need, for_load), available), room)
			if units <= 0:
				continue
			promised += units
			DebugLogging.print_event("[BEDDING] Riempio %s #%d: %d giorni × %.2f paglia/giorno (%d posti); dentro %.1f, in viaggio %d -> porto %d." % [
				building.building_type_name, building.id, days, need, KeptAnimalService.capacity(building), building.bedding_straw,
				int(in_transit.get(building.id, 0)), units])
			(result["create"] as Array).append({BEDDING_TARGET_KEY: building.id, "quantity": units, "building": building})
	for target_id in open_by_target.keys():
		if not served.has(int(target_id)):
			for order in open_by_target[target_id]:
				(result["remove"] as Array).append(int(order["id"]))
	return result


static func _unit_space() -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(BeddingService.RESOURCE)
	return rules.space_per_unit if rules != null and rules.space_per_unit > 0.0 else 1.0
