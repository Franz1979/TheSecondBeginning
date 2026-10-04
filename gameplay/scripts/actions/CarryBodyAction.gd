class_name CarryBodyAction
extends WalkAction

# "Cammina al cumulo" con il corpo in spalla (2026-10-04, richiesta utente — cumulo sepolcrale passo 2, terzo step di
# bury.tres). Una WalkAction (stesso movimento, stessa stamina — a pieno carico per HumanIndividual.get_walk_load_space —,
# stesso `target` Vector2 ribasato agli attraversamenti di bordo e salvato) verso un punto accanto al cumulo
# `target_building_id`, scelto all'assegnazione (BodyBurialService.find_nearest_mound) e già "prenotato" da questa task.
#
# Il cumulo viene ricontrollato a ogni tick (is_complete): se non è più valido (demolito, da demolire, senza più un posto
# per questo corpo) se ne sceglie un altro, il più vicino al pipottino, e il cammino riparte verso di lui; se non ce n'è
# nessuno lo step si chiude: il pipottino posa il corpo dove si trova, la task viene annullata e il giocatore avvisato
# (segnale burial_aborted, collegato da GameScene._ensure_step_signals).

signal burial_aborted(individual: HumanIndividual, body_name: String)

var body_id: int = -1
var target_building_id: int = -1
var _no_mound: bool = false


func _init(p_body_id: int = -1, p_target_building_id: int = -1) -> void:
	super(Vector2.ZERO)
	body_id = p_body_id
	target_building_id = p_target_building_id
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Valida finché il corpo esiste (in spalla non scade); il cumulo viene risolto in cammino.
func is_target_valid() -> bool:
	return not BodyBurialService.find_body_record(body_id).is_empty()


func activate(individual: Variant, context: Dictionary) -> void:
	_no_mound = not _resolve_mound(individual)
	if _no_mound:
		individual.clear_path()
		individual.is_moving = false
		return
	super(individual, context)
	# Passo rallentato con il corpo in spalla (2026-10-04, richiesta utente): metà del passo normale, l'INVERSO della corsa
	# (RunAction.RUN_INTENSITY_MULTIPLIER, 2.0 -> 0.5). I due valori sono legati: cambiare la corsa cambia anche questo.
	# Dopo super (Action.activate lo riporta a 1.0); riapplicato a ogni riattivazione dello step (anche al passaggio di
	# macrocella), e il prossimo step o la task che interrompe questa lo rimettono a 1.0. Il corpo trascinato segue la
	# posizione del pipottino (GameScene._drag_carried_body_view), quindi lo segue alla stessa velocità.
	individual.move_speed_multiplier = 1.0 / RunAction.RUN_INTENSITY_MULTIPLIER


# Tiene il cumulo attuale se ancora valido, altrimenti sceglie il più vicino raggiungibile; aggiorna `target` (punto
# accanto al cumulo). false se nessun cumulo è disponibile.
func _resolve_mound(individual: HumanIndividual) -> bool:
	var individuals: Array = GameSettings.active_human_individuals
	var building := BodyBurialService.find_building(target_building_id)
	if not BodyBurialService.is_mound_usable(building, body_id, individuals):
		building = BodyBurialService.find_nearest_mound(
			individual.position, individual.home_macro_coords, body_id, individuals, PathfindingService.reachability_for(individual)
		)
	if building == null:
		target_building_id = -1
		return false
	if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS and building.id != target_building_id:
		print("[BURY] #%d %s: destinazione del corpo -> cumulo #%d." % [individual.id, individual.name, building.id])
	target_building_id = building.id
	target = BodyBurialService.get_put_down_point(building, individual)
	return true


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if _no_mound:
		return true
	var building := BodyBurialService.find_building(target_building_id)
	if not BodyBurialService.is_mound_usable(building, body_id, GameSettings.active_human_individuals):
		if not _resolve_mound(individual):
			_no_mound = true
			return true
		# Nuovo cumulo: il cammino riparte verso di lui.
		individual.target_position = target
		individual.is_moving = true
		request_path(individual, target)
	return super(individual, context)


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _no_mound:
		var body_name := BodyBurialService.get_body_name(BodyBurialService.find_body_record(body_id))
		BodyBurialService.put_down_carried_body(individual)
		individual.clear_path()
		individual.is_moving = false
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "nessun cumulo sepolcrale con posti liberi"
		burial_aborted.emit(individual, body_name)
		return
	# Cumulo raggiunto: il passo "posa il corpo" lo legge dal context.
	context[BodyBurialService.CONTEXT_MOUND_ID] = target_building_id
	super(individual, context)


func get_save_data() -> Dictionary:
	return {"body_id": body_id, "target_building_id": target_building_id}
