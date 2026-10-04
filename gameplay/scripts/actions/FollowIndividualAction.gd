class_name FollowIndividualAction
extends Action

# "Segui un pipottino" (2026-10-04, richiesta utente — corteo, meccanismo generico; unico step di procession.tres).
# Schema di ApproachPreyAction senza nulla della caccia (niente armi, attrezzi, gittata): a ogni tick ritrova la guida
# (`guide_id`), ne riporta la posizione nel riferimento del partecipante (scarto di macrocella) e:
#   - la segue al passo normale finché la guida cammina, fermandosi entro FOLLOW_DISTANCE microcelle da lei e
#     ripartendo quando si allontana oltre FOLLOW_DISTANCE + RESUME_MARGIN (un piccolo margine evita lo scatto
#     continuo fermo/riparte). Percorso: A* ripianificato solo quando la guida cambia microcella o il percorso è perso,
#     al massimo ogni PATH_REPLAN_MIN_INTERVAL_MSEC, dopo un controllo di raggiungibilità (regioni); linea retta se la
#     guida è in un'altra macrocella, adiacente o senza griglia. Guida irraggiungibile: aspetta fermo;
#   - quando la guida arriva all'edificio di arrivo (`building_id`, entro ARRIVAL_DISTANCE dal suo centro), va a un
#     posto libero accanto all'edificio — una microcella non bloccata nei primi anelli attorno, diversa da quella della
#     guida e da quelle già scelte da altri partecipanti dello stesso edificio — e resta lì.
# Scioglimento (is_complete, a ogni tick): la guida non c'è più, o la task della guida che tiene vivo il corteo non è
# più la sua task in corso (finita, annullata, scartata, in coda). Identificata per riferimento; dopo un caricamento
# (riferimento perso) si riaggancia alla task in corso della guida se ha lo stesso nome (`keeper_task_name`).
#
# IN FILA (2026-10-04, richiesta utente — opzione usata dal corteo, `queue_order` >= 0; -1 = il comportamento generico
# sopra, invariato): il bersaglio durante il cammino non è la guida ma un punto della sua scia (ProcessionService,
# punti percorsi dalla guida da quando il corteo è partito), a LINE_FIRST_GAP microcelle dietro di lei per il primo
# (spazio per il corpo trascinato) e LINE_SPACING in più per ciascuno dei successivi. Il posto in fila è il rango tra i
# partecipanti ancora attivi dello stesso corteo (ordinati per queue_order): chi lascia il corteo fa avanzare di un posto
# quelli dietro. Fermo quando è sul suo punto (LINE_ARRIVE), riparte quando il punto si allontana oltre LINE_RESUME.
# Chi è ancora davanti alla guida (nel verso di marcia) la aspetta fermo finché non è passata, così non la attraversa
# né la supera; da dietro raggiunge il suo punto al passo normale, con lo stesso cammino del comportamento generico.

const FOLLOW_DISTANCE: float = 2.0
const RESUME_MARGIN: float = 0.5
const ARRIVAL_DISTANCE: float = 2.5
# Anelli di microcelle attorno all'edificio in cui cercare il posto (1 = le 8 vicine).
const SLOT_MAX_RING: int = 3
const SLOT_ARRIVAL_TOLERANCE: float = 0.15
const PATH_REPLAN_MIN_INTERVAL_MSEC: int = 250
# Fila (vedi sopra).
const LINE_FIRST_GAP: float = 1.5
const LINE_SPACING: float = 1.0
const LINE_ARRIVE: float = 0.3
const LINE_RESUME: float = 0.6
# Quanto davanti alla guida (nel verso di marcia) un partecipante deve essere per aspettarla fermo.
const LINE_AHEAD_MARGIN: float = 0.5
# Scia tenuta oltre l'ultimo posto della fila.
const LINE_TRAIL_MARGIN: float = 2.0
const _NO_CELL := Vector2i(-99999, -99999)

var guide_id: int = -1
var building_id: int = -1
var keeper_task_name: String = ""
# Task della guida che tiene vivo il corteo (non salvata: vedi _resolve_keeper).
var keeper_task: Task = null
# true quando la guida è arrivata all'edificio: da lì il partecipante va al suo posto e ci resta.
var arrived: bool = false
# Posto scelto accanto all'edificio: microcella nella macrocella dell'edificio, _NO_CELL se non ancora scelto.
var slot: Vector2i = _NO_CELL
# Numero d'ordine nella fila del corteo (assegnato alla convocazione, dal più vicino alla guida); -1 = nessuna fila.
var queue_order: int = -1

var _last_position: Variant = null
var _dissolved: bool = false
# Solo per i log del corteo (2026-10-04, ProcessionService.tick — nessun effetto sul comportamento): perché il
# partecipante sta aspettando fermo ("" = non aspetta), e se è arrivato al suo posto accanto all'edificio.
const WAIT_GUIDE_UNREACHABLE := "guida irraggiungibile"
const WAIT_NO_FREE_SLOT := "nessun posto libero accanto all'edificio di arrivo"
var wait_state: String = ""
var reached_slot: bool = false
var _slot_unreachable: bool = false
var _standing: bool = false
var _planned_guide_cell: Vector2i = _NO_CELL
var _last_replan_msec: int = -PATH_REPLAN_MIN_INTERVAL_MSEC


func _init(
	p_guide_id: int = -1, p_building_id: int = -1, p_keeper_task_name: String = "", p_keeper_task: Task = null,
	p_queue_order: int = -1
) -> void:
	target = null
	guide_id = p_guide_id
	building_id = p_building_id
	keeper_task_name = p_keeper_task_name
	keeper_task = p_keeper_task
	queue_order = p_queue_order
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_last_position = null
	_standing = false
	_planned_guide_cell = _NO_CELL
	_last_replan_msec = -PATH_REPLAN_MIN_INTERVAL_MSEC
	_update(individual)


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	var stamina_delta := 0.0
	if _last_position != null:
		stamina_delta = WalkAction.compute_walk_stamina_delta(individual, individual.position.distance_to(_last_position), "Follow")
	_last_position = individual.position
	_update(individual)
	return stamina_delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _dissolved


func on_complete(individual: Variant, context: Dictionary) -> void:
	_stand_still(individual)


func get_save_data() -> Dictionary:
	var data := {
		"guide_id": guide_id, "building_id": building_id, "keeper_task_name": keeper_task_name, "arrived": arrived,
		"queue_order": queue_order,
	}
	if slot != _NO_CELL:
		data["slot_x"] = slot.x
		data["slot_y"] = slot.y
	return data


func load_save_data(data: Dictionary) -> void:
	arrived = bool(data.get("arrived", false))
	if data.has("slot_x"):
		slot = Vector2i(int(data["slot_x"]), int(data["slot_y"]))


func _update(individual: HumanIndividual) -> void:
	if _dissolved:
		return
	var guide := _find_guide()
	if guide == null or not _resolve_keeper(guide):
		_dissolved = true
		_stand_still(individual)
		return
	var building := _find_building()
	if not arrived and building != null \
			and _absolute_position(guide).distance_to(InfluenceService.building_absolute_center(building)) <= ARRIVAL_DISTANCE:
		arrived = true
	if arrived and building != null:
		_go_to_slot(individual, guide, building)
	elif queue_order >= 0:
		_follow_in_line(individual, guide)
	else:
		_follow(individual, guide)


# Cammino in fila (vedi intestazione): bersaglio = punto della scia della guida al proprio posto.
func _follow_in_line(individual: HumanIndividual, guide: HumanIndividual) -> void:
	var line := _line_position()
	ProcessionService.record_trail(guide, LINE_FIRST_GAP + float(line["total"]) * LINE_SPACING + LINE_TRAIL_MARGIN)
	var guide_absolute := _absolute_position(guide)
	var my_absolute := _absolute_position(individual)
	var facing: Vector2 = guide.facing_direction.normalized() if guide.facing_direction.length() > 0.001 else Vector2.ZERO
	# Davanti alla guida: aspetta che passi, così non la attraversa né la supera.
	if facing != Vector2.ZERO and (my_absolute - guide_absolute).dot(facing) > LINE_AHEAD_MARGIN:
		if not _standing:
			_stand_still(individual)
		return
	var target_absolute := ProcessionService.point_behind(guide, LINE_FIRST_GAP + float(line["rank"]) * LINE_SPACING)
	var target_local := target_absolute - Vector2(individual.home_macro_coords.x * World.WIDTH, individual.home_macro_coords.y * World.HEIGHT)
	var distance := individual.position.distance_to(target_local)
	if distance <= LINE_ARRIVE or (_standing and distance <= LINE_RESUME):
		if not _standing:
			_stand_still(individual)
		return
	_standing = false
	_move_towards(individual, target_local)


# Posto in fila: {"rank": partecipanti attivi dello stesso corteo con queue_order minore, "total": partecipanti attivi
# in fila}. Stesso corteo = stessa guida e stesso nome della task che lo tiene vivo.
func _line_position() -> Dictionary:
	var rank := 0
	var total := 0
	for member in GameSettings.active_human_individuals:
		var other := member as HumanIndividual
		if other == null or other.current_task == null or other.current_task.is_finished():
			continue
		var action := other.current_task.get_current_action()
		if not (action is FollowIndividualAction):
			continue
		var follow := action as FollowIndividualAction
		if follow._dissolved or follow.queue_order < 0 or follow.guide_id != guide_id or follow.keeper_task_name != keeper_task_name:
			continue
		total += 1
		if follow != self and follow.queue_order < queue_order:
			rank += 1
	return {"rank": rank, "total": maxi(total, 1)}


# Verso `destination` (nel riferimento del partecipante) al passo normale: A* verso la sua microcella, ripianificato
# solo se la destinazione cambia microcella o il percorso è perso, al massimo ogni PATH_REPLAN_MIN_INTERVAL_MSEC, dopo un
# controllo di raggiungibilità (irraggiungibile: fermo); linea retta se è fuori dalla macrocella, adiacente o senza
# griglia. Stesso schema di _follow.
func _move_towards(individual: HumanIndividual, destination: Vector2) -> void:
	individual.is_moving = true
	var cell: LiveMacroCell = PathfindingService.get_live_cell(individual.home_macro_coords)
	var my_cell := Vector2i(individual.position.floor())
	var destination_cell := Vector2i(destination.floor())
	var adjacent: bool = maxi(absi(destination_cell.x - my_cell.x), absi(destination_cell.y - my_cell.y)) <= 1
	if cell == null or cell.path_grid == null or adjacent or not _in_macro(my_cell) or not _in_macro(destination_cell):
		_go_direct(individual, destination)
		return
	var path_lost: bool = individual.path_target != individual.target_position or (not individual.path_active and not individual.path_pending)
	var now_msec := Time.get_ticks_msec()
	if (destination_cell != _planned_guide_cell or path_lost) and now_msec - _last_replan_msec >= PATH_REPLAN_MIN_INTERVAL_MSEC:
		_last_replan_msec = now_msec
		if not PathfindingService.is_reachable(cell, my_cell, destination_cell):
			_planned_guide_cell = destination_cell
			wait_state = WAIT_GUIDE_UNREACHABLE
			_stand_still(individual)
			return
		wait_state = ""
		var destination_center := Vector2(destination_cell) + Vector2(0.5, 0.5)
		request_path(individual, destination_center)
		individual.target_position = destination_center
		_planned_guide_cell = destination_cell


# true se la task della guida che tiene vivo il corteo è ancora la sua task in corso.
func _resolve_keeper(guide: HumanIndividual) -> bool:
	var current := guide.current_task
	if current == null or current.is_finished():
		return false
	if keeper_task == null and current.task_name == keeper_task_name:
		keeper_task = current
	return current == keeper_task


func _follow(individual: HumanIndividual, guide: HumanIndividual) -> void:
	var guide_position := _guide_position_for(individual, guide)
	var distance := individual.position.distance_to(guide_position)
	if distance <= FOLLOW_DISTANCE or (_standing and distance <= FOLLOW_DISTANCE + RESUME_MARGIN):
		if not _standing:
			_stand_still(individual)
		return
	_standing = false
	individual.is_moving = true
	var cell: LiveMacroCell = PathfindingService.get_live_cell(individual.home_macro_coords)
	var my_cell := Vector2i(individual.position.floor())
	var guide_cell := Vector2i(guide_position.floor())
	var adjacent: bool = maxi(absi(guide_cell.x - my_cell.x), absi(guide_cell.y - my_cell.y)) <= 1
	if guide.home_macro_coords != individual.home_macro_coords or cell == null or cell.path_grid == null or adjacent \
			or not _in_macro(my_cell) or not _in_macro(guide_cell):
		_go_direct(individual, guide_position)
		return
	var path_lost: bool = individual.path_target != individual.target_position or (not individual.path_active and not individual.path_pending)
	var now_msec := Time.get_ticks_msec()
	if (guide_cell != _planned_guide_cell or path_lost) and now_msec - _last_replan_msec >= PATH_REPLAN_MIN_INTERVAL_MSEC:
		_last_replan_msec = now_msec
		if not PathfindingService.is_reachable(cell, my_cell, guide_cell):
			# Guida irraggiungibile da qui: si aspetta fermi, si riprova al prossimo cambio di microcella.
			_planned_guide_cell = guide_cell
			wait_state = WAIT_GUIDE_UNREACHABLE
			_stand_still(individual)
			return
		wait_state = ""
		var guide_cell_center := Vector2(guide_cell) + Vector2(0.5, 0.5)
		request_path(individual, guide_cell_center)
		individual.target_position = guide_cell_center
		_planned_guide_cell = guide_cell


func _go_to_slot(individual: HumanIndividual, guide: HumanIndividual, building: Building) -> void:
	var building_macro := Vector2i(building.macro_x, building.macro_y)
	if slot == _NO_CELL:
		slot = _pick_slot(individual, guide, building)
		if slot == Vector2i(building.micro_x, building.micro_y):
			wait_state = WAIT_NO_FREE_SLOT
	var macro_offset := Vector2(building_macro - individual.home_macro_coords) * World.WIDTH
	var point := Vector2(slot) + Vector2(0.5, 0.5) + macro_offset
	if individual.position.distance_to(point) <= SLOT_ARRIVAL_TOLERANCE:
		reached_slot = true
		if not _standing:
			_stand_still(individual)
		return
	if _slot_unreachable:
		return
	if is_path_unreachable(individual, point):
		# Posto irraggiungibile: resta dov'è, senza ritentare a ogni frame.
		_slot_unreachable = true
		wait_state = WAIT_NO_FREE_SLOT
		_stand_still(individual)
		return
	_standing = false
	if individual.target_position != point or (not individual.path_active and not individual.path_pending and not individual.is_moving):
		individual.target_position = point
		individual.is_moving = true
		request_path(individual, point)


# Microcella libera più vicina al partecipante negli anelli attorno all'edificio: non bloccata, non quella dell'edificio
# né quella della guida, non già scelta da un altro partecipante con lo stesso edificio. Nessuna: la microcella
# dell'edificio stessa (caso limite, edificio tutto circondato).
func _pick_slot(individual: HumanIndividual, guide: HumanIndividual, building: Building) -> Vector2i:
	var building_macro := Vector2i(building.macro_x, building.macro_y)
	var building_cell := Vector2i(building.micro_x, building.micro_y)
	var cell: LiveMacroCell = PathfindingService.get_live_cell(building_macro)
	var has_grid := cell != null and cell.path_grid != null
	var taken := _taken_slots()
	var guide_absolute := _absolute_position(guide).floor()
	var guide_cell := Vector2i(guide_absolute) - building_macro * World.WIDTH
	var macro_offset := Vector2(building_macro - individual.home_macro_coords) * World.WIDTH
	for ring in range(1, SLOT_MAX_RING + 1):
		var best := _NO_CELL
		var best_distance := INF
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var candidate := building_cell + Vector2i(dx, dy)
				if not _in_macro(candidate) or candidate == guide_cell or taken.has(candidate):
					continue
				if has_grid and PathfindingService.is_blocked(cell, candidate):
					continue
				var distance := (Vector2(candidate) + Vector2(0.5, 0.5) + macro_offset).distance_to(individual.position)
				if distance < best_distance:
					best_distance = distance
					best = candidate
		if best != _NO_CELL:
			return best
	return building_cell


# Posti già scelti da altri partecipanti diretti allo stesso edificio (corteo in corso).
func _taken_slots() -> Dictionary:
	var taken: Dictionary = {}
	for member in GameSettings.active_human_individuals:
		var other := member as HumanIndividual
		if other == null or other.current_task == null or other.current_task.is_finished():
			continue
		var action := other.current_task.get_current_action()
		if action is FollowIndividualAction and action != self:
			var follow := action as FollowIndividualAction
			if follow.building_id == building_id and follow.slot != _NO_CELL:
				taken[follow.slot] = true
	return taken


func _find_guide() -> HumanIndividual:
	for member in GameSettings.active_human_individuals:
		var individual := member as HumanIndividual
		if individual != null and individual.id == guide_id:
			return individual
	return null


func _find_building() -> Building:
	var world: World = GameSettings.active_world
	if world == null or building_id == -1:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null


func _go_direct(individual: HumanIndividual, destination: Vector2) -> void:
	if individual.path_active or individual.path_pending:
		individual.clear_path()
	_planned_guide_cell = _NO_CELL
	individual.target_position = destination
	individual.is_moving = true


func _stand_still(individual: Variant) -> void:
	individual.clear_path()
	individual.target_position = individual.position
	individual.is_moving = false
	_standing = true


static func _guide_position_for(individual: HumanIndividual, guide: HumanIndividual) -> Vector2:
	return guide.position + Vector2(guide.home_macro_coords - individual.home_macro_coords) * World.WIDTH


static func _absolute_position(individual: HumanIndividual) -> Vector2:
	return Vector2(individual.home_macro_coords.x * World.WIDTH, individual.home_macro_coords.y * World.HEIGHT) + individual.position


static func _in_macro(microcell: Vector2i) -> bool:
	return microcell.x >= 0 and microcell.y >= 0 and microcell.x < World.WIDTH and microcell.y < World.HEIGHT
