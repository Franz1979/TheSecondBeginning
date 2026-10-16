class_name TalkAction
extends Action

# Step "chiacchiera" della Talk (2026-10-13, socialità — talk.tres: Walk → Talk, vedi TalkService e
# docs/design/socialita_teaching.md). Il partner è nel context della Task (TalkService.CONTEXT_PARTNER_ID). Ogni
# fotogramma guarda dove è il partner (TalkService.get_partner_state):
# - ancora in cammino verso il punto d'incontro: attesa, al massimo TalkService.MAX_WAIT_DAYS;
# - al punto (anche lui nello step Talk): la conversazione avanza fino a TalkService.TALK_DURATION_DAYS;
# - non più nella talk con lui (interrotto, sparito): la Task si chiude senza effetti (pending_task_abort).
# Se il partner ha appena finito (completed sulla sua azione, un fotogramma prima), la conversazione è finita anche
# qui: chiusura con gli effetti. Gli effetti (+felicità, +socialità) li applica TaskCompletionEffectService a fine Task.

# Emesso una volta, quando i due sono insieme al punto e la conversazione comincia (2026-10-13 — fumetto e suono).
# Collegato da GameScene._track_talk_tasks.
signal talk_started(individual: HumanIndividual, is_caller: bool)

const STAMINA_DRAIN_PER_DAY: float = 50.0

# true dopo il completamento vero (non un abbandono): lo legge l'azione del partner.
var completed: bool = false
var _wait_elapsed: float = 0.0
var _talk_elapsed: float = 0.0
var _talk_started: bool = false
var _aborted: bool = false
# Azione Talk del partner, presa quando i due sono insieme al punto. Non salvata: dopo un caricamento si riprende al
# prossimo fotogramma in cui entrambi sono al punto.
var _partner_action: TalkAction = null


func _init() -> void:
	target = null
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _aborted or completed:
		return 0.0
	if _partner_action != null and _partner_action.completed:
		completed = true
		return 0.0
	var state := TalkService.get_partner_state(individual as HumanIndividual, context)
	match state["state"]:
		TalkService.PARTNER_PRESENT:
			_partner_action = state["action"]
			# Si guardano (2026-10-13): stessa macrocella per costruzione (TalkService), quindi stesso riferimento.
			var to_partner: Vector2 = (state["partner"] as HumanIndividual).position - (individual as HumanIndividual).position
			if to_partner.length() > 0.001:
				individual.facing_direction = to_partner.normalized()
			if not _talk_started:
				_talk_started = true
				TalkService.log_event(individual, "inizia a chiacchierare con #%d %s." % [state["partner"].id, state["partner"].name])
				talk_started.emit(individual, bool(context.get(TalkService.CONTEXT_IS_CALLER, false)))
			_talk_elapsed += delta
		TalkService.PARTNER_WALKING:
			_wait_elapsed += delta
			if _wait_elapsed >= TalkService.MAX_WAIT_DAYS:
				_abort(individual, context, "il partner non è arrivato entro %.2f giorni" % TalkService.MAX_WAIT_DAYS)
				return 0.0
		_:
			_abort(individual, context, String(state["reason"]))
			return 0.0
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _aborted or completed or _talk_elapsed >= TalkService.TALK_DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _aborted:
		return
	completed = true
	# Coesione del villaggio (2026-10-14): una volta per talk, dal lato di chi l'ha lanciata.
	if bool(context.get(TalkService.CONTEXT_IS_CALLER, false)):
		VillageCohesionService.add((individual as HumanIndividual).village_ref, VillageCohesionService.TALK_GAIN, "talk")
	# Gli effetti arrivano subito dopo, a fine Task (task_completion_effects.tres): qui i valori di partenza.
	TalkService.log_event(individual, "conversazione finita (%.2f giorni, attesa %.2f) — felicità %.0f e socialità %.0f prima degli effetti." % [
		_talk_elapsed, _wait_elapsed, individual.current_happiness, individual.skill_social
	])


func _abort(individual: Variant, context: Dictionary, reason: String) -> void:
	_aborted = true
	context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "talk: %s" % reason
	TalkService.log_event(individual, "talk chiusa senza effetti — %s." % reason)


func get_save_data() -> Dictionary:
	return {"wait_elapsed": _wait_elapsed, "talk_elapsed": _talk_elapsed, "talk_started": _talk_started}


func load_save_data(data: Dictionary) -> void:
	_wait_elapsed = float(data.get("wait_elapsed", 0.0))
	_talk_elapsed = float(data.get("talk_elapsed", 0.0))
	_talk_started = bool(data.get("talk_started", false))
