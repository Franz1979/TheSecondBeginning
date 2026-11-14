class_name FieldSeedStockService
extends RefCounted

# Regola del gestore scorte "Semi nei campi" (2026-11-15, richiesta utente — campi, passo 3b). Per ogni seme domestico,
# le once da tenere nel capanno di ogni campo che lo semina (GameData.stock_field_seeds: seme -> once; assente = la
# semina di tutti i lotti, FieldSeedStoreService.default_level); il singolo campo può avere il suo
# (Building.field_seed_level), sempre entro i vasi montati (FieldSeedStoreService.target_level). A ogni Inventario, come
# "Rifornisci le mangiatoie" (FeederStockService):
# - capanno sotto il livello (con quanto già in viaggio e gli ordini aperti): un ordine "transport" magazzino → capanno,
#   mai sotto il livello minimo del seme in magazzino e mai preso dal capanno di un altro campo;
# - semi che il capanno non tiene più (specie cambiata, o oltre il livello abbassato): un ordine "transport" capanno →
#   magazzino più vicino che li accetta (decisione utente: li porta via il WM).
# Un ordine aperto per capanno e seme; gli ordini che non servono più si tolgono. Senza stato.

const SEED_TARGET_KEY := "field_seed_target_id"
const SEED_REMOVE_KEY := "field_seed_remove_id"


# Capanno che la regola serve: campo finito, in piedi, in servizio.
static func is_served(building: Building) -> bool:
	return building != null and building.rules != null and building.is_complete and not building.is_demolished \
		and not building.is_out_of_service() and FieldSeedStoreService.is_seed_store(building)


# Righe del popup "Modifica…": un seme domestico per specie addomesticata, {"resource", "level", "max"}.
static func get_rule_rows(game_data: GameData) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if game_data == null:
		return rows
	for species in DomesticPlantCalculator.list_species():
		var rules := DomesticPlantCalculator.get_rules(species)
		if rules == null or rules.domestic_resource_name == "" or not game_data.domesticated_species.has(species):
			continue
		rows.append({"resource": rules.domestic_resource_name,
			"level": FieldSeedStoreService.general_level(game_data, rules.domestic_resource_name),
			"max": FieldSeedStoreService.max_type_capacity()})
	return rows


static func set_level(game_data: GameData, seed_name: String, level: int) -> void:
	if game_data != null and seed_name != "":
		game_data.stock_field_seeds[seed_name] = maxi(level, 0)


# Semi in viaggio: {"to": {id capanno: once}, "from": {"id|seme": once}} dai trasporti della regola (il residuo più alto
# per individuo: i viaggi ripetuti portano lo stesso residuo).
static func traveling(individuals: Array) -> Dictionary:
	var result := {"to": {}, "from": {}}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var best: Dictionary = {}
		for task in JobWorkScanService.open_tasks(individual):
			var key := ""
			if task.context.has(SEED_TARGET_KEY):
				key = "to|%d" % int(task.context[SEED_TARGET_KEY])
			elif task.context.has(SEED_REMOVE_KEY):
				key = "from|%d|%s" % [int(task.context[SEED_REMOVE_KEY]), String(task.context.get("transport_resource_name", ""))]
			else:
				continue
			best[key] = maxi(int(best.get(key, 0)), int(task.context.get("transport_requested_remaining", 0)))
		for key in best.keys():
			var text := String(key)
			if text.begins_with("to|"):
				var target_id := int(text.substr(3))
				result["to"][target_id] = int(result["to"].get(target_id, 0)) + int(best[key])
			else:
				var from_key := text.substr(5)
				result["from"][from_key] = int(result["from"].get(from_key, 0)) + int(best[key])
	return result


# Ordini da togliere (id) e da creare ({SEED_TARGET_KEY o SEED_REMOVE_KEY, "resource", "quantity", "building"}).
# `open_orders`: ordini del cassetto della regola non presi; `in_transit`: traveling(); `stock`: scorta del villaggio;
# `min_levels`: livelli minimi che agiscono.
static func plan_orders(world: World, game_data: GameData, open_orders: Array, in_transit: Dictionary, stock: Dictionary,
		min_levels: Dictionary) -> Dictionary:
	var result := {"remove": [], "create": []}
	if world == null or game_data == null:
		for order in open_orders:
			(result["remove"] as Array).append(int(order["id"]))
		return result
	var promised: Dictionary = {}
	for order in open_orders:
		if order.has(SEED_TARGET_KEY):
			var resource := String(order.get("resource", ""))
			promised[resource] = int(promised.get(resource, 0)) + int(order.get("quantity", 0))
	var kept: Dictionary = {}
	for building in world.buildings:
		if not is_served(building):
			continue
		var seed_name := CultivationService.seed_resource(building)
		var target := FieldSeedStoreService.target_level(game_data, building)
		# Portare: capanno sotto il livello.
		if seed_name != "" and target > 0:
			var have := FieldSeedStoreService.stored(building) + int((in_transit["to"] as Dictionary).get(building.id, 0))
			var open_delivery: Array = open_orders.filter(func(order: Dictionary) -> bool:
				return int(order.get(SEED_TARGET_KEY, -1)) == building.id and String(order.get("resource", "")) == seed_name)
			for order in open_delivery:
				have += int(order.get("quantity", 0))
				kept[int(order["id"])] = true
			var missing := target - have
			if missing > 0 and open_delivery.is_empty():
				# La scorta del villaggio non conta i semi dei capanni (FieldSeedStoreService.is_seed_reserved, passo 3d).
				var available := int(stock.get(seed_name, 0)) - int(min_levels.get(seed_name, 0)) - int(promised.get(seed_name, 0))
				var units := mini(missing, available)
				if units > 0:
					(result["create"] as Array).append({SEED_TARGET_KEY: building.id, "resource": seed_name, "quantity": units, "building": building})
					promised[seed_name] = int(promised.get(seed_name, 0)) + units
		# Portare via: semi che il capanno non tiene più (altra specie, o oltre il livello).
		for resource_name in building.stored_resources.keys():
			var stored := int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0))
			var excess := stored if String(resource_name) != seed_name else stored - target
			excess -= int((in_transit["from"] as Dictionary).get("%d|%s" % [building.id, resource_name], 0))
			var open_removal: Array = open_orders.filter(func(order: Dictionary) -> bool:
				return int(order.get(SEED_REMOVE_KEY, -1)) == building.id and String(order.get("resource", "")) == String(resource_name))
			if excess <= 0:
				continue
			for order in open_removal:
				kept[int(order["id"])] = true
			if open_removal.is_empty():
				(result["create"] as Array).append({SEED_REMOVE_KEY: building.id, "resource": String(resource_name), "quantity": excess, "building": building})
	for order in open_orders:
		if not kept.has(int(order["id"])):
			(result["remove"] as Array).append(int(order["id"]))
	return result


# Magazzino da cui portare `seed_name` al capanno `target`: il più vicino a `worker` (null = chiunque) che lo ha, mai il
# capanno di un campo.
static func pick_source(world: World, target: Building, seed_name: String, worker: HumanIndividual) -> Building:
	if world == null or target == null:
		return null
	var excluded := FieldSeedStoreService.store_ids(world)
	var origin := worker.position if worker != null else Vector2.ZERO
	var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
	var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
	return WarehouseSelectionService.find_source_for_retrieval(world, origin, origin_macro, seed_name, excluded, 1, -1, reachability)


# Magazzino più vicino al capanno `shed` che accetta `resource_name` portato via (null se nessuno).
static func pick_destination(world: World, shed: Building, resource_name: String, worker: HumanIndividual) -> Building:
	if world == null or shed == null:
		return null
	var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
	return WarehouseSelectionService.find_best(world, Vector2(shed.micro_x, shed.micro_y), Vector2i(shed.macro_x, shed.macro_y),
		resource_name, 1, [shed.id], reachability)
