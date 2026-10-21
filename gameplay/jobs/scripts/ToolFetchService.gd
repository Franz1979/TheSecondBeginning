class_name ToolFetchService
extends RefCounted

# Attrezzi per i lavori della coda (2026-10-11; spostati da GameScene il 2026-10-17, refactoring GameScene blocco 2d —
# regole invariate). Categorie richieste: quelle del comando per gli ordini di zona (Taglia CHOPPING, Estrai DIGGING,
# Caccia BUTCHERING + HUNTING), quelle della ricetta per la produzione. Regola:
#   - qualcuno in età ha addosso tutte le categorie (o le sta andando a prendere, task con ZONE_ORDER_TOOL_FETCH_KEY):
#     il lavoro lo prende solo chi ce le ha; gli altri non lo vedono come prendibile (nemmeno si incamminano);
#   - nessuno: il primo che arriva dal coordinatore, con posti liberi in cintura per ciò che gli manca, prende il lavoro e
#     prima va a prendere in deposito gli attrezzi mancanti (equip_tool.tres, in cintura), poi lavora;
#   - una categoria che nessuno ha e nessun deposito ha, o nessuno con abbastanza posto in cintura: lavoro bloccato.
# Le armi da caccia si prendono in deposito solo se non usano munizioni (le lance). Gli attrezzi presi restano "in
# prestito" (HumanIndividual.borrowed_tools) e, con la regola "Riponi gli attrezzi presi per un lavoro", tornano al
# deposito quando l'individuo è libero (return_borrowed_tools). Statico e senza stato; le task create si restituiscono a
# chi chiama, che ne collega i segnali (griglia del magazzino) e aggiorna i pannelli.

const ZONE_ORDER_TOOL_FETCH_KEY := "zone_order_tool_fetch"
# Riposizione automatica di un attrezzo in prestito (return_borrowed_tools): riga "Automatico" in "In corso".
const BORROWED_TOOL_RETURN_KEY := "borrowed_tool_return"
# Sacca presa con la regola "Prendi la sacca se disponibile" (try_take_bag): "id edificio:nome" nel context, la prenotazione.
const BAG_FETCH_KEY := "bag_fetch"
# Capo preso con la regola "Indossa i capi disponibili" (try_wear_apparel): "id edificio:nome" nel context, la prenotazione.
const APPAREL_FETCH_KEY := "apparel_fetch"
# Ordine degli slot del vestiario per la regola: prima il corpo, poi calzari, testa, collo, polsi.
const APPAREL_FETCH_ORDER: Array[int] = [
	HumanIndividual.ApparelSlot.BODY, HumanIndividual.ApparelSlot.FEET, HumanIndividual.ApparelSlot.HEAD,
	HumanIndividual.ApparelSlot.NECK, HumanIndividual.ApparelSlot.WRIST_LEFT, HumanIndividual.ApparelSlot.WRIST_RIGHT,
]

# Collegamento dei segnali di deposito della task della sacca (refresh di griglia e pannelli), registrato da GameScene in
# _ready — stesso schema di CargoReturnService.unload_signal_connector. Callable(task: Task, owner: HumanIndividual).
static var storage_signal_connector: Callable = Callable()
const ZONE_ORDER_TOOL_BLOCK_KEYS := {
	TaskTypes.ToolCategory.BUTCHERING: "drawer_hunt_nobody_has_knife",
	TaskTypes.ToolCategory.HUNTING: "drawer_hunt_nobody_has_weapon",
	TaskTypes.ToolCategory.CHOPPING: "drawer_cut_nobody_has_axe",
	TaskTypes.ToolCategory.DIGGING: "drawer_quarry_nobody_has_pickaxe",
}


# Età giusta per il lavoro: caccia (`age_kind` DrawerOrderService.TYPE_HUNT) = età della task hunt_zone.tres; gli altri =
# niente neonati né bambini.
static func age_ok(ctx: GameContext, member: HumanIndividual, age_kind: String) -> bool:
	var age_band := ctx.age_band_of(member)
	if age_kind == DrawerOrderService.TYPE_HUNT:
		var definition := load(HuntZoneService.TASK_DEFINITION_PATH) as TaskDefinition
		return definition == null or definition.allowed_age_bands.is_empty() or definition.allowed_age_bands.has(int(age_band))
	return age_band != HumanTypes.AgeBand.INFANT and age_band != HumanTypes.AgeBand.CHILD


# `member` copre `category` addosso: armi da caccia con le munizioni se servono (HuntService), il resto in cintura o zaino.
static func member_covers_tool(member: HumanIndividual, category: int) -> bool:
	if category == TaskTypes.ToolCategory.HUNTING:
		return HuntService.has_hunting_weapon_available(member)
	return ToolGateService.has_tool_for(member, category)


# `member` sta andando a prendere un attrezzo di `category` per un lavoro (task in corso o in coda).
static func member_fetching_tool(member: HumanIndividual, category: int) -> bool:
	for task in JobWorkScanService.open_tasks(member):
		var fetching: Variant = task.context.get(ZONE_ORDER_TOOL_FETCH_KEY, null)
		if fetching != null and int(fetching) == category:
			return true
	return false


# Categorie tra `categories` che `member` non ha addosso e non sta già andando a prendere.
static func member_missing_categories(member: HumanIndividual, categories: Array) -> Array:
	var missing: Array = []
	for category in categories:
		if not member_covers_tool(member, int(category)) and not member_fetching_tool(member, int(category)):
			missing.append(int(category))
	return missing


# true se qualcuno in età (per `age_kind`, vedi age_ok) ha (o sta prendendo) tutte le `categories`.
static func has_equipped_member(ctx: GameContext, categories: Array, age_kind: String) -> bool:
	for member in ctx.individuals:
		if age_ok(ctx, member, age_kind) and member_missing_categories(member, categories).is_empty():
			return true
	return false


# Come has_equipped_member, ma senza chi porta già un ordine di zona dello stesso tipo (2026-10-19, richiesta utente: due
# cacciatori attrezzati già a caccia per altri ordini tenevano fermi gli ordini nuovi con "lo ha già un altro", coi
# coltelli in magazzino). Per gli ordini di zona `age_kind` è il loro tipo (DrawerOrderService.TYPE_*). Solo per
# rejection: chi è impegnato tornerà libero, quindi per la riga in coda (blocked_reason) conta ancora.
static func has_available_equipped_member(ctx: GameContext, categories: Array, age_kind: String) -> bool:
	for member in ctx.individuals:
		if age_ok(ctx, member, age_kind) and member_missing_categories(member, categories).is_empty() 				and not _holds_zone_order_of_type(ctx, member, age_kind):
			return true
	return false


# `member` porta (in corso o in coda) la serie di un ordine di zona del cassetto di tipo `order_type`.
static func _holds_zone_order_of_type(ctx: GameContext, member: HumanIndividual, order_type: String) -> bool:
	if not DrawerOrderService.is_zone_order_type(order_type):
		return false
	for task in JobWorkScanService.open_tasks(member):
		var order_id := DrawerOrderService.order_of_task(task)
		if order_id < 0:
			continue
		if String(DrawerOrderService.find(ctx.game_data, order_id).get("type", "")) == order_type:
			return true
	return false


# Posti liberi della cintura di `member`, in ordine.
static func free_belt_slots(member: HumanIndividual) -> Array[int]:
	var slots: Array[int] = []
	for slot in range(member.get_tool_slot_count()):
		if member.get_equipped_tool(slot) == "":
			slots.append(slot)
	return slots


# Attrezzi che coprono `category` e si possono prendere in deposito per un lavoro (armi: solo senza munizioni).
static func fetchable_tool_names(category: int) -> Array[String]:
	var names: Array[String] = []
	for tool_name in ToolGateService.get_tools_covering(category):
		if category == TaskTypes.ToolCategory.HUNTING:
			var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
			if rules == null or rules.required_ammo_category >= 0:
				continue
		names.append(tool_name)
	return names


# Deposito e attrezzo che copre `category` per `worker` (raggiungibile; tra i nomi, il deposito più vicino); con `worker`
# null basta che un deposito ne abbia uno. {} se nessuno.
static func find_storage_tool(world: World, worker: HumanIndividual, category: int) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for tool_name in fetchable_tool_names(category):
		var origin := worker.position if worker != null else Vector2.ZERO
		var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
		var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
		var source := WarehouseSelectionService.find_source_for_retrieval(world, origin, origin_macro, tool_name, [], 1, -1, reachability)
		if source == null:
			continue
		if worker == null:
			return {"building": source, "tool_name": tool_name}
		var offset := Vector2(Vector2i(source.macro_x, source.macro_y) - worker.home_macro_coords) * World.WIDTH
		var distance := worker.position.distance_to(Vector2(source.micro_x, source.micro_y) + offset)
		if distance < best_distance:
			best_distance = distance
			best = {"building": source, "tool_name": tool_name}
	return best


# Motivo per cui nessuno può fare un lavoro che richiede `categories` ("" = qualcuno può): una categoria che nessuno ha
# addosso e nessun deposito ha; oppure nessuno in età con abbastanza posto in cintura per prenderle.
static func blocked_reason(ctx: GameContext, categories: Array, age_kind: String) -> String:
	if categories.is_empty() or ctx.world == null or has_equipped_member(ctx, categories, age_kind):
		return ""
	var nowhere: Array = []
	for category in categories:
		var someone_has := false
		for member in ctx.individuals:
			if age_ok(ctx, member, age_kind) and member_covers_tool(member, int(category)):
				someone_has = true
				break
		if not someone_has and find_storage_tool(ctx.world, null, int(category)).is_empty():
			nowhere.append(int(category))
	if not nowhere.is_empty():
		if nowhere.size() == 1 and ZONE_ORDER_TOOL_BLOCK_KEYS.has(nowhere[0]):
			return GameContext.tr_text(String(ZONE_ORDER_TOOL_BLOCK_KEYS[nowhere[0]]))
		return GameContext.tr_text("task_assignment_nobody_has_tool").format({"tools": describe_missing_categories(nowhere)})
	var needed: Array = []
	for member in ctx.individuals:
		if not age_ok(ctx, member, age_kind):
			continue
		var missing := member_missing_categories(member, categories)
		if free_belt_slots(member).size() >= missing.size() and missing_tools_in_storage(ctx.world, member, missing):
			return ""
		for category in missing:
			if not needed.has(category):
				needed.append(category)
	return GameContext.tr_text("drawer_order_nobody_has_belt_room").format({"tools": describe_missing_categories(needed)})


static func missing_tools_in_storage(world: World, member: HumanIndividual, missing: Array) -> bool:
	for category in missing:
		if find_storage_tool(world, member, int(category)).is_empty():
			return false
	return true


# Idoneità di `worker` per gli attrezzi ("" = può): tutto addosso; oppure, se nessuno in età ha l'equipaggiamento, posti
# liberi in cintura e un deposito raggiungibile per ogni categoria che gli manca.
static func rejection(ctx: GameContext, worker: HumanIndividual, categories: Array, age_kind: String) -> String:
	var missing := member_missing_categories(worker, categories)
	if missing.is_empty():
		return ""
	if has_available_equipped_member(ctx, categories, age_kind):
		return "attrezzo mancante: lo ha già un altro"
	if free_belt_slots(worker).size() < missing.size():
		return "cintura piena per gli attrezzi da prendere"
	if not missing_tools_in_storage(ctx.world, worker, missing):
		return "attrezzo mancante e non raggiungibile in deposito"
	return ""


# Attrezzi da prendere prima del lavoro: [{"category", "building", "tool_name", "slot"}], vuoto se ha già tutto.
static func plan_fetch(world: World, worker: HumanIndividual, categories: Array) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var missing := member_missing_categories(worker, categories)
	var slots := free_belt_slots(worker)
	for index in range(mini(missing.size(), slots.size())):
		var found := find_storage_tool(world, worker, int(missing[index]))
		if found.is_empty():
			continue
		found["category"] = int(missing[index])
		found["slot"] = slots[index]
		plan.append(found)
	return plan


# Prelievi in deposito prima del lavoro appena assegnato: una task equip_tool per attrezzo, assegnata dopo il lavoro (che
# è sospendibile e va in coda personale, riprendendo a prelievo finito). Prelievo fallito (attrezzo sparito): il lavoro
# riparte lo stesso e aspetta l'attrezzo come ogni altro passo senza attrezzo. Ogni attrezzo preso è "in prestito".
# `work_label` = cosa fa dopo, per il log. Ritorna le task assegnate (chi chiama ne collega i segnali).
static func start_fetch(ctx: GameContext, worker: HumanIndividual, plan: Array[Dictionary], work_label: Variant) -> Array[Task]:
	var assigned: Array[Task] = []
	for fetch in plan:
		var building: Building = fetch["building"]
		var tool_name := String(fetch["tool_name"])
		var task := TaskBuilderService.build_equip_tool_task(worker, building, tool_name, int(fetch["slot"]))
		if task == null:
			continue
		task.context[ZONE_ORDER_TOOL_FETCH_KEY] = int(fetch["category"])
		if not worker.assign_task(task, ctx.age_band_of(worker)):
			continue
		assigned.append(task)
		worker.borrowed_tools.append({"tool_name": tool_name, "building_id": building.id})
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] #%d %s: va a prendere %s in %s #%d prima di %s." % [
				worker.id, worker.name, tool_name, building.building_type_name, building.id,
				("ordine del cassetto #%d" % int(work_label)) if work_label is int else str(work_label)
			])
	return assigned


# Regola "Riponi gli attrezzi presi per un lavoro" (2026-10-11, GameData.job_board_return_borrowed_tools): ogni individuo
# libero (nessuna task in corso né in coda) con attrezzi in prestito li riporta: per ciascuno ancora in cintura una task
# store_tool (come "Riponi attrezzo" del pannello) verso l'edificio da cui l'ha preso, se c'è ancora e lo accetta,
# altrimenti il deposito migliore. Le voci non più in cintura (rotte, spostate a mano) si tolgono; senza destinazione si
# riprova al giro dopo. Una volta al secondo. Ritorna {"member": HumanIndividual, "task": Task} per ogni task creata (chi
# chiama ne collega i segnali).
static func return_borrowed_tools(ctx: GameContext) -> Array[Dictionary]:
	var created: Array[Dictionary] = []
	if ctx.game_data == null or ctx.world == null:
		return created
	for member in ctx.individuals:
		if member.borrowed_tools.is_empty():
			continue
		var still_equipped: Array = []
		for entry in member.borrowed_tools:
			if find_belt_slot_by_name(member, String(entry.get("tool_name", ""))) != -1:
				still_equipped.append(entry)
		member.borrowed_tools = still_equipped
		if member.borrowed_tools.is_empty() or not ctx.game_data.job_board_return_borrowed_tools:
			continue
		if member.current_task != null and not member.current_task.is_finished():
			continue
		if not member.task_queue.is_empty():
			continue
		var remaining: Array = []
		for entry in member.borrowed_tools:
			var tool_name := String(entry.get("tool_name", ""))
			var slot := find_belt_slot_by_name(member, tool_name)
			var destination := _borrowed_tool_destination(ctx.world, member, tool_name, int(entry.get("building_id", -1)))
			if slot == -1 or destination == null:
				remaining.append(entry)
				continue
			var task := TaskBuilderService.build_tool_task(member, TaskBuilderService.STORE_TOOL_TASK_DEFINITION_PATH, tool_name, destination, slot)
			if task == null:
				remaining.append(entry)
				continue
			task.context[BORROWED_TOOL_RETURN_KEY] = true
			if member.current_task == null or member.current_task.is_finished():
				if not member.assign_task(task, ctx.age_band_of(member)):
					remaining.append(entry)
					continue
			else:
				TaskQueueService.push_follow_up_task(member, task)
			created.append({"member": member, "task": task})
			if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
				print("[JOB BOARD] #%d %s: ripone %s in %s #%d (preso per un lavoro)." % [
					member.id, member.name, tool_name, destination.building_type_name, destination.id
				])
		member.borrowed_tools = remaining
	return created


# Regola "Prendi la sacca se disponibile" (2026-10-19, richiesta utente — GameData.job_board_take_bag): chiamata da
# HumanIndividualActionService.resolve_idle_individual appena `individual` si libera, prima della lista dei lavori (subito
# dopo la regola del vestiario). Senza sacca in cintura e con un posto libero va a prendere in deposito la sacca col bonus
# di capacità più alto (equip_tool.tres, in cintura). La sacca resta sua: niente borrowed_tools. Le sacche che altri stanno
# già andando a prendere (BAG_FETCH_KEY) non contano, così una sacca manda una persona sola. true = task assegnata.
static func try_take_bag(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or world == null or not game_data.job_board_take_bag:
		return false
	if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD:
		return false
	if HumanCalculator.get_equipped_carry_bonus(individual.equipped_tools) > 0.0:
		return false
	var slots := free_belt_slots(individual)
	if slots.is_empty() or not JobBoardService.is_enabled(GameSettings.active_human_folk):
		return false
	var reserved := _reserved_fetches(individual, BAG_FETCH_KEY)
	var bag_names := fetchable_tool_names(TaskTypes.ToolCategory.CARRYING)
	bag_names.sort_custom(func(a: String, b: String) -> bool:
		return _carry_bonus_of(a) > _carry_bonus_of(b)
	)
	var reachability := PathfindingService.reachability_for(individual)
	for bag_name in bag_names:
		var source := _find_free_source(individual, world, bag_name, reserved, reachability)
		if source == null:
			continue
		var task := TaskBuilderService.build_equip_tool_task(individual, source, bag_name, slots[0])
		if task == null:
			return false
		task.context[BAG_FETCH_KEY] = _fetch_key(source, bag_name)
		if not individual.assign_task(task, age_band):
			return false
		if storage_signal_connector.is_valid():
			storage_signal_connector.call(task, individual)
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] #%d %s: va a prendere %s in %s #%d (regola della sacca)." % [
				individual.id, individual.name, bag_name, source.building_type_name, source.id
			])
		return true
	return false


# Regola "Indossa i capi disponibili" (2026-10-19, richiesta utente — GameData.job_board_wear_apparel): chiamata da
# resolve_idle_individual appena libero, prima della sacca e della lista dei lavori. Il primo slot vuoto in ordine APPAREL_FETCH_ORDER sceglie il deposito (il più
# vicino con un capo del suo tipo); nello STESSO deposito si prendono anche i capi per gli altri slot vuoti, così è un
# viaggio solo: prima task assegnata, le altre accodate subito dopo. Quelli che lì mancano, a un momento libero successivo.
# Scelta per stagione (2026-10-20, richiesta utente): si considerano solo i capi convenienti nella stagione corrente
# (HumanVitalsInteractionService.is_apparel_convenient: meglio dello slot vuoto), dal punteggio più alto. Il primo slot
# sceglie il deposito più vicino che ha un capo della fascia di punteggio migliore disponibile, scendendo di fascia solo
# se nessuno ce l'ha; negli altri slot, nello stesso deposito, il capo conveniente col punteggio più alto e a parità
# quello con più pezzi. Solo slot vuoti: nessuno si toglie un capo indossato (il cambio stagionale è della Hut).
# L'unità prelevata è la più consumata (BuildingStorageService.withdraw_tool_units). I capi che altri stanno già andando
# a prendere (APPAREL_FETCH_KEY) non contano. Il capo resta suo. true = task assegnata.
static func try_wear_apparel(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or world == null or not game_data.job_board_wear_apparel:
		return false
	if not HumanIndividual.is_apparel_age_band(age_band):
		return false
	var empty_slots: Array[int] = []
	for slot in APPAREL_FETCH_ORDER:
		if individual.get_equipped_apparel(slot) == "":
			empty_slots.append(slot)
	if empty_slots.is_empty() or not JobBoardService.is_enabled(GameSettings.active_human_folk):
		return false
	var reserved := _reserved_fetches(individual, APPAREL_FETCH_KEY)
	var reachability := PathfindingService.reachability_for(individual)
	var season := HumanVitalsInteractionService.current_season()
	var depot: Building = null
	var plan: Array[Dictionary] = []
	for slot in empty_slots:
		var chosen := ""
		var candidates := _convenient_apparel_for_slot(individual, slot, season)
		if depot == null:
			# Fasce di punteggio dalla migliore: il deposito più vicino con un capo della fascia; la successiva solo se
			# nessun capo della fascia è disponibile.
			var index := 0
			while index < candidates.size() and depot == null:
				var tier_score := float(candidates[index]["score"])
				var best_distance := INF
				while index < candidates.size() and is_equal_approx(float(candidates[index]["score"]), tier_score):
					var apparel_name := String(candidates[index]["name"])
					index += 1
					var source := _find_free_source(individual, world, apparel_name, reserved, reachability)
					if source == null:
						continue
					var distance := _distance_to(individual, source)
					if distance < best_distance:
						best_distance = distance
						depot = source
						chosen = apparel_name
		else:
			var chosen_score := -INF
			var chosen_free := 0
			for candidate in candidates:
				var apparel_name := String(candidate["name"])
				var score := float(candidate["score"])
				var free := BuildingStorageService.get_available_quantity(depot, apparel_name) - int(reserved.get(_fetch_key(depot, apparel_name), 0))
				if free <= 0:
					continue
				if chosen == "" or score > chosen_score + 0.0001 or (is_equal_approx(score, chosen_score) and free > chosen_free):
					chosen = apparel_name
					chosen_score = score
					chosen_free = free
		if chosen == "":
			continue
		plan.append({"slot": slot, "name": chosen})
		var key := _fetch_key(depot, chosen)
		reserved[key] = int(reserved.get(key, 0)) + 1
	if plan.is_empty():
		return false
	var tasks: Array[Task] = []
	for entry in plan:
		var task := TaskBuilderService.build_tool_task(
			individual, TaskBuilderService.EQUIP_TOOL_TASK_DEFINITION_PATH, String(entry["name"]), depot, int(entry["slot"]), true
		)
		if task == null:
			continue
		task.context[APPAREL_FETCH_KEY] = _fetch_key(depot, String(entry["name"]))
		tasks.append(task)
	if tasks.is_empty() or not individual.assign_task(tasks[0], age_band):
		return false
	# La coda riprende dall'ultima (pop_back): i seguiti entrano al contrario, così escono nell'ordine degli slot.
	for index in range(tasks.size() - 1, 0, -1):
		TaskQueueService.push_follow_up_task(individual, tasks[index])
	for task in tasks:
		if storage_signal_connector.is_valid():
			storage_signal_connector.call(task, individual)
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		var names: Array[String] = []
		for entry in plan:
			names.append(String(entry["name"]))
		print("[JOB BOARD] #%d %s: va a prendere %s in %s #%d (regola del vestiario)." % [
			individual.id, individual.name, ", ".join(names), depot.building_type_name, depot.id
		])
	return true


# Capi (categoria APPAREL) che vanno nello slot del vestiario `slot` (HumanIndividual.can_wear_in_slot).
static func apparel_names_for_slot(slot: int) -> Array[String]:
	var names: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if HumanIndividual.can_wear_in_slot(resource_name, slot):
			names.append(resource_name)
	return names


# Capi per lo slot `slot` convenienti nella stagione `season` (HumanVitalsInteractionService.is_apparel_convenient), come
# {"name", "score"} dal punteggio più alto (2026-10-20, regola del vestiario).
static func _convenient_apparel_for_slot(individual: HumanIndividual, slot: int, season: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for apparel_name in apparel_names_for_slot(slot):
		if HumanVitalsInteractionService.is_apparel_convenient(individual, apparel_name, slot, season):
			result.append({"name": apparel_name, "score": HumanVitalsInteractionService.apparel_season_score(apparel_name, season)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return result


# true se un edificio qualsiasi ha un capo per lo slot `slot` (riga "Senza vestito" della campanella).
static func has_apparel_in_storage(world: World, slot: int) -> bool:
	for apparel_name in apparel_names_for_slot(slot):
		if WarehouseSelectionService.has_retrieval_source(world, apparel_name):
			return true
	return false


# Deposito raggiungibile più vicino con almeno un `resource_name` non prenotato (`reserved`: chiave _fetch_key -> quanti).
static func _find_free_source(individual: HumanIndividual, world: World, resource_name: String, reserved: Dictionary, reachability: Callable) -> Building:
	var excluded: Array[int] = []
	while true:
		var source := WarehouseSelectionService.find_source_for_retrieval(
			world, individual.position, individual.home_macro_coords, resource_name, excluded, 1, -1, reachability
		)
		if source == null:
			return null
		if BuildingStorageService.get_available_quantity(source, resource_name) > int(reserved.get(_fetch_key(source, resource_name), 0)):
			return source
		excluded.append(source.id)
	return null


static func _fetch_key(building: Building, resource_name: String) -> String:
	return "%d:%s" % [building.id, resource_name]


static func _distance_to(individual: HumanIndividual, building: Building) -> float:
	var offset := Vector2(Vector2i(building.macro_x, building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return individual.position.distance_to(Vector2(building.micro_x, building.micro_y) + offset)


# Prelievi già prenotati da altri (task aperte con `context_key` nel context): "id edificio:nome" -> quanti.
static func _reserved_fetches(except: HumanIndividual, context_key: String) -> Dictionary:
	var reserved: Dictionary = {}
	for member in GameSettings.active_human_individuals:
		if member == except:
			continue
		for task in JobWorkScanService.open_tasks(member):
			var key: Variant = task.context.get(context_key, null)
			if key != null:
				reserved[key] = int(reserved.get(key, 0)) + 1
	return reserved


static func _carry_bonus_of(tool_name: String) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
	return rules.carry_capacity_bonus if rules != null else 0.0


# Primo slot della cintura con l'attrezzo `tool_name`, -1 se nessuno.
static func find_belt_slot_by_name(member: HumanIndividual, tool_name: String) -> int:
	if tool_name == "":
		return -1
	for slot in range(member.get_tool_slot_count()):
		if member.get_equipped_tool(slot) == tool_name:
			return slot
	return -1


# Dove riporre un attrezzo in prestito: l'edificio da cui è stato preso, se esiste ancora e lo accetta; altrimenti il
# deposito migliore (WarehouseSelectionService.find_best). null se nessuno.
static func _borrowed_tool_destination(world: World, member: HumanIndividual, tool_name: String, building_id: int) -> Building:
	var origin: Building = null
	if building_id >= 0:
		for building in world.buildings:
			if building.id == building_id:
				origin = building
				break
	if origin != null and not origin.is_demolished and origin.is_complete and BuildingStorageService.can_accept(origin, tool_name):
		return origin
	return WarehouseSelectionService.find_best(
		world, member.position, member.home_macro_coords, tool_name, 1, [], PathfindingService.reachability_for(member)
	)


# Attrezzi richiesti dalla ricetta (SecondaryResourceRules.recipe_required_tool_categories), vuoto se nessuno.
static func recipe_tool_categories(recipe: String) -> Array[TaskTypes.ToolCategory]:
	var categories: Array[TaskTypes.ToolCategory] = []
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe)
	if recipe_rules != null:
		categories.assign(recipe_rules.recipe_required_tool_categories)
	return categories


# Categorie di `categories` che nessun pipottino adulto (non neonato né bambino, le fasce escluse dalla Produce) ha in
# cintura o nello zaino (ToolGateService.has_tool_for, sola lettura) — 2026-10-09, ordini di produzione in coda.
static func categories_nobody_has(ctx: GameContext, categories: Array) -> Array:
	var missing: Array = []
	for category in categories:
		var owned := false
		for member in ctx.individuals:
			var age_band := ctx.age_band_of(member)
			if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD:
				continue
			if ToolGateService.has_tool_for(member, category):
				owned = true
				break
		if not owned:
			missing.append(category)
	return missing


# Categorie mancanti con esempi di attrezzi che le coprono (2026-09-25 — il messaggio deve dire QUALI attrezzi servono):
# "taglio (es. Coltello di pietra); caccia (es. Lancia di legno)". Una categoria senza alcun attrezzo noto compare col
# solo nome.
static func describe_missing_categories(categories: Array) -> String:
	var parts: PackedStringArray = []
	for category in categories:
		var category_name := GameContext.tr_text("tool_category_" + String(TaskTypes.ToolCategory.keys()[category]).to_lower())
		var examples: PackedStringArray = []
		for tool_name in ToolGateService.get_tools_covering(category):
			examples.append(IconRegistry.get_resource_display_name(tool_name))
		if examples.is_empty():
			parts.append(category_name)
		else:
			parts.append(GameContext.tr_text("tool_gate_category_with_examples").format({
				"category": category_name, "examples": ", ".join(examples),
			}))
	return "; ".join(parts)
