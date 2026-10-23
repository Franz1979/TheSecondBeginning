class_name HouseHeatingService
extends RefCounted

# Riscaldamento delle case (2026-10-22, richiesta utente — Hut). Stateless, come gli altri *Service.
#
# Nelle stagioni fredde (COLD_SEASONS: inverno e autunno) il bonus giornaliero della casa vale solo se la casa è
# riscaldata quel giorno, altrimenti 0 (HumanVitalsInteractionService, regola 0; il malus resta solo per chi non ha casa).
# Una casa è riscaldabile se BuildingRules.heating_fuel_per_day_by_season ha un valore > 0 (oggi la Hut; le tende no:
# in autunno e inverno il loro bonus è sempre 0).
#
# Ogni giorno, per ogni casa riscaldabile ABITATA: il fabbisogno della stagione si somma a Building.heating_fuel_due (per
# le frazioni, es. 0.5 d'inverno = una legna ogni due giorni, 0.2 d'autunno = una ogni cinque); se il combustibile della casa lo copre la casa è
# riscaldata oggi e si bruciano le unità intere dovute con la stessa regola del focolare (ProductionService.consume_fuel:
# prima il fuel_value più alto, a parità per nome); se non basta, oggi resta fredda e non si brucia nulla.
#
# Il combustibile di una casa riscaldabile è riservato alla casa (is_fuel_reserved): nessun prelievo automatico
# (WarehouseSelectionService) e fuori dalle scorte del villaggio (VillageStockService). A mano dal pannello si può togliere.

const COLD_SEASONS: Array[int] = [GameTypes.Season.WINTER, GameTypes.Season.AUTUMN]


static func is_heatable(rules: BuildingRules) -> bool:
	if rules == null or rules.max_residents <= 0:
		return false
	for value in rules.heating_fuel_per_day_by_season:
		if value > 0.0:
			return true
	return false


static func is_cold_season(season: int) -> bool:
	return COLD_SEASONS.has(season)


# true se `resource_name` è combustibile riservato alla casa riscaldabile `building`.
static func is_fuel_reserved(building: Building, resource_name: String) -> bool:
	return building != null and building.rules != null and is_heatable(building.rules) \
		and ProductionService.get_fuel_value(resource_name) > 0.0


# Riscaldamento del giorno nella stagione `season`: {"heated": {id della casa -> true} per le case riscaldate oggi,
# "changed": case il cui stato "riscaldata" è cambiato (il fumo sulla mappa va ridisegnato)}. Aggiorna
# Building.heated_today e Building.heating_fuel_due e brucia il combustibile.
static func daily_heating(world: World, individuals: Array[HumanIndividual], season: int) -> Dictionary:
	var heated: Dictionary = {}
	var changed: Array[Building] = []
	if world == null:
		return {"heated": heated, "changed": changed}
	var inhabited: Dictionary = {}
	for individual in individuals:
		if individual.house_id != -1:
			inhabited[individual.house_id] = true
	for building in world.buildings:
		if building.rules == null or not is_heatable(building.rules):
			continue
		var was_heated := building.heated_today
		building.heated_today = _heat_one(building, season, inhabited)
		if building.heated_today:
			heated[building.id] = true
		if building.heated_today != was_heated:
			changed.append(building)
	return {"heated": heated, "changed": changed}


static func _heat_one(building: Building, season: int, inhabited: Dictionary) -> bool:
	if not building.is_complete or building.is_demolished or not inhabited.has(building.id):
		return false
	var per_day: Array[float] = building.rules.heating_fuel_per_day_by_season
	var need: float = per_day[season] if season >= 0 and season < per_day.size() else 0.0
	if need <= 0.0:
		return false
	var due := building.heating_fuel_due + need
	if ProductionService.get_available_fuel(building) + ProductionService.FUEL_EPSILON < due:
		return false
	var units := floori(due + ProductionService.FUEL_EPSILON)
	if units > 0:
		ProductionService.consume_fuel(building, float(units))
		due -= float(units)
	building.heating_fuel_due = maxf(due, 0.0)
	return true
