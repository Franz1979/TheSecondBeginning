class_name ThoughtTargetSelectionService
extends RefCounted

# Sceglie l'edificio più vicino con rules.accepts_thoughts == true (2026-09-10, richiesta utente —
# handler di ricerca per i pensieri, parallelo a WarehouseSelectionService ma per il ramo PENSIERO
# di UnloadAction). Stesso identico pattern "thin wrapper" di WarehouseSelectionService.find_best:
# nessun algoritmo di ricerca proprio, costruisce solo il predicate di dominio ("edificio che
# accetta pensieri", vedi BuildingRules.accepts_thoughts) e delega a SpatialSelectionService.
# find_nearest — stesso motore già in uso per la ricerca magazzino.
#
# Nessun parametro resource_name/quantity_needed (a differenza di WarehouseSelectionService.
# find_best): un pensiero non ha una categoria/quantità da verificare contro una capacità
# residua — solo "questo edificio accetta pensieri?", un controllo booleano su rules, nessuna
# nozione di spazio libero coinvolta (coerente con UnloadAction: il ramo pensiero è sempre a
# costo/spazio zero, vedi nota in testa a unload_action.gd).
static func find_best(
	world: World,
	origin_position: Vector2,
	origin_macro_coords: Vector2i,
	excluded_building_ids: Array[int] = []
) -> Building:
	if world == null:
		return null

	var predicate := func(building: Building) -> bool:
		return building.rules != null and building.rules.accepts_thoughts

	return SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, predicate, excluded_building_ids
	) as Building
