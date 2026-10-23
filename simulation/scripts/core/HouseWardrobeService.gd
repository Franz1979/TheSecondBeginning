class_name HouseWardrobeService
extends RefCounted

# Guardaroba delle case di nucleo (2026-10-22, richiesta utente — Hut). Stateless salvo una piccola cache per fotogramma.
#
# Il deposito di una casa di nucleo (AssignHouseService.is_nucleus_house, oggi la Hut) accetta solo combustibile e
# vestiario e non fa più da magazzino di ripiego (WarehouseSelectionService.find_best la esclude). Il vestiario di una
# casa ABITATA è riservato ai suoi abitanti: non è una sorgente per gli altri (WarehouseSelectionService) né una scorta
# del villaggio (VillageStockService); gli abitanti lo prendono direttamente dalla propria casa (ToolFetchService). Casa
# vuota: il suo vestiario torna una sorgente normale. Trasloco: i capi restano nella casa.


static func is_wardrobe_house(building: Building) -> bool:
	return AssignHouseService.is_nucleus_house(building)


static func is_apparel(resource_name: String) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules != null and rules.category == SecondaryResourceTypes.Category.APPAREL


# Il deposito della casa di nucleo accetta solo combustibile e vestiario.
static func accepts(resource_name: String) -> bool:
	return ProductionService.get_fuel_value(resource_name) > 0.0 or is_apparel(resource_name)


# true se `resource_name` è vestiario riservato agli abitanti della casa `building` (casa di nucleo abitata).
static func is_apparel_reserved(building: Building, resource_name: String) -> bool:
	return is_wardrobe_house(building) and is_apparel(resource_name) and is_inhabited(building)


# Casa del pipottino se è una casa di nucleo completa e in servizio, altrimenti null.
static func home_wardrobe(world: World, individual: HumanIndividual) -> Building:
	if world == null or individual == null or individual.house_id == -1:
		return null
	for building in world.buildings:
		if building.id == individual.house_id:
			return building if is_wardrobe_house(building) and building.is_complete and not building.is_out_of_service() else null
	return null


# Case abitate, ricalcolate al più una volta per fotogramma (la ricerca delle sorgenti chiede per ogni edificio).
static var _inhabited_frame: int = -1
static var _inhabited: Dictionary = {}


static func is_inhabited(building: Building) -> bool:
	var frame := Engine.get_process_frames()
	if frame != _inhabited_frame:
		_inhabited_frame = frame
		_inhabited.clear()
		for individual in GameSettings.active_human_individuals:
			if individual.house_id != -1:
				_inhabited[individual.house_id] = true
	return _inhabited.has(building.id)
