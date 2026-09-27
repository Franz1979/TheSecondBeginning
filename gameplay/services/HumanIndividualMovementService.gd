class_name HumanIndividualMovementService
extends RefCounted

# Servizio single-responsibility (stesso pattern di FirstStartMacroCellSelectionService/
# CellRichnessCalculator): muove un HumanIndividual verso il suo target_position a move_speed (microcelle per giorno di
# gioco), in linea retta tra un punto e l'altro. Girato ogni frame da GameScene._process.
#
# `live_cells` (2026-09-19, richiesta utente — modificatori di movimento del terreno): opzionale, default
# {} = nessun modificatore (tutte le microcelle 1.0). La velocità usa il terreno della microcella di
# PARTENZA del passo; alla fine il memo viene aggiornato sulla microcella di ARRIVO, così
# WalkAction/RunAction.get_stamina_delta (chiamate subito dopo, nello stesso frame, da apply_action)
# leggono il moltiplicatore di stamina della microcella in cui l'individuo si trova ora — vedi
# MovementTerrainService. move_speed_multiplier: 1.0 per default/WalkAction, raddoppiato da RunAction.
#
# All'arrivo NON si chiama individual.stop() (2026-09-07): la decisione "fermarsi per davvero" spetta a
# HumanIndividualActionService.apply_action, che vede lo step completo e passa al successivo; fino ad allora is_moving
# resta true con position == target_position, senza effetti. facing_direction si aggiorna solo sopra una soglia minima
# di distanza (normalized() su un vettore quasi nullo è instabile) e non viene mai azzerata.
#
# Pathfinding (2026-09-27, step 2): quando un WalkAction parte (individual.path_pending) il percorso viene calcolato
# qui con PathfindingService.find_path sulla griglia della macrocella dell'individuo e salvato in individual.path
# (waypoint = centri di microcella); il movimento li segue uno alla volta e l'ultimo tratto va alla posizione esatta
# di target_position. Se sulla macrocella cambia un blocco (LiveMacroCell.path_block_version) il percorso si ricalcola
# dal punto in cui si è. Destinazione irraggiungibile -> individual.path_failed (WalkAction chiude la Task).
# Nessun percorso (linea retta come prima) se la cella non è viva o non ha griglia, se partenza o destinazione sono
# fuori dalla macrocella (il passaggio di cella resta quello di sempre: dopo l'attraversamento WalkAction riparte e
# il percorso si calcola nella nuova cella), o per le azioni che non sono WalkAction (RunAction, ApproachPreyAction...).


func advance_movement(individual: HumanIndividual, delta: float, live_cells: Dictionary = {}) -> void:
	if not individual.is_moving:
		return
	_update_path(individual, live_cells)
	if individual.path_failed:
		individual.is_moving = false
		return
	MovementTerrainService.update_individual(individual, live_cells)

	# Punti intermedi: si passa al successivo entro PathfindingService.WAYPOINT_REACH_DISTANCE (2026-09-27, lisciatura);
	# la destinazione finale (target_position) resta esatta.
	while individual.path_active and not individual.path.is_empty() 			and individual.position.distance_to(individual.path[0]) <= PathfindingService.WAYPOINT_REACH_DISTANCE:
		individual.path.pop_front()
	var goal: Vector2 = individual.target_position
	var following_waypoint := individual.path_active and not individual.path.is_empty()
	if following_waypoint:
		goal = individual.path[0]
	var to_goal := goal - individual.position
	var distance := to_goal.length()
	var step := individual.move_speed * individual.move_speed_multiplier * individual.terrain_speed_multiplier * delta

	if distance > 0.01:
		individual.facing_direction = to_goal.normalized()

	if step >= distance:
		individual.position = goal
		if following_waypoint:
			individual.path.pop_front()
	else:
		individual.position += to_goal.normalized() * step
	MovementTerrainService.update_individual(individual, live_cells)


# Calcola il percorso se richiesto o se i blocchi della macrocella sono cambiati; lo invalida se un'altra azione ha
# cambiato bersaglio.
func _update_path(individual: HumanIndividual, live_cells: Dictionary) -> void:
	if individual.path_active and individual.path_target != individual.target_position:
		individual.path.clear()
		individual.path_active = false
	if not individual.path_pending and not individual.path_active:
		return
	var cell: LiveMacroCell = live_cells.get(individual.home_macro_coords)
	if individual.path_active and cell != null and cell.path_block_version != individual.path_block_version:
		individual.path_pending = true
	if not individual.path_pending:
		return
	individual.path_pending = false
	individual.path.clear()
	individual.path_active = false
	var from := Vector2i(floori(individual.position.x), floori(individual.position.y))
	var to := Vector2i(floori(individual.path_target.x), floori(individual.path_target.y))
	if cell == null or cell.path_grid == null:
		return
	if not PathfindingService._in_bounds(from) or not PathfindingService._in_bounds(to):
		return
	individual.path_block_version = cell.path_block_version
	if from == to:
		individual.path_active = true
		return
	var cells := PathfindingService.find_path(cell, from, to)
	if cells.is_empty():
		individual.path_failed = true
		if DebugLogging.ENABLED and DebugLogging.SHOW_PATHFINDING_LOGS:
			print("[PATHFINDING] #%d %s: destinazione %s irraggiungibile da %s nella macrocella %s — Task '%s' chiusa." % [
				individual.id, individual.name, to, from, individual.home_macro_coords,
				individual.current_task.task_name if individual.current_task != null else "?"
			])
		return
	# Waypoint: i centri delle microcelle intermedie (né quella di partenza né quella d'arrivo); l'ultimo tratto va
	# dritto alla posizione esatta di target_position.
	for i in range(1, cells.size() - 1):
		individual.path.append(Vector2(cells[i]) + Vector2(0.5, 0.5))
	individual.path_active = true

