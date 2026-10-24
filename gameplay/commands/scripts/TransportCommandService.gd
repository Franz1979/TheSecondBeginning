class_name TransportCommandService
extends RefCounted

# Comandi di trasporto e raccolta (2026-10-24, refactoring GameScene 5B.6 — prima GameScene._assign_transport_task,
# _assign_pickup_task, _assign_work_area_gather, la zona automatica e le zone valide di _on_work_area_gather_choice e
# _assign_drawer_transport_job). Senza stato: avvisi, icone, collegamenti dei segnali e pannelli passano dagli effetti.
# In scena restano i due clic destri del trasporto con il loro dialog, il dialog della raccolta e la scelta a mano della
# zona.


# Transport Task completa [Walk, Retrieve, Walk, Unload] da `source` a `destination` con risorsa e quantità già scelte
# nel TransportSourceDialog (`repeat_enabled`: casella "Ripeti", TaskRepeatRules). Obiettivo del viaggio: il minimo tra
# la quantità chiesta e il fabbisogno della destinazione se non è completa (TaskBuilderService.transport_trip_target);
# fabbisogno a zero = comando rifiutato. Icona "transport" o "task_rejected" sulla destinazione.
static func assign_transport(
	ctx: GameContext, worker: HumanIndividual, source_building: Building, destination_building: Building,
	resource_name: String, quantity: int, repeat_enabled: bool, effects: GameEffects
) -> void:
	if worker == null:
		return
	var destination_macro_coords := Vector2i(destination_building.macro_x, destination_building.macro_y)
	var destination_microcell := Vector2i(destination_building.micro_x, destination_building.micro_y)
	var trip_target: int = TaskBuilderService.transport_trip_target(destination_building, resource_name, quantity)
	if trip_target <= 0:
		effects.command_icon_at_microcell(destination_macro_coords, destination_microcell, "task_rejected")
		# Motivo (2026-09-26): la destinazione non ha bisogno di quella risorsa.
		CommandFeedback.reject(worker, GameContext.tr_text("task_reject_transport_not_needed").format({
			"name": worker.name, "building": destination_building.get_display_name(),
			"resource": IconRegistry.get_resource_display_name(resource_name),
		}), effects)
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[TRANSPORT] rifiutata: %s #%d non ha bisogno di '%s' (obiettivo 0)." % [
				destination_building.building_type_name, destination_building.id, resource_name
			])
		return
	var task := TaskBuilderService.build_transport_task(
		worker, source_building, destination_building, resource_name, trip_target, quantity, repeat_enabled, 0
	)
	var request := AssignRequest.create(worker, task, "task_activity_transport").at_microcell(
		destination_macro_coords, destination_microcell, "transport"
	)
	var age_band := ctx.age_band_of(worker)
	if not AssignService.check(request, age_band, effects):
		return
	effects.wire_storage_task(task, worker)
	AssignService.commit(request, age_band, effects)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[TRANSPORT] Task assegnata a #%d %s: %s #%d -> %s #%d, risorsa='%s' chiesta=%d obiettivo=%d ripeti=%s" % [
			worker.id, worker.name,
			source_building.building_type_name, source_building.id,
			destination_building.building_type_name, destination_building.id,
			resource_name, quantity, trip_target, str(repeat_enabled),
		])


# Raccolta sulla microcella `target_position` (clic destro, dialog della raccolta): zona 1×1 sulla cella (non entra in
# GameData.work_areas), Task della raccolta su zona (TaskBuilderService.build_haul_zone_task), icona "pickup" sulla cella.
# `quantity_requested` -1 = nessun tetto; `criterion_kind`/`criterion_category`: criterio di PickUpAction (NAME, CATEGORY,
# ALL — `resource_name` resta obbligatorio ma con CATEGORY/ALL non viene usato).
static func assign_pickup(
	ctx: GameContext, worker: HumanIndividual, macro_coords: Vector2i, target_position: Vector2i, resource_name: String,
	quantity_requested: int, criterion_kind: int, criterion_category: int, repeat_enabled: bool, repeat_count: int,
	source_kind: int, effects: GameEffects
) -> void:
	if worker == null:
		return
	var cell: LiveMacroCell = ctx.live_cells.get(macro_coords)
	if cell == null or cell.macro_state == null:
		return
	var zone := HaulZoneService.make_zone(
		macro_coords, Rect2i(target_position, Vector2i.ONE), criterion_kind, criterion_category, resource_name,
		quantity_requested, source_kind, HaulZoneService.CLICK_MAX_REPEATS
	)
	var task := TaskBuilderService.build_haul_zone_task(zone, repeat_enabled, repeat_count)
	effects.wire_task(GameEffects.WireKind.HAUL_ZONE, task, worker)
	AssignService.assign(
		AssignRequest.create(worker, task, "task_activity_pickup").at_microcell(macro_coords, target_position, "pickup"),
		ctx.age_band_of(worker), effects
	)


# Raccolta nella zona `area` (`order`: kind/category/resource_name/repeat/trips, opzionale stock_fill). Icona al centro
# della zona. `silent` (ordini "Raccogli" del cassetto): nessun avviso, popup né X. `drawer_order_id`: ordine del
# cassetto, scritto nella zona (viaggia con le ripetizioni, DrawerOrderService.task_zone_info); -1 = comando.
static func assign_work_area_gather(
	ctx: GameContext, worker: HumanIndividual, area: WorkArea, order: Dictionary, silent: bool, drawer_order_id: int,
	effects: GameEffects
) -> void:
	if worker == null or area == null or not ctx.individuals.has(worker):
		return
	var kind := int(order["kind"])
	var order_category := int(order["category"])
	var order_resource := String(order["resource_name"])
	var repeat := bool(order["repeat"])
	# Viaggi scelti (2026-10-01): N viaggi = il primo + N - 1 ripetizioni.
	var trips := int(order.get("trips", HaulZoneService.WORK_AREA_MAX_REPEATS + 1))
	var zone := HaulZoneService.make_work_area_zone(area.id, kind, order_category, order_resource, maxi(trips - 1, 0))
	if drawer_order_id >= 0:
		zone[DrawerOrderService.SERIES_KEY] = drawer_order_id
	# Raccolta del magazzino (2026-10-11): lo zaino si riempie con quello che serve (HaulZoneService.STOCK_FILL_KEY).
	if bool(order.get("stock_fill", false)):
		zone[HaulZoneService.STOCK_FILL_KEY] = true
	var task := TaskBuilderService.build_haul_zone_task(zone, repeat, 0)
	effects.wire_task(GameEffects.WireKind.HAUL_ZONE, task, worker)
	AssignService.assign(
		AssignRequest.create(worker, task, "task_activity_pickup", silent).at_microcell(
			area.macro_coords, area.rect.position + area.rect.size / 2, "pickup"
		),
		ctx.age_band_of(worker), effects
	)
	if DebugLogging.ENABLED and DebugLogging.SHOW_PICKUP_LOGS:
		print("[PICKUP] #%d %s: raccolta nella zona %s (#%d), criterio %d/%d/'%s', ripeti=%s." % [
			worker.id, worker.name, area.name, area.id, kind, order_category, order_resource, str(repeat)
		])


# Zona automatica della raccolta: ognuno nella propria zona migliore (HaulZoneService.choose_work_area), avviso per chi
# non ne ha una valida.
static func assign_auto_zone_gather(ctx: GameContext, workers: Array[HumanIndividual], order: Dictionary, effects: GameEffects) -> void:
	for worker in workers:
		if not ctx.individuals.has(worker):
			continue
		var area := HaulZoneService.choose_work_area(
			ctx.game_data, ctx.world, worker, int(order["kind"]), int(order["category"]), String(order["resource_name"])
		)
		if area == null:
			CommandFeedback.reject(worker, GameContext.tr_text("work_area_gather_no_zone").format({"name": worker.name}), effects)
			continue
		assign_work_area_gather(ctx, worker, area, order, false, -1, effects)


# Zone valide per la scelta a mano della raccolta: quelle con qualcosa da raccogliere per il filtro, per almeno uno dei
# pipottini.
static func gather_pick_area_ids(ctx: GameContext, workers: Array[HumanIndividual], order: Dictionary) -> Array[int]:
	var valid_ids: Array[int] = []
	for area in ctx.game_data.work_areas:
		var names := HaulZoneService.allowed_names_for(area, int(order["kind"]), int(order["category"]), String(order["resource_name"]))
		if names.is_empty():
			continue
		var macro_state := ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		for worker in workers:
			if HaulZoneService.has_available_in_area(area, macro_state, names, worker):
				valid_ids.append(area.id)
				break
	return valid_ids


# Presa di un ordine di trasporto del magazzino: il trasporto parte (con la ripetizione dei viaggi fino alla quantità)
# e l'ordine esce dal cassetto. Più di un viaggio di carico: prima il travois, se ce n'è uno libero.
static func assign_drawer_transport_job(ctx: GameContext, worker: HumanIndividual, job: Dictionary, effects: GameEffects) -> void:
	var order: Dictionary = job["order"]
	var order_id := int(order["id"])
	if DrawerOrderService.find(ctx.game_data, order_id).is_empty():
		return
	var pick := WarehouseManagerService.transport_order_pick(ctx.world, worker, order)
	if pick.is_empty():
		return
	var task := WarehouseManagerService.transport_order_task(worker, order, pick)
	if task == null:
		return
	if not worker.assign_task(task, ctx.age_band_of(worker)):
		return
	effects.wire_storage_task(task, worker)
	DrawerOrderService.remove(ctx.game_data, order_id)
	var job_keys: Array[String] = [String(job["key"])]
	CommandFeedback.forget_job_board_waits(ctx.game_data, job_keys, effects)
	# Travois (2026-10-23): più di un viaggio di carico -> lo prende prima, se ce n'è uno libero.
	if ToolFetchService.needs_towing_for(worker, String(pick["resource"]), int(pick["quantity"])):
		ZoneOrderCommandService.start_towed_fetch(ctx, worker, "trasporto #%d" % order_id, effects)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
