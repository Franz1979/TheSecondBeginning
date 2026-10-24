class_name GameSimulation
extends RefCounted

# Driver del tempo della simulazione del villaggio (2026-10-17, refactoring GameScene blocco 3 — docs/design/
# gamescene_refactoring.md): l'ordine dei passi di logica del giro "al secondo" e del giro giornaliero, in un punto solo e
# senza nodi. La scena (oggi GameScene 2D, domani quella 3D) gli passa il contesto, il momento di gioco e un GameEffects, poi
# esegue gli effetti. Statico e senza stato: lo stato dei passi vive in GameData (e nei suoi *_runtime).
#
# Dal blocco 5e (2026-10-18) qui anche il riallineamento giornaliero della produzione, i cantieri maturati e il giro annuale.
#
# Blocco 5a (2026-10-18): la simulazione diventa anche un'ISTANZA che possiede la popolazione (individui e Folk) e i
# servizi che la fanno vivere (movimento, azioni, tempo). La scena la crea, le passa dati della partita, mondo e celle
# vive per riferimento, e legge da lei individui e Folk. tick_second / tick_day restano statici e ricevono context().
# L'array degli individui non va MAI riassegnato dopo setup_population: lo stesso oggetto lo tengono GameSettings,
# GameTimeService, CoordinatorService e i contesti.

var game_data: GameData
var world: World
var individuals: Array[HumanIndividual] = []
var folk: Folk
# Macrocelle vive (Vector2i -> LiveMacroCell): lo stesso dizionario della scena, per riferimento (path_grid e macro_state
# servono alla simulazione).
var live_cells: Dictionary = {}
# Un solo servizio di movimento e uno di azioni per tutti gli individui (lo stato per individuo vive sulle Task).
var movement_service := HumanIndividualMovementService.new()
var action_service := HumanIndividualActionService.new()
# Nascite, morti e ricalcoli giornalieri/annuali agganciati all'orologio (start_time).
var time_service: GameTimeService


# Contesto per i servizi: solo riferimenti, nessuna copia.
func context() -> GameContext:
	var ctx := GameContext.new()
	ctx.game_data = game_data
	ctx.world = world
	ctx.individuals = individuals
	ctx.folk = folk
	ctx.live_cells = live_cells
	return ctx


# Popolazione all'ingresso in scena (prima in GameScene._ready). true = popolo già esistente riusato (salvataggio appena
# caricato o ritorno da WorldScene/MacroCellScene: GameSettings.active_human_individuals non vuoto, stessi oggetti, mai
# una copia); false = partita nuova, popolo seminato in `start_macro_coords`.
#
# set_current_era in ENTRAMBI i rami (fix di persistenza del 2026-09-12): le durate per età dell'Era si ricalcolano sempre
# da HumanRules/EraRules invece di fidarsi del JSON, che può essere stato scritto prima di un cambio delle fasce d'età.
# human_rules_ref non è mai salvato né propagato col popolo: va riassegnato a ogni ricostruzione.
func setup_population(human_rules: HumanRules, start_macro_coords: Vector2i) -> bool:
	game_data.set_current_era(game_data.current_era_name, human_rules)
	if not GameSettings.active_human_individuals.is_empty():
		folk = GameSettings.active_human_folk
		individuals = GameSettings.active_human_individuals
		folk.human_rules_ref = human_rules
		return true
	var seeding_result := HumanSeedingService.new().seed_player_start(
		start_macro_coords, game_data.starting_group_size_preference, human_rules,
		game_data.starting_folk_name if game_data.starting_folk_name != "" else Folk.pick_random_name(), game_data.year,
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female, game_data
	)
	folk = seeding_result.folk
	individuals = seeding_result.individuals
	# Pubblicati subito (2026-10-01): i servizi statici li leggono da GameSettings fin dalla prima sessione.
	publish_to_settings()
	# Tutto il gruppo nasce nella macrocella di partenza (posizioni già assolute, centrate da HumanSeedingService).
	for member in individuals:
		member.home_macro_coords = start_macro_coords
	# Istantanee dell'anno 0 (l'anno di partenza non "rotola" mai, quindi GameTimeService non le scriverebbe): popolazione
	# dei fondatori ed edifici (sempre 0 a inizio partita).
	game_data.population_snapshots[0] = individuals.size()
	game_data.building_snapshots[0] = 0
	return false


# Individuo seguito al ripristino: lo stesso che lo era all'uscita o al salvataggio (game_data.player_individual_id); il
# primo se non si trova (rete di sicurezza per dati incoerenti).
func find_focus_individual() -> HumanIndividual:
	for member in individuals:
		if member.id == game_data.player_individual_id:
			return member
	return individuals[0] if not individuals.is_empty() else null


# Messa a punto della popolazione appena pronta (prima in GameScene._ready, dopo la semina o il ripristino):
#   - villaggi: centri completi senza villaggio collegati in silenzio (idempotente);
#   - stamina, capacità di trasporto e parametri vitali ricalcolati subito: HumanIndividual._init gira prima che folk_ref
#     sia assegnato (sia nella semina sia nel caricamento), quindi resterebbero ai valori di riserva fino al primo giorno;
#   - task "zombie" di salvataggi vecchi ripulite (current_task o coda già concluse), poi chi è libero riceve subito
#     bisogno / coda / attività idle (resolve_idle_individual presume un individuo libero: chi ha una task non si tocca).
func initialize_population() -> void:
	VillageService.sync_with_existing_centers(folk, world, individuals)
	var era_rules := EraCalculator.get_era_rules(game_data.current_era_name)
	for member in individuals:
		HumanStaminaIndividualService.recalculate_max_stamina(member, game_data, era_rules)
		HumanCarryCapacityIndividualService.recalculate_max_carry_capacity(member, game_data)
		HumanVitalsIndividualService.recalculate_vitals(member, game_data)
		TaskQueueService.purge_finished_tasks(member)
		HumanIndividualActionService.recover_zombie_current_task(member)
		if member.current_task == null:
			HumanIndividualActionService.resolve_idle_individual(member, GameContext.age_band_for(member, game_data), world)


# Pubblica popolo e individui in GameSettings, dove li leggono i servizi statici e le altre scene (stessi oggetti).
func publish_to_settings() -> void:
	GameSettings.active_human_folk = folk
	GameSettings.active_human_individuals = individuals


# Giro per fotogramma (2026-10-18, blocco 5b — prima in GameScene._process). `real_delta` in secondi reali, `game_delta`
# in frazione di giorno (0 in pausa); `focus` = individuo seguito dalla telecamera. Ordine:
#   1. orologio della lista dei lavori (secondi reali, solo a gioco in corso);
#   2. per ogni individuo con una Task attiva: movimento PRIMA delle azioni (WalkAction misura la distanza dalla posizione
#      già aggiornata), poi passaggio di macrocella, poi figlio al seguito (segue la madre nello stesso fotogramma). Il
#      filtro sulla Task attiva è solo un'ottimizzazione (apply_action è già un no-op senza Task). Gira a ogni fotogramma:
#      con popolazioni molto più grandi andrà rivalutato;
#   3. gruppi di visitatori (camminano da soli, non sono nella popolazione; quelli usciti dalla mappa spariscono);
#   4. corpi in spalla: posati se la Task che li porta non è più quella in corso;
#   5. cortei funebri.
# I collegamenti dei segnali degli step li fa la scena prima di chiamare (GameScene._ensure_step_signals).
func tick_frame(real_delta: float, game_delta: float, is_playing: bool, focus: HumanIndividual, effects: GameEffects) -> void:
	if is_playing and game_data != null:
		JobBoardService.advance_clock(game_data, real_delta)
	var active_individuals: Array[HumanIndividual] = []
	for member in individuals:
		if member.current_task != null and not member.current_task.is_finished():
			active_individuals.append(member)
	for member in active_individuals:
		movement_service.advance_movement(member, game_delta, live_cells)
		action_service.apply_action(member, game_delta, world, game_data)
		IndividualBorderService.check_crossing(member, world, game_data, action_service, focus, effects)
		IndividualBorderService.sync_dependent_child(member, individuals, game_data, effects)
	if game_data != null and not game_data.visitor_parties.is_empty():
		var departed: Array[VisitorParty] = []
		for party in game_data.visitor_parties:
			if VisitorService.advance(party, game_delta):
				departed.append(party)
		for party in departed:
			game_data.visitor_parties.erase(party)
	for member in individuals:
		if member.carried_body_id != -1:
			BodyBurialService.enforce_carrier(member)
	ProcessionService.tick(game_delta)


# Accoglienza di un gruppo di visitatori (2026-10-18, blocco 5c — prima GameScene._welcome_visitor_party): i membri
# diventano HumanIndividual veri del Folk, con lo stesso percorso delle nascite (casa, vista) e stamina piena; provviste
# e riserva si riempiono al primo ricalcolo della capacità, come per ogni individuo appena creato. Entrano nel villaggio
# del centro che li ha attirati, che guadagna valore politico per ogni adulto. Chi porta una dote va prima a depositarla
# (_give_visitor_dowry), gli altri passano subito dall'idle. Effetti: viste (individual_added, nello stesso ordine),
# collegamento della task della dote, pannello della popolazione.
func welcome_visitor_party(party: VisitorParty, effects: GameEffects) -> void:
	var used_names: Array[String] = []
	for member in individuals:
		used_names.append(member.name)
	var center := VisitorService.find_village_center(world)
	var village := VillageService.find_village_by_center(folk, center.id if center != null else -1)
	var newcomers := VisitorService.materialize_members(party, game_data, folk, village, used_names)
	var era_rules := EraCalculator.get_era_rules(game_data.current_era_name)
	for newcomer in newcomers:
		HumanStaminaIndividualService.recalculate_max_stamina(newcomer, game_data, era_rules, world)
		HumanCarryCapacityIndividualService.recalculate_max_carry_capacity(newcomer, game_data)
		HumanVitalsIndividualService.recalculate_vitals(newcomer, game_data)
		newcomer.current_stamina = newcomer.max_stamina
		individuals.append(newcomer)
	game_data.visitor_parties.erase(party)
	var adult_count := 0
	for newcomer in newcomers:
		if GameContext.age_band_for(newcomer, game_data) >= HumanTypes.AgeBand.FERTILE_ADULT:
			adult_count += 1
	VillageInfluenceService.add_accepted_adults(folk, village, adult_count)
	AssignHouseService.assign_pending_residents(world, individuals, game_data.year)
	# newcomers è nello stesso ordine di party.members (VisitorService.materialize_members): l'indice serve alla dote.
	for i in range(newcomers.size()):
		var newcomer := newcomers[i]
		effects.individual_added(newcomer)
		if not _give_visitor_dowry(party, i, newcomer, effects):
			HumanIndividualActionService.resolve_idle_individual(newcomer, GameContext.age_band_for(newcomer, game_data), world)
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	if DebugLogging.ENABLED:
		var labels := PackedStringArray()
		for newcomer in newcomers:
			labels.append("#%d %s" % [newcomer.id, newcomer.name])
		print("[VISITORS] Gruppo #%d accolto: %s entrano nel villaggio." % [party.id, ", ".join(labels)])


# Dote del nuovo arrivato (VisitorPartyRules del tipo di gruppo, es. ghiande per i migranti adulti): zaino riempito in
# proporzione alla capacità di trasporto, deposito al magazzino come prima attività. true = task di deposito assegnata (il
# chiamante NON risolve l'idle).
#
# La task si assegna PRIMA di riempire lo zaino: assign_task, per chi non ha una task in corso, scarta a terra il carico,
# e con lo zaino ancora vuoto non c'è nulla da scartare (l'UnloadAction legge lo zaino solo all'arrivo). Per lo stesso
# motivo non si passa dall'idle con lo zaino pieno. La task è sospendibile: un bisogno la mette in coda con il carico.
# Senza un magazzino che accetti la dote, la dote si dà lo stesso e si torna all'idle: il carico finirà a terra come
# mucchio raccoglibile.
func _give_visitor_dowry(party: VisitorParty, member_index: int, newcomer: HumanIndividual, effects: GameEffects) -> bool:
	var dowry := VisitorService.get_member_dowry(party, member_index, newcomer)
	var resource_name: String = dowry["resource_name"]
	var quantity: int = dowry["quantity"]
	if quantity <= 0:
		return false
	# Prima un magazzino con posto per tutta la dote; altrimenti uno che ne accetti almeno un'unità (il residuo lo
	# ricolloca UnloadAction.on_complete con il re-routing già esistente).
	var warehouse := WarehouseSelectionService.find_best(
		world, newcomer.position, newcomer.home_macro_coords, resource_name, quantity, [],
		PathfindingService.reachability_for(newcomer)
	)
	if warehouse == null:
		warehouse = WarehouseSelectionService.find_best(
			world, newcomer.position, newcomer.home_macro_coords, resource_name, 1, [],
			PathfindingService.reachability_for(newcomer)
		)
	var assigned := false
	if warehouse != null:
		var task := TaskBuilderService.build_unload_resource_task(newcomer, warehouse)
		if task != null:
			assigned = newcomer.assign_task(task, GameContext.age_band_for(newcomer, game_data))
			# Il primo passo è la camminata verso il magazzino: i segnali dell'UnloadAction si collegano dagli effetti, nello
			# stesso fotogramma, prima che lo scarico si attivi.
			effects.wire_unload_task(task, newcomer)
	var added := newcomer.add_carried_resource(resource_name, quantity)
	if DebugLogging.ENABLED:
		print("[VISITORS] Dote di #%d %s: %d %s nello zaino, %s." % [
			newcomer.id, newcomer.name, added, resource_name,
			("deposito accodato al magazzino #%d" % warehouse.id) if assigned else "nessun magazzino disponibile (finirà a terra)"
		])
	return assigned


# Aggancia nascite, morti e ricalcoli all'orologio (GameTimeService, stessi array per riferimento). La scena collega i
# suoi segnali al servizio restituito; il suo day_advanced va collegato PRIMA di chiamare questa funzione, così il giro
# giornaliero della scena precede morti e nascite come sempre.
func start_time(clock: GameClockController) -> GameTimeService:
	time_service = GameTimeService.new()
	time_service.connect_to_clock(clock, game_data, individuals, folk, world, action_service)
	return time_service


# Giro "al secondo" (prima dentro GameScene._refresh_pending_entries, stesso ordine): gira ogni secondo reale e a ogni altro
# ricalcolo di "In sospeso". `now`: momento di gioco in giorni (con la frazione del giorno in corso).
static func tick_second(ctx: GameContext, now: float, effects: GameEffects) -> void:
	if ctx.game_data == null or ctx.world == null:
		return
	# Ordini di zona del cassetto (2026-10-09): quelli presi che nessuno porta più tornano in coda (o spariscono a serie
	# finita) prima di raccogliere i lavori.
	DrawerOrderService.settle_zone_orders(ctx)
	# Edifici entrati o usciti dallo stato "Danneggiato" (2026-10-10): mappa del movimento della loro cella aggiornata.
	BuildingMaintenanceService.sync_damaged_buildings(ctx.world, ctx.game_data, effects)
	# Riparazioni richieste (2026-10-10): quelle non più valide si chiudono, poi quelle automatiche sotto soglia.
	BuildingMaintenanceService.settle_repair_requests(ctx.world)
	BuildingMaintenanceService.auto_request_repairs(ctx.world, ctx.game_data, ctx.folk, ctx.individuals)
	# Cantieri nel bosco (2026-10-18): taglio finito -> cantiere normale, nasce il lavoro di costruzione.
	if not BuildingMaintenanceService.finish_site_cuts(ctx.world).is_empty():
		effects.refresh_pending()
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	# Raggio di disagio delle Fosse (2026-10-18): cambia col riempimento, copertura delle case aggiornata.
	WasteDisposalService.sync_discomfort_radii(ctx.world, ctx.game_data)
	# Detriti posati a terra (2026-10-18): diventano macerie da sgomberare.
	BuildingLifecycleService.settle_ground_debris(ctx, effects)
	# Macerie svuotate dallo sgombero (2026-10-18): tolte, la cella torna libera.
	for building in BuildingMaintenanceService.emptied_rubble(ctx.world):
		BuildingLifecycleService.demolish(ctx, building, effects)
	# Fosse svuotate (2026-10-18): restano vuote e chiuse ai rifiuti.
	if not BuildingMaintenanceService.finish_emptied_pits(ctx.world).is_empty():
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	# Sgombero automatico delle macerie (2026-10-10): segnate come col clic su "Sgombera".
	for building in BuildingMaintenanceService.rubble_to_clear(ctx.world, ctx.game_data, ctx.folk):
		if not BuildingLifecycleService.mark_for_demolition(ctx.world, building, effects):
			continue
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] Sgombero richiesto in automatico per le macerie #%d (crollo di %s): in coda come demolish:%d." % [
				building.id, building.get_rubble_source_display_name(), building.id
			])
	# Attrezzi presi in deposito per un lavoro (2026-10-11): la restituzione avviene appena libero (2026-10-24,
	# ToolFetchService.try_return_borrowed_tools in resolve_idle_individual); qui solo la pulizia dei prestiti.
	ToolFetchService.prune_borrowed_tools(ctx)
	# Fumo degli affumicatoi (2026-10-23): ridisegno solo delle celle il cui affumicatoio ha iniziato o smesso di lavorare.
	for building in ProductionService.refresh_smoking(ctx.world, ctx.individuals):
		effects.refresh_building_cell(building)
	# Chi aspetta un attrezzo per produrre (2026-10-23): riprova a prenderlo in deposito.
	for created in ToolFetchService.retry_waiting_fetches(ctx):
		effects.wire_storage_task(created["task"], created["member"])
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	# Coordinatori ai punti di assegnazione (2026-10-09, CoordinatorService). Con la sola idea, anche senza punti
	# (2026-10-10): così, quando l'ultimo punto sparisce, chi va al punto o è in fila smette e il turno del coordinatore
	# finisce.
	# La funzione dell'età la memorizza CoordinatorService: statica, legata alla partita (mai a questo contesto temporaneo).
	if JobBoardService.is_idea_completed(ctx.folk):
		CoordinatorService.tick(ctx.game_data, ctx.world, ctx.individuals, now, GameContext.age_band_for.bind(ctx.game_data))


# Giro giornaliero (prima in GameScene._on_day_advanced, stesso ordine), dopo il calo giornaliero dell'Integrità
# (WorldTimeService, già girato).
static func tick_day(ctx: GameContext, effects: GameEffects) -> void:
	# Rifiuti del villaggio (2026-10-18): ogni 30 giorni, nelle Fosse o accanto al centro del villaggio.
	BuildingLifecycleService.produce_village_waste(ctx, effects)
	# Crollo a Integrità zero (2026-10-10).
	BuildingLifecycleService.collapse_ruined_buildings(ctx, effects)
	# Case danneggiate (2026-10-10, effetti passo 5): sfratto di chi è in più, poi riassegnazione.
	BuildingLifecycleService.evict_damaged_house_overflow(ctx, effects)
	# Pezzi dovuti degli ordini di produzione riallineati alle Task vive (2026-10-18, blocco 5e — prima in scena dopo tick_day).
	JobWorkScanService.reconcile_all_production_units(ctx.world, ctx.individuals)
	# Cantieri che hanno raggiunto i giorni minimi di costruzione (2026-10-18, blocco 5e): completati, poi la scena esegue
	# il percorso del completamento (effetto building_completed).
	for matured_building in BuildingLifecycleService.complete_matured_constructions(ctx.world):
		effects.building_completed(matured_building)


# Giro annuale (2026-10-18, blocco 5e — prima in GameScene._on_year_rolled_over), al cambio d'anno dell'orologio:
#   - valori assoluti R/C/P dei villaggi (+ somma dei raggi effettivi di questo momento, regola 1 del 2026-10-12);
#   - storia di quei valori per la scheda Influenza delle statistiche: un punto per villaggio, tipo e anno;
#   - istantanea degli edifici dell'anno (scheda Statistiche/Edifici, GameData.building_snapshots): solo completi, senza
#     macerie né edifici di movimento (stesso criterio di "Edifici totali" in StatisticsPanel); la stessa serie per
#     villaggio. La popolazione dell'anno la registra GameTimeService.
# Pannelli di popolazione, individuo selezionato ed edifici rinfrescati come rete di sicurezza periodica.
static func tick_year(ctx: GameContext, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	VillageInfluenceService.apply_annual_growth(ctx.folk, ctx.world)
	if ctx.folk != null:
		for village in ctx.folk.villages:
			if not game_data.village_influence_snapshots.has(village.id):
				game_data.village_influence_snapshots[village.id] = {}
			var by_type: Dictionary = game_data.village_influence_snapshots[village.id]
			for influence_type in InfluenceService.InfluenceType.values():
				if not by_type.has(influence_type):
					by_type[influence_type] = {}
				by_type[influence_type][game_data.year] = village.get_influence_value(influence_type)
	var building_count := 0
	var village_building_counts: Dictionary = {}
	if ctx.folk != null:
		for village in ctx.folk.villages:
			village_building_counts[village.id] = 0
	if ctx.world != null:
		for building in ctx.world.buildings:
			if not building.is_complete or building.is_demolished or building.is_rubble():
				continue
			if building.rules == null or building.rules.category != BuildingTypes.Category.MOVEMENT:
				building_count += 1
				if village_building_counts.has(building.village_id):
					village_building_counts[building.village_id] += 1
	game_data.building_snapshots[game_data.year] = building_count
	for village_id in village_building_counts:
		if not game_data.village_building_snapshots.has(village_id):
			game_data.village_building_snapshots[village_id] = {}
		game_data.village_building_snapshots[village_id][game_data.year] = village_building_counts[village_id]
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
