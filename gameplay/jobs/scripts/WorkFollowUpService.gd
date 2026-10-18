class_name WorkFollowUpService
extends RefCounted

# Lavori che partono da soli dopo un altro lavoro (2026-10-18, refactoring GameScene blocco 5d — prima gestori di segnale
# in GameScene): macellazione dopo la caccia, trasporto dei mucchi a terra, prosecuzione delle serie di zona (caccia, cava,
# taglio), ripetizioni di trasporto e raccolta. La scena resta collegata ai segnali e delega qui, poi applica gli effetti
# (popup, icone, pannelli, collegamenti dei segnali delle task nuove). Le task si costruiscono con TaskBuilderService e si
# accodano con TaskQueueService (mai dalle assegnazioni dei comandi). Senza stato: lo stato non salvato (avvisi delle
# carcasse lasciate a terra) vive in GameData.job_board_runtime.


# --- macellazione dopo la caccia ---

# Richiesta di macellazione della carcassa appena fatta da `hunter` (HumanIndividualActionService.butcher_after_hunt_requested).
# Una sola macellazione per carcassa (se qualcuno ce l'ha già, in corso o in coda, non se ne accoda un'altra). Senza lama
# in cintura, cella o mucchio non disponibili, task non costruibile o età non ammessa, la carcassa resta a terra e compare
# l'avviso in "In sospeso" (note_unbutchered_carcass). Altrimenti la macellazione si accoda come seguito della caccia,
# anche a coda piena (è un seguito, fuori dal limite), con l'icona sulla carcassa.
static func butcher_after_hunt(ctx: GameContext, hunter: HumanIndividual, carcass: Dictionary, effects: GameEffects) -> void:
	var macro_coords := Vector2i(int(carcass.get("macro_x", 0)), int(carcass.get("macro_y", 0)))
	var microcell := Vector2i(int(carcass.get("micro_x", 0)), int(carcass.get("micro_y", 0)))
	var carcass_id: int = int(carcass.get("id", -1))
	HuntService.log_event(hunter, "richiesta macellazione ricevuta: carcassa #%d, da %s (%s)." % [
		carcass_id, String(carcass.get("requested_by", "origine sconosciuta")), HuntService.describe_now()
	])
	for member in ctx.individuals:
		var where := describe_butcher_task_for_carcass(member, carcass_id)
		if where != "":
			HuntService.log_event(hunter, "macellazione non accodata: la carcassa #%d ha già una macellazione — #%d %s, %s." % [
				carcass_id, member.id, member.name, where
			])
			return
	if ToolGateService.find_belt_slot_for(hunter, TaskTypes.ToolCategory.BUTCHERING) == -1:
		HuntService.log_event(hunter, "macellazione non accodata: nessuna lama in cintura, la carcassa resta a terra.")
		CommandFeedback.reject(hunter, GameContext.tr_text("hunt_no_knife_carcass_left").format({"name": hunter.name}), effects)
		note_unbutchered_carcass(ctx.game_data, macro_coords, microcell, carcass_id)
		return
	if GroundPileService.find_carcass(ctx.game_data, macro_coords, microcell, carcass_id).is_empty():
		return
	var cell: LiveMacroCell = ctx.live_cells.get(macro_coords)
	var pile := GroundPileService.find_at(ctx.game_data, macro_coords, microcell)
	if cell == null or cell.macro_state == null or pile == null:
		HuntService.log_event(hunter, "macellazione non accodata: cella o mucchio della carcassa #%d non disponibili, la carcassa resta a terra." % carcass_id)
		note_unbutchered_carcass(ctx.game_data, macro_coords, microcell, carcass_id)
		return
	var task := TaskBuilderService.build_butcher_task(
		hunter, pile, carcass_id, cell.macro_state, String(carcass.get("butcher_destination", ButcherDestinationService.CAMPFIRE))
	)
	if task == null:
		HuntService.log_event(hunter, "macellazione non accodata: task non creata, la carcassa #%d resta a terra." % carcass_id)
		note_unbutchered_carcass(ctx.game_data, macro_coords, microcell, carcass_id)
		return
	effects.wire_task(GameEffects.WireKind.BUTCHER, task, hunter)
	# Caccia di zona (serie a obiettivo di carne): la carne di questa carcassa conta per la serie.
	if carcass.has("hunt_zone_series"):
		task.context[HuntZoneService.CONTEXT_MEAT_SERIES] = carcass["hunt_zone_series"]
	var hunter_age_band := ctx.age_band_of(hunter)
	for step in task.steps:
		if step.disallowed_age_bands.has(hunter_age_band):
			HuntService.log_event(hunter, "macellazione non accodata: età non ammessa, la carcassa #%d resta a terra." % carcass_id)
			note_unbutchered_carcass(ctx.game_data, macro_coords, microcell, carcass_id)
			return
	if hunter.task_queue.size() >= TaskQueueService.MAX_QUEUE_SIZE:
		HuntService.log_event(hunter, "macellazione avviata con la coda piena (%d/%d): seguito della caccia, fuori dal limite." % [
			hunter.task_queue.size(), TaskQueueService.MAX_QUEUE_SIZE
		])
	TaskQueueService.push_follow_up_task(hunter, task)
	effects.command_icon_at_microcell(macro_coords, microcell, "butcher")
	HuntService.log_event(hunter, "macellazione accodata sulla carcassa #%d (Task istanza %d, coda ora %d)." % [
		carcass_id, task.get_instance_id(), hunter.task_queue.size()
	])
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Dove `member` ha già una macellazione della carcassa `carcass_id` (task in corso e/o posizioni in coda); "" se nessuna.
static func describe_butcher_task_for_carcass(member: HumanIndividual, carcass_id: int) -> String:
	var places := PackedStringArray()
	if _task_butchers_carcass(member.current_task, carcass_id):
		places.append("task in corso (istanza %d)" % member.current_task.get_instance_id())
	for i in range(member.task_queue.size()):
		if _task_butchers_carcass(member.task_queue[i], carcass_id):
			places.append("in coda posizione %d (istanza %d)" % [i + 1, member.task_queue[i].get_instance_id()])
	return "; ".join(places)


static func _task_butchers_carcass(task: Task, carcass_id: int) -> bool:
	if task == null or task.is_finished():
		return false
	for step in task.steps:
		if step is ButcherAction and (step as ButcherAction).carcass_id == carcass_id:
			return true
	return false


# Carcassa lasciata a terra senza macellazione: avviso per la scheda "In sospeso", una volta sola per carcassa.
static func note_unbutchered_carcass(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i, carcass_id: int) -> void:
	var alerts: Array[Dictionary] = game_data.job_board_runtime.unbutchered_carcass_alerts
	for alert in alerts:
		if int(alert["id"]) == carcass_id:
			return
	alerts.append({
		"id": carcass_id, "macro_x": macro_coords.x, "macro_y": macro_coords.y, "micro_x": microcell.x, "micro_y": microcell.y,
	})


# --- mucchi a terra ---

# Trasporto al magazzino di un mucchio a terra appena lasciato (HumanIndividualActionService.ground_pile_haul_requested:
# demolizione, sgombero, "fino a svuotare" delle serie di cava e taglio). Un mucchio già vuoto di una serie di taglio fa
# proseguire la serie. Coda piena: il mucchio resta a terra. Solo le risorse che un magazzino raggiungibile accetta; senza
# nessuna, o (fino a svuotare) senza posto per un'unità, avviso: "serie interrotta" se il mucchio è di una serie, altrimenti
# il messaggio generico. Fino a svuotare: zona di raccolta di una microcella che si ripete finché il mucchio è vuoto.
static func ground_pile_haul(ctx: GameContext, carrier: HumanIndividual, pile_ref: Dictionary, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	var macro_coords := Vector2i(int(pile_ref.get("macro_x", 0)), int(pile_ref.get("macro_y", 0)))
	var microcell := Vector2i(int(pile_ref.get("micro_x", 0)), int(pile_ref.get("micro_y", 0)))
	var pile := GroundPileService.find_at(game_data, macro_coords, microcell)
	var cell: LiveMacroCell = ctx.live_cells.get(macro_coords)
	if (pile == null or pile.resources.is_empty()) and pile_ref.has(CutZoneService.SERIES_ZONE_KEY):
		var emptied_series: Variant = pile_ref[CutZoneService.SERIES_ZONE_KEY]
		if emptied_series is Dictionary:
			continue_cut_series(ctx, carrier, (emptied_series as Dictionary).duplicate(), effects)
		return
	if pile == null or pile.resources.is_empty() or cell == null or cell.macro_state == null:
		return
	if carrier.task_queue.size() >= TaskQueueService.MAX_QUEUE_SIZE:
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[GROUND PILE HAUL] #%d %s: coda piena, il mucchio #%d resta a terra." % [carrier.id, carrier.name, pile.id])
		return
	var resource_names := pile.get_resource_names()
	var with_destination: Array[String] = []
	for resource_name in resource_names:
		if pile.get_quantity(resource_name) > 0 and WarehouseSelectionService.find_best(
			ctx.world, carrier.position, carrier.home_macro_coords, resource_name, 1, [],
			PathfindingService.reachability_for(carrier)
		) != null:
			with_destination.append(resource_name)
	if with_destination.is_empty():
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[GROUND PILE HAUL] #%d %s: nessun magazzino raggiungibile accetta il contenuto del mucchio #%d, resta a terra." % [
				carrier.id, carrier.name, pile.id
			])
		if bool(pile_ref.get("until_empty", false)):
			var no_storage_reason := HumanIndividualActionService.series_stop_reason_no_storage(resource_names)
			if not quarry_pile_series_stopped(game_data, carrier, pile_ref, no_storage_reason, effects) \
					and not cut_pile_series_stopped(game_data, carrier, pile_ref, no_storage_reason, effects):
				CommandFeedback.reject(carrier, HumanIndividualActionService.no_storage_message(carrier, resource_names), effects)
		return
	if bool(pile_ref.get("until_empty", false)):
		var carriable := false
		for resource_name in with_destination:
			if carrier.can_carry_one_unit_when_empty(resource_name):
				carriable = true
				break
		if not carriable:
			var no_room_reason := HumanIndividualActionService.series_stop_reason_no_room(with_destination)
			if not quarry_pile_series_stopped(game_data, carrier, pile_ref, no_room_reason, effects) \
					and not cut_pile_series_stopped(game_data, carrier, pile_ref, no_room_reason, effects):
				CommandFeedback.reject(carrier, HumanIndividualActionService.no_room_message(carrier, with_destination), effects)
			return
	var until_empty: bool = bool(pile_ref.get("until_empty", false))
	var task := TaskBuilderService.build_pickup_task(
		cell.macro_state, microcell, resource_names[0], -1, PickUpAction.CriterionKind.ALL, -1, until_empty, 0,
		PickUpAction.SourceKind.GROUND_PILE
	)
	if until_empty:
		var pile_units := 0
		for resource_name in resource_names:
			pile_units += pile.get_quantity(resource_name)
		var until_empty_zone := HaulZoneService.make_zone(
			macro_coords, Rect2i(microcell, Vector2i.ONE), PickUpAction.CriterionKind.ALL, -1, resource_names[0], -1,
			PickUpAction.SourceKind.GROUND_PILE, maxi(pile_units, 1)
		)
		until_empty_zone[HaulZoneService.UNTIL_EMPTY_KEY] = true
		# Le serie di cava e taglio, la zona di lavoro e l'etichetta del lavoro seguono il mucchio nelle ripetizioni.
		if pile_ref.has(QuarryZoneService.SERIES_ZONE_KEY):
			until_empty_zone[QuarryZoneService.SERIES_ZONE_KEY] = pile_ref[QuarryZoneService.SERIES_ZONE_KEY]
		if pile_ref.has(CutZoneService.SERIES_ZONE_KEY):
			until_empty_zone[CutZoneService.SERIES_ZONE_KEY] = pile_ref[CutZoneService.SERIES_ZONE_KEY]
		if pile_ref.has(CutZoneService.CONTEXT_WORK_AREA_ID):
			until_empty_zone[CutZoneService.CONTEXT_WORK_AREA_ID] = pile_ref[CutZoneService.CONTEXT_WORK_AREA_ID]
		if pile_ref.has(HaulZoneService.LABEL_TASK_KEY):
			until_empty_zone[HaulZoneService.LABEL_TASK_KEY] = pile_ref[HaulZoneService.LABEL_TASK_KEY]
		task.context[HaulZoneService.CONTEXT_KEY] = until_empty_zone
	task.context[HaulZoneService.JOB_DELIVERY_KEY] = true
	task.context[HaulZoneService.PILE_RESOURCE_KEY] = resource_names[0] if resource_names.size() == 1 else ""
	var carrier_age_band := ctx.age_band_of(carrier)
	for step in task.steps:
		if step.disallowed_age_bands.has(carrier_age_band):
			return
	TaskQueueService.push_suspended_task(carrier, task)
	effects.wire_task(GameEffects.WireKind.PICKUP, task, carrier)
	# L'icona solo per i mucchi senza etichetta di lavoro (gli altri hanno già la loro riga nella lista).
	if not pile_ref.has(HaulZoneService.LABEL_TASK_KEY):
		effects.command_icon_at_microcell(macro_coords, microcell, "pickup")
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[GROUND PILE HAUL] #%d %s: trasporto del mucchio #%d al magazzino accodato (coda ora %d)." % [
			carrier.id, carrier.name, pile.id, carrier.task_queue.size()
		])
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# --- serie di zona ---

# Coltello per la caccia di zona (la preda si macella subito): try_satisfy sulla lama; avviso se manca, salvo `silent`.
static func prepare_hunt_knife(ctx: GameContext, hunter: HumanIndividual, silent: bool, effects: GameEffects) -> bool:
	var required: Array[TaskTypes.ToolCategory] = [TaskTypes.ToolCategory.BUTCHERING]
	var gate := ToolGateService.try_satisfy(hunter, required, ctx.game_data)
	if gate["result"] == ToolGateService.Result.OK:
		return true
	if not silent:
		CommandFeedback.tool_gate_failure(hunter, gate, effects)
	return false


# Prossima caccia della serie di zona (HumanIndividualActionService.hunt_zone_series_continue_requested). Ordine del
# cassetto: solo se l'ordine è ancora preso (e se ne registra l'avanzamento). Zona non più di caccia: serie chiusa. Senza
# coltello: avviso e serie chiusa. Altrimenti la caccia successiva si accoda come seguito.
static func continue_hunt_series(ctx: GameContext, hunter: HumanIndividual, series: Dictionary, effects: GameEffects) -> void:
	if hunter == null or not ctx.individuals.has(hunter):
		return
	var drawer_order_id := int(series.get(DrawerOrderService.SERIES_KEY, -1))
	if drawer_order_id >= 0:
		var order := DrawerOrderService.find(ctx.game_data, drawer_order_id)
		if order.is_empty() or not bool(order.get("taken", false)):
			return
		order["done_seen"] = maxi(int(order.get("done_seen", 0)), int(series.get("delivered", 0)))
	var area := WorkAreaService.find_by_id(ctx.game_data, int(series.get("work_area_id", -1)))
	if area == null or not HuntZoneService.list_hunt_work_areas(ctx.game_data).has(area):
		HuntZoneService.log_event(hunter, "serie di caccia chiusa: zona non più disponibile per la caccia.")
		return
	var knife_rejection := HuntZoneService.get_hunt_rejection(hunter)
	if knife_rejection != "":
		HuntZoneService.log_event(hunter, "serie di caccia chiusa: %s" % knife_rejection)
		CommandFeedback.reject(hunter, knife_rejection, effects)
		return
	var task := TaskBuilderService.build_hunt_zone_task(area.id, series)
	if task == null:
		return
	if not prepare_hunt_knife(ctx, hunter, false, effects):
		return
	TaskQueueService.push_follow_up_task(hunter, task)
	HuntZoneService.log_event(hunter, "nuova caccia della serie accodata in %s #%d (%d/%d carne)." % [
		area.name, area.id, int(series.get("delivered", 0)), int(series.get("target", 0))
	])
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Prossimo sasso della serie di cava (quarry_zone_series_continue_requested): lo stesso sasso se è ancora disponibile,
# altrimenti il prossimo scelto dalla zona. Serie del cassetto: avanzamento registrato e prosegue solo se l'ordine è preso.
# Zona tolta, niente attrezzo per scavare o niente sassi: "serie interrotta".
static func continue_quarry_series(ctx: GameContext, worker: HumanIndividual, series: Dictionary, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	if series.has(DrawerOrderService.SERIES_KEY):
		DrawerOrderService.note_progress(game_data, series)
		var drawer_order := DrawerOrderService.find(game_data, int(series[DrawerOrderService.SERIES_KEY]))
		if drawer_order.is_empty() or not bool(drawer_order.get("taken", false)):
			return
	if worker == null or not ctx.individuals.has(worker) or QuarryZoneService.is_series_complete(series):
		return
	var area := WorkAreaService.find_by_id(game_data, int(series.get("work_area_id", -1)))
	if area == null or not QuarryZoneService.list_quarry_work_areas(game_data).has(area):
		series_stopped(game_data, worker, QuarryZoneService.SERIES_STOPPED_KEY, series, GameContext.tr_text("series_stop_zone_gone"), effects)
		return
	if not ToolGateService.has_tool_for(worker, TaskTypes.ToolCategory.DIGGING):
		series_stopped(game_data, worker, QuarryZoneService.SERIES_STOPPED_KEY, series, GameContext.tr_text("series_stop_no_tool").format({
			"tools": ToolFetchService.describe_missing_categories([TaskTypes.ToolCategory.DIGGING]),
		}), effects)
		return
	var macro_state := ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
	var reserved := QuarryZoneService.collect_reserved_rocks(ctx.individuals)
	var available := QuarryZoneService.list_available_rocks(area, macro_state, worker, reserved)
	var last_rock := Vector2i(int(series.get("rock_x", -1)), int(series.get("rock_y", -1)))
	var rock: Variant = last_rock if available.has(last_rock) else QuarryZoneService.choose_rock(area, macro_state, worker, reserved)
	if rock == null:
		series_stopped(game_data, worker, QuarryZoneService.SERIES_STOPPED_KEY, series, GameContext.tr_text("series_stop_no_rock"), effects)
		return
	var task := TaskBuilderService.build_quarry_task(worker, area.macro_coords, rock, area.id, series)
	if task == null:
		return
	TaskQueueService.push_suspended_task(worker, task)
	effects.wire_task(GameEffects.WireKind.BUILD_STEPS, task, worker)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Prossima pianta della serie di taglio (cut_zone_series_continue_requested; anche da un mucchio di una serie già vuoto).
# Serie su una cella (taglia tutto qui): continue_cut_cell_series. Serie di zona: pianta scelta dalla zona con la resa
# della serie; zona tolta, niente attrezzo per tagliare o niente piante: "serie interrotta".
static func continue_cut_series(ctx: GameContext, worker: HumanIndividual, series: Dictionary, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	if series.has(DrawerOrderService.SERIES_KEY):
		DrawerOrderService.note_progress(game_data, series)
		var drawer_order := DrawerOrderService.find(game_data, int(series[DrawerOrderService.SERIES_KEY]))
		if drawer_order.is_empty() or not bool(drawer_order.get("taken", false)):
			return
	if worker == null or not ctx.individuals.has(worker) or CutZoneService.is_series_complete(series):
		return
	if CutZoneService.is_cell_series(series):
		continue_cut_cell_series(ctx, worker, series, effects)
		return
	var area := WorkAreaService.find_by_id(game_data, int(series.get("work_area_id", -1)))
	if area == null or not CutZoneService.list_cut_work_areas(game_data).has(area):
		series_stopped(game_data, worker, CutZoneService.SERIES_STOPPED_KEY, series, GameContext.tr_text("series_stop_zone_gone"), effects)
		return
	if not ToolGateService.has_tool_for(worker, TaskTypes.ToolCategory.CHOPPING):
		series_stopped(game_data, worker, CutZoneService.SERIES_STOPPED_KEY, series, GameContext.tr_text("series_stop_no_tool").format({
			"tools": ToolFetchService.describe_missing_categories([TaskTypes.ToolCategory.CHOPPING]),
		}), effects)
		return
	var plant := CutZoneService.choose_plant(
		area, ctx.live_cells, worker, CutZoneService.collect_reserved_plants(ctx.individuals),
		String(series.get(CutZoneService.SERIES_YIELD_KEY, ""))
	)
	if plant.is_empty():
		series_stopped(game_data, worker, CutZoneService.SERIES_STOPPED_KEY, series, GameContext.tr_text("series_stop_no_plant"), effects)
		return
	var task := TaskBuilderService.build_cut_task(worker, plant, area.id, series)
	if task == null:
		return
	TaskQueueService.push_suspended_task(worker, task)
	effects.wire_task(GameEffects.WireKind.BUILD_STEPS, task, worker)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Serie "taglia tutto qui" su una cella: la prossima pianta del lotto; finite le piante la serie si chiude in silenzio.
# Senza attrezzo per tagliare: "serie interrotta".
static func continue_cut_cell_series(ctx: GameContext, worker: HumanIndividual, series: Dictionary, effects: GameEffects) -> void:
	var plant := CutZoneService.choose_plant_in_lot(
		ctx.live_cells, CutZoneService.get_cell_series_macro_coords(series), CutZoneService.get_cell_series_lot(series),
		worker, CutZoneService.collect_reserved_plants(ctx.individuals)
	)
	if plant.is_empty():
		return
	if not ToolGateService.has_tool_for(worker, TaskTypes.ToolCategory.CHOPPING):
		series_stopped(ctx.game_data, worker, CutZoneService.SERIES_STOPPED_KEY, series, GameContext.tr_text("series_stop_no_tool").format({
			"tools": ToolFetchService.describe_missing_categories([TaskTypes.ToolCategory.CHOPPING]),
		}), effects)
		return
	var task := TaskBuilderService.build_cut_task(worker, plant, -1, series)
	if task == null:
		return
	TaskQueueService.push_suspended_task(worker, task)
	effects.wire_task(GameEffects.WireKind.BUILD_STEPS, task, worker)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Serie interrotta (cava: QuarryZoneService.SERIES_STOPPED_KEY; taglio: CutZoneService.SERIES_STOPPED_KEY): avanzamento
# dell'eventuale ordine del cassetto registrato, poi l'avviso con il motivo.
static func series_stopped(
	game_data: GameData, worker: HumanIndividual, stopped_key: String, series: Dictionary, reason: String, effects: GameEffects
) -> void:
	DrawerOrderService.note_progress(game_data, series)
	CommandFeedback.reject(worker, HumanIndividualActionService.series_stopped_message(worker, stopped_key, series, reason), effects)


# Mucchio di una serie di cava non finita: "serie interrotta" e true; false se il mucchio non è di una serie di cava (o la
# serie è già completa), così il chiamante dà il suo avviso.
static func quarry_pile_series_stopped(
	game_data: GameData, worker: HumanIndividual, pile_ref: Dictionary, reason: String, effects: GameEffects
) -> bool:
	var series: Variant = pile_ref.get(QuarryZoneService.SERIES_ZONE_KEY, {})
	if not (series is Dictionary) or (series as Dictionary).is_empty():
		return false
	if not QuarryZoneService.is_series_complete(series):
		series_stopped(game_data, worker, QuarryZoneService.SERIES_STOPPED_KEY, series, reason, effects)
		return true
	return false


# Stessa regola per un mucchio di una serie di taglio.
static func cut_pile_series_stopped(
	game_data: GameData, worker: HumanIndividual, pile_ref: Dictionary, reason: String, effects: GameEffects
) -> bool:
	var series: Variant = pile_ref.get(CutZoneService.SERIES_ZONE_KEY, {})
	if not (series is Dictionary) or (series as Dictionary).is_empty():
		return false
	if not CutZoneService.is_series_complete(series):
		series_stopped(game_data, worker, CutZoneService.SERIES_STOPPED_KEY, series, reason, effects)
		return true
	return false


# --- ripetizioni ---

# Ripetizione del trasporto dopo una consegna (UnloadAction.transport_delivered): solo con la ripetizione attiva, sotto
# il numero massimo di ripetizioni, con ancora qualcosa da portare, sorgente e destinazione valide, risorsa ancora nella
# sorgente, posto nella destinazione e coda non piena. Il viaggio successivo si accoda (sospeso).
static func repeat_transport(ctx: GameContext, owner: HumanIndividual, context: Dictionary, delivered: int, effects: GameEffects) -> void:
	if owner == null or not TaskRepeatRules.is_enabled(context) or delivered <= 0:
		return
	var repeats_done: int = TaskRepeatRules.get_count(context)
	if repeats_done >= TaskRepeatRules.MAX_REPEATS:
		return
	var resource_name: String = String(context.get("transport_delivery_resource", ""))
	var remaining: int = int(context.get("transport_requested_remaining", 0)) - delivered
	if resource_name == "" or remaining <= 0:
		return
	var source_building := _find_building(ctx.world, int(context.get("transport_source_id", -1)))
	var destination_building := _find_building(ctx.world, int(context.get("transport_destination_id", -1)))
	if source_building == null or destination_building == null or source_building.is_demolished or not source_building.is_complete:
		return
	if BuildingStorageService.get_available_quantity(source_building, resource_name) <= 0:
		return
	var trip_target: int = TaskBuilderService.transport_trip_target(destination_building, resource_name, remaining)
	if trip_target <= 0:
		return
	if owner.task_queue.size() >= TaskQueueService.MAX_QUEUE_SIZE:
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[TRANSPORT] #%d %s: ripetizione %d non accodata - coda piena (%d)." % [
				owner.id, owner.name, repeats_done + 1, TaskQueueService.MAX_QUEUE_SIZE
			])
		return
	var repeat_task := TaskBuilderService.build_transport_task(
		owner, source_building, destination_building, resource_name, trip_target, remaining, true, repeats_done + 1
	)
	# Trasporto verso la rastrelliera ordinato dal gestore delle scorte: la ripetizione resta sua.
	if context.has(WarehouseManagerService.STOCK_DRY_KEY):
		repeat_task.context[WarehouseManagerService.STOCK_DRY_KEY] = context[WarehouseManagerService.STOCK_DRY_KEY]
	TaskQueueService.push_suspended_task(owner, repeat_task)
	effects.wire_storage_task(repeat_task, owner)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[TRANSPORT] #%d %s: ripetizione %d/%d accodata - consegnate %d, residuo %d, obiettivo del viaggio %d." % [
			owner.id, owner.name, repeats_done + 1, TaskRepeatRules.MAX_REPEATS, delivered, remaining, trip_target
		])


# Ripetizione della raccolta (PickUpAction.repeat_requested): una zona fuori dalle zone di lavoro richiede la sua
# macrocella viva; coda piena: niente ripetizione. La raccolta successiva si accoda (sospesa).
static func repeat_pickup(ctx: GameContext, owner: HumanIndividual, next_repeat_count: int, zone: Dictionary, effects: GameEffects) -> void:
	if owner == null or zone.is_empty():
		return
	if not HaulZoneService.is_work_area_zone(zone):
		var repeat_cell: LiveMacroCell = ctx.live_cells.get(HaulZoneService.get_macro_coords(zone))
		if repeat_cell == null or repeat_cell.macro_state == null:
			return
	if owner.task_queue.size() >= TaskQueueService.MAX_QUEUE_SIZE:
		if DebugLogging.ENABLED and DebugLogging.SHOW_PICKUP_LOGS:
			print("[PICKUP] #%d %s: ripetizione %d non accodata — coda piena (%d)." % [
				owner.id, owner.name, next_repeat_count, TaskQueueService.MAX_QUEUE_SIZE
			])
		return
	var repeat_task := TaskBuilderService.build_haul_zone_task(zone, true, next_repeat_count)
	TaskQueueService.push_suspended_task(owner, repeat_task)
	effects.wire_task(GameEffects.WireKind.HAUL_ZONE, repeat_task, owner)


static func _find_building(world: World, building_id: int) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null
