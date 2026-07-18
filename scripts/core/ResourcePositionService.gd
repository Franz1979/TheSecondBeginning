class_name ResourcePositionService
extends RefCounted

# 8 direzioni (non solo N/S/E/O): un BFS di crescita 4-connesso approssima un rombo (palla L1)
# invece di un cerchio — le diagonali arrotondano l'anello di crescita verso un ottagono,
# eliminando lo spigolo netto a 45° visibile sui bordi delle macchie generate.
const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(1, -1),
	Vector2i(1, 1),
	Vector2i(-1, -1),
	Vector2i(-1, 1),
]

# Ampiezza (in unità di valore di rumore Perlin, tipicamente [-1, 1]) della fascia attorno a
# `threshold` entro cui l'inclusione di una cella tra le candidate diventa probabilistica
# invece che un taglio netto sì/no — ammorbidisce il bordo guidato dal rumore, non solo
# quello prodotto dalla crescita BFS. Ben oltre questa fascia il comportamento resta
# invariato (dentro=sempre incluso, fuori=sempre escluso).
const SOFT_EDGE_BAND: float = 0.12

# Genera `count` posizioni microcella (100x100) a macchie tramite noise (stessa logica
# validata in origine per stone: campo Perlin sopra soglia, con bordo sfumato — vedi
# SOFT_EDGE_BAND — come candidate, poi ricondotte esattamente a `count` sottocampionando se
# troppe o facendo crescere le macchie verso i vicini liberi se poche). `occupied` esclude a
# priori le celle già assegnate altrove e
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
	# Esplicitati invece di affidarsi ai default impliciti di FastNoiseLite: stessa forma di
	# rumore di sempre, ma come scelta intenzionale e ritoccabile qui, non un accidente del
	# motore. Più ottave = più dettaglio ad alta frequenza sul bordo delle macchie.
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5

	var candidates := _collect_noise_candidates(noise, threshold, occupied, noise_seed)

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


static func _collect_noise_candidates(noise: FastNoiseLite, threshold: float, occupied: Dictionary, noise_seed: int) -> Array:
	var candidates: Array = []
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			if occupied.has(pos):
				continue
			if _passes_soft_threshold(noise.get_noise_2d(x, y), threshold, pos, noise_seed):
				candidates.append(pos)
	return candidates


# Taglio netto (noise_value >= threshold) solo ben fuori dalla fascia SOFT_EDGE_BAND attorno
# alla soglia; dentro la fascia l'inclusione è probabilistica, decisa da un hash deterministico
# di (posizione, noise_seed) — NON dal rng sequenziale passato al chiamante, per restare
# indipendente dall'ordine di iterazione del doppio for y/x sopra (stesso stile già validato in
# MicroCellRenderer per bacche/frutti: hash puro della posizione, stesso seed = stesso risultato
# sempre, in qualunque ordine venga valutato).
static func _passes_soft_threshold(noise_value: float, threshold: float, pos: Vector2i, noise_seed: int) -> bool:
	var distance_from_threshold: float = noise_value - threshold
	if distance_from_threshold >= SOFT_EDGE_BAND:
		return true
	if distance_from_threshold <= -SOFT_EDGE_BAND:
		return false

	var inclusion_chance: float = (distance_from_threshold + SOFT_EDGE_BAND) / (2.0 * SOFT_EDGE_BAND)
	var hash_value: float = float(hash(pos * 3 + Vector2i(noise_seed, 727)) % 100000) / 100000.0
	return hash_value < inclusion_chance


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
# liberi (8 direzioni, esclusi quelli già in `occupied`; ordine di celle E di vicini mescolato
# dallo stesso rng seedato, non fisso), un anello alla volta, finché non si raggiunge `count`.
# Se le macchie non possono più espandersi completa con un fallback random uniforme sulle
# celle rimaste libere, con un tetto di tentativi per non restare mai bloccati se la griglia
# è quasi satura tra tutte le risorse.
static func _grow_positions(candidates: Array, count: int, rng: RandomNumberGenerator, occupied: Dictionary) -> Array:
	var claimed: Dictionary = {}
	for pos in candidates:
		claimed[pos] = true

	var positions: Array = candidates.duplicate()
	var frontier: Array = candidates.duplicate()

	while positions.size() < count and not frontier.is_empty():
		var next_frontier: Array = []
		for cell in _shuffled(frontier, rng):
			for offset in _shuffled(NEIGHBOR_OFFSETS, rng):
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
