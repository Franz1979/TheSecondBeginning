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
#   - Peso (2026-10-16, richiesta utente — perché terra battuta e sentieri vengano scelti davvero): costo di una
#     microcella = fatica / velocità (LiveMacroCell.movement_modifiers), con il vantaggio sul terreno normale amplificato
#     da ROAD_PREFERENCE; poi NORMALIZZATO così che la microcella più conveniente (il miglior edificio MOVEMENT dei dati)
#     pesi 1 e le altre di più (terreno normale = terrain_weight()). Pesi tutti >= 1 tengono ammissibile l'euristica
#     OCTILE di AStarGrid2D (che stima 1 per microcella): prima, con pesi < 1, A* non trovava le strade. Solo la scelta
#     del percorso: fatica e velocità vere restano quelle di MovementTerrainService. I guadi: FORD_WEIGHT_SCALE × terreno.
# Specchio: LiveMacroCell.path_solid (PackedByteArray) riflette i blocchi della griglia, per il flood fill.
# Regioni: ogni microcella libera riceve l'id della sua regione connessa (flood fill a 4 vicini: con le diagonali
# ammesse solo senza ostacoli ai lati, la connettività a 8 coincide con quella a 4). Ricalcolo PIGRO: un cambio di
# blocco segna le regioni come da rifare, e le si rifà alla prossima get_region/is_reachable.
# Sacche chiuse (2026-10-27, richiesta utente — pipottini morti di fame chiusi tra le rocce): una regione di al più
# POCKET_MAX_CELLS microcelle che non tocca il bordo della macrocella. Ci si entrava partendo da una roccia (i ciottoli si
# raccolgono sopra la roccia, e una partenza bloccata vale per tutte le regioni che tocca), poi la roccia tornava
# ostacolo e non si usciva più. Ora una sacca non è mai una destinazione per chi non ci sta già dentro (is_reachable), e
# chi è dentro esce per la via d'uscita: il passaggio più corto attraverso le sole rocce fino a una regione aperta.
#
# Aggiornamento: costruzione completa solo all'ingresso nella macrocella (prima chiamata di sync_buildings, da
# GameScene._refresh_building_visuals, che gira anche all'attivazione della cella); poi, a ogni costruzione/
# demolizione, sync_buildings aggiorna SOLO le microcelle il cui edificio o peso è cambiato. Le rocce oggi non vengono
# mai rimosse (nessun evento da seguire).

# Peso dei guadi (per ora costante): attraversarli costa più del terreno normale.
const FORD_WEIGHT_SCALE: float = 3.0
# Preferenza per le strade (2026-10-16, richiesta utente): il vantaggio sul terreno normale (1 − costo) moltiplicato, solo
# nella scelta del percorso. 4 (2026-10-18, era 2: i pipottini tagliavano nel bosco, che pesa quanto il terreno) =
# sentiero di ciottoli visto a ~0.43 invece di ~0.86, terra battuta a 0.80 invece di 0.95: terreno normale ~2.33 volte il
# sentiero, quindi il sentiero conviene finché la deviazione allunga meno di ~2.3 volte.
const ROAD_PREFERENCE: float = 4.0
# Costo minimo ammesso dopo la preferenza (difensivo: un costo <= 0 romperebbe la normalizzazione).
const MIN_PATH_COST: float = 0.05
# Costo (dopo la preferenza) della microcella più conveniente possibile: il miglior edificio MOVEMENT dei dati, 1.0 se
# nessuno è migliore del terreno. Calcolato una volta (i .tres non cambiano in partita).
static var _best_cost: float = -1.0
# Righe di regioni stampate al massimo nel log (le più grandi per prime).
const MAX_LOGGED_REGIONS: int = 20

# Punto casuale dentro una microcella (2026-09-27): stesso scostamento 0,15–0,85 per asse già usato dalle task per non
# fermarsi sull'angolo (vedi random_point_in_microcell).
const MICROCELL_POINT_MIN: float = 0.15
const MICROCELL_POINT_MAX: float = 0.85
# Distanza entro cui chi segue un percorso passa al punto intermedio successivo (2026-09-27, lisciatura): i punti
# intermedi non vanno raggiunti esattamente; la destinazione finale sì.
const WAYPOINT_REACH_DISTANCE: float = 0.3
# Sacca chiusa (vedi in testa): dimensione massima, in microcelle, di una regione senza contatto col bordo.
const POCKET_MAX_CELLS: int = 40
const NO_POCKET_EXIT := Vector2i(-1, -1)
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
	# Terreno normale prima di tutto (pesi normalizzati, vedi in cima), poi le microcelle che deviano.
	grid.fill_weight_scale_region(grid.region, terrain_weight())
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
		if float(new_weights.get(position, terrain_weight())) != float(cell.path_weights[position]):
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
		cell.path_grid.set_point_weight_scale(position, float(new_weights.get(position, terrain_weight())))
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
	# Sacche (2026-10-27): ci entra solo chi ci sta già dentro; chi è dentro vale anche per la regione della via d'uscita.
	var own_region: int = cell.path_regions[_index(from)]
	if own_region != -1 and _is_pocket(cell, own_region):
		var exit := _pocket_exit(cell, own_region, from)
		if exit != NO_POCKET_EXIT:
			from_regions.append(cell.path_regions[_index(exit)])
	for region in _regions_around(cell, to):
		if _is_pocket(cell, region) and region != own_region:
			continue
		if from_regions.has(region):
			return true
	return false


# Percorso di microcelle da `from` a `to` (compresi), dentro la macrocella; vuoto se non esiste (verificato prima con
# is_reachable, senza A*). Partenza e destinazione sono sempre attraversabili: se bloccate vengono sbloccate solo per
# questa ricerca.
# Barriere (2026-10-23, richiesta utente — MicrocellObstacles.is_barrier: palizzata, vallo, cancello chiuso): se `to` è
# una loro microcella il percorso finisce sulla microcella libera prima, dal lato da cui si arriva (l'ultima cella è
# allora diversa da `to`: chi chiama si ferma lì). Prima si poteva arrivare sopra la barriera e, ripartendo da lì,
# uscire dall'altra parte.
static func find_path(cell: LiveMacroCell, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if cell == null or cell.path_grid == null or not _in_bounds(from) or not _in_bounds(to):
		return empty
	if not is_reachable(cell, from, to):
		return empty
	# Via d'uscita (2026-10-27): chi è chiuso in una sacca e va fuori passa prima attraverso le rocce fino alla regione
	# aperta più vicina, poi prosegue col percorso normale (lisciato solo quello: la via d'uscita attraversa ostacoli).
	var own_region: int = cell.path_regions[_index(from)]
	if own_region != -1 and _is_pocket(cell, own_region) and not _regions_around(cell, to).has(own_region):
		var escape := _escape_route(cell, from)
		if escape.is_empty():
			return empty
		var rest := find_path(cell, escape[escape.size() - 1], to)
		if rest.is_empty():
			return empty
		if DebugLogging.ENABLED and DebugLogging.SHOW_PATHFINDING_LOGS:
			print("[PATHFINDING] %s: via d'uscita dalla sacca %s -> %s (%d microcelle tra le rocce)." % [
				Vector2i(cell.macro_x, cell.macro_y), from, escape[escape.size() - 1], escape.size()
			])
		escape.resize(escape.size() - 1)
		escape.append_array(rest)
		return escape
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
	if path.size() >= 2 and cell.path_obstacles != null and cell.path_obstacles.is_barrier(to):
		path.resize(path.size() - 1)
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
	return float(cell.path_weights.get(microcell, terrain_weight()))


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


# Pesi diversi da quello del terreno normale: le microcelle con modificatori di movimento (path_weight) e i guadi.
static func _compute_weights(cell: LiveMacroCell) -> Dictionary:
	var weights: Dictionary = {}
	var terrain := terrain_weight()
	for position in cell.movement_modifiers.keys():
		var modifier: Vector2 = cell.movement_modifiers[position]
		var weight := path_weight(modifier.x, modifier.y)
		if not is_equal_approx(weight, terrain):
			weights[position] = weight
	for position in cell.path_fords.keys():
		weights[position] = FORD_WEIGHT_SCALE * terrain
	return weights


# Costo di una microcella per la scelta del percorso: fatica / velocità, con il vantaggio sul terreno normale (costo < 1)
# moltiplicato per ROAD_PREFERENCE; uno svantaggio (> 1) resta com'è.
static func path_cost(stamina_multiplier: float, speed_multiplier: float) -> float:
	var cost := stamina_multiplier / maxf(speed_multiplier, 0.01)
	if cost < 1.0:
		cost = 1.0 - (1.0 - cost) * ROAD_PREFERENCE
	return maxf(cost, MIN_PATH_COST)


# Peso nella griglia: costo / costo della microcella più conveniente (sempre >= 1 per i modificatori dei dati).
static func path_weight(stamina_multiplier: float, speed_multiplier: float) -> float:
	return path_cost(stamina_multiplier, speed_multiplier) / _get_best_cost()


# Peso del terreno normale (fatica e velocità 1): 1 / costo della microcella più conveniente (es. ~1.4 col sentiero).
static func terrain_weight() -> float:
	return 1.0 / _get_best_cost()


static func _get_best_cost() -> float:
	if _best_cost > 0.0:
		return _best_cost
	var best := 1.0
	for type_name in BuildingCalculator.list_building_type_names():
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules == null or rules.category != BuildingTypes.Category.MOVEMENT:
			continue
		best = minf(best, path_cost(rules.movement_stamina_multiplier, rules.movement_speed_multiplier))
	_best_cost = best
	return _best_cost


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


# true se la regione `region` è una sacca chiusa (vedi in testa).
static func _is_pocket(cell: LiveMacroCell, region: int) -> bool:
	return region >= 0 and region < cell.path_region_pocket.size() and cell.path_region_pocket[region] == 1


# Microcella d'arrivo della via d'uscita dalla sacca `region` (cercata da `from` la prima volta, poi tenuta fino al
# prossimo ricalcolo delle regioni); NO_POCKET_EXIT se non c'è.
static func _pocket_exit(cell: LiveMacroCell, region: int, from: Vector2i) -> Vector2i:
	if not cell.path_pocket_exits.has(region):
		var route := _escape_route(cell, from)
		cell.path_pocket_exits[region] = route[route.size() - 1] if not route.is_empty() else NO_POCKET_EXIT
	return cell.path_pocket_exits[region]


# Via d'uscita da `from`: ricerca in ampiezza a 4 vicini che attraversa microcelle libere e rocce (nient'altro: edifici,
# fiume e acqua restano ostacoli) fino alla prima microcella libera fuori da ogni sacca. Percorso da `from` a quella
# microcella compresi; vuoto se non c'è.
static func _escape_route(cell: LiveMacroCell, from: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	if cell.path_obstacles == null:
		return route
	var width := World.WIDTH
	var total := World.WIDTH * World.HEIGHT
	var parents := PackedInt32Array()
	parents.resize(total)
	parents.fill(-2)
	var queue := PackedInt32Array()
	queue.resize(total)
	var head := 0
	var tail := 0
	var start := _index(from)
	parents[start] = -1
	queue[tail] = start
	tail += 1
	var found := -1
	while head < tail:
		var index: int = queue[head]
		head += 1
		if cell.path_solid[index] == 0 and not _is_pocket(cell, cell.path_regions[index]):
			found = index
			break
		var position := Vector2i(index % width, index / width)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = position + offset
			if not _in_bounds(neighbor):
				continue
			var neighbor_index := _index(neighbor)
			if parents[neighbor_index] != -2:
				continue
			if cell.path_solid[neighbor_index] == 1 and not cell.path_obstacles.stones.has(neighbor):
				continue
			parents[neighbor_index] = index
			queue[tail] = neighbor_index
			tail += 1
	if found == -1:
		return route
	var current := found
	while current != -1:
		route.push_front(Vector2i(current % width, current / width))
		current = parents[current]
	return route


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
	var pockets := PackedByteArray()
	var region_count := 0
	var height := World.HEIGHT
	for start_index in range(total):
		if solid[start_index] == 1 or regions[start_index] != -1:
			continue
		regions[start_index] = region_count
		var head := 0
		var tail := 0
		queue[tail] = start_index
		tail += 1
		var touches_border := false
		while head < tail:
			var index: int = queue[head]
			head += 1
			var x := index % width
			if x == 0 or x == width - 1 or index < width or index >= (height - 1) * width:
				touches_border = true
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
		pockets.append(1 if not touches_border and tail <= POCKET_MAX_CELLS else 0)
		region_count += 1
	cell.path_regions = regions
	cell.path_region_count = region_count
	cell.path_region_pocket = pockets
	cell.path_pocket_exits.clear()
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
