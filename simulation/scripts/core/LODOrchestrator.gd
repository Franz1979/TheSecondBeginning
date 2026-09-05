class_name LODOrchestrator
extends RefCounted

# Meccanismo di LOD a TRE livelli (esteso da due a tre il 2026-08-30, vedi note di progetto —
# LOD0). Livello 2 = popolazioni il cui territorio interseca la "zona a fuoco" (le celle vive di
# GameScene/MacroCellScene) — calcolo giornaliero pieno, invariato. Livello 1 = territorio non a
# fuoco ORA, ma con ALMENO una cella già scoperta in passato (MacroCellState.has_ever_been_
# discovered) — calcolo aggregato stagionale (AnimalConsumptionAggregateService/
# AnimalHungerMortalityAggregateService), invariato. Livello 0 (NUOVO) = territorio con NESSUNA
# cella mai scoperta — nessun calcolo affatto, né giornaliero né stagionale: seminata all'inizio
# partita e congelata lì finché il player non ci arriva davvero.
#
# DUE flag separati su MacroCellState, non uno (fix di un bug di "contagio" trovato in sessione):
# has_ever_been_discovered guida SOLO la classificazione qui sopra (una cella è "scoperta" solo se
# è stata DAVVERO viva almeno una volta — LEVEL_1 è quindi raggiungibile solo per retrocessione da
# LEVEL_2, mai perché il territorio si sovrappone per caso a quello di un'altra popolazione).
# vegetation_feeding_active (separato) governa SOLO se la vegetazione può crescere in una cella —
# marcato anche sull'intero territorio di un erbivoro LEVEL_2 (non solo la cella viva vera, vedi
# _mark_feeding_ground_if_herbivore sotto), mai consultato dalla classificazione: un territorio
# erbivoro esteso (es. aurochs, decine di celle) sblocca la vegetazione dove mangia davvero ogni
# giorno, senza far salire a LEVEL_1 nessun'altra popolazione che tocca quelle stesse celle.
#
# Stateless (RefCounted, .new() per uso), stesso pattern di ogni altro "*Service" in
# scripts/core/ — nessuna sottocartella dedicata: la struttura esistente è piatta, non ci sono
# precedenti di raggruppamento per categoria sotto scripts/core/.

enum Level { LEVEL_0, LEVEL_1, LEVEL_2 }


# Classifica ogni PopulationGroup di world in LEVEL_2/LEVEL_1/LEVEL_0 — vedi commento di testa al
# file per la regola esatta. Territory non espone oggi un metodo di intersezione dedicato (solo
# get_cell_count/contains/get_primary_cell/get_centroid, vedi Territory.gd) — i controlli minimi
# sotto (_territory_intersects_live_cells/_territory_has_any_discovered_cell) iterano
# occupied_macrocells senza aggiungere nulla a Territory stesso (lettura pura dall'esterno,
# nessuna modifica a un file esistente).
#
# live_cell_coords è un Dictionary[Vector2i, bool] delle SINGOLE celle vive, non un Rect2i che ne
# faccia il bounding box — deliberato (fix 2026-08-30): con celle vive potenzialmente molto
# distanti tra loro (edifici lontani dal player, vedi GameScene._activate_all_building_cells), un
# bounding box tratterebbe come "a fuoco" anche tutto lo spazio vuoto in mezzo, promuovendo a
# torto popolazioni che non toccano nessuna cella viva reale.
#
# SIDE EFFECT DELIBERATO (2026-08-30, non più puramente di lettura come prima dell'introduzione di
# LOD0): marca has_ever_been_discovered=true su OGNI cella in live_cell_coords, indipendentemente
# da quale popolazione (se ce n'è una) la tocca — è l'unico punto che riceve già live_cell_coords
# ad ogni ricalcolo (attivazione cella, cambio vicino, checkpoint), quindi il posto naturale per
# registrare la scoperta. Governa anche WorldTimeService per il congelamento vegetazione, non solo
# la classificazione qui sotto. Non tocca altrimenti alcuno stato di PopulationGroup/Territory.
# Ritorna un Dictionary sia per il log leggibile (vedi print_classification_log sotto) sia per il
# consumo programmatico (WorldTimeService):
#   "level_2_groups"/"level_1_groups"/"level_0_groups": Array[PopulationGroup]
#   "level_2_count_by_species"/"level_1_count_by_species"/"level_0_count_by_species": Dictionary[String, int]
#
# `season` (aggiunto 2026-09-05, richiesta utente): serve SOLO per il catch-up di
# secondary_resource_stock alla prima scoperta di una cella (vedi _catch_up_secondary_resource_
# stock sotto) — verificato con una partita nuova che senza questo lo stock restava a 0.0 fino al
# prossimo checkpoint stagionale, anche con vegetazione fruttifera vera già presente. Nessun altro
# uso della stagione in questa funzione.
func set_focus_region(world: World, live_cell_coords: Dictionary, season: GameTypes.Season) -> Dictionary:
	for coords in live_cell_coords:
		var state := world.get_cell_state_at(coords.x, coords.y)
		if state != null:
			if not state.has_ever_been_discovered:
				_catch_up_secondary_resource_stock(world, coords, state, season)
				if DebugLogging.ENABLED:
					_print_new_discovery_secondary_stock(coords, state)
			state.has_ever_been_discovered = true

	var level_2_groups: Array = []
	var level_1_groups: Array = []
	var level_0_groups: Array = []
	var level_2_count_by_species: Dictionary = {}
	var level_1_count_by_species: Dictionary = {}
	var level_0_count_by_species: Dictionary = {}

	for group in world.population_groups:
		if _territory_intersects_live_cells(group.territory, live_cell_coords):
			level_2_groups.append(group)
			level_2_count_by_species[group.species_name] = int(level_2_count_by_species.get(group.species_name, 0)) + 1
			_mark_feeding_ground_if_herbivore(world, group)
		elif _territory_has_any_discovered_cell(group.territory, world):
			level_1_groups.append(group)
			level_1_count_by_species[group.species_name] = int(level_1_count_by_species.get(group.species_name, 0)) + 1
		else:
			level_0_groups.append(group)
			level_0_count_by_species[group.species_name] = int(level_0_count_by_species.get(group.species_name, 0)) + 1

	return {
		"level_2_groups": level_2_groups,
		"level_1_groups": level_1_groups,
		"level_0_groups": level_0_groups,
		"level_2_count_by_species": level_2_count_by_species,
		"level_1_count_by_species": level_1_count_by_species,
		"level_0_count_by_species": level_0_count_by_species,
	}


# Catch-up alla PRIMA scoperta di una cella (richiesta utente, 2026-09-05 — vedi set_focus_region
# sopra per il perché): calcola subito, per le 4 fonti a stock persistente (CaloricCalculator.
# SECONDARY_SOURCES), un reset pieno alla stagione CORRENTE — stesso identico calcolo che
# update_secondary_resource_stock fa una volta l'anno a cycle_start_season, isolato in
# CaloricCalculator.seed_secondary_resource_stock_now per essere richiamabile anche qui, fuori dal
# normale ciclo stagionale. Nessuna modifica alla pianta stessa (TREE/SHRUB/BIRDS, che può restare
# congelata) — solo lo stock derivato si allinea subito.
static func _catch_up_secondary_resource_stock(world: World, coords: Vector2i, state: MacroCellState, season: GameTypes.Season) -> void:
	var cell := world.get_cell_at(coords.x, coords.y)
	if cell == null:
		return
	for source in CaloricCalculator.SECONDARY_SOURCES:
		var rules := CaloricCalculator.get_caloric_source_rules(source["resource_name"])
		if rules == null:
			continue
		CaloricCalculator.seed_secondary_resource_stock_now(rules, cell, state, source["primary_resource_type"], season)


# DIAGNOSTICO TEMPORANEO (vedi set_focus_region sopra) — stampa lo stock calorico REALE
# (MacroCellState.secondary_resource_stock, quello che mangiano gli animali) delle 4 fonti a
# stock persistente per la cella appena scoperta, a fianco della composizione VISIVA dei
# sottotipi (subtype_composition, quella che pilota i puntini-frutto disegnati da
# MicroCellRenderer) — le due cose sono indipendenti: un valore di composizione > 0 NON implica
# uno stock > 0, ed è proprio questo che vogliamo distinguere prima di decidere se serve un
# catch-up dedicato al momento della scoperta.
static func _print_new_discovery_secondary_stock(coords: Vector2i, state: MacroCellState) -> void:
	var stock_parts: Array[String] = []
	for source_name in ["berry", "acorn", "fruit", "eggs"]:
		stock_parts.append("%s=%.2f" % [source_name, state.get_secondary_resource_stock(source_name)])
	var composition_parts: Array[String] = []
	for entry in [
		{"label": "shrub.fruit_bearing", "type": GameTypes.WorldObjectType.SHRUB, "subtype": "fruit_bearing"},
		{"label": "tree.wild_fruit", "type": GameTypes.WorldObjectType.TREE, "subtype": "wild_fruit"},
		{"label": "tree.domesticable_fruit", "type": GameTypes.WorldObjectType.TREE, "subtype": "domesticable_fruit"},
	]:
		composition_parts.append("%s=%d" % [entry["label"], state.get_subtype_count(entry["type"], entry["subtype"])])
	print("[CELL DISCOVERED] (%d,%d) secondary_resource_stock (REALE, quello che mangiano gli animali): %s | subtype_composition (COSMETICO, solo disegno): %s" % [
		coords.x, coords.y, ", ".join(stock_parts), ", ".join(composition_parts)
	])


# LOD0: marca vegetation_feeding_active=true su TUTTE le celle del territorio di `group` — SOLO
# se `group` è un erbivoro (mai un predatore, vedi commento su MacroCellState.vegetation_feeding_
# active per il perché: la caccia non legge mai dedicated_space, un territorio predatore da
# centinaia di celle non ha bisogno di vegetazione attiva da nessuna parte). Chiamata quando
# `group` diventa LEVEL_2 (set_focus_region/register_new_group) — un erbivoro mangia OGNI GIORNO
# da TUTTO il proprio territorio (vedi AnimalConsumptionService._consume_group, che itera
# occupied_macrocells per intero, non solo la cella a fuoco), quindi l'intero territorio deve
# poter ricrescere, non solo la cella viva vera. DELIBERATAMENTE separato da has_ever_been_
# discovered (mai scritto qui): questo flag non deve MAI far salire un'altra popolazione a
# LEVEL_1 solo perché il suo territorio si sovrappone per caso a quello di un erbivoro attivo —
# vedi il commento in testa a has_ever_been_discovered per il bug di "contagio" scoperto in
# sessione. rules == null (specie non risolvibile) tratta prudenzialmente come "non erbivoro
# accertato" — non marca nulla, nessun rischio di marcare per errore.
static func _mark_feeding_ground_if_herbivore(world: World, group: PopulationGroup) -> void:
	if group.territory == null:
		return
	var rules := AnimalCalculator.get_animal_rules(group.species_name)
	if rules == null or rules is PredatorRules:
		return
	for coords in group.territory.occupied_macrocells:
		var state := world.get_cell_state_at(coords.x, coords.y)
		if state != null:
			state.vegetation_feeding_active = true


static func _territory_intersects_live_cells(territory: Territory, live_cell_coords: Dictionary) -> bool:
	if territory == null:
		return false
	for coords in territory.occupied_macrocells:
		if live_cell_coords.has(coords):
			return true
	return false


# LOD0: vero se ALMENO una cella del territorio ha MacroCellState.has_ever_been_discovered=true —
# usata solo quando _territory_intersects_live_cells sopra è già falso (il chiamante decide prima
# LEVEL_2, poi questo per LEVEL_1 vs LEVEL_0), mai in isolamento: un territorio può benissimo
# essere "a fuoco ora" la prima volta che una sua cella diventa viva, nel qual caso LEVEL_2 vince
# comunque (has_ever_been_discovered viene marcato PRIMA di questo loop, nello stesso
# set_focus_region, quindi la cella risulterebbe comunque "scoperta" — ma l'ordine dei due
# controlli nel chiamante resta quello corretto per la semantica voluta, non per questo dettaglio).
static func _territory_has_any_discovered_cell(territory: Territory, world: World) -> bool:
	if territory == null:
		return false
	for coords in territory.occupied_macrocells:
		var state := world.get_cell_state_at(coords.x, coords.y)
		if state != null and state.has_ever_been_discovered:
			return true
	return false


# LOD0: vero se QUESTA macrocella va saltata dal checkpoint stagionale vegetazione (crescita/
# encroachment/mortalità/maturazione età) — usata da ResourceGrowthService/
# ResourceEncroachmentService/ResourceMortalityService/ResourceAgeBandService, un solo punto di
# verità invece di duplicare la stessa condizione in 4 file. MAI in "vista mondo"
# (world.lod_focus_state vuoto = nessun filtro, stesso sentinel già usato lato fauna in
# WorldTimeService._get_daily_herbivore_processing_groups — WorldScene continua a vedere tutto a
# piena velocità, invariato): il congelamento vale solo dentro una sessione GameScene/
# MacroCellScene con un focus attivo, e solo per macrocelle mai scoperte lì.
static func is_vegetation_frozen(world: World, state: MacroCellState) -> bool:
	if world.lod_focus_state.is_empty():
		return false
	return not (state.has_ever_been_discovered or state.vegetation_feeding_active)


# Insieme (Dictionary[Vector2i, bool], stesso idioma di live_cell_coords) di TUTTE le celle
# occupate dal territorio di una popolazione ERBIVORA (mai predatore — la caccia non legge mai
# secondary_resource_stock/dedicated_space(GRASS), vedi AnimalConsumptionService: "i predatori non
# consumano vegetazione") Livello 1 O Livello 2, cioè ogni cella dove una consumazione REALE può
# ancora avvenire (giornaliera per Livello 2, aggregata stagionale per Livello 1) anche se la
# cella stessa non è mai stata scoperta individualmente. Usata da WorldTimeService per due scopi
# indipendenti (richiesta utente, 2026-09-05): esentare queste celle dal salto del checkpoint
# frutta (secondary_resource_stock, per non congelare per sempre lo stock di popolazioni Livello 1
# multicella) e catturare/ripristinare grass_seed_baseline (per non far sparire il grass per
# sempre in celle congelate dove si consuma davvero). No-op (Dictionary vuoto) se
# world.lod_focus_state è vuoto (vista mondo, nessun focus attivo) — stesso sentinel di
# is_vegetation_frozen sopra.
static func get_active_herbivore_territory_cells(world: World) -> Dictionary:
	var cells: Dictionary = {}
	if world.lod_focus_state.is_empty():
		return cells
	for group in world.lod_focus_state["level_1_groups"] + world.lod_focus_state["level_2_groups"]:
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or rules is PredatorRules or group.territory == null:
			continue
		for coords in group.territory.occupied_macrocells:
			cells[coords] = true
	return cells


# LOD0, lato fauna: vero se QUESTO gruppo va saltato da OGNI checkpoint animale (nascite/morte per
# vecchiaia/maturazione fasce età/dinamiche territoriali — vedi AnimalBirthService/
# AnimalOldAgeMortalityService/AnimalAgeBandService/TerritoryDynamicsService.update_territories_
# and_mitigation) — stesso principio di is_vegetation_frozen sopra (mai in vista mondo), ma per
# popolazione invece che per macrocella: NESSUNA cella del territorio del gruppo è mai stata
# scoperta. Un gruppo LEVEL_2 la cui cella è appena diventata viva risulta comunque "scoperta" qui
# (set_focus_region marca has_ever_been_discovered PRIMA di classificare, nello stesso passaggio)
# — mai congelato per errore un gruppo a fuoco proprio ora. Deliberatamente NON usato dal consumo/
# fame giornalieri (quelli restano guidati da world.lod_focus_state["level_1_groups"]/
# WorldTimeService._get_daily_herbivore_processing_groups, che già escludono LEVEL_0 una volta che
# set_focus_region produce 3 livelli) né dalla predazione (mai filtrata da LOD, per decisione
# esplicita — vedi PredationService).
static func is_animal_frozen(world: World, group: PopulationGroup) -> bool:
	if world.lod_focus_state.is_empty():
		return false
	return not _territory_has_any_discovered_cell(group.territory, world)


# Registra UN SINGOLO gruppo appena creato (es. da uno split dentro TerritoryDynamicsService.
# process_daily_stagger, il percorso GIORNALIERO che _run_lod_focus_refresh_checkpoint non copre
# finché non arriva il prossimo checkpoint stagionale — vedi la discussione sul perché i nuovi
# gruppi da spalmamento finivano trattati come Livello 2 per tutta la stagione) dentro
# world.lod_focus_state, SENZA riclassificare tutto il mondo da zero (quello resta il compito di
# set_focus_region, deliberatamente più raro/costoso). No-op se nessun focus è attivo
# (world.lod_focus_state vuoto = vista mondo). Riusa le STESSE identiche regole geografiche di
# set_focus_region (_territory_intersects_live_cells/_territory_has_any_discovered_cell) — mai una
# seconda definizione di cosa significhi ciascun livello. Un nuovo gruppo nato da split appartiene
# per costruzione a un genitore Livello 1 o 2 (mai Livello 0, che non viene mai processato — nessun
# split può originare lì): il ramo LEVEL_0 sotto è comunque scritto per simmetria/difensivo, non
# perché ci si aspetti di prenderlo davvero.
static func register_new_group(world: World, group: PopulationGroup) -> void:
	if world.lod_focus_state.is_empty():
		return
	if _territory_intersects_live_cells(group.territory, world.lod_focus_live_cells):
		world.lod_focus_state["level_2_groups"].append(group)
		var counts: Dictionary = world.lod_focus_state["level_2_count_by_species"]
		counts[group.species_name] = int(counts.get(group.species_name, 0)) + 1
		_mark_feeding_ground_if_herbivore(world, group)
	elif _territory_has_any_discovered_cell(group.territory, world):
		world.lod_focus_state["level_1_groups"].append(group)
		var counts: Dictionary = world.lod_focus_state["level_1_count_by_species"]
		counts[group.species_name] = int(counts.get(group.species_name, 0)) + 1
	else:
		world.lod_focus_state["level_0_groups"].append(group)
		var counts: Dictionary = world.lod_focus_state["level_0_count_by_species"]
		counts[group.species_name] = int(counts.get(group.species_name, 0)) + 1


# Log leggibile del risultato di set_focus_region, riusabile da ogni futuro punto di invocazione
# (oggi MacroCellScene._ready/GameScene._refresh_lod_focus_region) senza duplicare il formato di
# stampa. Statica: non ha bisogno di stato dell'istanza, solo del Dictionary già calcolato.
static func print_classification_log(result: Dictionary) -> void:
	if not DebugLogging.SHOW_LOD_CLASSIFICATION_LOGS:
		return
	var level_2_groups: Array = result["level_2_groups"]
	var level_1_groups: Array = result["level_1_groups"]
	var level_0_groups: Array = result.get("level_0_groups", [])
	var total: int = level_2_groups.size() + level_1_groups.size() + level_0_groups.size()

	print("[LOD] Popolazioni totali: %d" % total)
	# "N" qui è un conteggio di GRUPPI (PopulationGroup), non di individui — un gruppo "rabbit: 1"
	# può comunque contenere decine di conigli (group.population), vedi il dettaglio per-gruppo
	# sotto. level_2_count_by_species è già una SOMMA per specie (set_focus_region incrementa lo
	# stesso contatore per ogni gruppo classificato LEVEL_2, mai un overwrite) — se compare più di
	# un gruppo della stessa specie a fuoco, il numero qui cresce di conseguenza, non resta fermo a
	# 1: NON è quindi possibile che questo conteggio nasconda gruppi "ripetuti ma non sommati". Se
	# vedi lo stesso blocco identico due volte di fila nel log, è perché print_classification_log è
	# stata richiamata due volte per due eventi distinti nello stesso frame (es. sia da _ready() sia
	# da un cambio di vicino attivo, vedi GameScene._refresh_lod_focus_region) — non un doppio conteggio.
	print("[LOD] LEVEL_2 (a fuoco, calcolo giornaliero invariato): %d gruppi" % level_2_groups.size())
	var level_2_by_species: Dictionary = result["level_2_count_by_species"]
	var level_2_species_names: Array = level_2_by_species.keys()
	level_2_species_names.sort()
	for species_name in level_2_species_names:
		print("  - %s: %d gruppi" % [species_name, level_2_by_species[species_name]])

	# Dettaglio per-gruppo (solo LEVEL_2, mai LEVEL_1/LEVEL_0: lì i gruppi sono migliaia, elencarli
	# singolarmente sommergerebbe il log) — INTERO territorio (tutte le occupied_macrocells), non
	# solo la cella primaria: un gruppo multi-cella (es. deer, min_territory_cells=3) può finire
	# LEVEL_2 perché una QUALSIASI delle sue celle tocca il set vivo (_territory_intersects_live_
	# cells, vedi sopra — non solo se la cella primaria coincide), quindi mostrare solo get_primary_
	# cell() qui potrebbe far sembrare "lontano" un gruppo che in realtà è a fuoco per via di
	# un'altra sua cella. Con l'intero elenco si vede sempre DAVVERO perché è stato classificato così.
	if not level_2_groups.is_empty():
		print("[LOD] Dettaglio gruppi LEVEL_2 (id specie: intero territorio, popolazione):")
		for group in level_2_groups:
			var cells: Array = []
			for coords in group.territory.occupied_macrocells:
				cells.append(str(coords))
			print("  - #%d %s: [%s], pop=%d" % [
				group.id, group.species_name, ", ".join(cells), group.population
			])

	print("[LOD] LEVEL_1 (scoperta, fuori fuoco ora — calcolo aggregato stagionale): %d" % level_1_groups.size())
	var level_1_by_species: Dictionary = result["level_1_count_by_species"]
	var level_1_species_names: Array = level_1_by_species.keys()
	level_1_species_names.sort()
	for species_name in level_1_species_names:
		print("  - %s: %d" % [species_name, level_1_by_species[species_name]])

	# LEVEL_0 (nuovo, 2026-08-30): mai scoperta, congelata — nessun calcolo, né giornaliero né
	# stagionale. Stesso formato riassuntivo di LEVEL_1 sopra, mai un elenco per-gruppo (potenziale
	# maggioranza schiacciante delle popolazioni del mondo).
	var level_0_by_species: Dictionary = result.get("level_0_count_by_species", {})
	print("[LOD] LEVEL_0 (mai scoperta, congelata — nessun calcolo): %d" % level_0_groups.size())
	var level_0_species_names: Array = level_0_by_species.keys()
	level_0_species_names.sort()
	for species_name in level_0_species_names:
		print("  - %s: %d" % [species_name, level_0_by_species[species_name]])

	# Nota informativa (solo quando pertinente, per non appesantire il log nel caso comune senza
	# predatori fuori fuoco): la classificazione qui sopra è puramente geografica, identica per
	# ogni specie — nessuna eccezione per i predatori nella classificazione stessa (vedi
	# set_focus_region), ma con LOD0 i predatori SONO effettivamente congelati come tutto il resto
	# quando LEVEL_0 (decisione esplicita, diversa dal trattamento LEVEL_1 dove restano sempre
	# giornalieri — vedi WorldTimeService/PredationService per l'implementazione esatta).
	var has_predator_in_level_1 := false
	for group in level_1_groups:
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules is PredatorRules:
			has_predator_in_level_1 = true
			break
	if has_predator_in_level_1:
		print(
			"[LOD] Nota: i predatori elencati sopra in LEVEL_1 restano comunque processati "
			+ "giornalmente da PredationService indipendentemente dal livello mostrato "
			+ "(la predazione non è filtrata da LEVEL_1/LEVEL_2, ma un predatore LEVEL_0 è "
			+ "congelato come qualunque altra popolazione)."
		)
