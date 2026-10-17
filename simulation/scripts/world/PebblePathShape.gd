class_name PebblePathShape
extends RefCounted

# Sentiero di ciottoli (pebble_path, 2026-10-16, richiesta utente) a pezzi uniti, condiviso da mappa, anteprima di
# piazzamento e icona tramite LinearShapes. Si unisce solo ad altri pezzi di sentiero (linear_link_group vuoto), mai al
# vallo.
# 2026-10-17 (richiesta utente — "è un sentiero del paleolitico, deve apparire più grossolano"): niente striscia a bordi
# dritti; il corpo è una fila di macchie irregolari color sabbia lungo il tracciato (body_points + blob_polygon), con i
# ciottoli sopra (pebble_points). Sulla mappa corpo e ciottoli li disegna il renderer in MultiMesh
# (MicroCellRenderer._rebuild_path_pebble_multimeshes); qui il disegno diretto serve solo ad anteprima e icona (un pezzo).
# Il fondo di terra battuta, solo accanto a un fondo, è il tile della terra battuta (MicroCellRenderer).

const BODY := Color(0.70, 0.64, 0.52, 1.0)
const INVALID_TINT := Color(0.9, 0.25, 0.25, 0.55)
# Macchie del corpo: raggio, vertici, irregolarità, quante sagome diverse.
const BLOB_RADIUS: float = 1.7
const BLOB_VERTICES: int = 9
const BLOB_JITTER: float = 0.28
const BLOB_VARIANTS: int = 4
# Distanze dal centro delle macchie lungo un braccio (l'ultima arriva quasi al bordo, dove incontra il pezzo accanto).
const ARM_BLOB_DISTANCES: Array[float] = [2.3, 4.5]
const PEBBLE_RADIUS: float = 0.55
# Ciottoli del centro (pezzo non ad angolo) e lungo ogni braccio (distanza dal centro, scostamento di lato).
const CENTER_PEBBLES: Array[Vector2] = [Vector2(-0.7, -0.6), Vector2(0.6, -0.3), Vector2(-0.3, 0.7), Vector2(0.8, 0.8)]
const ARM_PEBBLES: Array[Vector2] = [Vector2(2.9, -0.6), Vector2(4.2, 0.5)]
# Pezzo ad angolo: posizioni lungo il tratto dal punto medio di un lato all'altro (frazione, scostamento di lato).
const CORNER_PEBBLES: Array[Vector2] = [Vector2(0.15, 0.5), Vector2(0.4, -0.6), Vector2(0.62, 0.5), Vector2(0.86, -0.4)]
const CORNER_BLOB_FRACTIONS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
const PEBBLE_COLORS: Array[Color] = [PebbleIcon.PEBBLE_COLOR, Color(0.66, 0.65, 0.62, 1.0), Color(0.50, 0.49, 0.46, 1.0)]


# Disegno diretto di un pezzo (anteprima e icona). Sulla mappa (`with_pebbles` false) non disegna nulla: corpo e
# ciottoli sono nei MultiMesh del renderer.
static func draw(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0, _clip_mask: int = 0, with_pebbles: bool = true
) -> void:
	if not with_pebbles:
		return
	var body_color: Color = INVALID_TINT if invalid else BODY
	body_color.a *= alpha
	var body := body_points(neighbor_mask)
	for i in range(body.size()):
		var polygon := blob_polygon(i % BLOB_VARIANTS)
		var placed := PackedVector2Array()
		for point in polygon:
			placed.append(center + (body[i] + point) * scale)
		canvas.draw_colored_polygon(placed, body_color)
	if invalid:
		return
	var points := pebble_points(neighbor_mask)
	for i in range(points.size()):
		var color: Color = PEBBLE_COLORS[i % PEBBLE_COLORS.size()]
		canvas.draw_circle(center + points[i] * scale, PEBBLE_RADIUS * scale, Color(color.r, color.g, color.b, color.a * alpha))


# Sagoma irregolare di una macchia del corpo (unità della mappa, centrata in 0,0), deterministica per variante.
static func blob_polygon(variant: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(BLOB_VERTICES):
		var angle: float = TAU * float(i) / float(BLOB_VERTICES)
		var t: float = float(posmod(hash(Vector2i(variant * 17 + 3, i * 13 + 5)), 1000)) / 1000.0
		points.append(Vector2(cos(angle), sin(angle)) * BLOB_RADIUS * (1.0 + lerpf(-BLOB_JITTER, BLOB_JITTER, t)))
	return points


# Centri delle macchie del corpo di un pezzo (unità della mappa, rispetto al centro della microcella).
static func body_points(neighbor_mask: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if LinearShape.is_corner_mask(neighbor_mask):
		var sides := _corner_sides(neighbor_mask)
		for fraction in CORNER_BLOB_FRACTIONS:
			points.append(sides[0].lerp(sides[1], fraction))
		return points
	points.append(Vector2.ZERO)
	for side in range(4):
		if neighbor_mask & (1 << side):
			for distance in ARM_BLOB_DISTANCES:
				points.append(LinearShape.SIDE_DIRECTIONS[side] * distance)
	return points


# Posizioni dei ciottoli di un pezzo (unità della mappa, rispetto al centro della microcella).
static func pebble_points(neighbor_mask: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if LinearShape.is_corner_mask(neighbor_mask):
		var sides := _corner_sides(neighbor_mask)
		var along := sides[1] - sides[0]
		var across := Vector2(-along.y, along.x).normalized()
		for entry in CORNER_PEBBLES:
			points.append(sides[0] + along * entry.x + across * entry.y)
		return points
	points.append_array(CENTER_PEBBLES)
	for side in range(4):
		if not (neighbor_mask & (1 << side)):
			continue
		var direction: Vector2 = LinearShape.SIDE_DIRECTIONS[side]
		var lateral := Vector2(-direction.y, direction.x)
		for entry in ARM_PEBBLES:
			points.append(direction * entry.x + lateral * entry.y)
	return points


# Punti medi dei due lati collegati di un pezzo ad angolo.
static func _corner_sides(neighbor_mask: int) -> Array[Vector2]:
	var sides: Array[Vector2] = []
	for side in range(4):
		if neighbor_mask & (1 << side):
			sides.append(LinearShape.SIDE_DIRECTIONS[side] * LinearShape.HALF_CELL)
	return sides
