class_name FishCommandService
extends RefCounted

# Comando "Pesca" col clic destro (2026-10-31, richiesta utente — pesca manuale, passo 1): un pipottino con la lenza
# (in cintura o nello zaino; il comando compare solo così, come Taglia ed Estrai, vedi RightClickCommandService) va alla
# riva della microcella di ruscello e pesca una sessione (FishAction). Rifiuto con X e messaggio se la microcella
# non ha pesci o se un altro ci sta già pescando. Senza stato: avvisi, icone e collegamenti dei segnali passano dagli
# effetti.
# Pesca nelle zone (2026-10-31, richiesta utente — pesca nelle aree di lavoro, passo 2): pulsante "Pesca" della barra
# Azioni, come la caccia nelle zone: dialog dei pesci da consegnare, poi zona automatica (assign_auto_zone_fish) o scelta
# a mano (fish_pick_area_ids + assign_work_area_fish); il punto lo sceglie FishZoneService e la pesca è la stessa del
# clic destro, con zona e serie nel context.


# `spot`: {"macro_coords", "position"} della microcella di ruscello (RightClickTargets.stream_fish o FishZoneService).
# `work_area_id` / `series`: zona e serie della pesca nelle zone (-1 / {} col clic destro); la destinazione del pesce è
# quella della serie, altrimenti quella della carne della caccia diretta, letta ora.
# Ordine del cassetto (2026-10-31, passo 4): `silent` = niente messaggi né X (la presa dalla coda);
# `tools_from_storage` = la lenza la va a prendere in deposito (ZoneOrderCommandService), niente controllo della lenza qui.
static func assign_fish(
	ctx: GameContext, worker: HumanIndividual, spot: Dictionary, effects: GameEffects, work_area_id: int = -1,
	series: Dictionary = {}, silent: bool = false, tools_from_storage: bool = false
) -> void:
	if worker == null or spot.is_empty():
		return
	var macro_coords: Vector2i = spot["macro_coords"]
	var fish_position: Vector2i = spot["position"]
	var cell: LiveMacroCell = ctx.live_cells.get(macro_coords)
	if cell == null or cell.macro_state == null:
		return
	var fish := StreamFishService.get_fish(
		cell.macro_state, cell.stream_positions, macro_coords.x, macro_coords.y, fish_position, ctx.game_data.get_absolute_day()
	)
	if fish <= 0:
		if silent:
			return
		effects.command_icon_at_microcell(macro_coords, fish_position, "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("fish_reject_empty"), effects)
		return
	var holder := ExtractionCommandService.find_target_holder(ctx.individuals, func(step: Action) -> bool:
		return step is FishAction and (step as FishAction).is_same_spot(macro_coords, fish_position)
	)
	if holder != null and holder != worker:
		if silent:
			return
		effects.command_icon_at_microcell(macro_coords, fish_position, "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("fish_reject_reserved").format({"name": holder.name}), effects)
		return
	var task := build_task(ctx, worker, macro_coords, fish_position, work_area_id, series)
	if task == null:
		return
	wire(task, worker, effects)
	var request := AssignRequest.create(worker, task, "task_activity_fish", silent).at_microcell(macro_coords, fish_position, "fish")
	request.strict = true
	var age_band := ctx.age_band_of(worker)
	if not AssignService.check(request, age_band, effects):
		return
	if not tools_from_storage:
		var tool_gate := ToolGateService.check_and_prepare(worker, task, ctx.game_data)
		if tool_gate["result"] != ToolGateService.Result.OK:
			if silent:
				return
			CommandFeedback.tool_gate_failure(worker, tool_gate, effects)
			AssignService.reject_icon(request, effects)
			return
		worker.tool_gate_warning = ""
	if AssignService.commit(request, age_band, effects) and not silent \
			and not worker.can_carry_one_unit_when_empty(FishAction.CAUGHT_RESOURCE_NAME):
		CommandFeedback.reject(worker, HumanIndividualActionService.no_room_message(worker, [FishAction.CAUGHT_RESOURCE_NAME]), effects)
		worker.bind_panel_message_to_task(task)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Una sessione di pesca nella zona `area` con la serie `series`: il punto migliore per `worker` (FishZoneService.
# choose_spot: pesci adesso, riva raggiungibile, non prenotato), poi assign_fish con zona e serie. Nessun punto: messaggio.
static func assign_work_area_fish(ctx: GameContext, worker: HumanIndividual, area: WorkArea, series: Dictionary, effects: GameEffects) -> void:
	if worker == null or area == null or not ctx.individuals.has(worker):
		return
	var spot: Variant = FishZoneService.choose_spot(area, worker, FishZoneService.collect_reserved_spots(ctx.individuals))
	if spot == null:
		CommandFeedback.reject(worker, GameContext.tr_text("work_area_fish_no_spot"), effects)
		return
	assign_fish(ctx, worker, {"macro_coords": area.macro_coords, "position": spot}, effects, area.id, series)


# Zona automatica dopo il dialog della pesca: per ciascuno la zona migliore (FishZoneService.choose_work_area), le
# prenotazioni rilette dopo ogni assegnazione. Nessuna zona per lui: messaggio.
static func assign_auto_zone_fish(
	ctx: GameContext, workers: Array[HumanIndividual], target: int, butcher_destination: String, effects: GameEffects
) -> void:
	var reserved := FishZoneService.collect_reserved_spots(ctx.individuals)
	for worker in workers:
		var area := FishZoneService.choose_work_area(ctx.game_data, worker, reserved)
		if area == null:
			CommandFeedback.reject(worker, GameContext.tr_text("work_area_fish_no_spot"), effects)
			continue
		assign_work_area_fish(ctx, worker, area, FishZoneService.make_series(area.id, target, butcher_destination), effects)
		reserved = FishZoneService.collect_reserved_spots(ctx.individuals)


# Zone di pesca con almeno un punto disponibile per qualcuno di `workers` (scelta a mano della zona).
static func fish_pick_area_ids(ctx: GameContext, workers: Array[HumanIndividual]) -> Array[int]:
	var reserved := FishZoneService.collect_reserved_spots(ctx.individuals)
	var valid_ids: Array[int] = []
	for area in FishZoneService.list_fish_work_areas(ctx.game_data):
		for worker in workers:
			if not FishZoneService.list_available_spots(area, worker, reserved, true).is_empty():
				valid_ids.append(area.id)
				break
	return valid_ids


# Task Fish sul punto, con destinazione del pesce (quella della serie, altrimenti quella della carne della caccia diretta,
# letta ora), zona e serie nel context. Condivisa dal comando e dalla pesca successiva della serie
# (WorkFollowUpService.continue_fish_series).
static func build_task(
	ctx: GameContext, worker: HumanIndividual, macro_coords: Vector2i, fish_position: Vector2i, work_area_id: int, series: Dictionary
) -> Task:
	var task := TaskBuilderService.build_fish_task(worker, macro_coords, fish_position)
	if task == null:
		return null
	var destination := String(series.get("butcher_destination", ""))
	if destination == "":
		destination = ButcherDestinationService.resolve_default(ctx.game_data.last_butcher_destination, ctx.world, ctx.folk)
	task.context[ButcherDestinationService.CONTEXT_KEY] = destination
	if work_area_id != -1:
		task.context[FishZoneService.CONTEXT_WORK_AREA_ID] = work_area_id
	if not series.is_empty():
		task.context[FishZoneService.CONTEXT_SERIES] = series.duplicate()
	return task


# Segnali della Task Fish: step costruiti e Walk + Unload della consegna, aggiunti dopo la presa (scarichi come per la
# raccolta).
static func wire(task: Task, worker: HumanIndividual, effects: GameEffects) -> void:
	effects.wire_task(GameEffects.WireKind.BUILD_STEPS, task, worker)
	effects.wire_task(GameEffects.WireKind.PICKUP, task, worker)
