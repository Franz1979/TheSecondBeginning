class_name TrapService
extends RefCounted

# Trappole da piazzare (2026-11-07, capanna del trappoliere — prima la rete per uccelli). Generico per ogni trappola: una
# risorsa è una trappola se SecondaryResourceRules.trap_zone_job non è vuoto, e va nelle zone di lavoro con quel lavoro
# acceso (terra: "hunt", acqua: "fish"). Quante per zona: regola del WM (GameData.stock_traps_per_zone, per tipo) o il
# numero della zona (WorkArea.trap_targets), che vince. Il posto: la microcella della zona col miglior indice della preda
# (site_index), ad almeno trap_min_spacing da un'altra trappola dello stesso tipo. Montata: PlacedTrap in
# GameData.placed_traps. Lavoro "Piazza trappola": TrapJobProvider + place_trap.tres (TakeTrapAction, SetTrapAction).
# Stateless, funzioni statiche (una piccola cache del posto scelto, ricalcolata quando cambia qualcosa).

const TASK_NAME := "task_place_trap_name"
const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/place_trap.tres"
# Svuotamento (2026-11-07): lavoro "Svuota trappola" (TrapJobProvider, empty_trap.tres, EmptyTrapAction).
const EMPTY_TASK_NAME := "task_empty_trap_name"
# Stesse Task per la nassa (2026-11-08), con un nome loro: l'esperienza a fine Task va alla pesca (task_completion_effects.tres).
const FISH_TASK_NAME := "task_place_fish_trap_name"
const EMPTY_FISH_TASK_NAME := "task_empty_fish_trap_name"
const EMPTY_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/empty_trap.tres"
const CONTEXT_TRAP_ID := "trap_id"
# Chiavi del context della Task (JSON-native, salvate con la Task).
const CONTEXT_TRAP_NAME := "trap_name"
const CONTEXT_AREA_ID := "trap_area_id"
const CONTEXT_MACRO_X := "trap_macro_x"
const CONTEXT_MACRO_Y := "trap_macro_y"
const CONTEXT_LOT_X := "trap_lot_x"
const CONTEXT_LOT_Y := "trap_lot_y"
# Piazzamento ordinato col clic destro (2026-11-07): conta per la zona (numero voluto) ma non è il suo lavoro della lista.
const CONTEXT_MANUAL := "trap_manual"
# Giro delle reti di una zona (2026-11-07): la Task svuota più trappole (un EmptyTrapAction con la sua per tappa) e consegna
# una volta sola alla fine. CONTEXT_ROUND = true; CONTEXT_ROUND_CATCH = prede raccolte finora {risorsa: unità}.
const CONTEXT_ROUND := "trap_round"
const CONTEXT_ROUND_CATCH := "trap_round_catch"
# Lavoro di zona del giro (SecondaryResourceRules.trap_zone_job): reti e nasse hanno giri separati, con skill diverse.
const CONTEXT_ROUND_JOB := "trap_round_job"
# Chiave della skill per il montaggio (SkillActionEffects): chi è più bravo monta prima.
const SKILL_EFFECT_KEY := "trap"
const QUARRY_BIRDS := "birds"
# Nassa (2026-11-08): si monta solo sul ruscello e rende secondo i pesci a portata (StreamFishService.get_fish_in_reach).
const QUARRY_FISH := "fish"
# Mazzo di lacci (2026-11-09): conigli e pernici. Si monta fuori da bosco, ruscello, argilla e pietre, e in automatico si
# piazza comunque (numero del WM), senza guardare se ci sono le mandrie: le catture le leggeranno.
const QUARRY_SMALL_GAME := "small_game"
const NO_SITE := Vector2i(-1, -1)

static var _trap_names: Array[String] = []
static var _trap_names_loaded: bool = false
# Posto scelto per zona e tipo: "area_id|trap_name" -> {"key": String, "lot": Vector2i}.
static var _site_cache: Dictionary = {}


# Nomi delle risorse che sono trappole (trap_zone_job non vuoto), letti una volta.
static func list_trap_names() -> Array[String]:
	if not _trap_names_loaded:
		_trap_names_loaded = true
		for resource_name in CaloricCalculator.list_secondary_resource_names():
			var rules := get_rules(resource_name)
			if rules != null and rules.trap_zone_job != "":
				_trap_names.append(resource_name)
	return _trap_names


static func get_rules(trap_name: String) -> SecondaryResourceRules:
	return CaloricCalculator.get_caloric_source_rules(trap_name)


static func is_trap(resource_name: String) -> bool:
	var rules := get_rules(resource_name)
	return rules != null and rules.trap_zone_job != ""


# Trappole di tipo `trap_name` volute in `area`: il numero della zona se c'è, altrimenti quello del WM. 0 se la zona non ha
# acceso il lavoro della trappola.
static func target_for(game_data: GameData, area: WorkArea, trap_name: String) -> int:
	var rules := get_rules(trap_name)
	if game_data == null or area == null or rules == null or not area.enabled_jobs.has(rules.trap_zone_job):
		return 0
	if area.trap_targets.has(trap_name):
		return maxi(int(area.trap_targets[trap_name]), 0)
	return maxi(int(game_data.stock_traps_per_zone.get(trap_name, 0)), 0)


# Attrezzi per svuotare `trap_name` (SecondaryResourceRules.trap_empty_tool_categories).
static func empty_tool_categories(trap_name: String) -> Array[TaskTypes.ToolCategory]:
	var categories: Array[TaskTypes.ToolCategory] = []
	var rules := get_rules(trap_name)
	if rules != null:
		for category in rules.trap_empty_tool_categories:
			if not categories.has(category):
				categories.append(category as TaskTypes.ToolCategory)
	return categories


# Attrezzi per il giro di un lavoro di zona: quelli di tutti i tipi di trappola di quel lavoro (caccia: coltello per le reti).
static func round_tool_categories(zone_job: String) -> Array[TaskTypes.ToolCategory]:
	var categories: Array[TaskTypes.ToolCategory] = []
	for trap_name in list_trap_names():
		var rules := get_rules(trap_name)
		if rules == null or rules.trap_zone_job != zone_job:
			continue
		for category in empty_tool_categories(trap_name):
			if not categories.has(category):
				categories.append(category)
	return categories


static func is_place_task(task: Task) -> bool:
	return task != null and task.task_name in [TASK_NAME, FISH_TASK_NAME] and task.context.has(CONTEXT_TRAP_NAME)


static func is_empty_task(task: Task) -> bool:
	return task != null and task.task_name in [EMPTY_TASK_NAME, EMPTY_FISH_TASK_NAME] and task.context.has(CONTEXT_TRAP_ID)


# Trappole che la Task di svuotamento visita, in ordine: una per EmptyTrapAction (la sua o, se 0, quella del context).
static func task_trap_ids(task: Task) -> Array[int]:
	var ids: Array[int] = []
	if task == null:
		return ids
	for step in task.steps:
		if step is EmptyTrapAction:
			ids.append((step as EmptyTrapAction).resolve_trap_id(task.context))
	return ids


# Trappole già nella Task di svuotamento di qualcuno (in corso o in coda), tranne `excluded`: insieme id -> true.
static func trap_ids_being_emptied(individuals: Array[HumanIndividual], excluded: HumanIndividual = null) -> Dictionary:
	var busy := {}
	for member in individuals:
		if member == excluded:
			continue
		for task in JobWorkScanService.open_tasks(member):
			if is_empty_task(task):
				for trap_id in task_trap_ids(task):
					busy[trap_id] = true
	return busy


static func find_trap(game_data: GameData, trap_id: int) -> PlacedTrap:
	if game_data == null:
		return null
	for trap in game_data.placed_traps:
		if trap.id == trap_id:
			return trap
	return null


# true se la trappola va svuotata: piena, o la preda più vecchia è lì da trap_empty_after_days giorni.
static func needs_emptying(game_data: GameData, trap: PlacedTrap) -> bool:
	var rules := get_rules(trap.trap_name)
	if rules == null or trap.catch_days.is_empty():
		return false
	if trap.get_caught() >= rules.trap_capacity:
		return true
	return game_data.get_absolute_day() - trap.catch_days.min() >= rules.trap_empty_after_days


# Svuota la trappola (EmptyTrapAction all'arrivo): prende tutte le prede ancora dentro, toglie un uso (a zero la trappola
# sparisce) e restituisce {"resource", "quantity", "decay_fraction", "preys", "products"}: trap_catch_yield unità per preda,
# vecchie in media quanto le prede (giorni dalla cattura / day_durability della risorsa). Senza prede non consuma l'uso
# (quantity 0). "products": [{"resource", "quantity", "decay_fraction"}] da mettere nello zaino; per i lacci (2026-11-09)
# la macellazione di ogni preda (catch_products), altrimenti la sola trap_catch_resource. "preys": prede tolte.
static func empty(game_data: GameData, trap: PlacedTrap) -> Dictionary:
	var rules := get_rules(trap.trap_name)
	var result := {"resource": rules.trap_catch_resource if rules != null else "", "quantity": 0, "decay_fraction": 0.0,
		"preys": 0, "products": []}
	if rules == null or trap.catch_days.is_empty():
		return result
	var day := game_data.get_absolute_day()
	result["preys"] = trap.get_caught()
	if rules.trap_quarry == QUARRY_SMALL_GAME:
		result["products"] = catch_products(trap, day)
		for product in result["products"]:
			result["quantity"] = int(result["quantity"]) + int(product["quantity"])
		trap.catch_days.clear()
		trap.catch_species.clear()
		trap.catch_ages.clear()
		_consume_use(game_data, trap, rules, day, "ultimo svuotamento")
		game_data.placed_traps_revision += 1
		return result
	var total_age := 0
	for catch_day in trap.catch_days:
		total_age += maxi(day - catch_day, 0)
	var caught := trap.get_caught()
	var resource_rules := get_rules(rules.trap_catch_resource)
	var durability := float(resource_rules.day_durability) if resource_rules != null else 0.0
	if durability > 0.0:
		result["decay_fraction"] = clampf(float(total_age) / float(caught) / durability, 0.0, 1.0)
	result["quantity"] = caught * maxi(rules.trap_catch_yield, 0)
	result["products"] = [{"resource": result["resource"], "quantity": result["quantity"], "decay_fraction": result["decay_fraction"]}]
	trap.catch_days.clear()
	trap.catch_species.clear()
	trap.catch_ages.clear()
	_consume_use(game_data, trap, rules, day, "ultimo svuotamento")
	game_data.placed_traps_revision += 1
	return result


# Prodotti della macellazione delle prede di un laccio (2026-11-09): per preda ButcherAction.compute_yields(specie, età),
# ognuno vecchio quanto la preda (giorni dalla cattura / day_durability del prodotto). Una voce per preda e prodotto.
static func catch_products(trap: PlacedTrap, day: int) -> Array:
	var products: Array = []
	for i in range(trap.catch_days.size()):
		var species := trap.catch_species[i] if i < trap.catch_species.size() else ""
		var age_band := trap.catch_ages[i] if i < trap.catch_ages.size() else int(GameTypes.AgeBand.ADULT)
		var yields := ButcherAction.compute_yields(species, age_band)
		for resource_name in yields:
			var quantity := int(yields[resource_name])
			if quantity <= 0:
				continue
			var resource_rules := get_rules(String(resource_name))
			var durability := float(resource_rules.day_durability) if resource_rules != null else 0.0
			var decay := clampf(float(maxi(day - trap.catch_days[i], 0)) / durability, 0.0, 1.0) if durability > 0.0 else 0.0
			products.append({"resource": String(resource_name), "quantity": quantity, "decay_fraction": decay})
	return products


# Giorni di macellazione sul posto delle prede di un laccio (ritmo di ButcherAction); 0 per le altre trappole.
static func butcher_days(trap: PlacedTrap) -> float:
	var rules := get_rules(trap.trap_name)
	if rules == null or rules.trap_quarry != QUARRY_SMALL_GAME:
		return 0.0
	var days := 0.0
	for i in range(trap.catch_days.size()):
		var species := trap.catch_species[i] if i < trap.catch_species.size() else ""
		var age_band := trap.catch_ages[i] if i < trap.catch_ages.size() else int(GameTypes.AgeBand.ADULT)
		var meat := float(ButcherAction.compute_yields(species, age_band)["meat"])
		days += maxf(meat / ButcherAction.MEAT_UNITS_PER_DAY, ButcherAction.MIN_DURATION_DAYS)
	return days


# Toglie un uso alla trappola e fa ripartire il conto dell'usura a riposo. A zero usi la trappola è rotta: sparisce (le
# prede rimaste si perdono) e il posto va a riposo. true se si è rotta.
static func _consume_use(game_data: GameData, trap: PlacedTrap, rules: SecondaryResourceRules, day: int, reason: String) -> bool:
	var uses := trap.get_remaining_uses() - 1
	trap.instance[ToolInstance.KEY_REMAINING_USES] = uses
	trap.last_wear_day = day
	if uses > 0:
		return false
	game_data.placed_traps.erase(trap)
	if rules.trap_rest_days > 0:
		game_data.broken_traps.append({
			"id": trap.id, "trap_name": trap.trap_name, "macro_x": trap.macro_coords.x, "macro_y": trap.macro_coords.y,
			"lot_x": trap.lot.x, "lot_y": trap.lot.y, "broken_day": day,
		})
	log_line("%s #%d in %s %s: %s, la trappola è rotta (posto a riposo %d giorni)" % [trap.trap_name, trap.id, trap.macro_coords, trap.lot, reason, rules.trap_rest_days])
	return true


# Task "Piazza trappola" ancora aperte di tutti (in corso o in coda).
static func open_place_tasks(individuals: Array[HumanIndividual]) -> Array[Task]:
	var result: Array[Task] = []
	for member in individuals:
		if member == null:
			continue
		for task in JobWorkScanService.open_tasks(member):
			if is_place_task(task):
				result.append(task)
	return result


# Trappole di tipo `trap_name` della zona: montate più quelle in viaggio verso di lei.
static func count_for_area(game_data: GameData, individuals: Array[HumanIndividual], area: WorkArea, trap_name: String) -> int:
	var count := 0
	for trap in game_data.placed_traps:
		if trap.trap_name == trap_name and trap.work_area_id == area.id:
			count += 1
	for task in open_place_tasks(individuals):
		if String(task.context[CONTEXT_TRAP_NAME]) == trap_name and int(task.context.get(CONTEXT_AREA_ID, 0)) == area.id:
			count += 1
	return count


# Parte fissa dell'indice della preda sulla microcella (senza stagione): 0 = qui non prende niente.
static func site_index(trap_name: String, world: World, macro_coords: Vector2i, lot: Vector2i) -> float:
	var rules := get_rules(trap_name)
	if rules == null or world == null:
		return 0.0
	match rules.trap_quarry:
		QUARRY_BIRDS:
			var cell := world.get_cell_at(macro_coords.x, macro_coords.y)
			var state := world.get_cell_state_at(macro_coords.x, macro_coords.y)
			if cell == null or state == null:
				return 0.0
			return BirdPresenceService.get_site_index(state, cell.biome, lot)
		QUARRY_FISH:
			var game_data: GameData = GameSettings.active_game_data
			var cell := world.get_cell_at(macro_coords.x, macro_coords.y)
			var state := world.get_cell_state_at(macro_coords.x, macro_coords.y)
			if game_data == null or cell == null or state == null:
				return 0.0
			var fish := StreamFishService.get_fish_in_reach(state, StreamMicrocellService.get_positions(world, cell),
				macro_coords.x, macro_coords.y, lot, game_data.get_absolute_day())
			return clampf(float(fish) / float(StreamFishService.TRAP_FULL_FISH), 0.0, 1.0)
		QUARRY_SMALL_GAME:
			return 1.0
	return 0.0


# Indice del momento (stagione compresa) da quello fisso del posto.
static func current_index(trap_name: String, p_site_index: float, season: GameTypes.Season) -> float:
	var rules := get_rules(trap_name)
	if rules == null:
		return 0.0
	match rules.trap_quarry:
		QUARRY_BIRDS:
			return BirdPresenceService.apply_season(p_site_index, season)
		QUARRY_FISH, QUARRY_SMALL_GAME:
			return p_site_index
	return 0.0


# true se l'indice del momento basta per montarci una trappola (almeno "pochi").
static func is_worth_setting(trap_name: String, index: float) -> bool:
	var rules := get_rules(trap_name)
	if rules == null:
		return false
	match rules.trap_quarry:
		QUARRY_BIRDS:
			return BirdPresenceService.level_for_index(index) != BirdPresenceService.Level.NONE
		QUARRY_FISH, QUARRY_SMALL_GAME:
			return index > 0.0
	return false


# true se il tipo di trappola si può montare lì quanto a terreno: la nassa solo sul ruscello, le altre mai; i lacci
# (2026-11-09) nemmeno su alberi, argilla (se già scoperta) o pietre (`stone_lots`, da _stone_lots_of).
static func _fits_ground(rules: SecondaryResourceRules, stream_positions: Dictionary, lot: Vector2i, macro_state: MacroCellState, stone_lots: Dictionary) -> bool:
	if stream_positions.has(lot) != (rules.trap_quarry == QUARRY_FISH):
		return false
	if rules.trap_quarry != QUARRY_SMALL_GAME:
		return true
	if macro_state == null or stone_lots.has(lot):
		return false
	if macro_state.tree_claimed_lots.has(lot) and VegetationLotIndex.has_lot(macro_state, GameTypes.WorldObjectType.TREE, lot):
		return false
	return TerrainScatteredResourceService.is_resource_locked(ClayDepositService.RESOURCE_NAME) or not ClayDepositService.has_clay(macro_state, lot)


# Microcelle con pietre della cella, come insieme (stone_positions è un Array).
static func _stone_lots_of(macro_state: MacroCellState) -> Dictionary:
	var lots := {}
	if macro_state != null:
		for pos in macro_state.stone_positions:
			lots[pos] = true
	return lots


static func _stream_positions_of(world: World, macro_coords: Vector2i) -> Dictionary:
	return StreamMicrocellService.get_positions(world, world.get_cell_at(macro_coords.x, macro_coords.y))


# Posto per una nuova trappola di tipo `trap_name` in `area`: la microcella della zona col miglior indice del momento,
# senza edifici, ad almeno trap_min_spacing da ogni trappola dello stesso tipo (montate o in viaggio). NO_SITE se nessuna
# vale. Ricalcolato solo quando cambiano giorno, zona, trappole o Task aperte.
static func choose_site(game_data: GameData, world: World, individuals: Array[HumanIndividual], area: WorkArea, trap_name: String) -> Vector2i:
	var rules := get_rules(trap_name)
	if rules == null or world == null or area == null:
		return NO_SITE
	var taken: Array[Vector2i] = []
	for trap in game_data.placed_traps:
		if trap.trap_name == trap_name and trap.macro_coords == area.macro_coords:
			taken.append(trap.lot)
	for task in open_place_tasks(individuals):
		if String(task.context[CONTEXT_TRAP_NAME]) != trap_name:
			continue
		if Vector2i(int(task.context.get(CONTEXT_MACRO_X, -1)), int(task.context.get(CONTEXT_MACRO_Y, -1))) == area.macro_coords:
			taken.append(Vector2i(int(task.context.get(CONTEXT_LOT_X, -1)), int(task.context.get(CONTEXT_LOT_Y, -1))))
	var day := game_data.get_absolute_day()
	var cache_id := "%d|%s" % [area.id, trap_name]
	var resting := {}
	for broken in broken_in_macro_cell(game_data, area.macro_coords, trap_name):
		resting[Vector2i(int(broken.get("lot_x", -1)), int(broken.get("lot_y", -1)))] = true
	var cache_key := "%d|%d|%s|%d|%s" % [day, area.revision, str(taken), world.buildings.size(), str(resting.keys())]
	var cached: Dictionary = _site_cache.get(cache_id, {})
	if String(cached.get("key", "")) == cache_key:
		return cached["lot"]
	var occupied := _building_lots(world, area.macro_coords)
	var season := SeasonCalculator.get_season_for_day(game_data.current_day)
	var best := NO_SITE
	var best_index := 0.0
	var stream_positions := _stream_positions_of(world, area.macro_coords)
	var macro_state := world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
	var stone_lots := _stone_lots_of(macro_state) if rules.trap_quarry == QUARRY_SMALL_GAME else {}
	var best_score := 0.0
	for y in range(area.rect.position.y, area.rect.end.y):
		for x in range(area.rect.position.x, area.rect.end.x):
			var lot := Vector2i(x, y)
			if occupied.has(lot) or resting.has(lot) or not _fits_ground(rules, stream_positions, lot, macro_state, stone_lots) \
					or not _far_from(lot, taken, rules.trap_min_spacing):
				continue
			var index := current_index(trap_name, site_index(trap_name, world, area.macro_coords, lot), season)
			if not is_worth_setting(trap_name, index):
				continue
			# Lacci: tutti i posti valgono uguale; uno sparso a caso (stabile per microcella) invece del primo in alto a sinistra.
			var score := index + (_scatter(lot, area.id) if rules.trap_quarry == QUARRY_SMALL_GAME else 0.0)
			if score > best_score:
				best_score = score
				best_index = index
				best = lot
	if String(cached.get("key", "")).is_empty() or cached.get("lot", NO_SITE) != best:
		log_line("zona #%d %s, %s: %s" % [area.id, area.name, trap_name,
			"posto %s, indice %.2f (%d già prese o in viaggio)" % [best, best_index, taken.size()] if best != NO_SITE else "nessun posto che valga"])
	_site_cache[cache_id] = {"key": cache_key, "lot": best}
	return best


# Numero piccolo (0..0.001) e stabile per microcella e zona: sparge i posti che valgono uguale.
static func _scatter(lot: Vector2i, area_id: int) -> float:
	return float(absi(hash(Vector3i(lot.x, lot.y, area_id))) % 1000) * 0.000001


# Trappole piazzabili a mano sulla microcella (clic destro, 2026-11-07): [{"trap_name", "index", "level"}] per ogni tipo
# con una trappola pronta in un edificio e l'indice del momento almeno "pochi". Vuoto se sulla microcella c'è un edificio,
# una trappola montata o a riposo (di qualunque tipo: una sola per microcella) o un piazzamento già in viaggio.
static func placeable_traps(game_data: GameData, world: World, individuals: Array[HumanIndividual], macro_coords: Vector2i, lot: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if game_data == null or world == null:
		return result
	if not traps_at(game_data, macro_coords, lot).is_empty() or _building_lots(world, macro_coords).has(lot):
		return result
	for broken in broken_in_macro_cell(game_data, macro_coords):
		if Vector2i(int(broken.get("lot_x", -1)), int(broken.get("lot_y", -1))) == lot:
			return result
	for task in open_place_tasks(individuals):
		if Vector2i(int(task.context.get(CONTEXT_MACRO_X, -1)), int(task.context.get(CONTEXT_MACRO_Y, -1))) == macro_coords 				and Vector2i(int(task.context.get(CONTEXT_LOT_X, -1)), int(task.context.get(CONTEXT_LOT_Y, -1))) == lot:
			return result
	var season := SeasonCalculator.get_season_for_day(game_data.current_day)
	var stream_positions := _stream_positions_of(world, macro_coords)
	var macro_state := world.get_cell_state_at(macro_coords.x, macro_coords.y)
	var stone_lots := _stone_lots_of(macro_state)
	for trap_name in list_trap_names():
		var rules := get_rules(trap_name)
		if not _fits_ground(rules, stream_positions, lot, macro_state, stone_lots) or not WarehouseSelectionService.has_retrieval_source(world, trap_name):
			continue
		var index := current_index(trap_name, site_index(trap_name, world, macro_coords, lot), season)
		var level := -1
		if rules.trap_quarry == QUARRY_FISH:
			# A mano la nassa si monta anche senza pesci (2026-11-08, richiesta utente): la scelta è del giocatore.
			var cell := world.get_cell_at(macro_coords.x, macro_coords.y)
			var state := world.get_cell_state_at(macro_coords.x, macro_coords.y)
			level = int(StreamFishService.level_for_count(StreamFishService.get_fish_in_reach(
				state, stream_positions, macro_coords.x, macro_coords.y, lot, game_data.get_absolute_day()))) if state != null and cell != null else 0
		else:
			if not is_worth_setting(trap_name, index):
				continue
			if rules.trap_quarry == QUARRY_BIRDS:
				level = int(BirdPresenceService.level_for_index(index))
		result.append({"trap_name": trap_name, "index": index, "level": level, "quarry": rules.trap_quarry})
	return result


# Zona per una trappola piazzata a mano: la prima che contiene la microcella e ha acceso il lavoro della trappola (conta per
# il suo numero voluto), altrimenti 0.
static func area_for_lot(game_data: GameData, macro_coords: Vector2i, lot: Vector2i, trap_name: String) -> int:
	var rules := get_rules(trap_name)
	if game_data == null or rules == null:
		return 0
	for area in game_data.work_areas:
		if area.macro_coords == macro_coords and area.rect.has_point(lot) and area.enabled_jobs.has(rules.trap_zone_job):
			return area.id
	return 0


static func log_line(text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRAP_LOGS:
		print("[TRAP] giorno %d — %s" % [GameSettings.active_game_data.get_absolute_day() if GameSettings.active_game_data != null else -1, text])


# Monta la trappola: PlacedTrap nuova in game_data, con l'indice fisso del posto calcolato adesso.
static func place(game_data: GameData, world: World, trap_name: String, instance: Dictionary, macro_coords: Vector2i, lot: Vector2i, area_id: int) -> PlacedTrap:
	var trap := PlacedTrap.new()
	trap.id = game_data.allocate_placed_trap_id()
	trap.trap_name = trap_name
	trap.macro_coords = macro_coords
	trap.lot = lot
	trap.instance = ToolInstance.normalized(instance)
	trap.placed_day = game_data.get_absolute_day()
	trap.last_wear_day = trap.placed_day
	trap.site_index = site_index(trap_name, world, macro_coords, lot)
	trap.work_area_id = area_id
	game_data.placed_traps.append(trap)
	game_data.placed_traps_revision += 1
	return trap


# Giro giornaliero delle trappole montate (2026-11-07, GameTimeService._on_day_advanced): le prede lasciate troppo a lungo
# marciscono, poi un tiro per trappola non piena. Le trappole sono poche: costa niente.
static func advance_daily(game_data: GameData, world: World) -> void:
	if game_data == null or (game_data.placed_traps.is_empty() and game_data.broken_traps.is_empty()):
		SnareService.end_day(game_data)
		return
	var day := game_data.get_absolute_day()
	var season := SeasonCalculator.get_season_for_day(game_data.current_day)
	var changed := _end_rests(game_data, day)
	for trap in game_data.placed_traps.duplicate():
		var rules := get_rules(trap.trap_name)
		if rules == null:
			continue
		if _spoil_old_catches(trap, rules, day):
			changed = true
		# Usura a riposo (2026-11-07): trap_idle_wear_days senza svuotamenti = un uso in meno.
		if rules.trap_idle_wear_days > 0 and day - trap.last_wear_day >= rules.trap_idle_wear_days:
			changed = true
			if _consume_use(game_data, trap, rules, day, "usura senza svuotamenti"):
				continue
			log_line("%s #%d in %s %s: usura senza svuotamenti, usi rimasti %d" % [trap.trap_name, trap.id, trap.macro_coords, trap.lot, trap.get_remaining_uses()])
		if trap.get_caught() >= rules.trap_capacity:
			continue
		# Lacci (2026-11-09): una preda vera al giorno al massimo, dai passaggi del giorno (SnareService).
		if rules.trap_quarry == QUARRY_SMALL_GAME:
			var species := SnareService.roll_catch(game_data, trap, rules, randf())
			if species == "":
				continue
			var age_band := SnareService.take_prey(game_data, trap, rules, species)
			trap.catch_days.append(day)
			trap.catch_species.append(species)
			trap.catch_ages.append(age_band)
			changed = true
			log_line("%s #%d in %s %s: preso %s (ora %d/%d)" % [trap.trap_name, trap.id, trap.macro_coords, trap.lot, species, trap.get_caught(), rules.trap_capacity])
			continue
		# Nassa: i pesci a portata si contano ogni giorno, e il pescato esce davvero dal ruscello.
		var index_now: float = site_index(trap.trap_name, world, trap.macro_coords, trap.lot) if rules.trap_quarry == QUARRY_FISH else trap.site_index
		var caught := roll_catch(rules, current_index(trap.trap_name, index_now, season), randf())
		caught = mini(caught, rules.trap_capacity - trap.get_caught())
		if rules.trap_quarry == QUARRY_FISH and caught > 0:
			caught = _take_stream_fish(world, trap, caught, day)
		if caught <= 0:
			continue
		for i in range(caught):
			trap.catch_days.append(day)
		changed = true
		log_line("%s #%d in %s %s: prese %d (ora %d/%d)" % [trap.trap_name, trap.id, trap.macro_coords, trap.lot, caught, trap.get_caught(), rules.trap_capacity])
	SnareService.end_day(game_data)
	if changed:
		game_data.placed_traps_revision += 1


# Svuotamenti inutili (2026-11-07, richiesta utente): chi va a svuotare una trappola che nel frattempo è tornata vuota
# (prede marcite) o non c'è più perde il lavoro prima di arrivarci: tolto dalla coda, o fermato se è in corso. Chi la sta
# già svuotando (EmptyTrapAction iniziata o fatta) va avanti. Un giro si toglie solo se tutte le sue trappole sono vuote
# (le altre le salta strada facendo). Dopo advance_daily (GameTimeService).
static func release_needless_empty_tasks(ctx: GameContext, effects: GameEffects) -> void:
	if ctx.game_data == null:
		return
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if not is_empty_task(task) or _empty_step_reached(task):
				continue
			var trap_ids := task_trap_ids(task)
			var has_catch := false
			for trap_id in trap_ids:
				var trap := find_trap(ctx.game_data, trap_id)
				if trap != null and trap.get_caught() > 0:
					has_catch = true
					break
			if has_catch:
				continue
			log_line("#%d %s: svuotamento di %s %s tolto, le trappole sono vuote" % [member.id, member.name,
				String(task.context.get(CONTEXT_TRAP_NAME, "")), str(trap_ids)])
			if task == member.current_task:
				TaskCancelService.stop_current_task(ctx, member, effects, "trappola vuota")
			else:
				member.task_queue.erase(task)


# true se la Task di svuotamento è già arrivata al passo EmptyTrapAction (in corso o fatto).
static func _empty_step_reached(task: Task) -> bool:
	for i in range(task.steps.size()):
		if task.steps[i] is EmptyTrapAction:
			return task.current_step_index >= i
	return false


# Toglie dal ruscello fino a `count` pesci a portata della nassa e ridisegna i pesciolini se la cella è sulla mappa.
# Restituisce quanti ne ha tolti.
static func _take_stream_fish(world: World, trap: PlacedTrap, count: int, day: int) -> int:
	var cell := world.get_cell_at(trap.macro_coords.x, trap.macro_coords.y) if world != null else null
	var state := world.get_cell_state_at(trap.macro_coords.x, trap.macro_coords.y) if world != null else null
	if cell == null or state == null:
		return 0
	var positions := StreamMicrocellService.get_positions(world, cell)
	var taken := 0
	for i in range(count):
		if not StreamFishService.take_fish_in_reach(state, positions, trap.macro_coords.x, trap.macro_coords.y, trap.lot, day):
			break
		taken += 1
	var live_cell := PathfindingService.get_live_cell(trap.macro_coords)
	if taken > 0 and live_cell != null and live_cell.renderer != null:
		live_cell.renderer.set_stream_fish_counts(StreamFishService.get_fish_counts(state, positions, trap.macro_coords.x, trap.macro_coords.y, day))
	return taken


# Fine del riposo dei posti delle trappole rotte (trap_rest_days passati): la rete rotta sparisce, il posto torna libero.
static func _end_rests(game_data: GameData, day: int) -> bool:
	var kept: Array[Dictionary] = []
	for broken in game_data.broken_traps:
		var rules := get_rules(String(broken.get("trap_name", "")))
		var rest_days := rules.trap_rest_days if rules != null else 0
		if day - int(broken.get("broken_day", 0)) < rest_days:
			kept.append(broken)
		else:
			log_line("%s #%d in (%d, %d) (%d, %d): fine del riposo, il posto torna libero" % [String(broken.get("trap_name", "")), int(broken.get("id", 0)),
				int(broken.get("macro_x", 0)), int(broken.get("macro_y", 0)), int(broken.get("lot_x", 0)), int(broken.get("lot_y", 0))])
	if kept.size() == game_data.broken_traps.size():
		return false
	game_data.broken_traps = kept
	return true


# Trappole rotte (posti a riposo) della macrocella, eventualmente di un solo tipo.
static func broken_in_macro_cell(game_data: GameData, macro_coords: Vector2i, trap_name: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if game_data == null:
		return result
	for broken in game_data.broken_traps:
		if Vector2i(int(broken.get("macro_x", -1)), int(broken.get("macro_y", -1))) != macro_coords:
			continue
		if trap_name != "" and String(broken.get("trap_name", "")) != trap_name:
			continue
		result.append(broken)
	return result


# Prede prese da un tiro `roll` (0..1): niente sopra trap_daily_catch_chance × indice; dentro, la fascia si divide tra
# 1, 2, 3… prede secondo i pesi. Pura, per poterla provare a mano.
static func roll_catch(rules: SecondaryResourceRules, index: float, roll: float) -> int:
	var chance := clampf(rules.trap_daily_catch_chance * index, 0.0, 1.0)
	if chance <= 0.0 or roll >= chance:
		return 0
	var weights := rules.trap_catch_count_weights
	var total := 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return 1
	var position := roll / chance * total
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += maxf(weights[i], 0.0)
		if position < cumulative:
			return i + 1
	return weights.size()


# Toglie le prede rimaste più di trap_catch_spoil_days giorni. true se ne ha tolta qualcuna.
static func _spoil_old_catches(trap: PlacedTrap, rules: SecondaryResourceRules, day: int) -> bool:
	if rules.trap_catch_spoil_days <= 0 or trap.catch_days.is_empty():
		return false
	var kept: Array[int] = []
	var kept_species: Array[String] = []
	var kept_ages: Array[int] = []
	for i in range(trap.catch_days.size()):
		if day - trap.catch_days[i] < rules.trap_catch_spoil_days:
			kept.append(trap.catch_days[i])
			if i < trap.catch_species.size():
				kept_species.append(trap.catch_species[i])
			if i < trap.catch_ages.size():
				kept_ages.append(trap.catch_ages[i])
	var lost := trap.catch_days.size() - kept.size()
	if lost <= 0:
		return false
	trap.catch_days = kept
	trap.catch_species = kept_species
	trap.catch_ages = kept_ages
	log_line("%s #%d in %s %s: %d marcite o portate via (ora %d/%d)" % [trap.trap_name, trap.id, trap.macro_coords, trap.lot, lost, trap.get_caught(), rules.trap_capacity])
	return true


# Trappole montate sulla microcella (per l'ispezione e il disegno).
static func traps_at(game_data: GameData, macro_coords: Vector2i, lot: Vector2i) -> Array[PlacedTrap]:
	var result: Array[PlacedTrap] = []
	if game_data == null:
		return result
	for trap in game_data.placed_traps:
		if trap.macro_coords == macro_coords and trap.lot == lot:
			result.append(trap)
	return result


# Microcelle con una trappola montata nella macrocella (insieme: lot -> true). Il taglio le salta (CutZoneService, 2026-11-07):
# la rete è tesa tra quelle piante.
static func trap_lots(game_data: GameData, macro_coords: Vector2i) -> Dictionary:
	var lots := {}
	for trap in traps_in_macro_cell(game_data, macro_coords):
		lots[trap.lot] = true
	return lots


static func traps_in_macro_cell(game_data: GameData, macro_coords: Vector2i) -> Array[PlacedTrap]:
	var result: Array[PlacedTrap] = []
	if game_data == null:
		return result
	for trap in game_data.placed_traps:
		if trap.macro_coords == macro_coords:
			result.append(trap)
	return result


static func _far_from(lot: Vector2i, taken: Array[Vector2i], spacing: int) -> bool:
	for other in taken:
		if maxi(absi(other.x - lot.x), absi(other.y - lot.y)) < spacing:
			return false
	return true


# Microcelle della macrocella coperte da un edificio non calpestabile (strade e sentieri non contano).
static func _building_lots(world: World, macro_coords: Vector2i) -> Dictionary:
	var lots: Dictionary = {}
	for building in world.buildings:
		if building == null or building.is_demolished or Vector2i(building.macro_x, building.macro_y) != macro_coords:
			continue
		if building.rules != null and building.rules.walkable:
			continue
		for lot in BuildingFootprint.cells_of(building):
			lots[lot] = true
	return lots
