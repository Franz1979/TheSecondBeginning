class_name IdleTaskAssignmentService
extends RefCounted

# Fallback "perditempo" per individui LIBERI (2026-09-13, richiesta utente) — quando nessuna Task è
# in corso, nessun bisogno stamina è attivo e la coda personale (task_queue) è vuota, invece di
# restare fermo senza current_task l'individuo riceve una Task scelta a caso tra quelle "per
# passare il tempo", filtrate per età. Service RefCounted stateless, stesso pattern di
# NeedTaskAssignmentService/TaskQueueService.
#
# SEPARATO da TaskQueueService (richiesta utente: "a tua scelta motivata") — TaskQueueService resta
# scoped alla sola meccanica della coda LIFO (push/pop, zero conoscenza di TaskDefinition/
# TaskFactory/risoluzione target), stessa separazione di responsabilità già stabilita tra
# NeedTaskAssignmentService (risoluzione/costruzione/assegnazione delle Task-bisogno) e
# TaskQueueService stesso — un servizio, una responsabilità, mai mescolare "gestione coda" con
# "scelta/costruzione di una Task".
#
# resolve_wander_targets/resolve_play_targets ESTRATTE da GameScene._resolve_wander_targets/
# _resolve_play_targets (spostate qui TALI E QUALI, nessun cambio di comportamento) — i trigger
# manuali tasti G/P (GameScene._assign_wander_task/_assign_play_task) ora le richiamano da qui
# invece di tenerne una copia propria, stesso principio già applicato a Rest/Emergency Rest tramite
# NeedTaskAssignmentService: una sola formula, riusata sia dal comando manuale sia da questo
# fallback automatico, mai due copie indipendenti a rischio di disallinearsi in futuro.

# Elenco CENTRALIZZATO delle Task "perditempo" (2026-09-13, richiesta utente) — pensato per
# crescere in futuro (nuove Task "per passare il tempo") senza toccare la logica di scelta in
# assign_idle_fallback sotto: aggiungere un path qui basta perché entri nel tiro a sorte, filtrato
# per età con lo stesso identico meccanismo delle altre due. L'UNICA parte che va comunque estesa
# per una nuova voce è _build_idle_task sotto (il "come si risolve il context di QUESTA specifica
# Task" resta necessariamente per-caso, non genericizzabile senza un'astrazione che oggi non serve
# per due sole voci — stesso principio "niente genericità prematura" già seguito ovunque in questo
# progetto, es. TaskFactory.build_task).
const IDLE_FALLBACK_TASK_PATHS: Array[String] = [
	"res://gameplay/scripts/tasks/definitions/wander.tres",
	"res://gameplay/scripts/tasks/definitions/play.tres",
	"res://gameplay/scripts/tasks/definitions/leisure_rest.tres",
	"res://gameplay/scripts/tasks/definitions/daydreaming.tres",
	"res://gameplay/scripts/tasks/definitions/leisure_restock.tres",
]

# Guard di eleggibilita' di leisure_restock nel sorteggio idle (2026-09-19, richiesta utente): la Task e'
# eleggibile solo se lo spazio libero nelle provviste (food_space_capacity - food_space_used) e' almeno
# questa frazione della capacita' (0.4 = 40%). Con le provviste quasi piene il sorteggio la salta e ne
# pesca un'altra. Vale SOLO per il sorteggio idle: l'attivazione manuale (tasto F) resta senza
# condizioni.
const LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO: float = 0.4

# Range di durata (in giorni) della Rest per SVAGO (2026-09-16, richiesta utente) — RANDOM ad ogni
# assegnazione (a differenza del tetto FISSO di 8gg della Rest da bisogno, vedi
# NeedTaskAssignmentService.REST_TASK_MAX_DURATION_DAYS): qui non c'è un vero bisogno da soddisfare,
# solo un modo di passare il tempo, quindi una durata variabile è più naturale/meno meccanica di un
# singolo numero fisso ripetuto ad ogni occorrenza.
# Taratura 2026-09-26 (richiesta utente): da 4-8 a 2-5 giorni.
const LEISURE_REST_MIN_DURATION_DAYS: float = 2.0
const LEISURE_REST_MAX_DURATION_DAYS: float = 5.0

# RIATTIVATA (2026-09-16, richiesta utente) — era stata sospesa per il sintomo "i pipottini che
# ondulano fermi su se stessi"/"ondulando come quando camminano", causa poi isolata e corretta:
# GameScene._attempt_macro_cell_transition ribasava SOLO il target dello step ATTIVO al cambio di
# macrocella, lasciando le gambe FUTURE di Wander/Play/Leisure Rest nel vecchio sistema di
# riferimento (CAUSA A), e uno step bloccato al bordo (macrocella inesistente/acqua) restava
# incompleto per sempre, mai avanzato (CAUSA B) — vedi Task.rebase_positional_targets/
# HumanIndividualActionService.finish_current_step/GameScene._block_border_crossing, verificati da
# tools/border_crossing_test. Storico sospensioni precedenti (git blame per il dettaglio completo):
# prima disattivata per debug, poi il 2026-09-15, poi di nuovo il 2026-09-16 quando il sintomo era
# ricomparso subito dopo una prima riattivazione — sempre lo stesso bug, mai isolato fino ad ora.
#
# static var, non più const (2026-09-16, richiesta utente — infrastruttura per il test
# automatizzato tools/zombie_task_test/ZombieTaskTest.gd, fix "task zombie"): reso var SOLO perché
# quel test deve poterlo forzare temporaneamente, poi ripristinarlo. Nessun punto di produzione lo
# riassegna — il controllo runtime per disattivare il fallback perditempo SENZA toccare questo
# flag è ora `fallback_enabled` sotto (interruttore unico, sessione-only, bottone DebugBar).
static var WANDER_ENABLED := true

# RIATTIVATA insieme a WANDER_ENABLED sopra (2026-09-16, richiesta utente) — era stata sospesa SOLO
# per isolare meglio il problema di Wander (nessun sintomo proprio mai riscontrato su questa Task),
# stessa causa/stesso fix di sopra.
#
# static var, non più const — STESSO motivo/STESSO trattamento di WANDER_ENABLED sopra.
static var LEISURE_REST_ENABLED := true

# Interruttore GLOBALE di sessione per l'intero fallback perditempo (2026-09-16, richiesta utente)
# — DIVERSO da WANDER_ENABLED/LEISURE_REST_ENABLED sopra (che disattivano UNA task specifica,
# lasciando le altre candidate): questo spegne l'INTERO meccanismo (Wander/Play/Leisure Rest
# insieme), controllato da assign_idle_fallback sotto. Pensato per un pulsante di debug (DebugBar,
# vedi GameScene._on_debug_action_pressed), non per un bug da isolare — utile per confrontare
# rapidamente "con/senza perditempo" senza dover toccare i tre flag sopra uno per uno.
#
# Solo stato di SESSIONE (richiesta esplicita) — MAI salvato/letto da GameSettings o da un
# salvataggio: ad ogni avvio del gioco riparte SEMPRE acceso (true), indipendentemente da come è
# stato lasciato nella sessione precedente. Spegnimento: le task perditempo GIÀ in corso non
# vengono toccate (nessun controllo qui dentro apply_action/resolve_idle_individual, solo qui in
# assign_idle_fallback), finiscono normalmente per la loro strada; SOLO la prossima assegnazione
# viene bloccata. Riaccensione: nessun ripescaggio automatico degli individui nel frattempo finiti
# a current_task=null (via stop(), lo stesso ramo che scatterebbe comunque a flag acceso se nessun
# candidato fosse idoneo) — rientrano nel giro da soli alla prossima chiamata naturale di
# resolve_idle_individual (fine della loro prossima Task) o con un comando manuale (tasto H).
static var fallback_enabled := true


# Accende/spegne fallback_enabled sopra, con il log richiesto — unico punto che lo scrive (mai
# un'assegnazione diretta al campo altrove, cosi' il log non puo' disallinearsi dallo stato reale).
# Chiamata dal pulsante di debug in GameScene._on_debug_action_pressed.
static func set_fallback_enabled(enabled: bool) -> void:
	fallback_enabled = enabled
	if DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
		print("[IDLE FALLBACK] service %s." % ("attivato" if enabled else "disattivato"))

# Hook di connessione listener per lo step_appended di una Task Daydream (2026-09-16, richiesta
# utente, "Daydreaming nel fallback perditempo") — IdleTaskAssignmentService è uno stateless
# service senza riferimento alla scena (nessun Node): non può chiamare da sé
# GameScene._reconnect_unload_action_signals (side-effect UI: refresh griglia edifici, popup
# idea). GameScene si registra da sé in _ready() con questo Callable statico, stesso principio già
# seguito da fallback_enabled/set_fallback_enabled sopra ("GameScene configura lo stato del
# servizio dall'esterno, il servizio resta ignaro di chi lo consuma"). Callable() vuoto di default
# (contesti senza GameScene — tools/zombie_task_test, HumanBirthIndividualService — restano no-op
# sicuri via `.is_valid()` sotto: la Daydream funziona comunque, solo senza gli aggiornamenti UI
# collegati all'Unload del ramo pensiero). Chiamata da _build_idle_task sotto, subito dopo aver
# costruito la Task, PRIMA che assign_idle_fallback la assegni — stesso ordine (costruisci, collega
# listener, assegna) già seguito da GameScene._debug_test_daydream_task.
static var daydream_step_appended_connector: Callable = Callable()

# Lunghezza min/max (in microcelle) di ciascun tratto casuale di Wander/Play — STESSO valore/STESSO
# principio già in uso prima di questo spostamento (vedi GameScene.gd, ora rimosso da lì).
const WANDER_LEG_MIN_LENGTH: float = 4.0
const WANDER_LEG_MAX_LENGTH: float = 8.0

# Distanza/durata BASE della Daydream del fallback (2026-09-16, richiesta utente) — STESSI valori
# di GameScene._DEBUG_DAYDREAM_AROUND_DISTANCE/_DEBUG_DAYDREAM_THINK_BASE_DURATION (tasto Y), ma
# SENZA il moltiplicatore EraRules.think_duration_multiplier che quel tasto applica: questa
# funzione (chiamata da _resolve_active_stamina_need_priority/resolve_idle_individual a cascata,
# vedi HumanIndividualActionService) non riceve `game_data`, solo `world` — thread-arlo giù da lì
# toccherebbe 5 chiamanti esterni (HumanBirthIndividualService/GameLoadService/ZombieTaskTest/
# GameScene x2) per un affinamento cosmetico. Semplificazione deliberata: durata BASE = "era
# neutra" (moltiplicatore 1.0), coerente con l'uso già arbitrario di questa costante nel tasto Y.
const DAYDREAM_AROUND_DISTANCE: float = 14.1
const DAYDREAM_THINK_BASE_DURATION: float = 2.0

# Risoluzione dei tre target Walk della Wander Task — STESSA identica logica di GameScene.
# _resolve_wander_targets prima di questo spostamento (vedi doc di testa al file).
static func resolve_wander_targets(individual: HumanIndividual) -> Dictionary:
	var starting_position: Vector2 = individual.position
	var first_leg_length: float = randf_range(WANDER_LEG_MIN_LENGTH, WANDER_LEG_MAX_LENGTH)
	var target_1: Vector2 = starting_position + Vector2.from_angle(randf() * TAU) * first_leg_length
	var second_leg_length: float = randf_range(WANDER_LEG_MIN_LENGTH, WANDER_LEG_MAX_LENGTH)
	var target_2: Vector2 = target_1 + Vector2.from_angle(randf() * TAU) * second_leg_length
	return {"target_1": target_1, "target_2": target_2, "target_3": starting_position}


# Risoluzione dei due target Run della Play Task — STESSA identica logica di GameScene.
# _resolve_play_targets prima di questo spostamento (vedi doc di testa al file).
static func resolve_play_targets(individual: HumanIndividual) -> Dictionary:
	var starting_position: Vector2 = individual.position
	var first_leg_length: float = randf_range(WANDER_LEG_MIN_LENGTH, WANDER_LEG_MAX_LENGTH)
	var target_1: Vector2 = starting_position + Vector2.from_angle(randf() * TAU) * first_leg_length
	var second_leg_length: float = randf_range(WANDER_LEG_MIN_LENGTH, WANDER_LEG_MAX_LENGTH)
	var target_2: Vector2 = target_1 + Vector2.from_angle(randf() * TAU) * second_leg_length
	return {"target_1": target_1, "target_2": target_2}


# Eleggibilita' di leisure_restock nel sorteggio idle: spazio libero nelle provviste >=
# LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO x capacita'. Capacita' <= 0 -> non eleggibile.
static func _is_leisure_restock_eligible(individual: HumanIndividual) -> bool:
	if individual.food_space_capacity <= 0.0:
		return false
	var free_space: float = individual.food_space_capacity - individual.food_space_used
	return free_space >= LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO * individual.food_space_capacity


# Costruisce la Task runtime per UNO dei path di IDLE_FALLBACK_TASK_PATHS — match ESPLICITO per
# path (vedi il commento su IDLE_FALLBACK_TASK_PATHS sopra per il perché non è genericizzato). Il
# case `_` logga un errore invece di un crash silenzioso, per segnalare subito una voce aggiunta a
# IDLE_FALLBACK_TASK_PATHS senza il proprio case qui.
#
# `world` (2026-09-16, richiesta utente, Rest per svago) — DEVIAZIONE rispetto alla firma
# precedente (solo path/individual): necessario per riusare NeedTaskAssignmentService.
# resolve_rest_target, che a sua volta ne ha bisogno per risolvere la Building casa dell'individuo
# (stessa DEVIAZIONE già documentata altrove nel progetto per lo stesso motivo, es.
# HumanIndividualActionService.apply_action). Thread-ato da assign_idle_fallback sotto, che lo
# riceve già come proprio parametro.
static func _build_idle_task(path: String, individual: HumanIndividual, world: World) -> Task:
	match path:
		"res://gameplay/scripts/tasks/definitions/wander.tres":
			if not WANDER_ENABLED:
				return null
			var target_data := resolve_wander_targets(individual)
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"wander_target_1": target_data["target_1"],
				"wander_target_2": target_data["target_2"],
				"wander_target_3": target_data["target_3"],
			}
			return TaskFactory.build_task(definition, context)
		"res://gameplay/scripts/tasks/definitions/play.tres":
			var target_data := resolve_play_targets(individual)
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"play_target_1": target_data["target_1"],
				"play_target_2": target_data["target_2"],
			}
			return TaskFactory.build_task(definition, context)
		"res://gameplay/scripts/tasks/definitions/leisure_rest.tres":
			if not LEISURE_REST_ENABLED:
				return null
			# STESSO target (casa se c'è, altrimenti walk-around) della Rest da bisogno — riusa
			# NeedTaskAssignmentService.resolve_rest_target TALE E QUALE, nessuna copia della
			# logica "ha casa? vai lì" (2026-09-16, richiesta utente). A differenza di rest.tres
			# (NeedTaskAssignmentService.REST_TASK_MAX_DURATION_DAYS fisso, ignore_stamina_cap=
			# false): qui la durata è RANDOM ad ogni assegnazione (vedi LEISURE_REST_MIN/MAX_
			# DURATION_DAYS sopra) e ignore_stamina_cap=true — questa Rest non si ferma mai a
			# stamina piena, solo alla durata (vedi RestAction.is_complete per il perché).
			var target_data := NeedTaskAssignmentService.resolve_rest_target(individual, world)
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"target_position": target_data["target_position"],
				"rest_multiplier": target_data["rest_multiplier"],
				"walk_away_target_position": target_data["walk_away_target_position"],
				"rest_max_duration_days": randf_range(LEISURE_REST_MIN_DURATION_DAYS, LEISURE_REST_MAX_DURATION_DAYS),
				"rest_ignore_stamina_cap": true,
			}
			return TaskFactory.build_task(definition, context)
		"res://gameplay/scripts/tasks/definitions/daydreaming.tres":
			# Filtro "esiste un edificio che accetta pensieri" GIÀ APPLICATO a monte da
			# assign_idle_fallback (vedi lì) — qui si assume che il chiamante l'abbia già verificato,
			# stesso principio "un guard, un solo posto" già seguito per allowed_age_bands. Nessun
			# WANDER_ENABLED/LEISURE_REST_ENABLED equivalente per Daydream: nessuna richiesta di
			# poterla disattivare separatamente oggi.
			var around_position: Vector2 = individual.position + Vector2.from_angle(randf() * TAU) * DAYDREAM_AROUND_DISTANCE
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"target_position": around_position,
				"think_duration": DAYDREAM_THINK_BASE_DURATION,
			}
			var task := TaskFactory.build_task(definition, context)
			# daydream_step_appended_connector (vedi sopra) — collegato SUBITO dopo la costruzione,
			# PRIMA che assign_idle_fallback assegni la Task: stesso ordine di GameScene.
			# _debug_test_daydream_task (costruisci, collega, assegna).
			if daydream_step_appended_connector.is_valid():
				daydream_step_appended_connector.call(task, individual)
			return task
		"res://gameplay/scripts/tasks/definitions/leisure_restock.tres":
			# Guard dello spazio libero GIA' APPLICATO a monte da assign_idle_fallback (vedi lì). Se nessun
			# magazzino ha cibo torna null e assign_idle_fallback ritira tra le altre perditempo.
			return NeedTaskAssignmentService.build_restock_task(
				individual, world, NeedTaskAssignmentService.LEISURE_RESTOCK_TASK_DEFINITION_PATH
			)
		_:
			push_error("IdleTaskAssignmentService._build_idle_task: path '%s' non riconosciuto — aggiungi un case quando estendi IDLE_FALLBACK_TASK_PATHS." % path)
			return null


# Assegna una Task "perditempo" scelta a caso tra quelle di IDLE_FALLBACK_TASK_PATHS compatibili
# con age_band (2026-09-13, richiesta utente) — chiamata SOLO quando l'individuo è davvero libero:
# nessuna Task in corso, nessun bisogno stamina attivo, task_queue vuota (vedi
# HumanIndividualActionService._handle_task_completion_need_and_queue, l'unico chiamante oggi).
#
# Filtro età LEGGERO (2026-09-16, richiesta utente — sostituisce il filtro precedente basato su
# individual.can_assign_task): letto direttamente da TaskDefinition.allowed_age_bands, PRIMA di
# costruire alcuna Task — niente più "costruisci tutto poi scarta chi non passa". `remaining` porta
# solo path + TaskDefinition già caricata (mai una Task), una entry per candidato ancora in gioco.
#
# Tiro PESATO tra le entry rimanenti (vedi _pick_weighted_index sotto) usando TaskDefinition.
# idle_weight — poi si costruisce SOLO la Task estratta (mai le altre): se l'assegnazione fallisce
# (_build_idle_task torna null, es. WANDER_ENABLED/LEISURE_REST_ENABLED spento, oppure individual.
# assign_task rifiuta per un guard più profondo per-Action) quella entry viene rimossa da
# `remaining` e si ritira tra le rimanenti, finché una assegnazione riesce o il pool si esaurisce.
#
# `world` — consultato da _build_idle_task (Rest per svago: resolve_rest_target ne ha bisogno per
# risolvere la Building casa dell'individuo).
#
# Ritorna true/false (esito dell'assegnazione riuscita, o false se il pool si esaurisce senza
# successo) — stesso principio "il chiamante sa se è davvero riuscita" già seguito da
# NeedTaskAssignmentService.assign_rest_task/assign_emergency_rest_task.
static func assign_idle_fallback(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	# Interruttore globale (2026-09-16, richiesta utente) — controllato PRIMA di valutare
	# qualunque candidato: a fallback_enabled=false, nessuna Task perditempo viene mai assegnata,
	# indipendentemente da WANDER_ENABLED/LEISURE_REST_ENABLED/età — il chiamante (resolve_idle_
	# individual) ricade sul proprio ultimo ramo, individual.stop(), esattamente come se nessun
	# candidato fosse mai risultato idoneo. Nessun log qui: il log [IDLE FALLBACK] vive in
	# set_fallback_enabled sopra, al momento del toggle, non ad ogni tentativo di assegnazione
	# (che sarebbe rumoroso quanto il numero di individui che si liberano mentre il servizio è
	# spento).
	if not fallback_enabled:
		return false

	var remaining: Array[Dictionary] = []
	for path in IDLE_FALLBACK_TASK_PATHS:
		var definition := load(path) as TaskDefinition
		if not definition.allowed_age_bands.is_empty() and not definition.allowed_age_bands.has(age_band):
			continue
		# Daydream esclusa a monte se non esiste nessun edificio COMPLETO che accetta pensieri
		# (2026-09-16, richiesta utente) — STESSO criterio/STESSA funzione già usata dal gate upfront
		# del tasto debug Y (vedi GameScene._debug_test_daydream_task): senza edificio, la Task
		# finirebbe comunque "a vuoto" (Think + nessun deposito, vedi _handle_pending_thought_
		# target_search), non un fallimento distruttivo ma inutile da estrarre nel tiro pesato.
		if path == "res://gameplay/scripts/tasks/definitions/daydreaming.tres" and not ThoughtTargetSelectionService.has_thought_accepting_building(world):
			continue
		# leisure_restock esclusa a monte se le provviste sono quasi piene (spazio libero sotto
		# LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO della capacita'): il sorteggio ne pesca un'altra.
		if path == "res://gameplay/scripts/tasks/definitions/leisure_restock.tres" and not _is_leisure_restock_eligible(individual):
			continue
		remaining.append({"path": path, "definition": definition})

	while not remaining.is_empty():
		var drawn_index := _pick_weighted_index(remaining)
		var path: String = remaining[drawn_index]["path"]
		var candidate_task := _build_idle_task(path, individual, world)
		var assigned := candidate_task != null and individual.assign_task(candidate_task, age_band)
		if assigned:
			if DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
				print("[IDLE FALLBACK] #%d %s: nessuna Task/bisogno/coda attivi — assegnata '%s'." % [
					individual.id, individual.name, candidate_task.task_name
				])
			return true
		remaining.remove_at(drawn_index)
	return false


# Tiro PESATO su indice tra le entry di `remaining` (2026-09-16, richiesta utente — sostituisce
# _pick_weighted_task/IDLE_FALLBACK_TASK_WEIGHTS: il peso vive ora su TaskDefinition.idle_weight,
# letto qui direttamente dall'entry — vedi assign_idle_fallback sopra). Nessuna normalizzazione
# esplicita a somma 1.0: il tiro (`randf() * total_weight`) avviene già sul solo totale delle entry
# ANCORA in gioco in questa chiamata — via via che una entry fallita viene rimossa da `remaining`
# dal chiamante, il rapporto relativo tra i pesi restanti resta quello dichiarato.
#
# total_weight <= 0.0 (caso limite — idle_weight <= 0 su ogni entry rimanente, mai un caso reale
# oggi ma non un crash) -> ripiega sul tiro uniforme, nessuna entry mai esclusa per un peso mancante.
#
# Ultimo indice come fallback finale dopo il ciclo (mai raggiunto in teoria: roll < total_weight
# per costruzione, garantisce che l'ultimo confronto cumulativo sia sempre vero) — solo per
# proteggere da un residuo di imprecisione in virgola mobile, stesso principio "mai un crash" già
# seguito ovunque nel progetto.
static func _pick_weighted_index(remaining: Array[Dictionary]) -> int:
	var total_weight: float = 0.0
	for entry in remaining:
		total_weight += float((entry["definition"] as TaskDefinition).idle_weight)
	if total_weight <= 0.0:
		return randi() % remaining.size()
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for i in range(remaining.size()):
		cumulative += float((remaining[i]["definition"] as TaskDefinition).idle_weight)
		if roll < cumulative:
			return i
	return remaining.size() - 1
