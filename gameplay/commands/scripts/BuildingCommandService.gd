class_name BuildingCommandService
extends RefCounted

# Comandi sugli edifici: costruzione, demolizione, sgombero delle macerie, riparazione e nascita del cantiere (2026-10-24,
# refactoring GameScene 5B.4 — prima GameScene._assign_resumable_building_task, _assign_debris_clearing_task,
# _assign_repair_task, _can_start_repair/_can_assign_repair, _count_other_individuals_claiming_build e la parte di dati di
# _start_building_task_at). Senza stato: avvisi, icone e collegamenti dei segnali passano dagli effetti. In scena restano
# il piazzamento (fantasma, verifiche con avviso), il disegno e la lettura dell'erba disegnata sul cantiere.


# Riprende (o inizia) il lavoro di `worker` su `building`: Build per un cantiere, Demolish per un edificio "da demolire",
# trasporto dei detriti per macerie e Fossa da svuotare, taglio di una cella per un cantiere nel bosco in attesa del
# taglio. `grass_on_site` (solo Build, lo consuma ClearAction): null se la cella non è viva, altrimenti l'erba
# disegnata sul cantiere (bool per un 1x1, numero di microcelle per un edificio grande). false = niente da fare (nessuna
# Task costruibile): il clic destro prosegue col movimento.
static func assign_resumable(ctx: GameContext, worker: HumanIndividual, building: Building, grass_on_site: Variant, effects: GameEffects) -> bool:
	# Sgombero delle macerie e svuotamento di una Fossa (2026-10-18): Transport dei detriti alla Fossa, non una Demolish.
	if WasteDisposalService.has_debris_job(building):
		return assign_debris_clearing(ctx, worker, building, effects)
	# Cantiere nel bosco in attesa del taglio (2026-10-18): il comando fa tagliare una sua cella (con l'ascia), mai costruire.
	if building.awaiting_site_cut and not SiteCutService.try_finish(ctx.world, building):
		ExtractionCommandService.assign_site_cut_command(ctx, worker, building, effects)
		return true
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	var microcell := Vector2i(building.micro_x, building.micro_y)
	# Demolish Task (2026-09-27): stesso percorso per un edificio "da demolire" — reassign_task costruisce demolish.tres
	# (Building.get_resumable_task_definition_path), stesso limite di costruttori contato sulle Demolish Task.
	var is_demolition: bool = building.is_marked_for_demolition
	# Limite di costruttori (2026-09-14): rifiuto esplicito prima di costruire la Task, X e avviso {current}/{max}.
	var max_builders: int = building.rules.max_builders if building.rules != null else 1
	var other_builders_count := count_other_builders(ctx.individuals, building, worker, JobWorkScanService.DEMOLISH_TASK_NAMES if is_demolition else JobWorkScanService.BUILD_TASK_NAMES)
	if other_builders_count >= max_builders:
		effects.command_icon_at_microcell(macro_coords, microcell, "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("notification_build_capacity_full").format({
			"current": other_builders_count,
			"max": max_builders,
		}), effects)
		return true
	# extra_context solo per la Build (lo consumano SetupSite/Clear): per la Demolish resterebbe nel context della Task
	# (MacroCellState non è salvabile in JSON).
	var extra_context: Dictionary = {}
	if not is_demolition:
		extra_context = {
			"macro_state": ctx.world.get_cell_state_at(building.macro_x, building.macro_y) if ctx.world != null else null,
			"is_currently_grass": grass_on_site if grass_on_site != null else false,
		}
	var age_band := ctx.age_band_of(worker)
	# reassign_task assegna già la Task (anche in coda, con lo zaino occupato): qui solo l'esito.
	var task := TaskReassignmentService.reassign_task(building, worker, age_band, extra_context)
	if task == null:
		return false
	effects.wire_task(GameEffects.WireKind.MATERIAL_SUPPLY, task, worker)
	var icon_key := ("clear_rubble" if building.is_rubble() else "demolish") if is_demolition else "build"
	var request := AssignRequest.create(worker, task, "task_activity_demolish" if is_demolition else "task_activity_build").at_microcell(
		macro_coords, microcell, icon_key
	)
	request.strict = true
	if not AssignService.finish(request, true, age_band, effects):
		return true
	# Lavoro assegnato: esce dalla lista; se ci tornerà, l'attesa per l'assegnazione a mano ripartirà da capo.
	CommandFeedback.forget_job_board_waits(ctx.game_data, BuildingJobProvider.job_keys(building), effects)
	# Segnali di SetupSiteAction/ClearAction e degli altri step della Build (GameScene._reconnect_build_task_signals).
	effects.wire_task(GameEffects.WireKind.BUILD_STEPS, task, worker)
	if DebugLogging.ENABLED and (DebugLogging.SHOW_TRANSPORT_BUILD_LOGS or DebugLogging.SHOW_BUILDERS_LOGS):
		print("[BUILD] Task di %s assegnata a #%d %s per l'edificio #%d." % [
			"demolizione" if is_demolition else "costruzione", worker.id, worker.name, building.id
		])
	return true


# Sgombero delle macerie o svuotamento di una Fossa: Transport dei detriti alla Fossa. Nessuna Fossa con posto: X e
# avviso. Sempre true (comando gestito).
static func assign_debris_clearing(ctx: GameContext, worker: HumanIndividual, rubble: Building, effects: GameEffects) -> bool:
	var macro_coords := Vector2i(rubble.macro_x, rubble.macro_y)
	var microcell := Vector2i(rubble.micro_x, rubble.micro_y)
	var task := WasteDisposalService.build_debris_clearing_task(ctx.world, worker, rubble)
	if task == null:
		effects.command_icon_at_microcell(macro_coords, microcell, "task_rejected")
		CommandFeedback.reject(worker, GameContext.tr_text("notification_clear_rubble_no_pit"), effects)
		return true
	effects.wire_storage_task(task, worker)
	# Nessun controllo di idoneità prima (come sempre): l'esito di assign_task decide.
	var request := AssignRequest.create(worker, task, "task_activity_transport").at_microcell(macro_coords, microcell, "clear_rubble")
	if not AssignService.commit(request, ctx.age_band_of(worker), effects):
		return true
	CommandFeedback.forget_job_board_waits(ctx.game_data, BuildingJobProvider.job_keys(rubble), effects)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	return true


# Repair Task (Walk -> Repair) per `worker` su `building`: un solo riparatore per edificio; rifiuti con la X sul
# bersaglio e il motivo, come gli altri comandi. Assegnata: martello sull'edificio, come la Build.
static func assign_repair(ctx: GameContext, worker: HumanIndividual, building: Building, effects: GameEffects) -> void:
	if worker == null or building == null:
		return
	var microcell := Vector2i(building.micro_x, building.micro_y)
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
	if not can_assign_repair(ctx.individuals, building):
		if RepairAction.is_building_repairable(building) and not JobWorkScanService.workers_on_building(ctx.individuals, building, JobWorkScanService.REPAIR_TASK_NAMES).is_empty():
			CommandFeedback.reject(worker, GameContext.tr_text("repair_reject_already_repairing").format({"building": building.get_display_name()}), effects)
			effects.command_icon_at_microcell(macro_coords, microcell, "task_rejected")
		return
	var task := TaskBuilderService.build_repair_task(worker, building)
	if task == null:
		return
	# Idoneità, assegnazione (in corso o in coda) e icona del martello.
	var request := AssignRequest.create(worker, task, "task_activity_repair").at_microcell(macro_coords, microcell, "build")
	request.strict = true
	if AssignService.assign(request, ctx.age_band_of(worker), effects) != AssignService.Result.ASSIGNED:
		return
	# Lavoro assegnato: esce dalla coda; se ci tornerà, l'attesa per l'assegnazione a mano ripartirà da capo.
	CommandFeedback.forget_job_board_waits(ctx.game_data, RepairJobProvider.job_keys(building), effects)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[REPAIR] Riparazione dell'edificio #%d (%s) assegnata a #%d %s (Integrità %.1f/%d)." % [
			building.id, building.get_display_name(), worker.id, worker.name, building.current_durability, building.rules.max_durability
		])


# Stesse condizioni del pulsante: edificio riparabile, Integrità sotto la soglia, nessuno che lo ripara già, nessuna
# riparazione già richiesta.
static func can_start_repair(individuals: Array, building: Building) -> bool:
	if not RepairAction.is_building_repairable(building) or building.repair_requested:
		return false
	if building.current_durability / float(building.rules.max_durability) >= Building.DURABILITY_REPAIRABLE_RATIO:
		return false
	return JobWorkScanService.workers_on_building(individuals, building, JobWorkScanService.REPAIR_TASK_NAMES).is_empty()


# Si può dare la Repair Task su `building` adesso: riparabile, Integrità non piena, nessun altro riparatore, e sotto la
# soglia oppure con la riparazione richiesta (una riparazione richiesta e interrotta sopra il 70% torna in coda e si
# riassegna fino alla fine).
static func can_assign_repair(individuals: Array, building: Building) -> bool:
	if not RepairAction.is_building_repairable(building):
		return false
	if building.current_durability >= float(building.rules.max_durability):
		return false
	if not building.repair_requested and building.current_durability / float(building.rules.max_durability) >= Building.DURABILITY_REPAIRABLE_RATIO:
		return false
	return JobWorkScanService.workers_on_building(individuals, building, JobWorkScanService.REPAIR_TASK_NAMES).is_empty()


# Limite di costruttori (2026-09-14, guard temporaneo finché il multi-costruttore non è progettato): quanti ALTRI
# individui (escluso `excluding`, che può sempre riprendere il PROPRIO cantiere) hanno già la Task di `task_names` su
# `building`, attiva o sospesa in coda. task_names: BUILD_TASK_NAMES o DEMOLISH_TASK_NAMES.
static func count_other_builders(individuals: Array, building: Building, excluding: HumanIndividual, task_names: Array[String] = JobWorkScanService.BUILD_TASK_NAMES) -> int:
	var count := 0
	for other in JobWorkScanService.workers_on_building(individuals, building, task_names):
		if other != excluding:
			count += 1
	return count


# Nuovo cantiere di `type_name` con l'ancora `anchor` nella macrocella `macro` e la porta verso `rotation`: id, villaggio,
# attesa del taglio se sulle piante vive (2026-10-18), aggiunto al mondo. La verifica del posto la fa prima la scena.
static func create_site(ctx: GameContext, rules: BuildingRules, type_name: String, macro: Vector2i, anchor: Vector2i, rotation: GameTypes.Direction) -> Building:
	var building := Building.new(rules, macro.x, macro.y, type_name)
	building.id = ctx.world.allocate_building_id()
	building.micro_x = anchor.x
	building.micro_y = anchor.y
	BuildingLifecycleService.assign_village(ctx, building)
	building.is_complete = false
	building.rotation = rotation
	building.awaiting_site_cut = not SiteCutService.cells_with_plants(ctx.world, building).is_empty()
	ctx.world.buildings.append(building)
	return building
