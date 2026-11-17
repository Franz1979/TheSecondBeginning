class_name ManureStockService
extends RefCounted

# Pulizia del letame decisa dal gestore scorte (2026-11-17, richiesta utente — conigliera, fase 1). Una percentuale per
# specie (pannello Animali, species_clean_above; senza valore DEFAULT_CLEAN_ABOVE): quando il letame di un edificio arriva
# a quella parte della sua capienza (in percentuale, richiesta utente: vale uguale per edifici di capienza diversa), un
# ordine "transport" edificio → destinazione porta via tutto il letame. La singola conigliera può avere la sua
# (Building.manure_clean_override: -1 = valore della specie, 0 = esclusa, > 0 = suo). Destinazione scelta a ogni viaggio
# (pick_destination): il letamaio più vicino con posto (un edificio che accetta il letame nel suo deposito: arriverà con
# Agricoltura avanzata), altrimenti la Fossa dei rifiuti più vicina con posto; senza nessuno dei due niente ordine e un
# avviso in campanella (StockRuntimeState.manure_warnings). Il lavoro sta nella riga Allevamento e fa crescere solo
# Allevamento (come mangiatoie e lettiere). Un ordine aperto per edificio. Senza stato.

const MANURE_SOURCE_KEY := "manure_source_id"
const DEFAULT_CLEAN_ABOVE := 50


static func is_served(building: Building) -> bool:
	return ManureService.has_manure_store(building) and not building.is_out_of_service()


static func is_rule_available() -> bool:
	return WaterShelterStockService.is_rule_available()


# Soglia di pulizia di `building` in percentuale: la sua (0 = esclusa), altrimenti quella della specie tenuta.
static func clean_above(building: Building, game_data: GameData) -> int:
	if building.manure_clean_override >= 0:
		return building.manure_clean_override
	return species_clean_above(game_data, KeptAnimalService.current_species(game_data, building))


static func species_clean_above(game_data: GameData, species: String) -> int:
	if game_data == null:
		return 0
	return clampi(int(game_data.stock_manure_clean_by_species.get(species, DEFAULT_CLEAN_ABOVE)), 0, 100)


static func set_species_clean_above(game_data: GameData, species: String, value: int) -> void:
	game_data.stock_manure_clean_by_species[species] = clampi(value, 0, 100)


# Letame (unità) a cui parte la pulizia per `percent` della capienza di `building`; almeno 1.
static func threshold_units(building: Building, percent: int) -> int:
	return maxi(ceili(float(ManureService.capacity(building)) * float(percent) / 100.0 - 0.000001), 1)


# Edifici con una pulizia in corso: id -> true.
static func traveling(individuals: Array) -> Dictionary:
	var result: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		for task in JobWorkScanService.open_tasks(individual):
			if task.context.has(MANURE_SOURCE_KEY):
				result[int(task.context[MANURE_SOURCE_KEY])] = true
	return result


# Dove portare il letame di `source`: il letamaio più vicino che ne accetta almeno un'unità, altrimenti la Fossa più vicina
# con posto; null se nessuno.
static func pick_destination(world: World, source: Building) -> Building:
	if world == null:
		return null
	var origin: Vector2 = InfluenceService.building_absolute_center(source) if source != null else Vector2.ZERO
	var best: Building = null
	var best_distance := INF
	for building in world.buildings:
		if building == null or building == source or not building.is_complete or building.is_out_of_service():
			continue
		if not BuildingStorageService.can_accept(building, ManureService.RESOURCE) \
				or BuildingStorageService.get_max_depositable(building, ManureService.RESOURCE) <= 0:
			continue
		var distance: float = InfluenceService.building_absolute_center(building).distance_to(origin)
		if distance < best_distance:
			best_distance = distance
			best = building
	if best != null:
		return best
	return WasteDisposalService.find_pit_for(world, maxi(ceili(_unit_space()), 1), source)


# Ordini da togliere (id), da creare ({MANURE_SOURCE_KEY, "quantity", "building"}) e avvisi (id degli edifici oltre la
# soglia senza un posto dove buttarlo). `open_orders`: ordini del cassetto con MANURE_SOURCE_KEY; `in_transit`: traveling().
static func plan_orders(world: World, game_data: GameData, open_orders: Array, in_transit: Dictionary) -> Dictionary:
	var result := {"remove": [], "create": [], "warnings": []}
	var open_by_source: Dictionary = {}
	for order in open_orders:
		var source_id := int(order.get(MANURE_SOURCE_KEY, -1))
		if not open_by_source.has(source_id):
			open_by_source[source_id] = []
		(open_by_source[source_id] as Array).append(order)
	var served: Dictionary = {}
	if world != null and game_data != null:
		for building in world.buildings:
			if not is_served(building):
				continue
			var percent := clean_above(building, game_data)
			var manure := ManureService.stored(building)
			if percent <= 0 or manure <= 0:
				continue
			served[building.id] = true
			var threshold := threshold_units(building, percent)
			if manure < threshold or open_by_source.has(building.id) or in_transit.has(building.id):
				continue
			if pick_destination(world, building) == null:
				(result["warnings"] as Array).append(building.id)
				continue
			DebugLogging.print_event("[MANURE] Pulisco %s #%d: %d letame (soglia %d%% = %d)." % [building.building_type_name, building.id,
				manure, percent, threshold])
			(result["create"] as Array).append({MANURE_SOURCE_KEY: building.id, "quantity": manure, "building": building})
	for source_id in open_by_source.keys():
		if not served.has(int(source_id)):
			for order in open_by_source[source_id]:
				(result["remove"] as Array).append(int(order["id"]))
	return result


static func _unit_space() -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(ManureService.RESOURCE)
	return rules.space_per_unit if rules != null and rules.space_per_unit > 0.0 else 1.0
