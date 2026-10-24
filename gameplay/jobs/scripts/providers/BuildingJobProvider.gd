class_name BuildingJobProvider
extends RefCounted

# Fornitore "edifici" della lista dei lavori (2026-10-07; spostato da GameScene il 2026-10-17, refactoring GameScene blocco
# 2b): cantieri nuovi (build:<id>), cantieri di miglioramento (upgrade:<id>) ed edifici da demolire (demolish:<id>). Qui la
# parte di regola (quali lavori, chi può prenderli, chi ci lavora); assegnazione, X e Rimetti in coda restano alla scena.


# Un lavoro per edificio che ne ha uno: da demolire -> demolish (lavoratori: le task Demolisci); cantiere -> upgrade se è
# un miglioramento, altrimenti build (lavoratori: le task Costruisci). Nome della riga: quello dell'edificio per un
# cantiere nuovo, la voce di "In sospeso" ("Miglioramento · …", "Demolizione · …") per gli altri, così si distinguono.
static func collect(ctx: GameContext, provider: Dictionary, assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for building in ctx.world.buildings:
		if building.is_demolished or building.rules == null:
			continue
		var building_name := GameContext.tr_text(building.rules.building_name)
		var kind := ""
		var text := ""
		var is_assigned := false
		var open_slots := 0
		if building.is_marked_for_demolition:
			kind = "demolish"
			# Sgombero delle macerie (2026-10-10): stesso tipo delle demolizioni, "Sgombero (Macerie)".
			text = GameContext.tr_text("pending_demolish").format({"building": building_name})
			# Sgombero delle macerie (2026-10-18): origine e detriti, come la campanella.
			if building.is_rubble():
				text = GameContext.tr_text("pending_clear_rubble").format({
					"origin": building.get_rubble_origin_text(), "debris": WasteDisposalService.get_debris(building),
				})
			is_assigned = assigned["demolish"].has(building.id)
		# Detriti dei ceppi nel cantiere (2026-10-18): stesso tipo delle demolizioni (sgombero a viaggi verso la Fossa), al
		# posto del lavoro di costruzione finché non sono stati portati via.
		elif WasteDisposalService.has_site_debris(building):
			kind = "demolish"
			text = GameContext.tr_text("pending_site_debris").format({"building": building_name, "debris": WasteDisposalService.get_debris(building)})
			is_assigned = assigned["demolish"].has(building.id)
		# Svuotamento di una Fossa (2026-10-18): stesso tipo (e chiave demolish:<id>) delle demolizioni, un lavoro per edificio.
		elif building.waste_emptying and building.is_complete:
			kind = "demolish"
			text = GameContext.tr_text("pending_empty_pit").format({"building": building_name})
			is_assigned = assigned["demolish"].has(building.id)
		elif not building.is_complete:
			# In finitura (2026-10-17, giorni minimi): il lavoro è finito, nessuno ci deve andare.
			if BuildingLifecycleService.is_finishing(building):
				continue
			# Cantiere nel bosco (2026-10-18): prima il taglio (SiteCutJobProvider), il lavoro di costruzione dopo.
			if building.awaiting_site_cut:
				continue
			var is_upgrade := BuildingUpgradeService.get_upgrade_from_rules(building) != null
			kind = "upgrade" if is_upgrade else "build"
			text = GameContext.tr_text("pending_upgrade" if is_upgrade else "pending_build").format({"building": building_name})
			# Più costruttori (2026-10-17): "assigned" = almeno un costruttore (riga in "In corso"); finché i costruttori sono
			# sotto il limite (build_limit) il lavoro resta prendibile ("open_slots", JobBoardService.collect_candidates) e il
			# nome dice i posti, "Spiazzo delle feste · 1/2".
			var builders := (assigned["builders"].get(building.id, {}) as Dictionary).size()
			var limit := build_limit(ctx, building)
			is_assigned = builders > 0
			open_slots = maxi(limit - builders, 0) if is_assigned else 0
			if is_assigned and limit > 1:
				text = "%s · %d/%d" % [text, builders, limit]
				building_name = "%s · %d/%d" % [building_name, builders, limit]
		else:
			continue
		jobs.append({
			"key": "%s:%d" % [kind, building.id], "kind": kind,
			"name": building_name if kind == "build" else text, "text": text, "log_name": building_name,
			"icon": {"building_command": BuildingCommandIcon.KIND_CLEAR_RUBBLE if WasteDisposalService.is_debris_source(building) else BuildingCommandIcon.KIND_DEMOLISH} if kind == "demolish" else {"building_type": building.building_type_name},
			"map_icon_key": "clear_rubble" if WasteDisposalService.is_debris_source(building) else String(JobBoardService.ICON_KEY_BY_KIND.get(kind, "")),
			"macro": Vector2i(building.macro_x, building.macro_y), "microcell": Vector2i(building.micro_x, building.micro_y),
			"reach_target": building, "entry_kind": "building", "id": building.id, "sort": float(building.id),
			"assigned": is_assigned, "open_slots": open_slots, "hidden": false,
			"target": building, "provider": provider,
		})
		# Rimandato per materiale (2026-10-16): resta assegnato (nessun altro ci va) ma la riga va in "In coda" col motivo.
		if (kind == "build" or kind == "upgrade") and assigned["postponed"].has(building.id) and not assigned["build_active"].has(building.id):
			jobs[jobs.size() - 1]["postponed_by"] = assigned["postponed"][building.id]
	return jobs


# Costruttori al massimo per la coda dei lavori (2026-10-17): BuildingRules.max_builders, oppure 1 con la regola di
# assegnazione "Un solo costruttore per cantiere" (GameData.job_board_single_builder). Il comando manuale usa sempre
# max_builders.
static func build_limit(ctx: GameContext, building: Building) -> int:
	if ctx.game_data != null and ctx.game_data.job_board_single_builder:
		return 1
	return maxi(building.rules.max_builders if building.rules != null else 1, 1)


# Tutte le chiavi possibili dei lavori di `building` (per dimenticarne l'attesa all'assegnazione).
static func job_keys(building: Building) -> Array[String]:
	var keys: Array[String] = []
	for kind in ["build", "upgrade", "demolish"]:
		keys.append("%s:%d" % [kind, building.id])
	return keys


static func task_names(job: Dictionary) -> Array[String]:
	return JobWorkScanService.demolish_task_names_for(job["target"]) if String(job["kind"]) == "demolish" else JobWorkScanService.BUILD_TASK_NAMES


# Motivo per cui `worker` non potrebbe ricevere la task del lavoro (HumanIndividual.ASSIGN_OK se può): task di prova
# costruita con lo stesso contesto dell'assegnazione vera (per la Costruisci anche macro_state ed erba, per la Demolisci il
# solo contesto dell'edificio), mai assegnata.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var building: Building = job["target"]
	# Sgombero delle macerie e svuotamento di una Fossa (2026-10-18): la Transport dei detriti, solo con una Fossa che ha posto.
	if WasteDisposalService.has_debris_job(building):
		var clearing := WasteDisposalService.build_debris_clearing_task(ctx.world, worker, building)
		if clearing == null:
			return "nessuna Fossa dei rifiuti con posto"
		return worker.get_assign_rejection_reason(clearing, ctx.age_band_of(worker))
	var definition := TaskDefinitionCache.get_definition(building.get_resumable_task_definition_path())
	if definition == null:
		return "definizione mancante"
	var probe_context := building.get_resumable_task_context()
	if not building.is_marked_for_demolition:
		probe_context["macro_state"] = ctx.world.get_cell_state_at(building.macro_x, building.macro_y)
		probe_context["is_currently_grass"] = false
	var probe := TaskFactory.build_task(definition, probe_context)
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


# Chi ci lavora: task Costruisci o Demolisci sull'edificio, in corso o in coda.
static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	return JobWorkScanService.workers_on_building(ctx.individuals, job["target"], task_names(job))
