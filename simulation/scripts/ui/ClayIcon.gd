class_name ClayIcon
extends Control

# Icona "argilla" (2026-11-04, richiesta utente — Vasellame): un panetto tondeggiante e irregolare, mai squadrato (sembrerebbe
# un mattone), con le impronte delle dita e due briciole. Colori del giacimento sulla mappa (MicroCellRenderer.COLOR_CLAY_*),
# più chiaro in alto. Stesso schema di BoneIcon: draw_into (statica) condivisa con DepositStorageIcons.

const BASE_COLOR := Color(0.44, 0.28, 0.20, 1.0)
const BODY_COLOR := Color(0.58, 0.39, 0.28, 1.0)
const LIGHT_COLOR := Color(0.70, 0.50, 0.37, 1.0)
const DENT_COLOR := Color(0.42, 0.27, 0.19, 1.0)

# Sagoma del panetto, in frazioni dell'area.
const BODY_POINTS: Array[Vector2] = [
	Vector2(0.14, 0.62), Vector2(0.17, 0.42), Vector2(0.30, 0.28), Vector2(0.50, 0.24), Vector2(0.70, 0.27),
	Vector2(0.84, 0.40), Vector2(0.87, 0.60), Vector2(0.76, 0.74), Vector2(0.52, 0.79), Vector2(0.28, 0.75),
]
const LIGHT_POINTS: Array[Vector2] = [
	Vector2(0.26, 0.44), Vector2(0.35, 0.34), Vector2(0.50, 0.30), Vector2(0.66, 0.33), Vector2(0.76, 0.42),
	Vector2(0.66, 0.50), Vector2(0.48, 0.53), Vector2(0.33, 0.51),
]
# Impronte delle dita: x, y, raggio.
const DENTS: Array[Vector3] = [Vector3(0.40, 0.45, 0.055), Vector3(0.53, 0.42, 0.06), Vector3(0.66, 0.46, 0.05)]
const CRUMBS: Array[Vector3] = [Vector3(0.14, 0.82, 0.04), Vector3(0.84, 0.84, 0.03)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il panetto dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var width: float = minf(area.x, area.y)
	var p := func(point: Vector2) -> Vector2: return origin + Vector2(point.x * area.x, point.y * area.y)
	# Base in ombra, spostata in basso: dà il volume.
	var base := PackedVector2Array()
	var body := PackedVector2Array()
	for point in BODY_POINTS:
		base.append(p.call(point + Vector2(0.0, 0.05)))
		body.append(p.call(point))
	canvas.draw_colored_polygon(base, BASE_COLOR)
	canvas.draw_colored_polygon(body, BODY_COLOR)
	var light := PackedVector2Array()
	for point in LIGHT_POINTS:
		light.append(p.call(point))
	canvas.draw_colored_polygon(light, LIGHT_COLOR)
	for dent in DENTS:
		canvas.draw_circle(p.call(Vector2(dent.x, dent.y)), width * dent.z, DENT_COLOR)
	for crumb in CRUMBS:
		canvas.draw_circle(p.call(Vector2(crumb.x, crumb.y)), width * crumb.z, BODY_COLOR)
