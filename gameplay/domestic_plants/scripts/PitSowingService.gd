class_name PitSowingService
extends RefCounted

# Semina alla Fossa (2026-11-13, richiesta utente): i semi raccolti finiscono anche per terra vicino ai rifiuti. Ogni
# UNITS_PER_SOWN_LOT once di semi raccolte da terra (contatore in GameData.pit_sowing_units, col resto), una microcella
# libera entro SOWING_RADIUS dalla Fossa diventa erba per sempre, col massimo di semi (patch_capacity_max di
# SEED_RESOURCE, sempre con le stagioni). Si sceglie la Fossa più vicina a un centro di villaggio che ha ancora posto e,
# attorno, la microcella libera più vicina. Senza Fossa o senza posto il contatore aspetta. Su una microcella seminata
# poi edificata l'erba si perde (VegetationLayoutService.rebuild_from_function la toglie da MacroCellState.sown_grass_lots).
# Stato: MacroCellState.sown_grass_lots (lotto -> anno), salvato con la disposizione della vegetazione.
# Fossa generica (2026-11-15, richiesta utente): vale per ogni risorsa con SecondaryResourceRules.pit_sowing_units > 0
# (orzo e grano selvatici 500), ciascuna col suo contatore. Le risorse di un lotto seminato stanno in
# MacroCellState.sown_lot_resources. Se attorno non c'è una microcella libera, la risorsa si aggiunge a una microcella
# d'erba vicina che non la ha ancora (prima quelle già seminate, poi l'erba naturale), che da quel momento resta erba.

const SOWING_RADIUS: int = 5


# Once raccolte da terra: contano per la semina se la risorsa nasce alla Fossa. Chiamata da PickUpAction.
static func add_harvest(game_data: GameData, resource_name: String, quantity: int) -> void:
	if game_data == null or quantity <= 0 or units_per_lot(resource_name) <= 0:
		return
	game_data.pit_sowing_units[resource_name] = int(game_data.pit_sowing_units.get(resource_name, 0)) + quantity
	# Contatore nel log (2026-11-15, richiesta utente): a che punto è la prossima nascita alla Fossa.
	_log("[SEMINA] %s: +%d once raccolte da terra, contatore %d/%d verso la prossima nascita alla fossa" % [
		resource_name, quantity, int(game_data.pit_sowing_units[resource_name]), units_per_lot(resource_name)])


# Once per una semina (0: alla Fossa non nasce).
static func units_per_lot(resource_name: String) -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules.pit_sowing_units if rules != null else 0


# Risorse con once a sufficienza per una semina, in ordine di nome.
static func pending_resources(game_data: GameData) -> Array[String]:
	var names: Array[String] = []
	if game_data == null:
		return names
	for resource_name in game_data.pit_sowing_units.keys():
		var needed := units_per_lot(String(resource_name))
		if needed > 0 and int(game_data.pit_sowing_units[resource_name]) >= needed:
			names.append(String(resource_name))
	names.sort()
	return names


static var _weed_cache: Array[String] = []
static var _weed_cache_ready := false


# Risorse con SecondaryResourceRules.pit_weed_chance > 0 (2026-11-15: l'avena).
static func weed_resources() -> Array[String]:
	if not _weed_cache_ready:
		for resource_name in CaloricCalculator.list_secondary_resource_names():
			var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
			if rules != null and rules.pit_weed_chance > 0.0:
				_weed_cache.append(resource_name)
		_weed_cache_ready = true
	return _weed_cache


static func has_pending(game_data: GameData) -> bool:
	return not pending_resources(game_data).is_empty()


# Fosse che ricevono rifiuti, dalla più vicina a un centro di villaggio (senza centri: in ordine di costruzione).
static func pits_in_order(world: World, folk: Folk) -> Array[Building]:
	var pits: Array[Building] = []
	if world == null:
		return pits
	for building in world.buildings:
		if WasteDisposalService.is_waste_pit(building):
			pits.append(building)
	var centers: Array[Vector2] = []
	if folk != null:
		for village in folk.villages:
			var center := VillageService.find_center_building(world, village)
			if center != null:
				centers.append(_absolute(center))
	if centers.is_empty():
		pits.sort_custom(func(a: Building, b: Building) -> bool: return a.id < b.id)
		return pits
	var distance := func(pit: Building) -> float:
		var best := INF
		for center in centers:
			best = minf(best, _absolute(pit).distance_squared_to(center))
		return best
	pits.sort_custom(func(a: Building, b: Building) -> bool:
		var da: float = distance.call(a)
		var db: float = distance.call(b)
		return da < db if da != db else a.id < b.id)
	return pits


# Microcella libera più vicina alla Fossa (entro SOWING_RADIUS dal suo ingombro), null se non ce n'è. `blocked`: lotti
# vietati alla vegetazione (rocce, fiume, ruscelli, argilla, edifici e sentieri), preparati dalla scena. Libera vuol
# dire anche: niente erba, alberi o arbusti (lotti rivendicati), ceppi o piante morte, mucchi a terra. A parità di
# distanza decide un hash fisso della microcella e del numero di semine già fatte.
#
# Dal 2026-11-15 (Fossa generica): senza microcelle libere, la microcella d'erba più vicina che non ha ancora
# `resource_name`, prima tra quelle già seminate e poi tra l'erba naturale; null se non c'è nemmeno quella.
static func find_lot(game_data: GameData, macro_state: MacroCellState, pit: Building, blocked: Dictionary, resource_name: String) -> Variant:
	var lot: Variant = find_free_lot(game_data, macro_state, pit, blocked)
	if lot != null:
		return lot
	return _find_grass_lot(macro_state, pit, blocked, resource_name)


static func find_free_lot(game_data: GameData, macro_state: MacroCellState, pit: Building, blocked: Dictionary) -> Variant:
	if macro_state == null or pit == null or not macro_state.vegetation_layout_ready:
		return null
	var footprint := BuildingFootprint.cells_of(pit)
	var stump_lots: Dictionary = {}
	for key in macro_state.vegetation_death_exceptions.keys():
		stump_lots[Vector2i(key.x, key.y)] = true
	for key in macro_state.vegetation_cut_exceptions.keys():
		stump_lots[Vector2i(key.x, key.y)] = true
	var macro_coords := Vector2i(pit.macro_x, pit.macro_y)
	var best: Variant = null
	var best_distance := INF
	var best_tie := 0
	var limit := float(SOWING_RADIUS * SOWING_RADIUS)
	for y in range(pit.micro_y - SOWING_RADIUS, pit.micro_y + SOWING_RADIUS + 1):
		for x in range(pit.micro_x - SOWING_RADIUS, pit.micro_x + SOWING_RADIUS + 1):
			if x < 0 or y < 0 or x >= VegetationAtLotService.LOTS_PER_CELL or y >= VegetationAtLotService.LOTS_PER_CELL:
				continue
			var lot := Vector2i(x, y)
			var distance := INF
			for cell in footprint:
				distance = minf(distance, Vector2(lot - cell).length_squared())
			if distance <= 0.0 or distance > limit or distance > best_distance:
				continue
			if blocked.has(lot) or macro_state.grass_lots.has(lot) or macro_state.tree_claimed_lots.has(lot) \
					or macro_state.shrub_claimed_lots.has(lot) or stump_lots.has(lot):
				continue
			if GroundPileService.find_at(game_data, macro_coords, lot) != null:
				continue
			var tie := hash(Vector3i(x, y, macro_state.sown_grass_lots.size()))
			if distance < best_distance or tie < best_tie:
				best = lot
				best_distance = distance
				best_tie = tie
	return best


# Semina `resource_name` su `lot`: scala la soglia dal suo contatore e mette l'erba subito nella disposizione tenuta (la
# scena poi ridisegna la cella e ricalcola i lotti d'erba, LotCapacityService.refresh_grass_patch_lot_capacity).
static func sow(game_data: GameData, macro_state: MacroCellState, lot: Vector2i, resource_name: String) -> void:
	game_data.pit_sowing_units[resource_name] = int(game_data.pit_sowing_units.get(resource_name, 0)) - units_per_lot(resource_name)
	if not macro_state.sown_grass_lots.has(lot):
		macro_state.sown_grass_lots[lot] = game_data.year
	var names: Array = macro_state.sown_lot_resources.get(lot, [])
	if not names.has(resource_name):
		names.append(resource_name)
	# Infestanti (2026-11-15, avena): con una nascita di un'altra risorsa, ciascuna può spuntare sulla stessa microcella.
	for weed_name in weed_resources():
		if weed_name != resource_name and not names.has(weed_name) \
				and randf() < CaloricCalculator.get_caloric_source_rules(weed_name).pit_weed_chance:
			names.append(weed_name)
			_log("[SEMINA] %s spuntato come infestante in (%d,%d) microcella %s" % [
				weed_name, macro_state.x, macro_state.y, lot])
	macro_state.sown_lot_resources[lot] = names
	macro_state.grass_lots[lot] = true
	_log("[SEMINA] %s seminato alla fossa in (%d,%d) microcella %s; once in attesa %d" % [
		resource_name, macro_state.x, macro_state.y, lot, int(game_data.pit_sowing_units[resource_name])])


# Ripiego (2026-11-15): microcella d'erba entro SOWING_RADIUS dalla Fossa senza `resource_name` tra le seminate; prima
# quelle già seminate, poi la più vicina; a parità decide un hash fisso.
static func _find_grass_lot(macro_state: MacroCellState, pit: Building, blocked: Dictionary, resource_name: String) -> Variant:
	if macro_state == null or pit == null or not macro_state.vegetation_layout_ready:
		return null
	var footprint := BuildingFootprint.cells_of(pit)
	var limit := float(SOWING_RADIUS * SOWING_RADIUS)
	var best: Variant = null
	var best_key := Vector3(INF, INF, 0)
	for key in macro_state.grass_lots.keys():
		var lot := Vector2i(key.x, key.y)
		if blocked.has(lot) or macro_state.sown_lot_resources.get(lot, []).has(resource_name):
			continue
		var distance := INF
		for cell in footprint:
			distance = minf(distance, Vector2(lot - cell).length_squared())
		if distance <= 0.0 or distance > limit:
			continue
		var sort_key := Vector3(0.0 if macro_state.sown_grass_lots.has(lot) else 1.0, distance,
			float(hash(Vector3i(lot.x, lot.y, macro_state.sown_grass_lots.size())) % 100000))
		if sort_key < best_key:
			best = lot
			best_key = sort_key
	return best


# Righe [SEMINA] del contatore e delle nascite (2026-11-15, richiesta utente): sempre nel log col debug acceso, non nel
# canale degli eventi (DebugLogging.SHOW_GAME_EVENT_LOGS, spento).
# Spento il 2026-11-16 (richiesta utente, prove dell'acqua): riaccendere con DebugLogging.SHOW_CULTIVATION_LOGS.
static func _log(text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_CULTIVATION_LOGS:
		print(text)


static func _absolute(building: Building) -> Vector2:
	return Vector2(building.macro_x * World.WIDTH + building.micro_x, building.macro_y * World.HEIGHT + building.micro_y)
