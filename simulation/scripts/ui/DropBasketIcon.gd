class_name DropBasketIcon
extends Control

# Icona disegnata "cesto a caduta" (2026-11-12, cattura viva): cesto rovesciato di bastoni intrecciati, sollevato da un lato
# su un bastoncino, col laccio che scende all'esca. Solo _draw(), coordinate relative, nessun randf(). draw_into (statica)
# condivisa con DepositStorageIcons.

const WICKER_COLOR := Color(0.62, 0.46, 0.24, 1.0)
const WICKER_DARK_COLOR := Color(0.40, 0.28, 0.13, 1.0)
const STICK_COLOR := Color(0.50, 0.34, 0.17, 1.0)
const CORD_COLOR := Color(0.82, 0.74, 0.52, 1.0)
const BAIT_COLOR := Color(0.55, 0.20, 0.30, 1.0)

# Cupola del cesto: arco da sinistra (a terra) a destra (sollevata sul bastoncino).
const DOME_LEFT := Vector2(0.10, 0.84)
const DOME_RIGHT := Vector2(0.80, 0.62)
const DOME_HEIGHT := 0.52
const STICK_BOTTOM := Vector2(0.80, 0.88)
const BAIT := Vector2(0.52, 0.86)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il cesto a caduta dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(v: Vector2) -> Vector2: return origin + Vector2(v.x * area.x, v.y * area.y)
	var unit: float = minf(area.x, area.y)
	var width: float = maxf(unit * 0.05, 1.0)
	var base_dir := DOME_RIGHT - DOME_LEFT
	var normal := Vector2(base_dir.y, -base_dir.x).normalized()
	if normal.y > 0.0:
		normal = -normal
	var mid := (DOME_LEFT + DOME_RIGHT) * 0.5
	var dome := PackedVector2Array()
	const SEGMENTS := 14
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var angle := PI * t
		var along := DOME_LEFT.lerp(DOME_RIGHT, (1.0 - cos(angle)) * 0.5)
		dome.append(p.call(along + normal * sin(angle) * DOME_HEIGHT))
	# Esca sotto il cesto, poi il bastoncino e il laccio.
	canvas.draw_circle(p.call(BAIT), unit * 0.06, BAIT_COLOR)
	canvas.draw_line(p.call(STICK_BOTTOM), p.call(DOME_RIGHT), STICK_COLOR, width * 1.4, true)
	canvas.draw_line(p.call(DOME_RIGHT + Vector2(0.0, 0.06)), p.call(BAIT + Vector2(0.05, 0.0)), CORD_COLOR, width * 0.8, true)
	# Cesto: riempimento, intreccio (meridiani e due anelli), bordo.
	var fill := dome.duplicate()
	canvas.draw_colored_polygon(fill, WICKER_COLOR)
	for k in range(1, 5):
		var t := float(k) / 5.0
		var foot := DOME_LEFT.lerp(DOME_RIGHT, t)
		var top := mid + normal * DOME_HEIGHT
		canvas.draw_line(p.call(foot), p.call(foot.lerp(top, 0.85)), WICKER_DARK_COLOR, width * 0.6, true)
	for ring in [0.35, 0.7]:
		var ring_points := PackedVector2Array()
		for i in range(SEGMENTS + 1):
			var angle := PI * float(i) / float(SEGMENTS)
			var along := DOME_LEFT.lerp(DOME_RIGHT, (1.0 - cos(angle)) * 0.5)
			ring_points.append(p.call(along + normal * sin(angle) * DOME_HEIGHT * ring))
		canvas.draw_polyline(ring_points, WICKER_DARK_COLOR, width * 0.6, true)
	canvas.draw_polyline(dome, WICKER_DARK_COLOR, width * 1.1, true)
	canvas.draw_line(p.call(DOME_LEFT), p.call(DOME_RIGHT), WICKER_DARK_COLOR, width * 1.1, true)
