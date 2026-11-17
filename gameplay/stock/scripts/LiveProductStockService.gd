class_name LiveProductStockService
extends RefCounted

# Raccolta dei prodotti da vivi decisa dal gestore scorte (2026-11-17, richiesta utente — pollaio, uova). Come la pulizia
# del letame (ManureStockService): una percentuale per specie (pannello Animali, species_collect_above; senza valore
# DEFAULT_COLLECT_ABOVE) e, sul singolo edificio, la sua (Building.live_product_collect_override: -1 = valore della specie,
# 0 = esclusa, > 0 = sua), che vince sempre. Quando un prodotto (LiveProductService) arriva a quella parte della capienza,
# un ordine "transport" edificio → magazzino porta via tutto quello che c'è. Destinazione scelta a ogni viaggio
# (pick_destination): il magazzino vero più vicino (WarehouseManagerService.is_storage_building, Fossa esclusa) che accetta
# il prodotto e ha posto; senza, niente ordine e un avviso in campanella (StockRuntimeState.live_product_warnings). Un
# ordine aperto per edificio e prodotto. Il lavoro sta nella riga Allevamento e fa crescere solo Allevamento. Chi mangia
# può comunque prendere le uova direttamente dall'edificio. Senza stato.

const LIVE_PRODUCT_SOURCE_KEY := "live_product_source_id"
const DEFAULT_COLLECT_ABOVE := 25


static func is_served(building: Building) -> bool:
	return building != null and LiveProductService.capacity(building) > 0 and building.is_complete \
		and not building.is_demolished and not building.is_out_of_service()


static func is_rule_available() -> bool:
	return ManureStockService.is_rule_available()


# Soglia di raccolta di `building` in percentuale: la sua (0 = esclusa), altrimenti quella della specie tenuta.
static func collect_above(building: Building, game_data: GameData) -> int:
	if building.live_product_collect_override >= 0:
		return building.live_product_collect_override
	return species_collect_above(game_data, KeptAnimalService.current_species(game_data, building))


static func species_collect_above(game_data: GameData, species: String) -> int:
	if game_data == null:
		return 0
	return clampi(int(game_data.stock_live_product_collect_by_species.get(species, DEFAULT_COLLECT_ABOVE)), 0, 100)


static func set_species_collect_above(game_data: GameData, species: String, value: int) -> void:
	game_data.stock_live_product_collect_by_species[species] = clampi(value, 0, 100)


# Unità a cui parte la raccolta per `percent` della capienza di `building`; almeno 1.
static func threshold_units(building: Building, percent: int) -> int:
	return maxi(ceili(float(LiveProductService.capacity(building)) * float(percent) / 100.0 - 0.000001), 1)


# Edifici con una raccolta in corso: id -> true (un ordine alla volta per edificio basta: oggi un solo prodotto per specie).
static func traveling(individuals: Array) -> Dictionary:
	var result: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		for task in JobWorkScanService.open_tasks(individual):
			if task.context.has(LIVE_PRODUCT_SOURCE_KEY):
				result[int(task.context[LIVE_PRODUCT_SOURCE_KEY])] = true
	return result


# Il magazzino vero più vicino a `source` che accetta almeno un'unità di `product`; null se nessuno.
static func pick_destination(world: World, source: Building, product: String) -> Building:
	if world == null or source == null:
		return null
	var origin: Vector2 = InfluenceService.building_absolute_center(source)
	var best: Building = null
	var best_distance := INF
	for building in world.buildings:
		if building == source or not WarehouseManagerService.is_storage_building(building) or WasteDisposalService.is_pit(building):
			continue
		if not BuildingStorageService.can_accept(building, product) or BuildingStorageService.get_max_depositable(building, product) <= 0:
			continue
		var distance: float = InfluenceService.building_absolute_center(building).distance_to(origin)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


# Ordini da togliere (id), da creare ({LIVE_PRODUCT_SOURCE_KEY, "resource", "quantity", "building"}) e avvisi (id degli
# edifici oltre la soglia senza un magazzino con posto). `open_orders`: ordini del cassetto con LIVE_PRODUCT_SOURCE_KEY;
# `in_transit`: traveling().
static func plan_orders(world: World, game_data: GameData, open_orders: Array, in_transit: Dictionary) -> Dictionary:
	var result := {"remove": [], "create": [], "warnings": []}
	var open_by_key: Dictionary = {}
	for order in open_orders:
		var key := _key(int(order.get(LIVE_PRODUCT_SOURCE_KEY, -1)), String(order.get("resource", "")))
		if not open_by_key.has(key):
			open_by_key[key] = []
		(open_by_key[key] as Array).append(order)
	var served: Dictionary = {}
	if world != null and game_data != null:
		for building in world.buildings:
			if not is_served(building):
				continue
			var percent := collect_above(building, game_data)
			if percent <= 0:
				continue
			var threshold := threshold_units(building, percent)
			for product: String in _products_of(game_data, building):
				var have := LiveProductService.stored(building, product)
				if have <= 0:
					continue
				var key := _key(building.id, product)
				served[key] = true
				if have < threshold or open_by_key.has(key) or in_transit.has(building.id):
					continue
				if pick_destination(world, building, product) == null:
					if not (result["warnings"] as Array).has(building.id):
						(result["warnings"] as Array).append(building.id)
					continue
				DebugLogging.print_event("[LIVE PRODUCT] Raccolgo %s #%d: %d %s (soglia %d%% = %d)." % [building.building_type_name,
					building.id, have, product, percent, threshold])
				(result["create"] as Array).append({LIVE_PRODUCT_SOURCE_KEY: building.id, "resource": product, "quantity": have,
					"building": building})
	for key in open_by_key.keys():
		if not served.has(key):
			for order in open_by_key[key]:
				(result["remove"] as Array).append(int(order["id"]))
	return result


# Prodotti delle specie tenute in `building` (dalle regole della specie, anche fuori stagione).
static func _products_of(game_data: GameData, building: Building) -> Array[String]:
	var products: Array[String] = []
	var rules := BeddingService.species_rules(game_data, building)
	if rules == null:
		return products
	for entry in rules.live_products:
		var product_rules := entry as LiveProductRules
		if product_rules != null and not product_rules.product.is_empty() and not products.has(product_rules.product):
			products.append(product_rules.product)
	return products


static func _key(building_id: int, product: String) -> String:
	return "%d:%s" % [building_id, product]
