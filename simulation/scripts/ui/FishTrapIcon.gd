class_name FishTrapIcon
extends Control

# Icona disegnata "nassa" (2026-11-08, capanna del trappoliere): cesto a cono di rami intrecciati visto di lato, bocca
# larga a sinistra con l'imbuto scuro che fa entrare i pesci, coda legata a destra. Solo _draw(), coordinate relative,
# nessun randf(). draw_into (statica) condivisa con DepositStorageIcons.

const WICKER_COLOR := Color(0.66, 0.50, 0.28, 1.0)
const WICKER_DARK_COLOR := Color(0.38, 0.26, 0.13, 1.0)
const MOUTH_COLOR := Color(0.16, 0.12, 0.08, 1.0)
const LASHING_COLOR := Color(0.78, 0.70, 0.50, 1.0)

const MOUTH_CENTER := Vector2(0.24, 0.50)
const MOUTH_RADIUS := Vector2(0.11, 0.30)
const TAIL := Vector2(0.84, 0.53)
# Stecche: dal bordo della bocca (angolo in gradi) alla coda.
const RIB_ANGLES := [-80.0, -45.0, -15.0, 15.0, 45.0, 80.0]
# Cerchi dell'intreccio: quota lungo il cono, dalla bocca alla coda.
const HOOPS := [0.22, 0.42, 0.62, 0.80]
# Rametti che spuntano dalla coda legata.
const TAIL_TWIGS := [Vector2(0.95, 0.44), Vector2(0.96, 0.54), Vector2(0.93, 0.63)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la nassa dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(v: Vector2) -> Vector2: return origin + Vector2(v.x * area.x, v.y * area.y)
	var unit: float = minf(area.x, area.y)
	var width: float = maxf(unit * 0.035, 1.0)

	# Corpo: sagoma del cono sotto l'intreccio.
	var body := PackedVector2Array([
		p.call(MOUTH_CENTER + Vector2(0.0, -MOUTH_RADIUS.y)), p.call(TAIL + Vector2(0.0, -0.035)),
		p.call(TAIL + Vector2(0.0, 0.035)), p.call(MOUTH_CENTER + Vector2(0.0, MOUTH_RADIUS.y)),
	])
	canvas.draw_colored_polygon(body, WICKER_DARK_COLOR)

	# Stecche dalla bocca alla coda.
	for angle in RIB_ANGLES:
		var radians := deg_to_rad(float(angle))
		var start: Vector2 = MOUTH_CENTER + Vector2(cos(radians) * MOUTH_RADIUS.x, sin(radians) * MOUTH_RADIUS.y)
		canvas.draw_line(p.call(start), p.call(TAIL), WICKER_COLOR, width, true)

	# Cerchi dell'intreccio: archetti che si stringono verso la coda.
	for hoop in HOOPS:
		var t := float(hoop)
		var center: Vector2 = MOUTH_CENTER.lerp(TAIL, t)
		var half_height: float = lerpf(MOUTH_RADIUS.y, 0.035, t)
		var half_width: float = lerpf(MOUTH_RADIUS.x, 0.015, t)
		var points := PackedVector2Array()
		for step in range(9):
			var radians := deg_to_rad(-90.0 + 22.5 * float(step))
			points.append(p.call(center + Vector2(cos(radians) * half_width, sin(radians) * half_height)))
		canvas.draw_polyline(points, WICKER_COLOR, width * 1.2, true)

	# Bocca: ovale scuro con l'imbuto e il bordo intrecciato.
	var mouth := PackedVector2Array()
	for step in range(20):
		var radians := TAU * float(step) / 20.0
		mouth.append(p.call(MOUTH_CENTER + Vector2(cos(radians) * MOUTH_RADIUS.x, sin(radians) * MOUTH_RADIUS.y)))
	canvas.draw_colored_polygon(mouth, MOUTH_COLOR)
	mouth.append(mouth[0])
	canvas.draw_polyline(mouth, WICKER_COLOR, width * 1.6, true)

	# Coda: rametti che spuntano e legatura di fibra.
	for twig in TAIL_TWIGS:
		canvas.draw_line(p.call(TAIL), p.call(twig), WICKER_DARK_COLOR, width, true)
	for offset in [-0.02, 0.0, 0.02]:
		var a: Vector2 = TAIL + Vector2(float(offset) - 0.015, -0.05)
		var b: Vector2 = TAIL + Vector2(float(offset) + 0.015, 0.05)
		canvas.draw_line(p.call(a), p.call(b), LASHING_COLOR, width, true)
