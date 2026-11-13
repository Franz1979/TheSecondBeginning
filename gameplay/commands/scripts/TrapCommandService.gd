class_name TrapCommandService
extends RefCounted

# Piazzamento manuale delle trappole col clic destro (2026-11-07, richiesta utente — scheda "Trappole" del popup del clic
# destro, passo 1): il pipottino selezionato va a prendere la trappola nell'edificio più vicino e la monta sulla microcella
# cliccata (stessa Task del lavoro di zona, TrapJobProvider.build_place_task, segnata come manuale). Se la microcella sta in
# una zona col lavoro della trappola acceso, conta per il suo numero voluto. Rifiuto con X e motivo. Senza stato.


# `trap_name` sulla microcella `lot` di `macro_coords`, ricontrollata adesso (TrapService.placeable_traps).
static func assign_place(ctx: GameContext, worker: HumanIndividual, trap_name: String, macro_coords: Vector2i, lot: Vector2i, effects: GameEffects) -> void:
	if worker == null:
		return
	var placeable := false
	var blocked_reason := ""
	for option in TrapService.placeable_traps(ctx.game_data, ctx.world, ctx.individuals, macro_coords, lot):
		if String(option["trap_name"]) == trap_name:
			placeable = true
			blocked_reason = String(option.get("blocked_reason", ""))
			break
	if not placeable:
		_reject(worker, macro_coords, lot, GameContext.tr_text("trap_place_reject_unavailable"), effects)
		return
	# Vincolo di piazzamento (2026-11-12, cesto a caduta senza tettoia delle gabbie): X e motivo.
	if blocked_reason != "":
		_reject(worker, macro_coords, lot, blocked_reason, effects)
		return
	if not worker.can_carry_one_unit_when_empty(trap_name):
		_reject(worker, macro_coords, lot, HumanIndividualActionService.no_room_message(worker, [trap_name] as Array[String]), effects)
		return
	var area_id := TrapService.area_for_lot(ctx.game_data, macro_coords, lot, trap_name)
	var task := TrapJobProvider.build_place_task(ctx, worker, trap_name, macro_coords, lot, area_id, true)
	if task == null:
		_reject(worker, macro_coords, lot, GameContext.tr_text("trap_place_reject_unavailable"), effects)
		return
	var request := AssignRequest.create(worker, task, "task_activity_place_trap", false).at_microcell(macro_coords, lot, "trap")
	AssignService.assign(request, ctx.age_band_of(worker), effects)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Svuotamento a mano (2026-11-07, sorgente "Trappola" in Raccogli): stessa Task del lavoro di svuotamento, che risulta
# così preso. Rifiutato se la trappola non c'è più, è vuota o qualcun altro la sta già svuotando.
static func assign_empty(ctx: GameContext, worker: HumanIndividual, trap_id: int, effects: GameEffects) -> void:
	if worker == null:
		return
	var trap := TrapService.find_trap(ctx.game_data, trap_id)
	if trap == null or trap.get_caught() <= 0:
		if trap != null:
			_reject(worker, trap.macro_coords, trap.lot, GameContext.tr_text("trap_empty_reject_nothing"), effects)
		return
	for member in TrapJobProvider.workers(ctx, {"job_type": TrapJobProvider.JOB_EMPTY, "trap_id": trap_id}):
		if member != worker:
			_reject(worker, trap.macro_coords, trap.lot, GameContext.tr_text("trap_empty_reject_taken").format({"name": member.name}), effects)
			return
	var task := TrapJobProvider.build_empty_task(ctx, worker, trap_id)
	if task == null:
		_reject(worker, trap.macro_coords, trap.lot, GameContext.tr_text("trap_empty_reject_nothing"), effects)
		return
	var request := AssignRequest.create(worker, task, "task_activity_empty_trap", false).at_microcell(trap.macro_coords, trap.lot, "trap")
	# Attrezzi della trappola (2026-11-09, rete: coltello) già addosso: a mano non si va a prenderli.
	var tool_gate := ToolGateService.check_and_prepare(worker, task, ctx.game_data)
	if tool_gate["result"] != ToolGateService.Result.OK:
		CommandFeedback.tool_gate_failure(worker, tool_gate, effects)
		AssignService.reject_icon(request, effects)
		return
	AssignService.assign(request, ctx.age_band_of(worker), effects)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


static func _reject(worker: HumanIndividual, macro_coords: Vector2i, lot: Vector2i, text: String, effects: GameEffects) -> void:
	effects.command_icon_at_microcell(macro_coords, lot, "task_rejected")
	CommandFeedback.reject(worker, text, effects)
