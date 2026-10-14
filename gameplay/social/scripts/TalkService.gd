class_name TalkService
extends RefCounted

# Talk (2026-10-13, socialità livello 0 — vedi docs/design/socialita_teaching.md): due pipottini liberi si incontrano a
# metà strada e chiacchierano. Servizio senza stato: sceglie il partner e il punto d'incontro, costruisce e assegna le
# due Task collegate (talk.tres: Walk → Talk), e risponde a TalkAction su dove si trova il partner.
#
# Chi la lancia: chi la estrae nel sorteggio delle attività libere (IdleTaskAssignmentService).
# Una sola chiamata, istantanea: nessun partner valido = la talk non parte (il sorteggio ripesca un'altra attività).
# Chi viene chiamato: un individuo della stessa Folk e della stessa macrocella, nelle fasce d'età della talk, entro il
# raggio, senza task in coda né zaino carico, libero o in un'attività libera del sorteggio
# (IdleTaskAssignmentService.IDLE_FALLBACK_TASK_PATHS, talk esclusa); scelto a caso. La sua attività viene interrotta
# come da qualunque comando (daydreaming perde il pensiero, il rito spontaneo finisce senza effetto).
# Effetti a fine Task per entrambi: task_completion_effects.tres ("task_talk_name": felicità e skill_social).

const TALK_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/talk.tres"
const TALK_TASK_NAME := "task_talk_name"
# id del partner nel context della Task (non consumato da TaskFactory: lo legge TalkAction, si salva con la Task).
const CONTEXT_PARTNER_ID := "talk_partner_id"
# true nella Task di chi ha lanciato la talk (2026-10-13, suoni ed effetti: "hey" per chi chiama, "yeah" per chi risponde).
const CONTEXT_IS_CALLER := "talk_is_caller"

# Raggio di chiamata in microcelle = CALL_RADIUS_BASE × (1 + CALL_RADIUS_SOCIAL_BONUS × skill_social / SKILL_MAX): da 4 a
# 8, un po' meno del richiamo del coordinatore (CoordinatorService.CALL_RADIUS_BASE).
const CALL_RADIUS_BASE: float = 4.0
const CALL_RADIUS_SOCIAL_BONUS: float = 1.0
# Attesa massima del partner al punto d'incontro e durata della conversazione (giorni di gioco).
const MAX_WAIT_DAYS: float = 0.5
const TALK_DURATION_DAYS: float = 0.25
# Distanza fra i due punti d'incontro (microcelle): stanno uno accanto all'altro, non uno sopra l'altro. 2026-10-13: da 1.0
# a 0.8, più vicini.
const MEETING_SIDE_DISTANCE: float = 0.8

# Stati del partner visti da TalkAction (get_partner_state).
const PARTNER_PRESENT := "present"
const PARTNER_WALKING := "walking"
const PARTNER_GONE := "gone"


static func log_event(individual: Variant, text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_TALK_LOGS and individual != null:
		print("[TALK] #%d %s: %s" % [individual.id, individual.name, text])


static func is_talk_task(task: Task) -> bool:
	return task != null and task.task_name == TALK_TASK_NAME


static func is_caller(task: Task) -> bool:
	return task != null and bool(task.context.get(CONTEXT_IS_CALLER, false))


static func get_call_radius(individual: HumanIndividual) -> float:
	return CALL_RADIUS_BASE * (1.0 + CALL_RADIUS_SOCIAL_BONUS * individual.skill_social / HumanIndividual.SKILL_MAX)


# Fascia d'età con le durate dell'era (stessa formula di GameScene._resolve_age_band); -1 senza partita attiva.
static func resolve_age_band(individual: HumanIndividual) -> int:
	var game_data := GameSettings.active_game_data
	if game_data == null:
		return -1
	return HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, float(game_data.year - individual.birth_year_virtual)
	)


# Avvia la talk di `caller`. Ritorna {"ok": bool, "assign_rejection": String (HumanIndividual.ASSIGN_*, "" se il rifiuto
# non è di idoneità), "message": String (motivo tradotto per il giocatore, "" se ok)}.
static func start_talk(caller: HumanIndividual, caller_age_band: int) -> Dictionary:
	var result := {"ok": false, "assign_rejection": HumanIndividual.ASSIGN_OK, "message": ""}
	var definition := load(TALK_TASK_DEFINITION_PATH) as TaskDefinition
	if caller == null or definition == null:
		return result
	if not definition.allowed_age_bands.is_empty() and not definition.allowed_age_bands.has(caller_age_band):
		result["assign_rejection"] = HumanIndividual.ASSIGN_REJECT_AGE_NOT_ALLOWED
		log_event(caller, "non può lanciare una talk: fascia d'età non ammessa.")
		return result
	if not caller.carried_resources.is_empty():
		result["message"] = tr_text("talk_reject_backpack", caller)
		log_event(caller, "non può lanciare una talk: zaino carico (%s)." % str(caller.carried_resources))
		return result
	var radius := get_call_radius(caller)
	var candidates := find_partner_candidates(caller, definition, radius)
	if candidates.is_empty():
		result["message"] = tr_text("talk_reject_no_partner", caller)
		log_event(caller, "nessuno con cui parlare entro %.1f microcelle.%s" % [radius, _describe_exclusions(caller, definition, radius)])
		return result
	candidates.shuffle()
	for partner: HumanIndividual in candidates:
		var partner_age_band := resolve_age_band(partner)
		var points := _meeting_points(caller, partner)
		var caller_task := TaskFactory.build_task(definition, {"target_position": points[0], CONTEXT_PARTNER_ID: partner.id, CONTEXT_IS_CALLER: true})
		var partner_task := TaskFactory.build_task(definition, {"target_position": points[1], CONTEXT_PARTNER_ID: caller.id})
		var caller_rejection := caller.get_assign_rejection_reason(caller_task, caller_age_band as HumanTypes.AgeBand)
		if caller_rejection != HumanIndividual.ASSIGN_OK:
			result["assign_rejection"] = caller_rejection
			log_event(caller, "non può lanciare una talk: rifiutata (%s)." % caller_rejection)
			return result
		if partner.get_assign_rejection_reason(partner_task, partner_age_band as HumanTypes.AgeBand) != HumanIndividual.ASSIGN_OK:
			log_event(caller, "#%d %s scartato come partner (non può ricevere la talk), provo il prossimo." % [partner.id, partner.name])
			continue
		var interrupted := _describe_task(partner.current_task)
		if not caller.assign_task(caller_task, caller_age_band as HumanTypes.AgeBand) or caller.current_task != caller_task:
			log_event(caller, "assegnazione della talk non riuscita.")
			return result
		if not partner.assign_task(partner_task, partner_age_band as HumanTypes.AgeBand) or partner.current_task != partner_task:
			# Il chiamante resta con la sua talk: arrivato al punto vedrà che il partner non c'è e la chiuderà.
			log_event(caller, "#%d %s non ha ricevuto la talk: la mia si chiuderà da sola." % [partner.id, partner.name])
			return result
		log_event(caller, "chiama #%d %s (che lascia %s) — %d candidati entro %.1f microcelle, incontro a %s / %s." % [
			partner.id, partner.name, interrupted, candidates.size(), radius, str(points[0]), str(points[1])
		])
		result["ok"] = true
		return result
	result["message"] = tr_text("talk_reject_no_partner", caller)
	log_event(caller, "nessun candidato poteva ricevere la talk.")
	return result


# Individui chiamabili da `caller` (vedi il commento in testa al file), in ordine qualsiasi.
static func find_partner_candidates(caller: HumanIndividual, definition: TaskDefinition, radius: float) -> Array[HumanIndividual]:
	var callable_names := _callable_task_names()
	var candidates: Array[HumanIndividual] = []
	for member in GameSettings.active_human_individuals:
		if member == null or member == caller or member.folk_ref != caller.folk_ref:
			continue
		if _exclusion_reason(caller, member, definition, radius, callable_names) == "":
			candidates.append(member)
	return candidates


# Perché `member` non è chiamabile da `caller` ("" = chiamabile). Stesso ordine dei controlli di find_partner_candidates.
static func _exclusion_reason(
	caller: HumanIndividual, member: HumanIndividual, definition: TaskDefinition, radius: float, callable_names: Array[String]
) -> String:
	if member.home_macro_coords != caller.home_macro_coords:
		return "in un'altra macrocella"
	var distance := member.position.distance_to(caller.position)
	if distance > radius:
		return "fuori raggio (%.1f)" % distance
	if not member.task_queue.is_empty():
		return "ha %d task in coda" % member.task_queue.size()
	if not member.carried_resources.is_empty():
		return "zaino carico"
	var task := member.current_task
	if task != null and not task.is_finished() and not callable_names.has(task.task_name):
		return "occupato (%s)" % task.task_name
	var age_band := resolve_age_band(member)
	if not definition.allowed_age_bands.is_empty() and not definition.allowed_age_bands.has(age_band):
		return "fascia d'età %s" % (HumanTypes.AgeBand.keys()[age_band] if age_band >= 0 else "sconosciuta (nessuna partita attiva)")
	return ""


# Diagnosi per il log quando nessuno è chiamabile: i membri della stessa Folk e macrocella, dal più vicino, con il motivo
# dello scarto (al massimo LOG_EXCLUSIONS_MAX), più quanti sono in altre macrocelle.
const LOG_EXCLUSIONS_MAX := 8

static func _describe_exclusions(caller: HumanIndividual, definition: TaskDefinition, radius: float) -> String:
	var callable_names := _callable_task_names()
	var same_cell: Array[HumanIndividual] = []
	var elsewhere := 0
	for member in GameSettings.active_human_individuals:
		if member == null or member == caller or member.folk_ref != caller.folk_ref:
			continue
		if member.home_macro_coords != caller.home_macro_coords:
			elsewhere += 1
		else:
			same_cell.append(member)
	same_cell.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool:
		return a.position.distance_squared_to(caller.position) < b.position.distance_squared_to(caller.position)
	)
	var lines: Array[String] = []
	for member in same_cell.slice(0, LOG_EXCLUSIONS_MAX):
		lines.append("#%d %s a %.1f: %s" % [
			member.id, member.name, member.position.distance_to(caller.position),
			_exclusion_reason(caller, member, definition, radius, callable_names)
		])
	var text := " Vicini: " + ("; ".join(lines) if not lines.is_empty() else "nessuno nella macrocella")
	if same_cell.size() > LOG_EXCLUSIONS_MAX:
		text += " (+%d più lontani)" % (same_cell.size() - LOG_EXCLUSIONS_MAX)
	return text + ". In altre macrocelle: %d." % elsewhere


# Dove si trova il partner della talk di `individual` (context della sua Task): {"state", "partner", "action", "reason"}.
static func get_partner_state(individual: HumanIndividual, context: Dictionary) -> Dictionary:
	var partner_id := int(context.get(CONTEXT_PARTNER_ID, -1))
	var partner: HumanIndividual = null
	for member in GameSettings.active_human_individuals:
		if member != null and member.id == partner_id:
			partner = member
			break
	if partner == null:
		return {"state": PARTNER_GONE, "reason": "partner #%d non più presente" % partner_id}
	var task := partner.current_task
	if not is_talk_task(task) or task.is_finished() or int(task.context.get(CONTEXT_PARTNER_ID, -1)) != individual.id:
		return {"state": PARTNER_GONE, "partner": partner, "reason": "#%d %s non è più nella talk (ora: %s)" % [
			partner.id, partner.name, _describe_task(task)
		]}
	var action := task.get_current_action()
	if action is TalkAction:
		return {"state": PARTNER_PRESENT, "partner": partner, "action": action}
	return {"state": PARTNER_WALKING, "partner": partner}


# Testo tradotto per il giocatore (chiave con {name}).
static func tr_text(key: String, individual: HumanIndividual) -> String:
	return TranslationServer.translate(key).format({"name": individual.name})


# Nomi delle attività libere del sorteggio, talk esclusa.
static func _callable_task_names() -> Array[String]:
	var names: Array[String] = []
	for path in IdleTaskAssignmentService.IDLE_FALLBACK_TASK_PATHS:
		var definition := load(path) as TaskDefinition
		if definition != null and definition.task_name != TALK_TASK_NAME:
			names.append(definition.task_name)
	return names


# Punti d'incontro [chiamante, partner]: il primo è una microcella libera e raggiungibile vicino al punto medio (se non
# si trova, il chiamante resta dov'è); il secondo è accanto al primo (se non si trova, lo stesso punto).
static func _meeting_points(caller: HumanIndividual, partner: HumanIndividual) -> Array[Vector2]:
	var middle := (caller.position + partner.position) * 0.5
	var caller_point: Variant = PathfindingService.pick_free_destination(caller, func() -> Vector2:
		return middle + Vector2.from_angle(randf() * TAU) * randf_range(0.0, MEETING_SIDE_DISTANCE)
	)
	var first: Vector2 = caller_point if caller_point != null else caller.position
	var partner_point: Variant = PathfindingService.pick_free_destination(partner, func() -> Vector2:
		return first + Vector2.from_angle(randf() * TAU) * MEETING_SIDE_DISTANCE
	)
	var second: Vector2 = partner_point if partner_point != null else first
	return [first, second]


static func _describe_task(task: Task) -> String:
	if task == null or task.is_finished():
		return "nessuna task"
	return task.task_name
