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
	if has_equipped_member(ctx, categories, age_kind):
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
