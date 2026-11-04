class_name SlaughterAction
extends Action

# Macella un animale domestico per ordine del giocatore (cane, passo 7, 2026-11-04; unico step di slaughter.tres). Generica
# per ogni specie domestica. L'animale continua a girare e non scappa: la persona lo segue al passo normale (schema di
# ApproachPreyAction e FollowIndividualAction, bersaglio ritrovato a ogni tick) e arrivata al contatto lo uccide, con la lama
# in cintura. Lascia una carcassa macellabile dove sta l'animale e chiede la macellazione esistente sul posto, con lo stesso
# canale della caccia (HuntService.CONTEXT_PENDING_BUTCHER, destinazione nel context della Task). Nessun uso del coltello
# qui: lo consuma la macellazione.
#
# Stamina dell'uccisione: i numeri di ButcherAction, consumo al giorno per la sua durata minima, tutti insieme perché
# l'uccisione è istantanea.
#
# Animale irraggiungibile: la persona aspetta ferma e riprova, il lavoro resta suo (come il corteo). Senza lama: ferma in
# attesa (Action.ensure_required_tools). Animale sparito: la Task si chiude.

const REACH: float = ApproachPreyAction.MELEE_REACH
const KILL_STAMINA_COST: float = ButcherAction.STAMINA_DRAIN_PER_DAY * ButcherAction.MIN_DURATION_DAYS
const PATH_REPLAN_MIN_INTERVAL_MSEC: int = 250
const _NO_CELL := Vector2i(-99999, -99999)

var animal_id: int = -1

var _done: bool = false
var _last_position: Variant = null
var _planned_cell: Vector2i = _NO_CELL
var _last_replan_msec: int = -PATH_REPLAN_MIN_INTERVAL_MSEC


func _init(p_animal_id: int = -1) -> void:
	target = null
	animal_id = p_animal_id
	required_tool_categories = [TaskTypes.ToolCategory.BUTCHERING]
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func _get_animal() -> DomesticAnimal:
	return DomesticAnimalService.find_animal(GameSettings.active_game_data, animal_id)


func is_target_valid() -> bool:
	return _get_animal() != null


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_done = false
	_last_position = null
	_planned_cell = _NO_CELL
	_last_replan_msec = -PATH_REPLAN_MIN_INTERVAL_MSEC
	individual.clear_path()


# Costo del tratto percorso nell'ultimo frame, poi l'inseguimento per il frame successivo.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done:
		return 0.0
	var stamina_delta := 0.0
	if _last_position != null:
		stamina_delta = WalkAction.compute_walk_stamina_delta(individual, individual.position.distance_to(_last_position), "Slaughter")
	_last_position = individual.position
	if _update_pursuit(individual, context):
		stamina_delta -= KILL_STAMINA_COST
	return stamina_delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


func get_save_data() -> Dictionary:
	return {"animal_id": animal_id}


# true se in questo tick l'animale è stato ucciso.
func _update_pursuit(individual: Variant, context: Dictionary) -> bool:
	var animal := _get_animal()
	if animal == null:
		_done = true
		_stand_still(individual)
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "animale da macellare sparito"
		return false
	if not ensure_required_tools(individual) or animal.macro_coords.x < 0:
		_stand_still(individual)
		return false
	var animal_position: Vector2 = animal.position + Vector2(animal.macro_coords - individual.home_macro_coords) * World.WIDTH
	if individual.position.distance_to(animal_position) <= REACH:
		_done = true
		_stand_still(individual)
		_kill(animal, context)
		return true
	_follow(individual, animal, animal_position)
	return false


func _kill(animal: DomesticAnimal, context: Dictionary) -> void:
	var carcass := DomesticAnimalSlaughterService.kill(GameSettings.active_game_data, animal)
	if carcass.is_empty():
		return
	context[HuntService.CONTEXT_KILL_CARCASS] = carcass
	var butcher_request := carcass.duplicate()
	butcher_request["requested_by"] = "macellazione di un animale domestico"
	context[HuntService.CONTEXT_PENDING_BUTCHER] = butcher_request


# Percorso verso la microcella dell'animale, ricalcolato solo quando cambia cella o il percorso è perso; tratto diretto se è
# adiacente, in un'altra macrocella o senza griglia.
func _follow(individual: Variant, animal: DomesticAnimal, animal_position: Vector2) -> void:
	individual.is_moving = true
	var cell: LiveMacroCell = PathfindingService.get_live_cell(individual.home_macro_coords)
	var my_cell := Vector2i(individual.position.floor())
	var animal_cell := Vector2i(animal_position.floor())
	var adjacent: bool = maxi(absi(animal_cell.x - my_cell.x), absi(animal_cell.y - my_cell.y)) <= 1
	if animal.macro_coords != individual.home_macro_coords or cell == null or cell.path_grid == null or adjacent \
			or not PathfindingService._in_bounds(my_cell) or not PathfindingService._in_bounds(animal_cell):
		_go_direct(individual, animal_position)
		return
	var path_lost: bool = individual.path_target != individual.target_position or (not individual.path_active and not individual.path_pending)
	var now_msec := Time.get_ticks_msec()
	if (animal_cell == _planned_cell and not path_lost) or now_msec - _last_replan_msec < PATH_REPLAN_MIN_INTERVAL_MSEC:
		return
	_last_replan_msec = now_msec
	_planned_cell = animal_cell
	if not PathfindingService.is_reachable(cell, my_cell, animal_cell):
		_stand_still(individual)
		return
	var cell_center := Vector2(animal_cell) + Vector2(0.5, 0.5)
	request_path(individual, cell_center)
	individual.target_position = cell_center


func _go_direct(individual: Variant, destination: Vector2) -> void:
	if individual.path_active or individual.path_pending:
		individual.clear_path()
	_planned_cell = _NO_CELL
	individual.target_position = destination
	individual.is_moving = true


func _stand_still(individual: Variant) -> void:
	individual.clear_path()
	individual.target_position = individual.position
	individual.is_moving = false
