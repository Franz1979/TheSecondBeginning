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
# `threshold` entro cui l'inclusione di una cella tra i "semi" diventa probabilistica invece
# che un taglio netto sì/no — ammorbidisce il bordo guidato dal rumore. Ben oltre questa fascia
# il comportamento resta invariato (dentro=sempre incluso, fuori=sempre escluso).
const SOFT_EDGE_BAND: float = 0.12

# Genera `count` posizioni microcella (100x100) a macchie tramite noise (campo Perlin sopra
# soglia, bordo sfumato — vedi SOFT_EDGE_BAND — come "semi"), poi cresciute verso i vicini se
# non bastano. `occupied` esclude a priori le celle già assegnate altrove e viene aggiornato in
# place con le posizioni appena scelte: passare lo stesso dizionario a più chiamate in sequenza
# (es. una per risorsa) le fa escludere automaticamente a vicenda, senza vera "contesa" — ogni
# chiamata prenota solo tra le celle libere lasciate dalle precedenti.
#
# ORDINE DI PRIORITÀ FISSO (non più shuffle): a differenza della versione precedente (Fisher-
# Yates su `candidates`, la cui intera permutazione cambiava non appena la SIZE dell'array di
# candidate cambiava anche di una sola cella), qui ogni microcella ha una priorità calcolata
# SOLO da (posizione, noise_seed) — mai dalla quantità di celle candidate o da `occupied` —
# tramite due chiavi: 1) distanza BFS (8-connessa) dal seme di rumore più vicino, calcolata
# ignorando `occupied` (puramente geometrica: dipende solo dal campo di rumore, mai da cosa
# altre risorse hanno già rivendicato), 2) hash di spareggio a parità di distanza. Questo
# produce un ordine totale fisso su tutta la macrocella per (frequency, threshold, noise_seed):
# `generate_positions` si limita a scorrerlo, saltare le celle in `occupied`, e prendere le
# prime `count` libere. Conseguenze dirette (il problema di "traballamento" che questo
# redesign risolve): un cambio di `count` prende/rilascia solo la coda dell'ordine fisso
# (prefix-stabile per costruzione); un cambio di `occupied` (es. perché una risorsa rivendicata
# PRIMA in ordine di priorità in VegetationPositionService.CLAIM_ORDER ha reclamato un numero
# diverso di celle quest'anno) fa sparire/riapparire solo QUELLE celle specifiche nell'ordine
# fisso di questa risorsa, senza alterare l'ordine relativo di tutte le altre — l'effetto a
# catena TREE→SHRUB→GRASS diventa locale, non più un rimescolamento totale.
static func generate_positions(
	noise_seed: int,
	count: int,
	occupied: Dictionary,
	frequency: float,
	threshold: float
) -> Array:
	if count <= 0:
		return []

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

	var positions := _walk_priority_order(noise, threshold, noise_seed, count, occupied)

	for pos in positions:
		occupied[pos] = true

	return positions


# Cuore del meccanismo: BFS multi-sorgente a anelli, ognuno ordinato per priorità hash prima di
# essere processato (mai per shuffle sequenziale). Ring 0 = tutte le celle "seme" (noise sopra
# soglia), scoperte ignorando `occupied` — la geometria dei ring è quindi sempre la stessa a
# parità di (frequency, threshold, noise_seed), indipendentemente da cosa altre risorse hanno
# già rivendicato. `occupied` interviene SOLO al momento di decidere se una cella già visitata
# va aggiunta all'output — non blocca né devia l'espansione BFS verso i suoi vicini, che
# prosegue comunque oltre una cella occupata (trattata come "trasparente" ai fini della sola
# distanza, mai selezionabile come output). Si interrompe non appena `count` posizioni libere
# sono state raccolte, senza necessità di visitare l'intera griglia salvo casi limite.
static func _walk_priority_order(
	noise: FastNoiseLite,
	threshold: float,
	noise_seed: int,
	count: int,
	occupied: Dictionary
) -> Array:
	var positions: Array = []
	var visited: Dictionary = {}

	var seeds: Array = []
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			if _passes_soft_threshold(noise.get_noise_2d(x, y), threshold, pos, noise_seed):
				seeds.append(pos)
				visited[pos] = true

	var current_ring: Array = _sorted_by_priority(seeds, noise_seed)

	while not current_ring.is_empty():
		var next_ring: Array = []
		for pos in current_ring:
			if not occupied.has(pos):
				positions.append(pos)
				if positions.size() >= count:
					return positions
			for offset in NEIGHBOR_OFFSETS:
				var neighbor: Vector2i = pos + offset
				if neighbor.x < 0 or neighbor.x >= World.WIDTH or neighbor.y < 0 or neighbor.y >= World.HEIGHT:
					continue
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				next_ring.append(neighbor)
		current_ring = _sorted_by_priority(next_ring, noise_seed)

	# Caso limite: zero semi di rumore (candidates iniziali vuote) fa terminare il ciclo sopra
	# all'istante, oppure la griglia è satura di `occupied` a tal punto che ogni ring possibile
	# è già stato visitato senza raccogliere abbastanza posizioni. Fallback: stesso principio di
	# ordine fisso per hash, senza più nozione di "ring", su tutte le celle rimaste libere e mai
	# visitate — sostituisce il vecchio fallback a rng.randi_range sequenziale (instabile) con
	# uno stabile allo stesso modo del resto dell'algoritmo.
	if positions.size() < count:
		var remaining: Array = []
		for y in range(World.HEIGHT):
			for x in range(World.WIDTH):
				var pos := Vector2i(x, y)
				if not occupied.has(pos):
					remaining.append(pos)
		for pos in _sorted_by_priority(remaining, noise_seed):
			if positions.size() >= count:
				break
			if not visited.has(pos):
				positions.append(pos)

	return positions


# Taglio netto (noise_value >= threshold) solo ben fuori dalla fascia SOFT_EDGE_BAND attorno
# alla soglia; dentro la fascia l'inclusione è probabilistica, decisa da un hash deterministico
# di (posizione, noise_seed) — NON da un rng sequenziale, per restare indipendente dall'ordine
# di iterazione (stesso stile già validato in MicroCellRenderer per bacche/frutti: hash puro
# della posizione, stesso seed = stesso risultato sempre, in qualunque ordine venga valutato).
static func _passes_soft_threshold(noise_value: float, threshold: float, pos: Vector2i, noise_seed: int) -> bool:
	var distance_from_threshold: float = noise_value - threshold
	if distance_from_threshold >= SOFT_EDGE_BAND:
		return true
	if distance_from_threshold <= -SOFT_EDGE_BAND:
		return false

	var inclusion_chance: float = (distance_from_threshold + SOFT_EDGE_BAND) / (2.0 * SOFT_EDGE_BAND)
	var hash_value: float = float(hash(pos * 3 + Vector2i(noise_seed, 727)) % 100000) / 100000.0
	return hash_value < inclusion_chance


# Priorità di spareggio pura, indipendente da quante altre celle sono in gioco in un dato
# momento (a differenza di un indice di shuffle Fisher-Yates, la cui posizione finale dipende
# dalla size dell'intero array shufflato) — stesso principio di _passes_soft_threshold sopra,
# salt diverso per non correlare le due sequenze hash.
static func _priority_hash(pos: Vector2i, noise_seed: int) -> float:
	return float(hash(pos * 7 + Vector2i(noise_seed, 1301)) % 100000) / 100000.0


# Ordina per _priority_hash con pattern decorate-sort-undecorate (l'hash di ogni cella va
# calcolato una sola volta, non ad ogni confronto di sort_custom).
static func _sorted_by_priority(cells: Array, noise_seed: int) -> Array:
	var decorated: Array = []
	for pos in cells:
		decorated.append([_priority_hash(pos, noise_seed), pos])
	decorated.sort_custom(func(a, b): return a[0] < b[0])

	var sorted_cells: Array = []
	for pair in decorated:
		sorted_cells.append(pair[1])
	return sorted_cells
