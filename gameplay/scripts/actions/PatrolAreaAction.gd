class_name PatrolAreaAction
extends Action

# Pattuglia di una zona di lavoro per la caccia (2026-10-01, richiesta utente — caccia nelle zone, passo 2a). Primo
# step della Task hunt_zone.tres: il cacciatore cammina tra punti a caso dentro la zona e, ogni CHECK_INTERVAL_DAYS,
# cerca una preda con HuntZoneService.choose_prey (avvistamento entro il SUO raggio di vista). Esiti, letti da
# on_complete:
#   - preda avvistata: scrive la preda nel context (HuntZoneService.write_prey_context) e chiede l'inserimento degli
#     step di caccia di sempre — ApproachPrey → Aim → Throw — subito dopo di sé (HuntZoneService.CONTEXT_PENDING_PREY,
#     consumato da HumanIndividualActionService._handle_pending_hunt_zone_prey). L'inseguimento può uscire dalla zona;
#   - MAX_UNSIGHTED_DAYS di gioco passati DENTRO la zona senza avvistamenti: l'uscita finisce (chiusura anticipata,
#     nessun effetto di completamento). Il contatore (HuntZoneService.CONTEXT_UNSIGHTED_DAYS, nel context: salvato con
#     la Task) riparte da zero a ogni avvistamento; il tragitto fino alla zona non conta;
#   - zona eliminata o irraggiungibile: l'uscita finisce.
# Nessun attrezzo richiesto qui: il coltello è controllato al comando (HuntZoneService.get_hunt_rejection) e gli step
# di caccia hanno il loro gate HUNTING.

# Ogni quanto (giorni di gioco) si cerca una preda: abbastanza spesso da non "mancare" un animale che attraversa il
# raggio di vista, senza scorrere gli animali della macrocella a ogni frame.
const CHECK_INTERVAL_DAYS: float = 0.01
# Un giorno di gioco intero dentro la zona senza avvistamenti chiude l'uscita.
const MAX_UNSIGHTED_DAYS: float = 1.0
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
	HuntZoneService.log_event(individual, "pattuglia avviata in %s #%d (senza avvistamenti da %.2f giorni)." % [
		area.name, area.id, float(context.get(HuntZoneService.CONTEXT_UNSIGHTED_DAYS, 0.0))
	])
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

	# Tempo senza avvistamenti: solo DENTRO la zona.
	if area.contains(individual.home_macro_coords, Vector2i(individual.position.floor())):
		var unsighted: float = float(context.get(HuntZoneService.CONTEXT_UNSIGHTED_DAYS, 0.0)) + delta
		context[HuntZoneService.CONTEXT_UNSIGHTED_DAYS] = unsighted
		if unsighted >= MAX_UNSIGHTED_DAYS:
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
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "nessuna preda avvistata per %.0f giorno di pattuglia" % MAX_UNSIGHTED_DAYS


func get_save_data() -> Dictionary:
	return {"work_area_id": work_area_id}


func _get_area() -> WorkArea:
	return WorkAreaService.find_by_id(GameSettings.active_game_data, work_area_id)


# true (e step concluso) se c'è una preda da puntare: preda nel context, contatore senza avvistamenti azzerato.
func _try_sight(individual: Variant, context: Dictionary, area: WorkArea) -> bool:
	var prey := HuntZoneService.choose_prey(area, individual, PathfindingService.get_live_cells())
	if prey == null:
		return false
	HuntZoneService.write_prey_context(context, prey)
	context[HuntZoneService.CONTEXT_UNSIGHTED_DAYS] = 0.0
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
