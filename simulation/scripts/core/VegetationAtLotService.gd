class_name VegetationAtLotService
extends RefCounted

# Vegetazione a richiesta, passo 2 (docs/progetto_vegetazione_a_richiesta.md): cosa c'è in un lotto, calcolato solo da
# seme del mondo, bioma/terreno/costa, posizione e anno, senza guardare il resto della cella. La stessa domanda dà sempre
# la stessa risposta. La usano VegetationLayoutService (passo 4) e tools/vegetation_at_lot_preview.
#
# Maturità del lotto: rumore lento su x, y e tempo, reso quasi uniforme tra 0 e 1. Salendo: terra, prato, arbusti, alberi,
# con soglie che dipendono dal bioma (stesse proporzioni di ParametricResourceSetupService).
# Griglia: il rumore si calcola solo ogni GRID_STEP lotti e ogni BIRTH_YEAR_STEP anni, una volta per macrocella e passo di
# tempo, e tra i nodi si interpola. Le griglie sono solo memoria: i nodi dipendono dalle coordinate del mondo, quindi il
# risultato non dipende da quali lotti si chiedono né in che ordine, e due macrocelle vicine hanno gli stessi valori sul
# confine.
# Ciclo di ogni posto: durata e sfasamento dati dal suo hash. All'inizio di ogni ciclo la pianta nasce solo se la maturità
# di quell'anno lo consente, poi vive tutto il ciclo: così un bosco non cambia tutto insieme. Un albero nasce solo dove
# TREE_NEEDS_SHRUB_STEPS passi prima c'era già almeno la fascia degli arbusti.
# Uscita anticipata: una griglia con il massimo della maturità sugli anni che contano dice in un'unica lettura che nessun
# ciclo in corso può essere nato in quel lotto. È un limite vero, quindi non si perde nessuna pianta.
#
# Coordinate del mondo (macrocella × 100 + lotto): una macchia può continuare nella macrocella accanto.
# Non guarda ancora edifici, tagli, rocce e fiumi (passo 4), né risorse e frutta (passi 6 e 7).

const LOTS_PER_CELL := 100
# Il gioco non ha un seme per partita: anche il generatore di prima dava le stesse piante a parità di coordinate (micro_seed).
const DEFAULT_WORLD_SEED := 12345

# Da tarare guardando le immagini dello strumento.
const SPATIAL_FREQUENCY := 0.06
const DRIFT_PER_YEAR := 0.25
const NOISE_OCTAVES := 2
# Scala della logistica che rende uniforme il rumore; misurata dallo strumento (deviazione del rumore / 1,81).
const NOISE_LOGISTIC_SCALE := 0.108
# Bordo irregolare: spostamento fisso per lotto. Sostituisce il dettaglio fine che la griglia non ha.
const EDGE_JITTER := 0.07
# Bordo del bosco più rado: da questa frazione di posti pieni, fino a tutti su questa ampiezza di maturità.
const EDGE_RAMP := 0.05
const EDGE_MIN_FILL := 0.5
# Arbusti sotto le chiome: fascia di maturità sopra la soglia degli alberi e quota di posti.
const UNDER_CANOPY_BAND := 0.10
const UNDER_CANOPY_FILL := 0.30
const LIFESPAN_MIN_FACTOR := 0.7
const LIFESPAN_RANGE_FACTOR := 0.6
# Quante volte l'età adulta dura il ciclo oltre la gioventù: poco sopra 1, così le piante vecchie restano una minoranza.
const LIFESPAN_ADULT_FACTOR := 1.2
# Anni in cui resta il segno di una pianta morta non rinata.
const DEAD_SIGN_YEARS := 2
# Griglia della maturità: un nodo ogni tanti lotti, un passo di tempo ogni tanti anni.
const GRID_STEP := 4
const GRID_SIZE := LOTS_PER_CELL / GRID_STEP + 1
const BIRTH_YEAR_STEP := 8
const TREE_NEEDS_SHRUB_STEPS := 2
# Oltre questo numero di griglie in memoria si ricomincia da capo.
const MAX_CACHED_GRIDS := 512

const BAND_BARE := 0
const BAND_GRASS := 1
const BAND_SHRUB := 2
const BAND_TREE := 3

const NEVER := 2.0

const SALT_JITTER := 11
const SALT_SLOTS_TREE := 21
const SALT_SLOTS_SHRUB := 22
const SALT_CYCLE_TREE := 31
const SALT_CYCLE_SHRUB := 32
const SALT_FILL_TREE := 41
const SALT_FILL_SHRUB := 42
const SALT_SUBTYPE_TREE := 51
const SALT_SUBTYPE_SHRUB := 52

static var _noise: FastNoiseLite = null
# Vector3i(macrocella x, y, passo di tempo) -> PackedFloat32Array GRID_SIZE×GRID_SIZE.
static var _step_grids: Dictionary = {}
# Vector4i(macrocella x, y, primo passo, ultimo passo) -> massimo nodo per nodo su quei passi.
static var _bound_grids: Dictionary = {}


# Soglie e dati di una combinazione bioma/terreno/costa: si calcolano una volta per cella, non per lotto.
class LotProfile:
	var grass_min: float = NEVER
	var shrub_min: float = NEVER
	var tree_min: float = NEVER
	var tree_share: float = 0.0
	var shrub_share: float = 0.0
	var grass_share: float = 0.0
	var tree_density: float = 0.0
	var shrub_density: float = 0.0
	var tree_lifespan: float = 1.0
	var shrub_lifespan: float = 1.0
	# Quanti anni indietro può essere nato un ciclo ancora in corso, o quello prima per il segno di pianta morta.
	var window_years: int = 1
	var tree_subtypes_cumulative: PackedFloat32Array = PackedFloat32Array()
	var shrub_subtypes_cumulative: PackedFloat32Array = PackedFloat32Array()


# Vector4i(terreno, bioma, costa, età del mondo) -> LotProfile.
static var _profiles: Dictionary = {}


static func get_profile(
	terrain: GameTypes.TerrainBase, biome: GameTypes.Biome, coast: GameTypes.CoastType, age: GameTypes.WorldAge
) -> LotProfile:
	var key := Vector4i(terrain, biome, coast, age)
	var cached: Variant = _profiles.get(key)
	if cached != null:
		return cached
	var profile := make_profile(terrain, biome, coast, age)
	_profiles[key] = profile
	return profile


# Età del mondo dalla scelta di nuova partita (GameData.starting_world_age_mode). CLASSIC e partite vecchie: come OLD.
static func world_age_from_mode(mode: String) -> GameTypes.WorldAge:
	match mode:
		"YOUNG":
			return GameTypes.WorldAge.YOUNG
		"ADULT":
			return GameTypes.WorldAge.ADULT
	return GameTypes.WorldAge.OLD


static func set_world_seed(world_seed: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = SPATIAL_FREQUENCY
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = NOISE_OCTAVES
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	clear_maturity_cache()


static func clear_maturity_cache() -> void:
	_step_grids.clear()
	_bound_grids.clear()


static func make_profile(
	terrain: GameTypes.TerrainBase, biome: GameTypes.Biome, coast: GameTypes.CoastType, age: GameTypes.WorldAge = GameTypes.WorldAge.OLD
) -> LotProfile:
	var profile := LotProfile.new()
	var setup := ParametricResourceSetupService.new()
	var fill: float = ParametricResourceSetupService.FILL_FRACTION_BY_AGE[age]
	var proportions: Dictionary
	if biome == GameTypes.Biome.DESERT:
		fill *= ParametricResourceSetupService.DESERT_FILL_RATIO
		proportions = {
			GameTypes.WorldObjectType.GRASS: 0.0,
			GameTypes.WorldObjectType.SHRUB: 1.0,
			GameTypes.WorldObjectType.TREE: 0.0,
		}
	else:
		var row: Dictionary = ParametricResourceSetupService.BIOME_PROPORTIONS.get(biome, ParametricResourceSetupService.BIOME_PROPORTIONS[GameTypes.Biome.NONE])
		proportions = setup._adjust_for_terrain(row, terrain)
	var gated: Dictionary = setup._apply_density_gate(proportions, terrain, biome, coast)
	profile.tree_share = float(gated.get(GameTypes.WorldObjectType.TREE, 0.0)) * fill
	profile.shrub_share = float(gated.get(GameTypes.WorldObjectType.SHRUB, 0.0)) * fill
	profile.grass_share = float(gated.get(GameTypes.WorldObjectType.GRASS, 0.0)) * fill
	if profile.tree_share > 0.0:
		profile.tree_min = 1.0 - profile.tree_share
	var below_trees: float = 1.0 - profile.tree_share
	if profile.shrub_share > 0.0:
		profile.shrub_min = below_trees - profile.shrub_share
	var below_shrubs: float = below_trees - profile.shrub_share
	if profile.grass_share > 0.0:
		profile.grass_min = below_shrubs - profile.grass_share
	profile.tree_density = ResourceCalculator.get_max_density(GameTypes.WorldObjectType.TREE, terrain, biome, coast)
	profile.shrub_density = ResourceCalculator.get_max_density(GameTypes.WorldObjectType.SHRUB, terrain, biome, coast)
	profile.tree_lifespan = _mean_lifespan(GameTypes.WorldObjectType.TREE)
	profile.shrub_lifespan = _mean_lifespan(GameTypes.WorldObjectType.SHRUB)
	var longest_lifespan: float = maxf(profile.tree_lifespan, profile.shrub_lifespan) * (LIFESPAN_MIN_FACTOR + LIFESPAN_RANGE_FACTOR)
	profile.window_years = ceili(longest_lifespan) + DEAD_SIGN_YEARS
	profile.tree_subtypes_cumulative = _cumulative_subtype_weights(GameTypes.WorldObjectType.TREE, biome)
	profile.shrub_subtypes_cumulative = _cumulative_subtype_weights(GameTypes.WorldObjectType.SHRUB, biome)
	return profile


# Maturità tra 0 e 1 del lotto in quell'anno, spostamento fisso del lotto compreso.
static func maturity_at(world_x: int, world_y: int, year: int) -> float:
	var cell_x: int = floori(float(world_x) / float(LOTS_PER_CELL))
	var cell_y: int = floori(float(world_y) / float(LOTS_PER_CELL))
	var lot_x: int = world_x - cell_x * LOTS_PER_CELL
	var lot_y: int = world_y - cell_y * LOTS_PER_CELL
	var step: int = floori(float(year) / float(BIRTH_YEAR_STEP))
	var time_fraction: float = float(year - step * BIRTH_YEAR_STEP) / float(BIRTH_YEAR_STEP)
	return lerpf(
		_read_grid(_step_grid(cell_x, cell_y, step), lot_x, lot_y),
		_read_grid(_step_grid(cell_x, cell_y, step + 1), lot_x, lot_y),
		time_fraction
	) + _lot_jitter(world_x, world_y)


static func raw_noise_at(world_x: int, world_y: int, year: int) -> float:
	return _noise.get_noise_3d(world_x, world_y, year * DRIFT_PER_YEAR)


static func band_of(profile: LotProfile, maturity: float) -> int:
	if maturity >= profile.tree_min:
		return BAND_TREE
	if maturity >= profile.shrub_min:
		return BAND_SHRUB
	if maturity >= profile.grass_min:
		return BAND_GRASS
	return BAND_BARE


# trees/shrubs: PackedInt32Array piatto [indice posto, età, indice sottotipo, ...]. dead_*: posti con il segno di pianta
# morta. grass: se il lotto è a prato (dove non c'è nessuna pianta viva). `exact`: senza uscita anticipata, solo per
# verificare che non perda piante.
static func vegetation_at(profile: LotProfile, world_x: int, world_y: int, year: int, exact: bool = false) -> Dictionary:
	var cell_x: int = floori(float(world_x) / float(LOTS_PER_CELL))
	var cell_y: int = floori(float(world_y) / float(LOTS_PER_CELL))
	var lot_x: int = world_x - cell_x * LOTS_PER_CELL
	var lot_y: int = world_y - cell_y * LOTS_PER_CELL
	var jitter := _lot_jitter(world_x, world_y)
	var last_step: int = floori(float(year) / float(BIRTH_YEAR_STEP))
	var time_fraction: float = float(year - last_step * BIRTH_YEAR_STEP) / float(BIRTH_YEAR_STEP)
	var maturity: float = lerpf(
		_read_grid(_step_grid(cell_x, cell_y, last_step), lot_x, lot_y),
		_read_grid(_step_grid(cell_x, cell_y, last_step + 1), lot_x, lot_y),
		time_fraction
	) + jitter
	var first_step: int = floori(float(year - profile.window_years) / float(BIRTH_YEAR_STEP))
	var highest: float = _read_grid(_bound_grid(cell_x, cell_y, first_step, last_step), lot_x, lot_y) + jitter
	var can_have_trees: bool = profile.tree_share > 0.0 and (exact or highest >= profile.tree_min)
	var can_have_shrubs: bool = profile.shrub_share > 0.0 and (exact or highest >= profile.shrub_min)
	var trees := PackedInt32Array()
	var shrubs := PackedInt32Array()
	var dead_trees := 0
	var dead_shrubs := 0
	if can_have_trees or can_have_shrubs:
		var values_first_step: int = first_step - TREE_NEEDS_SHRUB_STEPS
		var values := PackedFloat32Array()
		values.resize(last_step - values_first_step + 1)
		for i in range(values.size()):
			values[i] = _read_grid(_step_grid(cell_x, cell_y, values_first_step + i), lot_x, lot_y) + jitter
		if can_have_trees:
			dead_trees = _fill_slots(profile, true, world_x, world_y, year, values, values_first_step, trees, -1)
		if can_have_shrubs:
			dead_shrubs = _fill_slots(profile, false, world_x, world_y, year, values, values_first_step, shrubs, -1)
	return {
		"trees": trees,
		"shrubs": shrubs,
		"dead_trees": dead_trees,
		"dead_shrubs": dead_shrubs,
		"grass": trees.is_empty() and shrubs.is_empty() and maturity >= profile.grass_min,
		"maturity": maturity,
	}


# Stesso risultato di vegetation_at, per molti lotti della stessa macrocella in una sola chiamata: griglie risolte una
# volta sola, niente Dictionary per lotto. `lot_codes`: y * 100 + x. Risultato:
#   trees/shrubs: PackedInt32Array piatto [codice lotto, indice posto, età, indice sottotipo, ...]
#   grass: codici dei lotti a prato; dead: un codice per ogni posto col segno di pianta morta.
static func vegetation_for_lots(profile: LotProfile, cell_x: int, cell_y: int, year: int, lot_codes: PackedInt32Array) -> Dictionary:
	var base_x: int = cell_x * LOTS_PER_CELL
	var base_y: int = cell_y * LOTS_PER_CELL
	var last_step: int = floori(float(year) / float(BIRTH_YEAR_STEP))
	var first_step: int = floori(float(year - profile.window_years) / float(BIRTH_YEAR_STEP))
	var values_first_step: int = first_step - TREE_NEEDS_SHRUB_STEPS
	var time_fraction: float = float(year - last_step * BIRTH_YEAR_STEP) / float(BIRTH_YEAR_STEP)
	var now_grid := _step_grid(cell_x, cell_y, last_step)
	var next_grid := _step_grid(cell_x, cell_y, last_step + 1)
	var bound_grid := _bound_grid(cell_x, cell_y, first_step, last_step)
	var grids: Array[PackedFloat32Array] = []
	for step in range(values_first_step, last_step + 1):
		grids.append(_step_grid(cell_x, cell_y, step))
	var grid_count: int = grids.size()
	var values := PackedFloat32Array()
	values.resize(grid_count)
	var trees := PackedInt32Array()
	var shrubs := PackedInt32Array()
	var grass := PackedInt32Array()
	var dead := PackedInt32Array()
	var has_trees: bool = profile.tree_share > 0.0
	var has_shrubs: bool = profile.shrub_share > 0.0
	var tree_min: float = profile.tree_min
	var shrub_min: float = profile.shrub_min
	var grass_min: float = profile.grass_min
	for code in lot_codes:
		var lot_y: int = code / LOTS_PER_CELL
		var lot_x: int = code - lot_y * LOTS_PER_CELL
		var world_x: int = base_x + lot_x
		var world_y: int = base_y + lot_y
		var node_x: int = lot_x / GRID_STEP
		var node_y: int = lot_y / GRID_STEP
		var fx: float = float(lot_x - node_x * GRID_STEP) / float(GRID_STEP)
		var fy: float = float(lot_y - node_y * GRID_STEP) / float(GRID_STEP)
		var i00: int = node_y * GRID_SIZE + node_x
		var i10: int = i00 + 1
		var i01: int = i00 + GRID_SIZE
		var i11: int = i01 + 1
		var w00: float = (1.0 - fx) * (1.0 - fy)
		var w10: float = fx * (1.0 - fy)
		var w01: float = (1.0 - fx) * fy
		var w11: float = fx * fy
		var jitter: float = (_unit(_mix(world_x, world_y, 0, SALT_JITTER)) - 0.5) * EDGE_JITTER
		var highest: float = bound_grid[i00] * w00 + bound_grid[i10] * w10 + bound_grid[i01] * w01 + bound_grid[i11] * w11 + jitter
		var can_have_trees: bool = has_trees and highest >= tree_min
		var can_have_shrubs: bool = has_shrubs and highest >= shrub_min
		var plants_before: int = trees.size() + shrubs.size()
		if can_have_trees or can_have_shrubs:
			for i in range(grid_count):
				var grid: PackedFloat32Array = grids[i]
				values[i] = grid[i00] * w00 + grid[i10] * w10 + grid[i01] * w01 + grid[i11] * w11 + jitter
			if can_have_trees:
				var dead_trees := _fill_slots(profile, true, world_x, world_y, year, values, values_first_step, trees, code)
				for j in range(dead_trees):
					dead.append(code)
			if can_have_shrubs:
				var dead_shrubs := _fill_slots(profile, false, world_x, world_y, year, values, values_first_step, shrubs, code)
				for j in range(dead_shrubs):
					dead.append(code)
		if trees.size() + shrubs.size() == plants_before:
			var now_value: float = now_grid[i00] * w00 + now_grid[i10] * w10 + now_grid[i01] * w01 + now_grid[i11] * w11
			var next_value: float = next_grid[i00] * w00 + next_grid[i10] * w10 + next_grid[i01] * w01 + next_grid[i11] * w11
			if now_value + (next_value - now_value) * time_fraction + jitter >= grass_min:
				grass.append(code)
	return {"trees": trees, "shrubs": shrubs, "grass": grass, "dead": dead}


# Riempie `plants` con le piante vive e ritorna quanti posti hanno il segno di pianta morta. `lot_code` >= 0: ogni pianta
# porta davanti il codice del lotto (vegetation_for_lots).
static func _fill_slots(
	profile: LotProfile, is_tree: bool, world_x: int, world_y: int, year: int,
	values: PackedFloat32Array, values_first_step: int, plants: PackedInt32Array, lot_code: int
) -> int:
	var density: float = profile.tree_density if is_tree else profile.shrub_density
	var slots_salt: int = SALT_SLOTS_TREE if is_tree else SALT_SLOTS_SHRUB
	var cycle_salt: int = SALT_CYCLE_TREE if is_tree else SALT_CYCLE_SHRUB
	var mean_lifespan: float = profile.tree_lifespan if is_tree else profile.shrub_lifespan
	var slot_count: int = int(density)
	if _unit(_mix(world_x, world_y, 0, slots_salt)) < density - float(slot_count):
		slot_count += 1
	var dead := 0
	for index in range(slot_count):
		var cycle_hash := _mix(world_x, world_y, index, cycle_salt)
		var lifespan: int = maxi(1, int(mean_lifespan * (LIFESPAN_MIN_FACTOR + LIFESPAN_RANGE_FACTOR * _unit(cycle_hash))))
		var phase: int = (cycle_hash >> 8) % lifespan
		var cycle: int = floori(float(year + phase) / float(lifespan))
		var cycle_start: int = cycle * lifespan - phase
		var age: int = year - cycle_start
		if _born_in_cycle(profile, is_tree, world_x, world_y, index, cycle, cycle_start, values, values_first_step):
			if lot_code >= 0:
				plants.append(lot_code)
			plants.append(index)
			plants.append(age)
			plants.append(_subtype_index(profile, is_tree, world_x, world_y, index, cycle))
		elif age < DEAD_SIGN_YEARS and _born_in_cycle(profile, is_tree, world_x, world_y, index, cycle - 1, cycle_start - lifespan, values, values_first_step):
			dead += 1
	return dead


static func _born_in_cycle(
	profile: LotProfile, is_tree: bool, world_x: int, world_y: int, index: int, cycle: int, cycle_start: int,
	values: PackedFloat32Array, values_first_step: int
) -> bool:
	var position: int = floori(float(cycle_start) / float(BIRTH_YEAR_STEP)) - values_first_step
	var maturity: float = values[position]
	var fill: float
	if is_tree:
		fill = _tree_fill(profile, maturity)
		if fill > 0.0 and profile.shrub_share > 0.0 and values[position - TREE_NEEDS_SHRUB_STEPS] < profile.shrub_min:
			return false
	else:
		fill = _shrub_fill(profile, maturity)
	if fill <= 0.0:
		return false
	if fill >= 1.0:
		return true
	return _unit(_mix(world_x, world_y, index * 1009 + cycle, SALT_FILL_TREE if is_tree else SALT_FILL_SHRUB)) < fill


static func _tree_fill(profile: LotProfile, maturity: float) -> float:
	if maturity < profile.tree_min:
		return 0.0
	return clampf((maturity - profile.tree_min) / EDGE_RAMP, EDGE_MIN_FILL, 1.0)


static func _shrub_fill(profile: LotProfile, maturity: float) -> float:
	if maturity < profile.shrub_min:
		return 0.0
	if maturity >= profile.tree_min:
		return UNDER_CANOPY_FILL if maturity < profile.tree_min + UNDER_CANOPY_BAND else 0.0
	return clampf((maturity - profile.shrub_min) / EDGE_RAMP, EDGE_MIN_FILL, 1.0)


static func _subtype_index(profile: LotProfile, is_tree: bool, world_x: int, world_y: int, index: int, cycle: int) -> int:
	var cumulative: PackedFloat32Array = profile.tree_subtypes_cumulative if is_tree else profile.shrub_subtypes_cumulative
	var roll := _unit(_mix(world_x, world_y, index * 1009 + cycle, SALT_SUBTYPE_TREE if is_tree else SALT_SUBTYPE_SHRUB))
	for i in range(cumulative.size()):
		if roll < cumulative[i]:
			return i
	return maxi(0, cumulative.size() - 1)


static func _step_grid(cell_x: int, cell_y: int, step: int) -> PackedFloat32Array:
	var key := Vector3i(cell_x, cell_y, step)
	var cached: Variant = _step_grids.get(key)
	if cached != null:
		return cached
	if _noise == null:
		set_world_seed(DEFAULT_WORLD_SEED)
	if _step_grids.size() >= MAX_CACHED_GRIDS:
		clear_maturity_cache()
	var grid := PackedFloat32Array()
	grid.resize(GRID_SIZE * GRID_SIZE)
	var time_coordinate: float = float(step * BIRTH_YEAR_STEP) * DRIFT_PER_YEAR
	for node_y in range(GRID_SIZE):
		for node_x in range(GRID_SIZE):
			var value: float = _noise.get_noise_3d(cell_x * LOTS_PER_CELL + node_x * GRID_STEP, cell_y * LOTS_PER_CELL + node_y * GRID_STEP, time_coordinate)
			grid[node_y * GRID_SIZE + node_x] = 1.0 / (1.0 + exp(-value / NOISE_LOGISTIC_SCALE))
	_step_grids[key] = grid
	return grid


static func _bound_grid(cell_x: int, cell_y: int, first_step: int, last_step: int) -> PackedFloat32Array:
	var key := Vector4i(cell_x, cell_y, first_step, last_step)
	var cached: Variant = _bound_grids.get(key)
	if cached != null:
		return cached
	if _bound_grids.size() >= MAX_CACHED_GRIDS:
		clear_maturity_cache()
	var bound: PackedFloat32Array = _step_grid(cell_x, cell_y, first_step).duplicate()
	for step in range(first_step + 1, last_step + 1):
		var grid := _step_grid(cell_x, cell_y, step)
		for i in range(bound.size()):
			if grid[i] > bound[i]:
				bound[i] = grid[i]
	_bound_grids[key] = bound
	return bound


static func _read_grid(grid: PackedFloat32Array, lot_x: int, lot_y: int) -> float:
	var node_x: int = lot_x / GRID_STEP
	var node_y: int = lot_y / GRID_STEP
	var fraction_x: float = float(lot_x - node_x * GRID_STEP) / float(GRID_STEP)
	var fraction_y: float = float(lot_y - node_y * GRID_STEP) / float(GRID_STEP)
	var index: int = node_y * GRID_SIZE + node_x
	var top: float = lerpf(grid[index], grid[index + 1], fraction_x)
	var bottom: float = lerpf(grid[index + GRID_SIZE], grid[index + GRID_SIZE + 1], fraction_x)
	return lerpf(top, bottom, fraction_y)


static func _lot_jitter(world_x: int, world_y: int) -> float:
	return (_unit(_mix(world_x, world_y, 0, SALT_JITTER)) - 0.5) * EDGE_JITTER


# Durata media del ciclo: gioventù e età adulta (LIFESPAN_ADULT_FACTOR), mediate tra i sottotipi.
static func _mean_lifespan(object_type: GameTypes.WorldObjectType) -> float:
	var rules: Array = ResourceCalculator.get_subtype_rules(object_type)
	if rules.is_empty():
		return 10.0
	var total := 0.0
	for rule in rules:
		total += float(rule.youth_duration_years) + float(rule.adult_duration_years) * LIFESPAN_ADULT_FACTOR
	return total / float(rules.size())


static func _cumulative_subtype_weights(object_type: GameTypes.WorldObjectType, biome: GameTypes.Biome) -> PackedFloat32Array:
	var weights: Dictionary = ResourceCalculator.get_initial_ratio_subtype_weights(object_type, biome)
	var cumulative := PackedFloat32Array()
	var rules: Array = ResourceCalculator.get_subtype_rules(object_type)
	var total := 0.0
	for rule in rules:
		total += float(weights.get(rule.subtype_name, 0.0))
	if total <= 0.0:
		return cumulative
	var running := 0.0
	for rule in rules:
		running += float(weights.get(rule.subtype_name, 0.0)) / total
		cumulative.append(running)
	return cumulative


# Hash intero veloce, senza array né stringhe: si chiama molte volte per lotto.
static func _mix(a: int, b: int, c: int, d: int) -> int:
	var h: int = a * 0x1E3779B97F4A7C15
	h ^= b * 0x2127599BF4325C37
	h = (h ^ (h >> 29)) * 0x27D4EB2F165667C5
	h ^= c * 0x165667B19E3779F9
	h ^= d * 0x0FC4CEB9FE1A85EC
	h = (h ^ (h >> 32)) * 0x1B03738712FAD5C9
	return (h ^ (h >> 29)) & 0x7FFFFFFFFFFFFFFF


static func _unit(hash_value: int) -> float:
	return float((hash_value >> 20) & 0xFFFFFF) / 16777216.0
