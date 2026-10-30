class_name BuildingLifecycleService
extends RefCounted

# Ciclo di vita degli edifici (spostato da GameScene il 2026-10-17, refactoring GameScene blocco 3b — regole invariate):
# chiusura dei lavori sull'edificio, residenti e casa persa, marcatura e annullo della demolizione, abbattimento, crollo e
# macerie, sfratti dalle case danneggiate, miglioramento sul posto (avvio e annullo), completamento della costruzione,
# centro del villaggio. Statico; le conseguenze per la presentazione (ridisegni, pannelli, avvisi, rametti del cantiere,
# selezione) vanno nel GameEffects passato da chi chiama. Dialoghi di conferma, scelta dell'orientamento e scoperte
# restano alla scena.

const RUBBLE_BUILDING_TYPE := "rubble"
# Task chiuse al crollo oltre a quelle che chiude già demolish (costruzione e demolizione).
const COLLAPSE_CLOSED_TASK_NAMES: Array[String] = ["task_produce_name", "task_repair_name", "task_rite_name", "task_leisure_rite_name"]


# --- Lavori sull'edificio ---

# Chiude, per UN individuo, le sole Task di `task_names` su `building` (2026-09-26): la current_task se lavora lì (stop),
# e le Task in coda che lavorano lì (rimosse). Tutte le altre sue Task restano intatte. Carico nello zaino (2026-09-29,
# regola unica — CargoReturnService.release_cargo, chiamata PRIMA di chiudere ciascuna Task): se la Task chiusa lo
# possiede, al suo posto (corrente o in coda) va il ritorno al magazzino più vicino; a terra solo se nessun magazzino lo
# accetta; un carico di un'altra Task resta nello zaino. true se la current_task è stata chiusa senza sostituirla: chi
# chiama rimette in moto l'individuo (resolve_freed), al momento giusto per lui.
static func close_individual_tasks(world: World, member: HumanIndividual, building: Building, task_names: Array[String]) -> bool:
	var current_closed := false
	if JobWorkScanService.task_works_on_building(member.current_task, building, task_names):
		if CargoReturnService.release_cargo(member, member.current_task, world) != CargoReturnService.Outcome.RETURNING:
			member.stop(false)
			current_closed = true
	for queued_task in member.task_queue.duplicate():
		if not JobWorkScanService.task_works_on_building(queued_task, building, task_names):
			continue
		# RETURNING: il ritorno ha già preso il posto di questa Task nella coda.
		if CargoReturnService.release_cargo(member, queued_task, world) != CargoReturnService.Outcome.RETURNING:
			member.task_queue.erase(queued_task)
	return current_closed


# Chiude le Task di `task_names` su `building` di tutti gli individui tranne `excluded`. Ritorna gli individui la cui
# current_task è stata chiusa, da rimettere in moto a cura di chi chiama (resolve_freed).
static func close_tasks_on_building(ctx: GameContext, building: Building, task_names: Array[String], excluded: HumanIndividual) -> Array[HumanIndividual]:
	var freed: Array[HumanIndividual] = []
	for other in ctx.individuals:
		if other == excluded:
			continue
		if close_individual_tasks(ctx.world, other, building, task_names):
			freed.append(other)
	return freed


# Individui rimasti senza task: riprendono dalla coda, da un bisogno o vanno in perditempo.
static func resolve_freed(ctx: GameContext, freed: Array[HumanIndividual]) -> void:
	for member in freed:
		HumanIndividualActionService.resolve_idle_individual(member, ctx.age_band_of(member), ctx.world)


# L'individuo che sta completando `building` in questo istante (il cui BuildAction corrente sta emettendo
# building_construction_completed, vedi BuildAction.completing_individual) — null se non c'è.
static func find_completing_individual(ctx: GameContext, building: Building) -> HumanIndividual:
	for candidate in ctx.individuals:
		if candidate.current_task == null:
			continue
		var action := candidate.current_task.get_current_action()
		if action is BuildAction and (action as BuildAction).target_building == building \
				and (action as BuildAction).completing_individual == candidate:
			return candidate
	return null


# --- Residenti ---

# Casa persa per demolizione o crollo (2026-10-10 — evento di felicità): chi abita in `building` perde
# HumanRules.home_lost_happiness_loss. Chiamata prima di azzerare house_id; mai dal miglioramento.
static func apply_home_lost_happiness(ctx: GameContext, building: Building) -> void:
	var rules: HumanRules = ctx.folk.human_rules_ref if ctx.folk != null else null
	if rules == null:
		return
	var residents: Array[HumanIndividual] = []
	for occupant in ctx.individuals:
		if occupant.house_id == building.id:
			residents.append(occupant)
	if residents.is_empty():
		return
	HumanVitalsInteractionService.apply_happiness_event(
		residents, -rules.home_lost_happiness_loss, {}, 0.0, -1, "casa persa (%s #%d)" % [building.get_display_name(), building.id]
	)


# Residenti di `building` fuori casa (2026-10-03): casa azzerata per chi ci abita, poi AssignHouseService li ricolloca dove
# c'è posto. Le Task di riposo in casa non puntano all'edificio (solo a una posizione): finiscono da sole. Nessun controllo
# su max_residents: nel miglioramento si chiama dopo il cambio di regole, e conta solo chi ha davvero questa casa.
static func release_residents(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	for occupant in ctx.individuals:
		if occupant.house_id == building.id:
			occupant.house_id = -1
	AssignHouseService.assign_pending_residents(ctx.world, ctx.individuals, ctx.game_data.year, {},
		"residenti liberati da %s #%d" % [building.get_display_name(), building.id])
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)


# Sfratto dalle case danneggiate (2026-10-10, effetti dello stato "Danneggiato" — passo 5): una volta al giorno, dopo il
# crollo. In ogni casa con più residenti dei posti effettivi (AssignHouseService.get_max_residents) quelli in più, scelti a
# caso, perdono la casa: calo di felicità della casa persa (HumanRules.home_lost_happiness_loss), riga [EVICTION] e avviso
# al giocatore. Poi, sempre, la normale riassegnazione delle case: riempie anche i posti tornati liberi dopo una
# riparazione sopra la soglia (gli sfrattati non tornano apposta nella stessa casa).
static func evict_damaged_house_overflow(ctx: GameContext, effects: GameEffects) -> void:
	if ctx.world == null or ctx.game_data == null:
		return
	var evicted_any := false
	for building in ctx.world.buildings:
		if building.rules == null or building.rules.max_residents <= 0 or not building.is_complete or building.is_demolished:
			continue
		# Case di nucleo (Hut, 2026-10-22): il posto in meno lo gestisce AssignHouseService (escono i figli adulti più
		# vecchi, senza penalità), non lo sfratto a caso.
		if AssignHouseService.is_nucleus_house(building):
			continue
		var residents: Array[HumanIndividual] = []
		for member in ctx.individuals:
			if member.house_id == building.id:
				residents.append(member)
		var overflow := residents.size() - AssignHouseService.get_max_residents(building)
		if overflow <= 0:
			continue
		residents.shuffle()
		var evicted: Array[HumanIndividual] = []
		for i in range(overflow):
			evicted.append(residents[i])
		var rules: HumanRules = ctx.folk.human_rules_ref if ctx.folk != null else null
		if rules != null:
			HumanVitalsInteractionService.apply_happiness_event(
				evicted, -rules.home_lost_happiness_loss, {}, 0.0, -1, "sfratto da %s #%d" % [building.get_display_name(), building.id]
			)
		for member in evicted:
			member.house_id = -1
			print("[EVICTION] #%d %s sfrattato da %s #%d: casa danneggiata, posti effettivi %d." % [
				member.id, member.name, building.get_display_name(), building.id, AssignHouseService.get_max_residents(building)
			])
		evicted_any = true
		effects.notify(
			NotificationTypes.NotificationPopupType.HOUSE_EVICTION,
			GameContext.tr_text("notification_house_eviction").format({"building": building.get_display_name(), "count": evicted.size()})
		)
	AssignHouseService.assign_pending_residents(ctx.world, ctx.individuals, ctx.game_data.year, {}, "controllo giornaliero")
	if evicted_any:
		effects.refresh_panel(GameEffects.PanelKind.POPULATION)
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)


# --- Demolizione ---

# Edificio completo segnato "da demolire" (2026-09-27). Demolizione pianificata (2026-10-14): segnarlo non lo ferma più,
# funziona finché il demolitore non comincia (start_demolition). Macerie (2026-10-18, Fossa dei rifiuti): segnate solo se
# esiste una Fossa con posto per i loro detriti (WasteDisposalService.find_pit_for_debris); una Fossa con dei rifiuti non
# si segna mai (WasteDisposalService.blocks_demolition). false = non segnato.
static func mark_for_demolition(world: World, building: Building, effects: GameEffects) -> bool:
	if (building.is_rubble() and WasteDisposalService.find_pit_for_debris(world, building) == null) \
			or WasteDisposalService.blocks_demolition(building):
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		return false
	building.is_marked_for_demolition = true
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	effects.refresh_marker(building)
	print("[DEMOLISH] Edificio #%d (%s) segnato da demolire (pianificata: funziona fino all'inizio del lavoro)." % [
		building.id, building.get_display_name()
	])
	return true


# Primo lavoro del demolitore (DemolishAction.demolition_started, 2026-10-14): da qui l'edificio è inagibile. Materiali della
# riparazione a terra (piano e richiesta chiusi), casa persa, Task di produzione chiuse, residenti fuori. Il riallineamento
# degli ordini di produzione dell'edificio lo fa chi chiama (dopo).
static func start_demolition(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	if building == null or building.is_demolished:
		return
	GroundPileService.drop_repair_materials(ctx.game_data, building, ctx.world)
	apply_home_lost_happiness(ctx, building)
	resolve_freed(ctx, close_tasks_on_building(ctx, building, JobWorkScanService.PRODUCE_TASK_NAMES, null))
	release_residents(ctx, building, effects)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	print("[DEMOLISH] Demolizione dell'edificio #%d (%s) iniziata: inagibile." % [building.id, building.get_display_name()])


# Demolizione annullata (2026-09-27): il flag "da demolire" si toglie e l'edificio torna a funzionare. I residenti liberati
# vengono ricollocati da AssignHouseService come al solito (anche in altri edifici); le Produce Task chiuse non tornano.
static func cancel_demolition(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	if building == null or building.is_demolished or not building.is_marked_for_demolition:
		return
	building.is_marked_for_demolition = false
	AssignHouseService.assign_pending_residents(ctx.world, ctx.individuals, ctx.game_data.year, {},
		"demolizione annullata: %s #%d" % [building.get_display_name(), building.id])
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
	effects.refresh_marker(building)
	print("[DEMOLISH] Demolizione dell'edificio #%d (%s) annullata." % [building.id, building.get_display_name()])


# "Annulla demolizione" (2026-09-27): solo finché il lavoro non è iniziato. Chiude le Demolish Task su questo edificio di
# tutti (correnti e in coda), poi toglie il flag. Sgombero annullato dal giocatore (2026-10-10): niente più sgombero
# automatico per quelle macerie.
static func request_cancel_demolition(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	if building == null or building.is_demolished or not building.is_marked_for_demolition:
		return
	if float(building.construction_progress.get(DemolishAction.LABOR_KEY, 0.0)) > 0.0:
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		return
	var freed := close_tasks_on_building(ctx, building, JobWorkScanService.demolish_task_names_for(building), null)
	if building.is_rubble():
		building.rubble_auto_excluded = true
	cancel_demolition(ctx, building, effects)
	resolve_freed(ctx, freed)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Fine della Demolish Task (DemolishAction.demolition_completed, 2026-09-27): abbatte l'edificio, facendo cadere in un unico
# mucchio metà dei required_materials (per difetto; il materiale di allestimento non si recupera), il deposito e il buffer
# di uscita. Se c'è un mucchio, chiede nel context della Task di accodare allo stesso individuo il trasporto al magazzino
# (HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL, consumato subito dopo questo step).
# Macerie (2026-10-18, richiesta utente): la metà persa diventa macerie, una per microcella dell'edificio
# (WasteDisposalService.demolition_debris_quantity, divisa con split_debris), già da sgomberare; il mucchio cade fuori da
# quelle celle. Con una Fossa che ha posto il demolitore, dopo il mucchio, sgombera anche le macerie (Task accodata).
# Ritorna le macerie create.
static func complete_demolition(ctx: GameContext, building: Building, demolisher: HumanIndividual, context: Dictionary, effects: GameEffects) -> Array[Building]:
	var rubbles: Array[Building] = []
	if building == null or building.is_demolished:
		return rubbles
	var salvaged: Dictionary = {}
	if building.rules != null:
		for material_name in building.rules.required_materials.keys():
			var salvaged_quantity: int = floori(float(building.rules.required_materials[material_name]) / 2.0)
			if salvaged_quantity > 0:
				salvaged[material_name] = salvaged_quantity
	var debris: int = WasteDisposalService.demolition_debris_quantity(building.rules)
	var cells: Array = BuildingFootprint.cells_of(building) if debris > 0 else []
	var source_type := building.building_type_name
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	var pile := demolish(ctx, building, effects, salvaged, demolisher, cells)
	if pile != null:
		context[HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL] = {
			"macro_x": pile.macro_coords.x, "macro_y": pile.macro_coords.y,
			"micro_x": pile.microcell.x, "micro_y": pile.microcell.y,
		}
	if debris <= 0:
		return rubbles
	rubbles = spawn_rubble_on_cells(ctx, source_type, macro_coords, cells, debris, effects, Building.RUBBLE_ORIGIN_DEMOLITION)
	for rubble in rubbles:
		rubble.is_marked_for_demolition = true
		effects.refresh_marker(rubble)
	if demolisher != null and not rubbles.is_empty() and demolisher.task_queue.size() < TaskQueueService.MAX_QUEUE_SIZE:
		var clearing := WasteDisposalService.build_debris_clearing_task(ctx.world, demolisher, rubbles[0])
		if clearing != null:
			TaskQueueService.push_suspended_task(demolisher, clearing)
			effects.wire_storage_task(clearing, demolisher)
	BuildingMaintenanceService.request_rubble_check(ctx.game_data)
	effects.refresh_pending()
	print("[DEMOLISH] Macerie lasciate dalla demolizione di %s: %d detriti su %d microcelle." % [source_type, debris, rubbles.size()])
	return rubbles


# Macerie 1x1 su `cells` (microcelle di `macro_coords`) con `total_debris` detriti divisi tra loro (split_debris): crollo e
# demolizione. Ritorna le macerie create.
static func spawn_rubble_on_cells(
	ctx: GameContext, source_type: String, macro_coords: Vector2i, cells: Array, total_debris: int, effects: GameEffects,
	origin: String = Building.RUBBLE_ORIGIN_COLLAPSE
) -> Array[Building]:
	var result: Array[Building] = []
	# Ricalcolo completo come prima (2026-10-28): le celle dell'edificio sparito senza maceria tornano libere per l'erba.
	effects.refresh_vegetation(macro_coords)
	var debris_split := split_debris(total_debris, cells.size())
	var overflow := 0
	for i in range(cells.size()):
		var share := int(debris_split[i])
		var rubble := spawn_rubble(ctx, source_type, macro_coords, cells[i], mini(share, WasteDisposalService.MAX_DEBRIS_PER_RUBBLE), effects, origin)
		if rubble != null:
			result.append(rubble)
			overflow += maxi(share - WasteDisposalService.MAX_DEBRIS_PER_RUBBLE, 0)
	# Oltre il tetto per maceria (2026-10-18): il resto in macerie nuove vicine, stessa origine; segnate come le prime
	# (la demolizione le segna dopo, chi chiama).
	if overflow > 0 and not cells.is_empty():
		var extra := put_debris_near(ctx, macro_coords, cells[0], overflow, effects, null, source_type, origin, false)
		for rubble in extra["rubbles"]:
			if not result.has(rubble):
				result.append(rubble)
	return result


# Demolizione VERA (2026-09-12): `building` viene rimosso da world.buildings, quindi nessuna doppia chiamata è possibile per
# lo stesso Building. `salvaged` = materiali recuperati (nome -> quantità) che cadono a terra insieme al contenuto;
# `completing` = chi ha appena finito di abbatterlo, la cui Task (in pieno completamento) non va chiusa. Ritorna il mucchio
# a terra, o null.
# `excluded_drop_cells` (2026-10-18): microcelle dove il mucchio non deve cadere (lì nasceranno le macerie della demolizione).
static func demolish(ctx: GameContext, building: Building, effects: GameEffects, salvaged: Dictionary = {}, completing: HumanIndividual = null, excluded_drop_cells: Array = []) -> GroundPile:
	if building == null or ctx.world == null:
		return null
	# 1) Lavori sull'edificio (costruzione e demolizione, correnti e in coda) chiusi, con la regola del carico
	# (CargoReturnService). Chi resta senza task si rimette in moto DOPO l'abbattimento (step 6), così una task in coda per lo
	# stesso edificio non può essere ripresa.
	var individuals_to_resolve := close_tasks_on_building(ctx, building, JobWorkScanService.BUILD_AND_DEMOLISH_TASK_NAMES, completing)
	# Macerie (2026-10-18): anche gli sgomberi che devono ancora prendere detriti qui.
	if building.is_rubble():
		individuals_to_resolve.append_array(close_tasks_on_building(ctx, building, JobWorkScanService.RUBBLE_CLEARING_TASK_NAMES, completing))
	# 2) Residenti: slot liberati (house_id torna a -1) solo per un edificio residenziale. Casa persa (2026-10-10): crollo o
	# cantiere annullato con residenti; per un edificio "da demolire" i residenti sono già usciti all'inizio del lavoro.
	if building.rules != null and building.rules.max_residents > 0:
		apply_home_lost_happiness(ctx, building)
		for occupant in ctx.individuals:
			if occupant.house_id == building.id:
				occupant.house_id = -1
	# 3) Produzione in corso persa (2026-09-23). Deposito e buffer di uscita cadono a terra con i materiali recuperati, dopo
	# la rimozione dall'elenco, così il mucchio può posarsi anche sulla microcella liberata.
	building.production_progress = {}
	building.production_suspended = {}
	# 4) Spazio dedicato liberato SOLO se era stato davvero riservato: is_complete (costruzione finita o piazzamento
	# istantaneo) oppure construction_progress["space_reserved"] (cantiere con il ClearAction già completato).
	var space_was_reserved: bool = building.is_complete or bool(building.construction_progress.get("space_reserved", false))
	if space_was_reserved and building.rules != null:
		var state := ctx.world.get_cell_state_at(building.macro_x, building.macro_y)
		if state != null:
			var current_building_space := state.get_dedicated_space(GameTypes.WorldObjectType.BUILDING)
			state.set_dedicated_space(GameTypes.WorldObjectType.BUILDING, max(0, current_building_space - building.rules.required_space))
	# 5) Rimozione vera dall'unica fonte di verità — is_demolished prima dell'erase, sullo stesso oggetto (chi ha una Task
	# in corso verso questo edificio tiene un riferimento diretto che resta valido anche dopo, Building.is_demolished).
	building.is_demolished = true
	ctx.world.buildings.erase(building)
	village_center_removed(ctx, building, effects)
	var pile := GroundPileService.drop_building_contents(ctx.game_data, building, ctx.world, salvaged, excluded_drop_cells)
	# 6) Individui rimasti senza task per la demolizione: riprendono dalla coda o vanno in perditempo.
	resolve_freed(ctx, individuals_to_resolve)
	# Ridisegno della cella (torna il terreno; i rametti del cantiere spariscono col ridisegno) e delle vicine, selezione
	# chiusa se era questo edificio, pannelli e barra (un centro del villaggio demolito riapre lo slot del Cerchio di sassi).
	effects.building_removed(building.id)
	effects.refresh_building_cell(building)
	effects.refresh_neighbors(building)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.BUILD_BAR)
	print("[DEMOLISH] Edificio #%d (%s) demolito — %s." % [
		building.id, building.get_display_name(),
		("mucchio a terra #%d, microcella %s" % [pile.id, str(pile.microcell)]) if pile != null else "nulla a terra"
	])
	# 7) Ricolloca chi è rimasto senza casa in altri posti liberi, poi scheda popolazione.
	AssignHouseService.assign_pending_residents(ctx.world, ctx.individuals, ctx.game_data.year, {},
		"demolito %s #%d" % [building.get_display_name(), building.id])
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	return pile


# --- Crollo ---

# Crollo degli edifici (2026-10-10): quando il calo giornaliero (WorldTimeService._advance_building_durability_decay) porta
# a 0 l'Integrità di un edificio completo che deperisce, l'edificio crolla. Una volta al giorno, prima degli sfratti.
static func collapse_ruined_buildings(ctx: GameContext, effects: GameEffects) -> void:
	if ctx.world == null:
		return
	for building in ctx.world.buildings.duplicate():
		if building.is_demolished or not building.is_complete or building.is_marked_for_demolition or building.rules == null:
			continue
		if building.rules.lifespan_years <= 0 or building.current_durability > 0.0:
			continue
		collapse(ctx, building, effects)


# Persone come nella demolizione (residenti liberati e ricollocati, lavori sull'edificio chiusi); in più si chiudono
# produzione, riparazione e riti sull'edificio e la richiesta di riparazione. Contenuto (magazzino, prodotti finiti,
# Attrezzeria) e materiali: tutto perso, nessun mucchio. Con BuildingRules.leaves_rubble al suo posto nascono le "Macerie"
# (rubble, 1x1): una per ogni microcella dell'ingombro (2026-10-18, richiesta utente — sgomberabili una per una), con i
# detriti dell'edificio divisi tra loro (split_debris); senza, le celle tornano libere. Avviso al giocatore e riga [COLLAPSE].
static func collapse(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	var display_name := building.get_display_name()
	var leaves_rubble: bool = building.rules.leaves_rubble
	var source_type := building.building_type_name
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	# Celle dell'ingombro (rettangolo già ruotato), lette prima che demolish tolga l'edificio.
	var rubble_cells: Array = BuildingFootprint.cells_of(building)
	var freed := close_tasks_on_building(ctx, building, COLLAPSE_CLOSED_TASK_NAMES, null)
	building.repair_requested = false
	# Tutto perso: demolish non trova nulla da far cadere a terra.
	building.stored_resources.clear()
	building.production_output.clear()
	building.toolkit.clear()
	# Materiali della riparazione persi anche loro (2026-10-10, passo 5); piano chiuso (la richiesta è già chiusa sopra).
	building.repair_materials.clear()
	building.repair_plan = {}
	demolish(ctx, building, effects)
	resolve_freed(ctx, freed)
	var rubble_ids: Array[int] = []
	if leaves_rubble:
		for rubble in spawn_rubble_on_cells(ctx, source_type, macro_coords, rubble_cells, WasteDisposalService.rubble_debris_quantity(source_type), effects):
			rubble_ids.append(rubble.id)
	# Crollo con macerie (2026-10-10, evento di felicità): tutto il villaggio; chi ci abitava ha già perso la casa sopra.
	if leaves_rubble:
		var collapse_rules: HumanRules = ctx.folk.human_rules_ref if ctx.folk != null else null
		if collapse_rules != null:
			HumanVitalsInteractionService.apply_happiness_event(
				ctx.individuals, -collapse_rules.collapse_village_happiness_loss, {}, 0.0, -1, "crollo di %s" % display_name
			)
	print("[COLLAPSE] Edificio #%d (%s) crollato a Integrità zero — %s." % [
		building.id, display_name, ("macerie %s, una per microcella" % str(rubble_ids)) if not rubble_ids.is_empty() else "nessuna maceria, celle libere"
	])
	effects.notify(
		NotificationTypes.NotificationPopupType.BUILDING_COLLAPSED,
		GameContext.tr_text("notification_building_collapsed" if leaves_rubble else "notification_building_lost").format({"building": display_name})
	)
	# Sgombero automatico (2026-10-10): le macerie appena nate si controllano subito.
	BuildingMaintenanceService.request_rubble_check(ctx.game_data)
	effects.refresh_pending()
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Detriti posati a terra (2026-10-18, richiesta utente): ogni mucchio con dei detriti li cede a una maceria da sgomberare
# vicina (WasteDisposalService.GROUND_DEBRIS_MERGE_RADIUS) o a una maceria nuova sulla microcella adatta più vicina
# (GroundPileService.find_rubble_microcell; senza origine, "Detriti abbandonati"), già da sgomberare. Senza posto i detriti
# restano nel mucchio e si riprova al giro dopo. Una volta al secondo (GameSimulation.tick_second).
static func settle_ground_debris(ctx: GameContext, effects: GameEffects) -> void:
	if ctx.world == null or ctx.game_data == null:
		return
	var changed := false
	for entry in WasteDisposalService.find_ground_debris(ctx.game_data):
		var pile: GroundPile = entry["pile"]
		var quantity: int = int(entry["quantity"])
		# Un mucchio di soli detriti sparisce: la sua microcella va bene per la maceria.
		var only_debris := true
		for resource_name in pile.resources.keys():
			if not WasteDisposalService.is_waste_only(String(resource_name)):
				only_debris = false
		var placed := put_debris_near(ctx, pile.macro_coords, pile.microcell, quantity, effects, pile if only_debris and pile.carcasses.is_empty() else null)
		if (placed["rubbles"] as Array).is_empty():
			continue
		WasteDisposalService.take_ground_debris(ctx.game_data, pile)
		# Detriti senza posto (tutte le celle vicine occupate): restano a terra, si riprova al giro dopo.
		var leftover := int(placed["leftover"])
		if leftover > 0:
			GroundPileService.drop_entries(ctx.game_data, pile.macro_coords, Vector2(pile.microcell) + Vector2(0.5, 0.5),
				{WasteDisposalService.DEBRIS_RESOURCE: {"quantity": leftover, "decay_fraction": 0.0}}, ctx.world)
		print("[DEBRIS] %d detriti a terra in %s %s -> %d macerie (senza posto: %d)." % [quantity, pile.macro_coords, pile.microcell, (placed["rubbles"] as Array).size(), leftover])
		changed = true
	if changed:
		BuildingMaintenanceService.request_rubble_check(ctx.game_data)
		effects.refresh_pending()
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)


# `quantity` detriti a terra vicino a `micro` (2026-10-18): riempiono le macerie da sgomberare entro
# WasteDisposalService.GROUND_DEBRIS_MERGE_RADIUS fino al tetto (MAX_DEBRIS_PER_RUBBLE), il resto va in macerie nuove
# (blocchi fino al tetto) sulle microcelle adatte più vicine (GroundPileService.find_rubble_microcell; `leaving_pile` =
# mucchio che sta per sparire, la sua cella vale). `source_type`/`origin`: edificio e origine delle macerie nuove (di base
# detriti abbandonati); `marked` = nascono già da sgomberare. Ritorna {"rubbles": macerie toccate, "leftover": detriti
# senza posto}.
static func put_debris_near(
	ctx: GameContext, macro: Vector2i, micro: Vector2i, quantity: int, effects: GameEffects, leaving_pile: GroundPile = null,
	source_type: String = "", origin: String = Building.RUBBLE_ORIGIN_DROPPED, marked: bool = true
) -> Dictionary:
	var rubbles: Array[Building] = []
	var remaining := quantity
	while remaining > 0:
		var rubble := WasteDisposalService.find_rubble_near(ctx.world, macro, micro, WasteDisposalService.GROUND_DEBRIS_MERGE_RADIUS)
		if rubble != null:
			var added := mini(remaining, WasteDisposalService.rubble_room(rubble))
			WasteDisposalService.add_debris(rubble, added)
			remaining -= added
			if not rubbles.has(rubble):
				rubbles.append(rubble)
			effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
			continue
		var cell: Variant = GroundPileService.find_rubble_microcell(ctx.game_data, ctx.world, macro, micro, leaving_pile)
		if cell == null:
			break
		leaving_pile = null
		var share := mini(remaining, WasteDisposalService.MAX_DEBRIS_PER_RUBBLE)
		rubble = spawn_rubble(ctx, source_type, macro, cell, share, effects, origin)
		if rubble == null:
			break
		remaining -= share
		rubble.is_marked_for_demolition = marked
		effects.refresh_marker(rubble)
		rubbles.append(rubble)
		# Una maceria non segnata (crollo) non è trovata da find_rubble_near: il prossimo blocco va in una nuova.
	return {"rubbles": rubbles, "leftover": remaining}


# Detriti dei ceppi di un cantiere appena ripulito (2026-10-18, richiesta utente — ClearAction.STUMP_DEBRIS_KEY): una
# maceria accanto al cantiere (put_debris_near, mai sulle sue celle, occupate dall'edificio); il costruttore, finito
# l'edificio, la sgombera se c'è una Fossa con posto (Task accodata in fondo, dopo la costruzione). Senza posto vicino i
# detriti cadono in un mucchio, che settle_ground_debris riprova a trasformare in maceria ogni secondo (nessun blocco della
# costruzione).
static func settle_site_stump_debris(ctx: GameContext, site: Building, builder: HumanIndividual, effects: GameEffects) -> void:
	if site == null or ctx.world == null:
		return
	var debris: int = int(site.construction_progress.get(ClearAction.STUMP_DEBRIS_KEY, 0))
	if debris <= 0:
		return
	site.construction_progress.erase(ClearAction.STUMP_DEBRIS_KEY)
	var macro := Vector2i(site.macro_x, site.macro_y)
	var placed := put_debris_near(
		ctx, macro, Vector2i(site.micro_x, site.micro_y), debris, effects, null, site.building_type_name, Building.RUBBLE_ORIGIN_STUMPS
	)
	# Misura temporanea (2026-10-28, scatto della pulizia del cantiere): no-op fuori da un'azione lenta.
	HumanIndividualActionService.timing_step("maceria: posto e creazione")
	var leftover := int(placed["leftover"])
	# Nessuna cella libera vicina (2026-10-18, richiesta utente — cantiere in mezzo al bosco): i detriti restano nel
	# cantiere e la costruzione aspetta che vengano portati alla Fossa (BuildAction, lavoro "Sgombero · detriti del
	# cantiere").
	if leftover > 0:
		WasteDisposalService.add_debris(site, leftover)
		effects.refresh_building_cell(site)
		effects.refresh_pending()
	if (placed["rubbles"] as Array).is_empty():
		return
	var rubble: Building = placed["rubbles"][0]
	print("[DEBRIS] %d detriti dei ceppi del cantiere #%d -> macerie #%d." % [debris, site.id, rubble.id])
	if builder != null and builder.task_queue.size() < TaskQueueService.MAX_QUEUE_SIZE:
		var clearing := WasteDisposalService.build_debris_clearing_task(ctx.world, builder, rubble)
		if clearing != null:
			TaskQueueService.push_suspended_task(builder, clearing)
			effects.wire_storage_task(clearing, builder)
	HumanIndividualActionService.timing_step("maceria: lavoro di sgombero")
	BuildingMaintenanceService.request_rubble_check(ctx.game_data)
	effects.refresh_pending()


# Rifiuti del villaggio (2026-10-18, richiesta utente): ogni WasteDisposalService.VILLAGE_WASTE_PERIOD_DAYS giorni, per
# ogni villaggio con centro, VILLAGE_WASTE_PER_INHABITANT_PER_MONTH × abitanti detriti; entrano direttamente nelle Fosse
# aperte più vicine al centro, il resto diventa "Rifiuti del villaggio" accanto al centro (put_debris_near, già da
# sgomberare). Senza centro niente. Dal giro giornaliero (GameSimulation.tick_day).
# Prima del carico ogni Fossa cala (WasteDisposalService.decay_pits, 2026-10-25), anche senza villaggi: il posto
# liberato si usa già in questo giro.
static func produce_village_waste(ctx: GameContext, effects: GameEffects) -> void:
	if ctx.world == null or ctx.game_data == null:
		return
	if ctx.game_data.get_absolute_day() % WasteDisposalService.VILLAGE_WASTE_PERIOD_DAYS != 0:
		return
	WasteDisposalService.decay_pits(ctx.world)
	if ctx.folk == null:
		return
	var first_village_id := -1
	for village in ctx.folk.villages:
		if village.center_building_id != -1:
			first_village_id = village.id
			break
	var changed := false
	for village in ctx.folk.villages:
		if village.center_building_id == -1:
			continue
		var center: Building = null
		for building in ctx.world.buildings:
			if building.id == village.center_building_id and not building.is_demolished:
				center = building
				break
		if center == null:
			continue
		var inhabitants := WasteDisposalService.village_inhabitants(village, ctx.individuals, ctx.world, first_village_id)
		var amount := inhabitants * WasteDisposalService.VILLAGE_WASTE_PER_INHABITANT_PER_MONTH
		if amount <= 0:
			continue
		var dumped := WasteDisposalService.dump_into_pits(ctx.world, center, amount)
		var leftover := amount - dumped
		if leftover > 0:
			var placed := put_debris_near(
				ctx, Vector2i(center.macro_x, center.macro_y), Vector2i(center.micro_x, center.micro_y), leftover, effects, null, "",
				Building.RUBBLE_ORIGIN_VILLAGE
			)
			leftover = int(placed["leftover"])
		print("[WASTE] %s: %d abitanti -> %d rifiuti, %d nelle Fosse, %d come macerie, %d senza posto." % [
			village.get_display_name(), inhabitants, amount, dumped, amount - dumped - leftover, leftover
		])
		changed = true
	if changed:
		BuildingMaintenanceService.request_rubble_check(ctx.game_data)
		effects.refresh_pending()
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)


# Detriti di un crollo divisi tra `parts` macerie (2026-10-18): parti intere quasi uguali, le prime `resto` con +1, ognuna
# almeno 1 (330 su 4 -> 83, 83, 82, 82).
static func split_debris(total: int, parts: int) -> Array[int]:
	var result: Array[int] = []
	if parts <= 0:
		return result
	var base: int = total / parts
	var remainder: int = total % parts
	for i in range(parts):
		result.append(maxi(base + (1 if i < remainder else 0), 1))
	return result


# Maceria 1x1 su una microcella di un edificio crollato (`source_type` = suo building_type_name), con `debris` detriti:
# edificio completo come il piazzamento istantaneo, 1 di spazio della macrocella come la microcella che occupa (le piante
# non ricrescono lì), nessuna pulizia della vegetazione (la cella era già occupata).
static func spawn_rubble(
	ctx: GameContext, source_type: String, macro_coords: Vector2i, microcell: Vector2i, debris: int, effects: GameEffects,
	origin: String = Building.RUBBLE_ORIGIN_COLLAPSE
) -> Building:
	var rules := BuildingCalculator.get_building_rules(RUBBLE_BUILDING_TYPE)
	var state := ctx.world.get_cell_state_at(macro_coords.x, macro_coords.y) if ctx.world != null else null
	if rules == null or state == null:
		return null
	var rubble := Building.new(rules, macro_coords.x, macro_coords.y, RUBBLE_BUILDING_TYPE)
	rubble.id = ctx.world.allocate_building_id()
	rubble.micro_x = microcell.x
	rubble.micro_y = microcell.y
	assign_village(ctx, rubble)
	rubble.is_complete = true
	rubble.site_setup_complete = true
	rubble.current_durability = rules.max_durability
	rubble.built_year = ctx.game_data.year
	rubble.rubble_source_name = source_type
	rubble.rubble_origin = origin
	# Detriti da portare alla Fossa dei rifiuti (2026-10-18): lo sgombero li porta via a viaggi.
	WasteDisposalService.seed_rubble_debris(rubble, debris)
	ctx.world.buildings.append(rubble)
	state.set_dedicated_space(GameTypes.WorldObjectType.BUILDING, state.get_dedicated_space(GameTypes.WorldObjectType.BUILDING) + rules.required_space)
	effects.refresh_cell(macro_coords)
	# Solo l'erba di questa microcella (2026-10-28, scatti): piante legnose qui non ce ne sono (find_rubble_microcell, o
	# celle di un edificio). Crollo e demolizione chiedono anche il ricalcolo completo (spawn_rubble_on_cells).
	effects.rubble_placed(macro_coords, microcell)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.BUILD_BAR)
	return rubble


# --- Miglioramento (2026-10-03; dati e costo: BuildingUpgradeService) ---

# Destinazione valida, edificio completo e non "da demolire", idea della destinazione scoperta. Le scorte non bloccano
# (2026-10-04): finiscono a terra all'avvio.
static func can_start_upgrade(ctx: GameContext, building: Building) -> bool:
	var target := BuildingUpgradeService.get_upgrade_rules(building)
	if target == null or building.is_demolished or not building.is_complete or building.is_marked_for_demolition:
		return false
	if target.required_idea_id != "" and (ctx.folk == null or not ctx.folk.completed_ideas.has(target.required_idea_id)):
		return false
	return true


# Trasforma l'edificio completo nel cantiere del tipo di destinazione: stesso id, posto e istanza (influenza conservata).
#   - salva in construction_progress tipo di partenza, durabilità, anno di costruzione, orientamento e lo sconto usato;
#   - scorte e materiali della riparazione a terra PRIMA della trasformazione (GroundPileService);
#   - tipo e regole nuovi, cantiere senza allestimento (site_setup_complete) e con lo spazio già riservato (stesso
#     required_space); lo sconto usato in stored_resources come materiale già consegnato;
#   - residenti fuori DOPO il passaggio a cantiere (2026-10-03, bugfix: prima li si liberava con l'edificio ancora completo
#     e AssignHouseService li rimetteva nella stessa casa);
#   - materiale recuperato (sconto non usato) in un mucchio a terra dalla posizione dell'edificio;
#   - viste come dopo una costruzione e rametti del cantiere.
# `chosen_rotation` (2026-10-04): orientamento scelto (GameTypes.Direction), -1 = resta quello dell'edificio.
static func start_upgrade(ctx: GameContext, building: Building, chosen_rotation: int, effects: GameEffects) -> void:
	var target := BuildingUpgradeService.get_upgrade_rules(building)
	if target == null:
		return
	var cost := BuildingUpgradeService.get_upgrade_cost(building.rules, target)
	var from_type := building.building_type_name
	var from_name := building.get_display_name()
	resolve_freed(ctx, close_tasks_on_building(ctx, building, JobWorkScanService.PRODUCE_TASK_NAMES, null))
	var contents_pile := GroundPileService.drop_building_contents(ctx.game_data, building, ctx.world)
	GroundPileService.drop_repair_materials(ctx.game_data, building, ctx.world)
	if contents_pile != null:
		print("[UPGRADE] Edificio #%d: scorte a terra nel mucchio #%d, microcella %s." % [building.id, contents_pile.id, str(contents_pile.microcell)])
	building.construction_progress = {
		"space_reserved": true,
		BuildingUpgradeService.UPGRADE_FROM_TYPE_KEY: from_type,
		BuildingUpgradeService.UPGRADE_FROM_DURABILITY_KEY: building.current_durability,
		BuildingUpgradeService.UPGRADE_FROM_BUILT_YEAR_KEY: building.built_year,
		BuildingUpgradeService.UPGRADE_FROM_ROTATION_KEY: int(building.rotation),
		BuildingUpgradeService.UPGRADE_CREDITED_KEY: (cost["credited"] as Dictionary).duplicate(),
	}
	# Per aggiunta (2026-10-28, bugfix): il lavoro dell'edificio di partenza è già fatto, resta solo quello del costo.
	if BuildingUpgradeService.is_additive(target):
		building.construction_progress["labor_accumulated"] = float(maxi(0, target.required_labor - int(cost["labor"])))
	if chosen_rotation >= 0:
		building.rotation = chosen_rotation as GameTypes.Direction
	building.building_type_name = from_type if building.rules == null else building.rules.upgrades_to
	building.rules = target
	building.is_complete = false
	building.site_setup_complete = true
	building.is_awaiting_material = false
	building.production_progress = {}
	building.production_suspended = {}
	for material_name in (cost["credited"] as Dictionary).keys():
		building.stored_resources[String(material_name)] = {"quantity": int(cost["credited"][material_name]), "decay_fraction": 0.0}
	# Precedenza al rientro (2026-10-22, Hut per nucleo): chi ci abitava, letto al completamento.
	var previous_residents: Array = []
	for occupant in ctx.individuals:
		if occupant.house_id == building.id:
			previous_residents.append(occupant.id)
	building.construction_progress[BuildingUpgradeService.UPGRADE_PREVIOUS_RESIDENTS_KEY] = previous_residents
	release_residents(ctx, building, effects)
	var recovered_entries: Dictionary = {}
	for material_name in (cost["recovered"] as Dictionary).keys():
		recovered_entries[String(material_name)] = {"quantity": int(cost["recovered"][material_name]), "decay_fraction": 0.0}
	var pile := GroundPileService.drop_entries(
		ctx.game_data, Vector2i(building.macro_x, building.macro_y),
		Vector2(float(building.micro_x) + 0.5, float(building.micro_y) + 0.5), recovered_entries, ctx.world
	)
	_refresh_upgraded_building_views(building, effects)
	effects.spawn_site_placeholders(building)
	print("[UPGRADE] Edificio #%d: %s -> %s, materiale recuperato %s." % [
		building.id, from_name, building.get_display_name(),
		("a terra nel mucchio #%d" % pile.id) if pile != null else "nessuno"
	])


# Annullamento del cantiere di un miglioramento (ramo dedicato di "Annulla cantiere"): chiude le Build Task sul cantiere,
# rimette tipo, regole, completezza, durabilità, anno e orientamento salvati e li cancella; i materiali consegnati oltre lo
# sconto cadono a terra; il lavoro fatto si perde. Poi residenti ricollocati. L'edificio non sparisce mai.
static func cancel_upgrade(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	var progress := building.construction_progress
	var from_type := String(progress.get(BuildingUpgradeService.UPGRADE_FROM_TYPE_KEY, ""))
	var from_rules := BuildingCalculator.get_building_rules(from_type)
	if from_rules == null:
		push_warning("BuildingLifecycleService: annullamento del miglioramento dell'edificio #%d impossibile, tipo di partenza '%s' sconosciuto." % [building.id, from_type])
		return
	var freed := close_tasks_on_building(ctx, building, JobWorkScanService.BUILD_TASK_NAMES, null)
	var credited: Dictionary = progress.get(BuildingUpgradeService.UPGRADE_CREDITED_KEY, {})
	var surplus: Dictionary = {}
	for resource_name in building.stored_resources.keys():
		var entry: Dictionary = building.stored_resources[resource_name]
		var extra: int = int(entry.get("quantity", 0)) - int(credited.get(resource_name, 0))
		if extra > 0:
			surplus[String(resource_name)] = {"quantity": extra, "decay_fraction": float(entry.get("decay_fraction", 0.0))}
	building.stored_resources.clear()
	building.building_type_name = from_type
	building.rules = from_rules
	building.is_complete = true
	building.site_setup_complete = true
	building.is_awaiting_material = false
	building.current_durability = int(progress.get(BuildingUpgradeService.UPGRADE_FROM_DURABILITY_KEY, from_rules.max_durability))
	building.built_year = int(progress.get(BuildingUpgradeService.UPGRADE_FROM_BUILT_YEAR_KEY, building.built_year))
	# Orientamento di prima (2026-10-04); assente nei salvataggi precedenti: resta quello attuale.
	building.rotation = int(progress.get(BuildingUpgradeService.UPGRADE_FROM_ROTATION_KEY, int(building.rotation))) as GameTypes.Direction
	building.construction_progress = {}
	var pile := GroundPileService.drop_entries(
		ctx.game_data, Vector2i(building.macro_x, building.macro_y),
		Vector2(float(building.micro_x) + 0.5, float(building.micro_y) + 0.5), surplus, ctx.world
	)
	resolve_freed(ctx, freed)
	AssignHouseService.assign_pending_residents(ctx.world, ctx.individuals, ctx.game_data.year, {},
		"miglioramento annullato: %s #%d" % [building.get_display_name(), building.id])
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	# Il ridisegno della cella toglie anche i rametti del cantiere (edificio di nuovo completo).
	_refresh_upgraded_building_views(building, effects)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	print("[UPGRADE] Miglioramento dell'edificio #%d annullato: torna %s, materiale %s." % [
		building.id, building.get_display_name(), ("a terra nel mucchio #%d" % pile.id) if pile != null else "nessuno a terra"
	])


# Viste dopo un cambio di tipo sul posto: disegno della cella, pannelli e barra (alza buildings_revision: copertura e layer
# di influenza).
static func _refresh_upgraded_building_views(building: Building, effects: GameEffects) -> void:
	effects.refresh_building_cell(building)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.BUILD_BAR)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)


# --- Completamento della costruzione ---

# Costruzione completata (BuildAction.building_construction_completed): gli altri individui con una task su questo edificio
# non hanno più nulla da costruire (BuildAction.on_complete ha appena tolto i materiali) e vengono liberati, zaino
# conservato; chi ha completato prosegue da sé. Valori salvati per l'annullo di un miglioramento cancellati; centro del
# villaggio, residenti di un edificio residenziale (anche fuori dalle celle vive), rametti tolti col ridisegno, vicine
# ridisegnate. Le scoperte BUILDING_COMPLETED le fa partire chi chiama.
# --- Giorni minimi di costruzione (2026-10-17, BuildingRules.min_construction_days) ---
# Il conto parte dal primo lavoro vero (BuildAction, BUILD_STARTED_DAY_KEY). Se il lavoro finisce prima dei giorni minimi
# l'edificio va "in finitura" (LABOR_DONE_KEY: materiali consumati, costruttori liberi, niente più fabbisogno né lavoro
# in coda) e si completa da solo allo scadere (complete_matured_constructions, una volta al giorno). Chiavi in
# Building.construction_progress, salvate con l'edificio.
const BUILD_STARTED_DAY_KEY := "build_started_day"
const LABOR_DONE_KEY := "labor_done"


# Segna il giorno del primo lavoro vero, se non c'è già.
static func mark_build_started(building: Building) -> void:
	if building == null or building.construction_progress.has(BUILD_STARTED_DAY_KEY) or GameSettings.active_game_data == null:
		return
	building.construction_progress[BUILD_STARTED_DAY_KEY] = GameSettings.active_game_data.get_absolute_day()


# Giorni che mancano ai giorni minimi (0 = passati; senza giorno d'inizio si conta da oggi).
static func get_min_days_left(building: Building) -> int:
	if building == null or building.rules == null or GameSettings.active_game_data == null:
		return 0
	var today := GameSettings.active_game_data.get_absolute_day()
	var started := int(building.construction_progress.get(BUILD_STARTED_DAY_KEY, today))
	return maxi(building.rules.min_construction_days - (today - started), 0)


# true se il lavoro è finito ma l'edificio aspetta i giorni minimi.
static func is_finishing(building: Building) -> bool:
	return building != null and not building.is_complete and bool(building.construction_progress.get(LABOR_DONE_KEY, false))


# Lavoro finito prima dei giorni minimi: materiali consumati, edificio in finitura.
static func enter_finishing(building: Building) -> void:
	_consume_build_materials(building)
	building.construction_progress[LABOR_DONE_KEY] = true
	building.is_awaiting_material = false


# Corpo del completamento (estratto da BuildAction.on_complete il 2026-10-17): completo, anno di costruzione, Integrità
# piena, materiali consumati, niente più attesa di materiale. Il chiamante poi avvisa la scena (segnale o chiamata
# diretta) per complete_construction.
static func finish_building(building: Building) -> void:
	building.is_complete = true
	# built_year scritto QUI, nello stesso punto di is_complete (2026-09-19): letto adesso da GameSettings.active_game_data,
	# non iniettato prima (l'anno può cambiare tra la creazione della Task e il completamento). Senza partita resta -1.
	if GameSettings.active_game_data != null:
		building.built_year = GameSettings.active_game_data.year
	if building.rules != null:
		building.current_durability = building.rules.max_durability
	_consume_build_materials(building)
	building.is_awaiting_material = false


# Consumo dei materiali di costruzione (2026-09-14): erase() di ogni voce di required_materials, non un decremento.
static func _consume_build_materials(building: Building) -> void:
	if building.rules == null:
		return
	var used: Dictionary = {}
	for resource_name in building.rules.required_materials.keys():
		if building.stored_resources.has(resource_name):
			used[resource_name] = int(building.stored_resources[resource_name].get("quantity", 0))
		building.stored_resources.erase(resource_name)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[MATERIAL USE] Building #%d %s: costruzione finita, consumati %s." % [building.id, building.get_display_name(), str(used)])


# Controllo giornaliero: completa gli edifici in finitura con i giorni minimi passati. Ritorna quelli completati, per cui
# la scena chiama il suo gestore di fine costruzione (come il segnale di BuildAction).
static func complete_matured_constructions(world: World) -> Array[Building]:
	var matured: Array[Building] = []
	if world == null:
		return matured
	for building in world.buildings:
		if building.is_demolished or not is_finishing(building) or get_min_days_left(building) > 0:
			continue
		finish_building(building)
		matured.append(building)
		if DebugLogging.ENABLED and (DebugLogging.SHOW_TRANSPORT_BUILD_LOGS or DebugLogging.SHOW_BUILDERS_LOGS):
			print("[BUILD] Edificio #%d (%s): finitura terminata, edificio completo." % [building.id, building.building_type_name])
	return matured


static func complete_construction(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	if building == null:
		return
	var completing := find_completing_individual(ctx, building)
	# Più costruttori (2026-10-17): chi stava costruendo lì riceve gli effetti di fine costruzione come chi la completa
	# (task_completion_effects.tres), prima che la sua task venga chiusa.
	for other in ctx.individuals:
		var other_task := other.current_task
		if other == completing or other_task == null or other_task.is_finished():
			continue
		var other_step := other_task.get_current_action()
		if JobWorkScanService.BUILD_TASK_NAMES.has(other_task.task_name) and other_step is BuildAction \
				and (other_step as BuildAction).target_building == building:
			TaskCompletionEffectService.apply_effects(other, other_task)
			if DebugLogging.ENABLED and (DebugLogging.SHOW_TRANSPORT_BUILD_LOGS or DebugLogging.SHOW_BUILDERS_LOGS):
				print("[BUILD] Edificio #%d completato da #%d: effetti di fine costruzione anche a #%d %s (skill_builder ora %.1f)." % [
					building.id, completing.id if completing != null else -1, other.id, other.name, float(other.skill_builder)
				])
	resolve_freed(ctx, close_tasks_on_building(ctx, building, JobWorkScanService.BUILD_TASK_NAMES, completing))
	var previous_residents: Array = building.construction_progress.get(BuildingUpgradeService.UPGRADE_PREVIOUS_RESIDENTS_KEY, [])
	for upgrade_key in BuildingUpgradeService.UPGRADE_KEYS:
		building.construction_progress.erase(upgrade_key)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD] Edificio #%d completato! (anno=%d)" % [building.id, building.built_year])
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	# Il primo deposito completo sblocca gli altri edifici nella barra (2026-09-29).
	effects.refresh_panel(GameEffects.PanelKind.BUILD_BAR)
	village_center_completed(ctx, building, effects)
	if building.rules != null and building.rules.max_residents > 0:
		AssignHouseService.assign_pending_residents(ctx.world, ctx.individuals, ctx.game_data.year, {building.id: previous_residents},
			"%s completato: %s #%d" % ["miglioramento" if not previous_residents.is_empty() else "edificio", building.get_display_name(), building.id])
		effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	effects.refresh_neighbors(building)
	effects.refresh_building_cell(building)


# --- Villaggio (2026-10-12, Folk/Village) ---

# Villaggio di un edificio appena piazzato (passo 3): quello del centro più vicino; nessuno (-1) se non esiste ancora un
# villaggio — lo adotterà il primo centro completato (VillageService.adopt_orphan_buildings).
static func assign_village(ctx: GameContext, building: Building) -> void:
	var village := VillageService.find_village_for_building(ctx.folk, ctx.world, building)
	building.village_id = village.id if village != null else -1


# Centro del villaggio completato: fonda un villaggio o ricollega quello rimasto senza centro (VillageService), poi avviso e
# scheda popolazione. Un candidato completato in un villaggio che ha già il centro (cerchio del consiglio, 2026-10-26) resta
# candidato: solo l'avviso che vi si può spostare il centro dal pannello. No-op per edifici che non possono fare da centro.
static func village_center_completed(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	if building.rules == null or not building.rules.can_be_village_center():
		return
	var result := VillageService.on_village_center_completed(ctx.folk, ctx.world, building, ctx.individuals)
	var village: Village = result["village"]
	if result["outcome"] == VillageService.CenterOutcome.NONE and village == null:
		var move_village := VillageService.get_center_move_village(ctx.folk, ctx.world, building)
		if move_village != null:
			_notify_village_center_changed(GameContext.tr_text("notification_village_center_movable").format({
				"village": move_village.get_display_name(), "building": building.get_display_name(),
			}), effects)
		return
	match result["outcome"]:
		VillageService.CenterOutcome.FOUNDED:
			# Primo villaggio: la nascita la racconta già la scoperta del Cerchio di sassi (first_thought_building.tres),
			# niente avviso doppio.
			if ctx.folk.villages.size() == 1:
				effects.refresh_panel(GameEffects.PanelKind.POPULATION)
				return
			_notify_village_center_changed(GameContext.tr_text("notification_village_founded").format({
				"village": village.get_display_name(), "building": building.get_display_name(),
			}), effects)
		VillageService.CenterOutcome.RECONNECTED:
			_notify_village_center_changed(GameContext.tr_text("notification_village_center_restored").format({"village": village.get_display_name()}), effects)
		_:
			return
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)


# Centro del villaggio demolito o crollato: il villaggio resta in vita senza centro (VillageService). Un candidato che non
# era il centro (find_village_by_center null) non cambia nulla.
static func village_center_removed(ctx: GameContext, building: Building, effects: GameEffects) -> void:
	if building.rules == null or not building.rules.can_be_village_center():
		return
	var village := VillageService.on_village_center_removed(ctx.folk, building)
	if village != null:
		_notify_village_center_changed(GameContext.tr_text("notification_village_center_lost").format({"village": village.get_display_name()}), effects)


# Sposta qui il centro del villaggio (2026-10-26, cerchio del consiglio), dopo la conferma della scena: ricontrolla che sia
# ancora possibile (VillageService.get_center_move_village), sposta e battezza (`village_name`, se il villaggio non ha
# ancora un nome). true se il centro è stato spostato.
static func move_village_center(ctx: GameContext, building: Building, village_name: String, effects: GameEffects) -> bool:
	var village := VillageService.get_center_move_village(ctx.folk, ctx.world, building)
	if village == null:
		return false
	VillageService.move_center(village, building, village_name)
	_notify_village_center_changed(GameContext.tr_text("notification_village_center_moved").format({
		"village": village.get_display_name(), "building": building.get_display_name(),
	}), effects)
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
	return true


# Battesimo del villaggio dal pannello del centro (2026-10-26), dopo la conferma della scena. true se il nome è stato dato.
static func name_village(ctx: GameContext, building: Building, village_name: String, effects: GameEffects) -> bool:
	var village := VillageService.get_nameable_village(ctx.folk, ctx.world, building)
	if village == null or not VillageService.name_village(village, village_name):
		return false
	_notify_village_center_changed(GameContext.tr_text("notification_village_named").format({"village": village.get_display_name()}), effects)
	effects.refresh_panel(GameEffects.PanelKind.POPULATION)
	effects.refresh_panel(GameEffects.PanelKind.BUILDINGS)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
	return true


static func _notify_village_center_changed(text: String, effects: GameEffects) -> void:
	print("[VILLAGE] %s" % text)
	effects.notify(NotificationTypes.NotificationPopupType.VILLAGE_CENTER_CHANGED, text)
