class_name FuelStockService
extends RefCounted

# Regola del gestore scorte "combustibile negli edifici che lo usano" (2026-10-16, richiesta utente): ogni edificio
# completo e in servizio con almeno una ricetta che brucia combustibile (focolare, affumicatoio…) deve avere nel suo
# deposito almeno il minimo del suo TIPO (in unità di fuel_value). Minimo per tipo modificabile nel cassetto Gestione
# scorte (GameData.stock_fuel_min_by_type); un tipo mai toccato usa BuildingRules.fuel_stock_min. Regola accesa/spenta:
# GameData.stock_fuel_rule_enabled.
# Servizio senza stato: decide quali ordini creare o togliere; GameScene li mette nel cassetto come ordini "transport"
# (deposito → edificio) con FUEL_TARGET_KEY. L'ordine chiede una quantità di combustibile, non una risorsa: quale
# combustibile e da dove lo sceglie chi lo prende (pick_fuel), il migliore nella sorgente più vicina.
# Il combustibile già dentro gli edifici non è nelle scorte del magazzino: si legge edificio per edificio.

# Nell'ordine del cassetto e nel context della Transport Task: id dell'edificio da rifornire.
const FUEL_TARGET_KEY := "fuel_target_id"
# Nell'ordine: combustibile da portare (in fuel_value).
const FUEL_AMOUNT_KEY := "fuel_amount"


# true se il tipo `type_name` ha almeno una ricetta che brucia combustibile.
static func type_uses_fuel(type_name: String) -> bool:
	var rules := BuildingCalculator.get_building_rules(type_name)
	if rules == null or not rules.is_workstation:
		return false
	for recipe_name in CaloricCalculator.list_secondary_resource_names():
		var recipe := CaloricCalculator.get_caloric_source_rules(recipe_name)
		if recipe != null and recipe.recipe_fuel_required > 0.0 and recipe.recipe_workstation_types.has(type_name):
			return true
	return false


# Righe del cassetto: [{"type", "name", "level"}] per i tipi che usano combustibile e sono già sbloccati
# (required_idea_id tra `completed_ideas`).
static func get_rule_rows(game_data: GameData, completed_ideas: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for type_name in BuildingCalculator.list_building_type_names():
		if not type_uses_fuel(type_name):
			continue
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules.required_idea_id != "" and not completed_ideas.has(rules.required_idea_id):
			continue
		rows.append({"type": type_name, "name": rules.building_name, "level": get_min_for_type(type_name, game_data)})
	return rows


# Minimo della partita per `type_name`, o quello del suo .tres se mai cambiato.
static func get_min_for_type(type_name: String, game_data: GameData) -> int:
	if game_data != null and game_data.stock_fuel_min_by_type.has(type_name):
		return int(game_data.stock_fuel_min_by_type[type_name])
	var rules := BuildingCalculator.get_building_rules(type_name)
	return rules.fuel_stock_min if rules != null else 0


# Ordini da togliere (id) e da creare ({FUEL_TARGET_KEY, FUEL_AMOUNT_KEY, "building"}) per la regola.
# `open_orders`: gli ordini del cassetto con FUEL_TARGET_KEY non ancora presi; `traveling`: edificio id -> combustibile
# già in viaggio (traveling_fuel).
static func plan_orders(world: World, game_data: GameData, open_orders: Array, traveling: Dictionary) -> Dictionary:
	var result := {"remove": [], "create": []}
	var open_by_target: Dictionary = {}
	for order in open_orders:
		open_by_target[int(order.get(FUEL_TARGET_KEY, -1))] = order
	var served: Dictionary = {}
	if world != null and game_data != null and game_data.stock_fuel_rule_enabled:
		var uses_by_type: Dictionary = {}
		for building in world.buildings:
			if building.is_demolished or not building.is_complete or building.is_out_of_service():
				continue
			var type_name := building.building_type_name
			if not uses_by_type.has(type_name):
				uses_by_type[type_name] = type_uses_fuel(type_name)
			var min_fuel := get_min_for_type(type_name, game_data)
			if not bool(uses_by_type[type_name]) or min_fuel <= 0:
				continue
			served[building.id] = true
			var missing := float(min_fuel) - ProductionService.get_available_fuel(building) - float(traveling.get(building.id, 0.0))
			if missing <= ProductionService.FUEL_EPSILON:
				if open_by_target.has(building.id):
					(result["remove"] as Array).append(int(open_by_target[building.id]["id"]))
				continue
			if open_by_target.has(building.id):
				continue
			if pick_fuel(world, building, missing, null).is_empty():
				continue
			(result["create"] as Array).append({FUEL_TARGET_KEY: building.id, FUEL_AMOUNT_KEY: missing, "building": building})
	# Ordini per edifici non più da servire (regola spenta, minimo a 0, edificio sparito o fuori servizio).
	for target_id in open_by_target.keys():
		if not served.has(int(target_id)):
			(result["remove"] as Array).append(int(open_by_target[target_id]["id"]))
	return result


# Combustibile da portare a `target` per `fuel_amount` (in fuel_value): {"resource", "quantity", "source"} — sorgente
# più vicina a `worker` (con `worker` null: a chiunque) con combustibile, risorsa = la migliore lì
# (MaterialSupplyService.best_fuel_in), pezzi = fuel_amount / fuel_value per eccesso, limitati al posto nell'edificio.
# {} se niente da portare.
static func pick_fuel(world: World, target: Building, fuel_amount: float, worker: HumanIndividual) -> Dictionary:
	if world == null or target == null or fuel_amount <= ProductionService.FUEL_EPSILON:
		return {}
	var origin := worker.position if worker != null else Vector2.ZERO
	var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
	var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
	var source := WarehouseSelectionService.find_source_for_retrieval(
		world, origin, origin_macro, WarehouseSelectionService.FUEL_CRITERION, [target.id], 1, -1, reachability, true
	)
	if source == null:
		return {}
	var fuel_name := MaterialSupplyService.best_fuel_in(source)
	var fuel_value := ProductionService.get_fuel_value(fuel_name)
	if fuel_name == "" or fuel_value <= 0.0:
		return {}
	var units: int = int(ceil(fuel_amount / fuel_value - ProductionService.FUEL_EPSILON))
	var quantity := mini(units, BuildingStorageService.get_max_depositable(target, fuel_name))
	if quantity <= 0:
		return {}
	return {"resource": fuel_name, "quantity": quantity, "source": source}


# Combustibile in viaggio per edificio (id -> fuel_value × pezzi ancora da consegnare) dai trasporti con FUEL_TARGET_KEY
# (il più alto per individuo: i viaggi ripetuti portano lo stesso residuo).
static func traveling_fuel(individuals: Array) -> Dictionary:
	var result: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var tasks: Array = [individual.current_task]
		tasks.append_array(individual.task_queue)
		var best: Dictionary = {}
		for task in tasks:
			if task == null or (task as Task).is_finished() or not (task as Task).context.has(FUEL_TARGET_KEY):
				continue
			var target_id := int((task as Task).context[FUEL_TARGET_KEY])
			var fuel_name := String((task as Task).context.get("transport_delivery_resource", ""))
			var amount := float(int((task as Task).context.get("transport_requested_remaining", 0))) * maxf(ProductionService.get_fuel_value(fuel_name), 1.0)
			best[target_id] = maxf(float(best.get(target_id, 0.0)), amount)
		for target_id in best.keys():
			result[target_id] = float(result.get(target_id, 0.0)) + float(best[target_id])
	return result
