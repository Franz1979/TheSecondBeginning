class_name IndividualBorderService
extends RefCounted

# Passaggio di un individuo da una macrocella all'altra e figlio al seguito (2026-10-18, refactoring GameScene blocco
# 5b — prima _check_macro_cell_border_crossing / _attempt_macro_cell_transition / _block_border_crossing /
# _sync_dependent_child_position in GameScene). Solo il modello: posizione, macrocella, Task ribasate, avanzamento dello
# step. Viste, celle vive, telecamera e LOD li fa la scena dall'effetto GameEffects.individual_moved. Senza stato.

# Margine dal bordo quando l'individuo viene fermato lì (stesso valore di GameScene.BORDER_CLAMP_EPSILON di prima).
const BORDER_CLAMP_EPSILON: float = 0.01


# Controllo dell'uscita dalla griglia micro, per OGNI individuo attivo (non solo quello seguito: un individuo qualunque
# può avere un bersaglio nella macrocella vicina). Un asse alla volta: un'uscita diagonale diventa due passaggi
# 4-connessi consecutivi (es. prima est, poi nord), mai un vicino diagonale. Il passaggio avviene esattamente al bordo vero
# (0/WIDTH): il vicino è già caricato prima che ci si arrivi (_update_live_neighbor della scena), quindi è invisibile.
# `focus` = individuo seguito dalla telecamera (per lui si aggiorna anche game_data.player_macro_cell_*).
static func check_crossing(
	member: HumanIndividual, world: World, game_data: GameData, action_service: HumanIndividualActionService,
	focus: HumanIndividual, effects: GameEffects
) -> void:
	if world == null:
		return
	if member.position.x < 0.0:
		_attempt_transition(member, -1, 0, world, game_data, action_service, focus, effects)
	elif member.position.x >= float(World.WIDTH):
		_attempt_transition(member, 1, 0, world, game_data, action_service, focus, effects)
	if member.position.y < 0.0:
		_attempt_transition(member, 0, -1, world, game_data, action_service, focus, effects)
	elif member.position.y >= float(World.HEIGHT):
		_attempt_transition(member, 0, 1, world, game_data, action_service, focus, effects)


# Tentativo di uscita in direzione (dx, dy), un asse solo. Macrocella vicina inesistente (bordo del mondo) o microcella di
# ingresso in acqua: l'individuo resta al bordo (_block_crossing). Altrimenti il passaggio si conferma subito.
#
# I bersagli posizionali delle Task (corrente e in coda) sono coordinate locali della macrocella di partenza: si
# ribasano di quanto cambia il riferimento, così la destinazione assoluta resta la stessa. Lo step in corso, se ha un
# bersaglio Vector2, viene riattivato per richiedere un percorso nuovo nel nuovo riferimento (il percorso si calcola al
# prossimo avanzamento del movimento, quando la cella è già viva). Le Task NON vengono cancellate: si interrompe solo il
# tragitto vecchio.
static func _attempt_transition(
	member: HumanIndividual, dx: int, dy: int, world: World, game_data: GameData,
	action_service: HumanIndividualActionService, focus: HumanIndividual, effects: GameEffects
) -> void:
	var origin_macro_coords := member.home_macro_coords
	var target_x := origin_macro_coords.x + dx
	var target_y := origin_macro_coords.y + dy
	var target_cell := world.get_cell_at(target_x, target_y)
	if target_cell == null:
		_block_crossing(member, dx, dy, world, game_data, action_service)
		return

	var entry_position := member.position
	if dx == 1:
		entry_position.x -= float(World.WIDTH)
	elif dx == -1:
		entry_position.x += float(World.WIDTH)
	if dy == 1:
		entry_position.y -= float(World.HEIGHT)
	elif dy == -1:
		entry_position.y += float(World.HEIGHT)

	# Terreno micro uniforme: acqua se la macrocella è mare/lago, o se l'ingresso cade sulla fascia di un fiume.
	if RiverMicrocellService.is_water_microcell(world, target_cell, Vector2i(int(entry_position.x), int(entry_position.y))):
		_block_crossing(member, dx, dy, world, game_data, action_service)
		return

	var frame_offset := entry_position - member.position
	var current_action: Action = null
	if member.current_task != null:
		current_action = member.current_task.get_current_action()
		var rebased_current := member.current_task.rebase_positional_targets(frame_offset)
		if rebased_current > 0 and DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
			print("[BORDER] Individuo #%d %s: ribasati %d step posizionali di current_task '%s' (offset=%s)." % [
				member.id, member.name, rebased_current, member.current_task.task_name, str(frame_offset)
			])
	for queued_task in member.task_queue:
		var rebased_queued := queued_task.rebase_positional_targets(frame_offset)
		if rebased_queued > 0 and DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
			print("[BORDER] Individuo #%d %s: ribasati %d step posizionali di una task in coda '%s' (offset=%s)." % [
				member.id, member.name, rebased_queued, queued_task.task_name, str(frame_offset)
			])

	var target_macro_coords := Vector2i(target_x, target_y)
	var is_focus := member == focus
	if is_focus:
		game_data.player_macro_cell_x = target_x
		game_data.player_macro_cell_y = target_y

	if DebugLogging.ENABLED and DebugLogging.SHOW_FOW_DIAG_LOGS:
		print("[FOW DIAG] passaggio di macrocella: individuo #%d %s attraversa %s -> %s (dx=%d dy=%d). PRIMA: position=%s" % [
			member.id, member.name, str(origin_macro_coords), str(target_macro_coords), dx, dy, str(member.position)
		])
	member.position = entry_position
	member.home_macro_coords = target_macro_coords

	if current_action != null and current_action.target is Vector2:
		current_action.activate(member, member.current_task.context)
	effects.individual_moved(member, target_macro_coords, Vector2i(dx, dy), is_focus, false)


# Ferma l'individuo esattamente al bordo della macrocella attuale sull'asse (dx, dy): bordo del mondo o acqua. Non cancella
# la Task, solo il tragitto (is_moving / path). Se la Task è un'attività idle e lo step è una camminata, la gamba si
# considera conclusa e si passa allo step successivo; per le altre Task il bersaglio irraggiungibile resta un limite noto
# (non esiste ancora un "fallimento della Task" per bersaglio irraggiungibile).
static func _block_crossing(
	member: HumanIndividual, dx: int, dy: int, world: World, game_data: GameData,
	action_service: HumanIndividualActionService
) -> void:
	if dx == 1:
		member.position.x = float(World.WIDTH) - BORDER_CLAMP_EPSILON
	elif dx == -1:
		member.position.x = 0.0
	if dy == 1:
		member.position.y = float(World.HEIGHT) - BORDER_CLAMP_EPSILON
	elif dy == -1:
		member.position.y = 0.0
	member.is_moving = false
	member.path.clear()

	var blocked_task := member.current_task
	var is_idle_task := blocked_task != null and blocked_task.is_idle_activity
	if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
		print("[BORDER] Individuo #%d %s: movimento bloccato al bordo (dx=%d dy=%d — macrocella inesistente o ingresso in acqua) — task=%s is_idle_activity=%s." % [
			member.id, member.name, dx, dy,
			("'%s'" % blocked_task.task_name if blocked_task != null else "(nessuna)"), str(is_idle_task)
		])
	if not is_idle_task:
		return
	var blocked_action := blocked_task.get_current_action()
	if not (blocked_action is WalkAction or blocked_action is RunAction):
		return
	if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
		print("[BORDER] Individuo #%d %s: gamba di '%s' (task perditempo) considerata conclusa — avanzo allo step successivo." % [
			member.id, member.name, blocked_task.task_name
		])
	action_service.finish_current_step(member, blocked_task, world, game_data)


# Figlio a carico di `mother` (trasporto dei neonati): posizione accanto alla madre e, se lei ha cambiato macrocella,
# stessa macrocella (vista spostata dalla scena con l'effetto individual_moved, solo se la cella è viva). Fa da sé la
# manutenzione del campo: dependent_child_id torna a -1 se il figlio non c'è più o non è più un neonato. Chiamata dopo
# check_crossing per lo stesso individuo, così il figlio segue la madre nello stesso fotogramma.
static func sync_dependent_child(mother: HumanIndividual, individuals: Array, game_data: GameData, effects: GameEffects) -> void:
	if mother.dependent_child_id == -1:
		return
	var child: HumanIndividual = null
	for candidate in individuals:
		if candidate.id == mother.dependent_child_id:
			child = candidate
			break
	if child == null:
		mother.dependent_child_id = -1
		return
	if GameContext.age_band_for(child, game_data) != HumanTypes.AgeBand.INFANT:
		mother.dependent_child_id = -1
		return
	child.position = mother.position + mother.facing_direction.orthogonal() * HumanBirthIndividualService.DEPENDENT_CHILD_SIDE_OFFSET
	if child.home_macro_coords != mother.home_macro_coords:
		child.home_macro_coords = mother.home_macro_coords
		effects.individual_moved(child, mother.home_macro_coords, Vector2i.ZERO, false, true)
