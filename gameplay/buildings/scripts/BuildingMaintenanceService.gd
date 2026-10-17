class_name BuildingMaintenanceService
extends RefCounted

# Manutenzione degli edifici (2026-10-10; spostata da GameScene il 2026-10-17, refactoring GameScene blocco 3a — regole
# invariate): stato "Danneggiato" che cambia, richieste di riparazione che si chiudono da sole, riparazione automatica sotto
# soglia, sgombero automatico delle macerie. Un giro al secondo (tick della scena, in futuro GameSimulation). Statico; lo
# stato che vive solo in partita sta in GameData.building_runtime (BuildingRuntimeState). Le conseguenze per la
# presentazione vanno in un GameEffects.


# Stato "Danneggiato" cambiato (2026-10-10, effetti passo 1): confronta gli edifici danneggiati CHE INCIDONO SUL MOVIMENTO
# (movement_stamina_multiplier diverso da 1) con quelli dell'ultimo giro; ogni cella toccata si ridisegna una volta sola per
# giro (mappa del movimento e pesi del cammino), perché il risparmio di stamina di un edificio danneggiato vale 1. Edifici
# religiosi (effetti passo 4): raggio e sacralità cambiano, quindi copertura delle case e layer vanno ricalcolati
# (GameData.buildings_revision) — una sola volta per giro.
static func sync_damaged_buildings(world: World, game_data: GameData, effects: GameEffects) -> void:
	if world == null or game_data == null:
		return
	var runtime := game_data.building_runtime
	var damaged_ids: Dictionary = {}
	var religious_changed := false
	for building in world.buildings:
		if building.rules == null:
			continue
		var affects_movement := not is_equal_approx(building.rules.movement_stamina_multiplier, 1.0)
		var is_religious := building.rules.religious_radius > 0
		if not affects_movement and not is_religious:
			continue
		var damaged := building.is_damaged()
		if damaged:
			damaged_ids[building.id] = true
		if damaged != runtime.last_damaged_building_ids.has(building.id):
			if affects_movement:
				effects.refresh_building_cell(building)
			if is_religious:
				religious_changed = true
	runtime.last_damaged_building_ids = damaged_ids
	if religious_changed:
		game_data.buildings_revision += 1


# Chiude da sole le richieste di riparazione non più valide (2026-10-10): Integrità piena, edificio demolito, "da demolire"
# o in miglioramento (non più completo). L'esclusione dalla riparazione automatica finisce a Integrità piena.
static func settle_repair_requests(world: World) -> void:
	if world == null:
		return
	for building in world.buildings:
		var full := building.rules != null and building.current_durability >= float(building.rules.max_durability)
		if building.repair_auto_excluded and full:
			building.repair_auto_excluded = false
		if not building.repair_requested:
			continue
		if RepairAction.is_building_repairable(building) and not full:
			continue
		building.repair_requested = false
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] Richiesta di riparazione dell'edificio #%d (%s) chiusa: %s." % [
				building.id, building.get_display_name(), "Integrità piena" if full else "edificio demolito, da demolire o in miglioramento"
			])


# Riparazione automatica (2026-10-10 — soglia JobBoardService.get_auto_repair_percent, voce delle regole di assegnazione):
# solo con l'idea dell'assegnazione, un edificio completo che deperisce (lifespan_years > 0), non da demolire né in
# miglioramento, sotto la soglia, senza riparazione richiesta o in corso e non escluso (Building.repair_auto_excluded)
# riceve la stessa richiesta del martello. Un controllo per giorno di gioco (il primo giro della coda del giorno, quindi dopo
# il calo dell'Integrità), più subito a soglia cambiata e alla prima lettura dopo un caricamento.
static func auto_request_repairs(world: World, game_data: GameData, folk: Folk, individuals: Array[HumanIndividual]) -> void:
	if world == null or game_data == null:
		return
	var runtime := game_data.building_runtime
	if not JobBoardService.is_enabled(folk):
		runtime.auto_repair_checked_day = -1
		return
	var day := game_data.get_absolute_day()
	var percent := JobBoardService.get_auto_repair_percent(game_data)
	if day == runtime.auto_repair_checked_day and percent == runtime.auto_repair_checked_percent:
		return
	runtime.auto_repair_checked_day = day
	runtime.auto_repair_checked_percent = percent
	if percent <= 0:
		return
	for building in world.buildings:
		if building.repair_requested or building.repair_auto_excluded or not RepairAction.is_building_repairable(building):
			continue
		if building.rules.lifespan_years <= 0:
			continue
		var integrity_percent: float = building.current_durability / float(building.rules.max_durability) * 100.0
		if integrity_percent >= float(percent):
			continue
		if not JobWorkScanService.workers_on_building(individuals, building, JobWorkScanService.REPAIR_TASK_NAMES).is_empty():
			continue
		building.repair_requested = true
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] Riparazione richiesta in automatico per l'edificio #%d (%s), Integrità %.1f/%d (sotto il %d%%): in coda come repair:%d." % [
				building.id, building.get_display_name(), building.current_durability, building.rules.max_durability, percent, building.id
			])


# Sgombero automatico delle macerie (2026-10-10, regola "Sgombera sempre le macerie", GameData.job_board_auto_clear_rubble):
# con la coda attiva, le macerie non già da sgomberare e non escluse (Building.rubble_auto_excluded) da segnare come col
# clic su "Sgombera". Un controllo per giorno di gioco, più subito a spunta cambiata, alla prima lettura dopo un caricamento
# e al crollo (request_rubble_check). Ritorna le macerie da segnare (la marcatura la fa chi chiama).
static func rubble_to_clear(world: World, game_data: GameData, folk: Folk) -> Array[Building]:
	var result: Array[Building] = []
	if world == null or game_data == null:
		return result
	var runtime := game_data.building_runtime
	if not JobBoardService.is_enabled(folk):
		runtime.auto_clear_checked_day = -1
		return result
	var day := game_data.get_absolute_day()
	var enabled := game_data.job_board_auto_clear_rubble
	if day == runtime.auto_clear_checked_day and enabled == runtime.auto_clear_checked_enabled:
		return result
	runtime.auto_clear_checked_day = day
	runtime.auto_clear_checked_enabled = enabled
	if not enabled:
		return result
	for building in world.buildings:
		if not building.is_rubble() or building.is_demolished or building.is_marked_for_demolition or building.rubble_auto_excluded:
			continue
		result.append(building)
	return result


# Un crollo ha appena lasciato macerie: lo sgombero automatico ricontrolla al prossimo giro invece di aspettare il giorno dopo.
static func request_rubble_check(game_data: GameData) -> void:
	if game_data != null:
		game_data.building_runtime.auto_clear_checked_day = -1
