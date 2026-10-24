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
# ordini di produzione senza lavoratore ("produce:<id>:<ordine>", ProduceJobProvider.collect): un tipo
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
# riparazione (BuildingMaintenanceService.auto_request_repairs). 0 = mai. Da 0 a 70 (la soglia del martello, Building.
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
# DrawerOrderJobProvider._zone_job).
# "repair" (2026-10-10): riparazioni richieste dal pannello edificio ("repair:<id edificio>", Building.repair_requested).
# "inventory" (2026-10-11): inventario del magazzino ("inventory:0", uno alla volta; InventoryJobProvider.collect).
# "rite" (2026-10-14): riti ordinati dal pannello edificio ("rite:<id edificio>", Building.requested_rite_id).
const DEFAULT_STATE_BY_KIND := {"build": STATE_LISTED, "upgrade": STATE_LISTED, "demolish": STATE_LISTED, "body": STATE_LISTED, "pile": STATE_LISTED, "output": STATE_LISTED, "produce": STATE_LISTED, "cut": STATE_LISTED, "quarry": STATE_LISTED, "gather": STATE_LISTED, "hunt": STATE_LISTED, "repair": STATE_LISTED, "inventory": STATE_LISTED, "rite": STATE_LISTED, "site_cut": STATE_LISTED}
# Tipo di lavoro -> chiave di SkillEffectService (skill_action_effects.tres) della sua skill (modo "Più adatto").
const SKILL_KEY_BY_KIND := {"build": "build", "upgrade": "build", "demolish": "build", "body": RiteAction.SKILL_EFFECT_KEY, "pile": "pickup", "output": "pickup", "produce": "produce", "cut": "cut", "quarry": "quarry", "gather": "pickup", "hunt": HuntService.SKILL_EFFECT_KEY, "repair": "build", "inventory": InventoryAction.SKILL_EFFECT_KEY, "rite": RiteAction.SKILL_EFFECT_KEY, "site_cut": "cut"}
# Tipo di lavoro -> icona di comando (IconRegistry) che lampeggia sull'edificio durante l'attesa per l'assegnazione a mano.
const ICON_KEY_BY_KIND := {"build": "build", "upgrade": "build", "demolish": "demolish", "body": "bury", "pile": "pickup", "output": "transport", "produce": "produce", "cut": "cut", "quarry": "quarry", "gather": "pickup", "hunt": "hunt", "repair": "build", "inventory": "transport", "rite": "rite", "site_cut": "cut"}

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
# "inventory" (2026-10-11): l'inventario del magazzino, per primo (senza di lui non escono gli ordini del magazzino).
const DEFAULT_KIND_ORDER: Array[String] = ["inventory", "body", "build", "upgrade", "demolish", "pile", "output", "produce", "site_cut", "cut", "quarry", "gather", "hunt", "repair", "rite"]
# Tipo -> chiave tr() del nome nell'elenco dei tipi e nel log.
const KIND_NAME_KEYS := {
	"site_cut": "task_assignment_kind_site_cut",
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
	"inventory": "task_assignment_kind_inventory",
	"rite": "task_assignment_kind_rite",
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
# Dal 2026-10-24 (assegnatore fase 1) la partenza non chiede più job_available_checker: can_depart_to_seek più sotto.

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

# --- Risposte di job_available_checker in memoria (2026-10-23, scatti: il coordinatore e "Cerca lavoro" facevano la
# domanda per più pipottini nello stesso fotogramma, 25–70 ms l'una) ---
# Una risposta vale fino a AVAILABILITY_MAX_AGE_MSEC e finché nessuno prende un lavoro (take_revision). La presa vera
# (take_job) ricalcola sempre da capo: una risposta vecchia sposta solo una decisione di al massimo ~1,5 s. (Il
# riscaldamento a turno su più fotogrammi, provato lo stesso giorno, è stato tolto su richiesta dell'utente: tanti
# piccoli scatti invece di uno raro.)
const AVAILABILITY_MAX_AGE_MSEC := 1500
static var take_revision: int = 0
static var _availability: Dictionary = {}  # id individuo -> {"result": bool, "time": int msec, "revision": int}


# Risposta in memoria per `worker` (null se manca o non vale più).
static func cached_availability(worker: HumanIndividual) -> Variant:
	var entry: Variant = _availability.get(worker.id)
	if entry == null or int(entry["revision"]) != take_revision \
			or Time.get_ticks_msec() - int(entry["time"]) >= AVAILABILITY_MAX_AGE_MSEC:
		return null
	return bool(entry["result"])


static func store_availability(worker: HumanIndividual, result: bool) -> void:
	if _availability.size() > 512:
		_availability.clear()
	_availability[worker.id] = {"result": result, "time": Time.get_ticks_msec(), "revision": take_revision}


static func queue_has_jobs() -> bool:
	return queue_has_jobs_checker.is_valid() and bool(queue_has_jobs_checker.call())


# Callable() -> int, registrato da GameScene (2026-10-09, richiamo del coordinatore): lavori della coda prendibili adesso
# (senza nessuno, non bloccati, fuori dall'attesa per l'assegnazione a mano).
static var open_jobs_counter: Callable = Callable()


static func open_jobs_count() -> int:
	return int(open_jobs_counter.call()) if open_jobs_counter.is_valid() else 0


# --- Partenza verso il punto (2026-10-24, assegnatore fase 1, docs/progetto_assegnatore_unico_lavori.md) ---
# Il pipottino libero va a vedere al punto senza chiedersi se un lavoro è adatto a lui (lo decide il coordinatore, al
# punto; viaggio a vuoto accettato). Parte solo se i lavori aperti dell'ultimo giro della lista (open_job_keys, giro al
# secondo) sono più di chi cerca già lavoro in tutto il villaggio (seekers_count: in cammino o in fila).

# true se i lavori aperti dell'ultimo giro sono più di chi cerca già lavoro e `individual` non ha già fatto un viaggio a
# vuoto con gli stessi lavori aperti (is_waiting_after_empty_trip).
static func can_depart_to_seek(game_data: GameData, individual: HumanIndividual) -> bool:
	if game_data == null:
		return false
	var runtime := game_data.job_board_runtime
	if runtime.open_job_keys.size() <= runtime.seekers_count:
		return false
	return not is_waiting_after_empty_trip(game_data, individual)


# Viaggio a vuoto (2026-10-24, richiesta utente): `individual` è arrivato al punto e non ha preso nessun lavoro. Non
# riparte (né viene richiamato) finché l'insieme dei lavori aperti non cambia (open_jobs_revision).
static func note_empty_trip(game_data: GameData, individual: HumanIndividual) -> void:
	if game_data != null and individual != null:
		game_data.job_board_runtime.empty_trip_revision[individual.id] = game_data.job_board_runtime.open_jobs_revision


# true se `individual` ha fatto un viaggio a vuoto e i lavori aperti sono ancora gli stessi; a lavori cambiati il segno
# si toglie.
static func is_waiting_after_empty_trip(game_data: GameData, individual: HumanIndividual) -> bool:
	if game_data == null or individual == null:
		return false
	var runtime := game_data.job_board_runtime
	if not runtime.empty_trip_revision.has(individual.id):
		return false
	if int(runtime.empty_trip_revision[individual.id]) == runtime.open_jobs_revision:
		return true
	runtime.empty_trip_revision.erase(individual.id)
	return false


# Lavori aperti all'ultimo giro della lista (richiamo del coordinatore): letti, mai ricalcolati.
static func last_open_jobs_count(game_data: GameData) -> int:
	return game_data.job_board_runtime.open_job_keys.size() if game_data != null else 0


# Riconta chi ha "Cerca lavoro" in corso (in cammino o in fila al punto, non ancora rilasciato): giro al secondo.
static func recount_seekers(game_data: GameData, individuals: Array[HumanIndividual]) -> void:
	if game_data == null:
		return
	var count := 0
	for member in individuals:
		var task := member.current_task
		if task == null or task.is_finished() or task.task_name != SEEK_JOB_TASK_NAME:
			continue
		var wait_action := task.get_current_action() as WaitAtPointAction
		if wait_action != null and wait_action.released:
			continue
		count += 1
	game_data.job_board_runtime.seekers_count = count


# Punto di assegnazione completo, non da demolire e raggiungibile più vicino a `individual`; null se nessuno.
static func find_assignment_point(individual: HumanIndividual, world: World) -> Building:
	if individual == null or world == null:
		return null
	var is_point := func(building: Building) -> bool:
		return building.rules != null and building.rules.is_assignment_point and building.is_complete \
			and not building.is_demolished and not building.is_out_of_service()
	return SpatialSelectionService.find_nearest(
		world.buildings, individual.position, individual.home_macro_coords, is_point, [],
		PathfindingService.reachability_for(individual)
	) as Building


# Assegnatore fase 1 (2026-10-24): niente più domanda "c'è un lavoro per lui?" (job_available_checker) prima di partire;
# basta can_depart_to_seek, letto dall'ultimo giro della lista. L'idoneità la verifica il coordinatore al punto.
static func try_seek_job(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> SeekOutcome:
	if not can_depart_to_seek(GameSettings.active_game_data, individual):
		return SeekOutcome.NOTHING
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	var point := find_assignment_point(individual, world)
	if timing:
		JobBoardTimingService.add("punto più vicino", started)
	if point == null:
		return SeekOutcome.NO_POINT
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
	# Assegnatore fase 1 (2026-10-24): conta subito tra chi cerca lavoro, fino al prossimo riconteggio (recount_seekers).
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null:
		game_data.job_board_runtime.seekers_count += 1
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] #%d %s: va a vedere al punto di assegnazione %s #%d (%d lavori aperti, %d cercano lavoro)." % [
			individual.id, individual.name, point.building_type_name, point.id, last_open_jobs_count(game_data),
			game_data.job_board_runtime.seekers_count if game_data != null else 0,
		])
	return true


# Punto d'ingresso di resolve_idle_individual: true se `individual` ha preso un lavoro dalla lista.
static func try_take_job(individual: HumanIndividual) -> bool:
	if individual == null or not job_taker.is_valid():
		return false
	JobBoardTimingService.caller = "arrivo"
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


# ============================================================================================
# Nucleo della lista (2026-10-17, refactoring GameScene blocco 2a — estratto da GameScene, regole invariate): candidati,
# attese per l'assegnazione a mano, lavori aperti, scelta e presa. Lo stato che vive solo in partita sta in
# GameData.job_board_runtime (JobBoardRuntimeState). Le voci dei lavori arrivano dai fornitori ("collect"), e la task di
# prova, l'idoneità e l'assegnazione vera sono le Callable del fornitore nella voce (job["provider"]). Le icone
# lampeggianti dell'attesa e la stampa del log restano alla scena.
# ============================================================================================

# Fa avanzare l'orologio delle attese: secondi reali, solo a gioco in corso (lo decide chi chiama).
static func advance_clock(game_data: GameData, delta: float) -> void:
	game_data.job_board_runtime.clock += delta


# Lavori gestiti dalla lista senza nessuno assegnato (o con posti liberi, "open_slots" — 2026-10-17, cantieri con più
# costruttori) e non nascosti, bloccati compresi: chiave -> voce. Fuori i lavori
# impossibili per ora ("blocked_reason", es. un mucchio che nessun magazzino accetta): restano visibili nel cassetto ma
# non entrano nell'attesa né si prendono; quando tornano possibili entrano come un lavoro nuovo (parte l'attesa).
static func collect_candidates(jobs: Array[Dictionary]) -> Dictionary:
	var candidates: Dictionary = {}
	for job in jobs:
		var takeable := not bool(job["assigned"]) or int(job.get("open_slots", 0)) > 0
		if takeable and not bool(job["hidden"]) and String(job.get("blocked_reason", "")) == "":
			candidates[String(job["key"])] = job
	return candidates


# Secondi reali che mancano alla fine dell'attesa di `job_key`; 0 se finita o se il lavoro non è in lista.
static func get_wait_seconds(game_data: GameData, job_key: String) -> float:
	var runtime := game_data.job_board_runtime
	if not runtime.waiting_since.has(job_key):
		return 0.0
	return maxf(0.0, get_manual_assign_window_seconds() - (runtime.clock - float(runtime.waiting_since[job_key])))


# Ingressi e uscite dalla lista rispetto all'ultima lettura. `candidates`: chiave -> voce (collect_candidates).
static func sync_waits(game_data: GameData, candidates: Dictionary) -> void:
	var runtime := game_data.job_board_runtime
	for key in runtime.waiting_since.keys():
		if not candidates.has(key):
			runtime.waiting_since.erase(key)
	for key in candidates.keys():
		if not runtime.waiting_since.has(key):
			# Inventario (2026-10-11, richiesta utente): niente attesa per l'assegnazione a mano, subito prendibile.
			var no_wait := not runtime.waits_initialized or String(candidates[key].get("kind", "")) == "inventory"
			runtime.waiting_since[key] = runtime.clock - get_manual_assign_window_seconds() if no_wait else runtime.clock
	runtime.waits_initialized = true


# Senza l'idea dell'assegnazione: niente attese; alla prossima lettura i lavori già in lista sono subito prendibili.
static func reset_waits(game_data: GameData) -> void:
	game_data.job_board_runtime.waiting_since.clear()
	game_data.job_board_runtime.waits_initialized = false


# Lavoro appena assegnato (`job_keys`: tutte le sue chiavi possibili): fuori dal conto dell'attesa.
static func forget_waits(game_data: GameData, job_keys: Array[String]) -> void:
	for key in job_keys:
		game_data.job_board_runtime.waiting_since.erase(key)


# Lavoro sbloccato dal giocatore (2026-10-07): subito prendibile, nessuna attesa.
static func end_wait(game_data: GameData, job_key: String) -> void:
	var runtime := game_data.job_board_runtime
	if runtime.waiting_since.has(job_key):
		runtime.waiting_since[job_key] = runtime.clock - get_manual_assign_window_seconds()


# Chiavi dei lavori prendibili adesso: senza nessuno, non bloccati, fuori dall'attesa per l'assegnazione a mano.
static func open_job_keys(game_data: GameData, candidates: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	for job_key in candidates.keys():
		if get_state(game_data, job_key) == STATE_LOCKED:
			continue
		if get_wait_seconds(game_data, job_key) > 0.0:
			continue
		keys[job_key] = true
	return keys


# Richiamo del coordinatore (2026-10-09): un lavoro diventato prendibile (nuovo in coda o finita la sua attesa) è un
# evento per i coordinatori che aspettano senza fila (CoordinatorService.on_jobs_available).
static func notify_new_open_jobs(game_data: GameData, folk: Folk, jobs: Array[Dictionary]) -> void:
	var runtime := game_data.job_board_runtime
	if not is_enabled(folk):
		runtime.open_job_keys.clear()
		return
	var open_keys := open_job_keys(game_data, collect_candidates(jobs))
	var has_new := false
	for job_key in open_keys.keys():
		if not runtime.open_job_keys.has(job_key):
			has_new = true
			break
	# Viaggi a vuoto (2026-10-24): insieme dei lavori aperti cambiato (entrato o uscito un lavoro), nuova revisione.
	if has_new or open_keys.size() != runtime.open_job_keys.size():
		runtime.open_jobs_revision += 1
	runtime.open_job_keys = open_keys
	if has_new:
		CoordinatorService.on_jobs_available()


# La coda ha almeno un lavoro senza nessuno, non bloccato (CoordinatorService: fine del turno).
static func has_open_jobs(game_data: GameData, candidates: Dictionary) -> bool:
	for job_key in candidates.keys():
		if get_state(game_data, job_key) != STATE_LOCKED:
			return true
	return false


# Lavori della lista che `worker` può prendere adesso tra i `candidates`: {"jobs": Array[Dictionary], "found_text": testo
# per il log, "log": riga del "nessuno preso" ("" = nessuna)}; "jobs" vuoto = nessuno. Filtri: bloccati, attesa per
# l'assegnazione a mano, idoneità con una task di prova per tipo di task ("rejection" del fornitore: età ed energia
# dipendono dal pipottino e dalla task, non dal singolo lavoro), raggiungibilità, materiali troppo pesanti.
# `now`: momento di gioco per l'età dei lavori (stamp_entered).
# Tempi (2026-10-24, fase 0 dell'assegnatore, JobBoardTimingService): attese ed età, idoneità per tipo di lavoro
# ("idoneità:<tipo>"), raggiungibilità e materiali troppo pesanti.
static func find_takeable_jobs(worker: HumanIndividual, game_data: GameData, candidates: Dictionary, now: float) -> Dictionary:
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	sync_waits(game_data, candidates)
	# Età (2026-10-08): un lavoro comparso dopo l'ultimo giro del cassetto viene segnato qui, prima della scelta.
	stamp_entered(game_data, candidates.values(), now)
	if timing:
		JobBoardTimingService.add("attese ed età", started)
	var open_jobs: Array[Dictionary] = []
	var locked_count := 0
	var waiting_count := 0
	for job_key in candidates.keys():
		if get_state(game_data, job_key) == STATE_LOCKED:
			locked_count += 1
			continue
		if get_wait_seconds(game_data, job_key) > 0.0:
			waiting_count += 1
			continue
		open_jobs.append(candidates[job_key])
	var found_text := "%d in lista (%d bloccati, %d in attesa)" % [open_jobs.size() + locked_count + waiting_count, locked_count, waiting_count]
	var no_jobs: Array[Dictionary] = []
	var none := {"jobs": no_jobs, "found_text": found_text, "log": ""}
	if open_jobs.is_empty():
		# Lista vuota: nessuna riga (2026-10-07, riempiva la console senza dire niente).
		if waiting_count > 0:
			none["log"] = "%s — nessuno preso: solo lavori in attesa di assegnazione." % found_text
		elif locked_count > 0:
			none["log"] = "%s — nessuno preso: tutti bloccati." % found_text
		return none
	var rejection_by_probe: Dictionary = {}
	var suitable_jobs: Array[Dictionary] = []
	for job in open_jobs:
		var probe_key := String(job["provider"]["probe_key"].call(job))
		if not rejection_by_probe.has(probe_key):
			started = JobBoardTimingService.now() if timing else 0
			rejection_by_probe[probe_key] = String(job["provider"]["rejection"].call(worker, job))
			if timing:
				JobBoardTimingService.add("idoneità:%s" % String(job["kind"]), started)
		if String(rejection_by_probe[probe_key]) == HumanIndividual.ASSIGN_OK:
			suitable_jobs.append(job)
	if suitable_jobs.is_empty():
		var reasons: Array[String] = []
		for probe_key in rejection_by_probe.keys():
			reasons.append(String(rejection_by_probe[probe_key]))
		none["log"] = "%s — nessuno preso: non adatto (%s)." % [found_text, ", ".join(reasons)]
		return none
	var reachable := PathfindingService.reachability_for(worker)
	var takeable_jobs: Array[Dictionary] = []
	# Materiali troppo pesanti (2026-10-16): costruzione e riparazione solo a chi porta almeno un'unità di ogni
	# materiale ancora mancante (MaterialSupplyService.get_uncarryable_materials, cintura attuale).
	var too_heavy: Array[String] = []
	started = JobBoardTimingService.now() if timing else 0
	for job in suitable_jobs:
		if not reachable.call(job["reach_target"]):
			continue
		var kind := String(job["kind"])
		if kind == "build" or kind == "upgrade" or kind == "repair":
			var heavy := MaterialSupplyService.get_uncarryable_materials(worker, job["target"], kind == "repair")
			if not heavy.is_empty():
				too_heavy.append("%s: %s" % [String(job["log_name"]), ", ".join(heavy)])
				continue
		takeable_jobs.append(job)
	if timing:
		JobBoardTimingService.add("raggiungibilità e materiali", started)
	if takeable_jobs.is_empty():
		if too_heavy.is_empty():
			none["log"] = "%s — nessuno preso: non adatto (nessun lavoro raggiungibile)." % found_text
		else:
			none["log"] = "%s — nessuno preso: non adatto (non può trasportare %s)." % [found_text, "; ".join(too_heavy)]
		return none
	return {"jobs": takeable_jobs, "found_text": found_text, "log": ""}


# Presa di un lavoro tra quelli di find_takeable_jobs (`found`, con "jobs" non vuoto): scelta secondo il modo di priorità
# del giocatore (pick_job, 2026-10-08: la distanza non conta) e la stessa funzione dell'assegnazione a mano ("assign"
# del fornitore). {"taken": bool, "log": riga per il log}. Un rifiuto non viene ritentato: resolve_idle_individual passa
# alle attività di ripiego.
static func take_job(worker: HumanIndividual, game_data: GameData, found: Dictionary) -> Dictionary:
	var takeable_jobs: Array[Dictionary] = []
	takeable_jobs.assign(found.get("jobs", []))
	var found_text := String(found.get("found_text", ""))
	var pick := pick_job(game_data, worker, takeable_jobs)
	var best: Dictionary = pick["job"]
	var task_before := worker.current_task
	var queue_size_before := worker.task_queue.size()
	best["provider"]["assign"].call(worker, best)
	var taken := (worker.current_task != null and worker.current_task != task_before) or worker.task_queue.size() > queue_size_before
	var job_text := "%s %s" % [String(best["key"]), String(best["log_name"])]
	if taken:
		# Lavoro preso: le risposte in memoria di job_available_checker non valgono più (2026-10-23).
		take_revision += 1
		# "key" (2026-10-24, assegnatore fase 2): la scena toglie solo questo lavoro dalla lista in memoria.
		return {"taken": true, "key": String(best["key"]), "log":"%s — preso %s — %s." % [found_text, job_text, String(pick["reason"])]}
	return {"taken": false, "log": "%s — scelto %s — %s, ma rifiutato: passa alle attività di ripiego." % [found_text, job_text, String(pick["reason"])]}
