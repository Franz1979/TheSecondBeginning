class_name WarehouseSelectionService
extends RefCounted

# Sceglie il magazzino più vicino con posto per quantity_needed unità di resource_name (2026-09-09,
# richiesta utente — re-routing UnloadAction quando il magazzino bersaglio risulta pieno). Stateless,
# stesso pattern "fabbrica statica"/service già in uso da TerrainScatteredResourceService/
# BuildingStorageService: nessuna istanza, opera sempre sugli argomenti passati.
#
# DEVIAZIONE dalla firma letterale richiesta (segnalata, come da istruzioni): la richiesta originale
# era find_best(world, origin_position, resource_name, quantity_needed, excluded_building_ids). Un
# semplice Vector2 origin_position però è ambiguo per il confronto di distanza con edifici che
# possono trovarsi in una macrocella DIVERSA da quella dell'individuo — la stessa conversione
# cross-macrocella già in uso ovunque nel progetto (GameScene._try_assign_unload_command_on_right_
# click/_debug_test_daydream_task) richiede di sapere a quale macrocella origin_position è
# relativa. Aggiunto quindi un parametro origin_macro_coords: Vector2i (tipicamente
# individual.home_macro_coords, la stessa granularità già usata da quei due call site) — senza
# questo, un edificio nella macrocella dell'individuo e uno in una macrocella adiacente con la
# STESSA posizione micro apparirebbero alla stessa distanza, sbagliato.
#
# Filtro capacità: get_max_depositable(...) >= quantity_needed, NON solo "> 0" — coerenza con
# UnloadAction.activate() (vedi lì), che dichiara "pieno" un magazzino che non può accettare
# l'INTERA quantità trasportata, non uno che ne accetterebbe solo una parte. can_accept() non è
# richiamato separatamente: get_max_depositable ritorna comunque un valore >= 0 coerente anche per
# una categoria non accettata (vedi commento lì), quindi il confronto >= quantity_needed (con
# quantity_needed sempre > 0, controllato sotto) lo esclude già implicitamente in ogni caso pratico
# — un edificio con categoria non accettata non ha comunque slot dedicati a quella risorsa.
#
# building.is_complete NON filtrato qui (fuori dallo scope letterale della richiesta) — un edificio
# ancora in costruzione che risultasse comunque idoneo per errore è un caso preesistente/non
# introdotto da questo service, non affrontato qui.
#
# REFACTOR (2026-09-10, richiesta utente — generalizzazione a SpatialSelectionService): questa
# funzione non contiene più l'algoritmo "candidato più vicino ammissibile" — estratto in
# SpatialSelectionService.find_nearest (generico, non conosce Building) perché lo stesso identico
# algoritmo serve anche per futuri candidati non-Building (es. aree di lavoro). Questo service resta
# come thin wrapper: costruisce il predicate "capacità residua sufficiente" (l'unica logica
# specifica-magazzino rimasta) e delega la ricerca. Comportamento invariato: stesso ordine di filtri
# (esclusi prima del predicate), stesso criterio di tie-break (primo trovato a parità di distanza),
# stessa formula di distanza — tutto spostato in SpatialSelectionService senza modifiche. Firma e
# comportamento visibile di find_best invariati: nessun call site (HumanIndividualActionService.
# _handle_pending_warehouse_search) tocca.
static func find_best(
	world: World,
	origin_position: Vector2,
	origin_macro_coords: Vector2i,
	resource_name: String,
	quantity_needed: int,
	excluded_building_ids: Array[int] = []
) -> Building:
	if world == null or quantity_needed <= 0:
		return null

	var predicate := func(building: Building) -> bool:
		return BuildingStorageService.get_max_depositable(building, resource_name) >= quantity_needed

	return SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, predicate, excluded_building_ids
	) as Building
