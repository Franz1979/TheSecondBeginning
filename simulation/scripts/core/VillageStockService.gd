class_name VillageStockService
extends RefCounted

# Scorte del villaggio (2026-10-10, richiesta utente — cassetto "Gestione scorte", sola lettura). Stateless, stesso
# pattern degli altri *Service. Contano, per ogni edificio COMPLETO e non demolito:
#   - le scorte (Building.stored_resources) degli edifici che NON sono postazioni di lavoro: depositi e case;
#   - i prodotti finiti (Building.production_output) delle postazioni di lavoro.
# Non contano: ingredienti e combustibile nel magazzino delle postazioni di lavoro (le loro stored_resources), l'Attrezzeria,
# i materiali di cantieri (edifici non completi) e riparazioni (Building.repair_materials, contenitore a parte), quello
# che gli individui hanno addosso e i mucchi a terra.


# Totale per risorsa: nome -> quantità (int), solo le risorse presenti.
static func get_village_stock(world: World) -> Dictionary:
	var totals: Dictionary = {}
	if world == null:
		return totals
	for building in world.buildings:
		if building.rules == null or building.is_demolished or not building.is_complete:
			continue
		if building.rules.is_workstation:
			for output_name in building.production_output.keys():
				_add(totals, String(output_name), int(building.production_output[output_name]))
		else:
			for resource_name in building.stored_resources.keys():
				var entry: Dictionary = building.stored_resources[resource_name]
				_add(totals, String(resource_name), int(entry.get("quantity", 0)))
	return totals


# Calorie totali del cibo in `stock` (quantità × SecondaryResourceRules.calories_per_unit, solo categoria FOOD).
static func get_food_calories(stock: Dictionary) -> float:
	var calories := 0.0
	for resource_name in stock.keys():
		var rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if rules != null and rules.category == SecondaryResourceTypes.Category.FOOD:
			calories += float(stock[resource_name]) * rules.calories_per_unit
	return calories


# Riempimento dei depositi (2026-10-10, barra del cassetto "Gestione scorte"): [spazio occupato, spazio totale] dei soli
# edifici di categoria STORAGE completi e non demoliti — non le case né gli edifici di produzione. Spazio occupato =
# BuildingStorageService.get_used_space (quantità × spazio per unità); spazio totale = get_capacity, con gli slot
# effettivi (a metà se il deposito è danneggiato). Il contenuto oltre la capienza di un deposito danneggiato conta tutto.
static func get_storage_fill(world: World) -> Array:
	var used := 0.0
	var capacity := 0.0
	if world == null:
		return [used, capacity]
	for building in world.buildings:
		if building.rules == null or building.is_demolished or not building.is_complete:
			continue
		if building.rules.category != BuildingTypes.Category.STORAGE:
			continue
		used += BuildingStorageService.get_used_space(building)
		capacity += float(BuildingStorageService.get_capacity(building))
	return [used, capacity]


static func _add(totals: Dictionary, resource_name: String, quantity: int) -> void:
	if quantity <= 0:
		return
	totals[resource_name] = int(totals.get(resource_name, 0)) + quantity
