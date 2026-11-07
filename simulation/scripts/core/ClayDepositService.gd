class_name ClayDepositService
extends RefCounted

# Giacimenti di argilla (2026-11-03, richiesta utente — Vasellame, passo 2). Stateless, funzioni statiche. Tutta la logica
# dell'argilla sta qui: il refactoring che ridurrà il ruolo della macrocella dovrà cambiare solo questo punto.
#
# Presenza: sempre dove c'è acqua (has_water), mai altrove. Non occupa dedicated_space: lo spazio occupato entra nella
# mortalità delle piante, e l'argilla non deve cambiare la vegetazione.
# Chiazze: alla prima attivazione della cella, da 1 a 3, ciascuna con centro sulla riva e cresciuta a caso entro
# BAND_RADIUS microcelle dall'acqua: una striscia che segue il ruscello. Poi le posizioni sono salvate (MacroCellState.clay_positions), come le
# rocce: il layout resta stabile anche se cambiano gli edifici o l'algoritmo.
# Argilla: la quantità iniziale di ogni microcella si ricava dalla posizione e non si salva (stesso principio di
# RockStoneService). Il giacimento si esaurisce e non si rinnova: l'argilla si forma in tempi geologici. Una microcella
# esaurita esce da clay_positions e torna terreno normale: ci si costruisce e le piante possono tornare.
# Calpestabile, ma non ci si costruisce sopra (BuildingVerificationService) e le piante non ci nascono (GameScene,
# `occupied` di _refresh_resource_visuals). Risorsa bloccata da required_idea_id (clay.tres, idea "pottery"): si vede
# sempre, ma fino all'idea l'ispezione dice "Risorsa sconosciuta", come le erbe medicinali.

const RESOURCE_NAME := "clay"

const PATCH_COUNT_MIN: int = 1
const PATCH_COUNT_MAX: int = 3
const PATCH_SIZE_MIN: int = 20
const PATCH_SIZE_MAX: int = 60
# Distanza massima dalle rive di ogni microcella di una chiazza.
const BAND_RADIUS: int = 3
const UNITS_MIN: int = 200
const UNITS_MAX: int = 400
# Resa di un'estrazione (2026-11-04, QuarryAction): lo stesso spazio di una pietra.
const UNITS_PER_EXTRACTION: int = 50

const _NEIGHBORS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const _NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


# true se la macrocella di terra ha acqua: palude, fiume, ruscello o sorgente, lago vicino, spiaggia. Le coste a scogliera
# non contano: lì il mare non deposita argilla.
static func has_water(cell: MacroCellData, world: World) -> bool:
	if cell == null or cell.terrain_base == GameTypes.TerrainBase.WATER:
		return false
	return cell.biome == GameTypes.Biome.SWAMP or cell.water_type == GameTypes.WaterType.RIVER \
			or cell.stream_edges != 0 or cell.stream_has_spring or cell.coast_type == GameTypes.CoastType.BEACH \
			or _has_neighbor_water(cell, world, GameTypes.WaterType.LAKE)


# Genera le chiazze una volta sola per macrocella. `water_access`: le rive della cella viva (ThirstService).
# `excluded_groups`: Array di collezioni di Vector2i dove l'argilla non va (ruscello, fiume, rocce, edifici).
# `guaranteed`: la cella di partenza ha sempre argilla. true se ha generato le posizioni adesso (anche zero).
static func generate_if_needed(
	macro_state: MacroCellState, cell: MacroCellData, world: World, water_access: Dictionary,
	excluded_groups: Array, guaranteed: bool = false
) -> bool:
	if macro_state == null or cell == null or macro_state.clay_positions_generated:
		return false
	macro_state.clay_positions_generated = true
	if cell.terrain_base == GameTypes.TerrainBase.WATER:
		return true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([macro_state.micro_seed, RESOURCE_NAME])
	if not guaranteed and not has_water(cell, world):
		return true

	var excluded: Dictionary = {}
	for group: Variant in excluded_groups:
		for position: Vector2i in group:
			excluded[position] = true
	var anchors := _build_anchors(cell, world, water_access)
	var free_band := _build_free_band(anchors, excluded)
	if free_band.is_empty():
		return true
	# Centri sulla riva; senza rive libere, ovunque nella fascia.
	var centers: Array = []
	for position: Vector2i in anchors:
		if free_band.has(position):
			centers.append(position)
	if centers.is_empty():
		centers = free_band.keys()
	# Ordine fisso: le chiavi delle rive dipendono da come sono state calcolate, le chiazze non devono.
	centers.sort()
	for _patch in range(rng.randi_range(PATCH_COUNT_MIN, PATCH_COUNT_MAX)):
		var center: Vector2i = centers[rng.randi_range(0, centers.size() - 1)]
		_grow_patch(macro_state.clay_positions, center, rng.randi_range(PATCH_SIZE_MIN, PATCH_SIZE_MAX), free_band, rng)
	return true


# true se in `position` c'è un giacimento.
static func has_clay(macro_state: MacroCellState, position: Vector2i) -> bool:
	return macro_state != null and macro_state.clay_positions.has(position)


# Argilla rimasta nella microcella (0 se non c'è giacimento).
static func get_remaining(macro_state: MacroCellState, position: Vector2i) -> int:
	if not has_clay(macro_state, position):
		return 0
	return maxi(get_initial_clay(macro_state, position) - int(macro_state.extracted_clay_by_position.get(position, 0)), 0)


# Un'estrazione: UNITS_PER_EXTRACTION, o quanto resta se è meno. {"resource_name", "quantity"}, {} se non resta nulla.
static func extract(macro_state: MacroCellState, position: Vector2i) -> Dictionary:
	var remaining := get_remaining(macro_state, position)
	if remaining <= 0:
		return {}
	var units: int = mini(UNITS_PER_EXTRACTION, remaining)
	if units == remaining:
		macro_state.clay_positions.erase(position)
		macro_state.extracted_clay_by_position.erase(position)
	else:
		macro_state.extracted_clay_by_position[position] = int(macro_state.extracted_clay_by_position.get(position, 0)) + units
	return {"resource_name": RESOURCE_NAME, "quantity": units}


# Argilla iniziale della microcella (0 se non c'è giacimento): ricavata dalla posizione, sempre la stessa.
static func get_initial_clay(macro_state: MacroCellState, position: Vector2i) -> int:
	if not has_clay(macro_state, position):
		return 0
	var position_hash: int = absi(hash([macro_state.micro_seed, position.x, position.y, RESOURCE_NAME]))
	return UNITS_MIN + position_hash % (UNITS_MAX - UNITS_MIN + 1)


static func _has_neighbor_water(cell: MacroCellData, world: World, water_type: GameTypes.WaterType) -> bool:
	if world == null:
		return false
	for direction in _NEIGHBORS_4:
		var neighbor := world.get_cell_at(cell.x + direction.x, cell.y + direction.y)
		if neighbor != null and neighbor.terrain_base == GameTypes.TerrainBase.WATER and neighbor.water_type == water_type:
			return true
	return false


# Da dove misurare la distanza dall'acqua: le rive della cella più, su una spiaggia, la fila di bordo verso il mare (le
# rive di ThirstService non contano il mare: non si beve).
static func _build_anchors(cell: MacroCellData, world: World, water_access: Dictionary) -> Dictionary:
	var anchors := water_access.duplicate()
	if world == null or cell.coast_type != GameTypes.CoastType.BEACH:
		return anchors
	for direction in _NEIGHBORS_4:
		var neighbor := world.get_cell_at(cell.x + direction.x, cell.y + direction.y)
		if neighbor == null or neighbor.terrain_base != GameTypes.TerrainBase.WATER or neighbor.water_type != GameTypes.WaterType.SEA:
			continue
		for i in range(World.WIDTH):
			var position := Vector2i(0, i)
			if direction.y == -1:
				position = Vector2i(i, 0)
			elif direction.x == 1:
				position = Vector2i(World.WIDTH - 1, i)
			elif direction.y == 1:
				position = Vector2i(i, World.HEIGHT - 1)
			anchors[position] = true
	return anchors


# Microcelle libere entro BAND_RADIUS dalle ancore (visita a strati). Senza ancore (palude senz'acqua nella cella, cella
# di partenza asciutta): tutta la macrocella.
static func _build_free_band(anchors: Dictionary, excluded: Dictionary) -> Dictionary:
	var band: Dictionary = {}
	if anchors.is_empty():
		for y in range(World.HEIGHT):
			for x in range(World.WIDTH):
				var position := Vector2i(x, y)
				if not excluded.has(position):
					band[position] = true
		return band
	var visited := anchors.duplicate()
	var layer: Array = anchors.keys()
	for _distance in range(BAND_RADIUS + 1):
		var next_layer: Array = []
		for position: Vector2i in layer:
			if not excluded.has(position):
				band[position] = true
			for direction in _NEIGHBORS_8:
				var near: Vector2i = position + direction
				if near.x < 0 or near.y < 0 or near.x >= World.WIDTH or near.y >= World.HEIGHT or visited.has(near):
					continue
				visited[near] = true
				next_layer.append(near)
		layer = next_layer
	return band


# Cresce una chiazza dal centro aggiungendo ogni volta una microcella a caso del bordo: forma tondeggiante, bordi irregolari.
static func _grow_patch(clay_positions: Dictionary, center: Vector2i, size: int, free_band: Dictionary, rng: RandomNumberGenerator) -> void:
	var seen: Dictionary = {center: true}
	var frontier: Array[Vector2i] = [center]
	var placed := 0
	while placed < size and not frontier.is_empty():
		var index := rng.randi_range(0, frontier.size() - 1)
		var position: Vector2i = frontier[index]
		frontier[index] = frontier[frontier.size() - 1]
		frontier.pop_back()
		if not clay_positions.has(position):
			clay_positions[position] = true
			placed += 1
		for direction in _NEIGHBORS_8:
			var near: Vector2i = position + direction
			if free_band.has(near) and not seen.has(near):
				seen[near] = true
				frontier.append(near)
