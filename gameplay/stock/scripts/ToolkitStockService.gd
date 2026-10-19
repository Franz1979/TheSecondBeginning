class_name ToolkitStockService
extends RefCounted

# Regola del gestore scorte "Rifornisci le Attrezzerie" (2026-10-18, richiesta utente): per TIPO di edificio con
# Attrezzeria il giocatore fissa quanti pezzi di ogni attrezzo accettato vuole (GameData.stock_toolkit_targets, es.
# "woodshed" -> {"stone_axe": 2}: vale per tutte le Legnaie). All'Inventario il WM crea ordini "transport" deposito →
# Attrezzeria per quello che manca, ANCHE sotto la scorta minima del magazzino (così il minimo fa nascere gli ordini di
# produzione per rimpiazzarli); senza pezzi nei magazzini, un avviso in campanella. Il WM non produce attrezzi da sé.
# Stesso schema di FuelStockService: servizio senza stato, decide quali ordini creare o togliere.

# Nell'ordine del cassetto e nel context della Transport Task: id dell'edificio e attrezzo da portare.
const TOOLKIT_TARGET_KEY := "toolkit_target_id"
const TOOLKIT_TOOL_KEY := "toolkit_tool"


# Attrezzi che l'Attrezzeria del tipo `type_name` accetta (BuildingToolkitService.accepted_tools_for_type).
# Righe del cassetto: [{"type", "name", "tools": [{"tool", "level", "max"}]}] per i tipi con Attrezzeria già sbloccati.
static func get_rule_rows(game_data: GameData, completed_ideas: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for type_name in BuildingCalculator.list_building_type_names():
		if not BuildingToolkitService.type_has_toolkit(type_name):
			continue
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules.required_idea_id != "" and not completed_ideas.has(rules.required_idea_id):
			continue
		var tools: Array[Dictionary] = []
		for tool_name in BuildingToolkitService.accepted_tools_for_type(type_name):
			tools.append({
				"tool": tool_name, "level": get_target(game_data, type_name, tool_name),
				"max": BuildingToolkitService.units_per_type_for(type_name),
			})
		if not tools.is_empty():
			rows.append({"type": type_name, "name": rules.building_name, "tools": tools})
	return rows


# Pezzi voluti di `tool_name` nelle Attrezzerie del tipo `type_name` (0 = nessuno).
static func get_target(game_data: GameData, type_name: String, tool_name: String) -> int:
	if game_data == null:
		return 0
	return int((game_data.stock_toolkit_targets.get(type_name, {}) as Dictionary).get(tool_name, 0))


static func set_target(game_data: GameData, type_name: String, tool_name: String, level: int) -> void:
	if not game_data.stock_toolkit_targets.has(type_name):
		game_data.stock_toolkit_targets[type_name] = {}
	var by_tool: Dictionary = game_data.stock_toolkit_targets[type_name]
	if level > 0:
		by_tool[tool_name] = level
	else:
		by_tool.erase(tool_name)
	if by_tool.is_empty():
		game_data.stock_toolkit_targets.erase(type_name)


static func order_key(building_id: int, tool_name: String) -> String:
	return "%d|%s" % [building_id, tool_name]


# Pezzi in viaggio verso le Attrezzerie: "id|attrezzo" -> residuo dei trasporti con TOOLKIT_TARGET_KEY (il più alto per
# individuo: i viaggi ripetuti portano lo stesso residuo).
static func traveling(individuals: Array) -> Dictionary:
	var result: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var best: Dictionary = {}
		for task in JobWorkScanService.open_tasks(individual):
			if not task.context.has(TOOLKIT_TARGET_KEY):
				continue
			var key := order_key(int(task.context[TOOLKIT_TARGET_KEY]), String(task.context.get(TOOLKIT_TOOL_KEY, "")))
			best[key] = maxi(int(best.get(key, 0)), int(task.context.get("transport_requested_remaining", 0)))
		for key in best.keys():
			result[key] = int(result.get(key, 0)) + int(best[key])
	return result


# Ordini da togliere (id), da creare ({TOOLKIT_TARGET_KEY, TOOLKIT_TOOL_KEY, "quantity", "building"}) e avvisi
# (attrezzo -> pezzi che mancano e nessun magazzino ha). `open_orders`: ordini del cassetto con TOOLKIT_TARGET_KEY non
# ancora presi; `in_transit`: traveling().
static func plan_orders(world: World, game_data: GameData, open_orders: Array, in_transit: Dictionary) -> Dictionary:
	var result := {"remove": [], "create": [], "warnings": {}}
	var open_by_key: Dictionary = {}
	for order in open_orders:
		open_by_key[order_key(int(order.get(TOOLKIT_TARGET_KEY, -1)), String(order.get(TOOLKIT_TOOL_KEY, "")))] = order
	var served: Dictionary = {}
	if world != null and game_data != null and game_data.stock_toolkit_rule_enabled:
		for building in world.buildings:
			if building.is_demolished or not building.is_complete or building.is_out_of_service():
				continue
			var targets: Dictionary = game_data.stock_toolkit_targets.get(building.building_type_name, {})
			for tool_name in targets.keys():
				var tool := String(tool_name)
				if not BuildingToolkitService.is_accepted_tool(building, tool):
					continue
				var key := order_key(building.id, tool)
				served[key] = true
				var desired := mini(int(targets[tool_name]), BuildingToolkitService.get_units_per_type(building))
				var missing := desired - BuildingToolkitService.get_quantity(building, tool) - int(in_transit.get(key, 0))
				missing = mini(missing, BuildingToolkitService.get_max_toolkit_depositable(building, tool))
				if missing <= 0:
					if open_by_key.has(key):
						(result["remove"] as Array).append(int(open_by_key[key]["id"]))
					continue
				if open_by_key.has(key):
					continue
				var excluded: Array[int] = [building.id]
				if not WarehouseSelectionService.has_retrieval_source(world, tool, excluded):
					var warnings: Dictionary = result["warnings"]
					warnings[tool] = int(warnings.get(tool, 0)) + missing
					continue
				(result["create"] as Array).append({TOOLKIT_TARGET_KEY: building.id, TOOLKIT_TOOL_KEY: tool, "quantity": missing, "building": building})
	# Ordini per Attrezzerie non più da servire (regola spenta, desiderato a 0, edificio sparito o fuori servizio).
	for key in open_by_key.keys():
		if not served.has(key):
			(result["remove"] as Array).append(int(open_by_key[key]["id"]))
	return result


# Sorgente per portare `tool_name` all'Attrezzeria di `target`: il magazzino più vicino a `worker` (null = chiunque) che
# lo ha, senza guardare la scorta minima. null se nessuno.
static func pick_source(world: World, target: Building, tool_name: String, worker: HumanIndividual) -> Building:
	if world == null or target == null:
		return null
	var origin := worker.position if worker != null else Vector2.ZERO
	var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
	var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
	return WarehouseSelectionService.find_source_for_retrieval(world, origin, origin_macro, tool_name, [target.id], 1, -1, reachability)
