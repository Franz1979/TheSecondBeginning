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
# building.is_complete — GAP CHIUSO (2026-09-11, richiesta utente): non filtrato ESPLICITAMENTE
# qui, ma `has_capacity` sotto chiama BuildingStorageService.get_max_depositable, che ora rifiuta
# (ritorna 0) qualunque building con is_complete=false — un cantiere non ancora finito risulta quindi
# già escluso da tutti e tre i tier per costruzione, senza bisogno di un controllo dedicato in questo
# file. Guard messo lì (non qui) perché get_max_depositable è il punto consultato anche da
# UnloadAction.activate (riverifica still_fits) e implicitamente da store() via can_accept — un solo
# punto copre ogni percorso di deposito, automatico o manuale, invece di ripetere il controllo in
# ognuno.
#
# REFACTOR (2026-09-10, richiesta utente — generalizzazione a SpatialSelectionService): questa
# funzione non contiene più l'algoritmo "candidato più vicino ammissibile" — estratto in
# SpatialSelectionService.find_nearest (generico, non conosce Building) perché lo stesso identico
# algoritmo serve anche per futuri candidati non-Building (es. aree di lavoro). Questo service resta
# come thin wrapper: costruisce il/i predicate di dominio e delega la ricerca a SpatialSelectionService,
# che NON acquisisce mai un concetto di priorità/tier (resta generico, riusato as-is anche da
# ThoughtTargetSelectionService, che non ha bisogno di alcuna priorità) — vedi PRIORITÀ PER CATEGORIA
# sotto per dove vive quella logica.
#
# PRIORITÀ PER CATEGORIA (2026-09-10, richiesta utente — "se ho una capanna più vicina di un deposito
# e c'è spazio in entrambi, oggi scarica in capanna perché più vicina": comportamento indesiderato
# quando esiste un edificio DEDICATO allo storage): find_best ora prova fino a TRE ricerche in
# sequenza, stesso `excluded_building_ids` per tutte e tre (un edificio escluso — es. re-routing su
# magazzino pieno — resta escluso ad ogni tier, mai riselezionato), ciascuna una chiamata separata a
# SpatialSelectionService.find_nearest (nessuna modifica lì, resta a singolo predicate/singolo tier):
#   Tier 1 — BuildingTypes.Category.STORAGE (es. deposit_site): il più vicino CON capacità residua
#            sufficiente. Se lo trova, è la risposta — anche se un edificio di un'altra categoria più
#            vicino avrebbe avuto posto.
#   Tier 2 — BuildingTypes.Category.RESIDENTIAL (es. hut): SOLO se il tier 1 non ha trovato nulla
#            (nessuno storage con posto). Stessa logica, categoria diversa.
#   Tier 3 — qualunque ALTRA categoria (oggi solo POLITICAL, es. stone_circle — che però non ha
#            storage_slot_count valorizzato, quindi in pratica non risulterà mai idoneo finché resta
#            così): SOLO se anche il tier 2 fallisce. STORAGE è esplicitamente escluso da questo
#            tier — se siamo arrivati qui, nessun edificio STORAGE aveva posto (già verificato al
#            tier 1 con lo stesso `excluded_building_ids`), quindi ripeterne la verifica sarebbe
#            ridondante, mai un edificio perso per questo. RESIDENTIAL non è escluso esplicitamente
#            (stesso motivo: già verificato al tier 2, non può più corrispondere qui) — la
#            combinazione dei tre tier copre quindi ESATTAMENTE lo stesso insieme di candidati di
#            un'unica ricerca senza filtro categoria, solo in un ordine di priorità diverso.
#
# Costo: fino a 3 passate O(N) su world.buildings invece di 1 — accettabile finché il numero di
# edifici resta piccolo (stesso principio già assunto altrove nel progetto, es.
# TaskPersistenceService._find_building_by_id). Un singolo passaggio O(N) con più "migliori correnti"
# tracciati in parallelo sarebbe più efficiente ma richiederebbe o inlineare l'algoritmo qui (perdendo
# la delega a SpatialSelectionService) o insegnare un concetto di priorità/tier al service generico
# (accoppiandolo a una logica di dominio che ThoughtTargetSelectionService non deve mai vedere) —
# scartato per lo stesso motivo per cui la priorità vive qui e non lì.
#
# Firma di find_best INVARIATA — nessun call site (HumanIndividualActionService.
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

	var has_capacity := func(building: Building) -> bool:
		return BuildingStorageService.get_max_depositable(building, resource_name) >= quantity_needed

	var storage_predicate := func(building: Building) -> bool:
		return building.rules != null and building.rules.category == BuildingTypes.Category.STORAGE and has_capacity.call(building)
	var candidate: Variant = SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, storage_predicate, excluded_building_ids
	)
	if candidate != null:
		return candidate as Building

	var residential_predicate := func(building: Building) -> bool:
		return building.rules != null and building.rules.category == BuildingTypes.Category.RESIDENTIAL and has_capacity.call(building)
	candidate = SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, residential_predicate, excluded_building_ids
	)
	if candidate != null:
		return candidate as Building

	var other_predicate := func(building: Building) -> bool:
		return building.rules != null and building.rules.category != BuildingTypes.Category.STORAGE and has_capacity.call(building)
	return SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, other_predicate, excluded_building_ids
	) as Building
