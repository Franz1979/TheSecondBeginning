class_name WaitAtPointAction
extends Action

# Attesa al punto di assegnazione (2026-10-09, coordinatore — step di "Cerca lavoro", seek_job.tres, e unico step di
# "Coordina", coordinate.tres): l'individuo resta al punto. Stesso modello di ThinkAction: accumula il tempo di gioco
# trascorso (_elapsed), con un tetto facoltativo (max_wait_days, negativo = nessun tetto).
#
# Istruzione (tempi in tempo di gioco come le altre azioni): CoordinatorService la avvia (start_instruction) su chi viene
# istruito — o sul coordinatore stesso, per l'autoassegnazione — e da lì l'azione accumula il tempo dell'istruzione e
# finisce dopo CoordinatorService.ASSIGNMENT_DURATION_DAYS, uguale a ogni velocità di gioco; il tempo già trascorso si
# salva con l'azione. released: fine immediata, decisa da CoordinatorService (fine del turno, punto sparito).
#
# Eventi: all'attivazione (arrivo al punto) e alla chiusura l'azione avvisa CoordinatorService, che decide a fine
# fotogramma. Alla chiusura l'individuo è segnato come arrivato (HumanIndividual.job_seek_arrived): resolve_idle_individual
# gli fa prendere il lavoro dalla lista (stessa scelta di sempre) o lo manda allo svago, senza un'altra "Cerca lavoro".
#
# Stamina (2026-10-09, richiesta utente): un costo giornaliero scalato per il tempo trascorso, come le altre azioni
# (un'ora = STAMINA_COST_PER_DAY / 24), anche durante l'ora delle istruzioni. Tempo e stamina realmente applicati sono
# accumulati qui (elapsed_days, instruction_days, stamina_spent) per il log [COORDINATORE].

const STAMINA_COST_PER_DAY: float = 120.0

var max_wait_days: float = -1.0
var released: bool = false
var instructing: bool = false
# Stamina tolta da questa azione dall'arrivo (somma dei costi applicati) e tempo di attesa prima dell'istruzione.
var stamina_spent: float = 0.0
var wait_before_instruction: float = 0.0
# Limite di attesa del coordinatore (2026-10-09, coordinatore passo 4): con idle_timeout_days >= 0 (lo imposta
# CoordinatorService sull'attesa di "Coordina", SELF_ASSIGN_WAIT_DAYS) l'azione misura il tempo dall'ultimo arrivo al
# punto (reset_idle_timer) e allo scadere lo segna (timed_out) e avvisa CoordinatorService (on_wait_timeout), una volta.
var idle_timeout_days: float = -1.0
# Chi ha dato l'istruzione (2026-10-09, crescita della Leadership): id del coordinatore, -1 = autoassegnazione o nessuna.
var instructor_id: int = -1
var timed_out: bool = false
var _idle_elapsed: float = 0.0
var _elapsed: float = 0.0
var _instruction_elapsed: float = 0.0


func _init(p_max_wait_days: float = -1.0) -> void:
	target = null
	max_wait_days = p_max_wait_days
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if individual is HumanIndividual:
		CoordinatorService.on_wait_started(individual as HumanIndividual, context, self)


# Inizio dell'istruzione (CoordinatorService): da qui l'attesa finisce dopo ASSIGNMENT_DURATION_DAYS di gioco.
func start_instruction(p_instructor_id: int = -1) -> void:
	instructor_id = p_instructor_id
	instructing = true
	_instruction_elapsed = 0.0
	wait_before_instruction = _elapsed


# Nuovo arrivo al punto (CoordinatorService): il limite di attesa riparte da zero.
func reset_idle_timer() -> void:
	_idle_elapsed = 0.0
	timed_out = false


func get_elapsed_days() -> float:
	return _elapsed


func get_instruction_days() -> float:
	return _instruction_elapsed


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	# Durante un'istruzione (2026-10-09) conta solo il tempo che le manca: anche con un passo grande (fotogramma lento)
	# dura esattamente ASSIGNMENT_DURATION_DAYS e costa STAMINA_COST_PER_DAY × quella durata (5 per un'ora).
	var used := delta
	if instructing:
		used = clampf(CoordinatorService.ASSIGNMENT_DURATION_DAYS - _instruction_elapsed, 0.0, delta)
	_elapsed += used
	var cost := STAMINA_COST_PER_DAY * used
	stamina_spent += cost
	if idle_timeout_days >= 0.0 and not timed_out:
		_idle_elapsed += used
		if _idle_elapsed >= idle_timeout_days:
			timed_out = true
			if individual is HumanIndividual:
				CoordinatorService.on_wait_timeout(individual as HumanIndividual, context)
	if instructing:
		_instruction_elapsed += used
		# Prova a 4x (2026-10-09): tempo ricevuto a ogni fotogramma durante un'istruzione.
		if DebugLogging.ENABLED and DebugLogging.SHOW_ACTION_TIME_LOGS:
			print("[ACTION TIME] WaitAtPointAction #%d %s: +%.5f giorni (%.1f min) — istruzione %.5f/%.5f giorni, stamina −%.2f" % [
				individual.id, individual.name, used, used * 1440.0, _instruction_elapsed,
				CoordinatorService.ASSIGNMENT_DURATION_DAYS, cost
			])
	return -cost


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return released or (instructing and _instruction_elapsed >= CoordinatorService.ASSIGNMENT_DURATION_DAYS) \
		or (max_wait_days >= 0.0 and _elapsed >= max_wait_days)


func on_complete(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if individual is HumanIndividual:
		(individual as HumanIndividual).job_seek_arrived = true
		CoordinatorService.on_wait_finished(individual as HumanIndividual, context, instructing and not released, self)


func get_save_data() -> Dictionary:
	return {
		"max_wait_days": max_wait_days, "elapsed": _elapsed, "released": released, "instructing": instructing,
		"instruction_elapsed": _instruction_elapsed, "stamina_spent": stamina_spent,
		"wait_before_instruction": wait_before_instruction, "idle_timeout_days": idle_timeout_days,
		"idle_elapsed": _idle_elapsed, "timed_out": timed_out, "instructor_id": instructor_id,
	}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	released = bool(data.get("released", false))
	instructing = bool(data.get("instructing", false))
	_instruction_elapsed = float(data.get("instruction_elapsed", 0.0))
	stamina_spent = float(data.get("stamina_spent", 0.0))
	wait_before_instruction = float(data.get("wait_before_instruction", 0.0))
	idle_timeout_days = float(data.get("idle_timeout_days", -1.0))
	_idle_elapsed = float(data.get("idle_elapsed", 0.0))
	timed_out = bool(data.get("timed_out", false))
	instructor_id = int(data.get("instructor_id", -1))
