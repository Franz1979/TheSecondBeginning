class_name GameTimeService
extends RefCounted

# Step 2 del piano riproduzione (2026-09-06): nascondono (non rimuovono) i riepiloghi annuali
# "[HUMAN MORTALITY]"/"[HUMAN COUPLING]" già verificati in sessioni precedenti — richiesta utente:
# troppo rumore in console ora che si aggiunge "[HUMAN CONCEPTION]" (quello sì sempre attivo, vedi
# _run_annual_human_conception sotto). Riattivabili a `true` senza dover riscrivere nulla. Non
# tocca "[HUMAN MORTALITY DEBUG]" (diagnostico per-individuo, tag distinto, non menzionato dalla
# richiesta) né alcun'altra logica dei due service.
const DEBUG_LOG_MORTALITY := false
const DEBUG_LOG_COUPLING := true

# Primo consumatore gameplay-side dei checkpoint temporali classificati esposti da
# GameClockController (day_advanced/season_ended/year_rolled_over, propagati da WorldTimeService.
# advance_day senza duplicare i confronti su SeasonCalculator — vedi ricognizione 2026-09-05).
#
# RefCounted come gli altri *Service del progetto, ma a differenza di quelli (stateless,
# "istanzia con .new() e chiama il metodo" — vedi CLAUDE.md) questa istanza deve restare VIVA per
# tutta la durata di GameScene: è la connessione ai segnali stessa a doverle sopravvivere. Il
# chiamante (GameScene) la tiene in un campo (game_time_service), esattamente come tiene clock
# (GameClockController) — se l'unico riferimento uscisse di scope, Godot libererebbe l'istanza e
# le connessioni smetterebbero di scattare senza errore visibile.

# Step 6 (2026-09-05): emesso PRIMA di rimuovere l'individuo da _human_individuals (vedi
# _apply_scheduled_human_deaths sotto), con l'indice che aveva in quell'array in quel momento —
# GameScene.human_individual_views è parallelo per indice a human_individuals (stessa collezione
# di GameScene, vedi il commento lì: "parallelo per indice... la riparentazione richiede di
# trovare la view di un individuo per indice"), quindi GameScene deve rimuovere/liberare la view
# corrispondente ALLO STESSO indice prima che la rimozione qui sotto sfasi tutto ciò che segue.
# age_at_death/partner_freed (sistema notifiche, 2026-09-05): già calcolati qui per il log
# console, passati a GameScene così può comporre il testo del popup di morte senza doverli
# ricalcolare — questa classe non sa nulla di UI/popup, si limita a fornire i dati.
# cause/day AGGIUNTI (Step 9, 2026-09-05): prima GameScene leggeva individual.scheduled_death_day
# direttamente per il "giorno" del popup — sbagliato per una morte immediata (kill_individual_now
# sotto, causa MURDER) che non passa mai da scheduled_death_day, quel campo resterebbe -1. day è
# ora sempre il giorno vero passato a _kill_individual, cause la causa vera invece del fisso
# OLD_AGE di prima — nessun consumo ancora nel testo del popup (arriva in uno step successivo),
# ma il segnale porta già il dato corretto.
signal individual_died(
	individual: HumanIndividual, index: int, age_at_death: int, partner_freed: bool,
	cause: DeathTypes.DeathCause, day: int
)
# Emesso UNA VOLTA a fine giornata, DOPO che tutte le rimozioni/aggiornamenti di total_count del
# giorno sono completati — a differenza di individual_died sopra (emesso PRIMA di ogni singola
# rimozione, con l'indice ancora valido per human_individual_views), questo è il punto giusto per
# rinfrescare pannelli che leggono lo stato AGGIORNATO (es. la scheda 👨‍👩‍👧, che mostra anche
# total_count) — bugfix, richiesta utente, 2026-09-05: collegare il refresh direttamente dentro
# individual_died mostrava ancora i dati vecchi, perché a quel punto la rimozione non era ancora
# avvenuta. Non emesso nei giorni senza morti (nessun refresh inutile).
signal human_population_changed
# Step 4 del piano riproduzione (2026-09-06) — stesso schema simmetrico di individual_died sopra:
# emesso DOPO che il neonato è già stato aggiunto a _human_individuals (HumanBirthIndividualService
# lo appende direttamente, vedi _run_annual_human_births sotto), non prima — GameScene lo ascolta
# per creare la HumanIndividualView corrispondente e tenerla parallela per indice a
# human_individual_views (stesso invariante già rispettato per le rimozioni di individual_died).
signal individual_born(individual: HumanIndividual)
# Step 2 dell'effetto nato-morto (2026-09-06) — simmetrico a individual_born sopra, ma per
# l'esito OPPOSTO del tiro sopravvivenza figlio (vedi HumanBirthIndividualService._roll_
# childbirth_survival): quando fallisce, nessun HumanIndividual viene mai creato (vedi
# _run_births_in_group), quindi non esiste un figlio da passare come individual_born fa — solo
# `mother` (chi ha vissuto il nato-morto), sufficiente per comporre il testo del popup (Step 3,
# GameScene). Nessun parametro aggiuntivo (father_id/year) aggiunto in anticipo: nessun consumatore
# ne ha bisogno oggi.
signal human_stillbirth(mother: HumanIndividual)
# Decadimento zaino (2026-09-09, richiesta utente, Step 3 decadimento) — emesso da
# _advance_daily_individual_resource_decay sotto quando ResourceDecayService.advance_individual_
# decay riporta una perdita (decay_fraction >= 1.0, risorsa rimossa). Stesso identico principio di
# disaccoppiamento di individual_died/individual_born sopra: questa classe non sa nulla di popup/
# UI, si limita a segnalare il FATTO, GameScene decide come mostrarlo.
signal individual_resource_decayed(individual: HumanIndividual, resource_name: String, quantity: int)

# Emesso il giorno in cui un individuo finisce le provviste e comincia a consumare la riserva corporea
# (2026-09-19, richiesta utente): una volta per inizio di consumo, vedi body_reserve_in_use. GameScene
# lo trasforma in un popup di alert.
signal individual_started_body_reserve(individual: HumanIndividual)

# Giorni consecutivi di fame dopo i quali un individuo muore per STARVATION (2026-09-19, richiesta
# utente). Un individuo che consuma calorie conta i giorni con body_calories a 0; un INFANT senza nessun
# adulto che lo porta conta i giorni da orfano. Vedi _apply_daily_starvation e HumanIndividual.starvation_days.
const STARVATION_DAYS: int = 5

var _game_data: GameData
# Riferimenti (non copie) allo STESSO Array/Folk/HumanPopulationGroup che GameScene possiede —
# un Array in GDScript è per riferimento, quindi la rimozione reale (Step 6, vedi
# _apply_scheduled_human_deaths sotto) fatta qui resta visibile a GameScene senza dover ripassare
# nulla ad ogni chiamata. _human_folk (non solo human_rules_ref preso una volta sola) perché
# human_rules_ref potrebbe in teoria essere riassegnato più avanti (cambio Era) — leggerlo fresco
# ad ogni anno invece di cachearlo resta corretto in entrambi i casi.
var _human_individuals: Array[HumanIndividual]
var _human_folk: Folk
# Riferimento al World condiviso (2026-09-14, richiesta utente — controllo giornaliero di
# ritentativo per un individuo bloccato su SetupSiteAction, vedi HumanIndividualActionService.
# retry_blocked_material_shortages) — STESSO oggetto di GameScene.macro_world, per riferimento
# (World è una classe, non un Resource value-type), mai una copia. Nessun altro consumatore in
# questo file lo usa ancora: aggiunto ORA perché questo è il primo ricalcolo giornaliero che deve
# conoscere World.buildings (i precedenti — stamina/carry capacity/vitali/decadimento — operano
# solo su HumanIndividual, mai su Building).
var _world: World
# Istanza CONDIVISA di HumanIndividualActionService (2026-09-14, richiesta utente/bugfix parser —
# STESSA istanza di GameScene.individual_action_service, quella che guida apply_action ogni frame):
# retry_blocked_material_shortages/_resolve_material_shortage sono metodi D'ISTANZA (mai stati
# static — _resolve_material_shortage in particolare deve poter emettere il segnale building_
# material_blocked, e i segnali in GDScript vivono solo su un'istanza), quindi questa classe non
# può più richiamarli per nome di classe: deve girare sulla STESSA istanza a cui GameScene è già
# collegato per quel segnale.
var _individual_action_service: HumanIndividualActionService
# Serve SOLO per tenere total_count allineato a _human_individuals.size() dopo una rimozione
# (Step 6) — HumanPopulationInfoPanel.show_population riceve i due dati separatamente, mai
# ricalcolato da _human_individuals.size() al volo.
var _human_population_group: HumanPopulationGroup


# Connessione UNA TANTUM (richiesta utente, 2026-09-05) — chiamata da GameScene._setup_clock
# subito dopo clock.day_advanced.connect(...), stesso punto di inizializzazione, nessun registry
# dedicato esiste ancora nel progetto per questo scopo (vedi ricognizione).
#
# human_individuals/human_folk (Step 5 del piano mortalità): servono per agganciare
# HumanMortalityIndividualService.check_mortality a year_rolled_over — vedi _on_year_rolled_over
# sotto. human_population_group (Step 6): serve per tenere total_count allineato dopo una
# rimozione reale — vedi _apply_scheduled_human_deaths.
func connect_to_clock(
	clock: GameClockController,
	game_data: GameData,
	human_individuals: Array[HumanIndividual],
	human_folk: Folk,
	human_population_group: HumanPopulationGroup,
	world: World,
	individual_action_service: HumanIndividualActionService
) -> void:
	_game_data = game_data
	_human_individuals = human_individuals
	_human_folk = human_folk
	_human_population_group = human_population_group
	_world = world
	_individual_action_service = individual_action_service
	clock.day_advanced.connect(_on_day_advanced)
	clock.year_rolled_over.connect(_on_year_rolled_over)
	clock.season_ended.connect(_on_season_ended)


# Step 6 del piano mortalità (2026-09-05): stesso hook giornaliero già esistente usato da
# GameScene._on_day_advanced per vegetazione/eventi — riusato qui, non un nuovo aggancio, stesso
# principio già seguito per year_rolled_over allo Step 5. checkpoint_ran/animals_changed non
# servono a questa applicazione (le morti programmate non dipendono da nessuno dei due), quindi
# ignorati.
func _on_day_advanced(_checkpoint_ran: bool, _animals_changed: bool) -> void:
	_apply_scheduled_human_deaths()
	# Validazione giornaliera dei figli a carico (2026-09-19, richiesta utente) - PRIMA del ricalcolo della
	# stamina, cosi' il malus del figlio a carico sparisce lo stesso giorno in cui il figlio esce da INFANT
	# o muore (le morti programmate sono gia' state applicate sopra).
	_validate_daily_dependent_children()
	_recalculate_daily_max_stamina()
	_recalculate_daily_carry_capacity()
	_recalculate_daily_vitals()
	# Morte per fame (2026-09-19, richiesta utente): dopo il consumo calorico del giorno, che aggiorna
	# body_calories.
	_apply_daily_starvation()
	_log_daily_food_need()
	_apply_daily_vitals_interaction()
	_advance_daily_individual_resource_decay()
	# Ritentativo giornaliero fabbisogno materiale (2026-09-14, richiesta utente) — INCONDIZIONATO,
	# stesso principio "periodico" di ogni _recalculate_daily_*/_advance_daily_* sopra. Vedi
	# HumanIndividualActionService.retry_blocked_material_shortages per il dettaglio/il perché.
	_individual_action_service.retry_blocked_material_shortages(_world, _human_individuals)
	# Pulizia temporale del registro debug 🐞 (2026-09-13, richiesta utente: "le interrotte o
	# completate cancellale dopo 2gg") — INCONDIZIONATO, stesso principio delle altre
	# _recalculate_daily_*/_advance_daily_* sopra: TaskDebugRegistry.on_day_advanced aggiorna il
	# giorno assoluto noto al registro (per stampare correttamente closed_at_absolute_day sulle
	# entry che si chiuderanno OGGI) e rimuove le entry COMPLETED/INTERRUPTED già scadute.
	TaskDebugRegistry.on_day_advanced(_game_data.get_absolute_day())
	# Step 4 del sistema oggetti-scaduti (2026-09-05): giorno 10 fisso, non year_rolled_over (per
	# non sommarsi alle altre operazioni che già girano lì, richiesta utente) — nessun nuovo
	# contatore/segnale, solo una condizione sul giorno corrente già disponibile in questo tick.
	# Indagine preliminare (richiesta utente): WorldTimeService._clear_natural_death_markers usa un
	# meccanismo DIVERSO (checkpoint stagionale via _run_seasonal_checkpoints/SeasonCalculator, non
	# un semplice "if giorno == X" dentro un tick giornaliero) — non pertinente da riusare qui, si
	# segue invece il pattern esplicito richiesto.
	if _game_data.current_day == 10:
		_cleanup_expired_objects()
	# Step 3 del piano coupling (2026-09-05): giorno 15 fisso, stesso pattern/motivazione del
	# giorno 10 sopra (un contatore/checkpoint dedicato sarebbe overkill per un singolo "if giorno
	# == X" annuale) — ma un blocco `if` A SÉ, non annidato/fuso con quello del giorno 10 (richiesta
	# esplicita utente): sono due operazioni indipendenti che capitano solo a coincidere sullo
	# stesso hook giornaliero, non un'unica condizione composta. Giorno 15, non giorno 0
	# (year_rolled_over, dove gira già la mortalità): lascia che l'anno sia già "rotolato" e l'età
	# di tutti già coerente con year corrente prima di valutare FERTILE_ADULT per il pool.
	if _game_data.current_day == 15:
		_run_annual_human_coupling()
	# Step 3 del piano riproduzione (2026-09-06): giorno 110 fisso, stesso pattern/motivazione dei
	# blocchi giorno 10/15 sopra — blocco `if` A SÉ, indipendente, non annidato/fuso con nessuno
	# degli altri tre.
	if _game_data.current_day == 110:
		_run_annual_human_conception()
	# Step 1 del piano parto (2026-09-06): giorno 20 fisso, stesso pattern/motivazione dei blocchi
	# giorno 10/15/110 sopra — blocco `if` A SÉ, indipendente, non annidato/fuso con nessuno degli
	# altri tre. Verificato libero (nessun altro blocco su questo giorno). ~9 mesi dopo il
	# concepimento del day 110 dell'ANNO PRECEDENTE (110 -> fine anno -> 20 del nuovo anno).
	if _game_data.current_day == 20:
		_run_annual_human_births()


# Ricalcolo giornaliero di HumanIndividual.max_stamina per l'INTERA popolazione (2026-09-06,
# richiesta utente) — INCONDIZIONATO, nessun `if _game_data.current_day == X` (a differenza dei
# blocchi annuali sotto/sopra): stesso stile di _apply_scheduled_human_deaths in cima a questo
# handler, che gira ogni giorno senza condizioni.
#
# SOLUZIONE TEMPORANEA (richiesta utente, 2026-09-06) — periodica (una volta al giorno, per OGNI
# individuo) invece che event-driven (solo quando qualcosa che influenza max_stamina cambia
# davvero: inizio/fine gravidanza, figlio a carico assegnato/rimosso, cambio age_band). Vedi il
# commento di testa a HumanStaminaIndividualService.recalculate_max_stamina per il perché: il
# progetto non ha oggi nessun meccanismo generale per rilevare questi cambi di stato. Da rivedere
# quando servirà un sistema più granulare (evento-driven invece che periodico) — questo passo si
# limita a garantire che max_stamina non resti mai stantio più di un giorno di gioco.
#
# era_rules risolto UNA VOLTA qui (non per ogni individuo dentro il ciclo) — stesso principio già
# seguito da _run_annual_human_conception/_run_annual_human_births: non cambia da un individuo
# all'altro nello stesso giorno, ricalcolarlo N volte sarebbe lavoro ripetuto inutile (anche se
# EraCalculator.get_era_rules è già cachato da Godot via load(), quindi il costo reale sarebbe
# comunque basso — resta comunque il pattern corretto per coerenza col resto del file).
#
# Log diretto (non un accumulatore come HumanIndividualView._process): gira una volta al giorno,
# non ad alta frequenza per-frame, quindi una riga per ricalcolo resta leggibile senza necessità di
# sommare su una finestra di tempo.
func _recalculate_daily_max_stamina() -> void:
	if _human_individuals.is_empty():
		return
	var era_rules := EraCalculator.get_era_rules(_game_data.current_era_name)
	var start_usec := Time.get_ticks_usec()
	for individual in _human_individuals:
		HumanStaminaIndividualService.recalculate_max_stamina(individual, _game_data, era_rules, _world)
	if not DebugLogging.ENABLED or not DebugLogging.SHOW_STAMINA_RECALC_LOGS:
		return
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	print("[HUMAN STAMINA RECALC] anno=%d giorno=%d: %d individui ricalcolati in %.3f ms" % [
		_game_data.year, _game_data.current_day, _human_individuals.size(), elapsed_ms
	])


# Validazione giornaliera di HumanIndividual.dependent_child_id per l'INTERA popolazione (2026-09-19,
# richiesta utente - bugfix: prima il riferimento veniva azzerato SOLO da GameScene._sync_dependent_
# child_position, che gira solo per gli individui con una Task attiva, quindi una madre ferma teneva
# il malus di stamina del figlio a carico anche dopo che il figlio aveva superato la fascia INFANT):
# se dependent_child_id != -1 e il figlio non esiste piu' (non e' in _human_individuals) o non e' piu'
# INFANT (stessa formula di GameScene._resolve_age_band), lo azzera. _sync_dependent_child_position
# resta com'e' per la posizione del figlio. Una sola mappa id -> individuo per giorno (O(N)), non una
# ricerca lineare per madre.
func _validate_daily_dependent_children() -> void:
	var individuals_by_id: Dictionary = {}
	var has_dependent_child := false
	for individual in _human_individuals:
		individuals_by_id[individual.id] = individual
		if individual.dependent_child_id != -1:
			has_dependent_child = true
	if not has_dependent_child:
		return
	for mother in _human_individuals:
		if mother.dependent_child_id == -1:
			continue
		var child: HumanIndividual = individuals_by_id.get(mother.dependent_child_id)
		if child == null:
			mother.dependent_child_id = -1
			continue
		var child_age := float(_game_data.year - child.birth_year_virtual)
		var child_age_band := HumanCalculator.get_age_band(
			_game_data.era_effective_age_band_durations_male, _game_data.era_effective_age_band_durations_female,
			child.sex, child_age
		)
		if child_age_band != HumanTypes.AgeBand.INFANT:
			mother.dependent_child_id = -1


# Log giornaliero del bisogno di PROVVISTE (2026-09-19, richiesta utente): dietro
# DebugLogging.SHOW_FOOD_NEED_LOGS, per l'UNICO individuo FOOD_NEED_LOG_INDIVIDUAL_ID. E' l'unica
# chiamata a HumanIndividualActionService._resolve_active_food_need_priority: solo lettura, nessuna
# Task e nessun interrupt. Chiamata dopo _recalculate_daily_vitals, cioe' dopo il consumo calorico
# del giorno (le calorie stampate sono quelle residue). Consumo e autonomia sono ricalcolati qui solo
# per la riga di log, con la stessa formula della funzione.
func _log_daily_food_need() -> void:
	if not DebugLogging.ENABLED or not DebugLogging.SHOW_FOOD_NEED_LOGS:
		return
	for individual in _human_individuals:
		if individual.id != DebugLogging.FOOD_NEED_LOG_INDIVIDUAL_ID:
			continue
		var human_rules: HumanRules = null
		if individual.source_group_ref != null and individual.source_group_ref.folk_ref != null:
			human_rules = individual.source_group_ref.folk_ref.human_rules_ref
		if human_rules == null:
			return
		var era_rules := EraCalculator.get_era_rules(_game_data.current_era_name)
		var age := float(_game_data.year - individual.birth_year_virtual)
		var age_band := HumanCalculator.get_age_band(
			_game_data.era_effective_age_band_durations_male, _game_data.era_effective_age_band_durations_female,
			individual.sex, age
		)
		var daily_consumption: float = HumanCalculator.get_daily_calorie_consumption(
			human_rules, age_band, individual.sex, individual.dependent_child_id != -1, era_rules
		)
		var autonomy_text := "infinita"
		if daily_consumption > 0.0:
			autonomy_text = "%.2f" % (individual.food_calories_held / daily_consumption)
		var priority: int = HumanIndividualActionService._resolve_active_food_need_priority(
			individual, human_rules, age_band, individual.sex, era_rules
		)
		print("[FOOD NEED DEBUG] anno=%d giorno=%d #%d calorie=%.3f consumo_giornaliero=%.3f autonomia_giorni=%s priorita=%d" % [
			_game_data.year, _game_data.current_day, individual.id, individual.food_calories_held,
			daily_consumption, autonomy_text, priority
		])
		return


# Ricalcolo giornaliero di HumanIndividual.max_carry_capacity per l'INTERA popolazione (2026-09-08,
# richiesta utente) — stesso identico pattern/motivazione di _recalculate_daily_max_stamina sopra
# (INCONDIZIONATO, periodico non event-driven, log diretto una riga per ricalcolo): vedi quel
# commento per il perché. Nessun era_rules qui (a differenza di _recalculate_daily_max_stamina):
# HumanCarryCapacityIndividualService.recalculate_max_carry_capacity non ne ha bisogno, la
# capacità di trasporto non ha un ramo gravidanza/figlio-a-carico come la stamina.
func _recalculate_daily_carry_capacity() -> void:
	if _human_individuals.is_empty():
		return
	var start_usec := Time.get_ticks_usec()
	for individual in _human_individuals:
		HumanCarryCapacityIndividualService.recalculate_max_carry_capacity(individual, _game_data)
	if not DebugLogging.ENABLED or not DebugLogging.SHOW_CARRY_CAPACITY_RECALC_LOGS:
		return
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	print("[HUMAN CARRY CAPACITY RECALC] anno=%d giorno=%d: %d individui ricalcolati in %.3f ms" % [
		_game_data.year, _game_data.current_day, _human_individuals.size(), elapsed_ms
	])


# Ricalcolo giornaliero dei 5 nuovi parametri vitali (hunger/thirst/health/happiness/loyalty) per
# l'INTERA popolazione (2026-09-13, richiesta utente) — stesso identico pattern/motivazione di
# _recalculate_daily_max_stamina/_recalculate_daily_carry_capacity sopra (INCONDIZIONATO,
# periodico non event-driven, log diretto una riga per ricalcolo): vedi quel commento per il
# perché. UN SOLO service consolidato per tutti e 5 (HumanVitalsIndividualService.recalculate_
# vitals, non 5 service separati) — vedi quel file per il perché. Nessun era_rules qui, stesso
# motivo di _recalculate_daily_carry_capacity: nessuno dei 5 nuovi get_max_* ha un ramo
# gravidanza/figlio-a-carico.
func _recalculate_daily_vitals() -> void:
	if _human_individuals.is_empty():
		return
	var start_usec := Time.get_ticks_usec()
	var era_rules := EraCalculator.get_era_rules(_game_data.current_era_name)
	for individual in _human_individuals:
		HumanVitalsIndividualService.recalculate_vitals(individual, _game_data)
		# Consumo calorico giornaliero della saccoccia (2026-09-19, richiesta utente): stesso ciclo, quindi
		# per l'INTERA popolazione e non solo per chi ha una task attiva. Dopo il ricalcolo della capacita'
		# (_recalculate_daily_carry_capacity, chiamata prima nello stesso tick).
		if HumanVitalsIndividualService.apply_daily_calorie_consumption(individual, _game_data, era_rules):
			individual_started_body_reserve.emit(individual)
	if not DebugLogging.ENABLED or not DebugLogging.SHOW_VITALS_RECALC_LOGS:
		return
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	print("[HUMAN VITALS RECALC] anno=%d giorno=%d: %d individui ricalcolati in %.3f ms" % [
		_game_data.year, _game_data.current_day, _human_individuals.size(), elapsed_ms
	])


# Interazione GIORNALIERA fra i 5 parametri vitali per l'INTERA popolazione (2026-09-13, richiesta
# utente) — SUBITO DOPO _recalculate_daily_vitals sopra nello stesso tick (ordine esplicito
# richiesto: 1° max/clamp esistente, 2° questa interazione), così le due regole di
# HumanVitalsInteractionService.apply_daily_interaction leggono max_stamina/max_happiness e
# current_happiness/current_loyalty già coerenti con l'era/age_band e già clampati per OGGI, non
# dati stantii di ieri. Stesso pattern INCONDIZIONATO/periodico/log diretto delle altre
# _recalculate_daily_* sopra.
func _apply_daily_vitals_interaction() -> void:
	if _human_individuals.is_empty():
		return
	for individual in _human_individuals:
		HumanVitalsInteractionService.apply_daily_interaction(individual)


# Avanzamento giornaliero della decay_fraction di ogni varietà di HumanIndividual.carried_resources per l'INTERA popolazione
# (2026-09-09, richiesta utente, Step 3 decadimento) — stesso identico pattern/motivazione di
# _recalculate_daily_max_stamina/_recalculate_daily_carry_capacity sopra (INCONDIZIONATO, periodico,
# stessa cadenza giornaliera): ResourceDecayService.advance_individual_decay stessa già no-op per
# zaino vuoto/risorsa non deperibile, nessun filtro aggiuntivo necessario qui. Emette
# individual_resource_decayed una volta per ogni varietà deperita (l'Array di ritorno; una perdita reale
# oggi) — il caso comune (nulla deperisce quel giorno) non emette mai nulla.
func _advance_daily_individual_resource_decay() -> void:
	if _human_individuals.is_empty():
		return
	for individual in _human_individuals:
		# Una emissione per varietà deperita (zaino multi-risorsa, 2026-09-20).
		for lost in ResourceDecayService.advance_individual_decay(individual):
			individual_resource_decayed.emit(individual, lost["resource_name"], lost["quantity"])


# Step 4 del sistema oggetti-scaduti (2026-09-05): rimuove da game_data.expired_objects i record
# scaduti secondo ExpiredObjectCalculator.is_expired, valutati contro le ExpiredObjectRules del
# proprio object_type (get_object_rules — null e quindi skip se un futuro tipo non avesse ancora
# un .tres). Iterazione ALL'INDIETRO con remove_at, stesso idioma già usato per
# _apply_scheduled_human_deaths. SOLO pulizia del dato — nessun rendering/view toccati qui (la
# rappresentazione visiva, incluso far smettere di disegnare un corpo scaduto anche PRIMA che
# l'array venga fisicamente ripulito qui, resta un passo a parte).
func _cleanup_expired_objects() -> void:
	var removed_count := 0
	var i := _game_data.expired_objects.size() - 1
	while i >= 0:
		var record: Dictionary = _game_data.expired_objects[i]
		var rules := ExpiredObjectCalculator.get_object_rules(record["object_type"])
		if rules != null and ExpiredObjectCalculator.is_expired(record, rules, _game_data.year, _game_data.current_day):
			_game_data.expired_objects.remove_at(i)
			removed_count += 1
		i -= 1
	# "Always announce" come [HUMAN MORTALITY] (richiesta utente) — stampa anche "0 rimossi", non
	# solo quando succede qualcosa (a differenza di [HUMAN DEATH]/[DEAD BODY LOG], che loggano solo
	# eventi reali).
	if DebugLogging.ENABLED:
		print("[EXPIRED OBJECTS CLEANUP] anno=%d, giorno=%d: %d record rimossi (rimasti: %d)" % [
			_game_data.year, _game_data.current_day, removed_count, _game_data.expired_objects.size()
		])


# Step 3 del piano coupling (2026-09-05): formazione coppie FERTILE_ADULT/senza-partner, chiamata
# da _on_day_advanced sopra al giorno 15 fisso. Stessa fonte di durate EFFETTIVE (scalate per Era)
# già passata a check_mortality in _run_annual_human_mortality_determination sotto — un solo posto
# di verità per età/age_band, mai due fonti diverse nello stesso anno.
func _run_annual_human_coupling() -> void:
	if _human_individuals.is_empty():
		return
	var durations_male := _game_data.era_effective_age_band_durations_male
	var durations_female := _game_data.era_effective_age_band_durations_female
	var formed := HumanCouplingIndividualService.form_couples(
		_human_individuals, _game_data.year, durations_male, durations_female
	)
	if not DebugLogging.ENABLED or not DEBUG_LOG_COUPLING:
		return
	if formed.is_empty():
		print("[HUMAN COUPLING] anno=%d: nessuna nuova coppia formata" % _game_data.year)
		return
	var details: Array[String] = []
	for pair in formed:
		var a: HumanIndividual = pair["a"]
		var b: HumanIndividual = pair["b"]
		details.append("#%d %s + #%d %s" % [a.id, a.name, b.id, b.name])
	print("[HUMAN COUPLING] anno=%d: %d coppie formate -> %s" % [
		_game_data.year, formed.size(), ", ".join(details)
	])


# Step 3 del piano riproduzione (2026-09-06): concepimento (SOLO concepimento, nessun parto)
# FERTILE_ADULT/FERTILE_ADULT senza figlio sotto soglia, chiamata da _on_day_advanced sopra al
# giorno 110 fisso. Stessa fonte di durate EFFETTIVE già passata a check_mortality/form_couples —
# un solo posto di verità per età/age_band. era_rules risolto qui da EraCalculator.get_era_rules
# (stesso canale già esistente usato per la cache delle durate in GameData.set_current_era) — MAI
# un nuovo canale di cache per le probabilità scalari di Reproduction, verificato con l'utente
# 2026-09-06: qui basta una singola moltiplicazione scalare fatta al momento in
# HumanConceptionIndividualService, non serve nulla di pre-calcolato.
#
# Log "[HUMAN CONCEPTION]" NON dietro DEBUG_LOG_* (richiesta utente): è il log nuovo che serve
# vedere, a differenza dei due riepiloghi esistenti sopra appena nascosti. Include il tempo (ms)
# della sola fase di query "figli sotto soglia" per l'intero gruppo — richiesta utente, verifica
# empirica del costo invece di darlo per scontato.
#
# Log ESPLICATIVO (richiesta utente, 2026-09-06) — non solo il conteggio finale: mostra ogni fase
# della cascata (A: idonee -> B: scartate per spaziamento, CON la soglia in anni -> C: candidate al
# tiro, CON probabilità ed esito OK/NO per ciascuna -> concepimenti finali), così è chiaro dove
# "si perdono" le donne che sembravano poter concepire ma non l'hanno fatto. Ogni segmento con
# lista vuota viene omesso dai dettagli (mai "0 scartate: " senza nulla dopo), tranne il primo
# (idonee) e l'ultimo (concepimenti), sempre presenti anche a zero — sono i due estremi della
# cascata, utili anche quando non c'è nulla in mezzo da mostrare.
func _run_annual_human_conception() -> void:
	if _human_folk == null or _human_folk.human_rules_ref == null or _human_individuals.is_empty():
		return
	var era_rules := EraCalculator.get_era_rules(_game_data.current_era_name)
	if era_rules == null:
		return
	var durations_male := _game_data.era_effective_age_band_durations_male
	var durations_female := _game_data.era_effective_age_band_durations_female
	var result := HumanConceptionIndividualService.run_conception(
		_human_individuals, _game_data.year, durations_male, durations_female,
		_human_folk.human_rules_ref, era_rules
	)
	var query_time_ms: float = result["query_time_usec"] / 1000.0
	if not DebugLogging.ENABLED:
		return
	var eligible_women: Array[HumanIndividual] = result["eligible_women"]
	var excluded_already_pregnant: Array[HumanIndividual] = result["excluded_already_pregnant"]
	var excluded_self_not_fertile: Array[HumanIndividual] = result["excluded_self_not_fertile"]
	var excluded_partner_not_fertile: Array[HumanIndividual] = result["excluded_partner_not_fertile"]
	var excluded_partner_missing: Array[HumanIndividual] = result["excluded_partner_missing"]
	var discarded_for_spacing: Array[HumanIndividual] = result["discarded_for_spacing"]
	var candidates: Array[HumanIndividual] = result["candidates"]
	var newly_pregnant: Array[HumanIndividual] = result["newly_pregnant"]
	var min_birth_spacing_years: int = result["min_birth_spacing_years"]
	var conception_probability: float = result["conception_probability"]

	# Stage fase (A) — "coppie totali" (richiesta utente, 2026-09-06: sapere anche QUANTE coppie
	# esistevano prima di qualunque esclusione, non solo il risultato "idonee") + "escluse", con
	# motivo per ciascuna (già incinta / lei non più fertile / partner non più fertile / partner
	# introvabile — quest'ultimo un caso difensivo, non dovrebbe capitare). SEMPRE presenti, anche
	# a zero escluse (stesso principio di "scartate per spaziamento" sotto: l'assenza di uno stage
	# si legge come "controllo non fatto", non come "zero", quindi vanno mostrati comunque).
	var excluded_total := (
		excluded_already_pregnant.size() + excluded_self_not_fertile.size()
		+ excluded_partner_not_fertile.size() + excluded_partner_missing.size()
	)
	var total_couples := eligible_women.size() + excluded_total
	var excluded_details: Array[String] = []
	for woman in excluded_already_pregnant:
		excluded_details.append("#%d %s (già incinta)" % [woman.id, woman.name])
	for woman in excluded_self_not_fertile:
		excluded_details.append("#%d %s (lei non più fertile)" % [woman.id, woman.name])
	for woman in excluded_partner_not_fertile:
		excluded_details.append("#%d %s (partner non più fertile)" % [woman.id, woman.name])
	for woman in excluded_partner_missing:
		excluded_details.append("#%d %s (partner introvabile)" % [woman.id, woman.name])

	# Stage "scartate per spaziamento" SEMPRE presente, anche a zero (richiesta utente, 2026-09-06 —
	# la sua ASSENZA veniva letta come "il controllo non è stato fatto", non come "0 scartate":
	# a differenza degli altri stage, questo è un controllo che gira comunque su ogni idonea, quindi
	# va confermato esplicitamente anche quando non scarta nessuno). Solo l'elenco nomi resta
	# condizionato (mai ": " seguito da nulla).
	var stages: Array[String] = []
	stages.append("%d coppie totali" % total_couples)
	stages.append(
		"%d escluse per fertilità/gravidanza%s" % [
			excluded_total, (": " + ", ".join(excluded_details)) if excluded_total > 0 else ""
		]
	)
	stages.append("%d donne idonee (coppia FERTILE_ADULT)" % eligible_women.size())
	stages.append(
		"%d scartate per figlio sotto soglia (soglia<=%d anni)%s" % [
			discarded_for_spacing.size(), min_birth_spacing_years,
			(": " + _format_individuals(discarded_for_spacing)) if not discarded_for_spacing.is_empty() else ""
		]
	)
	if not candidates.is_empty():
		var candidate_details: Array[String] = []
		for woman in candidates:
			candidate_details.append("#%d %s %s" % [woman.id, woman.name, "OK" if newly_pregnant.has(woman) else "NO"])
		stages.append("%d candidate al tiro (prob=%.1f%%): %s" % [
			candidates.size(), conception_probability * 100.0, ", ".join(candidate_details)
		])
	stages.append(
		"%d concepimenti" % newly_pregnant.size()
		if newly_pregnant.is_empty() else
		"%d concepimenti: %s" % [newly_pregnant.size(), _format_individuals(newly_pregnant)]
	)
	print("[HUMAN CONCEPTION] anno=%d: %s (query figli-sotto-soglia: %.3f ms)" % [
		_game_data.year, " -> ".join(stages), query_time_ms
	])


# Formatta una lista di HumanIndividual come "#id nome, #id nome, ..." — stesso formato compatto
# già usato in tutti i log di questo file (HUMAN COUPLING/HUMAN BIRTH/ecc.), estratto qui perché
# _run_annual_human_conception sopra lo ripete tre volte (idonee scartate, candidate, concepimenti).
func _format_individuals(individuals: Array[HumanIndividual]) -> String:
	var details: Array[String] = []
	for individual in individuals:
		details.append("#%d %s" % [individual.id, individual.name])
	return ", ".join(details)


# Risoluzione annuale delle gravidanze (vedi HumanBirthIndividualService per la logica di
# dettaglio — hair_color/skin_color/father_id vengono SOLO da pending_child_*, mai da un nuovo
# tiro o da woman.partner_id), chiamata da _on_day_advanced sopra al giorno 20 fisso. Nessun tiro
# sesso pesato (50/50 puro, confermato). Effetto nato-morto (tiro sopravvivenza figlio) ed effetto
# morte materna (tiro sopravvivenza madre, 2026-09-06) sono entrambi ORA reali e completamente
# indipendenti l'uno dall'altro — vedi il ciclo su birth_results sotto.
#
# total_count (stesso trattamento di _apply_scheduled_human_deaths, che lo tiene allineato dopo
# una RIMOZIONE): qui va tenuto allineato dopo un'AGGIUNTA — ricalcolato da
# _human_individuals.size(), non incrementato a mano, stessa formula. individual_born emesso DOPO
# che il neonato è già in _human_individuals (append fatto dentro HumanBirthIndividualService
# stesso, array condiviso per riferimento) — GameScene crea la view in risposta.
#
# Log "[HUMAN BIRTH]" NON dietro DEBUG_LOG_* (richiesta utente, stesso trattamento di
# "[HUMAN CONCEPTION]" sopra): è il log nuovo che serve vedere — resta comunque dietro
# DebugLogging.ENABLED come tutti gli altri log di questo file.
func _run_annual_human_births() -> void:
	if _human_individuals.is_empty():
		return
	if _human_folk == null or _human_folk.human_rules_ref == null:
		return
	var era_rules := EraCalculator.get_era_rules(_game_data.current_era_name)
	if era_rules == null:
		return
	var result := HumanBirthIndividualService.run_births(
		_human_individuals, _game_data, _human_folk.human_rules_ref, era_rules
	)
	# birth_results: un elemento per OGNI gravidanza risolta (successo O nato-morto), non più tre
	# array paralleli — vedi HumanBirthIndividualService.run_births per il perché del cambio.
	var birth_results: Array[Dictionary] = result["birth_results"]
	if birth_results.is_empty():
		if DebugLogging.ENABLED:
			print("[HUMAN BIRTH] anno=%d: nessuna gravidanza da risolvere" % _game_data.year)
		return
	if _human_population_group != null:
		_human_population_group.total_count = _human_individuals.size()
	# individual_born per i nati VIVI, human_stillbirth per i nati morti (entry["newborn"] == null
	# — vedi HumanBirthIndividualService._run_births_in_group) — Step 2 dell'effetto nato-morto,
	# 2026-09-06. Effetto morte materna (STEP 2/3, 2026-09-06): DOPO il segnale sul figlio (nato
	# vivo o nato-morto, comunque già risolto), se il tiro sopravvivenza-madre è fallito risolviamo
	# PRIMA la custodia dell'eventuale figlio a carico (_transfer_or_orphan_dependent_child, deve
	# girare mentre mother.dependent_child_id è ancora leggibile e PRIMA che _kill_individual la
	# rimuova) e SOLO DOPO chiamiamo la pipeline di morte esistente, riusata as-is: rimozione da
	# _human_individuals, death_events, notifica popup (già generica, userà "death_cause_
	# childbirth"), azzeramento partner_id del padre superstite (_free_partner_if_any, invariato —
	# evento separato da dependent_child_id, entrambi si applicano). mother_index ricalcolato FRESCO
	# per ogni morte (mai un indice cacheato): se più madri muoiono nello stesso anno, ogni
	# _kill_individual precedente ha già spostato gli indici di chi viene dopo nell'array.
	for entry in birth_results:
		var mother: HumanIndividual = entry["mother"]
		var newborn: HumanIndividual = entry["newborn"]
		if newborn != null:
			individual_born.emit(newborn)
		else:
			human_stillbirth.emit(mother)
		var roll: Dictionary = entry["survival_roll"]
		if not roll["mother_survived_roll"]:
			# La custodia del figlio a carico passa ora da _kill_individual (a OGNI morte, qualunque causa).
			var mother_index := _human_individuals.find(mother)
			if mother_index != -1:
				var mother_age_at_death := _game_data.year - mother.birth_year_virtual
				_kill_individual(
					mother, mother_index, DeathTypes.DeathCause.CHILDBIRTH, _game_data.current_day, mother_age_at_death
				)
	# Stesso motivo/meccanismo di _apply_scheduled_human_deaths: la scheda 👨‍👩‍👧 mostra
	# total_count, appena cambiato sopra — senza questo resterebbe coi dati vecchi fino al
	# prossimo rollover d'anno. _kill_individual (se chiamata sopra) lo aggiorna già da sé ad ogni
	# morte materna, questo emit resta comunque necessario per il caso "solo nascite, nessuna
	# morte materna quest'anno".
	human_population_changed.emit()
	if not DebugLogging.ENABLED:
		return
	# "sopravvivenza_figlio" e "sopravvivenza_madre" hanno ORA ENTRAMBI un effetto reale (STEP 3
	# effetto nato-morto + STEP 3 effetto morte materna, 2026-09-06): un fallimento del primo
	# produce un nato-morto (nessun #id/nome, l'individuo non è mai stato creato); un fallimento
	# del secondo aggiunge "MADRE DECEDUTA (causa: parto)" alla riga, indipendentemente dall'esito
	# del figlio (i due tiri restano completamente slegati, come da progetto).
	var details: Array[String] = []
	for entry in birth_results:
		var mother: HumanIndividual = entry["mother"]
		var newborn: HumanIndividual = entry["newborn"]
		var roll: Dictionary = entry["survival_roll"]
		var mother_roll_text := "SUCCESSO" if roll["mother_survived_roll"] else "FALLIMENTO"
		var mother_outcome_suffix := "" if roll["mother_survived_roll"] else " | MADRE DECEDUTA (causa: parto)"
		if newborn != null:
			details.append(
				"#%d %s -> #%d %s (padre #%d) [sopravvivenza_figlio: %.1f%% -> SUCCESSO, sopravvivenza_madre: %.1f%% -> %s]%s" % [
					mother.id, mother.name, newborn.id, newborn.name, newborn.father_id,
					roll["child_survival_probability"] * 100.0,
					roll["mother_survival_probability"] * 100.0, mother_roll_text,
					mother_outcome_suffix,
				]
			)
		else:
			details.append(
				"#%d %s -> NATO MORTO [sopravvivenza_figlio: %.1f%% -> FALLIMENTO, sopravvivenza_madre: %.1f%% -> %s]%s" % [
					mother.id, mother.name,
					roll["child_survival_probability"] * 100.0,
					roll["mother_survival_probability"] * 100.0, mother_roll_text,
					mother_outcome_suffix,
				]
			)
	print("[HUMAN BIRTH] anno=%d: %d esiti -> %s" % [
		_game_data.year, birth_results.size(), ", ".join(details)
	])


func _on_year_rolled_over() -> void:
	print("GameTimeService: nuovo anno, year=%d" % _game_data.year)
	# Step 3 del piano statistiche (2026-09-06) — snapshot annuale della popolazione umana totale,
	# per il futuro grafico popolazione/anno del pannello statistiche: non ricavabile in modo
	# affidabile dai soli death_events/birth_events (dipenderebbe dal numero di fondatori iniziali
	# restare sempre corretto, fragile con un'eventuale futura immigrazione), quindi un log
	# dedicato, un punto per anno. Qui, non dentro _run_annual_human_mortality_determination sotto:
	# vogliamo la popolazione COSÌ COM'È all'inizio dell'anno (year già incrementato da
	# GameData.advance_day prima che questo segnale scattasse), prima che qualunque logica di
	# quest'anno (determinazione mortalità, coupling, concepimento, parto) la tocchi.
	_game_data.population_snapshots[_game_data.year] = _human_individuals.size()
	_run_annual_human_mortality_determination()


# Step 5 del piano mortalità (2026-09-05): determinazione + assegnazione scheduled_death_day
# annuale sulla popolazione umana REALE — prima di questo step girava solo isolatamente sui dati
# fittizi di res://tools/mortality_test/.
#
# Gira SOLO sulla popolazione a piena simulazione: oggi _human_individuals È già solo quella (un
# solo Folk/insediamento esiste nel progetto, nessuna rappresentazione aggregata "lontana" per gli
# umani ancora — a differenza degli animali non c'è un secondo livello da filtrare qui). Quando in
# futuro esisterà un equivalente umano del LOD animale (popolazioni umane rappresentate solo in
# forma aggregata), questo metodo andrà limitato ai soli individui a piena simulazione, stesso
# principio già seguito da WorldTimeService per gli animali (Livello 2 vs aggregato Livello 1).
func _run_annual_human_mortality_determination() -> void:
	if _human_folk == null or _human_folk.human_rules_ref == null or _human_individuals.is_empty():
		return
	# Durate EFFETTIVE (scalate per Era corrente), non le durate BASE di HumanRules — bugfix,
	# richiesta utente, 2026-09-05: prima il gate age_band e la curva di probabilità leggevano
	# rules.age_band_durations_male/female direttamente, ignorando EraRules.
	# longevity_multiplier_by_age — un individuo poteva risultare ancora FERTILE_ADULT/MATURE_ADULT
	# qui mentre i pannelli (che già usavano game_data.era_effective_age_band_durations_male/female)
	# lo mostravano OLD. Stessa fonte già usata da GameScene per i pannelli, un solo posto di verità.
	var durations_male := _game_data.era_effective_age_band_durations_male
	var durations_female := _game_data.era_effective_age_band_durations_female
	# DIAGNOSTICO TEMPORANEO (richiesta utente, 2026-09-05 — verifica numeri reali invece di
	# continuare a supporre): stampa età/age_band/probabilità calcolata per OGNI individuo (non
	# solo i marcati), PRIMA della determinazione vera e propria. Da rimuovere quando non serve
	# più.
	if DebugLogging.ENABLED:
		for individual in _human_individuals:
			var age := _game_data.year - individual.birth_year_virtual
			var age_band := HumanCalculator.get_age_band(durations_male, durations_female, individual.sex, float(age))
			var probability := HumanCalculator.get_annual_death_probability(
				age, _human_folk.human_rules_ref, durations_male, durations_female
			)
			print("[HUMAN MORTALITY DEBUG] #%d %s eta'=%d age_band=%s probabilita'=%.4f" % [
				individual.id, individual.name, age, HumanTypes.AgeBand.keys()[age_band], probability
			])
	var marked := HumanMortalityIndividualService.check_mortality(
		_human_individuals, _human_folk.human_rules_ref, _game_data.year, durations_male, durations_female
	)
	if not DebugLogging.ENABLED or not DEBUG_LOG_MORTALITY:
		return
	if marked.is_empty():
		print("[HUMAN MORTALITY] anno=%d: nessun individuo marcato per morire" % _game_data.year)
		return
	var details: Array[String] = []
	for individual in marked:
		details.append("#%d %s (giorno %d)" % [individual.id, individual.name, individual.scheduled_death_day])
	print("[HUMAN MORTALITY] anno=%d: %d individui marcati per morire quest'anno -> %s" % [
		_game_data.year, marked.size(), ", ".join(details)
	])


# Step 6 del piano mortalità (2026-09-05): applicazione REALE delle morti programmate dallo
# Step 5 (HumanIndividual.scheduled_death_day) — rimozione da _human_individuals/allineamento
# di total_count, pulizia partner_id del coniuge superstite (vedi _free_partner_if_any sotto).
#
# Step 9 (2026-09-05): il corpo per-singolo-individuo è stato estratto in _kill_individual sotto —
# condiviso con kill_individual_now (morte immediata di debug, causa MURDER, mai passa da
# scheduled_death_day). Comportamento del percorso OLD_AGE qui INVARIATO, solo il codice è ora
# condiviso invece che duplicato.
#
# Iterazione ALL'INDIETRO (mai un for in avanti su un Array da cui si rimuove durante lo scorso:
# remove_at farebbe scalare tutto di una posizione, saltando l'elemento successivo) — stesso
# idioma già in uso altrove nel progetto per rimozioni in-place da un Array scorso linearmente.
func _apply_scheduled_human_deaths() -> void:
	if _human_individuals.is_empty():
		return
	var today := _game_data.current_day
	# any_removed è INDIPENDENTE da DebugLogging.ENABLED (bugfix in corso d'opera: prima si
	# decideva se emettere human_population_changed guardando removed_log_lines, popolato SOLO a
	# log abilitati — con ENABLED=false il segnale non sarebbe mai scattato, lasciando la scheda
	# 👨‍👩‍👧 stantia anche a fronte di rimozioni vere).
	var any_removed := false
	var removed_log_lines: Array[String] = []
	var i := _human_individuals.size() - 1
	while i >= 0:
		var individual: HumanIndividual = _human_individuals[i]
		if individual.scheduled_death_day == today:
			var age_at_death := _game_data.year - individual.birth_year_virtual
			var partner_freed := _kill_individual(
				individual, i, individual.scheduled_death_cause, today, age_at_death
			)
			any_removed = true
			if DebugLogging.ENABLED:
				removed_log_lines.append("#%d %s (eta'=%d, causa=%s%s)" % [
					individual.id, individual.name, age_at_death,
					_cause_debug_name(individual.scheduled_death_cause),
					", coniuge liberato" if partner_freed else ""
				])
		i -= 1
	if not any_removed:
		return
	# Nessuna riga se oggi non muore nessuno (a differenza del riepilogo annuale sopra, che
	# stampa sempre) — evita spam giornaliero, richiesta utente.
	if DebugLogging.ENABLED and not removed_log_lines.is_empty():
		print("[HUMAN DEATH] giorno=%d: %s" % [today, ", ".join(removed_log_lines)])
	# Solo ora (dopo TUTTE le rimozioni/total_count del giorno) — vedi commento sul signal.
	human_population_changed.emit()


# Step 9c del piano mortalità (2026-09-05): morte IMMEDIATA di debug (bottone "Kill (debug)" su
# HumanIndividualInfoPanel), causa sempre MURDER — deliberatamente NON passa da
# scheduled_death_day/scheduled_death_cause: quel meccanismo è pensato per "un giorno a caso di
# QUEST'anno" (giorno-dell'anno, non assoluto), quindi se il tick di oggi fosse già passato
# impostarlo ora farebbe morire l'individuo tra un anno, non oggi (analisi discussa con l'utente).
# Qui invece si chiama subito _kill_individual con il giorno vero di oggi.
#
# Indice trovato per RIFERIMENTO (Array.find usa l'uguaglianza di default per Object = identità),
# non per id — coerente con come questa classe non ha mai un indice stabile a parte quello
# nell'array stesso. No-op silenzioso se l'individuo non è (più) nel roster, stesso principio
# difensivo di _free_partner_if_any.
func kill_individual_now(individual: HumanIndividual) -> void:
	var index := _human_individuals.find(individual)
	if index == -1:
		return
	var age_at_death := _game_data.year - individual.birth_year_virtual
	var partner_freed := _kill_individual(
		individual, index, DeathTypes.DeathCause.MURDER, _game_data.current_day, age_at_death
	)
	if DebugLogging.ENABLED:
		print("[HUMAN DEATH] kill immediato: #%d %s (eta'=%d, causa=%s%s)" % [
			individual.id, individual.name, age_at_death, _cause_debug_name(DeathTypes.DeathCause.MURDER),
			", coniuge liberato" if partner_freed else ""
		])
	# Fuori dal ciclo giornaliero, nessun batch da attendere — stesso segnale che
	# _apply_scheduled_human_deaths emette a fine giornata, qui subito.
	human_population_changed.emit()


# Elaborazione condivisa di UNA morte, qualunque sia la causa/il chiamante (Step 9, 2026-09-05 —
# estratta da _apply_scheduled_human_deaths, che la chiama per OLD_AGE; kill_individual_now sopra
# la chiama per MURDER, immediatamente, senza mai passare da scheduled_death_day). age_at_death
# passato dal chiamante (non ricalcolato qui) — entrambi i chiamanti lo calcolano comunque per il
# proprio log, evita di farlo due volte. Ritorna partner_freed così ciascun chiamante può comporre
# il proprio messaggio di log nel proprio formato, senza che questa funzione sappia nulla di log.
#
# Step 8 (2026-09-05): il DeathEvent è costruito PRIMA di _free_partner_if_any e PRIMA della
# rimozione dal roster sotto, così spouse_id cattura il partner_id del defunto come snapshot ("il
# coniuge al momento della morte", altrimenti perso). -1 = nessun partner, stessa convenzione di
# HumanIndividual.partner_id stesso.
func _kill_individual(
	individual: HumanIndividual, index: int, cause: DeathTypes.DeathCause, day: int, age_at_death: int
) -> bool:
	# Custodia del figlio a carico (2026-09-19, richiesta utente): a OGNI morte, qualunque causa, mentre
	# dependent_child_id e' ancora leggibile e l'individuo e' ancora nel roster (il padre e' cercato li').
	# Se il padre non puo' prenderlo in carico il bambino resta orfano, vedi _apply_daily_starvation.
	_transfer_or_orphan_dependent_child(individual)
	_game_data.death_events.append({
		"individual_id": individual.id,
		"name": individual.name,
		"sex": individual.sex,
		"age_at_death": age_at_death,
		"cause": cause,
		"year": _game_data.year,
		"day": day,
		"spouse_id": individual.partner_id,
	})
	# Log di verifica SEPARATO dal riepilogo "[HUMAN DEATH]" (mai toccato, richiesta esplicita) —
	# conferma che l'evento è stato davvero registrato in game_data.death_events e mostra il
	# conteggio totale accumulato (utile anche per controllare che sopravviva a un save/load).
	if DebugLogging.ENABLED:
		print("[DEATH LOG] registrato: %s (totale eventi finora: %d)" % [
			_game_data.death_events[-1], _game_data.death_events.size()
		])
	# Step 3 del sistema oggetti-scaduti (2026-09-05): comparsa di un DEAD_BODY, in parallelo al
	# DeathEvent sopra — stesso momento (PRIMA della rimozione dal roster sotto, individual.position
	# è ancora quella al momento della morte), stesso anno/giorno passati al DeathEvent (year/day
	# qui sotto coincidono esattamente con quelli appena scritti sopra). Nessuna rimozione/
	# decadimento/visual qui — solo la comparsa del dato (Step 4 se ne occuperà).
	_game_data.expired_objects.append({
		"object_type": ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY,
		"individual_id": individual.id,
		"position": individual.position,
		# Step 6 (2026-09-05): necessario per il hit-test di selezione (DeadBodySelectorController),
		# stesso identico bisogno di HumanIndividual.home_macro_coords — senza questo campo,
		# candidate.position non sarebbe traducibile nello spazio locale della cella centrale per un
		# corpo comparso in una macrocella diversa da quella attualmente al centro. Generico (non
		# type_specific_data): riguarda DOVE il record vive, non COSA il tipo specifico comporta —
		# rilevante per qualunque futuro ExpiredObjectType con una posizione nel mondo.
		"home_macro_coords": individual.home_macro_coords,
		"appeared_at_year": _game_data.year,
		"appeared_at_day": day,
		# Step 5 (2026-09-05): snapshot dell'aspetto al momento della morte — DeadBodyView lo userà
		# per disegnare il corpo (stessa scala/colori di quando l'individuo era vivo), senza dover
		# tenere in vita l'HumanIndividual originale (già rimosso dal roster poco sotto). Tutti
		# valori int/enum, già JSON-nativi come il resto del record — vedi commento sopra su
		# GameSaveService/GameLoadService, nessuna gestione speciale oltre quella già esistente per
		# expired_objects nel suo complesso. "name" aggiunto allo Step 6 per DeadBodyInfoPanel
		# (String, anch'esso già JSON-nativo).
		"type_specific_data": {
			"name": individual.name,
			"sex": individual.sex,
			"age_at_death": age_at_death,
			"cause": cause,
			"hair_color": individual.hair_color,
			"clothing_color": individual.clothing_color,
			# Carnagione (2026-09-06) — stesso trattamento di hair_color/clothing_color sopra, per
			# completezza dello snapshot. Nessun consumo visivo ancora: SKIN_COLOR in
			# HumanIndividualView (ereditato da DeadBodyView) resta oggi una costante fissa, non
			# pilotata per-individuo, esattamente come per un individuo vivo — innocuo finché
			# HumanTypes.SkinColor ha un solo membro possibile.
			"skin_color": individual.skin_color,
		},
	})
	# Log di verifica, stesso stile/scopo di "[DEATH LOG]" sopra per death_events — conferma che il
	# record è stato registrato in game_data.expired_objects e mostra il conteggio totale.
	if DebugLogging.ENABLED:
		print("[DEAD BODY LOG] registrato: %s (totale oggetti scaduti finora: %d)" % [
			_game_data.expired_objects[-1], _game_data.expired_objects.size()
		])
	var partner_freed := _free_partner_if_any(individual)
	# EMESSO PRIMA della rimozione sotto, con l'indice ancora valido — vedi commento sul signal
	# per il perché (GameScene.human_individual_views parallelo per indice).
	individual_died.emit(individual, index, age_at_death, partner_freed, cause, day)
	_human_individuals.remove_at(index)
	if _human_population_group != null:
		_human_population_group.total_count = _human_individuals.size()
	return partner_freed


# Nome causa per il SOLO log console di debug (non tr(), non user-facing — vedi GameScene per il
# testo del popup, che resta un'altra cosa) — chiave enum minuscola, es. "old_age"/"murder".
func _cause_debug_name(cause: DeathTypes.DeathCause) -> String:
	return String(DeathTypes.DeathCause.keys()[cause]).to_lower()


# Libera partner_id del coniuge superstite di `deceased`, se presente — trovato per scansione
# lineare su _human_individuals (stesso costo già accettato altrove nel progetto per array
# analoghi, es. GameScene._find_building_by_id). MAI mother_id/father_id, di nessuno: restano
# dangling, puramente genealogici (già deciso in sessione precedente). Nessun crash se il
# coniuge non viene trovato (già rimosso in precedenza, o riferimento dangling per altri motivi)
# — skip silenzioso, come richiesto.
func _free_partner_if_any(deceased: HumanIndividual) -> bool:
	if deceased.partner_id == -1:
		return false
	for other in _human_individuals:
		if other.id == deceased.partner_id:
			other.partner_id = -1
			return true
	return false


# Custodia del figlio a carico alla morte di `mother` (2026-09-06, esteso 2026-09-19: ora chiamata da
# _kill_individual a OGNI morte, qualunque causa, non piu' solo il parto) — se ha un figlio a carico
# (dependent_child_id != -1), il riferimento passa al
# padre di quel figlio, se vivo, reperibile e libero — stesso identico campo/meccanismo di
# GameScene._sync_dependent_child_position, che legge dependent_child_id da CHIUNQUE lo tenga
# valorizzato, mai assumendo che sia la madre biologica (nessuna modifica lì necessaria — vedi
# ricognizione, nessun controllo di sesso su questo campo). In OGNI altro caso il bambino resta
# orfano, SEMPRE con lo stesso fallback silenzioso, nessuna distinzione di trattamento: padre
# morto/non trovato, OPPURE padre già occupato con un altro figlio a carico (dependent_child_id
# diverso da quello di questa madre — es. ereditato da una compagna precedente deceduta) sono
# trattati identicamente — nessuna regola su quale dei due figli "vince" in quest'ultimo caso,
# nessun log/avviso di sorta (richiesta esplicita utente, 2026-09-06): è un caso limite raro ma
# previsto, il fallback "resta orfano" è già di per sé il comportamento corretto, senza bisogno di
# visibilità aggiuntiva.
func _transfer_or_orphan_dependent_child(mother: HumanIndividual) -> void:
	if mother.dependent_child_id == -1:
		return
	var child: HumanIndividual = null
	for candidate in _human_individuals:
		if candidate.id == mother.dependent_child_id:
			child = candidate
			break
	if child == null:
		# Il figlio non è (più) nel roster — nulla da trasferire, dependent_child_id sparirà
		# comunque con la madre tra un attimo.
		return
	var father: HumanIndividual = null
	for candidate in _human_individuals:
		if candidate.id == child.father_id:
			father = candidate
			break
	if father == null:
		return
	if father.dependent_child_id != -1:
		return
	father.dependent_child_id = mother.dependent_child_id
	mother.dependent_child_id = -1


# Morte per fame (2026-09-19, richiesta utente), una volta al giorno per l'INTERA popolazione, dopo il
# consumo calorico. Aggiorna HumanIndividual.starvation_days e uccide (causa STARVATION) chi raggiunge
# STARVATION_DAYS:
#   - individuo che consuma calorie (fascia diversa da INFANT): "in fame" se body_calories <= 0;
#   - INFANT (non consuma calorie): "in fame" se nessun individuo del roster lo porta
#     (dependent_child_id uguale al suo id), cioe' e' orfano.
# Il contatore si azzera il giorno in cui la condizione cessa. Le uccisioni passano da _kill_individual
# (death_events, corpo, popup con "death_cause_starvation", custodia del figlio a carico); l'indice e'
# ricalcolato fresco per ogni morte.
func _apply_daily_starvation() -> void:
	if _human_individuals.is_empty():
		return
	var carried_child_ids: Dictionary = {}
	for individual in _human_individuals:
		if individual.dependent_child_id != -1:
			carried_child_ids[individual.dependent_child_id] = true
	var doomed: Array[HumanIndividual] = []
	for individual in _human_individuals:
		var age_band := HumanCalculator.get_age_band(
			_game_data.era_effective_age_band_durations_male, _game_data.era_effective_age_band_durations_female,
			individual.sex, float(_game_data.year - individual.birth_year_virtual)
		)
		var starving: bool
		if age_band == HumanTypes.AgeBand.INFANT:
			starving = not carried_child_ids.has(individual.id)
		else:
			starving = individual.body_calories <= 0.0
		individual.starvation_days = (individual.starvation_days + 1) if starving else 0
		if individual.starvation_days >= STARVATION_DAYS:
			doomed.append(individual)
	if doomed.is_empty():
		return
	var removed_log_lines: Array[String] = []
	for individual in doomed:
		var index := _human_individuals.find(individual)
		if index == -1:
			continue
		var age_at_death := _game_data.year - individual.birth_year_virtual
		var partner_freed := _kill_individual(
			individual, index, DeathTypes.DeathCause.STARVATION, _game_data.current_day, age_at_death
		)
		if DebugLogging.ENABLED:
			removed_log_lines.append("#%d %s (eta'=%d, causa=%s%s)" % [
				individual.id, individual.name, age_at_death,
				_cause_debug_name(DeathTypes.DeathCause.STARVATION), ", coniuge liberato" if partner_freed else ""
			])
	if DebugLogging.ENABLED and not removed_log_lines.is_empty():
		print("[HUMAN DEATH] giorno=%d: %s" % [_game_data.current_day, ", ".join(removed_log_lines)])
	human_population_changed.emit()


# Placeholder: nessuna reazione ancora, solo il collegamento richiesto (vedi doc di testa al
# file). Prossimo consumo reale probabilmente qui, quando arriverà una logica per-stagione.
func _on_season_ended(season: GameTypes.Season) -> void:
	pass
