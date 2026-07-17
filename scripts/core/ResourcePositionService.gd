class_name ResourcePositionService
extends RefCounted

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(-1, 0),
]

# Genera `count` posizioni microcella (100x100) a macchie tramite noise (stessa logica
# validata in origine per stone: campo Perlin sopra soglia come candidate, poi ricondotte
# esattamente a `count` sottocampionando se troppe o facendo crescere le macchie verso i
# vicini liberi se poche). `occupied` esclude a priori le celle già assegnate altrove e
# viene aggiornato in place con le posizioni appena scelte: passare lo stesso dizionario a
# più chiamate in sequenza (es. una per risorsa) le fa escludere automaticamente a vicenda,
# senza vera "contesa" — ogni chiamata prenota solo tra le celle libere lasciate dalle precedenti.
static func generate_positions(
	noise_seed: int,
	count: int,
	occupied: Dictionary,
	frequency: float,
	threshold: float
) -> Array:
	if count <= 0:
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed

	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = frequency

	var candidates := _collect_noise_candidates(noise, threshold, occupied)

	var positions: Array
	if candidates.size() > count:
		positions = _shuffled(candidates, rng).slice(0, count)
	elif candidates.size() < count:
		positions = _grow_positions(candidates, count, rng, occupied)
	else:
		positions = candidates

	for pos in positions:
		occupied[pos] = true

	return positions


static func _collect_noise_candidates(noise: FastNoiseLite, threshold: float, occupied: Dictionary) -> Array:
	var candidates: Array = []
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			if occupied.has(pos):
				continue
			if noise.get_noise_2d(x, y) >= threshold:
				candidates.append(pos)
	return candidates


# Fisher-Yates deterministico (stesso rng seedato ovunque venga chiamato).
static func _shuffled(array: Array, rng: RandomNumberGenerator) -> Array:
	var shuffled: Array = array.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = temp
	return shuffled


# Le candidate da noise sono troppo poche: fa crescere le macchie esistenti verso i vicini
# liberi (N/S/E/O, esclusi quelli già in `occupied`), un anello alla volta, finché non si
# raggiunge `count`. Se le macchie non possono più espandersi completa con un fallback
# random uniforme sulle celle rimaste libere, con un tetto di tentativi per non restare mai
# bloccati se la griglia è quasi satura tra tutte le risorse.
static func _grow_positions(candidates: Array, count: int, rng: RandomNumberGenerator, occupied: Dictionary) -> Array:
	var claimed: Dictionary = {}
	for pos in candidates:
		claimed[pos] = true

	var positions: Array = candidates.duplicate()
	var frontier: Array = candidates.duplicate()

	while positions.size() < count and not frontier.is_empty():
		var next_frontier: Array = []
		for cell in _shuffled(frontier, rng):
			for offset in NEIGHBOR_OFFSETS:
				var neighbor: Vector2i = cell + offset
				if neighbor.x < 0 or neighbor.x >= World.WIDTH or neighbor.y < 0 or neighbor.y >= World.HEIGHT:
					continue
				if claimed.has(neighbor) or occupied.has(neighbor):
					continue
				claimed[neighbor] = true
				positions.append(neighbor)
				next_frontier.append(neighbor)
				if positions.size() >= count:
					break
			if positions.size() >= count:
				break
		frontier = next_frontier

	var attempts: int = 0
	var max_attempts: int = World.WIDTH * World.HEIGHT * 4
	while positions.size() < count and attempts < max_attempts:
		attempts += 1
		var pos := Vector2i(rng.randi_range(0, World.WIDTH - 1), rng.randi_range(0, World.HEIGHT - 1))
		if claimed.has(pos) or occupied.has(pos):
			continue
		claimed[pos] = true
		positions.append(pos)

	return positions
