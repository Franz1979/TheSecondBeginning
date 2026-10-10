class_name JobBoardService
extends RefCounted

# Lista dei lavori (2026-10-07, richiesta utente — assegnazione compiti, passo A): i lavori senza nessuno assegnato
# (nessuna task in corso o in coda) compaiono nella sezione "In lista" del cassetto dell'assegnazione, "attivi"
# (disponibili per chiunque) o "bloccati" (fermi finché il giocatore non li sblocca). Vale solo con l'idea
# TaskAssignmentPanel.REQUIRED_IDEA_ID completata. La scheda "In sospeso" dell'info panel non dipende da questo stato.
#
# Stato in un punto unico, GameData.job_board_states (salvato), con le chiavi della scheda "In sospeso" ("build:<id>",
# in futuro "upgrade:", "demolish:", "produce:", "body:"). Oggi il solo tipo gestito è il cantiere di un edificio nuovo
# ("build"), dal 2026-10-07 il cantiere di un miglioramento ("upgrade", stesse regole: è un cantiere normale) e
# l'edificio "da demolire" senza demolitore ("demolish", fuori lista finché è aperto il suo mirino), dal 2026-10-09 gli
# ordini di produzione senza lavoratore ("produce:<id>:<ordine>", GameScene._produce_jobs_collect): un tipo
# nuovo si aggiunge a DEFAULT_STATE_BY_KIND (e a SKILL_KEY_BY_KIND per "Più adatto", KIND_NAME_KEYS per il nome).
#
# Passo B (2026-10-07): un pipottino libero prende da solo il lavoro attivo più adatto (try_take_job), chiamato SOLO da
# HumanIndividualActionService.resolve_idle_individual tra una task e l'altra — dopo bisogni, coda personale e
# rilascio del carico, prima delle attività di ripiego — mai durante una task o un'attività di ripiego. La scelta e
# l'assegnazione (stessa funzione dell'assegnazione a mano) le fa GameScene, che registra qui `job_taker`; la scelta tra
# i lavori prendibili è pick_job. Stateless, funzioni statiche (job_taker è l'unico dato, un aggancio, mai salvato).
#
# Priorità (2026-10-08, richiesta utente — sostituisce il vecchio punteggio bravura / (distanza + 10): la distanza non
# conta più, resta solo l'esclusione dei lavori irraggiungibili). Il giocatore sceglie un modo (PRIORITY_*) e, per
# "Personalizzata", l'ordine dei tipi; entrambi in GameData (salvati con la partita, non nelle preferenze). L'età di un
# lavoro è il momento di gioco (giorni assoluti con la frazione del giorno) in cui è entrato in coda la prima volta,
# GameData.job_board_entered_at, scritto da stamp_entered e tolto solo quando il lavoro non esiste più (forget_missing):
# "Rimetti in coda", un'interruzione o un ritorno in coda non lo azzerano.

# Attesa per l'assegnazione a mano (2026-10-07, richiesta utente): secondi reali (uguali a ogni velocità, fermi in pausa)
# dopo l'ingresso di un lavoro in lista (nato senza lavoratore o tornato in lista) durante i quali nessuno può prenderlo
# dalla lista; l'assegnazione a mano resta sempre possibile. 0 = nessuna attesa. Il conto lo tiene GameScene, mai salvato.
# Valore iniziale: dal 2026-10-07 il giocatore lo sceglie nelle impostazioni del cassetto (UserOptions.
# job_board_manual_assign_seconds, tra MIN e MAX); leggere sempre get_manual_assign_window_seconds().
const MANUAL_ASSIGN_WINDOW_SECONDS := 5.0
const MANUAL_ASSIGN_WINDOW_MIN_SECONDS := 0.0
const MANUAL_ASSIGN_WINDOW_MAX_SECONDS := 30.0

# Riparazione automatica (2026-10-10, regole di assegnazione del cassetto; dato della partita, GameData.
# job_board_auto_repair_percent): sotto questa Integrità (%) un edificio che deperisce riceve da solo la richiesta di
# riparazione (GameScene._auto_request_repairs). 0 = mai. Da 0 a 70 (la soglia del martello, Building.
# DURABILITY_REPAIRABLE_RATIO) a passi di 10. Partita nuova e salvataggi vecchi: AUTO_REPAIR_DEFAULT_PERCENT.
const AUTO_REPAIR_DEFAULT_PERCENT := 50
const AUTO_REPAIR_MIN_PERCENT := 0
const AUTO_REPAIR_MAX_PERCENT := 70
const AUTO_REPAIR_STEP_PERCENT := 10

const STATE_LISTED := "listed"
const STATE_LOCKED := "locked"
# Tipi di lavoro gestiti dalla lista -> stato iniziale (chiave assente in GameData.job_board_states).
# "body" (2026-10-07): corpi da seppellire; "pile" (2026-10-07): mucchi a terra abbandonati.
# "output" (2026-10-08): Prodotti finiti pieni che fermano un ordine, da consegnare a magazzino.
# "produce" (2026-10-09): ordini di produzione senza lavoratore ("produce:<id edificio>:<chiave ordine>").
# "cut" / "quarry" / "gather" (2026-10-09): ordini di taglio / estrazione / raccolta del cassetto ("order:<id>", tipo della voce;
# GameScene._drawer_cut_job).
# "repair" (2026-10-10): riparazioni richieste dal pannello edificio ("repair:<id edificio>", Building.repair_requested).
const DEFAULT_STATE_BY_KIND := {"build": STATE_LISTED, "upgrade": STATE_LISTED, "demolish": STATE_LISTED, "body": STATE_LISTED, "pile": STATE_LISTED, "output": STATE_LISTED, "produce": STATE_LISTED, "cut": STATE_LISTED, "quarry": STATE_LISTED, "gather": STATE_LISTED, "hunt": STATE_LISTED, "repair": STATE_LISTED}
# Tipo di lavoro -> chiave di SkillEffectService (skill_action_effects.tres) della sua skill (modo "Più adatto").
const SKILL_KEY_BY_KIND := {"build": "build", "upgrade": "build", "demolish": "build", "body": RiteAction.SKILL_EFFECT_KEY, "pile": "pickup", "output": "pickup", "produce": "produce", "cut": "cut", "quarry": "quarry", "gather": "pickup", "hunt": HuntService.SKILL_EFFECT_KEY, "repair": "build"}
# Tipo di lavoro -> icona di comando (IconRegistry) che lampeggia sull'edificio durante l'attesa per l'assegnazione a mano.
const ICON_KEY_BY_KIND := {"build": "build", "upgrade": "build", "demolish": "demolish", "body": "bury", "pile": "pickup", "output": "transport", "produce": "produce", "cut": "cut", "quarry": "quarry", "gather": "pickup", "hunt": "hunt", "repair": "build"}

# Modi di priorità (valori salvati in GameData.job_board_priority_mode, mai cambiarli).
const PRIORITY_BEST_FIT := "best_fit"
const PRIORITY_OLDEST := "oldest"
const PRIORITY_NEWEST := "newest"
const PRIORITY_CUSTOM := "custom"
# Ordine dei modi nello strato delle regole.
const PRIORITY_MODES: Array[String] = [PRIORITY_BEST_FIT, PRIORITY_OLDEST, PRIORITY_NEWEST, PRIORITY_CUSTOM]
const DEFAULT_PRIORITY_MODE := PRIORITY_BEST_FIT
# Modo -> chiave tr() del nome (strato delle regole e log); il tooltip è la stessa chiave con "_tooltip".
const PRIORITY_NAME_KEYS := {
	PRIORITY_BEST_FIT: "task_assignment_priority_best_fit",
	PRIORITY_OLDEST: "task_assignment_priority_oldest",
	PRIORITY_NEWEST: "task_assignment_priority_newest",
	PRIORITY_CUSTOM: "task_assignment_priority_custom",
}
# Ordine iniziale dei tipi per "Personalizzata". Un tipo nuovo di DEFAULT_STATE_BY_KIND che non è qui (né nell'ordine
# salvato) entra in fondo (get_kind_order).
# "hunt" (2026-10-09): ordini di caccia del cassetto, in fondo. "repair" (2026-10-10): riparazioni richieste, in fondo.
const DEFAULT_KIND_ORDER: Array[String] = ["body", "build", "upgrade", "demolish", "pile", "output", "produce", "cut", "quarry", "gather", "hunt", "repair"]
# Tipo -> chiave tr() del nome nell'elenco dei tipi e nel log.
const KIND_NAME_KEYS := {
	"body": "task_assignment_kind_body",
	"build": "task_assignment_kind_build",
	"upgrade": "task_assignment_kind_upgrade",
	"demolish": "task_assignment_kind_demolish",
	"pile": "task_assignment_kind_pile",
	"output": "task_assignment_kind_output",
	"produce": "task_assignment_kind_produce",
	"cut": "task_assignment_kind_cut",
	"quarry": "task_assignment_kind_quarry",
	"gather": "task_assignment_kind_gather",
	"hunt": "task_assignment_kind_hunt",
	"repair": "task_assignment_kind_repair",
}
# Due skill uguali entro questo scarto contano come pari (poi decide l'età).
const SKILL_TIE_EPSILON: float = 0.0001

# Callable(individual: HumanIndividual) -> bool, registrato da GameScene: guarda la lista e prova a far prendere a
# `individual` il lavoro più adatto; true = preso (ha una task nuova). Non valido fuori dalla scena di gioco.
static var job_taker: Callable = Callable()


# Attesa per l'assegnazione a mano in uso: l'impostazione del giocatore (UserOptions), nei limiti; mai scelta = il valore
# iniziale MANUAL_ASSIGN_WINDOW_SECONDS.
static func get_manual_assign_window_seconds() -> float:
	if UserOptions.job_board_manual_assign_seconds < 0:
		return MANUAL_ASSIGN_WINDOW_SECONDS
	return clampf(float(UserOptions.job_board_manual_assign_seconds), MANUAL_ASSIGN_WINDOW_MIN_SECONDS, MANUAL_ASSIGN_WINDOW_MAX_SECONDS)


# Soglia della riparazione automatica della partita (%), nei limiti e a passi di 10; senza partita il valore iniziale.
static func get_auto_repair_percent(game_data: GameData) -> int:
	if game_data == null:
		return AUTO_REPAIR_DEFAULT_PERCENT
	return clamp_auto_repair_percent(game_data.job_board_auto_repair_percent)


static func set_auto_repair_percent(game_data: GameData, percent: int) -> void:
	if game_data != null:
		game_data.job_board_auto_repair_percent = clamp_auto_repair_percent(percent)


static func clamp_auto_repair_percent(percent: int) -> int:
	return clampi(snappedi(percent, AUTO_REPAIR_STEP_PERCENT), AUTO_REPAIR_MIN_PERCENT, AUTO_REPAIR_MAX_PERCENT)


# Coda dell'assegnazione ATTIVA (2026-10-10, richiesta utente — punto unico): idea dell'assegnazione completata E almeno un
# punto di assegnazione completo e in funzione (CoordinatorService.is_valid_point: oggi il cerchio di sassi; cantieri,
# miglioramenti in corso ed edifici da demolire non contano). Altrimenti il gioco si comporta come senza l'idea: nessuno
# prende lavori da solo, niente riparazione automatica, assegnazione solo a mano. Tutti i controlli "con l'idea" ai fini
# dell'assegnazione passano da qui; la sola idea è is_idea_completed.
static func is_enabled(folk: Folk) -> bool:
	return is_idea_completed(folk) and has_assignment_point()


# true con l'idea dell'assegnazione completata dal popolo del giocatore (con o senza punto di assegnazione).
static func is_idea_completed(folk: Folk) -> bool:
	return folk != null and folk.completed_ideas.has(TaskAssignmentPanel.REQUIRED_IDEA_ID)


# Callable() -> World, registrato da GameScene: il mondo in cui cercare i punti di assegnazione.
static var world_provider: Callable = Callable()


# true se nel mondo c'è almeno un punto di assegnazione completo e in funzione.
static func has_assignment_point() -> bool:
	var world: World = world_provider.call() if world_provider.is_valid() else null
	if world == null:
		return false
	for building in world.buildings:
		if CoordinatorService.is_valid_point(building):
			return true
	return false


# Tipo del lavoro dalla chiave ("build:12" -> "build").
static func get_kind(job_key: String) -> String:
	return job_key.get_slice(":", 0)


# Ordini creati dal cassetto (2026-10-09, GameData.drawer_orders): chiave "order:<id>". Il prefisso non è un tipo: il
# tipo della voce (priorità, skill, "Più adatto") lo dà l'ordine (es. "produce", lo stesso degli ordini dei pannelli).
# Stato iniziale: attivo.
const DRAWER_ORDER_KEY_PREFIX := "order"


static func drawer_order_key(order_id: int) -> String:
	return "%s:%d" % [DRAWER_ORDER_KEY_PREFIX, order_id]


# true se il tipo del lavoro passa dalla lista.
static func is_managed(job_key: String) -> bool:
	var kind := get_kind(job_key)
	return DEFAULT_STATE_BY_KIND.has(kind) or kind == DRAWER_ORDER_KEY_PREFIX


static func get_state(game_data: GameData, job_key: String) -> String:
	var kind := get_kind(job_key)
	var default_state := STATE_LISTED if kind == DRAWER_ORDER_KEY_PREFIX else String(DEFAULT_STATE_BY_KIND.get(kind, STATE_LOCKED))
	if game_data == null:
		return default_state
	var state := String(game_data.job_board_states.get(job_key, default_state))
	# "suspended" e "paused" = nomi di prima di "bloccato" (stesso giorno), letti come bloccato.
	return STATE_LOCKED if state == "suspended" or state == "paused" else state


static func set_state(game_data: GameData, job_key: String, state: String) -> void:
	if game_data == null or not is_managed(job_key):
		return
	game_data.job_board_states[job_key] = state


# Skill di `individual` per un tipo di lavoro: fattore di SkillEffectService della chiave SKILL_KEY_BY_KIND (1.0 se il
# tipo non ne ha).
static func get_job_skill(individual: HumanIndividual, job_kind: String) -> float:
	var skill_key := String(SKILL_KEY_BY_KIND.get(job_kind, ""))
	return SkillEffectService.get_factor(skill_key, individual) if skill_key != "" else 1.0


# --- Priorità (2026-10-08) ---

static func get_priority_mode(game_data: GameData) -> String:
	if game_data == null or not PRIORITY_MODES.has(game_data.job_board_priority_mode):
		return DEFAULT_PRIORITY_MODE
	return game_data.job_board_priority_mode


static func set_priority_mode(game_data: GameData, mode: String) -> void:
	if game_data != null and PRIORITY_MODES.has(mode):
		game_data.job_board_priority_mode = mode


# Ordine dei tipi per "Personalizzata": quello salvato (solo tipi esistenti, senza doppioni), poi i tipi mancanti
# nell'ordine iniziale, poi qualunque tipo gestito ancora assente (un tipo aggiunto in futuro entra in fondo).
static func get_kind_order(game_data: GameData) -> Array[String]:
	var order: Array[String] = []
	if game_data != null:
		for kind in game_data.job_board_kind_order:
			if DEFAULT_STATE_BY_KIND.has(kind) and not order.has(kind):
				order.append(kind)
	for kind in DEFAULT_KIND_ORDER:
		if not order.has(kind):
			order.append(kind)
	for kind in DEFAULT_STATE_BY_KIND.keys():
		if not order.has(String(kind)):
			order.append(String(kind))
	return order


static func set_kind_order(game_data: GameData, order: Array[String]) -> void:
	if game_data == null:
		return
	game_data.job_board_kind_order = order.duplicate()


static func get_priority_name(mode: String) -> String:
	return TranslationServer.translate(String(PRIORITY_NAME_KEYS.get(mode, mode)))


static func get_kind_name(kind: String) -> String:
	return TranslationServer.translate(String(KIND_NAME_KEYS.get(kind, kind)))


# Età: segna l'ingresso in coda dei lavori di `jobs` (voci con "key") che non l'hanno ancora, al momento `now` (giorni
# assoluti di gioco con la frazione). Mai prima dell'ingresso più recente già segnato: dopo un caricamento la frazione
# del giorno riparte da zero, e un lavoro nuovo non deve risultare più vecchio di uno già in coda.
static func stamp_entered(game_data: GameData, jobs: Array, now: float) -> void:
	if game_data == null:
		return
	var stamp := now
	for value in game_data.job_board_entered_at.values():
		stamp = maxf(stamp, float(value))
	for job in jobs:
		var key := String(job["key"])
		if not game_data.job_board_entered_at.has(key):
			game_data.job_board_entered_at[key] = stamp


# Momento d'ingresso in coda di `job_key`; INF se non è mai stato segnato (conta come il più recente).
static func get_entered_at(game_data: GameData, job_key: String) -> float:
	if game_data == null:
		return INF
	return float(game_data.job_board_entered_at.get(job_key, INF))


# true se `a` è entrato in coda prima di `b` (a parità, decide la chiave: ordine stabile).
static func _is_older(game_data: GameData, a: Dictionary, b: Dictionary) -> bool:
	var entered_a := get_entered_at(game_data, String(a["key"]))
	var entered_b := get_entered_at(game_data, String(b["key"]))
	if entered_a != entered_b:
		return entered_a < entered_b
	return String(a["key"]) < String(b["key"])


static func _oldest(game_data: GameData, jobs: Array) -> Dictionary:
	var best: Dictionary = {}
	for job in jobs:
		if best.is_empty() or _is_older(game_data, job, best):
			best = job
	return best


static func _newest(game_data: GameData, jobs: Array) -> Dictionary:
	var best: Dictionary = {}
	for job in jobs:
		if best.is_empty() or _is_older(game_data, best, job):
			best = job
	return best


# Scelta tra i lavori PRENDIBILI di `individual` (esclusioni già fatte dal chiamante: bloccati, attesa, non adatto,
# irraggiungibili, impossibili per ora), secondo il modo attivo:
#   - "Più adatto": skill più alta (get_job_skill), a parità il più vecchio;
#   - "Prima i più vecchi" / "Prima i più recenti": per età;
#   - "Personalizzata": il primo tipo dell'ordine con almeno un lavoro, dentro il tipo il più vecchio.
# Ritorna {"job": voce scelta, "reason": testo per il log}; {} se `jobs` è vuoto.
static func pick_job(game_data: GameData, individual: HumanIndividual, jobs: Array) -> Dictionary:
	if jobs.is_empty():
		return {}
	var mode := get_priority_mode(game_data)
	var mode_name := get_priority_name(mode)
	match mode:
		PRIORITY_OLDEST:
			return {"job": _oldest(game_data, jobs), "reason": mode_name}
		PRIORITY_NEWEST:
			return {"job": _newest(game_data, jobs), "reason": mode_name}
		PRIORITY_CUSTOM:
			for kind in get_kind_order(game_data):
				var of_kind: Array = jobs.filter(func(job: Dictionary) -> bool: return String(job["kind"]) == kind)
				if not of_kind.is_empty():
					return {"job": _oldest(game_data, of_kind), "reason": "%s, %s" % [mode_name, get_kind_name(kind)]}
			return {"job": _oldest(game_data, jobs), "reason": mode_name}
	var best: Dictionary = {}
	var best_skill := 0.0
	for job in jobs:
		var skill := get_job_skill(individual, String(job["kind"]))
		if best.is_empty() or skill > best_skill + SKILL_TIE_EPSILON \
				or (absf(skill - best_skill) <= SKILL_TIE_EPSILON and _is_older(game_data, job, best)):
			best = job
			best_skill = skill
	return {"job": best, "reason": "%s, skill %s" % [mode_name, str(snappedf(best_skill, 0.01))]}


# Ordine delle righe "In coda" del cassetto secondo il modo attivo (in place): "Più adatto" e "Prima i più vecchi" dal
# più vecchio, "Prima i più recenti" dal più recente, "Personalizzata" per tipo (ordine del giocatore) e poi dal più
# vecchio.
static func sort_for_display(game_data: GameData, jobs: Array) -> void:
	var mode := get_priority_mode(game_data)
	if mode == PRIORITY_NEWEST:
		jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _is_older(game_data, b, a))
	elif mode == PRIORITY_CUSTOM:
		var order := get_kind_order(game_data)
		jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var index_a := order.find(String(a["kind"]))
			var index_b := order.find(String(b["kind"]))
			if index_a != index_b:
				return index_a < index_b
			return _is_older(game_data, a, b)
		)
	else:
		jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _is_older(game_data, a, b))


# --- Punto di assegnazione e "Cerca lavoro" (2026-10-09, coordinatore passo 1) ---
# Con un punto di assegnazione (BuildingRules.is_assignment_point, completo e non da demolire) raggiungibile e almeno un
# lavoro della lista che l'individuo può prendere (job_available_checker, gli stessi filtri della presa), l'individuo
# libero riceve "Cerca lavoro" verso il punto più vicino; arrivato, prende il lavoro con try_take_job come prima.

const SEEK_JOB_TASK_PATH := "res://gameplay/scripts/tasks/definitions/seek_job.tres"
const SEEK_JOB_TASK_NAME := "task_seek_job_name"

# Esito di try_seek_job: NO_POINT = nessun punto di assegnazione raggiungibile (presa diretta come prima); STARTED =
# "Cerca lavoro" assegnata; NOTHING = punto c'è, ma nessun lavoro per lui (o assegnazione fallita): svago.
enum SeekOutcome { NO_POINT, STARTED, NOTHING }

# Callable(individual: HumanIndividual) -> bool, registrato da GameScene: c'è almeno un lavoro della lista che
# `individual` può prendere adesso (stessi controlli della presa, senza prenderlo).
static var job_available_checker: Callable = Callable()
# Callable() -> bool, registrato da GameScene (2026-10-09, coordinatore): la coda ha almeno un lavoro non bloccato.
static var queue_has_jobs_checker: Callable = Callable()


static func queue_has_jobs() -> bool:
	return queue_has_jobs_checker.is_valid() and bool(queue_has_jobs_checker.call())


# Callable() -> int, registrato da GameScene (2026-10-09, richiamo del coordinatore): lavori della coda prendibili adesso
# (senza nessuno, non bloccati, fuori dall'attesa per l'assegnazione a mano).
static var open_jobs_counter: Callable = Callable()


static func open_jobs_count() -> int:
	return int(open_jobs_counter.call()) if open_jobs_counter.is_valid() else 0


# Punto di assegnazione completo, non da demolire e raggiungibile più vicino a `individual`; null se nessuno.
static func find_assignment_point(individual: HumanIndividual, world: World) -> Building:
	if individual == null or world == null:
		return null
	var is_point := func(building: Building) -> bool:
		return building.rules != null and building.rules.is_assignment_point and building.is_complete \
			and not building.is_demolished and not building.is_marked_for_demolition
	return SpatialSelectionService.find_nearest(
		world.buildings, individual.position, individual.home_macro_coords, is_point, [],
		PathfindingService.reachability_for(individual)
	) as Building


static func try_seek_job(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> SeekOutcome:
	var point := find_assignment_point(individual, world)
	if point == null:
		return SeekOutcome.NO_POINT
	if not job_available_checker.is_valid() or not bool(job_available_checker.call(individual)):
		return SeekOutcome.NOTHING
	return SeekOutcome.STARTED if start_seek_job(individual, age_band, point) else SeekOutcome.NOTHING


# "Cerca lavoro" verso il punto `point` (2026-10-09: estratto da try_seek_job, usato anche dal richiamo del
# coordinatore). Nessun controllo sui lavori: lo fa il chiamante. true = assegnata.
static func start_seek_job(individual: HumanIndividual, age_band: HumanTypes.AgeBand, point: Building) -> bool:
	var definition := load(SEEK_JOB_TASK_PATH) as TaskDefinition
	if definition == null or point == null:
		return false
	var macro_offset := Vector2(Vector2i(point.macro_x, point.macro_y) - individual.home_macro_coords) * World.WIDTH
	# Punto nel context (2026-10-09): lì aspetta il coordinatore (CoordinatorService), senza tetto di attesa.
	var task := TaskFactory.build_task(definition, {
		"target_position": PathfindingService.random_point_in_microcell(Vector2(point.micro_x, point.micro_y) + macro_offset),
		CoordinatorService.CONTEXT_POINT_ID: point.id,
	})
	if not individual.assign_task(task, age_band):
		return false
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] #%d %s: c'è un lavoro per lui — va a cercarlo al punto di assegnazione %s #%d." % [
			individual.id, individual.name, point.building_type_name, point.id
		])
	return true


# Punto d'ingresso di resolve_idle_individual: true se `individual` ha preso un lavoro dalla lista.
static func try_take_job(individual: HumanIndividual) -> bool:
	if individual == null or not job_taker.is_valid():
		return false
	return bool(job_taker.call(individual))


# Toglie le voci dei lavori che non esistono più (`existing_keys`: chiave -> true dei lavori ancora da fare, assegnati
# o no). Un lavoro che qualcuno sta facendo resta, così se viene abbandonato torna dov'era.
static func forget_missing(game_data: GameData, existing_keys: Dictionary) -> void:
	if game_data == null:
		return
	for job_key in game_data.job_board_states.keys():
		if not existing_keys.has(job_key):
			game_data.job_board_states.erase(job_key)
	# Età (2026-10-08): resta finché il lavoro esiste, anche mentre qualcuno lo fa.
	for job_key in game_data.job_board_entered_at.keys():
		if not existing_keys.has(job_key):
			game_data.job_board_entered_at.erase(job_key)
