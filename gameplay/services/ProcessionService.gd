class_name ProcessionService
extends RefCounted

# Corteo (2026-10-04, richiesta utente — meccanismo generico, usato per ora solo dal funerale): convoca dei pipottini a
# seguire una guida fino a un edificio e a restarvi accanto finché la task della guida che tiene vivo il corteo resta la
# sua task in corso (procession.tres, FollowIndividualAction). Stateless. Nessuna regola su CHI convocare: la decide il
# chiamante (per il funerale, PickUpBodyAction: i parenti vivi del morto).

const PROCESSION_TASK_NAME := "task_procession_name"
const PROCESSION_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/procession.tres"
# Chiavi del context (procession.tres): guida, edificio di arrivo, task della guida (nome salvato + riferimento non
# salvato, consumato dallo step) e testo dell'attività (resta nel context).
const CONTEXT_GUIDE_ID := "procession_guide_id"
const CONTEXT_BUILDING_ID := "procession_building_id"
const CONTEXT_KEEPER_TASK_NAME := "procession_keeper_task_name"
const CONTEXT_KEEPER_TASK := "procession_keeper_task"
const CONTEXT_TEXT := "procession_text"

const CONTEXT_QUEUE_ORDER := "procession_queue_order"

# Esiti di convoke, uno per partecipante (testo per i log).
const OUTCOME_CONVOKED := "convocato"

# Scia della guida (2026-10-04, richiesta utente — corteo in fila, FollowIndividualAction): per ogni guida di un corteo,
# i punti percorsi da quando il corteo è partito, in microcelle ASSOLUTE, dal più vecchio al più recente, uno ogni
# TRAIL_STEP circa; potata alla lunghezza che serve alla fila. Non salvata: dopo un caricamento riparte vuota (e la fila
# usa intanto i punti dietro la guida nel verso opposto a quello di marcia).
const TRAIL_STEP: float = 0.5
static var _trails: Dictionary = {}  # guide id -> PackedVector2Array


# Scia azzerata alla partenza di un corteo.
static func reset_trail(guide: HumanIndividual) -> void:
	_trails[guide.id] = PackedVector2Array([_absolute_position(guide)])


# Aggiunge la posizione attuale della guida se si è spostata di almeno TRAIL_STEP dall'ultimo punto, poi pota la scia
# a `max_length` microcelle dietro la guida. Chiamata a ogni tick da ogni partecipante in fila (idempotente).
static func record_trail(guide: HumanIndividual, max_length: float) -> void:
	var trail: PackedVector2Array = _trails.get(guide.id, PackedVector2Array())
	var position := _absolute_position(guide)
	if trail.is_empty() or trail[trail.size() - 1].distance_to(position) >= TRAIL_STEP:
		trail.append(position)
	var length := position.distance_to(trail[trail.size() - 1])
	var keep_from := 0
	for i in range(trail.size() - 1, 0, -1):
		length += trail[i].distance_to(trail[i - 1])
		if length > max_length:
			keep_from = i - 1
			break
	if keep_from > 0:
		trail = trail.slice(keep_from)
	_trails[guide.id] = trail


# Punto della scia a `distance` microcelle dietro la guida (assolute), misurato lungo il percorso dalla posizione
# attuale. Scia troppo corta: prosegue oltre il punto più vecchio nel verso opposto a quello di marcia della guida.
static func point_behind(guide: HumanIndividual, distance: float) -> Vector2:
	var trail: PackedVector2Array = _trails.get(guide.id, PackedVector2Array())
	var current := _absolute_position(guide)
	var remaining := distance
	for i in range(trail.size() - 1, -1, -1):
		var segment := current.distance_to(trail[i])
		if segment >= remaining and segment > 0.0:
			return current + (trail[i] - current) * (remaining / segment)
		remaining -= segment
		current = trail[i]
	var backward := -guide.facing_direction.normalized() if guide.facing_direction.length() > 0.001 else Vector2.ZERO
	return current + backward * remaining


# Assegna la task Corteo a ciascuno dei `participants`, interrompendo la task in corso, tranne a chi: sta soddisfacendo
# un bisogno (task con interrupt_priority), non può camminare (neonato; quello a carico segue già la madre da solo), è
# la guida o porta un corpo, è oltre `max_distance` microcelle dalla guida in linea d'aria, ha già una task Corteo (in
# corso o in coda). Ritorna un esito per partecipante: [{"individual": HumanIndividual, "outcome": String}], dove
# outcome è OUTCOME_CONVOKED o il motivo dello scarto (in italiano, per i log).
# `new_procession` (2026-10-04): true = nuovo corteo della guida (scia azzerata, registro del corteo rifatto, fila da 0);
# false = altri convocati dello stesso corteo, accodati in fondo alla fila (corteo esteso, richiamo).
static func convoke(
	guide: HumanIndividual, guide_task: Task, participants: Array, building: Building, text: String, max_distance: float,
	new_procession: bool = true
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var game_data: GameData = GameSettings.active_game_data
	if guide == null or guide_task == null or building == null or game_data == null:
		return results
	var definition := load(PROCESSION_TASK_DEFINITION_PATH) as TaskDefinition
	if definition == null:
		push_error("ProcessionService.convoke: %s non caricabile." % PROCESSION_TASK_DEFINITION_PATH)
		return results
	# Fila (2026-10-04): scia azzerata e numeri d'ordine dal più vicino alla guida al più lontano.
	if new_procession or not _processions.has(guide.id):
		reset_trail(guide)
		_processions[guide.id] = {
			"keeper_task": guide_task, "building": building, "text": text, "max_distance": max_distance,
			"next_order": 0, "joined": {}, "exited": {}, "recall_ids": [], "recall_interval": 0.0, "elapsed": 0.0,
			"recall_log_prefix": "", "actions": {}, "arrived": {},
		}
	var entry: Dictionary = _processions[guide.id]
	var guide_absolute := _absolute_position(guide)
	var ordered: Array = participants.duplicate()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _absolute_position(a as HumanIndividual).distance_to(guide_absolute) < _absolute_position(b as HumanIndividual).distance_to(guide_absolute)
	)
	var next_order: int = int(entry["next_order"])
	for member in ordered:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var outcome := _skip_reason(individual, guide, max_distance, game_data)
		if outcome == "":
			var task := TaskFactory.build_task(definition, {
				CONTEXT_GUIDE_ID: guide.id,
				CONTEXT_BUILDING_ID: building.id,
				CONTEXT_KEEPER_TASK_NAME: guide_task.task_name,
				CONTEXT_KEEPER_TASK: guide_task,
				CONTEXT_TEXT: text,
				CONTEXT_QUEUE_ORDER: next_order,
			})
			var age_band := HumanIndividualActionService._resolve_age_band(individual, game_data)
			var rejection := individual.get_assign_rejection_reason(task, age_band)
			if rejection != HumanIndividual.ASSIGN_OK:
				outcome = "assegnazione rifiutata (%s)" % rejection
			elif not individual.assign_task(task, age_band) or individual.current_task != task:
				outcome = "assegnazione rifiutata"
			else:
				outcome = OUTCOME_CONVOKED
				next_order += 1
				entry["joined"][individual.id] = true
				entry["actions"][individual.id] = task.steps[0] if not task.steps.is_empty() else null
		results.append({"individual": individual, "outcome": outcome})
	entry["next_order"] = next_order
	return results


# Registro dei cortei in corso (2026-10-04, richiamo): guida id -> {"keeper_task", "building", "text", "max_distance",
# "next_order" (prossimo numero d'ordine, in fondo alla fila), "joined" (id -> true, chi è stato convocato), "exited"
# (id -> true, chi ha fatto parte del corteo e l'ha lasciato: non rientra), "recall_ids" (chi richiamare), "recall_interval"
# (giorni, 0 = nessun richiamo), "elapsed", "recall_log_prefix" (prefisso dei log del richiamo, "" = nessun log)}. Non
# salvato: dopo un caricamento i cortei in corso proseguono, ma senza richiamo.
static var _processions: Dictionary = {}


# Richiamo (2026-10-04, richiesta utente): finché il corteo della guida è in corso, ogni `interval_days` giorni di gioco
# riprova a convocare chi in `recall_ids` non ne fa parte e non ne è mai uscito, rivalutando ogni esclusione in quel
# momento; i convocati si accodano in fondo alla fila. `log_prefix` != "": una riga di log per ogni convocato.
static func set_recall(guide: HumanIndividual, recall_ids: Array, interval_days: float, log_prefix: String = "") -> void:
	if guide == null or not _processions.has(guide.id):
		return
	var entry: Dictionary = _processions[guide.id]
	entry["recall_ids"] = recall_ids.duplicate()
	entry["recall_interval"] = interval_days
	entry["elapsed"] = 0.0
	entry["recall_log_prefix"] = log_prefix


# A ogni frame (GameScene, con i giorni di gioco trascorsi): chiude i cortei la cui task della guida non è più quella in
# corso, aggiorna chi è uscito e, allo scadere dell'intervallo, esegue il richiamo.
static func tick(game_delta: float) -> void:
	if _processions.is_empty():
		return
	var individuals: Array = GameSettings.active_human_individuals
	var by_id: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual != null:
			by_id[individual.id] = individual
	for guide_id in _processions.keys():
		var entry: Dictionary = _processions[guide_id]
		var guide: HumanIndividual = by_id.get(guide_id)
		var keeper: Task = entry["keeper_task"]
		var log_prefix := String(entry["recall_log_prefix"])
		if guide == null or guide.current_task == null or guide.current_task != keeper or keeper.is_finished():
			if log_prefix != "":
				_log_procession_end(entry, guide, keeper, by_id, log_prefix)
			_processions.erase(guide_id)
			continue
		for member_id in entry["joined"].keys():
			if entry["exited"].has(member_id):
				continue
			var member: HumanIndividual = by_id.get(member_id)
			if member == null or not _is_following(member, int(guide_id)):
				entry["exited"][member_id] = true
				if log_prefix != "":
					print("%s   uscita dal corteo: #%d %s, a %s dalla guida — %s." % [
						log_prefix, int(member_id), member.name if member != null else "?",
						"%.1f microcelle" % distance_between(member, guide) if member != null else "?",
						_exit_reason(member, entry["actions"].get(member_id))
					])
				continue
			var action = entry["actions"].get(member_id)
			if action is FollowIndividualAction and (action as FollowIndividualAction).reached_slot and not entry["arrived"].has(member_id):
				entry["arrived"][member_id] = true
				if log_prefix != "" and entry["building"] != null:
					print("%s   arrivato al suo posto: #%d %s, a %.1f microcelle dall'edificio." % [
						log_prefix, member.id, member.name,
						_absolute_position(member).distance_to(InfluenceService.building_absolute_center(entry["building"]))
					])
		var interval := float(entry["recall_interval"])
		if interval <= 0.0:
			continue
		entry["elapsed"] = float(entry["elapsed"]) + game_delta
		if float(entry["elapsed"]) < interval:
			continue
		entry["elapsed"] = 0.0
		var candidates: Array = []
		for recall_id in entry["recall_ids"]:
			var candidate: HumanIndividual = by_id.get(int(recall_id))
			if candidate != null and not entry["joined"].has(candidate.id):
				candidates.append(candidate)
		if candidates.is_empty():
			continue
		var results := convoke(guide, keeper, candidates, entry["building"], String(entry["text"]), float(entry["max_distance"]), false)
		if log_prefix == "":
			continue
		for result in results:
			if result["outcome"] == OUTCOME_CONVOKED:
				var recalled: HumanIndividual = result["individual"]
				print("%s   #%d %s: convocato al richiamo." % [log_prefix, recalled.id, recalled.name])


# Motivo dell'uscita di un partecipante dal corteo (solo log): la task che lo ha sostituito, preceduta dal motivo per
# cui stava aspettando fermo (guida irraggiungibile, nessun posto libero) se era in attesa.
static func _exit_reason(member: HumanIndividual, action: Variant) -> String:
	var wait := ""
	if action is FollowIndividualAction:
		wait = (action as FollowIndividualAction).wait_state
	var reason := ""
	if member == null:
		reason = "altro: non è più nel villaggio (morto?)"
	elif member.current_task == null or member.current_task.is_finished():
		reason = "altro: nessuna task in corso (corteo chiuso dal partecipante)"
	elif member.current_task.interrupt_priority != -1:
		reason = "interrotto da un bisogno (%s)" % member.current_task.task_name
	elif member.current_task.task_name == PROCESSION_TASK_NAME:
		reason = "altro: segue un altro corteo"
	else:
		reason = "interrotto da un'altra task o da un comando (%s)" % member.current_task.task_name
	return "%s, poi %s" % [wait, reason] if wait != "" else reason


# Fine di un corteo (solo log): se la task della guida è finita (rito concluso), riepilogo convocati/arrivati/usciti; se
# la guida è stata interrotta o non c'è più, una riga di uscita per ogni partecipante ancora nel corteo.
static func _log_procession_end(entry: Dictionary, guide: HumanIndividual, keeper: Task, by_id: Dictionary, log_prefix: String) -> void:
	if keeper != null and keeper.is_finished():
		print("%s corteo concluso: %d convocati, %d arrivati al loro posto, %d usciti prima della fine." % [
			log_prefix, entry["joined"].size(), entry["arrived"].size(), entry["exited"].size()
		])
		return
	for member_id in entry["joined"].keys():
		if entry["exited"].has(member_id):
			continue
		var member: HumanIndividual = by_id.get(member_id)
		print("%s   uscita dal corteo: #%d %s, a %s dalla guida — corteo sciolto perché la guida è stata interrotta%s." % [
			log_prefix, int(member_id), member.name if member != null else "?",
			"%.1f microcelle" % distance_between(member, guide) if member != null and guide != null else "?",
			"" if guide != null else " (guida non più nel villaggio)"
		])


# true se `individual` sta seguendo (task Corteo in corso) la guida `guide_id`.
static func _is_following(individual: HumanIndividual, guide_id: int) -> bool:
	var task := individual.current_task
	if task == null or task.is_finished() or task.task_name != PROCESSION_TASK_NAME:
		return false
	var action := task.get_current_action()
	return action is FollowIndividualAction and (action as FollowIndividualAction).guide_id == guide_id


# "" se `individual` può essere convocato da `guide` entro `max_distance` (stesse esclusioni di convoke), altrimenti il
# motivo. Pubblica per chi sceglie i candidati prima di convocarli (corteo funebre esteso).
static func get_skip_reason(individual: HumanIndividual, guide: HumanIndividual, max_distance: float) -> String:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return "partita non disponibile"
	return _skip_reason(individual, guide, max_distance, game_data)


# Distanza in linea d'aria tra due pipottini, in microcelle (anche in macrocelle diverse).
static func distance_between(a: HumanIndividual, b: HumanIndividual) -> float:
	return _absolute_position(a).distance_to(_absolute_position(b))


# "" se `individual` può essere convocato, altrimenti il motivo (per i log).
static func _skip_reason(individual: HumanIndividual, guide: HumanIndividual, max_distance: float, game_data: GameData) -> String:
	if individual == guide:
		return "è la guida"
	if individual.carried_body_id != -1:
		return "porta un corpo"
	if HumanIndividualActionService._resolve_age_band(individual, game_data) == HumanTypes.AgeBand.INFANT:
		return "non cammina (neonato)"
	var current := individual.current_task
	if current != null and not current.is_finished() and current.interrupt_priority != -1:
		return "sta soddisfacendo un bisogno (%s)" % current.task_name
	if has_procession_task(individual):
		return "ha già un corteo"
	var distance := _absolute_position(individual).distance_to(_absolute_position(guide))
	if distance > max_distance:
		return "troppo lontano (%.1f > %.1f microcelle)" % [distance, max_distance]
	return ""


static func has_procession_task(individual: HumanIndividual) -> bool:
	if individual.current_task != null and not individual.current_task.is_finished() \
			and individual.current_task.task_name == PROCESSION_TASK_NAME:
		return true
	for queued in individual.task_queue:
		if queued.task_name == PROCESSION_TASK_NAME:
			return true
	return false


static func _absolute_position(individual: HumanIndividual) -> Vector2:
	return Vector2(individual.home_macro_coords.x * World.WIDTH, individual.home_macro_coords.y * World.HEIGHT) + individual.position
