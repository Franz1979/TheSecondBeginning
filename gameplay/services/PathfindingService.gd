class_name PathfindingService
extends RefCounted

# Griglia di pathfinding per macrocella (2026-09-27, richiesta utente — step 1: griglia, regioni, overlay; step 2:
# WalkAction segue il percorso, vedi HumanIndividualMovementService). Stateless come MovementTerrainService: lo stato
# vive sulla LiveMacroCell (path_grid & co.), scritto solo da qui.
#
# Griglia: AStarGrid2D World.WIDTH x World.HEIGHT, una cella per microcella, diagonali solo senza ostacoli ai lati.
#   - Bloccate (regola MicrocellObstacles.is_free, con allow_river solo sui guadi e gli edifici MOVEMENT ignorati):
#     rocce, edifici non calpestabili (anche da cantiere, dal piazzamento), l'intera macrocella se è acqua, il fiume
#     tranne i guadi (MacroCellState.ford_positions, per ora sempre vuoto).
#   - Attraversabili: edifici MOVEMENT (anche da cantiere), mucchi a terra, alberi e vegetazione.
#   - Peso: moltiplicatore di stamina del terreno (LiveMacroCell.movement_modifiers, default 1); i guadi FORD_WEIGHT_SCALE.
# Specchio: LiveMacroCell.path_solid (PackedByteArray) riflette i blocchi della griglia, per il flood fill.
# Regioni: ogni microcella libera riceve l'id della sua regione connessa (flood fill a 4 vicini: con le diagonali
# ammesse solo senza ostacoli ai lati, la connettività a 8 coincide con quella a 4). Ricalcolo PIGRO: un cambio di
# blocco segna le regioni come da rifare, e le si rifà alla prossima get_region/is_reachable.
#
# Aggiornamento: costruzione completa solo all'ingresso nella macrocella (prima chiamata di sync_buildings, da
# GameScene._refresh_building_visuals, che gira anche all'attivazione della cella); poi, a ogni costruzione/
# demolizione, sync_buildings aggiorna SOLO le microcelle il cui edificio o peso è cambiato. Le rocce oggi non vengono
# mai rimosse (nessun evento da seguire).

# Peso dei guadi (per ora costante): attraversarli costa più del terreno normale.
const FORD_WEIGHT_SCALE: float = 3.0
# Righe di regioni stampate al massimo nel log (le più grandi per prime).
const MAX_LOGGED_REGIONS: int = 20

# Punto casuale dentro una microcella (2026-09-27): stesso scostamento 0,15–0,85 per asse già usato dalle task per non
# fermarsi sull'angolo (vedi random_point_in_microcell).
const MICROCELL_POINT_MIN: float = 0.15
const MICROCELL_POINT_MAX: float = 0.85
# Distanza entro cui chi segue un percorso passa al punto intermedio successivo (2026-09-27, lisciatura): i punti
# intermedi non vanno raggiunti esattamente; la destinazione finale sì.
const WAYPOINT_REACH_DISTANCE: float = 0.3
# Tentativi di sorteggio di una destinazione casuale libera e raggiungibile (vedi pick_free_destination).
const RANDOM_DESTINATION_ATTEMPTS: int = 8

# Celle vive di GameScene (macrocella -> LiveMacroCell), registrate una volta da GameScene._ready (stesso Dictionary,
# mai riassegnato): servono a pick_free_destination, chiamata da azioni e servizi che non hanno le celle vive.
static var _live_cells: Dictionary = {}


static func register_live_cells(live_cells: Dictionary) -> void:
	_live_cells = live_cells


# Cella viva della macrocella `macro_coords`, o null (2026-09-27, step 3 — per le azioni che pianificano da sé, es.
# ApproachPreyAction).
static func get_live_cell(macro_coords: Vector2i) -> LiveMacroCell:
	return _live_cells.get(macro_coords)


# Tutte le celle vive (macrocella -> LiveMacroCell), per chi non ha GameScene sotto mano (PatrolAreaAction).
static func get_live_cells() -> Dictionary:
	return _live_cells


# Punto casuale dentro la microcella il cui angolo in alto a sinistra è `corner` (coordinate già nel riferimento
# dell'individuo, macro_offset compreso): corner + (0,15–0,85, 0,15–0,85). Mai l'angolo esatto, che è condiviso con 3
# microcelle vicine (il disegno del pipottino ci cadrebbe dentro per un quarto ciascuna).
static func random_point_in_microcell(corner: Vector2) -> Vector2:
	return corner + Vector2(
		randf_range(MICROCELL_POINT_MIN, MICROCELL_POINT_MAX), randf_range(MICROCELL_POINT_MIN, MICROCELL_POINT_MAX)
	)


# Callable(Vector2i microcella) -> bool "microcella bloccata?" per gli animali della macrocella `macro_coords` (2026-09-27,
# pathfinding step 4 — AnimalGroupRenderer.blocked_test, che non conosce LiveMacroCell). Cella non viva o senza griglia:
# false (nessuna collisione, come prima). Valutato al momento della chiamata, sulla griglia aggiornata.
static func blocked_test_for(macro_coords: Vector2i) -> Callable:
	return func(microcell: Vector2i) -> bool:
		var cell: LiveMacroCell = _live_cells.get(macro_coords)
		if cell == null or cell.path_grid == null or not _in_bounds(microcell):
			return false
		return is_blocked(cell, microcell)


# Callable(candidato) -> bool "raggiungibile da `individual`?" per le ricerche di bersagli (2026-09-27, step 2b —
# SpatialSelectionService.find_nearest, WarehouseSelectionService, ThoughtTargetSelectionService). Il candidato
# espone macro_x/macro_y/micro_x/micro_y (es. Building). Valutato al momento della chiamata, dalla posizione attuale
# dell'individuo; solo con le regioni (is_reachable, mai A*). Un candidato in un'altra macrocella, o una cella senza
# griglia, vale come raggiungibile (nessun dato per dire di no; il passaggio di cella è gestito altrove).
static func reachability_for(individual: HumanIndividual) -> Callable:
	return func(candidate: Variant) -> bool:
		var cell: LiveMacroCell = _live_cells.get(individual.home_macro_coords)
		if cell == null or cell.path_grid == null:
			return true
		if Vector2i(candidate.macro_x, candidate.macro_y) != individual.home_macro_coords:
			return true
		var from := Vector2i(floori(individual.position.x), floori(individual.position.y))
		return is_reachable(cell, from, Vector2i(candidate.micro_x, candidate.micro_y))


# Destinazione casuale LIBERA e RAGGIUNGIBILE per `individual` (2026-09-27 — "allontanati" e riposi senza meta):
# `sampler` (Callable senza argomenti -> Vector2, nel riferimento dell'individuo) viene chiamato fino a
# RANDOM_DESTINATION_ATTEMPTS volte; vale il primo punto la cui microcella non è bloccata ed è raggiungibile dalla
# microcella dell'individuo (is_blocked / is_reachable, mai A*). Un punto fuori dalla macrocella dell'individuo è
# scartato. null = nessun tentativo valido: il chiamante lascia l'individuo dov'è. Senza griglia (cella non viva) vale
# il primo sorteggio, come prima.
static func pick_free_destination(individual: HumanIndividual, sampler: Callable) -> Variant:
	var cell: LiveMacroCell = _live_cells.get(individual.home_macro_coords)
	if cell == null or cell.path_grid == null:
		return sampler.call()
	var from := Vector2i(floori(individual.position.x), floori(individual.position.y))
	for _attempt in range(RANDOM_DESTINATION_ATTEMPTS):
		var candidate: Vector2 = sampler.call()
		var microcell := Vector2i(floori(candidate.x), floori(candidate.y))
		if is_blocked(cell, microcell) or not is_reachable(cell, from, microcell):
			continue
		return candidate
	if DebugLogging.ENABLED and DebugLogging.SHOW_PATHFINDING_LOGS:
		print("[PATHFINDING] #%d %s: nessuna destinazione casuale libera e raggiungibile in %d tentativi — resta dov'è." % [
			individual.id, individual.name, RANDOM_DESTINATION_ATTEMPTS
		])
	return null


# Costruzione completa della griglia della cella (ingresso nella macrocella).
static func rebuild(cell: LiveMacroCell, macro_world: World) -> void:
	var start_usec := Time.get_ticks_usec()
	var macro_coords := Vector2i(cell.macro_x, cell.macro_y)
	cell.path_obstacles = MicrocellObstacles.build(macro_coords, cell.macro_cell, cell.macro_state, cell.river_positions, macro_world)
	cell.path_fords.clear()
	if cell.macro_state != null:
		for position in cell.macro_state.ford_positions:
			cell.path_fords[position] = true
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, World.WIDTH, World.HEIGHT)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	cell.path_grid = grid

	var solid := PackedByteArray()
	solid.resize(World.WIDTH * World.HEIGHT)
	var obstacles := cell.path_obstacles
	var blocked_count := 0
	if not obstacles.cell_known or obstacles.water_cell:
		grid.fill_solid_region(grid.region, true)
		solid.fill(1)
		blocked_count = solid.size()
	else:
		solid.fill(0)
		# Solo le microcelle candidate a essere bloccate (insiemi degli ostacoli), non tutte le 10000.
		for candidates in [obstacles.stones, obstacles.blocking_buildings, obstacles.river]:
			for position in (candidates as Dictionary).keys():
				if not _in_bounds(position) or solid[_index(position)] == 1:
					continue
				if _is_blocked_by_rule(cell, position):
					grid.set_point_solid(position, true)
					solid[_index(position)] = 1
					blocked_count += 1
	cell.path_solid = solid
	cell.path_weights = _compute_weights(cell)
	for position in cell.path_weights.keys():
		if _in_bounds(position):
			grid.set_point_weight_scale(position, float(cell.path_weights[position]))
	cell.path_regions_dirty = true
	cell.path_block_version += 1
	cell.path_grid_version += 1
	if DebugLogging.ENABLED and DebugLogging.SHOW_PATHFINDING_LOGS:
		print("[PATHFINDING] griglia %s costruita in %.2f ms: %d microcelle bloccate (regioni calcolate alla prima richiesta)." % [
			macro_coords, (Time.get_ticks_usec() - start_usec) / 1000.0, blocked_count
		])


# Costruzione/demolizione di edifici (e ingresso nella macrocella, se la griglia non esiste ancora): aggiorna solo le
# microcelle il cui edificio bloccante o il cui peso è cambiato; un cambio di blocco segna le regioni da rifare.
static func sync_buildings(cell: LiveMacroCell, macro_world: World) -> void:
	if cell.path_grid == null or cell.path_obstacles == null:
		rebuild(cell, macro_world)
		return
	var start_usec := Time.get_ticks_usec()
	var macro_coords := Vector2i(cell.macro_x, cell.macro_y)
	var old_blocking: Dictionary = cell.path_obstacles.blocking_buildings.duplicate()
	cell.path_obstacles.refresh_buildings(macro_coords, macro_world)
	var changed: Dictionary = {}
	for position in old_blocking.keys():
		if not cell.path_obstacles.blocking_buildings.has(position):
			changed[position] = true
	for position in cell.path_obstacles.blocking_buildings.keys():
		if not old_blocking.has(position):
			changed[position] = true
	var new_weights := _compute_weights(cell)
	for position in cell.path_weights.keys():
		if float(new_weights.get(position, 1.0)) != float(cell.path_weights[position]):
			changed[position] = true
	for position in new_weights.keys():
		if not cell.path_weights.has(position):
			changed[position] = true
	cell.path_weights = new_weights
	if changed.is_empty():
		return

	var solid := cell.path_solid
	var blocking_changed := false
	for position in changed.keys():
		if not _in_bounds(position):
			continue
		var blocked := _is_blocked_by_rule(cell, position)
		var index := _index(position)
		if (solid[index] == 1) != blocked:
			blocking_changed = true
			solid[index] = 1 if blocked else 0
			cell.path_grid.set_point_solid(position, blocked)
		cell.path_grid.set_point_weight_scale(position, float(new_weights.get(position, 1.0)))
	cell.path_solid = solid
	if blocking_changed:
		cell.path_regions_dirty = true
		cell.path_block_version += 1
	cell.path_grid_version += 1
	if DebugLogging.ENABLED and DebugLogging.SHOW_PATHFINDING_LOGS:
		var update_usec := Time.get_ticks_usec() - start_usec
		print("[PATHFINDING] griglia %s: %d microcelle aggiornate in %.3f ms (%.3f ms per microcella), %s." % [
			macro_coords, changed.size(), update_usec / 1000.0, update_usec / 1000.0 / float(changed.size()),
			"blocchi cambiati: regioni da rifare, percorsi in corso da ricalcolare" if blocking_changed else "solo pesi, blocchi invariati"
		])


# Roccia esaurita dall'estrazione (2026-10-08, RockStoneService.is_depleted): la sua microcella esce dagli ostacoli e,
# se nient'altro la blocca, diventa calpestabile per pipottini e animali; un cambio di blocco segna le regioni da rifare,
# come sync_buildings. Senza griglia non fa nulla: la prossima rebuild salta già le rocce esaurite.
static func release_stone(cell: LiveMacroCell, position: Vector2i) -> void:
	if cell == null or cell.path_grid == null or cell.path_obstacles == null:
		return
	if not cell.path_obstacles.stones.erase(position) or not _in_bounds(position):
		return
	var solid := cell.path_solid
	var blocked := _is_blocked_by_rule(cell, position)
	var index := _index(position)
	if (solid[index] == 1) != blocked:
		solid[index] = 1 if blocked else 0
		cell.path_grid.set_point_solid(position, blocked)
		cell.path_solid = solid
		cell.path_regions_dirty = true
		cell.path_block_version += 1
	cell.path_grid_version += 1


# true se la microcella è bloccata (o fuori dalla macrocella, o griglia non ancora costruita).
static func is_blocked(cell: LiveMacroCell, microcell: Vector2i) -> bool:
	if cell == null or cell.path_grid == null or not _in_bounds(microcell):
		return true
	return cell.path_solid[_index(microcell)] == 1


# Id della regione connessa della microcella, -1 se bloccata, fuori dalla macrocella o griglia assente. Ricalcola le
# regioni se sono da rifare.
static func get_region(cell: LiveMacroCell, microcell: Vector2i) -> int:
	if cell == null or cell.path_grid == null or not _in_bounds(microcell):
		return -1
	_ensure_regions(cell)
	return cell.path_regions[_index(microcell)]


# true se da `from` si può arrivare a `to` dentro la macrocella, SOLO con le regioni (mai A*). Una microcella
# bloccata (partenza su un sasso, destinazione su un edificio) vale per le regioni delle sue microcelle libere
# adiacenti (4 vicini: una diagonale ammessa implica i due lati liberi, quindi basta). Fuori dalla macrocella o senza
# griglia: true (nessun dato per dire di no; il passaggio tra celle è gestito altrove).
static func is_reachable(cell: LiveMacroCell, from: Vector2i, to: Vector2i) -> bool:
	if cell == null or cell.path_grid == null or not _in_bounds(from) or not _in_bounds(to):
		return true
	if from == to:
		return true
	_ensure_regions(cell)
	var from_regions := _regions_around(cell, from)
	if from_regions.is_empty():
		return false
	for region in _regions_around(cell, to):
		if from_regions.has(region):
			return true
	return false


# Percorso di microcelle da `from` a `to` (compresi), dentro la macrocella; vuoto se non esiste (verificato prima con
# is_reachable, senza A*). Partenza e destinazione sono sempre attraversabili: se bloccate vengono sbloccate solo per
# questa ricerca.
static func find_path(cell: LiveMacroCell, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if cell == null or cell.path_grid == null or not _in_bounds(from) or not _in_bounds(to):
		return empty
	if not is_reachable(cell, from, to):
		return empty
	var grid := cell.path_grid
	var from_was_blocked := cell.path_solid[_index(from)] == 1
	var to_was_blocked := cell.path_solid[_index(to)] == 1
	if from_was_blocked:
		grid.set_point_solid(from, false)
	if to_was_blocked:
		grid.set_point_solid(to, false)
	var path: Array[Vector2i] = grid.get_id_path(from, to)
	if from_was_blocked:
		grid.set_point_solid(from, true)
	if to_was_blocked:
		grid.set_point_solid(to, true)
	# Lisciatura (2026-09-27): tutti i chiamanti (pipottini, visitatori, ricalcoli per cambio di blocco) ricevono il
	# percorso già semplificato.
	return simplify_path(cell, path)


# Semplificazione del percorso (2026-09-27, lisciatura): da ogni punto tenuto si salta al punto più lontano del percorso
# raggiungibile in linea retta (dal centro al centro delle microcelle) passando SOLO da microcelle libere, senza
# tagliare spigoli di microcelle bloccate (un passaggio esatto per un angolo richiede libere entrambe le celle ai lati)
# e senza microcelle di peso maggiore del massimo del tratto originale saltato. Partenza e destinazione restano sempre
# (possono essere bloccate: trattate come attraversabili, come in find_path). Percorsi di 0–2 punti: invariati.
static func simplify_path(cell: LiveMacroCell, path: Array[Vector2i]) -> Array[Vector2i]:
	if path.size() <= 2 or cell == null or cell.path_grid == null:
		return path
	var first: Vector2i = path[0]
	var last: Vector2i = path[path.size() - 1]
	var result: Array[Vector2i] = [first]
	var anchor := 0
	var probe := anchor + 1
	var max_weight := maxf(_weight_of(cell, path[anchor]), _weight_of(cell, path[probe]))
	while probe < path.size() - 1:
		var next_weight := maxf(max_weight, _weight_of(cell, path[probe + 1]))
		if _segment_clear(cell, path[anchor], path[probe + 1], next_weight, first, last):
			probe += 1
			max_weight = next_weight
			continue
		result.append(path[probe])
		anchor = probe
		probe = anchor + 1
		max_weight = maxf(_weight_of(cell, path[anchor]), _weight_of(cell, path[probe]))
	result.append(last)
	return result


static func _weight_of(cell: LiveMacroCell, microcell: Vector2i) -> float:
	return float(cell.path_weights.get(microcell, 1.0))


# true se il segmento dal centro di `a` al centro di `b` attraversa solo microcelle libere e di peso <= max_weight
# (traversata a griglia: ogni microcella toccata; al passaggio esatto per uno spigolo devono essere libere entrambe le
# celle ai lati). `exempt_a`/`exempt_b` (partenza e destinazione del percorso) sono sempre ammesse.
static func _segment_clear(cell: LiveMacroCell, a: Vector2i, b: Vector2i, max_weight: float, exempt_a: Vector2i, exempt_b: Vector2i) -> bool:
	var start := Vector2(a) + Vector2(0.5, 0.5)
	var direction := (Vector2(b) + Vector2(0.5, 0.5)) - start
	var x := a.x
	var y := a.y
	var step_x := 1 if direction.x > 0.0 else -1
	var step_y := 1 if direction.y > 0.0 else -1
	var t_delta_x := absf(1.0 / direction.x) if direction.x != 0.0 else INF
	var t_delta_y := absf(1.0 / direction.y) if direction.y != 0.0 else INF
	# Dal centro della cella il primo bordo è a mezza cella.
	var t_max_x := 0.5 * t_delta_x
	var t_max_y := 0.5 * t_delta_y
	var guard := absi(b.x - a.x) + absi(b.y - a.y) + 2
	while Vector2i(x, y) != b and guard > 0:
		guard -= 1
		if absf(t_max_x - t_max_y) < 0.000001:
			# Passaggio esatto per uno spigolo: entrambe le celle ai lati devono essere libere.
			if not _cell_ok(cell, Vector2i(x + step_x, y), max_weight, exempt_a, exempt_b) \
					or not _cell_ok(cell, Vector2i(x, y + step_y), max_weight, exempt_a, exempt_b):
				return false
			x += step_x
			y += step_y
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			x += step_x
			t_max_x += t_delta_x
		else:
			y += step_y
			t_max_y += t_delta_y
		if not _cell_ok(cell, Vector2i(x, y), max_weight, exempt_a, exempt_b):
			return false
	return Vector2i(x, y) == b


static func _cell_ok(cell: LiveMacroCell, microcell: Vector2i, max_weight: float, exempt_a: Vector2i, exempt_b: Vector2i) -> bool:
	if microcell == exempt_a or microcell == exempt_b:
		return true
	if not _in_bounds(microcell) or cell.path_solid[_index(microcell)] == 1:
		return false
	return _weight_of(cell, microcell) <= max_weight + 0.000001


# Numero di regioni connesse (ricalcolate se da rifare).
static func get_region_count(cell: LiveMacroCell) -> int:
	if cell == null or cell.path_grid == null:
		return 0
	_ensure_regions(cell)
	return cell.path_region_count


# Numero di microcelle bloccate (log e overlay).
static func count_blocked(cell: LiveMacroCell) -> int:
	if cell == null or cell.path_grid == null:
		return 0
	return cell.path_solid.count(1)


# Blocco di UNA microcella secondo la regola condivisa (MicrocellObstacles.is_free): guado = fiume ammesso, edifici
# MOVEMENT ignorati. Acqua dell'intera macrocella compresa (is_free la rifiuta).
static func _is_blocked_by_rule(cell: LiveMacroCell, position: Vector2i) -> bool:
	return not cell.path_obstacles.is_free(position, false, cell.path_fords.has(position), false, true)


# Pesi diversi da 1: moltiplicatore di stamina del terreno (movement_modifiers.x), i guadi FORD_WEIGHT_SCALE.
static func _compute_weights(cell: LiveMacroCell) -> Dictionary:
	var weights: Dictionary = {}
	for position in cell.movement_modifiers.keys():
		var stamina_multiplier: float = (cell.movement_modifiers[position] as Vector2).x
		if stamina_multiplier != 1.0:
			weights[position] = stamina_multiplier
	for position in cell.path_fords.keys():
		weights[position] = FORD_WEIGHT_SCALE
	return weights


# Regioni delle microcelle libere tra `position` stessa (se libera) e, se bloccata, i suoi 4 vicini liberi.
static func _regions_around(cell: LiveMacroCell, position: Vector2i) -> Array[int]:
	var regions: Array[int] = []
	var index := _index(position)
	if cell.path_solid[index] == 0:
		regions.append(cell.path_regions[index])
		return regions
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor: Vector2i = position + offset
		if not _in_bounds(neighbor):
			continue
		var region: int = cell.path_regions[_index(neighbor)]
		if region != -1 and not regions.has(region):
			regions.append(region)
	return regions


static func _ensure_regions(cell: LiveMacroCell) -> void:
	if cell.path_regions_dirty or cell.path_regions.size() != World.WIDTH * World.HEIGHT:
		_recompute_regions(cell)


# Flood fill a 4 vicini delle microcelle libere, solo su PackedInt32Array/PackedByteArray e indici interi (niente
# dizionari né Vector2i per cella), con una coda a indice di testa. Aggiorna path_regions/path_region_count.
static func _recompute_regions(cell: LiveMacroCell) -> void:
	var start_usec := Time.get_ticks_usec()
	var width := World.WIDTH
	var total := World.WIDTH * World.HEIGHT
	var solid := cell.path_solid
	var regions := PackedInt32Array()
	regions.resize(total)
	regions.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(total)
	var region_sizes := PackedInt32Array()
	var region_samples := PackedInt32Array()
	var region_count := 0
	for start_index in range(total):
		if solid[start_index] == 1 or regions[start_index] != -1:
			continue
		regions[start_index] = region_count
		var head := 0
		var tail := 0
		queue[tail] = start_index
		tail += 1
		while head < tail:
			var index: int = queue[head]
			head += 1
			var x := index % width
			if x > 0 and solid[index - 1] == 0 and regions[index - 1] == -1:
				regions[index - 1] = region_count
				queue[tail] = index - 1
				tail += 1
			if x < width - 1 and solid[index + 1] == 0 and regions[index + 1] == -1:
				regions[index + 1] = region_count
				queue[tail] = index + 1
				tail += 1
			if index >= width and solid[index - width] == 0 and regions[index - width] == -1:
				regions[index - width] = region_count
				queue[tail] = index - width
				tail += 1
			if index + width < total and solid[index + width] == 0 and regions[index + width] == -1:
				regions[index + width] = region_count
				queue[tail] = index + width
				tail += 1
		region_sizes.append(tail)
		region_samples.append(start_index)
		region_count += 1
	cell.path_regions = regions
	cell.path_region_count = region_count
	cell.path_regions_dirty = false
	if DebugLogging.ENABLED and DebugLogging.SHOW_PATHFINDING_LOGS:
		var order: Array[int] = []
		for i in range(region_count):
			order.append(i)
		order.sort_custom(func(a: int, b: int) -> bool: return region_sizes[a] > region_sizes[b])
		var parts := PackedStringArray()
		for i in range(mini(order.size(), MAX_LOGGED_REGIONS)):
			var region: int = order[i]
			parts.append("#%d: %d celle, es. (%d,%d)" % [region, region_sizes[region], region_samples[region] % width, region_samples[region] / width])
		print("[PATHFINDING] regioni %s ricalcolate in %.2f ms: %d regioni%s%s." % [
			Vector2i(cell.macro_x, cell.macro_y), (Time.get_ticks_usec() - start_usec) / 1000.0, region_count,
			(" — " + "; ".join(parts)) if not parts.is_empty() else "",
			(" (+%d più piccole)" % (region_count - MAX_LOGGED_REGIONS)) if region_count > MAX_LOGGED_REGIONS else ""
		])


static func _index(position: Vector2i) -> int:
	return position.y * World.WIDTH + position.x


static func _in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.x < World.WIDTH and position.y < World.HEIGHT
