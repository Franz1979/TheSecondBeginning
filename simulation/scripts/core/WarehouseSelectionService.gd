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
# haul_resource/transport). [Nota storica: la versione originale non filtrava su is_complete/
# is_demolished, coerente con RetrieveAction che preleva da QUALUNQUE building con stored_resources;
# con la generalizzazione sotto, i candidati devono invece essere completi e non demoliti.]
# GENERALIZZATA (2026-09-19, richiesta utente - assorbe la ricerca "magazzino con cibo", niente due
# ricerche quasi identiche): il vecchio `resource_name: String` diventa `criterion`, che accetta:
#   - un NOME di risorsa (String, es. "stick") - comportamento originale, servira' al futuro Produce;
#   - null o "" - QUALUNQUE risorsa;
#   - una CATEGORIA (SecondaryResourceTypes.Category, es. FOOD) - qualunque risorsa di quella
#     categoria (SecondaryResourceRules.category, via CaloricCalculator.get_caloric_source_rules).
# `min_quantity` (default 1, cioe' quantity > 0 come prima): quantita' minima di UNA singola risorsa
# che soddisfa il criterio - non la somma tra risorse diverse. Un edificio e' candidato se ne ha
# almeno una.
#
# Filtri sull'edificio: COMPLETO e NON demolito (aggiunti insieme alla generalizzazione; la versione
# originale non li aveva). Ritorna l'edificio piu' vicino o null, via SpatialSelectionService.
# find_nearest.
#
# `requesting_individual_id` (opzionale, default -1): serve SOLO al log diagnostico
# (DebugLogging.SHOW_FOOD_SOURCE_LOGS, spento di default) per stampare l'esito per l'individuo con l'id
# configurato; non influisce sulla ricerca.
static func find_source_for_retrieval(
	world: World,
	origin_position: Vector2,
	origin_macro_coords: Vector2i,
	criterion: Variant = null,
	excluded_building_ids: Array[int] = [],
	min_quantity: int = 1,
	requesting_individual_id: int = -1
) -> Building:
	if world == null:
		return null

	var has_stock := func(building: Building) -> bool:
		if not building.is_complete or building.is_demolished:
			return false
		return not WarehouseSelectionService._get_matching_stock(building, criterion, min_quantity).is_empty()

	var source := SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, has_stock, excluded_building_ids
	) as Building

	if DebugLogging.ENABLED and DebugLogging.SHOW_FOOD_SOURCE_LOGS \
			and requesting_individual_id == DebugLogging.FOOD_SOURCE_LOG_INDIVIDUAL_ID:
		if source == null:
			print("[FOOD SOURCE DEBUG] #%d origine=%s criterio=%s min=%d: nessun magazzino completo idoneo (esclusi=%s)." % [
				requesting_individual_id, str(origin_position), str(criterion), min_quantity, str(excluded_building_ids)
			])
		else:
			print("[FOOD SOURCE DEBUG] #%d origine=%s criterio=%s min=%d: trovato %s #%d in macro=(%d,%d) micro=(%d,%d), risorse=%s (esclusi=%s)." % [
				requesting_individual_id, str(origin_position), str(criterion), min_quantity, source.building_type_name,
				source.id, source.macro_x, source.macro_y, source.micro_x, source.micro_y,
				str(_get_matching_stock(source, criterion, min_quantity)), str(excluded_building_ids)
			])
	return source


# nome risorsa -> quantita' delle sole risorse di stored_resources di `building` che soddisfano
# `criterion` (vedi find_source_for_retrieval: nome, null/"" = qualunque, categoria) con quantity >=
# min_quantity (e comunque > 0). Vuoto = nessuna. Era l'helper del cibo, ora
# generalizzato.
static func _get_matching_stock(building: Building, criterion: Variant, min_quantity: int) -> Dictionary:
	var matching_stock: Dictionary = {}
	var minimum: int = maxi(min_quantity, 1)
	# stored_resources più il buffer di uscita della produzione (2026-09-23): stessa quantità che
	# BuildingStorageService.withdraw può prelevare.
	var candidate_names: Array = building.stored_resources.keys()
	for output_name in building.production_output.keys():
		if not candidate_names.has(output_name):
			candidate_names.append(output_name)
	for resource_name in candidate_names:
		var quantity: int = BuildingStorageService.get_available_quantity(building, String(resource_name))
		if quantity < minimum:
			continue
		if criterion == null or (criterion is String and criterion == ""):
			matching_stock[resource_name] = quantity
		elif criterion is String or criterion is StringName:
			if resource_name == String(criterion):
				matching_stock[resource_name] = quantity
		else:
			var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
			if rules != null and rules.category == int(criterion):
				matching_stock[resource_name] = quantity
	return matching_stock
