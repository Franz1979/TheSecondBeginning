class_name CoordinatorService
extends RefCounted

# Coordinatore dei lavori della coda (2026-10-09, coordinatore passo 3 — task "Coordina", coordinate.tres). Stateless,
# funzioni statiche come gli altri *Service; lo stato (chi coordina in quale punto, chi aspetta e in che ordine, chi sta
# ricevendo le istruzioni) vive in GameData.coordinator_posts ed è salvato.
#
# Tempi e decisioni: i tempi sono quelli delle azioni, in tempo di gioco, uguali a ogni velocità — l'istruzione la misura
# la WaitAtPointAction di chi la riceve (start_instruction, ASSIGNMENT_DURATION_DAYS). Le istruzioni (anche
# l'autoassegnazione) partono SOLO dagli eventi di quell'azione — arrivo al punto (on_wait_started) e fine dell'attesa
# (on_wait_finished) — elaborati a fine fotogramma (_process_point_deferred), più un evento una tantum quando il gioco
# diventa pronto dopo un caricamento. Il giro al secondo del cassetto (tick) fa solo i controlli di sicurezza (posti da
# liberare dopo un caricamento, coordinatore sparito o interrotto, punto sparito, fine del turno a coda vuota) e non
# avvia mai un'istruzione. Nessuna decisione finché il gioco non è pronto (_is_ready).
#
# Per ogni punto di assegnazione (BuildingRules.is_assignment_point, completo e non da demolire):
#   - chi arriva con "Cerca lavoro" si mette in fila; senza coordinatore, il primo della fila diventa coordinatore
#     (can_coordinate) e riceve "Coordina" (solo l'attesa: è già al punto);
#   - il coordinatore istruisce la fila uno alla volta; finita l'istruzione, chi aspettava prende il lavoro dalla lista
#     come prima (resolve_idle_individual con job_seek_arrived) o va allo svago, e il coordinatore passa al prossimo;
#   - nessuno in fila né in cammino verso il punto: con un lavoro per lui il coordinatore se lo autoassegna (stessa
#     istruzione, poi lascia "Coordina" e prende il lavoro); con la coda vuota il turno finisce (svago);
#   - "Coordina" interrotta (bisogno, H) o sparita: il posto si libera e il prossimo in fila diventa coordinatore. Chi
#     aspettava resta in fila.
#
# Provvisorio (passi successivi): niente richiamo, suono, raggio né Leadership; can_coordinate risponde sempre sì.

# Durata di un'istruzione (giorni di gioco): un'ora. La misura l'azione (WaitAtPointAction), non il giro al secondo.
const ASSIGNMENT_DURATION_DAYS: float = 1.0 / 24.0

# Richiamo (2026-10-09, coordinatore passo 5): raggio in microcelle dal punto di assegnazione entro cui il coordinatore
# chiama chi è in svago. Raggio = CALL_RADIUS_BASE × (1 + CALL_RADIUS_LEADERSHIP_BONUS × skill_leadership / 1000).
# 2026-10-09 (passo 6): da 10 a 5 — da 5 a 10 microcelle, il chiamato arriva entro un giorno (10 microcelle al giorno).
const CALL_RADIUS_BASE: float = 5.0
const CALL_RADIUS_LEADERSHIP_BONUS: float = 1.0
# Limite di attesa (2026-10-09, coordinatore passo 4, giorni di gioco): il coordinatore aspetta al massimo questo tempo
# dall'ultimo arrivo al punto (o da quando è diventato coordinatore), anche con qualcuno ancora in cammino. Lo misura la
# sua WaitAtPointAction (idle_timeout_days); allo scadere si autoassegna se c'è un lavoro per lui, altrimenti chiude il
# turno.
const SELF_ASSIGN_WAIT_DAYS: float = 1.0
# Crescita della Leadership (2026-10-09, passo 6): il coordinatore guadagna questo valore su skill_leadership (fino al
# tetto comune HumanIndividual.SKILL_MAX, 2026-10-10 — prima un LEADERSHIP_MAX proprio a 1000) ogni volta che un ALTRO
# individuo riceve il lavoro alla fine di un'istruzione; niente per l'autoassegnazione né per chi viene istruito senza
# ricevere un lavoro.
const LEADERSHIP_GAIN_PER_ASSIGNMENT: float = 1.0

const COORDINATE_TASK_PATH := "res://gameplay/scripts/tasks/definitions/coordinate.tres"
const COORDINATE_TASK_NAME := "task_coordinate_name"
# Punto di assegnazione (id dell'edificio) nel context di "Cerca lavoro" e di "Coordina".
const CONTEXT_POINT_ID := "assignment_point_id"

# Agganci registrati da GameScene: Callable(HumanIndividual) -> HumanTypes.AgeBand (assegnazione di "Coordina"),
# Callable() -> float, il momento di gioco in giorni (ora delle righe del log), e Callable() -> bool, scena pronta.
static var age_band_resolver: Callable = Callable()
static var now_provider: Callable = Callable()
static var scene_ready_checker: Callable = Callable()
# Callable(HumanIndividual): suono del richiamo alla posizione del coordinatore (GameScene.coordinator_called).
static var call_sound_emitter: Callable = Callable()

# Solo per il log [COORDINATORE], mai usati dalle decisioni né salvati: l'attesa al punto di ogni individuo (tempo e
# stamina realmente applicati li tiene lei) e, per chi coordina, quanti ne ha istruiti.
static var _actions: Dictionary = {}  # id individuo -> WaitAtPointAction
static var _log_info: Dictionary = {}  # id individuo -> {"coordinator": bool, "instructed": int}
static var _last_now: float = -1.0


# Un giorno sarà il ruolo "coordinatore"; per ora chiunque.
static func can_coordinate(_individual: HumanIndividual) -> bool:
	return true


static func is_valid_point(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.is_assignment_point and building.is_complete \
		and not building.is_demolished and not building.is_marked_for_demolition


static func is_coordinate_task(task: Task) -> bool:
	return task != null and task.task_name == COORDINATE_TASK_NAME


# Gioco pronto per le decisioni: scena pronta, controlli della coda registrati (e validi), primo giro dopo un caricamento
# passato.
static func _is_ready(game_data: GameData) -> bool:
	return game_data != null and game_data.coordinator_posts_checked and scene_ready_checker.is_valid() \
		and bool(scene_ready_checker.call()) and JobBoardService.queue_has_jobs_checker.is_valid() \
		and JobBoardService.job_available_checker.is_valid() and age_band_resolver.is_valid()


# --- Eventi (WaitAtPointAction) ---

# Arrivo al punto: chi cerca lavoro, o il coordinatore al suo posto. La decisione a fine fotogramma.
static func on_wait_started(member: HumanIndividual, context: Dictionary, action: WaitAtPointAction) -> void:
	_actions[member.id] = action
	# Attesa di "Coordina": limite di attesa attivo (dopo un caricamento resta quello salvato).
	if is_coordinate_task(member.current_task) and action.idle_timeout_days < 0.0:
		action.idle_timeout_days = SELF_ASSIGN_WAIT_DAYS
	var point_id := int(context.get(CONTEXT_POINT_ID, -1))
	if point_id >= 0 and _is_ready(GameSettings.active_game_data):
		_process_point_deferred.call_deferred(point_id)


# Fine dell'attesa al punto. `instructed`: istruzione completata (non un rilascio). Chi aspettava: fuori dalla fila,
# il coordinatore conta un istruito; il coordinatore: lascia il posto (autoassegnazione finita, o fine del turno già
# scritta nel log). Poi la decisione per il punto a fine fotogramma.
static func on_wait_finished(member: HumanIndividual, context: Dictionary, instructed: bool, action: WaitAtPointAction) -> void:
	_actions[member.id] = action
	var game_data: GameData = GameSettings.active_game_data
	var point_id := int(context.get(CONTEXT_POINT_ID, -1))
	if game_data == null or point_id < 0:
		return
	_update_now()
	var post: Dictionary = game_data.coordinator_posts.get(str(point_id), {})
	if is_coordinate_task(member.current_task):
		if int(post.get("coordinator_id", -1)) == member.id:
			post["coordinator_id"] = -1
			post["serving_id"] = -1
			if instructed:
				log_event(member, "autoassegnazione finita: lascia il posto e prende il lavoro (%s)." % _shift_summary(member))
	elif not post.is_empty():
		var queue: Array = post.get("queue", [])
		queue.erase(member.id)
		if int(post.get("serving_id", -1)) == member.id:
			post["serving_id"] = -1
			if instructed:
				var coordinator_info := _info_of_id(int(post.get("coordinator_id", -1)))
				coordinator_info["instructed"] = int(coordinator_info.get("instructed", 0)) + 1
	if _is_ready(game_data):
		_process_point_deferred.call_deferred(point_id)


# Un lavoro è diventato prendibile (entrato in coda o finita la sua attesa per l'assegnazione a mano — GameScene, giro
# della lista): evento per ogni punto con un coordinatore, che può chiamare chi è in svago o autoassegnarsi.
static func on_jobs_available() -> void:
	var game_data: GameData = GameSettings.active_game_data
	if not _is_ready(game_data):
		return
	for post_key in game_data.coordinator_posts.keys():
		if int((game_data.coordinator_posts[post_key] as Dictionary).get("coordinator_id", -1)) >= 0:
			_process_point_deferred.call_deferred(int(post_key))


# Limite di attesa del coordinatore scaduto (evento della sua WaitAtPointAction): decisione a fine fotogramma.
static func on_wait_timeout(member: HumanIndividual, context: Dictionary) -> void:
	var point_id := int(context.get(CONTEXT_POINT_ID, -1))
	if point_id >= 0 and _is_ready(GameSettings.active_game_data):
		_process_point_deferred.call_deferred(point_id)


static func _process_point_deferred(point_id: int) -> void:
	var game_data: GameData = GameSettings.active_game_data
	var world: World = GameSettings.active_world
	if world == null or not _is_ready(game_data):
		return
	var point := _find_point(world, point_id)
	if point == null:
		return
	_update_now()
	_process_point(game_data, point, GameSettings.active_human_individuals, true)


# --- Giro al secondo: solo controlli di sicurezza (nessuna istruzione avviata qui) ---

static func tick(game_data: GameData, world: World, individuals: Array[HumanIndividual], now: float, age_band_of: Callable) -> void:
	if game_data == null or world == null:
		return
	_last_now = now
	if age_band_of.is_valid():
		age_band_resolver = age_band_of
	# Scena non ancora pronta (caricamento in corso): nessuna decisione.
	if not scene_ready_checker.is_valid() or not bool(scene_ready_checker.call()):
		return
	var points: Dictionary = {}
	for building in world.buildings:
		if is_valid_point(building):
			points[building.id] = building
	# Primo giro con il gioco pronto (dopo un caricamento o in una partita nuova): posti di chi non ha più "Coordina"
	# liberati, poi un evento "gioco pronto" per ogni punto (decisione a fine fotogramma).
	if not game_data.coordinator_posts_checked:
		game_data.coordinator_posts_checked = true
		_log_info.clear()
		for post_key in game_data.coordinator_posts.keys():
			var loaded_post: Dictionary = game_data.coordinator_posts[post_key]
			var loaded_coordinator := _find(individuals, int(loaded_post.get("coordinator_id", -1)))
			if loaded_coordinator != null and _is_coordinating_at(loaded_coordinator, int(post_key)):
				_info_of(loaded_coordinator)["coordinator"] = true
			elif int(loaded_post.get("coordinator_id", -1)) >= 0:
				loaded_post["coordinator_id"] = -1
				loaded_post["serving_id"] = -1
				log_text("posto del punto #%s liberato al caricamento (%s non coordina più)." % [
					str(post_key), loaded_coordinator.name if loaded_coordinator != null else "il coordinatore",
				])
		for point_id in points.keys():
			_process_point_deferred.call_deferred(point_id)
		return
	# Chi cerca lavoro verso un punto sparito: l'attesa finisce (prende il lavoro da sé, o va allo svago).
	var waiting_points: Dictionary = {}
	for member in individuals:
		var task := member.current_task
		if task == null or task.is_finished() or task.task_name != JobBoardService.SEEK_JOB_TASK_NAME:
			continue
		var point_id := int(task.context.get(CONTEXT_POINT_ID, -1))
		if not points.has(point_id):
			if task.get_current_action() is WaitAtPointAction:
				_release(member)
			elif age_band_resolver.is_valid():
				# Ancora in cammino verso il punto sparito (2026-10-10): smette subito; libero, cerca un altro punto o va allo
				# svago (senza punti la coda non è attiva).
				member.stop(false)
				HumanIndividualActionService.resolve_idle_individual(member, age_band_resolver.call(member), world)
			continue
		waiting_points[point_id] = true
	# Posti di punti spariti: il coordinatore finisce il turno.
	for key in game_data.coordinator_posts.keys():
		if points.has(int(key)):
			continue
		var gone_coordinator := _find(individuals, int((game_data.coordinator_posts[key] as Dictionary).get("coordinator_id", -1)))
		if gone_coordinator != null and is_coordinate_task(gone_coordinator.current_task):
			log_event(gone_coordinator, "fine del turno: punto di assegnazione #%s sparito (%s)." % [str(key), _shift_summary(gone_coordinator)])
			_release(gone_coordinator)
		game_data.coordinator_posts.erase(key)
	for point_id in points.keys():
		if game_data.coordinator_posts.has(str(point_id)) or waiting_points.has(point_id):
			_process_point(game_data, points[point_id], individuals, false)


# --- Decisioni per un punto: nessun tempo misurato qui. `allow_start`: true solo dagli eventi (istruzioni e
# autoassegnazione); il giro di sicurezza passa false. ---

static func _process_point(game_data: GameData, point: Building, individuals: Array[HumanIndividual], allow_start: bool) -> void:
	var key := str(point.id)
	# Chi cerca lavoro verso questo punto: arrivato (in attesa) o ancora in cammino.
	var waiting: Array[HumanIndividual] = []
	var walking_count := 0
	for member in individuals:
		var task := member.current_task
		if task == null or task.is_finished() or task.task_name != JobBoardService.SEEK_JOB_TASK_NAME:
			continue
		if int(task.context.get(CONTEXT_POINT_ID, -1)) != point.id:
			continue
		var wait_action := task.get_current_action() as WaitAtPointAction
		if wait_action != null:
			if not wait_action.released:
				waiting.append(member)
		else:
			walking_count += 1
	var post: Dictionary = game_data.coordinator_posts.get(key, {})
	if post.is_empty() and waiting.is_empty():
		return
	# Fila in ordine di arrivo: tolti quelli che non aspettano più, aggiunti in fondo i nuovi arrivati.
	var waiting_ids: Array[int] = []
	for member in waiting:
		waiting_ids.append(member.id)
	var queue: Array[int] = []
	for raw_id in post.get("queue", []):
		if waiting_ids.has(int(raw_id)) and not queue.has(int(raw_id)):
			queue.append(int(raw_id))
	# Nuovi arrivati: la riga del log si scrive dopo aver deciso chi coordina (_log_arrivals).
	var newly_arrived: Array[int] = []
	for member_id in waiting_ids:
		if not queue.has(member_id):
			queue.append(member_id)
			newly_arrived.append(member_id)
	post["queue"] = queue
	game_data.coordinator_posts[key] = post
	# Coordinatore ancora al suo posto? Altrimenti il posto si libera e il primo della fila lo prende.
	var coordinator := _find(individuals, int(post.get("coordinator_id", -1)))
	if coordinator != null and not _is_coordinating_at(coordinator, point.id):
		log_event(coordinator, "fine del turno: %s (%s)." % [_interruption_reason(coordinator), _shift_summary(coordinator)])
		_forget(coordinator.id)
		coordinator = null
	elif coordinator == null and int(post.get("coordinator_id", -1)) >= 0:
		var missing_id := int(post.get("coordinator_id", -1))
		log_text("fine del turno del coordinatore #%d: non c'è più (%s)." % [missing_id, _shift_summary_of_id(missing_id)])
		_forget(missing_id)
	if coordinator == null:
		post["coordinator_id"] = -1
		post["serving_id"] = -1
		for member_id in queue.duplicate():
			var candidate := _find(individuals, member_id)
			if candidate != null and can_coordinate(candidate) and _start_coordinating(candidate, point):
				post["coordinator_id"] = candidate.id
				queue.erase(member_id)
				_log_info[candidate.id] = {"coordinator": true, "instructed": 0}
				if newly_arrived.has(candidate.id):
					log_event(candidate, "arriva a %s #%d e diventa coordinatore." % [point.building_type_name, point.id])
					newly_arrived.erase(candidate.id)
				else:
					log_event(candidate, "diventa coordinatore di %s #%d." % [point.building_type_name, point.id])
				break
		_log_arrivals(individuals, point, queue, newly_arrived, int(post["serving_id"]), int(post["coordinator_id"]) >= 0)
		if int(post["coordinator_id"]) < 0 and queue.is_empty():
			game_data.coordinator_posts.erase(key)
		return
	_log_arrivals(individuals, point, queue, newly_arrived, int(post.get("serving_id", -1)), true)
	# Il coordinatore decide solo quando è al punto (attesa di "Coordina" in corso).
	var coordinator_wait := _wait_action_of(coordinator)
	if coordinator_wait == null:
		return
	# Nuovo arrivo al punto: il limite di attesa del coordinatore riparte da zero.
	if not newly_arrived.is_empty():
		coordinator_wait.reset_idle_timer()
	var serving_id := int(post.get("serving_id", -1))
	if serving_id >= 0:
		# Istruzione in corso (la misura l'azione di chi la riceve): niente da decidere, a meno che non sia sparito.
		if serving_id == coordinator.id:
			if coordinator_wait.instructing:
				return
		elif queue.has(serving_id):
			var served_wait := _wait_action_of(_find(individuals, serving_id))
			if served_wait != null and served_wait.instructing:
				return
		post["serving_id"] = -1
	if not queue.is_empty():
		if not allow_start:
			return
		var next_member := _find(individuals, queue[0])
		var next_wait := _wait_action_of(next_member)
		if next_wait != null:
			next_wait.start_instruction(coordinator.id)
			post["serving_id"] = next_member.id
			log_event(coordinator, "istruisce %s." % next_member.name)
		return
	if allow_start:
		# Limite di attesa scaduto (anche con qualcuno in cammino): si autoassegna se c'è un lavoro per lui, altrimenti
		# chiude il turno.
		if coordinator_wait.timed_out:
			if bool(JobBoardService.job_available_checker.call(coordinator)):
				coordinator_wait.start_instruction()
				post["serving_id"] = coordinator.id
				log_event(coordinator, "attesa scaduta (%s): si autoassegna." % _days_text(SELF_ASSIGN_WAIT_DAYS))
			else:
				log_event(coordinator, "attesa scaduta: niente per lui, fine del turno (%s)." % _shift_summary(coordinator))
				post["coordinator_id"] = -1
				_release(coordinator)
				game_data.coordinator_posts.erase(key)
			return
		# Unico del gruppo che può prendere almeno un lavoro della coda: si autoassegna subito.
		if _is_only_worker(coordinator, individuals):
			coordinator_wait.start_instruction()
			post["serving_id"] = coordinator.id
			log_event(coordinator, "unico lavoratore: si autoassegna subito.")
			return
	# Richiamo (solo dagli eventi), prima della decisione di autoassegnarsi: chi viene chiamato è subito in cammino.
	if allow_start:
		walking_count += _call_idle_individuals(point, coordinator, individuals, walking_count)
	if walking_count > 0:
		return
	# Nessuno in fila né in cammino.
	if not JobBoardService.queue_has_jobs():
		log_event(coordinator, "fine del turno: coda vuota (%s)." % _shift_summary(coordinator))
		post["coordinator_id"] = -1
		_release(coordinator)
		game_data.coordinator_posts.erase(key)
	elif allow_start and bool(JobBoardService.job_available_checker.call(coordinator)):
		coordinator_wait.start_instruction()
		post["serving_id"] = coordinator.id
		log_event(coordinator, "nessuno in fila né in arrivo: si autoassegna un lavoro.")


# Il coordinatore è l'unico del gruppo che può prendere almeno un lavoro della coda (stessi controlli della presa): lui
# sì, nessun altro individuo sì.
static func _is_only_worker(coordinator: HumanIndividual, individuals: Array[HumanIndividual]) -> bool:
	if not bool(JobBoardService.job_available_checker.call(coordinator)):
		return false
	for member in individuals:
		if member != coordinator and bool(JobBoardService.job_available_checker.call(member)):
			return false
	return true


static func _days_text(days: float) -> String:
	return "1 giorno" if is_equal_approx(days, 1.0) else "%s giorni" % str(snappedf(days, 0.01))


# Richiamo (2026-10-09): quanti = lavori prendibili in coda − chi è già in cammino verso il punto − 1 (il coordinatore);
# ≤ 0 = nessuno. Candidati: solo individui in svago (task con is_idle_activity; mai bisogni né altre task) entro il
# raggio dal punto, che possono prendere almeno un lavoro (stessi filtri della presa), dal più vicino al punto. Il
# chiamato lascia lo svago e riceve "Cerca lavoro" verso il punto. Un suono "hey" alla posizione del coordinatore se
# chiama almeno una persona. Ritorna quanti ne ha chiamati.
static func _call_idle_individuals(
	point: Building, coordinator: HumanIndividual, individuals: Array[HumanIndividual], walking_count: int
) -> int:
	var needed := JobBoardService.open_jobs_count() - walking_count - 1
	if needed <= 0:
		return 0
	var radius := CALL_RADIUS_BASE * (1.0 + CALL_RADIUS_LEADERSHIP_BONUS * coordinator.skill_leadership / 1000.0)
	# Punto di assegnazione danneggiato (2026-10-10): raggio di richiamo a metà; resta comunque punto di assegnazione.
	if point != null and point.is_damaged():
		radius *= 0.5
	var candidates: Array[Dictionary] = []
	for member in individuals:
		if member == coordinator:
			continue
		var task := member.current_task
		if task == null or task.is_finished() or not task.is_idle_activity:
			continue
		var distance := member.position.distance_to(SpatialSelectionService._position_relative_to(point, member.home_macro_coords))
		if distance <= radius:
			candidates.append({"member": member, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	var called: Array[String] = []
	for candidate in candidates:
		if called.size() >= needed:
			break
		var member: HumanIndividual = candidate["member"]
		if not bool(JobBoardService.job_available_checker.call(member)):
			continue
		if JobBoardService.start_seek_job(member, age_band_resolver.call(member), point):
			called.append(member.name)
	if called.is_empty():
		log_event(coordinator, "nessuno in svago nel raggio (raggio %.1f)." % radius)
		return 0
	log_event(coordinator, "chiama %d: %s (raggio %.1f)." % [called.size(), ", ".join(called), radius])
	if call_sound_emitter.is_valid():
		call_sound_emitter.call(coordinator)
	return called.size()


# Righe di arrivo di chi resta in fila: con un coordinatore, la posizione (1 = il prossimo a essere istruito, escluso chi
# sta già ricevendo le istruzioni); senza (nessuno ha potuto prendere il posto), solo l'attesa.
static func _log_arrivals(
	individuals: Array[HumanIndividual], point: Building, queue: Array[int], newly_arrived: Array[int], serving_id: int,
	has_coordinator: bool
) -> void:
	for member_id in newly_arrived:
		var member := _find(individuals, member_id)
		if member == null:
			continue
		if not has_coordinator:
			log_event(member, "arriva a %s #%d e aspetta (nessun coordinatore)." % [point.building_type_name, point.id])
			continue
		var position := 0
		for queued_id in queue:
			if queued_id == serving_id:
				continue
			position += 1
			if queued_id == member_id:
				break
		log_event(member, "arriva a %s #%d e si mette in fila (posizione %d)." % [point.building_type_name, point.id, position])


static func _is_coordinating_at(member: HumanIndividual, point_id: int) -> bool:
	var task := member.current_task
	return is_coordinate_task(task) and not task.is_finished() and int(task.context.get(CONTEXT_POINT_ID, -1)) == point_id


# "Coordina" (solo l'attesa): assegnata qui, la sua attivazione è l'evento che fa partire subito, nello stesso
# fotogramma, la prima decisione del coordinatore.
static func _start_coordinating(member: HumanIndividual, point: Building) -> bool:
	var definition := load(COORDINATE_TASK_PATH) as TaskDefinition
	if definition == null or not age_band_resolver.is_valid():
		return false
	var task := TaskFactory.build_task(definition, {CONTEXT_POINT_ID: point.id})
	return member.assign_task(task, age_band_resolver.call(member))


# Fine immediata dell'attesa al punto (WaitAtPointAction.released): alla chiusura dello step l'individuo prende il lavoro
# dalla lista o va allo svago (job_seek_arrived).
static func _release(member: HumanIndividual) -> void:
	var action := _wait_action_of(member)
	if action != null:
		action.released = true


static func _find(individuals: Array[HumanIndividual], member_id: int) -> HumanIndividual:
	if member_id < 0:
		return null
	for member in individuals:
		if member.id == member_id:
			return member
	return null


static func _find_point(world: World, point_id: int) -> Building:
	for building in world.buildings:
		if building.id == point_id and is_valid_point(building):
			return building
	return null


static func _wait_action_of(member: HumanIndividual) -> WaitAtPointAction:
	if member == null or member.current_task == null:
		return null
	return member.current_task.get_current_action() as WaitAtPointAction


static func _update_now() -> void:
	if now_provider.is_valid():
		_last_now = float(now_provider.call())


# Motivo per cui chi coordinava non ha più "Coordina": un bisogno, H (end_shift_by_player lo scrive già) o altro.
static func _interruption_reason(member: HumanIndividual) -> String:
	var task := member.current_task
	if task != null and task.interrupt_priority >= 0:
		return "bisogno (%s)" % TranslationServer.translate(task.task_name)
	if task == null:
		return "interrotto"
	return "interrotto da '%s'" % TranslationServer.translate(task.task_name)


# H del giocatore su chi coordina (GameScene._stop_member_task, 2026-10-09): il posto si libera subito, con il motivo.
static func end_shift_by_player(game_data: GameData, member: HumanIndividual) -> void:
	if game_data == null or member == null or not is_coordinate_task(member.current_task):
		return
	_update_now()
	var point_id := int(member.current_task.context.get(CONTEXT_POINT_ID, -1))
	var post: Dictionary = game_data.coordinator_posts.get(str(point_id), {})
	if int(post.get("coordinator_id", -1)) == member.id:
		post["coordinator_id"] = -1
		post["serving_id"] = -1
	log_event(member, "fine del turno: H (%s)." % _shift_summary(member))
	_forget(member.id)
	# Il prossimo in fila prende il posto (evento: decisione a fine fotogramma).
	if point_id >= 0 and _is_ready(game_data):
		_process_point_deferred.call_deferred(point_id)


# --- Log [COORDINATORE]: valori accumulati dall'azione (tempo e stamina realmente applicati) ---

# Partenza dal punto (HumanIndividualActionService.resolve_idle_individual, dopo la fine dell'attesa): `received_text` =
# il lavoro preso, "" = niente per lui (svago). Chi aspettava: attesa prima dell'istruzione, durata dell'istruzione,
# stamina dell'attesa; il coordinatore (autoassegnazione o fine del turno): durata dell'istruzione, se c'è stata, durata
# e stamina del turno.
static func report_departure(member: HumanIndividual, received_text: String) -> void:
	if member == null:
		return
	_update_now()
	var action: WaitAtPointAction = _actions.get(member.id, null)
	var info: Dictionary = _log_info.get(member.id, {})
	var parts: Array[String] = []
	if action == null:
		parts.append("tempi non disponibili")
	elif bool(info.get("coordinator", false)):
		if action.instructing:
			parts.append("istruzione %s" % _hours_text(action.get_instruction_days()))
		parts.append("turno %s" % _hours_text(action.get_elapsed_days()))
		parts.append("stamina del turno −%.1f" % action.stamina_spent)
	else:
		parts.append("attesa %s" % _hours_text(action.wait_before_instruction if action.instructing else action.get_elapsed_days()))
		if action.instructing:
			parts.append("istruzione %s" % _hours_text(action.get_instruction_days()))
		parts.append("stamina −%.1f" % action.stamina_spent)
		# Lavoro ricevuto alla fine di un'istruzione: cresce la Leadership di chi l'ha istruito.
		if received_text != "" and action.instructing and action.instructor_id >= 0:
			var leadership_text := _grant_leadership(action.instructor_id)
			if leadership_text != "":
				parts.append(leadership_text)
	if received_text != "":
		log_event(member, "lavoro ricevuto: %s (%s)." % [received_text, ", ".join(parts)])
	else:
		log_event(member, "niente per lui → svago (%s)." % ", ".join(parts))
	_forget(member.id)


# Crescita della Leadership del coordinatore `coordinator_id` (LEADERSHIP_GAIN_PER_ASSIGNMENT, tetto HumanIndividual.SKILL_MAX):
# somma diretta, come le altre skill (TaskCompletionEffectService), più il tetto. Testo per il log ("" se non c'è più).
static func _grant_leadership(coordinator_id: int) -> String:
	var coordinator := _find(GameSettings.active_human_individuals, coordinator_id)
	if coordinator == null:
		return ""
	var before := coordinator.skill_leadership
	coordinator.skill_leadership = minf(before + LEADERSHIP_GAIN_PER_ASSIGNMENT, maxf(HumanIndividual.SKILL_MAX, before))
	return "Leadership di %s %d → %d" % [coordinator.name, roundi(before), roundi(coordinator.skill_leadership)]


static func _forget(member_id: int) -> void:
	_actions.erase(member_id)
	_log_info.erase(member_id)


static func _info_of(member: HumanIndividual) -> Dictionary:
	return _info_of_id(member.id)


static func _info_of_id(member_id: int) -> Dictionary:
	if not _log_info.has(member_id):
		_log_info[member_id] = {}
	return _log_info[member_id]


# "turno 3.5 h, istruiti 2, stamina −20.0" dall'attesa di "Coordina" ("?" se non disponibile, es. dopo un caricamento).
static func _shift_summary(member: HumanIndividual) -> String:
	return _shift_summary_of_id(member.id)


static func _shift_summary_of_id(member_id: int) -> String:
	var action: WaitAtPointAction = _actions.get(member_id, null)
	var instructed := int((_log_info.get(member_id, {}) as Dictionary).get("instructed", 0))
	if action == null:
		return "turno ?, istruiti %d, stamina ?" % instructed
	return "turno %s, istruiti %d, stamina −%.1f" % [_hours_text(action.get_elapsed_days()), instructed, action.stamina_spent]


static func _hours_text(days: float) -> String:
	return "%.1f h" % (days * 24.0)


# Giorno e ora di gioco (orologio): "g12 08:30 ".
static func _time_prefix() -> String:
	if _last_now < 0.0:
		return ""
	var day := int(floor(_last_now)) % GameData.DAYS_PER_YEAR
	var minutes := int(floor((_last_now - floor(_last_now)) * 24.0 * 60.0))
	return "g%d %02d:%02d " % [day, floori(minutes / 60.0), minutes % 60]


# Log [COORDINATORE] (DebugLogging.SHOW_COORDINATOR_LOGS), con giorno e ora di gioco e il nome dell'individuo.
static func log_event(member: HumanIndividual, text: String) -> void:
	if member == null:
		log_text(text)
	elif DebugLogging.ENABLED and DebugLogging.SHOW_COORDINATOR_LOGS:
		print("[COORDINATORE] %s%s: %s" % [_time_prefix(), member.name, text])


static func log_text(text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_COORDINATOR_LOGS:
		print("[COORDINATORE] %s%s" % [_time_prefix(), text])
