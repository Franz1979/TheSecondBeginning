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
# building.is_complete — RIAPERTO E RICHIUSO (2026-09-11 poi 2026-09-14, richiesta utente): la
# versione 2026-09-11 di questo commento dava per assodato che get_max_depositable rifiutasse
# QUALUNQUE building con is_complete=false, escludendo quindi i cantieri "gratis" — FALSO, e
# CONFERMATO BUG REALE con l'utente: da quando esiste un fabbisogno materiale di SetupSite
# (BuildingRules.setup_site_material_name/setup_site_material_per_cell), get_max_depositable per un
# edificio incompleto ritorna quanto materiale di CANTIERE gli manca ancora — un numero che può
# benissimo essere >= quantity_needed, facendo apparire un hut/stick_tent ancora in costruzione come
# se avesse "posto libero" da magazzino, quando in realtà sta solo segnalando il proprio fabbisogno
# di allestimento. Guard ESPLICITO ora in `has_capacity` sotto (`building.is_complete and ...`): un
# candidato di find_best deve essere DAVVERO finito, mai un cantiere — la consegna DELIBERATA di
# materiale a un cantiere resta possibile SOLO tramite un target scelto a mano dal player (comando
# Transport/Unload manuale in GameScene), mai tramite questa ricerca automatica.
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
#   Tier 3 — qualunque ALTRA categoria (oggi solo POLITICAL, es. pebble_circle — che però non ha
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

	# is_complete (2026-09-14, richiesta utente — bugfix "il re-routing finisce in un cantiere
	# incompleto che non è affatto un magazzino"): get_max_depositable, per un edificio NON completo,
	# ritorna quanto materiale di SETUP SITE gli manca ancora (vedi BuildingStorageService.gd) — un
	# numero che per COSTRUZIONE può risultare >= quantity_needed anche se quell'edificio non è mai
	# stato un vero magazzino, semplicemente perché il proprio fabbisogno di cantiere combacia per
	# caso con la quantità da ricollocare. find_best cerca SEMPRE una vera destinazione di deposito
	# generica (mai il fabbisogno specifico di un cantiere, che ha il proprio percorso dedicato via
	# consegna MANUALE — vedi GameScene, mai tramite questa ricerca automatica), quindi un candidato
	# deve essere COMPLETO prima ancora di guardare la capacità: uno storage/residenziale vero
	# accetta merce solo da completo (vedi BuildingStorageService.get_max_depositable, ramo
	# "edificio COMPLETO"), mai mentre è ancora un cantiere.
	var has_capacity := func(building: Building) -> bool:
		return building.is_complete and BuildingStorageService.get_max_depositable(building, resource_name) >= quantity_needed

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


# Sceglie il magazzino più vicino che ha ALMENO UNA unità di resource_name da CEDERE (2026-09-13,
# richiesta utente — Build Task collegata a un vero fabbisogno di materiale: un cantiere a corto di
# materiale deve trovare una SORGENTE da cui prelevare, operazione OPPOSTA a find_best sopra, che
# invece cerca una DESTINAZIONE con capacità residua per un deposito). Nessuna priorità per
# categoria (a differenza di find_best — STORAGE/RESIDENTIAL/altro): la richiesta non la prevede
# ("un magazzino sorgente con stick disponibili", nessuna gerarchia), quindi un'unica ricerca
# tramite SpatialSelectionService.find_nearest, stesso principio "thin wrapper" già seguito da
# find_best per il proprio algoritmo.
#
# Soglia ">0" (non ">= quantity_needed" come has_capacity sopra in find_best): RetrieveAction
# preleva già "quanto riesce" (min tra richiesta/capacità individuo/disponibilità, vedi
# RetrieveAction.activate) — un magazzino con SOLO 1 unità disponibile resta comunque un candidato
# valido (porterà solo 1 unità questo viaggio, il chiamante dovrà eventualmente generare un
# secondo viaggio per il resto, stesso principio "porta quello che riesci" già confermato per
# haul_resource/transport). Filtro categoria/is_complete/is_demolished DELIBERATAMENTE assente
# qui (a differenza di find_best, che passa da get_max_depositable — con tutti quei guard):
# RetrieveAction stessa non ha mai richiesto nulla del genere per il PRELIEVO (vedi la nota in
# testa a RetrieveAction.gd — "funziona su QUALUNQUE building con stored_resources, completo o in
# costruzione"), quindi questa ricerca resta coerente con quello che l'Action che la userà può
# davvero fare.
static func find_source_for_retrieval(
	world: World,
	origin_position: Vector2,
	origin_macro_coords: Vector2i,
	resource_name: String,
	excluded_building_ids: Array[int] = []
) -> Building:
	if world == null:
		return null

	var has_stock := func(building: Building) -> bool:
		var stored_entry: Dictionary = building.stored_resources.get(resource_name, {})
		return int(stored_entry.get("quantity", 0)) > 0

	return SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, has_stock, excluded_building_ids
	) as Building
