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


# Gate booleano riusabile (2026-09-10, richiesta utente — Step 3 del refactor Daydream via
# TaskFactory, preparazione del meccanismo) — "esiste ALMENO UN edificio che accetta pensieri nel
# mondo?", non "qual è il più vicino": nessuna nozione di origine/distanza qui, quindi nessuna
# delega a SpatialSelectionService.find_nearest (quel motore risolve sempre un CANDIDATO più vicino
# a una posizione, calcolo sprecato/concettualmente sbagliato per una semplice domanda di esistenza
# — un controllo diretto su world.buildings basta, stesso costo asintotico, zero dipendenze in più).
# Vive qui (non su GameScene) perché è lo stesso criterio (`rules.accepts_thoughts`) già incapsulato
# da find_best sopra — un solo posto per "cosa significa essere un edificio che accetta pensieri",
# non duplicato altrove. Pensata per essere chiamata sia dal tasto debug Y oggi (secondo prompt, non
# in questo) sia da una futura logica di generazione automatica della Task Daydream (pool), come
# gate PRIMA di assegnare l'intera Task — evita di far camminare/pensare un individuo per poi non
# trovare nessun edificio idoneo al momento del deposito (vedi la ricognizione dedicata).
static func has_thought_accepting_building(world: World) -> bool:
	if world == null:
		return false
	for building in world.buildings:
		if building.rules != null and building.rules.accepts_thoughts:
			return true
	return false
