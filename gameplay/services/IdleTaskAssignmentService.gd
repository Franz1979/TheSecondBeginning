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
]

# DEBUG: rimettere a true a fine sessione di debug
const WANDER_ENABLED := false

# Lunghezza min/max (in microcelle) di ciascun tratto casuale di Wander/Play — STESSO valore/STESSO
# principio già in uso prima di questo spostamento (vedi GameScene.gd, ora rimosso da lì).
const WANDER_LEG_MIN_LENGTH: float = 4.0
const WANDER_LEG_MAX_LENGTH: float = 8.0


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
static func _build_idle_task(path: String, individual: HumanIndividual) -> Task:
	match path:
		"res://gameplay/scripts/tasks/definitions/wander.tres":
			if not WANDER_ENABLED: # DEBUG: rimettere a true a fine sessione di debug
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
# Un solo candidato -> usato direttamente (nessun tiro). Più di uno -> randi() % candidates.size().
# Zero candidati dopo il filtro (caso limite — non dovrebbe succedere: Wander è compatibile con
# tutte le età sopra INFANT) -> ritorna false, nessun effetto collaterale: il chiamante decide cosa
# fare (oggi, individual.stop() come fallback finale).
#
# `world` (2026-09-13) — non ancora consultato da nessuna delle Task perditempo di oggi (Wander/
# Play non ne hanno bisogno), tenuto in firma per non dover cambiare il chiamante quando una futura
# Task perditempo ne avrà bisogno (stesso principio "deviazione firma anticipata" già visto per
# `world`/`game_data` in HumanIndividualActionService.apply_action).
#
# Ritorna true/false (esito di individual.assign_task, o false se nessun candidato) — stesso
# principio "il chiamante sa se è davvero riuscita" già seguito da NeedTaskAssignmentService.
# assign_rest_task/assign_emergency_rest_task.
static func assign_idle_fallback(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	var candidates: Array[Task] = []
	for path in IDLE_FALLBACK_TASK_PATHS:
		var candidate_task := _build_idle_task(path, individual)
		if candidate_task != null and individual.can_assign_task(candidate_task, age_band):
			candidates.append(candidate_task)
	if candidates.is_empty():
		return false
	var chosen_task: Task = candidates[0] if candidates.size() == 1 else candidates[randi() % candidates.size()]
	var assigned := individual.assign_task(chosen_task, age_band)
	if assigned and DebugLogging.ENABLED:
		print("[IDLE FALLBACK] #%d %s: nessuna Task/bisogno/coda attivi — assegnata '%s' (%d candidate compatibili con age_band=%s)." % [
			individual.id, individual.name, chosen_task.task_name, candidates.size(), HumanTypes.AgeBand.keys()[age_band]
		])
	return assigned
