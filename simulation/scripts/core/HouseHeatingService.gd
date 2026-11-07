class_name HouseHeatingService
extends RefCounted

# Riscaldamento delle case (2026-10-22, richiesta utente — Hut). Stateless, come gli altri *Service.
#
# Nelle stagioni fredde (COLD_SEASONS: inverno e autunno) il bonus giornaliero della casa vale solo se la casa è
# riscaldata quel giorno, altrimenti 0 (HumanVitalsInteractionService, regola 0; il malus resta solo per chi non ha casa).
# Una casa è riscaldabile se BuildingRules.heating_fuel_per_day_by_season ha un valore > 0 (oggi la Hut; le tende no:
# in autunno e inverno il loro bonus è sempre 0).
#
# Ogni giorno, per ogni casa riscaldabile ABITATA: il fabbisogno della stagione si prende dall'anticipo della casa
# (Building.heating_fuel_credit); se non basta si brucia SUBITO un pezzo intero dal deposito (ProductionService.consume_fuel:
# prima il fuel_value più alto, a parità per nome) e quello che avanza resta come anticipo per i giorni dopo (es. 0.5
# d'inverno = un pezzo ogni due giorni, 0.2 d'autunno = uno ogni cinque). Così nel deposito c'è solo legna davvero libera
# (2026-11-07, richiesta utente: prima era un debito e il pannello mostrava pezzi già in parte consumati). Se anticipo e
# deposito insieme non bastano, oggi resta fredda e non si brucia nulla. Stessa regola per il fuoco della zuppa
# (HomeSoupService), con can_cover_fuel/spend_fuel.
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
# Building.heated_today e Building.heating_fuel_credit e brucia il combustibile.
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
	if need <= 0.0 or not can_cover_fuel(building, need):
		return false
	spend_fuel(building, need)
	return true


# true se anticipo + combustibile nel deposito della casa coprono `amount`. L'anticipo può essere negativo solo nei
# salvataggi di prima del 2026-11-07 (il vecchio debito, GameLoadService): va saldato prima.
static func can_cover_fuel(building: Building, amount: float) -> bool:
	return building.heating_fuel_credit + ProductionService.get_available_fuel(building) + ProductionService.FUEL_EPSILON >= amount


# Consuma `amount`: prima dall'anticipo, poi bruciando pezzi interi; l'avanzo resta come anticipo. Chiamare dopo
# can_cover_fuel.
static func spend_fuel(building: Building, amount: float) -> void:
	building.heating_fuel_credit -= amount
	if building.heating_fuel_credit < -ProductionService.FUEL_EPSILON:
		building.heating_fuel_credit += ProductionService.consume_fuel(building, -building.heating_fuel_credit)
	if absf(building.heating_fuel_credit) <= ProductionService.FUEL_EPSILON:
		building.heating_fuel_credit = 0.0
