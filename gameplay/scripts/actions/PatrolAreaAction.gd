class_name PatrolAreaAction
extends Action

# Pattuglia di una zona di lavoro per la caccia (2026-10-01, richiesta utente — caccia nelle zone, passo 2a). Primo
# step della Task hunt_zone.tres: il cacciatore cammina tra punti a caso dentro la zona e, ogni CHECK_INTERVAL_DAYS,
# cerca una preda con HuntZoneService.choose_prey (avvistamento entro il SUO raggio di vista). Esiti, letti da
# on_complete:
#   - preda avvistata: scrive la preda nel context (HuntZoneService.write_prey_context) e chiede l'inserimento degli
#     step di caccia di sempre — ApproachPrey → Aim → Throw — subito dopo di sé (HuntZoneService.CONTEXT_PENDING_PREY,
#     consumato da HumanIndividualActionService._handle_pending_hunt_zone_prey). L'inseguimento può uscire dalla zona;
#   - PATROL_DAYS_WITHOUT_PREY_LIMIT giorni dell'uscita senza catture: l'uscita finisce (chiusura anticipata, nessun
#     effetto di completamento). Dal 2026-10-10 il contatore (HuntZoneService.CONTEXT_UNSIGHTED_DAYS, nel context:
#     salvato con la Task) lo fa avanzare HumanIndividualActionService.apply_action per tutta l'uscita, dall'arrivo nella
#     zona (avvio qui, HuntZoneService.CONTEXT_CAPTURE_CLOCK_STARTED; il tragitto non conta), e lo azzera solo
#     un'uccisione: qui si controlla soltanto il limite (gli avvistamenti non lo azzerano più);
#   - zona eliminata o irraggiungibile: l'uscita finisce.
# Nessun attrezzo richiesto qui: il coltello è controllato al comando (HuntZoneService.get_hunt_rejection) e gli step
# di caccia hanno il loro gate HUNTING.

# Ogni quanto (giorni di gioco) si cerca una preda: abbastanza spesso da non "mancare" un animale che attraversa il
# raggio di vista, senza scorrere gli animali della macrocella a ogni frame.
const CHECK_INTERVAL_DAYS: float = 0.01
# Giorni di gioco dell'uscita senza catture dopo cui l'uscita finisce (comando Caccia nelle zone e ordine "Caccia" del
# cassetto). 2026-10-09: da 1 a 2 giorni. 2026-10-10: tutta l'uscita, non solo la pattuglia (vedi testa del file).
const PATROL_DAYS_WITHOUT_PREY_LIMIT: float = 2.0
# Distanza (microcelle) entro cui un punto di pattuglia è raggiunto e se ne sceglie un altro.
const WAYPOINT_REACH: float = 0.3
# Punti di pattuglia irraggiungibili di fila prima di considerare la zona irraggiungibile.
const MAX_UNREACHABLE_WAYPOINTS: int = 8

# WorkArea pattugliata (WorkArea.id). Salvato con lo step (get_save_data).
var work_area_id: int = -1

var _has_waypoint: bool = false
# Punto di pattuglia: microcella LOCALE alla macrocella della zona (il bersaglio vero si ricalcola rispetto alla home
# attuale del cacciatore, che cambia attraversando il bordo di una macrocella).
var _waypoint: Vector2i = Vector2i.ZERO
var _check_elapsed: float = 0.0
var _last_position: Variant = null
var _unreachable_count: int = 0
var _done: bool = false
var _found: bool = false
var _timed_out: bool = false
var _zone_missing: bool = false
var _zone_unreachable: bool = false


func _init(p_work_area_id: int = -1) -> void:
	target = null
	work_area_id = p_work_area_id
	# Stesse fasce della caccia (ApproachPreyAction).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD, HumanTypes.AgeBand.TEENAGER]


func is_target_valid() -> bool:
	return _get_area() != null


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_has_waypoint = false
	_check_elapsed = 0.0
	_last_position = null
	_unreachable_count = 0
	_done = false
	_found = false
	_timed_out = false
	_zone_missing = false
	_zone_unreachable = false
	var area := _get_area()
	if area == null:
		HuntZoneService.log_event(individual, "pattuglia: zona #%d non trovata, uscita chiusa." % work_area_id)
		_zone_missing = true
		_done = true
		return
	HuntZoneService.log_event(individual, "pattuglia avviata in %s #%d (senza catture da %.2f giorni)." % [
		area.name, area.id, HuntZoneService.get_days_without_capture(context)
	])
	# Limite senza catture già raggiunto (2026-10-10, es. ritorno alla pattuglia dopo un inseguimento): l'uscita finisce
	# senza cercare altre prede.
	if HuntZoneService.is_no_capture_limit_reached(context):
		_timed_out = true
		_finish(individual)
		return
	# Primo controllo subito: una preda già in vista all'avvio non aspetta il primo intervallo.
	if _try_sight(individual, context, area):
		return
	_pick_waypoint(individual, area)


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done:
		return 0.0
	var area := _get_area()
	if area == null:
		_zone_missing = true
		_finish(individual)
		return 0.0
	var stamina_delta := 0.0
	if _last_position != null:
		var distance: float = individual.position.distance_to(_last_position)
		stamina_delta = WalkAction.compute_walk_stamina_delta(individual, distance, "PatrolArea")
	_last_position = individual.position

	# Giorni senza catture (2026-10-10): li conta HumanIndividualActionService.apply_action per tutta l'uscita, dall'arrivo
	# nella zona in poi (il tragitto non conta): l'avvio del contatore è qui, al primo frame dentro la zona.
	if not HuntZoneService.is_capture_clock_started(context) \
			and area.contains(individual.home_macro_coords, Vector2i(individual.position.floor())):
		HuntZoneService.start_capture_clock(context)
		HuntZoneService.log_event(individual, "arrivato in %s #%d: parte il conteggio dei giorni senza catture." % [area.name, area.id])
	if HuntZoneService.is_no_capture_limit_reached(context):
		_timed_out = true
		_finish(individual)
		return stamina_delta

	_check_elapsed += delta
	if _check_elapsed >= CHECK_INTERVAL_DAYS:
		_check_elapsed = 0.0
		if _try_sight(individual, context, area):
			return stamina_delta

	var destination := _waypoint_position(individual, area)
	if is_path_unreachable(individual, destination):
		_unreachable_count += 1
		if _unreachable_count >= MAX_UNREACHABLE_WAYPOINTS:
			_zone_unreachable = true
			_finish(individual)
			return stamina_delta
		_pick_waypoint(individual, area)
	elif not _has_waypoint or individual.position.distance_to(destination) <= WAYPOINT_REACH:
		_unreachable_count = 0
		_pick_waypoint(individual, area)
	else:
		_head_to(individual, destination)
	return stamina_delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


func on_complete(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if _found:
		context[HuntZoneService.CONTEXT_PENDING_PREY] = true
		return
	if _zone_missing:
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "zona di caccia eliminata"
	elif _zone_unreachable:
		abort_task_unreachable(individual, context, "zona di caccia irraggiungibile")
	elif _timed_out:
		HuntZoneService.log_no_capture_end(individual, context, "la pattuglia")
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "nessuna cattura per %.1f giorni" % PATROL_DAYS_WITHOUT_PREY_LIMIT
		# Per chi segue la serie (2026-10-09, ordini di caccia del cassetto): uscita finita senza prede.
		context[HuntZoneService.CONTEXT_NO_PREY] = true


func get_save_data() -> Dictionary:
	return {"work_area_id": work_area_id}


func _get_area() -> WorkArea:
	return WorkAreaService.find_by_id(GameSettings.active_game_data, work_area_id)


# true (e step concluso) se c'è una preda da puntare: preda nel context. Il contatore senza catture NON si azzera qui
# (2026-10-10): solo un'uccisione lo azzera.
func _try_sight(individual: Variant, context: Dictionary, area: WorkArea) -> bool:
	# Prede lasciate per troppi tiri a vuoto (2026-10-10): ignorate per il resto dell'uscita.
	var prey := HuntZoneService.choose_prey(
		area, individual, PathfindingService.get_live_cells(), HuntZoneService.get_ignored_prey_ids(context)
	)
	if prey == null:
		return false
	HuntZoneService.write_prey_context(context, prey)
	# Preda avvistata prima di entrare nella zona: il conteggio parte comunque qui, con l'inseguimento.
	HuntZoneService.start_capture_clock(context)
	HuntService.log_event(individual, "pattuglia in %s: avvistato %s #%d — inizia l'inseguimento." % [area.name, prey.species_name, prey.id])
	_found = true
	_finish(individual)
	return true


func _pick_waypoint(individual: Variant, area: WorkArea) -> void:
	_waypoint = Vector2i(
		randi_range(area.rect.position.x, area.rect.end.x - 1),
		randi_range(area.rect.position.y, area.rect.end.y - 1)
	)
	_has_waypoint = true
	var destination := _waypoint_position(individual, area)
	request_path(individual, destination)
	_head_to(individual, destination)


func _waypoint_position(individual: Variant, area: WorkArea) -> Vector2:
	return Vector2(_waypoint) + Vector2(0.5, 0.5) + Vector2(area.macro_coords - individual.home_macro_coords) * World.WIDTH


func _head_to(individual: Variant, destination: Vector2) -> void:
	if individual.path_target != destination:
		request_path(individual, destination)
	individual.target_position = destination
	individual.is_moving = true


func _finish(individual: Variant) -> void:
	_done = true
	individual.clear_path()
	individual.target_position = individual.position
	individual.is_moving = false
