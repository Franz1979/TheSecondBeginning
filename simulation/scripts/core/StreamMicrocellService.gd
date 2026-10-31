class_name StreamMicrocellService
extends RefCounted

# Ruscelli dentro una macrocella (passo 2 dell'acqua): dal dato macro di StreamNetworkGenerator
# (stream_edges/stream_has_spring) al tracciato in microcelle. Funzione pura e deterministica
# (solo hash delle coordinate, nessun random libero): la stessa cella dà sempre lo stesso
# tracciato, senza salvarlo. Usato sia dal disegno (MicroCellRenderer.set_streams) sia dalla logica
# (vegetazione, pathfinding, ostacoli), così ciò che si vede e ciò che si calpesta coincidono.
#
# Geometria:
#   - punto sul bordo: ogni lato toccato ha un punto d'ingresso calcolato dall'hash del BORDO
#     CONDIVISO (non della cella), così le due celle vicine trovano la stessa microcella senza
#     salvarla e il ruscello continua senza salti;
#   - giunzione: un punto interno (hash della cella) dove si incontrano i tratti di tutti i lati;
#   - ogni tratto va dal bordo alla giunzione serpeggiando, largo 1 microcella, con qualche
#     insenatura da 2;
#   - sorgente: una pozza di poche microcelle sulla giunzione;
#   - cella-fiume: i ruscelli delle vicine che ci sfociano proseguono dal bordo fino alla fascia
#     del fiume (la cella-fiume non ha stream_edges propri).

const EDGE_OFFSET_MIN := 15
const EDGE_OFFSET_MAX := 84
const JUNCTION_MIN := 30
const JUNCTION_MAX := 69
# Serpeggiamento: ampiezza massima della curva, come frazione della lunghezza del tratto.
const MEANDER_MAIN_RATIO := 0.18
const MEANDER_SECOND_RATIO := 0.07
# Probabilità che una microcella del tratto abbia un'insenatura accanto (larghezza 2).
const WIDENING_CHANCE := 0.08
# Microcelle iniziali di ogni tratto senza insenature: il passaggio di bordo resta largo 1.
const WIDENING_EDGE_MARGIN := 3
# Pozza della sorgente: raggio in microcelle (1.6 = circa 9 microcelle).
const POND_RADIUS := 1.6

const _DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

# Cache di sessione: i ruscelli non cambiano in partita. Chiave "id_mondo:x:y".
static var _cache: Dictionary = {}


# Microcelle d'acqua del ruscello della macrocella (Vector2i -> true), vuoto se non ce n'è.
static func get_positions(world: World, cell: MacroCellData) -> Dictionary:
	return get_layout(world, cell)["positions"]


# Tratto del ruscello largo 1 (2026-10-31, Guado di pietre — BuildingRules.requires_narrow_stream): `pos` è ruscello,
# ha al massimo due vicini di ruscello (N/E/S/O) e non fa parte di nessun quadrato 2x2 di ruscello (insenature, pozza).
static func is_narrow(positions: Dictionary, pos: Vector2i) -> bool:
	if not positions.has(pos):
		return false
	var neighbors := 0
	for direction in _DIRECTIONS:
		if positions.has(pos + direction):
			neighbors += 1
	if neighbors > 2:
		return false
	for corner in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var origin: Vector2i = pos + corner
		if positions.has(origin) and positions.has(origin + Vector2i(1, 0)) and positions.has(origin + Vector2i(0, 1)) \
				and positions.has(origin + Vector2i(1, 1)):
			return false
	return true


# Tracciato completo:
#   "positions": Dictionary Vector2i -> true (logica: tratti, insenature, pozza);
#   "paths": Array di PackedVector2Array, linee centrali in unità di microcella (per il disegno);
#   "widenings": Array di Vector2 (centro dell'insenatura, unità di microcella);
#   "pond_center": Vector2 (unità di microcella) o null se non c'è sorgente.
static func get_layout(world: World, cell: MacroCellData) -> Dictionary:
	if world == null or cell == null:
		return _empty_layout()
	var key := "%d:%d:%d" % [world.get_instance_id(), cell.x, cell.y]
	if _cache.has(key):
		return _cache[key]
	var layout := _build_layout(world, cell)
	_cache[key] = layout
	return layout


static func _empty_layout() -> Dictionary:
	return {"positions": {}, "paths": [], "widenings": [], "pond_center": null}


static func _build_layout(world: World, cell: MacroCellData) -> Dictionary:
	var layout := _empty_layout()
	if not StreamNetworkGenerator.STREAMS_ENABLED:
		return layout
	if cell.terrain_base == GameTypes.TerrainBase.WATER:
		return layout
	if cell.water_type == GameTypes.WaterType.RIVER:
		_build_river_mouths(world, cell, layout)
		return layout
	if cell.stream_edges == 0 and not cell.stream_has_spring:
		return layout

	var junction := Vector2i(
		JUNCTION_MIN + _hash(cell.x, cell.y, 11) % (JUNCTION_MAX - JUNCTION_MIN + 1),
		JUNCTION_MIN + _hash(cell.x, cell.y, 12) % (JUNCTION_MAX - JUNCTION_MIN + 1)
	)
	for d in range(4):
		if not (cell.stream_edges & StreamNetworkGenerator.DIRECTION_EDGES[d]):
			continue
		var start := _edge_microcell(cell.x, cell.y, d)
		var path_cells := _trace(start, junction, _hash(cell.x, cell.y, 20 + d), {})
		_add_path(layout, path_cells, d, _hash(cell.x, cell.y, 30 + d))
	if cell.stream_has_spring:
		layout["pond_center"] = Vector2(junction) + Vector2(0.5, 0.5)
		var reach := int(ceil(POND_RADIUS))
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if Vector2(dx, dy).length() <= POND_RADIUS:
					var pos := junction + Vector2i(dx, dy)
					if _in_bounds(pos):
						layout["positions"][pos] = true
	return layout


# Ruscelli delle vicine che sfociano in questa cella-fiume: dal bordo verso il centro, fermandosi
# sulla prima microcella della fascia del fiume.
static func _build_river_mouths(world: World, cell: MacroCellData, layout: Dictionary) -> void:
	var river: Dictionary = RiverMicrocellService.get_water_microcells(world, cell)
	var center := Vector2i(World.WIDTH / 2, World.HEIGHT / 2)
	for d in range(4):
		var direction: Vector2i = _DIRECTIONS[d]
		var neighbor := world.get_cell_at(cell.x + direction.x, cell.y + direction.y)
		if neighbor == null or neighbor.water_type == GameTypes.WaterType.RIVER:
			continue
		var edge_toward_us := StreamNetworkGenerator.opposite_edge(StreamNetworkGenerator.DIRECTION_EDGES[d])
		if not (neighbor.stream_edges & edge_toward_us):
			continue
		var start := _edge_microcell(cell.x, cell.y, d)
		if river.has(start):
			continue
		var path_cells := _trace(start, center, _hash(cell.x, cell.y, 40 + d), river)
		_add_path(layout, path_cells, d, _hash(cell.x, cell.y, 50 + d))


# Aggiunge un tratto al tracciato: microcelle, linea centrale per il disegno (con il punto esatto
# sul bordo della cella in testa, così il nastro tocca quello della cella vicina) e insenature.
static func _add_path(layout: Dictionary, path_cells: Array[Vector2i], direction: int, seed_value: int) -> void:
	if path_cells.is_empty():
		return
	var positions: Dictionary = layout["positions"]
	var centers := PackedVector2Array()
	var first := path_cells[0]
	var border_point := Vector2(first) + Vector2(0.5, 0.5) + Vector2(_DIRECTIONS[direction]) * 0.5
	centers.append(border_point)
	for i in range(path_cells.size()):
		var pos := path_cells[i]
		positions[pos] = true
		centers.append(Vector2(pos) + Vector2(0.5, 0.5))
		if i < WIDENING_EDGE_MARGIN or i >= path_cells.size() - 1:
			continue
		if _hash(pos.x, pos.y, seed_value) % 1000 >= int(WIDENING_CHANCE * 1000.0):
			continue
		# Insenatura di fianco al tratto (perpendicolare alla direzione locale).
		var step := path_cells[i + 1] - path_cells[i - 1]
		var side := Vector2i(step.y, -step.x)
		side = Vector2i(signi(side.x), signi(side.y))
		if side == Vector2i.ZERO or (side.x != 0 and side.y != 0):
			side = Vector2i(0, 1) if step.x != 0 else Vector2i(1, 0)
		if _hash(pos.x, pos.y, seed_value + 1) % 2 == 0:
			side = -side
		var widening := pos + side
		if _in_bounds(widening):
			positions[widening] = true
			layout["widenings"].append((Vector2(pos) + Vector2(widening)) / 2.0 + Vector2(0.5, 0.5))
	layout["paths"].append(_smooth(centers))


# Tratto 4-connesso da `start` a `target` lungo una curva serpeggiante (sinusoidi con ampiezza e
# verso dall'hash, nulle agli estremi). Si ferma prima se entra in `stop_at`.
static func _trace(start: Vector2i, target: Vector2i, seed_value: int, stop_at: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var a := Vector2(start) + Vector2(0.5, 0.5)
	var b := Vector2(target) + Vector2(0.5, 0.5)
	var length := a.distance_to(b)
	if length < 0.5:
		result.append(start)
		return result
	var normal := (b - a).normalized().orthogonal()
	var main_amp := length * MEANDER_MAIN_RATIO * (float(seed_value % 2001) / 1000.0 - 1.0)
	var second_amp := length * MEANDER_SECOND_RATIO * (float((seed_value / 2001) % 2001) / 1000.0 - 1.0)
	var steps := int(length * 4.0)
	var previous := Vector2i(-1, -1)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var point := a.lerp(b, t) + normal * (main_amp * sin(PI * t) + second_amp * sin(TAU * t))
		var pos := Vector2i(clampi(int(floor(point.x)), 0, World.WIDTH - 1), clampi(int(floor(point.y)), 0, World.HEIGHT - 1))
		if pos == previous:
			continue
		if previous.x >= 0 and pos.x != previous.x and pos.y != previous.y:
			# Passo diagonale: microcella intermedia, così il tratto resta 4-connesso.
			var bridge := Vector2i(pos.x, previous.y) if (seed_value + i) % 2 == 0 else Vector2i(previous.x, pos.y)
			result.append(bridge)
			if stop_at.has(bridge):
				return result
		result.append(pos)
		if stop_at.has(pos):
			return result
		previous = pos
	return result


# Due passate di Chaikin sulla linea a gradini dei centri: curva morbida che resta dentro le
# microcelle del tratto. Gli estremi restano fissi.
static func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	var current := points
	for _pass in range(2):
		if current.size() < 3:
			return current
		var next := PackedVector2Array()
		next.append(current[0])
		for i in range(current.size() - 1):
			next.append(current[i].lerp(current[i + 1], 0.25))
			next.append(current[i].lerp(current[i + 1], 0.75))
		next.append(current[current.size() - 1])
		current = next
	return current


# Microcella d'ingresso sul lato `direction` della cella (cx, cy): lo scostamento lungo il lato
# viene dall'hash del bordo condiviso, identico visto dalle due celle.
static func _edge_microcell(cx: int, cy: int, direction: int) -> Vector2i:
	var offset: int
	match direction:
		0:  # nord: bordo orizzontale in cima a (cx, cy)
			offset = _edge_offset(cx, cy, 0)
			return Vector2i(offset, 0)
		1:  # est: bordo verticale a sinistra di (cx + 1, cy)
			offset = _edge_offset(cx + 1, cy, 1)
			return Vector2i(World.WIDTH - 1, offset)
		2:  # sud: bordo orizzontale in cima a (cx, cy + 1)
			offset = _edge_offset(cx, cy + 1, 0)
			return Vector2i(offset, World.HEIGHT - 1)
		_:  # ovest: bordo verticale a sinistra di (cx, cy)
			offset = _edge_offset(cx, cy, 1)
			return Vector2i(0, offset)


static func _edge_offset(ex: int, ey: int, orientation: int) -> int:
	return EDGE_OFFSET_MIN + _hash(ex, ey, 100 + orientation) % (EDGE_OFFSET_MAX - EDGE_OFFSET_MIN + 1)


static func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < World.WIDTH and pos.y < World.HEIGHT


# Hash intero deterministico (non dipende dal seed del motore né dalla sessione), sempre >= 0.
static func _hash(a: int, b: int, c: int) -> int:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff
