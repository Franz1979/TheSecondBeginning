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
]

# Range di durata (in giorni) della Rest per SVAGO (2026-09-16, richiesta utente) — RANDOM ad ogni
# assegnazione (a differenza del tetto FISSO di 8gg della Rest da bisogno, vedi
# NeedTaskAssignmentService.REST_TASK_MAX_DURATION_DAYS): qui non c'è un vero bisogno da soddisfare,
# solo un modo di passare il tempo, quindi una durata variabile è più naturale/meno meccanica di un
# singolo numero fisso ripetuto ad ogni occorrenza.
const LEISURE_REST_MIN_DURATION_DAYS: float = 4.0
const LEISURE_REST_MAX_DURATION_DAYS: float = 8.0

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

# Lunghezza min/max (in microcelle) di ciascun tratto casuale di Wander/Play — STESSO valore/STESSO
# principio già in uso prima di questo spostamento (vedi GameScene.gd, ora rimosso da lì).
const WANDER_LEG_MIN_LENGTH: float = 4.0
const WANDER_LEG_MAX_LENGTH: float = 8.0

# Pesi del tiro random tra le Task idle-fallback IDONEE (2026-09-16, richiesta utente — prima un
# tiro UNIFORME tra i soli candidati che passano il filtro età, ora pesato) — Play/Leisure Rest
# favoriti (0.4 ciascuna) rispetto a Wander (0.2, appena riattivata dopo un bug non isolato, vedi
# sopra — peso più basso finché non si ha più fiducia nella sua stabilità). Chiave = stesso path di
# IDLE_FALLBACK_TASK_PATHS sopra, NESSUNA normalizzazione esplicita a somma 1.0 necessaria: _pick_
# weighted_task sotto tira su un intervallo [0, somma_pesi_dei_soli_idonei), che mantiene da sé il
# rapporto relativo corretto anche quando un candidato è escluso dal filtro età (es. Play per una
# fascia diversa da CHILD) — vedi quella funzione per il dettaglio.
const IDLE_FALLBACK_TASK_WEIGHTS := {
	"res://gameplay/scripts/tasks/definitions/wander.tres": 0.2,
	"res://gameplay/scripts/tasks/definitions/play.tres": 0.4,
	"res://gameplay/scripts/tasks/definitions/leisure_rest.tres": 0.4,
}


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
		_:
			push_error("IdleTaskAssignmentService._build_idle_task: path '%s' non riconosciuto — aggiungi un case quando estendi IDLE_FALLBACK_TASK_PATHS." % path)
			return null


# Assegna una Task "perditempo" scelta a caso tra quelle di IDLE_FALLBACK_TASK_PATHS compatibili
# con age_band (2026-09-13, richiesta utente) — chiamata SOLO quando l'individuo è davvero libero:
# nessuna Task in corso, nessun bisogno stamina attivo, task_queue vuota (vedi
# HumanIndividualActionService._handle_task_completion_need_and_queue, l'unico chiamante oggi).
#
# Filtro età tramite individual.can_assign_task (STESSA identica logica già usata ovunque per
# questo scopo — HumanIndividual.gd — non duplicata qui in una forma "statica" separata): per
# ciascun path viene costruita la Task COMPLETA (con target già risolti) e verificata col guard —
# solo chi passa entra tra i candidati. Costruire comunque ogni candidato (invece di un controllo
# "leggero" senza costruire nulla) è il prezzo per riusare can_assign_task così com'è.
#
# Un solo candidato -> usato direttamente (nessun tiro). Più di uno -> tiro PESATO (vedi
# IDLE_FALLBACK_TASK_WEIGHTS/_pick_weighted_task sotto, 2026-09-16, richiesta utente — prima era
# uniforme, randi() % candidates.size()). Zero candidati dopo il filtro (caso limite — non dovrebbe
# succedere: Wander è compatibile con tutte le età sopra INFANT) -> ritorna false, nessun effetto
# collaterale: il chiamante decide cosa fare (oggi, individual.stop() come fallback finale).
#
# `world` — ORA CONSULTATO (2026-09-16, richiesta utente, Rest per svago: resolve_rest_target ne
# ha bisogno per risolvere la Building casa dell'individuo, vedi _build_idle_task sopra). Prima di
# questo passo nessuna Task perditempo lo usava (Wander/Play non ne hanno bisogno), tenuto comunque
# in firma da subito per lo stesso principio "deviazione firma anticipata" già visto per `world`/
# `game_data` in HumanIndividualActionService.apply_action — quel principio ha ripagato qui.
#
# Ritorna true/false (esito di individual.assign_task, o false se nessun candidato) — stesso
# principio "il chiamante sa se è davvero riuscita" già seguito da NeedTaskAssignmentService.
# assign_rest_task/assign_emergency_rest_task.
static func assign_idle_fallback(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	# Interruttore globale (2026-09-16, richiesta utente) — controllato PRIMA di costruire
	# qualunque candidato: a fallback_enabled=false, nessuna Task perditempo viene mai assegnata,
	# indipendentemente da WANDER_ENABLED/LEISURE_REST_ENABLED/età — il chiamante (resolve_idle_
	# individual) ricade sul proprio ultimo ramo, individual.stop(), esattamente come se nessun
	# candidato fosse mai risultato idoneo. Nessun log qui: il log [IDLE FALLBACK] vive in
	# set_fallback_enabled sopra, al momento del toggle, non ad ogni tentativo di assegnazione
	# (che sarebbe rumoroso quanto il numero di individui che si liberano mentre il servizio è
	# spento).
	if not fallback_enabled:
		return false
	var candidates: Array[Task] = []
	# candidate_paths — PARALLELO a candidates (stesso indice), necessario per risolvere il peso di
	# ciascun candidato in _pick_weighted_task sotto: Task non porta con sé il path da cui è nata
	# (solo task_name, un identificativo leggibile ma non lo stesso valore usato come chiave in
	# IDLE_FALLBACK_TASK_WEIGHTS).
	var candidate_paths: Array[String] = []
	for path in IDLE_FALLBACK_TASK_PATHS:
		var candidate_task := _build_idle_task(path, individual, world)
		if candidate_task != null and individual.can_assign_task(candidate_task, age_band):
			candidates.append(candidate_task)
			candidate_paths.append(path)
	if candidates.is_empty():
		return false
	var chosen_task: Task = candidates[0] if candidates.size() == 1 else _pick_weighted_task(candidates, candidate_paths)
	var assigned := individual.assign_task(chosen_task, age_band)
	if assigned and DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
		print("[IDLE FALLBACK] #%d %s: nessuna Task/bisogno/coda attivi — assegnata '%s' (%d candidate compatibili con age_band=%s)." % [
			individual.id, individual.name, chosen_task.task_name, candidates.size(), HumanTypes.AgeBand.keys()[age_band]
		])
	return assigned


# Tiro PESATO tra `candidates` (2026-09-16, richiesta utente) — pesi letti da
# IDLE_FALLBACK_TASK_WEIGHTS per il path PARALLELO in `paths` (stesso indice di `candidates`,
# vedi assign_idle_fallback sopra). Nessuna normalizzazione esplicita a somma 1.0: il tiro
# (`randf() * total_weight`) avviene già sul solo totale dei candidati IDONEI presenti in questa
# chiamata — se uno o più path sono assenti (esclusi a monte dal filtro età), il loro peso semplicemente
# non entra nella somma, e il rapporto relativo tra i pesi rimanenti resta quello dichiarato
# (es. Wander 0.2 / Leisure Rest 0.4 = 1:2, INVARIATO anche se Play è escluso).
#
# total_weight <= 0.0 (caso limite — un path in IDLE_FALLBACK_TASK_PATHS senza voce in
# IDLE_FALLBACK_TASK_WEIGHTS, mai un caso reale oggi ma non un crash) -> ripiega sul tiro uniforme
# di prima, nessun candidato mai escluso per un peso mancante.
#
# Ultimo candidato come fallback finale dopo il ciclo (mai raggiunto in teoria: roll < total_weight
# per costruzione, garantisce che l'ultimo confronto cumulativo sia sempre vero) — solo per
# proteggere da un residuo di imprecisione in virgola mobile, stesso principio "mai un crash" già
# seguito ovunque nel progetto.
static func _pick_weighted_task(candidates: Array[Task], paths: Array[String]) -> Task:
	var total_weight: float = 0.0
	for path in paths:
		total_weight += float(IDLE_FALLBACK_TASK_WEIGHTS.get(path, 0.0))
	if total_weight <= 0.0:
		return candidates[randi() % candidates.size()]
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for i in range(candidates.size()):
		cumulative += float(IDLE_FALLBACK_TASK_WEIGHTS.get(paths[i], 0.0))
		if roll < cumulative:
			return candidates[i]
	return candidates[candidates.size() - 1]
