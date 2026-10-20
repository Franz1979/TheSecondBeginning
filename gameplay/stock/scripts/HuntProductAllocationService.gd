class_name HuntProductAllocationService
extends RefCounted

# Divisione dei prodotti delle cacce del gestore scorte (2026-10-19, richiesta utente). Allo scarico, la carne e le pelli
# che il cacciatore porta vanno prima a coprire i minimi che ne mancano, divise in proporzione a quanto manca a ciascuno;
# quello che avanza va alla destinazione scelta per il suo tipo (la coppia carne/pelli del gestore,
# ButcherDestinationService). Minimi, per la risorsa portata:
#   - essiccatoio: prodotti ad avanzamento automatico sotto livello che la usano (carne/pelle essiccata), al netto di
#     quanto è già sull'essiccatoio, in viaggio o negli ordini "transport" aperti;
#   - affumicatoio: ciò che manca agli ordini già sulle postazioni dell'affumicatoio (l'affumicatura va ordinata: senza
#     ordine la carne lì resterebbe ferma);
#   - focolare (solo la carne): prodotti con lavoro del focolare sotto livello (carne cotta), al netto di quelli in
#     produzione e della carne già nei focolari;
#   - magazzino: il livello della risorsa stessa (riserva di carne cruda, pelli) più ciò che serve agli ordini "Produci"
#     del cassetto fatti altrove (es. vestiti di pelliccia), al netto della scorta.
# Destinazioni senza un edificio disponibile non ricevono nulla. Stateless; legge la partita da GameSettings.


# [{"target": ButcherDestinationService target, "quantity": int}] per `quantity` unità di `resource_name`; somma esatta.
static func allocate(resource_name: String, quantity: int, destination: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if quantity <= 0:
		return result
	var fallback := ButcherDestinationService.target_for(destination, resource_name)
	var deficits := get_deficits(resource_name)
	var total := 0
	for target in deficits.keys():
		total += int(deficits[target])
	var shares: Dictionary = {}
	if total <= 0:
		shares[fallback] = quantity
	elif total <= quantity:
		shares = deficits.duplicate()
		shares[fallback] = int(shares.get(fallback, 0)) + quantity - total
	else:
		shares = _proportional(deficits, total, quantity)
	for target in shares.keys():
		if int(shares[target]) > 0:
			result.append({"target": String(target), "quantity": int(shares[target])})
	return result


# Quanto manca a ciascun minimo, per destinazione: target -> unità di `resource_name` (solo i positivi).
static func get_deficits(resource_name: String) -> Dictionary:
	var deficits: Dictionary = {}
	var world: World = GameSettings.active_world
	var game_data: GameData = GameSettings.active_game_data
	if world == null or game_data == null:
		return deficits
	var folk: Folk = GameSettings.active_human_folk
	var stock := VillageStockService.get_village_stock(world)
	var candidates := {
		ButcherDestinationService.DRYING_RACK: _drying_deficit(world, game_data, stock, resource_name),
		ButcherDestinationService.SMOKEHOUSE: _ordered_deficit(world, ButcherDestinationService.SMOKEHOUSE, resource_name, stock),
		ButcherDestinationService.CAMPFIRE: _campfire_deficit(world, game_data, stock, resource_name),
		ButcherDestinationService.WAREHOUSE: _warehouse_deficit(game_data, stock, resource_name),
	}
	for target in candidates.keys():
		var amount := int(candidates[target])
		if amount > 0 and ButcherDestinationService.accepts_resource(String(target), resource_name) \
				and ButcherDestinationService.is_available(String(target), world, folk):
			deficits[target] = amount
	return deficits


static func _drying_deficit(world: World, game_data: GameData, stock: Dictionary, resource_name: String) -> int:
	var total := 0
	for level_name in game_data.stock_min_levels.keys():
		var recipe := String(level_name)
		if StockRequestService.source_kind_for(recipe) != StockRequestService.SOURCE_DRY \
				or WarehouseManagerService.dry_ingredient(recipe) != resource_name:
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(recipe)
		var covered := int(stock.get(recipe, 0)) + WarehouseManagerService.dry_in_racks(world, recipe, resource_name) \
			+ WarehouseManagerService.dry_traveling(GameSettings.active_human_individuals, recipe)
		for order in game_data.drawer_orders:
			if String(order.get("type", "")) == DrawerOrderService.TYPE_TRANSPORT and String(order.get("recipe", "")) == recipe:
				covered += int(order.get("quantity", 0))
		var missing := int(game_data.stock_min_levels[level_name]) - covered
		if missing > 0:
			total += missing * int(rules.recipe_inputs.get(resource_name, 1))
	return total


# Ciò che manca agli ordini già sulle postazioni del tipo di `target` (meno quello che hanno già nel deposito) e agli
# ordini "Produci" del cassetto per ricette di quel tipo, meno la risorsa già nei depositi del villaggio (lì la
# prenderebbero comunque).
static func _ordered_deficit(world: World, target: String, resource_name: String, stock: Dictionary) -> int:
	var building_type := String(ButcherDestinationService.BUILDING_TYPES[target])
	var total := 0
	for order in GameSettings.active_game_data.drawer_orders:
		if String(order.get("type", "")) != DrawerOrderService.TYPE_PRODUCE:
			continue
		var order_rules := CaloricCalculator.get_caloric_source_rules(String(order.get("recipe", "")))
		if order_rules != null and order_rules.recipe_workstation_types.has(building_type) and order_rules.recipe_inputs.has(resource_name):
			total += int(order.get("quantity", 0)) * int(order_rules.recipe_inputs[resource_name])
	for building in world.buildings:
		if building.building_type_name != building_type or building.is_demolished or not building.is_complete:
			continue
		var needed := 0
		for order_key in ProductionService.get_order_keys(building):
			var rules := CaloricCalculator.get_caloric_source_rules(ProductionService.get_order_recipe(building, order_key))
			if rules != null and rules.recipe_inputs.has(resource_name):
				needed += ProductionService.get_order_units(building, order_key) * int(rules.recipe_inputs[resource_name])
		total += maxi(needed - _stored(building, resource_name), 0)
	return maxi(total - int(stock.get(resource_name, 0)), 0)


# Ricette del focolare con un livello che usano la risorsa: i pezzi che mancano al livello oltre a quelli già ordinati,
# meno la carne già nei focolari. Gli ordini già esistenti (anche la cottura per i giorni di cibo) non contano: nascono
# solo con la carne cruda già in deposito, quindi la loro carne c'è (2026-10-19, correzione chiesta dall'utente).
static func _campfire_deficit(world: World, game_data: GameData, stock: Dictionary, resource_name: String) -> int:
	var campfire_type := String(ButcherDestinationService.BUILDING_TYPES[ButcherDestinationService.CAMPFIRE])
	var needed := 0
	for level_name in game_data.stock_min_levels.keys():
		var recipe := String(level_name)
		var rules := CaloricCalculator.get_caloric_source_rules(recipe)
		if rules == null or rules.recipe_auto_progress_days > 0 or not rules.recipe_inputs.has(resource_name) \
				or not rules.recipe_workstation_types.has(campfire_type):
			continue
		var missing := int(game_data.stock_min_levels[level_name]) - int(stock.get(recipe, 0)) - _units_in_progress(world, recipe)
		if missing > 0:
			needed += missing * int(rules.recipe_inputs[resource_name])
	if needed <= 0:
		return 0
	var in_campfires := 0
	for building in world.buildings:
		if building.building_type_name == campfire_type and not building.is_demolished:
			in_campfires += _stored(building, resource_name)
	return maxi(needed - in_campfires, 0)


static func _warehouse_deficit(game_data: GameData, stock: Dictionary, resource_name: String) -> int:
	var needed := int(game_data.stock_min_levels.get(resource_name, 0))
	var processing_types: Array[String] = []
	for target in [ButcherDestinationService.CAMPFIRE, ButcherDestinationService.DRYING_RACK, ButcherDestinationService.SMOKEHOUSE]:
		processing_types.append(String(ButcherDestinationService.BUILDING_TYPES[target]))
	for order in game_data.drawer_orders:
		if String(order.get("type", "")) != DrawerOrderService.TYPE_PRODUCE:
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(String(order.get("recipe", "")))
		if rules == null or not rules.recipe_inputs.has(resource_name):
			continue
		var made_at_processing := false
		for building_type in processing_types:
			if rules.recipe_workstation_types.has(building_type):
				made_at_processing = true
		if not made_at_processing:
			needed += int(order.get("quantity", 0)) * int(rules.recipe_inputs[resource_name])
	return maxi(needed - int(stock.get(resource_name, 0)), 0)


# Pezzi di `recipe` ancora da fare negli ordini sulle postazioni e negli ordini "Produci" del cassetto.
static func _units_in_progress(world: World, recipe: String) -> int:
	var units := 0
	for building in world.buildings:
		if building.is_demolished or building.rules == null or not building.rules.is_workstation:
			continue
		for order_key in ProductionService.get_order_keys(building):
			if ProductionService.get_order_recipe(building, order_key) == recipe:
				units += ProductionService.get_order_units(building, order_key)
	for order in GameSettings.active_game_data.drawer_orders:
		if String(order.get("type", "")) == DrawerOrderService.TYPE_PRODUCE and String(order.get("recipe", "")) == recipe:
			units += int(order.get("quantity", 0))
	return units


static func _stored(building: Building, resource_name: String) -> int:
	var entry: Variant = building.stored_resources.get(resource_name, null)
	return int((entry as Dictionary).get("quantity", 0)) if entry is Dictionary else 0


# `quantity` diviso tra i minimi in proporzione a quanto manca (largest remainder: la somma è esatta).
static func _proportional(deficits: Dictionary, total: int, quantity: int) -> Dictionary:
	var shares: Dictionary = {}
	var remainders: Array = []
	var assigned := 0
	for target in deficits.keys():
		var exact := float(quantity) * float(deficits[target]) / float(total)
		var whole := floori(exact)
		shares[target] = whole
		assigned += whole
		remainders.append({"target": target, "rest": exact - float(whole)})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rest"]) > float(b["rest"]))
	var index := 0
	while assigned < quantity and not remainders.is_empty():
		var target: Variant = remainders[index % remainders.size()]["target"]
		shares[target] = int(shares[target]) + 1
		assigned += 1
		index += 1
	return shares
