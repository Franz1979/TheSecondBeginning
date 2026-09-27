class_name ApproachPreyAction
extends Action

# Avvicinamento a una preda in movimento (2026-09-26, richiesta utente — caccia, step 2: primo step
# della Hunt Task, vedi hunt.tres). Azione SEPARATA da WalkAction (non una sottoclasse) perché il suo
# bersaglio non è una posizione fissa: WalkAction ha un `target` Vector2 persistito, spostato da
# Task.rebase_positional_targets agli attraversamenti di bordo e riconosciuto da vari controlli
# `is WalkAction` (persistenza, ripresa dalla coda, bordo per le task perditempo) che qui non devono
# scattare. Condivide con WalkAction solo il costo di stamina per microcella (WalkAction.
# compute_walk_stamina_delta, stessa formula).
#
# Bersaglio: l'individuo animale con id `prey_id`, ritrovato a ogni tick nel registro dei vivi
# (AnimalGroupRenderer.find_live_individual). `target` resta null. A ogni tick (get_stamina_delta,
# chiamata da apply_action ogni frame subito dopo il movimento) la destinazione dell'individuo
# (individual.target_position) viene riportata sulla posizione ATTUALE della preda, convertita nel
# sistema di coordinate dell'individuo con lo stesso scarto di macrocella usato per gli edifici — il
# movimento resta quello di sempre (HumanIndividualMovementService), con un frame di ritardo invisibile.
#
# Arrivo: non "sono sul posto" ma "sono entro la gittata dell'arma in cintura" — la max_range più alta
# tra gli attrezzi che coprono HUNTING (ToolGateService.get_belt_max_range_for), con un minimo di
# MELEE_REACH per le armi da corpo a corpo (gittata 0) — moltiplicata per HuntService.APPROACH_REACH_FRACTION
# (2026-09-26) per lasciare un margine al movimento della preda durante la mira.
#
# Senza arma (required_tool_categories = HUNTING, stesso gate della produzione): l'individuo resta
# fermo e lo step in attesa (Action.ensure_required_tools), riparte da solo quando l'arma arriva nello
# zaino.
#
# Preda sparita (morta, rimossa dalla riconciliazione con la popolazione, cella disattivata): lo step
# si considera concluso; lo step successivo (AimAction) ha lo stesso bersaglio, quindi il controllo
# di validità all'attivazione (HumanIndividualActionService.finish_current_step) chiude la Task.

# Distanza minima di colpo per un'arma da corpo a corpo (max_range 0), in microcelle — circa il
# contatto (un umano adulto misura ~0.22 microcelle).
const MELEE_REACH: float = 0.5

var prey_id: int = 0
var prey_species: String = ""
# Macrocella della preda, aggiornata a ogni tick in cui la preda viene ritrovata. Salvata: al
# caricamento GameScene attiva questa cella PRIMA del primo tick (_activate_hunt_prey_cells), così la
# preda ricostruita dal salvataggio è già nel registro quando la caccia riprende.
var prey_macro_coords: Vector2i = Vector2i.ZERO

var _last_position: Variant = null
var _prey_lost: bool = false
# Perché la preda è stata persa (CombatTarget.Status: GONE o OUT_OF_SIGHT), per il log di fine avvicinamento.
var _prey_loss_status: int = 0 # = CombatTarget.Status.OK (letterale: evita un riferimento circolare nell'inizializzazione)
var _in_range: bool = false
# Solo per il log di debug della caccia (DebugLogging.SHOW_HUNT_LOGS), mai salvati: ultima distanza
# dalla preda e gittata usata, giorni di gioco dall'ultima riga di avvicinamento, stato di attesa
# attrezzi del tick precedente (per loggare solo inizio e fine dell'attesa).
var _last_distance: float = -1.0
var _last_reach: float = 0.0
var _log_elapsed_days: float = 0.0
var _was_waiting_for_tools: bool = false


# Pathfinding (2026-09-27, step 3): con la preda nella stessa macrocella e a più di una microcella di distanza, si segue
# un percorso verso la MICROCELLA della preda (target_position = centro di quella microcella, così il percorso resta
# valido finché la preda non cambia cella). Ricalcolo solo quando la preda cambia microcella (i cambi di blocco li
# gestisce già HumanIndividualMovementService), al più ogni PATH_REPLAN_MIN_INTERVAL_MSEC per cacciatore. Preda nella
# stessa microcella o in una adiacente: tratto diretto sulla posizione esatta, come prima. Preda in un'altra macrocella
# o cella senza griglia: linea retta come prima. Preda irraggiungibile (PathfindingService.is_reachable): la caccia si
# chiude (quarta uscita pulita, dopo preda sparita, fuori vista e tetto dei riavvicinamenti).
const PATH_REPLAN_MIN_INTERVAL_MSEC: int = 250
const _NO_CELL := Vector2i(-99999, -99999)
var _prey_unreachable: bool = false
var _planned_prey_cell: Vector2i = _NO_CELL
var _last_replan_msec: int = -PATH_REPLAN_MIN_INTERVAL_MSEC


func _init(p_prey_id: int = 0, p_prey_species: String = "", p_prey_macro_coords: Vector2i = Vector2i.ZERO) -> void:
	target = null
	prey_id = p_prey_id
	prey_species = p_prey_species
	prey_macro_coords = p_prey_macro_coords
	required_tool_categories = [TaskTypes.ToolCategory.HUNTING]
	# Caccia vietata a neonati, bambini e adolescenti (2026-09-26, richiesta utente — la produzione resta
	# permessa agli adolescenti). Stesse fasce di AimAction/ThrowAction per la caccia.
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD, HumanTypes.AgeBand.TEENAGER]


# Preda esistente E in vista (2026-09-26, preda persa di vista): stesso criterio del bersaglio di
# AimAction/ThrowAction (CombatTarget.get_status).
func is_target_valid() -> bool:
	return get_prey_status(prey_id) == CombatTarget.Status.OK


# Stato (CombatTarget.Status) della preda animale con questo id: sparita, persa di vista o valida.
static func get_prey_status(target_prey_id: int) -> int:
	return CombatTarget.for_animal(target_prey_id, "", Vector2i.ZERO).get_status()


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_last_position = null
	_prey_lost = false
	_prey_loss_status = CombatTarget.Status.OK
	_in_range = false
	_prey_unreachable = false
	individual.clear_path()
	_planned_prey_cell = _NO_CELL
	_last_replan_msec = -PATH_REPLAN_MIN_INTERVAL_MSEC
	_log_elapsed_days = 0.0
	_was_waiting_for_tools = false
	_update_pursuit(individual, context)
	if HuntService.is_logging() and not _prey_lost and not _in_range and not _was_waiting_for_tools:
		HuntService.log_event(individual, "avvicinamento iniziato: preda %s #%d a %.2f microcelle, soglia di arrivo %.2f (gittata × APPROACH_REACH_FRACTION)." % [
			prey_species, prey_id, _last_distance, _last_reach
		])


# Costo del tratto percorso nell'ultimo frame (stesso schema di WalkAction._last_position), poi
# aggiornamento dell'inseguimento per il frame successivo.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	var stamina_delta := 0.0
	if _last_position != null:
		var distance: float = individual.position.distance_to(_last_position)
		stamina_delta = WalkAction.compute_walk_stamina_delta(individual, distance, "ApproachPrey")
	_last_position = individual.position
	_update_pursuit(individual, context)
	_log_approach_progress(individual, delta)
	return stamina_delta


# Riga periodica di avvicinamento (DebugLogging.SHOW_HUNT_LOGS): ogni HUNT_APPROACH_LOG_INTERVAL_DAYS di
# gioco, solo mentre l'individuo sta davvero inseguendo (non in attesa attrezzi, non già arrivato).
func _log_approach_progress(individual: Variant, delta: float) -> void:
	if not HuntService.is_logging() or _prey_lost or _in_range or _was_waiting_for_tools:
		return
	_log_elapsed_days += delta
	if _log_elapsed_days < DebugLogging.HUNT_APPROACH_LOG_INTERVAL_DAYS:
		return
	_log_elapsed_days = 0.0
	HuntService.log_event(individual, "avvicinamento a %s #%d: distanza %.2f microcelle, soglia di arrivo %.2f (gittata × APPROACH_REACH_FRACTION)." % [
		prey_species, prey_id, _last_distance, _last_reach
	])


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _prey_lost or _in_range or _prey_unreachable


func on_complete(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_STAMINA_LOGS:
		MovementStaminaDebugLog.flush(individual)
	# Quarta uscita pulita (2026-09-27, pathfinding step 3): preda irraggiungibile, la caccia si chiude.
	if _prey_unreachable:
		HuntService.log_event(individual, "avvicinamento finito: preda %s #%d irraggiungibile (nessun percorso a piedi) — la caccia si chiude." % [
			prey_species, prey_id
		])
		abort_task_unreachable(individual, context, "preda %s #%d irraggiungibile" % [prey_species, prey_id])
		return
	if _prey_lost:
		HuntService.log_event(individual, "avvicinamento finito: %s #%d — %s — la caccia verrà chiusa." % [
			prey_species, prey_id, CombatTarget.describe_status(_prey_loss_status)
		])
	else:
		HuntService.log_event(individual, "avvicinamento finito: preda %s #%d entro il margine di tiro (distanza %.2f <= %.2f, gittata × APPROACH_REACH_FRACTION)." % [
			prey_species, prey_id, _last_distance, _last_reach
		])


# Ricalcola destinazione e stato dell'inseguimento. Fermo (is_moving false) se la preda è sparita o
# non è più in vista (2026-09-26: niente inseguimento di un animale che non si vede — lo step si chiude e,
# con lui, la caccia), se manca l'arma o se è già entro la gittata; altrimenti in cammino verso la
# posizione attuale della preda.
func _update_pursuit(individual: Variant, context: Dictionary) -> void:
	var status := get_prey_status(prey_id)
	if status != CombatTarget.Status.OK:
		_prey_lost = true
		_prey_loss_status = status
		_stand_still(individual)
		return
	var prey := AnimalGroupRenderer.find_live_individual(prey_id)
	prey_macro_coords = prey.macro_coords
	var prey_position := prey_position_for(individual, prey)
	_last_distance = individual.position.distance_to(prey_position)
	var has_tools := ensure_required_tools(individual)
	_log_tool_wait_transition(individual, not has_tools)
	if not has_tools:
		_in_range = false
		_stand_still(individual)
		return
	# Ci si ferma a una frazione della gittata (HuntService.APPROACH_REACH_FRACTION), non al limite: margine per
	# il movimento della preda durante la mira.
	# Gittata dell'arma della caccia (2026-09-27): scelta una volta e salvata nel context (HuntService.resolve_weapon),
	# la SUA max_range, non la massima della cintura.
	var weapon_name := HuntService.resolve_weapon(individual, context, TaskTypes.ToolCategory.HUNTING, prey_species, int(prey.age_band))
	var reach := HuntService.compute_weapon_reach(weapon_name) * HuntService.APPROACH_REACH_FRACTION
	_last_reach = reach
	if _last_distance <= reach:
		_in_range = true
		_stand_still(individual)
		return
	_in_range = false
	_follow_prey(individual, prey, prey_position)


# Movimento verso la preda (2026-09-27, pathfinding step 3 — vedi le costanti in testa): percorso verso la sua
# microcella, oppure tratto diretto sulla posizione esatta.
func _follow_prey(individual: Variant, prey: AnimalVisualGroup, prey_position: Vector2) -> void:
	individual.is_moving = true
	var cell: LiveMacroCell = PathfindingService.get_live_cell(individual.home_macro_coords)
	var my_cell := Vector2i(individual.position.floor())
	var prey_cell := Vector2i(prey_position.floor())
	var same_macro: bool = prey.macro_coords == individual.home_macro_coords
	var adjacent: bool = maxi(absi(prey_cell.x - my_cell.x), absi(prey_cell.y - my_cell.y)) <= 1
	if not same_macro or cell == null or cell.path_grid == null or adjacent 			or not PathfindingService._in_bounds(my_cell) or not PathfindingService._in_bounds(prey_cell):
		_go_direct(individual, prey_position)
		return
	var prey_cell_center := Vector2(prey_cell) + Vector2(0.5, 0.5)
	# Il servizio di movimento non ha trovato un percorso verso la microcella pianificata: irraggiungibile.
	if is_path_unreachable(individual, individual.path_target) and _planned_prey_cell != _NO_CELL:
		_prey_unreachable = true
		_stand_still(individual)
		return
	var path_lost: bool = individual.path_target != individual.target_position or (not individual.path_active and not individual.path_pending)
	var now_msec := Time.get_ticks_msec()
	var may_replan: bool = now_msec - _last_replan_msec >= PATH_REPLAN_MIN_INTERVAL_MSEC
	if (prey_cell != _planned_prey_cell or path_lost) and may_replan:
		if not PathfindingService.is_reachable(cell, my_cell, prey_cell):
			_prey_unreachable = true
			_stand_still(individual)
			return
		request_path(individual, prey_cell_center)
		individual.target_position = prey_cell_center
		_planned_prey_cell = prey_cell
		_last_replan_msec = now_msec
	elif _planned_prey_cell == _NO_CELL:
		# Nessun percorso ancora pianificato (ricalcolo rimandato dal tetto di frequenza): per ora dritto.
		individual.target_position = prey_position


# Tratto diretto sulla posizione esatta della preda (come prima del pathfinding): nessun percorso da seguire.
func _go_direct(individual: Variant, prey_position: Vector2) -> void:
	if individual.path_active or individual.path_pending:
		individual.clear_path()
	_planned_prey_cell = _NO_CELL
	individual.target_position = prey_position
	individual.is_moving = true


# Log di inizio/fine attesa attrezzi (DebugLogging.SHOW_HUNT_LOGS): una riga quando l'attesa comincia,
# con il motivo (stato tool_wait_* di Action), e una quando finisce. Aggiorna comunque lo stato, anche
# a log spento, così accendere il flag a metà partita non produce una falsa riga di "fine attesa".
func _log_tool_wait_transition(individual: Variant, is_waiting: bool) -> void:
	if is_waiting == _was_waiting_for_tools:
		return
	_was_waiting_for_tools = is_waiting
	if not HuntService.is_logging():
		return
	if not is_waiting:
		HuntService.log_event(individual, "attesa attrezzi finita: %s — l'avvicinamento riparte." % HuntService.describe_weapon(individual))
		return
	var reason := ""
	match tool_wait_result:
		ToolGateService.Result.MISSING_TOOLS:
			reason = "manca un attrezzo per le categorie %s (né in cintura né nello zaino)" % str(tool_wait_missing_categories.map(
				func(category: int) -> String: return String(TaskTypes.ToolCategory.keys()[category])
			))
		ToolGateService.Result.BELT_FULL:
			reason = "%s è nello zaino ma la cintura è piena" % tool_wait_tool_name
		ToolGateService.Result.CANNOT_EQUIP:
			reason = "%s è nello zaino ma lo zaino è troppo pieno per spostarlo in cintura" % tool_wait_tool_name
	HuntService.log_event(individual, "in attesa di attrezzi (preda %s #%d): %s." % [prey_species, prey_id, reason])




# Posizione della preda nel sistema di coordinate dell'individuo (stesso scarto di macrocella usato per
# gli edifici). Statica.
static func prey_position_for(individual: Variant, prey: AnimalVisualGroup) -> Vector2:
	var macro_offset: Vector2 = Vector2(prey.macro_coords - individual.home_macro_coords) * World.WIDTH
	return prey.position + macro_offset


func _stand_still(individual: Variant) -> void:
	individual.clear_path()
	individual.target_position = individual.position
	individual.is_moving = false


# Persistenza: id e specie della preda (identità, letti da TaskPersistenceService come argomenti di
# _init) più la macrocella, necessaria a GameScene per riattivarla prima del primo tick dopo un load.
func get_save_data() -> Dictionary:
	return {
		"prey_id": prey_id,
		"prey_species": prey_species,
		"prey_macro_x": prey_macro_coords.x,
		"prey_macro_y": prey_macro_coords.y,
	}
