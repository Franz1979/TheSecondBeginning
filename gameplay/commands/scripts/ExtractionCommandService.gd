class_name ExtractionCommandService
extends RefCounted

# Comandi di ricavo: taglio e cava (2026-10-24, refactoring GameScene 5B.3 — prima GameScene._assign_cut_task,
# _assign_quarry_task, _assign_extraction_task, _assign_cut_all_plants, _assign_work_area_cut/_quarry, la zona automatica
# di _on_cut/_quarry_count_chosen e _assign_site_cut_command). Un solo pipottino per bersaglio (pianta o roccia); la Task
# di ricavo va in coda dietro i ricavi già ordinati. Senza stato: avvisi, icone e collegamenti dei segnali passano dagli
# effetti. In scena restano i dialog (quante piante/pietre, scelta della pianta) e la scelta a mano della zona.


# Costruisce e assegna la Task di taglio sulla pianta `plant` ({"macro_coords", "object_type", "individual_key"}).
# Rifiuto con messaggio se la pianta è già nel lavoro di un pipottino (in corso o in coda); il resto in _assign_extraction.
# `work_area_id`: zona della pianta, per l'etichetta (-1 = comando col clic destro). `series`: serie di tagli ({} = taglio
# singolo). `silent` (presa dalla lista dei lavori): nessun avviso, popup né X.
static func assign_cut(ctx: GameContext, worker: HumanIndividual, plant: Dictionary, work_area_id: int, series: Dictionary, silent: bool, effects: GameEffects) -> void:
	if worker == null or plant.is_empty():
		return
	var macro_coords: Vector2i = plant["macro_coords"]
	var object_type: GameTypes.WorldObjectType = plant["object_type"]
	var individual_key: Vector3i = plant["individual_key"]
	var cell: LiveMacroCell = ctx.live_cells.get(macro_coords)
	if cell == null or cell.macro_state == null or not PlantCutService.is_individual_alive(cell.macro_state, object_type, individual_key):
		return
	var lot := Vector2i(individual_key.x, individual_key.y)
	var holder := find_target_holder(ctx.individuals, func(step: Action) -> bool:
		return step is CutAction and (step as CutAction).is_same_plant(macro_coords, int(object_type), individual_key)
	)
	if holder != null:
		if silent:
			return
		effects.command_icon_at_microcell(macro_coords, lot, "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("cut_reject_reserved").format({"name": holder.name}), effects)
		return
	var task := TaskBuilderService.build_cut_task(worker, plant, work_area_id, series)
	if task == null:
		return
	var cut_yield := PlantCutService.compute_yield(cell.macro_state, object_type, individual_key, ctx.game_data.year)
	_assign_extraction(ctx, worker, task, macro_coords, lot, "task_activity_cut", "cut", String(cut_yield.get("resource_name", "")), silent, effects)


# Costruisce e assegna la Task di estrazione sulla roccia `rock` ({"macro_coords", "position"}). Rifiuto con messaggio se
# la roccia non ha più pietra o è già nel lavoro di un pipottino; parametri come assign_cut.
static func assign_quarry(ctx: GameContext, worker: HumanIndividual, rock: Dictionary, work_area_id: int, series: Dictionary, silent: bool, effects: GameEffects) -> void:
	if worker == null or rock.is_empty():
		return
	var macro_coords: Vector2i = rock["macro_coords"]
	var rock_position: Vector2i = rock["position"]
	var cell: LiveMacroCell = ctx.live_cells.get(macro_coords)
	if cell == null or cell.macro_state == null:
		return
	if RockStoneService.get_remaining_stone(cell.macro_state, rock_position) <= 0:
		if silent:
			return
		effects.command_icon_at_microcell(macro_coords, rock_position, "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("quarry_reject_exhausted"), effects)
		return
	var holder := find_target_holder(ctx.individuals, func(step: Action) -> bool:
		return step is QuarryAction and (step as QuarryAction).is_same_rock(macro_coords, rock_position)
	)
	if holder != null:
		if silent:
			return
		effects.command_icon_at_microcell(macro_coords, rock_position, "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("quarry_reject_reserved").format({"name": holder.name}), effects)
		return
	var task := TaskBuilderService.build_quarry_task(worker, macro_coords, rock_position, work_area_id, series)
	if task == null:
		return
	var rock_rules := ResourceCalculator.get_density_rules(GameTypes.WorldObjectType.ROCK)
	var quarry_product: String = rock_rules.extraction_yield_resource_name if rock_rules != null else ""
	_assign_extraction(ctx, worker, task, macro_coords, rock_position, "task_activity_quarry", "quarry", quarry_product, silent, effects)


# "Taglia tutto qui" (`all_plants`: {"macro_coords", "lot"}): serie sulle piante disponibili della microcella, la prima
# scelta per `worker`. Nessuna pianta: messaggio.
static func assign_cut_all_plants(ctx: GameContext, worker: HumanIndividual, all_plants: Dictionary, effects: GameEffects) -> void:
	if worker == null or all_plants.is_empty():
		return
	var macro_coords: Vector2i = all_plants["macro_coords"]
	var lot: Vector2i = all_plants["lot"]
	var reserved := CutZoneService.collect_reserved_plants(ctx.individuals)
	var target := CutZoneService.list_available_plants_in_lot(ctx.live_cells, macro_coords, lot, null, reserved).size()
	var plant := CutZoneService.choose_plant_in_lot(ctx.live_cells, macro_coords, lot, worker, reserved)
	if plant.is_empty():
		CommandFeedback.reject(worker, GameContext.tr_text("cut_all_plants_none"), effects)
		return
	assign_cut(ctx, worker, plant, -1, CutZoneService.make_cell_series(macro_coords, lot, target), false, effects)


# Un taglio nella zona `area`: la pianta migliore per `worker` (CutZoneService.choose_plant: viva, ammessa dal filtro,
# raggiungibile, non prenotata), poi assign_cut con la zona per l'etichetta. Nessuna pianta: messaggio.
# `count`: tagli della serie (CutZoneService.make_series), questo è il primo.
static func assign_work_area_cut(ctx: GameContext, worker: HumanIndividual, area: WorkArea, count: int, effects: GameEffects) -> void:
	if worker == null or area == null or not ctx.individuals.has(worker):
		return
	var plant := CutZoneService.choose_plant(area, ctx.live_cells, worker, CutZoneService.collect_reserved_plants(ctx.individuals))
	if plant.is_empty():
		CommandFeedback.reject(worker, GameContext.tr_text("work_area_cut_no_plant"), effects)
		return
	assign_cut(ctx, worker, plant, area.id, CutZoneService.make_series(area.id, count), false, effects)


# Una estrazione nella zona `area`: la roccia migliore per `worker` (QuarryZoneService.choose_rock: pietra rimasta,
# raggiungibile, non prenotata), poi assign_quarry con la zona per l'etichetta. Nessuna roccia: messaggio.
# `count`: estrazioni della serie (QuarryZoneService.make_series), questa è la prima.
static func assign_work_area_quarry(ctx: GameContext, worker: HumanIndividual, area: WorkArea, count: int, effects: GameEffects) -> void:
	if worker == null or area == null or not ctx.individuals.has(worker):
		return
	var macro_state := ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
	var rock: Variant = QuarryZoneService.choose_rock(area, macro_state, worker, QuarryZoneService.collect_reserved_rocks(ctx.individuals))
	if rock == null:
		CommandFeedback.reject(worker, GameContext.tr_text("work_area_quarry_no_rock"), effects)
		return
	assign_quarry(ctx, worker, {"macro_coords": area.macro_coords, "position": rock}, area.id, QuarryZoneService.make_series(area.id, count), false, effects)


# Zona automatica dopo "Piante da tagliare": per ciascuno la zona migliore (CutZoneService.choose_work_area), le
# prenotazioni rilette dopo ogni assegnazione. Nessuna zona per lui: messaggio.
static func assign_auto_zone_cut(ctx: GameContext, workers: Array[HumanIndividual], count: int, effects: GameEffects) -> void:
	var reserved := CutZoneService.collect_reserved_plants(ctx.individuals)
	for worker in workers:
		var area := CutZoneService.choose_work_area(ctx.game_data, ctx.live_cells, worker, reserved)
		if area == null:
			CommandFeedback.reject(worker, GameContext.tr_text("work_area_cut_no_plant"), effects)
			continue
		assign_work_area_cut(ctx, worker, area, count, effects)
		reserved = CutZoneService.collect_reserved_plants(ctx.individuals)


# Zona automatica dopo "Pietre da estrarre", come assign_auto_zone_cut.
static func assign_auto_zone_quarry(ctx: GameContext, workers: Array[HumanIndividual], count: int, effects: GameEffects) -> void:
	var reserved := QuarryZoneService.collect_reserved_rocks(ctx.individuals)
	for worker in workers:
		var area := QuarryZoneService.choose_work_area(ctx.game_data, ctx.world, worker, reserved)
		if area == null:
			CommandFeedback.reject(worker, GameContext.tr_text("work_area_quarry_no_rock"), effects)
			continue
		assign_work_area_quarry(ctx, worker, area, count, effects)
		reserved = QuarryZoneService.collect_reserved_rocks(ctx.individuals)


# Zone di taglio con almeno una pianta disponibile per qualcuno di `workers` (scelta a mano della zona).
static func cut_pick_area_ids(ctx: GameContext, workers: Array[HumanIndividual]) -> Array[int]:
	var reserved := CutZoneService.collect_reserved_plants(ctx.individuals)
	var valid_ids: Array[int] = []
	for area in CutZoneService.list_cut_work_areas(ctx.game_data):
		for worker in workers:
			if not CutZoneService.list_available_plants(area, ctx.live_cells, worker, reserved, "", true).is_empty():
				valid_ids.append(area.id)
				break
	return valid_ids


# Zone di cava con almeno una roccia disponibile per qualcuno di `workers` (scelta a mano della zona).
static func quarry_pick_area_ids(ctx: GameContext, workers: Array[HumanIndividual]) -> Array[int]:
	var reserved := QuarryZoneService.collect_reserved_rocks(ctx.individuals)
	var valid_ids: Array[int] = []
	for area in QuarryZoneService.list_quarry_work_areas(ctx.game_data):
		var macro_state := ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		for worker in workers:
			if not QuarryZoneService.list_available_rocks(area, macro_state, worker, reserved, true).is_empty():
				valid_ids.append(area.id)
				break
	return valid_ids


# Comando "costruisci" su un cantiere in attesa del taglio: chi ha l'ascia taglia una cella libera del cantiere; senza
# ascia, o senza celle da prendere, X e motivo.
static func assign_site_cut_command(ctx: GameContext, worker: HumanIndividual, site: Building, effects: GameEffects) -> void:
	var cell: Variant = SiteCutService.pick_cell(ctx, worker, site) if ToolGateService.has_tool_for(worker, TaskTypes.ToolCategory.CHOPPING) else null
	if cell == null:
		effects.command_icon_at_microcell(Vector2i(site.macro_x, site.macro_y), Vector2i(site.micro_x, site.micro_y), "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("site_cut_command_needs_axe"), effects)
		return
	assign_cut(ctx, worker, SiteCutService.pick_plant(ctx, worker, site, cell), -1, SiteCutService.make_series(ctx, site, cell), false, effects)


# Assegnazione comune di una Task di ricavo già costruita: idoneità, poi coda. Se `worker` sta già facendo un ricavo (o
# consegnando il mucchio di uno) la nuova Task va in coda dietro quelle ordinate prima (in testa all'elenco, che si svuota
# dal fondo), lasciando un posto libero alla consegna del mucchio; altrimenti si assegna come gli altri comandi.
# `product_name`: resa principale; se nemmeno un'unità entra a carico vuoto, avviso "non ha spazio per trasportare" — il
# comando parte lo stesso. Segnali degli step (taglio, estrazione) collegati dalla scena (effetto BUILD_STEPS).
static func _assign_extraction(ctx: GameContext, worker: HumanIndividual, task: Task, macro_coords: Vector2i, lot: Vector2i, activity_key: String, icon_key: String, product_name: String, silent: bool, effects: GameEffects) -> void:
	effects.wire_task(GameEffects.WireKind.BUILD_STEPS, task, worker)
	var age_band := ctx.age_band_of(worker)
	var request := AssignRequest.create(worker, task, activity_key, silent).at_microcell(macro_coords, lot, icon_key)
	if not AssignService.check(request, age_band, effects):
		return
	var assigned := false
	if is_extraction_chain_task(worker.current_task):
		if worker.task_queue.size() >= TaskQueueService.MAX_QUEUE_SIZE - 1:
			if silent:
				return
			AssignService.reject_icon(request, effects)
			CommandFeedback.reject(worker, GameContext.tr_text("cut_reject_queue_full").format({"name": worker.name}), effects)
			return
		worker.task_queue.insert(0, task)
		assigned = AssignService.finish(request, true, age_band, effects)
	else:
		assigned = AssignService.commit(request, age_band, effects)
	if assigned and not silent and product_name != "" and not worker.can_carry_one_unit_when_empty(product_name):
		CommandFeedback.reject(worker, HumanIndividualActionService.no_room_message(worker, [product_name]), effects)
		# Avviso su una task che parte lo stesso: resta finché la task è in corso o in coda.
		worker.bind_panel_message_to_task(task)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# true se `task` è un ricavo non concluso (taglio, estrazione) o la consegna di un mucchio a terra (quella che segue).
static func is_extraction_chain_task(task: Task) -> bool:
	if task == null or task.is_finished():
		return false
	for step in task.steps:
		if step is CutAction or step is QuarryAction:
			return true
		if step is PickUpAction and (step as PickUpAction).source_kind == PickUpAction.SourceKind.GROUND_PILE:
			return true
	var zone := HaulZoneService.get_zone(task.context)
	return not zone.is_empty() and HaulZoneService.get_source_kind(zone) == PickUpAction.SourceKind.GROUND_PILE


# Pipottino che ha già in lavoro, in corso o in coda, uno step per cui `matches` (Callable(Action) -> bool) è vero;
# null se nessuno. "Un solo pipottino per bersaglio" di taglio (pianta) ed estrazione (roccia).
static func find_target_holder(individuals: Array, matches: Callable) -> HumanIndividual:
	for member in individuals:
		var tasks: Array = member.task_queue.duplicate()
		if member.current_task != null and not member.current_task.is_finished():
			tasks.append(member.current_task)
		for task in tasks:
			for step in task.steps:
				if matches.call(step):
					return member
	return null
