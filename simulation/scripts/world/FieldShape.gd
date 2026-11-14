class_name FieldShape
extends RefCounted

# Disegno del Campo con capanno (2026-11-15, richiesta utente — ramo piante, campi), vista dall'alto: un solo disegno per
# mappa (MicroCellRenderer._draw_buildings), anteprima di piazzamento (BuildingGhost) e icona della barra (FieldIcon).
# Microcelle del campo in coordinate di griglia NON ruotate, (0,0) = il capanno nell'angolo; la rotazione scelta al
# piazzamento gira tutto attorno al centro, così il capanno finisce nell'angolo voluto. Oggi le microcelle sono sempre il
# 3×3 di base (BASE_CELLS); con gli appezzamenti arriverà la forma vera (`cells`) e recinto e terra la seguiranno da soli:
# - terra dissodata a solchi su ogni microcella coltivata;
# - capanno piccolo (attrezzeria: bastoni da scavo e falcetti) sulla microcella (0,0);
# - recinto di pali e rami lungo il bordo vero: un tratto su ogni lato di microcella che non confina con un'altra del campo;
# - cancellino sul lato nord della microcella accanto al capanno (sempre bordo: nulla sta sopra la riga del capanno).
# `center`: centro del rettangolo 3×3 nello spazio del canvas; `scale`: pixel per unità (1.0 sulla mappa: 10 px a cella).

const TYPE := "field"
const CELL := 10.0
const SHED_CELL := Vector2i(0, 0)
const GATE_CELL := Vector2i(1, 0)
const BASE_SIZE := Vector2i(3, 3)

const SOIL := Color(0.30, 0.22, 0.14, 1.0)
const FURROW := Color(0.21, 0.15, 0.09, 1.0)
const SHED_FLOOR := Color(0.42, 0.33, 0.22, 1.0)
const WOOD := Color(0.55, 0.38, 0.20, 1.0)
const WOOD_DARK := Color(0.36, 0.24, 0.12, 1.0)
const WOOD_LIGHT := Color(0.70, 0.52, 0.30, 1.0)
const STRAW := Color(0.80, 0.70, 0.42, 1.0)
const STRAW_DARK := Color(0.62, 0.52, 0.30, 1.0)
const STONE := Color(0.62, 0.61, 0.58, 1.0)
const FENCE_INSET := 0.6


# Microcelle del campo nella macrocella (2026-11-15, passo 2b — lotti): le celle di base girate come il disegno (stessa
# rotazione attorno al centro del 3×3, Building.rotation), dall'ancora in alto a sinistra. Senza il capanno se
# `include_shed` è false (i lotti coltivati).
static func world_cells(building: Building, include_shed: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var turns := posmod(int(building.rotation) - int(GameTypes.Direction.SOUTH), 4)
	var center := Vector2i(building.micro_x, building.micro_y) + BASE_SIZE / 2
	for cell in base_cells():
		if cell == SHED_CELL and not include_shed:
			continue
		var offset := cell - BASE_SIZE / 2
		for i in range(turns):
			offset = Vector2i(-offset.y, offset.x)
		result.append(center + offset)
	return result


static func base_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(BASE_SIZE.y):
		for x in range(BASE_SIZE.x):
			cells.append(Vector2i(x, y))
	return cells


static func draw(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction = GameTypes.Direction.SOUTH, invalid: bool = false,
	scale: float = 1.0, cells: Array[Vector2i] = []
) -> void:
	var field_cells := cells if not cells.is_empty() else base_cells()
	var lookup: Dictionary = {}
	for cell in field_cells:
		lookup[cell] = true
	var angle := float(int(direction) - int(GameTypes.Direction.SOUTH)) * PI / 2.0
	canvas.draw_set_transform(center, angle, Vector2.ONE)
	var tint := func(color: Color) -> Color: return PlaceholderBuildingShapes.INVALID_TINT if invalid else color
	# Origine della griglia: angolo in alto a sinistra del 3×3 di base, centrato.
	var origin := -Vector2(BASE_SIZE) * CELL * 0.5 * scale
	var corner := func(cell: Vector2i) -> Vector2: return origin + Vector2(cell) * CELL * scale
	var w := func(width: float) -> float: return width * scale
	# Terra e solchi.
	for cell in field_cells:
		var top_left: Vector2 = corner.call(cell)
		if cell == SHED_CELL:
			canvas.draw_rect(Rect2(top_left, Vector2.ONE * CELL * scale), tint.call(SHED_FLOOR))
			continue
		canvas.draw_rect(Rect2(top_left, Vector2.ONE * CELL * scale), tint.call(SOIL))
		for i in range(3):
			var y := (2.2 + float(i) * 2.8) * scale
			canvas.draw_line(top_left + Vector2(w.call(1.0), y), top_left + Vector2(w.call(CELL - 1.0), y + w.call(0.15)),
				tint.call(FURROW), w.call(0.4), true)
	_draw_shed(canvas, corner.call(SHED_CELL), scale, tint)
	_draw_fence(canvas, field_cells, lookup, corner, scale, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Capanno: quattro pali agli angoli, tetto di paglia a due falde, un bastone da scavo e un falcetto appoggiati.
static func _draw_shed(canvas: CanvasItem, top_left: Vector2, scale: float, tint: Callable) -> void:
	var p := func(x: float, y: float) -> Vector2: return top_left + Vector2(x, y) * scale
	var roof := Rect2(p.call(2.0, 2.2), Vector2(6.0, 5.2) * scale)
	canvas.draw_rect(roof, tint.call(STRAW))
	canvas.draw_line(p.call(5.0, 2.4), p.call(5.0, 7.2), tint.call(STRAW_DARK), 0.4 * scale, true)
	for post in [Vector2(2.0, 2.2), Vector2(8.0, 2.2), Vector2(2.0, 7.4), Vector2(8.0, 7.4)]:
		canvas.draw_circle(p.call(post.x, post.y), 0.5 * scale, tint.call(WOOD_DARK))
	# Bastone da scavo (manico con la pietra) e falcetto, appoggiati sotto la gronda.
	canvas.draw_line(p.call(3.0, 8.6), p.call(5.4, 7.9), tint.call(WOOD), 0.35 * scale, true)
	canvas.draw_circle(p.call(3.1, 8.6), 0.4 * scale, tint.call(STONE))
	canvas.draw_line(p.call(6.0, 8.8), p.call(7.6, 8.1), tint.call(WOOD), 0.35 * scale, true)
	canvas.draw_arc(p.call(7.9, 7.6), 0.8 * scale, -PI * 0.9, PI * 0.1, 6, tint.call(STONE), 0.35 * scale, true)


# Recinto: un tratto (due rami) su ogni lato di microcella che dà fuori dal campo, pali agli angoli; sul lato nord della
# microcella accanto al capanno il cancellino al posto dei rami.
static func _draw_fence(canvas: CanvasItem, cells: Array[Vector2i], lookup: Dictionary, corner: Callable, scale: float, tint: Callable) -> void:
	var inset := FENCE_INSET * scale
	var size := CELL * scale
	var stakes: Dictionary = {}
	for cell in cells:
		var top_left: Vector2 = corner.call(cell)
		# [vicino, inizio, fine] del lato, rientrati verso l'interno del campo.
		var sides := [
			[cell + Vector2i(0, -1), top_left + Vector2(0.0, inset), top_left + Vector2(size, inset)],
			[cell + Vector2i(1, 0), top_left + Vector2(size - inset, 0.0), top_left + Vector2(size - inset, size)],
			[cell + Vector2i(0, 1), top_left + Vector2(0.0, size - inset), top_left + Vector2(size, size - inset)],
			[cell + Vector2i(-1, 0), top_left + Vector2(inset, 0.0), top_left + Vector2(inset, size)],
		]
		for side_index in range(sides.size()):
			var side: Array = sides[side_index]
			if lookup.has(side[0]):
				continue
			var a: Vector2 = side[1]
			var b: Vector2 = side[2]
			var along := (b - a).normalized()
			if cell == GATE_CELL and side_index == 0:
				_draw_gate(canvas, a, b, scale, tint)
			else:
				var across := along.orthogonal() * 0.35 * scale
				canvas.draw_line(a + across, b + across, tint.call(WOOD), 0.3 * scale, true)
				canvas.draw_line(a - across, b - across, tint.call(WOOD), 0.3 * scale, true)
			stakes[a.round()] = a
			stakes[b.round()] = b
			stakes[((a + b) * 0.5).round()] = (a + b) * 0.5
	for stake in stakes.values():
		canvas.draw_circle(stake, 0.55 * scale, tint.call(WOOD_DARK))


# Cancellino: due ante di assi chiare con una traversa, pali più grossi ai lati.
static func _draw_gate(canvas: CanvasItem, a: Vector2, b: Vector2, scale: float, tint: Callable) -> void:
	var along := (b - a)
	var gate_a := a + along * 0.3
	var gate_b := a + along * 0.7
	var middle := (gate_a + gate_b) * 0.5
	var across := along.normalized().orthogonal() * 0.35 * scale
	# Rami del recinto fino al cancello, da tutte e due le parti.
	for segment in [[a, gate_a], [gate_b, b]]:
		canvas.draw_line(segment[0] + across, segment[1] + across, tint.call(WOOD), 0.3 * scale, true)
		canvas.draw_line(segment[0] - across, segment[1] - across, tint.call(WOOD), 0.3 * scale, true)
	for leaf in [[gate_a, middle - along.normalized() * 0.2 * scale], [middle + along.normalized() * 0.2 * scale, gate_b]]:
		canvas.draw_line(leaf[0], leaf[1], tint.call(WOOD_LIGHT), 0.9 * scale, true)
	canvas.draw_circle(gate_a, 0.75 * scale, tint.call(WOOD_DARK))
	canvas.draw_circle(gate_b, 0.75 * scale, tint.call(WOOD_DARK))
