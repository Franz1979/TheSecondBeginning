class_name WorldTimeService
extends RefCounted

# Accumulatore del timing diagnostico per il checkpoint stagionale (vedi _run_timed/
# _run_seasonal_checkpoints/_print_checkpoint_timing_summary sotto) — azzerato a inizio di ogni
# chiamata a _run_seasonal_checkpoints, così l'instance persistente di WorldTimeService (se il
# chiamante ne riusa una sola per più giorni) non accumula tra un giorno e l'altro. Non è un
# duplicato del vecchio log per-passo già presente in _run_timed (quello resta commentato,
# invariato): qui si raccoglie lo stesso dato per stamparlo in UNA riga compatta a fine
# checkpoint, invece di una riga sparsa per ciascun componente.
var _checkpoint_timings_ms: Dictionary = {}

# Stesso principio di _checkpoint_timings_ms sopra, ma per i passi che girano OGNI giorno
# (_run_daily_animal_consumption/_run_daily_predation/_run_daily_territory_dynamics_stagger/
# _run_daily_animal_hunger/remove_extinct_population_groups dentro advance_day) — MAI coperti dal
# riepilogo [LOD TIMING] esistente, che misura solo _run_seasonal_checkpoints e stampa solo nei
# giorni con checkpoint. Dizionario separato apposta: azzerato a inizio di ogni advance_day, mai
# mescolato con _checkpoint_timings_ms (che ha la propria vita solo dentro _run_seasonal_
# checkpoints), così un giorno senza checkpoint stampa comunque il proprio riepilogo giornaliero
# senza numeri di un altro giorno mischiati dentro.
var _daily_timings_ms: Dictionary = {}

# Advances the calendar by exactly one day, then runs whichever seasonal simulation
# checkpoint(s) fall on the resulting day (see _run_seasonal_checkpoints), plus the animal
# consumption pass (see _run_daily_animal_consumption), che a differenza dei checkpoint
# stagionali gira OGNI giorno, non solo ai confini di stagione. Ritorna le due cause di
# cambiamento separate (non fuse in un solo bool) così i chiamanti che vogliono trattarle
# diversamente — vedi MacroCellScene, che ridisegna sempre ai checkpoint stagionali ma
# l'aggiornamento guidato dal solo consumo animale lo rende opzionale — possono farlo senza
# dover indovinare quale delle due è effettivamente scattata.
func advance_day(world: World, game_data: GameData) -> Dictionary:
	# Timing diagnostico dei soli passi GIORNALIERI (vedi _daily_timings_ms/_print_daily_timing_
	# summary) — azzerato qui, non dentro _run_seasonal_checkpoints (quello resta indipendente,
	# vedi _checkpoint_timings_ms).
	_daily_timings_ms.clear()
	var day_overall_start_usec := Time.get_ticks_usec()

	var year_rolled_over := game_data.advance_day()
	var animals_changed: bool = _run_timed_daily_returning("animal_consumption", func(): return _run_daily_animal_consumption(world, game_data))
	# Caccia dei predatori (Step 3 del piano predatori) — gira OGNI giorno come il consumo
	# erbivoro sopra, indipendente dai checkpoint stagionali, e PRIMA di questi ultimi: una preda
	# catturata oggi deve già risultare decrementata quando gli eventuali checkpoint di oggi
	# (nascite/maturazione/territorio) leggono la sua popolazione, mai lo stato di ieri. Anche
	# PRIMA di _run_daily_animal_hunger sotto (che gira comunque dopo i checkpoint stagionali,
	# vedi ordine esistente): PopulationGroup.apply_predation_loss non tocca hunger_buckets della
	# preda, la riconciliazione con population se ne occupa la prossima volta che
	# AnimalHungerService gira su quel gruppo — stesso giorno, con questo ordine.
	_run_timed_daily("predation", func(): _run_daily_predation(world, game_data))
	# Spalmamento Livello 1 di TerritoryDynamicsService (vedi _run_daily_territory_dynamics_stagger
	# sotto) — gira ogni giorno come consumo/predazione sopra, PRIMA dei checkpoint stagionali:
	# il giorno di turno di un gruppo (dentro la finestra della stagione PRECEDENTE al suo
	# birth_season) non coincide mai per costruzione col giorno di inizio della stagione successiva
	# (dove gira invece il checkpoint stagionale/rete di sicurezza), quindi l'ordine tra i due in
	# uno stesso giorno non è mai osservabile — nessun gruppo viene mai toccato da entrambi lo
	# stesso giorno.
	_run_timed_daily("territory_dynamics_stagger", func(): _run_daily_territory_dynamics_stagger(world, game_data))
	var checkpoint_result := _run_seasonal_checkpoints(world, game_data, year_rolled_over)
	var checkpoint_ran: bool = checkpoint_result["checkpoint_ran"]
	# DOPO i checkpoint stagionali (mai prima): se oggi capita anche un checkpoint di fine
	# birth_season (nascite/morte per vecchiaia), hunger_buckets viene già mantenuto coerente con
	# population da PopulationGroup.apply_births/apply_old_age_mortality PRIMA che questo servizio
	# legga population — vedi AnimalHungerService.
	_run_timed_daily("animal_hunger", func(): _run_daily_animal_hunger(world))
	# ULTIMO passo della giornata, dopo ogni checkpoint che può azzerare population (morte per
	# vecchiaia sopra, fame prolungata appena sopra) — mai prima, altrimenti un gruppo morto oggi
	# stesso resterebbe nell'array (e quindi "occupante" la propria cella) fino a domani. Vedi
	# World.remove_extinct_population_groups per il perché.
	_run_timed_daily("remove_extinct_population_groups", func(): world.remove_extinct_population_groups())

	# Filtrato ai soli dintorni di un checkpoint stagionale (richiesta utente, 2026-09-05 — un log
	# per OGNI giorno, checkpoint o no, era troppo rumoroso): vedi SeasonCalculator.
	# is_near_seasonal_checkpoint per cosa conta come "dintorni".
	if DebugLogging.SHOW_DAILY_TIMING_LOGS and SeasonCalculator.is_near_seasonal_checkpoint(game_data.current_day):
		var day_overall_ms: float = (Time.get_ticks_usec() - day_overall_start_usec) / 1000.0
		_print_daily_timing_summary(game_data.current_day, day_overall_ms, checkpoint_ran)

	# year_rolled_over/season_ended (richiesta utente, 2026-09-05 — Opzione A dalla ricognizione
	# GameClockController<->WorldTimeService): dati GIA' calcolati sopra/dentro
	# _run_seasonal_checkpoints (year_rolled_over da GameData.advance_day(), season_ended dagli
	# stessi confronti su SeasonCalculator che decidono quale blocco eseguire) — semplicemente
	# propagati qui invece di essere scartati, nessuna soglia calendariale nuova calcolata da
	# questo metodo. GameClockController li spacchetta in due segnali distinti (season_ended/
	# year_rolled_over) accanto al day_advanced esistente.
	return {
		"checkpoint_ran": checkpoint_ran,
		"animals_changed": animals_changed,
		"year_rolled_over": year_rolled_over,
		"season_ended": checkpoint_result["season_ended"],
	}


# Parte B del LOD, condivisa da consumo E fame giornalieri (vedi entrambi i chiamanti sotto):
# calcola quali gruppi vanno processati OGGI da un checkpoint erbivoro giornaliero. INCLUDE (non
# più esclude, da quando LOD0 ha portato i livelli a 3 — vedi sotto) solo i gruppi Livello 2 più i
# predatori di qualunque livello — inizialmente costruita solo per il consumo
# (AnimalConsumptionAggregateService la sostituisce per Livello 1), ora estesa anche alla fame
# perché lasciarla "giornaliera per Livello 1" produceva un bug reale: AnimalHungerService legge
# group.daily_caloric_ratio, che però smette di essere aggiornato per un gruppo escluso dal
# consumo giornaliero — il ratio restava CONGELATO all'istante esatto dell'esclusione, producendo
# mortalità da fame arbitraria e scollegata dalla realtà (confermato: pattern di crollo
# irregolare osservato su rabbit/partridge in una sessione di gioco reale). Le popolazioni
# Livello 1 restarono per un periodo SENZA alcun meccanismo di morte diretta per fame — scelta
# deliberata, preferibile a un dato rotto — finché AnimalHungerMortalityAggregateService (vedi
# _run_animal_consumption_aggregate_checkpoint sotto) non ha aggiunto l'equivalente stagionale,
# disattivabile via AnimalHungerMortalityAggregateService.ENABLED. Gli altri sei freni alla
# crescita — mitigazione natalità calorica, mitigazione da densità, espansione/contrazione
# territoriale, split da pressione demografica, recovery post-split, mortalità per vecchiaia —
# restano comunque attivi e invariati per Livello 1 (ma NON per Livello 0, congelato anche lì —
# vedi LODOrchestrator.is_animal_frozen), indipendenti da questo interruttore.
#
# I predatori restano SEMPRE inclusi (cioè sempre processati giornalmente) indipendentemente dal
# loro livello LOD — decisione presa nel profiling, la predazione pesa troppo poco per
# giustificare un'aggregazione. FIX 2026-08-30 (LOD0): con 3 livelli, la vecchia logica a
# ESCLUSIONE ("escludi level_1_groups") avrebbe lasciato filtrare per errore i gruppi Livello 0
# nel calcolo giornaliero (non essendo più in level_1_groups, non sarebbero stati esclusi da
# nulla) — invertita a INCLUSIONE ("includi solo level_2_groups + predatori"), corretta a
# prescindere da quanti livelli sotto esistono, oggi o in futuro.
#
# Ritorna:
#   [] (vuoto)      -> nessun filtro, comportamento di default invariato (processa tutti) — o
#                      perché lod_focus_state è vuoto (vista mondo), o perché non c'è nessun
#                      gruppo Livello 0/1 da escludere (tutti già Livello 2 o predatori).
#   null            -> nessuno da processare oggi (il chiamante deve saltare la chiamata al
#                      service): caso limite in cui NESSUN gruppo del mondo è Livello 2 né
#                      predatore — un array vuoto in quel caso verrebbe riletto dal service come
#                      "nessun filtro, processa tutti" (stesso sentinel "vuoto = default" del
#                      parametro groups_override), l'opposto di quanto inteso.
#   Array non vuoto -> processa solo questi gruppi.
func _get_daily_herbivore_processing_groups(world: World) -> Variant:
	if world.lod_focus_state.is_empty():
		return []

	var included_ids: Dictionary = {}
	for group in world.lod_focus_state["level_2_groups"]:
		included_ids[group.id] = true
	for group in world.population_groups:
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules is PredatorRules:
			included_ids[group.id] = true

	if included_ids.size() >= world.population_groups.size():
		return []

	var groups_to_process: Array = []
	for group in world.population_groups:
		if included_ids.has(group.id):
			groups_to_process.append(group)

	if groups_to_process.is_empty():
		return null

	return groups_to_process


# Gira ogni giorno (non solo ai checkpoint stagionali): il fabbisogno calorico degli animali
# non aspetta il cambio di stagione. Vedi AnimalConsumptionService per la formula.
func _run_daily_animal_consumption(world: World, game_data: GameData) -> bool:
	var current_season := SeasonCalculator.get_season_for_day(game_data.current_day)
	var groups_to_process = _get_daily_herbivore_processing_groups(world)
	if groups_to_process == null:
		return false
	return AnimalConsumptionService.new().apply_daily_consumption(world, current_season, groups_to_process)


# Gira ogni giorno, indipendente da birth_season, esattamente come _run_daily_animal_consumption
# sopra — ma per i predatori (vedi PredationService), non per gli erbivori. year/current_day
# passati per popolare PopulationGroup.recent_hunt_log/yearly_prey_totals (tab Fauna 3, UI) —
# letti DOPO game_data.advance_day() già chiamato sopra in questo stesso metodo, quindi riflettono
# già la data di OGGI, non quella di ieri.
func _run_daily_predation(world: World, game_data: GameData) -> void:
	# LOD0 (2026-08-30): a differenza degli erbivori, i predatori NON hanno mai avuto
	# un'aggregazione stagionale (predazione mai filtrata da Livello 1 vs 2, decisione presa nel
	# profiling) — ma un predatore Livello 0 (mai scoperto) va comunque congelato come tutto il
	# resto (deciso esplicitamente con l'utente, nessuna eccezione neanche per i predatori). Vedi
	# _get_active_predator_groups sotto — PredationService.apply_daily_predation aveva già il
	# parametro active_predator_groups_override pronto (infrastruttura Parte B del LOD mai
	# collegata da nessun chiamante), lo colleghiamo qui.
	var active_predator_groups = _get_active_predator_groups(world)
	if active_predator_groups == null:
		return
	PredationService.new().apply_daily_predation(world, game_data.year, game_data.current_day, active_predator_groups)


# LOD0, lato predatori: quali branchi predatori cacciano OGGI — tutti tranne quelli Livello 0
# (mai scoperti, vedi LODOrchestrator.is_animal_frozen). A differenza di _get_daily_herbivore_
# processing_groups sopra, qui non conta il livello oltre "congelato o no": un predatore Livello 1
# caccia esattamente come uno Livello 2 (nessuna aggregazione stagionale esiste per la predazione).
# Le prede restano SEMPRE cacciabili a prescindere dal proprio livello — PredationService._gather_
# prey_candidates continua a leggere world.population_groups per intero, mai filtrato qui: solo
# l'ATTORE (il predatore) può essere congelato, mai il bersaglio (deciso esplicitamente: la
# predazione su prede Livello 0 resta un decremento reale, nessuna eccezione).
#
# Stesso sentinel [] (nessun filtro)/null (nessuno da processare) di _get_daily_herbivore_
# processing_groups sopra — vedi lì per il significato esatto.
func _get_active_predator_groups(world: World) -> Variant:
	if world.lod_focus_state.is_empty():
		return []

	var groups_to_process: Array = []
	var any_frozen_predator := false
	for group in world.population_groups:
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if not (rules is PredatorRules):
			continue
		if LODOrchestrator.is_animal_frozen(world, group):
			any_frozen_predator = true
			continue
		groups_to_process.append(group)

	if not any_frozen_predator:
		return []

	if groups_to_process.is_empty():
		return null

	return groups_to_process


# Gira ogni giorno, indipendente da birth_season (vedi AnimalHungerService): legge
# group.daily_caloric_ratio già calcolato sopra da _run_daily_animal_consumption, non lo
# ricalcola. Stessa esclusione Livello 1 del consumo (vedi _get_daily_herbivore_processing_groups
# sopra per il perché).
func _run_daily_animal_hunger(world: World) -> void:
	var groups_to_process = _get_daily_herbivore_processing_groups(world)
	if groups_to_process == null:
		return
	AnimalHungerService.new().apply_daily_hunger(world, groups_to_process)


# Fix del bug "classificazione LOD congelata": world.lod_focus_state veniva calcolato una sola
# volta, all'apertura di MacroCellScene, e mai più aggiornato — nuovi PopulationGroup nati da
# split territoriale durante l'anno (PopulationSplitService, dentro territory_dynamics_checkpoint)
# non comparivano in nessuna delle due liste (level_1_groups/level_2_groups), restando quindi
# "non trovati" dalla logica di esclusione in _get_daily_herbivore_processing_groups — trattati
# per sempre come se dovessero girare ogni giorno, erodendo progressivamente il beneficio del LOD
# man mano che le scissioni si accumulavano nel tempo (confermato con una sessione di gioco
# reale: uscire e rientrare dalla macrocella, che rifà set_focus_region da zero, ripristinava la
# velocità).
#
# Richiamato da _run_seasonal_checkpoints SOLO nei giorni in cui è già scattato almeno un
# checkpoint stagionale (mai ogni giorno — vedi guard su checkpoint_ran nel chiamante): rieseguire
# set_focus_region con lo STESSO insieme di celle vive salvato in world.lod_focus_live_cells (mai
# ripassato da GameScene/MacroCellScene ad ogni chiamata) riclassifica TUTTI i gruppi correnti,
# inclusi quelli nati da split in questa stessa stagione — il loro territorio è già stabilizzato a
# questo punto (lo split succede dentro territory_dynamics_checkpoint, che gira sempre prima di
# questo checkpoint nello stesso giorno se è un giorno di inizio-stagione), non classificati a
# metà della propria creazione. No-op se nessun focus è attivo (world.lod_focus_state già vuoto) —
# stesso sentinel "vuoto = vista mondo" usato ovunque altrove per questo campo.
func _run_lod_focus_refresh_checkpoint(world: World, game_data: GameData) -> void:
	if world.lod_focus_state.is_empty():
		return
	var season := SeasonCalculator.get_season_for_day(game_data.current_day)
	world.lod_focus_state = LODOrchestrator.new().set_focus_region(world, world.lod_focus_live_cells, season)


# Parte B del LOD (vedi AnimalConsumptionAggregateService): no-op se nessun focus è attivo — in
# quel caso non esiste alcun gruppo "Livello 1" da processare qui, tutti i gruppi restano sul
# percorso giornaliero invariato (_run_daily_animal_consumption sopra). `season` è la stagione che
# STA INIZIANDO oggi: si passa a valle la stagione PRECEDENTE (SeasonCalculator.get_previous_
# season), la stessa convenzione già usata da _run_secondary_resource_stock_checkpoint, perché il
# consumo aggregato rappresenta il pascolo della stagione appena conclusa, non di quella che parte.
# Ritorna un Dictionary vuoto se non c'è nulla da processare (nessun focus attivo), altrimenti
# {"level_1_groups","previous_season","seasonal_ratios"} — passato a valle a
# _run_animal_hunger_mortality_aggregate_checkpoint sotto (chiamata separata, per un timing
# [LOD TIMING] distinto invece di sommarla silenziosamente a questo passo), che riusa lo STESSO
# Dictionary[group_id -> seasonal_ratio] appena calcolato qui — mai ricalcolato da capo, mai un
# ratio stock-based diverso.
func _run_animal_consumption_aggregate_checkpoint(world: World, season: GameTypes.Season) -> Dictionary:
	if world.lod_focus_state.is_empty():
		return {}
	var level_1_groups: Array = world.lod_focus_state["level_1_groups"]
	var previous_season := SeasonCalculator.get_previous_season(season)
	var seasonal_ratios := AnimalConsumptionAggregateService.new().apply_seasonal_consumption(
		world, level_1_groups, previous_season
	)
	return {
		"level_1_groups": level_1_groups,
		"previous_season": previous_season,
		"seasonal_ratios": seasonal_ratios,
	}


# Passo separato (vedi nota sopra) SOLO per dare a AnimalHungerMortalityAggregateService un
# proprio timing in [LOD TIMING] — no-op se consumption_result è vuoto (nessun focus attivo, vedi
# sopra). Disattivabile per intero via AnimalHungerMortalityAggregateService.ENABLED se il
# meccanismo non convince, senza toccare questa pipeline.
func _run_animal_hunger_mortality_aggregate_checkpoint(world: World, consumption_result: Dictionary) -> void:
	if consumption_result.is_empty():
		return
	AnimalHungerMortalityAggregateService.new().apply_seasonal_hunger_mortality(
		world,
		consumption_result["level_1_groups"],
		consumption_result["previous_season"],
		consumption_result["seasonal_ratios"]
	)

# Debug/emergency fast-forward (the "+1" button): advances a full 365 days one at a time (via
# advance_day) so every seasonal checkpoint crossed along the way still runs, in chronological
# order, exactly once — instead of jumping straight to day 0 and running everything at once.
func force_advance_to_year_end(world: World, game_data: GameData) -> void:
	for i in range(GameData.DAYS_PER_YEAR):
		advance_day(world, game_data)

# Dispatches to the seasonal pipeline steps whose checkpoint day matches game_data.current_day:
#   - start of spring: apply last autumn's pending migration surplus (compute + apply transfers)
#   - end of each season: animal lifecycle (age-band maturation, then births) for whichever
#     species have that AnimalRules.birth_season (see AnimalAgeBandService/AnimalBirthService)
#     — always before that day's other sibling checkpoint, and maturation always before births
#     within the lifecycle checkpoint itself, so this year's newborns never mature the same
#     cycle they're born in — same principle as vegetation's age-band maturation before growth
#   - end of spring: growth + encroachment, leftover surplus stored as this year's pending surplus
#   - start of each season: evaluate natural event types whose reference_season matches
#   - start of each season: for every multi-cell animal territory (any species, not gated by
#     birth_season), reshuffle the random per-cell population weights (visual only — see
#     PopulationTerritoryShuffleService)
#   - end of autumn (year rollover): mortality
# Order within a shared day matters only for SPRING's start (migration before any future
# spring-referenced event type), chosen to mirror the original pipeline's resource-then-events
# ordering.
func _run_seasonal_checkpoints(world: World, game_data: GameData, year_rolled_over: bool) -> Dictionary:
	var day := game_data.current_day
	var checkpoint_ran := false
	# season_ended (richiesta utente, 2026-09-05): quale stagione è terminata OGGI, letta dagli
	# stessi confronti su SeasonCalculator già presenti sotto per decidere quale blocco di
	# checkpoint eseguire — non un secondo calcolo. Sentinel -1 (stessa convenzione "-1 = non
	# applicabile" già in uso ovunque nel progetto, es. GameData.player_macro_cell_x) invece di
	# GameTypes.Season perché nessuna stagione termina nella maggioranza dei giorni: un int
	# generico evita di dover forzare -1 dentro un tipo enum. Al massimo una stagione può
	# terminare in un dato giorno (i tre confronti "end of season" sotto e il ramo year_rolled_over
	# sono su giorni sempre distinti per costruzione, mai sovrapposti), quindi una singola
	# variabile basta, nessun array.
	var season_ended: int = -1
	# Timing diagnostico (vedi _print_checkpoint_timing_summary in fondo alla funzione): azzerato
	# ad ogni chiamata, non solo ad ogni sessione — un giorno ordinario (nessun checkpoint) non
	# stampa nulla comunque, ma l'accumulatore va comunque svuotato per non mischiare i tempi di
	# un giorno con checkpoint con quelli di un giorno successivo senza.
	_checkpoint_timings_ms.clear()
	var overall_start_usec := Time.get_ticks_usec()

	if day == SeasonCalculator.get_season_day_range(GameTypes.Season.SPRING).x:
		_run_timed("migration_checkpoint", func(): _run_migration_checkpoint(world, game_data))
		checkpoint_ran = true

	# Nessun'altra logica gira ancora a fine inverno: blocco dedicato solo alle specie animali
	# con birth_season == WINTER (nessuna oggi, ma il checkpoint deve esistere comunque).
	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.WINTER):
		_run_timed("animal_lifecycle_checkpoint(WINTER)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.WINTER))
		checkpoint_ran = true
		season_ended = GameTypes.Season.WINTER

	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.SPRING):
		_run_timed("animal_lifecycle_checkpoint(SPRING)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.SPRING))
		_run_timed("growth_checkpoint", func(): _run_growth_checkpoint(world, game_data))
		checkpoint_ran = true
		season_ended = GameTypes.Season.SPRING

	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.SUMMER):
		_run_timed("animal_lifecycle_checkpoint(SUMMER)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.SUMMER))
		_run_timed("fauna_migration_checkpoint", func(): _run_fauna_migration_checkpoint(world))
		checkpoint_ran = true
		season_ended = GameTypes.Season.SUMMER

	for season in [GameTypes.Season.WINTER, GameTypes.Season.SPRING, GameTypes.Season.SUMMER, GameTypes.Season.AUTUMN]:
		if day == SeasonCalculator.get_season_day_range(season).x:
			_run_timed(
				"secondary_resource_stock_checkpoint",
				func(): _run_secondary_resource_stock_checkpoint(world, SeasonCalculator.get_previous_season(season), season)
			)
			# Cattura grass_seed_baseline (richiesta utente, 2026-09-05) — DEVE girare PRIMA del
			# consumo appena sotto, vedi doc comment di _run_grass_baseline_capture_checkpoint per
			# il perché dell'ordine.
			_run_timed("grass_baseline_capture_checkpoint", func(): _run_grass_baseline_capture_checkpoint(world))
			# Parte B del LOD: consumo aggregato stagionale SOLO per popolazioni Livello 1 non
			# predatrici (vedi AnimalConsumptionAggregateService) — DOPO l'aggiornamento delle
			# scorte a stock sopra (che devono maturare per la nuova stagione prima di poter essere
			# consumate) e PRIMA di natural_events/territory_dynamics sotto, cosicché
			# AnimalBirthMitigationService (dentro territory_dynamics_checkpoint) legga
			# dedicated_space/secondary_resource_stock già decrementati da questo consumo, esattamente
			# come farebbe con il consumo giornaliero di Livello 2. No-op per costruzione se
			# World.lod_focus_state è vuoto (vista mondo, nessun focus attivo) — vedi guard nel
			# metodo sotto. AnimalConsumptionService (Livello 2/debug) resta invariato, mai toccato.
			var consumption_result: Dictionary = _run_timed_returning(
				"animal_consumption_aggregate_checkpoint",
				func(): return _run_animal_consumption_aggregate_checkpoint(world, season)
			)
			# Mortalità da fame aggregata (AnimalHungerMortalityAggregateService), timing separato
			# dal consumo sopra — vedi doc comment del metodo per il perché.
			_run_timed(
				"animal_hunger_mortality_aggregate_checkpoint",
				func(): _run_animal_hunger_mortality_aggregate_checkpoint(world, consumption_result)
			)
			_run_timed("natural_events_checkpoint", func(): _run_natural_events_checkpoint(world, game_data, season))
			# Step 8 del refactoring fauna: territorio ed espansione/contrazione girano nello
			# STESSO checkpoint di inizio birth_season in cui girava già (da solo) il calcolo del
			# ratio calorico per la mitigazione natalità — i due condividono la stessa identica
			# definizione di scarsità (vedi TerritoryDynamicsService), quindi la mitigazione non è
			# più un checkpoint a sé: è orchestrata da TerritoryDynamicsService stesso, DOPO
			# l'eventuale aggiustamento del territorio, mai prima.
			_run_timed(
				"territory_dynamics_checkpoint",
				func(): _run_territory_dynamics_checkpoint(world, season, game_data.year)
			)
			_run_timed("animal_territory_shuffle_checkpoint", func(): _run_animal_territory_shuffle_checkpoint(world, season))
			checkpoint_ran = true

	if year_rolled_over:
		# AUTUMN "end of season" non può essere un confronto sul giorno (current_day è già
		# tornato a 0 quando year_rolled_over è true, vedi GameData.advance_day) — year_rolled_over
		# stesso è il segnale di fine autunno, stesso schema già usato da _run_mortality_checkpoint.
		_run_timed("animal_lifecycle_checkpoint(AUTUMN)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.AUTUMN))
		_run_timed("mortality_checkpoint", func(): _run_mortality_checkpoint(world))
		checkpoint_ran = true
		season_ended = GameTypes.Season.AUTUMN

	# Fix del bug "classificazione LOD congelata": ricalcola lod_focus_state, se un focus è
	# attivo, ALLA FINE di qualunque giorno in cui sia scattato almeno un checkpoint stagionale
	# (mai un giorno ordinario — vedi guard su checkpoint_ran, altrimenti si perderebbe tutto il
	# guadagno di performance del LOD ricalcolando ogni giorno). Copre sia i giorni di fine-
	# stagione (lifecycle/growth/mortality, che non creano mai nuovi gruppi) sia quelli di inizio-
	# stagione (territory_dynamics, l'unico punto che ne crea via PopulationSplitService) — vedi
	# _run_lod_focus_refresh_checkpoint per il dettaglio completo.
	if checkpoint_ran:
		_run_timed("lod_focus_refresh_checkpoint", func(): _run_lod_focus_refresh_checkpoint(world, game_data))

	# Riepilogo diagnostico compatto (Richiesta: "aggiungi timing... senza toccare i log
	# esistenti se possibile") — una sola riga a fine checkpoint, indipendente dal log per-passo
	# già presente in _run_timed (che resta commentato/inattivo, invariato) e dal logging molto
	# verboso di PredationService (tutt'altro percorso, mai toccato da questo timing). Solo nei
	# giorni in cui è scattato almeno un checkpoint — un giorno ordinario non stampa nulla.
	if checkpoint_ran and DebugLogging.SHOW_DAILY_TIMING_LOGS:
		var overall_ms: float = (Time.get_ticks_usec() - overall_start_usec) / 1000.0
		_print_checkpoint_timing_summary(day, overall_ms)

	return {"checkpoint_ran": checkpoint_ran, "season_ended": season_ended}


# Stampa un'unica riga compatta col tempo di ciascun componente del checkpoint stagionale di
# oggi, ordinati per nome (non per durata: un ordine stabile rende più facile confrontare a
# colpo d'occhio la stessa riga tra giorni diversi). `overall_ms` è misurato con un cronometro
# INDIPENDENTE che avvolge l'intera _run_seasonal_checkpoints (non la somma dei singoli
# componenti): alcune etichette sono annidate l'una nell'altra (es. "growth_checkpoint" include
# già il tempo di "  grow_resources"/"  grow_fauna" al suo interno, essendo la funzione che li
# chiama) — sommare le etichette darebbe un totale gonfiato da doppio conteggio, mentre il
# cronometro esterno misura il tempo di parete reale una sola volta.
func _print_checkpoint_timing_summary(day: int, overall_ms: float) -> void:
	var season := SeasonCalculator.get_season_for_day(day)
	var labels: Array = _checkpoint_timings_ms.keys()
	labels.sort()
	var parts: Array = []
	for label in labels:
		parts.append("%s=%.1fms" % [label.strip_edges(), _checkpoint_timings_ms[label]])
	print("[LOD TIMING] giorno %d (%s) totale=%.1fms | %s" % [
		day, GameTypes.Season.keys()[season], overall_ms, ", ".join(parts)
	])


# TEMPORANEO — diagnostica per isolare quale funzione del checkpoint stagionale è responsabile
# del rallentamento segnalato tra giorno 181 e 182 (Step 11): misura e stampa il tempo di ogni
# passo (Time.get_ticks_usec, non affetto da eventuale vsync/frame limiting). Gated da
# DebugLogging.ENABLED come il resto della diagnostica — va rimossa una volta individuata la
# causa. `action` viene sempre eseguita (il gate riguarda solo la stampa del tempo, mai il
# lavoro reale).
func _run_timed(label: String, action: Callable) -> void:
	var start_usec := Time.get_ticks_usec()
	action.call()
	var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0
	# Accumula per il riepilogo compatto di fine checkpoint (vedi _print_checkpoint_timing_summary)
	# — additivo (non un'assegnazione secca) perché lo stesso label può ricorrere più volte nello
	# stesso giorno (es. animal_lifecycle_checkpoint per stagioni diverse non capita mai lo stesso
	# giorno, ma label annidate come "  grow_resources" sono comunque unici per giorno oggi;
	# l'addizione è comunque sicura in caso cambiasse in futuro).
	_checkpoint_timings_ms[label] = float(_checkpoint_timings_ms.get(label, 0.0)) + elapsed_ms
	if DebugLogging.ENABLED:
		pass
		#print("[TIMING] %s: %.2f ms" % [label, elapsed_ms])


# Variante di _run_timed sopra che propaga il valore di ritorno di `action` al chiamante — GDScript
# cattura le variabili locali dei lambda PER VALORE (un'assegnazione a una variabile esterna
# dentro un lambda non si propaga fuori), quindi un pattern "func(): outer_var = ..." passato a
# _run_timed non funzionerebbe per portare un risultato fuori dal timing. Usata da
# _run_animal_consumption_aggregate_checkpoint sotto, che deve passare il proprio risultato al
# checkpoint di mortalità da fame successivo mantenendo comunque un timing separato per entrambi.
func _run_timed_returning(label: String, action: Callable) -> Variant:
	var start_usec := Time.get_ticks_usec()
	var result = action.call()
	var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0
	_checkpoint_timings_ms[label] = float(_checkpoint_timings_ms.get(label, 0.0)) + elapsed_ms
	return result


# Stesse due varianti di _run_timed/_run_timed_returning sopra, ma per i passi GIORNALIERI di
# advance_day (accumulano in _daily_timings_ms, mai in _checkpoint_timings_ms — vedi il commento
# su quel campo per il perché restano separati).
func _run_timed_daily(label: String, action: Callable) -> void:
	var start_usec := Time.get_ticks_usec()
	action.call()
	var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0
	_daily_timings_ms[label] = float(_daily_timings_ms.get(label, 0.0)) + elapsed_ms


func _run_timed_daily_returning(label: String, action: Callable) -> Variant:
	var start_usec := Time.get_ticks_usec()
	var result = action.call()
	var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0
	_daily_timings_ms[label] = float(_daily_timings_ms.get(label, 0.0)) + elapsed_ms
	return result


# Riepilogo compatto di TUTTI i giorni (a differenza di _print_checkpoint_timing_summary, che
# stampa solo nei giorni con almeno un checkpoint stagionale) — serve proprio a distinguere se la
# lentezza percepita viene dai passi giornalieri qui sotto o da altrove (es. rendering/streaming
# celle vive in GameScene, mai misurato da WorldTimeService). `overall_ms` include anche l'eventuale
# _run_seasonal_checkpoints di oggi (misurato per conto proprio, vedi [LOD TIMING] accanto a
# questa riga nei giorni in cui compare) — sottraendo la somma delle etichette qui sotto a
# overall_ms si ottiene il costo del solo checkpoint stagionale, se presente.
func _print_daily_timing_summary(day: int, overall_ms: float, checkpoint_ran: bool) -> void:
	var labels: Array = _daily_timings_ms.keys()
	labels.sort()
	var parts: Array = []
	for label in labels:
		parts.append("%s=%.1fms" % [label, _daily_timings_ms[label]])
	print("[DAY TIMING] giorno %d totale=%.1fms (checkpoint_stagionale=%s) | %s" % [
		day, overall_ms, "si" if checkpoint_ran else "no", ", ".join(parts)
	])


func _run_animal_lifecycle_checkpoint(world: World, season: GameTypes.Season) -> void:
	# Ordine fisso: maturazione -> nascite -> morte per vecchiaia. Maturazione PRIMA, nascite
	# DOPO — così i nuovi nati (sempre aggiunti in YOUNG da AnimalBirthService) non maturano mai
	# nello stesso ciclo in cui compaiono, garantito strutturalmente dall'ordine di chiamata qui,
	# non da un controllo a parte. Morte per vecchiaia PER ULTIMA: include anche gli individui
	# appena entrati in OLD in questo stesso checkpoint (la maturazione adult->old gira prima,
	# sopra) — nessuno stato "appena arrivato" viene tracciato da nessuna transizione di fascia,
	# quindi non lo tracciamo neanche per la mortalità (vedi AnimalOldAgeMortalityService).
	_run_timed("  mature_age_bands (animali)", func(): AnimalAgeBandService.new().mature_age_bands(world, season))
	_run_timed("  apply_births", func(): AnimalBirthService.new().apply_births(world, season))
	_run_timed("  apply_old_age_mortality", func(): AnimalOldAgeMortalityService.new().apply_old_age_mortality(world, season))


func _run_growth_checkpoint(world: World, game_data: GameData) -> void:
	# Maturazione PRIMA di growth/encroachment: opera sulla composizione young/adult/old
	# ereditata dagli anni precedenti, cosicché le nascite di growth in questo stesso ciclo
	# (età 0) non vengano mai incluse nella maturazione dello stesso anno in cui compaiono —
	# vedi ResourceAgeBandService.
	_run_timed("  mature_age_bands (vegetazione)", func(): ResourceAgeBandService.new().mature_age_bands(world))

	_run_timed("  grow_resources", func(): ResourceGrowthService.new().grow_resources(world, game_data))

	# Fine della finestra di visibilità dei marker "morto" da mortalità naturale (vedi
	# SeasonCalculator.is_within_natural_death_visibility_window/IndividualVegetationService): a
	# differenza del taglio (persistente, azione deliberata del giocatore), la morte naturale è solo
	# un artificio grafico stagionale — "morto" da fine autunno a qui, poi la ricrescita rioccupa lo
	# slot. Pulizia GLOBALE (tutto world.cell_states, non solo le celle vive), stessa ampiezza di
	# ResourceMortalityService/grow_resources sopra: una cella mai visitata deve arrivare comunque
	# "pulita" al prossimo first-sight, esattamente come una già nota.
	_run_timed("  clear_natural_death_markers", func(): _clear_natural_death_markers(world))

	# Step 11 Step 4: mitigazione dell'encroachment da presenza fisica di fauna brucante (densità
	# di riempimento per cella rispetto ad AnimalRules.max_density_per_cell) — vedi
	# BrowsingMitigationService. Il risultato è ora un INPUT REALE per encroach_resources sotto
	# (non più solo calcolo/log): gira quindi SEMPRE, non gated da DebugLogging.ENABLED. Il
	# prototipo calorico precedente (GrazingPressureService, scartato: la scarsità calorica è già
	# coperta altrove da fame/mortalità) è stato rimosso in una sessione precedente.
	# Non passata tramite _run_timed: serve il valore di ritorno, misurata quindi a mano — stesso
	# schema di encroach_resources sotto.
	var browsing_start_usec := Time.get_ticks_usec()
	var browsing_mitigation := BrowsingMitigationService.new().compute_browsing_mitigation(world)
	# Registrato per il riepilogo compatto di fine checkpoint (vedi _print_checkpoint_timing_
	# summary) accanto al vecchio log per-passo sotto, che resta commentato/invariato — le due
	# cose sono indipendenti, questa riga non lo sostituisce.
	_checkpoint_timings_ms["  compute_browsing_mitigation"] = float(_checkpoint_timings_ms.get("  compute_browsing_mitigation", 0.0)) + (Time.get_ticks_usec() - browsing_start_usec) / 1000.0
	if DebugLogging.ENABLED:
		pass
		#print("[TIMING]   compute_browsing_mitigation: %.2f ms" % [(Time.get_ticks_usec() - browsing_start_usec) / 1000.0])

	var encroach_start_usec := Time.get_ticks_usec()
	var encroachment_service := ResourceEncroachmentService.new()
	var leftover_surplus := encroachment_service.encroach_resources(world, browsing_mitigation)
	_checkpoint_timings_ms["  encroach_resources"] = float(_checkpoint_timings_ms.get("  encroach_resources", 0.0)) + (Time.get_ticks_usec() - encroach_start_usec) / 1000.0
	if DebugLogging.ENABLED:
		pass
		#print("[TIMING]   encroach_resources: %.2f ms" % [(Time.get_ticks_usec() - encroach_start_usec) / 1000.0])
	_store_pending_migration_surplus(world, leftover_surplus)

	# FISH cresce sullo stesso checkpoint di fine primavera della vegetazione, ma su un budget
	# separato (water_dedicated_space): nessuna interazione con
	# encroachment/pending_migration_surplus terrestri. Migration e mortality per FISH sono
	# invece in checkpoint propri (fine estate/fine autunno, vedi sotto) — a differenza della
	# vegetazione, growth->migration->mortality per FISH restano tre momenti separati dell'anno
	# invece che un'unica pipeline diretta, per poter osservare l'evoluzione di ciascuna fase.
	_run_timed("  grow_fauna", func(): FaunaGrowthService.new().grow_fauna(world))

	# Ripristino annuale del grass "congelato ma consumato" (richiesta utente, 2026-09-05): SOLO
	# le celle con un grass_seed_baseline catturato (vedi _run_grass_baseline_capture_checkpoint)
	# tornano al valore di semina, invece di restare erose per sempre dal consumo Livello 1 —
	# senza far girare qui la vera crescita (che resta bloccata, is_vegetation_frozen invariato).
	_run_timed("  grass_baseline_restore", func(): _restore_frozen_grass_to_baseline(world))


# Contro-parte del ripristino sopra: cattura grass_seed_baseline (una tantum, mai sovrascritto)
# per ogni cella congelata che entra a far parte del territorio di una popolazione erbivora
# Livello 1/2 attiva — DEVE girare PRIMA di animal_consumption_aggregate_checkpoint nello stesso
# checkpoint di inizio stagione (vedi chiamata sotto), altrimenti rischierebbe di fotografare un
# valore già eroso dal consumo di quella stessa stagione invece del vero valore di semina. Sicuro
# catturare qui indipendentemente da quale giorno della stagione precedente il territorio abbia
# davvero guadagnato la cella (spalmamento giornaliero, TerritoryDynamicsService.
# process_daily_stagger): il consumo Livello 1 è SOLO a checkpoint, mai giornaliero, quindi nulla
# può aver eroso dedicated_space(GRASS) tra l'ingresso nel territorio e questo momento.
func _run_grass_baseline_capture_checkpoint(world: World) -> void:
	for coords in LODOrchestrator.get_active_herbivore_territory_cells(world):
		var state := world.get_cell_state_at(coords.x, coords.y)
		if state == null or state.grass_seed_baseline != -1:
			continue
		if not LODOrchestrator.is_vegetation_frozen(world, state):
			continue
		state.grass_seed_baseline = state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)


func _restore_frozen_grass_to_baseline(world: World) -> void:
	for state in world.cell_states:
		if state.grass_seed_baseline == -1 or not LODOrchestrator.is_vegetation_frozen(world, state):
			continue
		state.set_dedicated_space(GameTypes.WorldObjectType.GRASS, state.grass_seed_baseline)
		var cell := world.get_cell_at(state.x, state.y)
		if cell == null:
			continue
		var max_density := ResourceCalculator.get_max_density(
			GameTypes.WorldObjectType.GRASS, cell.terrain_base, cell.biome, cell.coast_type
		)
		state.set_resource_quantity(
			GameTypes.WorldObjectType.GRASS, int(round(state.grass_seed_baseline * max_density))
		)


func _clear_natural_death_markers(world: World) -> void:
	for state in world.cell_states:
		if not state.vegetation_death_exceptions.is_empty():
			state.vegetation_death_exceptions.clear()


# Fine estate: unico checkpoint per la migrazione FISH, nessuno sfasamento all'anno successivo
# come lo schema "seed bank" della vegetazione (_run_migration_checkpoint sotto).
func _run_fauna_migration_checkpoint(world: World) -> void:
	FaunaMigrationService.new().migrate_fauna(world)


func _run_mortality_checkpoint(world: World) -> void:
	var mortality_service := ResourceMortalityService.new()
	mortality_service.apply_mortality(world)

	# Rete di sicurezza annuale contro il raro overshoot di dedicated_space introdotto da
	# BuildingSiteClearingService (vedi SpaceReconciliationService) — subito dopo la mortalità
	# perché è il momento in cui dedicated_space[TREE/SHRUB/GRASS] è già stato ridotto in base a
	# chi è morto davvero: nella maggior parte dei casi la somma è già tornata sotto TOTAL_SPACE da
	# sola, questo passaggio interviene solo sul residuo. GLOBALE (tutto world.cell_states, non
	# solo le celle vive), stessa ampiezza di apply_mortality sopra.
	for state in world.cell_states:
		SpaceReconciliationService.reconcile(state)

	# Stesso checkpoint di fine autunno (year_rolled_over) della mortalità vegetale, su
	# water_dedicated_space invece che dedicated_space.
	FaunaMortalityService.new().apply_fauna_mortality(world)


# A inizio di ogni stagione (stesso giorno degli altri checkpoint "start of season" sopra): per
# le specie con birth_season == season, valuta espansione/contrazione del territorio e poi
# calcola il moltiplicatore di mitigazione della natalità legato alla disponibilità calorica —
# in quest'ordine, sullo stesso ratio calorico condiviso (vedi TerritoryDynamicsService). Il
# moltiplicatore risultante resta memorizzato sul gruppo fino al checkpoint di nascita già
# esistente, a fine birth_season.
func _run_territory_dynamics_checkpoint(world: World, season: GameTypes.Season, current_year: int) -> void:
	TerritoryDynamicsService.new().update_territories_and_mitigation(world, season, current_year)


# Driver giornaliero dello spalmamento Livello 1 (TerritoryDynamicsService.STAGGER_LEVEL_1_ENABLED
# — vedi lì per il design completo): gira OGNI giorno, non solo ai confini di stagione, esattamente
# come _run_daily_animal_consumption/_run_daily_predation/_run_daily_animal_hunger sopra. No-op
# immediato dentro TerritoryDynamicsService.process_daily_stagger se l'interruttore è a false o se
# nessun focus LOD è attivo — nessun guard duplicato qui, un solo punto di verità.
func _run_daily_territory_dynamics_stagger(world: World, game_data: GameData) -> void:
	TerritoryDynamicsService.new().process_daily_stagger(world, game_data)


func _run_migration_checkpoint(world: World, game_data: GameData) -> void:
	var migration_service := ResourceMigrationService.new()
	var leftover_surplus := _collect_pending_migration_surplus(world)
	var transfers := migration_service.compute_transfers(world, leftover_surplus)
	migration_service.apply_transfers(world, transfers)
	_clear_pending_migration_surplus(world)


func _run_natural_events_checkpoint(world: World, game_data: GameData, season: GameTypes.Season) -> void:
	var natural_event_service := NaturalEventService.new()
	natural_event_service.trigger_events(world, game_data, season)


# Stesso giorno "inizio stagione" del checkpoint sopra, ma NON filtrato per AnimalRules.
# birth_season: si applica a ogni gruppo con territorio multi-cella a ogni cambio stagione (4
# volte/anno), non solo alla propria stagione di nascita — qui la stagione è solo il ritmo del
# rimescolamento visivo, non legata al ciclo riproduttivo di una specie (vedi
# PopulationTerritoryShuffleService, Step 6 del refactoring fauna).
func _run_animal_territory_shuffle_checkpoint(world: World, season: GameTypes.Season) -> void:
	PopulationTerritoryShuffleService.new().shuffle_distribution(world, season)


func _run_secondary_resource_stock_checkpoint(
	world: World, previous_season: GameTypes.Season, new_season: GameTypes.Season
) -> void:
	# Skip a monte, DUE condizioni indipendenti (richiesta utente, 2026-09-05):
	# - Opzione 1: CaloricCalculator.has_secondary_resource_potential legge solo dati grezzi già in
	#   RAM (nessuna densità/regola sottotipo) — sicuro saltare quando sia il potenziale ATTUALE sia
	#   lo stock già presente sono 0, non c'è nulla che possa cambiare.
	# - Opzione 2 (LOD0): una cella CONGELATA (LODOrchestrator.is_vegetation_frozen — mai scoperta,
	#   nessun erbivoro Livello 2 ci pascola) può comunque essere saltata SOLO se in più non
	#   appartiene al territorio di nessuna popolazione erbivora Livello 1/2 attiva
	#   (get_active_herbivore_territory_cells) — altrimenti quella popolazione si troverebbe questa
	#   fonte congelata a zero per sempre in gran parte del proprio territorio (stesso rischio già
	#   verificato e corretto per il grass). Le due condizioni si sommano (OR), mai in conflitto:
	#   nessuna delle due salta mai una cella che serva davvero a qualcuno.
	# Log diagnostico di quante celle (su world.cell_states.size(), tipicamente 10.000) sono state
	# effettivamente saltate per ciascuna fonte, per misurare il beneficio reale di entrambe insieme.
	#
	# MIGLIORAMENTO FUTURO possibile (misurato in sessione, 2026-09-05 — non implementato): anche a
	# skip ~100%, il checkpoint resta a ~150-180ms (contro le migliaia di ms di prima, ma non i
	# "pochi ms" sperati) perché il ciclo sotto continua comunque a VISITARE tutte le 40.000
	# combinazioni fonte×cella per decidere di saltarle — l'overhead di chiamata GDScript ripetuto
	# 40.000 volte è ormai il costo dominante, non il calcolo vero. Per scendere oltre servirebbe
	# smettere di scorrere world.cell_states per intero: mantenere un insieme esplicito e già
	# aggiornato di "celle potenzialmente rilevanti" (scoperte + territori attivi, tipicamente
	# minuscolo) e iterare SOLO quello — richiede un indice che oggi non esiste da nessuna parte
	# (has_ever_been_discovered è un flag per-cella, non una lista consultabile), quindi un cambio
	# più strutturale, rimandato.
	var active_herbivore_territory_cells := LODOrchestrator.get_active_herbivore_territory_cells(world)
	var skip_summary: Array[String] = []
	var total_skipped := 0
	var total_checked := 0
	for source in CaloricCalculator.SECONDARY_SOURCES:
		var rules := CaloricCalculator.get_caloric_source_rules(source["resource_name"])
		if rules == null:
			continue
		var skipped := 0
		for state in world.cell_states:
			var cell := world.get_cell_at(state.x, state.y)
			if cell == null:
				continue
			total_checked += 1
			if (
				not CaloricCalculator.has_secondary_resource_potential(rules, state, source["primary_resource_type"])
				and state.get_secondary_resource_stock(source["resource_name"]) == 0.0
			):
				skipped += 1
				continue
			if (
				LODOrchestrator.is_vegetation_frozen(world, state)
				and not active_herbivore_territory_cells.has(Vector2i(state.x, state.y))
			):
				skipped += 1
				continue
			CaloricCalculator.update_secondary_resource_stock(
				rules, cell, state, source["primary_resource_type"], previous_season, new_season
			)
		skip_summary.append("%s=%d/%d" % [source["resource_name"], skipped, world.cell_states.size()])
		total_skipped += skipped

	if DebugLogging.SHOW_DAILY_TIMING_LOGS:
		print("[SECONDARY STOCK SKIP] %s | totale=%d/%d (%.1f%%)" % [
			", ".join(skip_summary), total_skipped, total_checked,
			100.0 * total_skipped / total_checked if total_checked > 0 else 0.0
		])


func _store_pending_migration_surplus(world: World, leftover_surplus: Dictionary) -> void:
	for cell_key in leftover_surplus.keys():
		var state := world.get_cell_state_at(cell_key.x, cell_key.y)
		if state == null:
			continue
		for resource_type in leftover_surplus[cell_key].keys():
			var surplus_quantity = leftover_surplus[cell_key][resource_type]
			state.pending_migration_surplus[resource_type] = surplus_quantity
			#if DebugLogging.ENABLED and cell_key.x == 50 and cell_key.y == 50:
			#	print("[SURPLUS SAVED 50,50] %s: %.3f accantonato" % [
			#		GameTypes.WorldObjectType.keys()[resource_type], surplus_quantity
			#	])


func _collect_pending_migration_surplus(world: World) -> Dictionary:
	var leftover_surplus: Dictionary = {}
	for state in world.cell_states:
		if state.pending_migration_surplus.is_empty():
			continue
		#if DebugLogging.ENABLED and state.x == 50 and state.y == 50:
		#	for resource_type in state.pending_migration_surplus.keys():
		#		print("[SURPLUS APPLIED 50,50] %s: %.3f applicato" % [
		#			GameTypes.WorldObjectType.keys()[resource_type], state.pending_migration_surplus[resource_type]
		#		])
		leftover_surplus[Vector2i(state.x, state.y)] = state.pending_migration_surplus.duplicate()
	return leftover_surplus


func _clear_pending_migration_surplus(world: World) -> void:
	for state in world.cell_states:
		state.pending_migration_surplus.clear()
