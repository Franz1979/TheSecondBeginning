class_name StreamNetworkGenerator
extends RefCounted

# Rete dei ruscelli sulla mappa macro (passo 1 dell'acqua: solo dati + disegno nel mondo).
# Tecnica dei bacini idrografici: un rumore fa da rilievo finto, ogni cella di terra "scola"
# verso una vicina (priority-flood: le conche vengono riempite, quindi ogni cella arriva sempre a
# un lago/mare/fiume o al bordo della mappa), poi si conta quante celle drenano attraverso
# ciascuna. Le celle con abbastanza acqua da monte diventano ruscello: confluenze e rete ad albero
# vengono da sole, senza anelli. Separata dai fiumi (river_shape), che restano invariati.

# Interruttore unico: spento = nessuna generazione e nessun disegno, il mondo resta com'era.
const STREAMS_ENABLED := true

const EDGE_N := 1
const EDGE_E := 2
const EDGE_S := 4
const EDGE_W := 8

# Frazione delle celle di terra attraversate da un ruscello.
const TARGET_LAND_COVERAGE := 0.25
# Sorgenti/pozze isolate (senza ruscello), come frazione delle celle di terra rimaste asciutte.
const ISOLATED_SPRING_RATIO := 0.01
# Rilievo finto: frequenza bassa = valli larghe, bacini grandi.
const RELIEF_NOISE_FREQUENCY := 0.04
# Pendenza casuale minima aggiunta a ogni passo del flood: nelle zone piatte (o nelle conche
# riempite) l'ordine di espansione diventa casuale invece che a "fronte d'onda", quindi i
# ruscelli serpeggiano invece di correre dritti verso il lago/bordo più vicino.
const FLAT_JITTER := 0.005
# Rilievo aggiunto dal terreno della mappa: le sorgenti nascono soprattutto su colline e montagne
# e i ruscelli scendono verso pianure, laghi e fiumi.
const TERRAIN_RELIEF := {
	GameTypes.TerrainBase.HILL: 0.35,
	GameTypes.TerrainBase.MOUNTAIN: 0.7,
}

const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRECTION_EDGES := [EDGE_N, EDGE_E, EDGE_S, EDGE_W]
# Direzione di scolo: indice in DIRECTIONS, oppure uno di questi due valori.
const FLOW_NONE := -1  # cella d'acqua (lago/mare/fiume): raccoglie, non scola


static func opposite_edge(edge: int) -> int:
	match edge:
		EDGE_N:
			return EDGE_S
		EDGE_E:
			return EDGE_W
		EDGE_S:
			return EDGE_N
		EDGE_W:
			return EDGE_E
	return 0


static func is_water_sink(cell: MacroCellData) -> bool:
	return cell.terrain_base == GameTypes.TerrainBase.WATER or cell.water_type == GameTypes.WaterType.RIVER


static func generate(world: World) -> void:
	world.streams_generated = true
	if not STREAMS_ENABLED:
		return
	for cell in world.cells:
		cell.stream_edges = 0
		cell.stream_has_spring = false

	var width := World.WIDTH
	var height := World.HEIGHT
	var count := width * height
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.frequency = RELIEF_NOISE_FREQUENCY

	var relief := PackedFloat32Array()
	relief.resize(count)
	var flow := PackedInt32Array()
	flow.resize(count)
	var visited := PackedByteArray()
	visited.resize(count)
	var heap := _Heap.new()

	# Uscite: celle d'acqua (raccolgono) e celle di terra sul bordo (scolano fuori mappa).
	for cell in world.cells:
		var index := cell.y * width + cell.x
		relief[index] = noise.get_noise_2d(cell.x, cell.y) + float(TERRAIN_RELIEF.get(cell.terrain_base, 0.0))
		flow[index] = FLOW_NONE
		if is_water_sink(cell):
			visited[index] = 1
			heap.push(relief[index], index)
		elif cell.x == 0 or cell.y == 0 or cell.x == width - 1 or cell.y == height - 1:
			visited[index] = 1
			flow[index] = _outward_direction(cell.x, cell.y, width, height, rng)
			heap.push(relief[index], index)

	# Priority-flood: dal più basso verso monte, ogni cella nuova scola verso quella da cui è stata
	# raggiunta. pop_order è quindi sempre "valle prima di monte".
	var pop_order := PackedInt32Array()
	while not heap.is_empty():
		var entry: Array = heap.pop()
		var level: float = entry[0]
		var index: int = entry[1]
		pop_order.append(index)
		var x := index % width
		var y := index / width
		for d in range(DIRECTIONS.size()):
			var nx: int = x + DIRECTIONS[d].x
			var ny: int = y + DIRECTIONS[d].y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var n_index := ny * width + nx
			if visited[n_index] == 1:
				continue
			visited[n_index] = 1
			flow[n_index] = (d + 2) % 4  # la vicina scola indietro verso questa cella
			heap.push(maxf(relief[n_index], level) + rng.randf() * FLAT_JITTER, n_index)

	# Acqua raccolta: ogni cella di terra vale 1, sommata verso valle (monte prima di valle).
	var accumulation := PackedInt32Array()
	accumulation.resize(count)
	var land_indices: Array[int] = []
	for index in range(count):
		if not is_water_sink(world.cells[index]):
			accumulation[index] = 1
			land_indices.append(index)
	for i in range(pop_order.size() - 1, -1, -1):
		var index := pop_order[i]
		var direction := flow[index]
		if direction == FLOW_NONE:
			continue
		var target := _neighbor_index(index, direction, width, height)
		if target >= 0 and not is_water_sink(world.cells[target]):
			accumulation[target] += accumulation[index]

	if land_indices.is_empty():
		return
	var sorted_accumulation: Array[int] = []
	for index in land_indices:
		sorted_accumulation.append(accumulation[index])
	sorted_accumulation.sort()
	sorted_accumulation.reverse()
	var cutoff_position := clampi(int(land_indices.size() * TARGET_LAND_COVERAGE) - 1, 0, land_indices.size() - 1)
	var threshold: int = maxi(2, sorted_accumulation[cutoff_position])

	# Bit dei lati: ogni cella-ruscello si collega alla cella verso cui scola (che ha sempre più
	# acqua raccolta, quindi è ruscello anche lei, oppure è acqua, oppure è fuori mappa).
	for index in land_indices:
		if accumulation[index] < threshold:
			continue
		var cell: MacroCellData = world.cells[index]
		var direction := flow[index]
		cell.stream_edges |= DIRECTION_EDGES[direction]
		var target := _neighbor_index(index, direction, width, height)
		if target >= 0 and not is_water_sink(world.cells[target]):
			world.cells[target].stream_edges |= opposite_edge(DIRECTION_EDGES[direction])

	# Sorgenti: celle-ruscello in cui nessun ruscello arriva da monte (un solo lato toccato).
	for index in land_indices:
		var cell: MacroCellData = world.cells[index]
		if accumulation[index] >= threshold and _edge_count(cell.stream_edges) == 1:
			cell.stream_has_spring = true

	# Qualche sorgente/pozza isolata tra le celle rimaste asciutte.
	var dry_indices: Array[int] = []
	for index in land_indices:
		if world.cells[index].stream_edges == 0:
			dry_indices.append(index)
	var isolated_count := int(dry_indices.size() * ISOLATED_SPRING_RATIO)
	for i in range(isolated_count):
		if dry_indices.is_empty():
			break
		var pick := rng.randi_range(0, dry_indices.size() - 1)
		world.cells[dry_indices[pick]].stream_has_spring = true
		dry_indices.remove_at(pick)


static func _edge_count(edges: int) -> int:
	var total := 0
	for edge in DIRECTION_EDGES:
		if edges & edge:
			total += 1
	return total


static func _neighbor_index(index: int, direction: int, width: int, height: int) -> int:
	var x: int = index % width + DIRECTIONS[direction].x
	var y: int = index / width + DIRECTIONS[direction].y
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return y * width + x


# Cella di bordo: scola verso l'esterno (negli angoli, uno dei due lati a caso).
static func _outward_direction(x: int, y: int, width: int, height: int, rng: RandomNumberGenerator) -> int:
	var options: Array[int] = []
	if y == 0:
		options.append(0)
	if x == width - 1:
		options.append(1)
	if y == height - 1:
		options.append(2)
	if x == 0:
		options.append(3)
	return options[rng.randi_range(0, options.size() - 1)]


# Min-heap minimale (priorità float, valore int) per il priority-flood.
class _Heap:
	var _priorities: Array[float] = []
	var _values: Array[int] = []

	func is_empty() -> bool:
		return _values.is_empty()

	func push(priority: float, value: int) -> void:
		_priorities.append(priority)
		_values.append(value)
		var i := _values.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if _priorities[parent] <= _priorities[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Array:
		var result := [_priorities[0], _values[0]]
		var last := _values.size() - 1
		_swap(0, last)
		_priorities.remove_at(last)
		_values.remove_at(last)
		var i := 0
		var size := _values.size()
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < size and _priorities[left] < _priorities[smallest]:
				smallest = left
			if right < size and _priorities[right] < _priorities[smallest]:
				smallest = right
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return result

	func _swap(a: int, b: int) -> void:
		var priority := _priorities[a]
		_priorities[a] = _priorities[b]
		_priorities[b] = priority
		var value := _values[a]
		_values[a] = _values[b]
		_values[b] = value
