class_name ClayBowlIcon
extends Control

# Icona "ciotola di terracotta" (2026-11-07, richiesta utente — al posto dell'emoji, e sulla mappa al posto del pallino di
# ripiego): una scodella bassa e larga vista un po' dall'alto, apertura scura con l'orlo chiaro, piccolo piede sotto. Stessi
# colori della giara (ClayJarIcon). Stesso schema di ClayJarIcon: draw_into condivisa con DepositStorageIcons.

const BODY_COLOR := ClayJarIcon.BODY_COLOR
const SHADE_COLOR := ClayJarIcon.SHADE_COLOR
const RIM_COLOR := ClayJarIcon.RIM_COLOR
const INSIDE_COLOR := ClayJarIcon.MOUTH_COLOR

# Orlo (ellisse), in frazioni dell'area.
const RIM_CENTER := Vector2(0.50, 0.40)
const RIM_RADIUS := Vector2(0.42, 0.14)
# Profondità della vasca sotto l'orlo e piede.
const BODY_DEPTH: float = 0.34
const FOOT_RECT := Rect2(0.38, 0.70, 0.24, 0.10)
const SEGMENTS: int = 20


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la ciotola dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(point: Vector2) -> Vector2: return origin + Vector2(point.x * area.x, point.y * area.y)
	# Piede.
	canvas.draw_rect(Rect2(p.call(FOOT_RECT.position), Vector2(FOOT_RECT.size.x * area.x, FOOT_RECT.size.y * area.y)), SHADE_COLOR)
	# Vasca: mezza ellisse sotto l'orlo; il lato destro in ombra.
	var body := PackedVector2Array()
	var shade := PackedVector2Array()
	for i in range(SEGMENTS + 1):
		var angle := PI * float(i) / float(SEGMENTS)
		var point: Vector2 = p.call(RIM_CENTER + Vector2(cos(angle) * RIM_RADIUS.x, sin(angle) * BODY_DEPTH))
		body.append(point)
		if i <= SEGMENTS / 3:
			shade.append(point)
	canvas.draw_colored_polygon(body, BODY_COLOR)
	shade.append(p.call(RIM_CENTER + Vector2(RIM_RADIUS.x * 0.35, 0.0)))
	canvas.draw_colored_polygon(shade, SHADE_COLOR)
	# Orlo chiaro e interno scuro.
	_draw_ellipse(canvas, p.call(RIM_CENTER), Vector2(RIM_RADIUS.x * area.x, RIM_RADIUS.y * area.y), RIM_COLOR)
	_draw_ellipse(canvas, p.call(RIM_CENTER), Vector2(RIM_RADIUS.x * area.x, RIM_RADIUS.y * area.y) * 0.78, INSIDE_COLOR)


static func _draw_ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	canvas.draw_colored_polygon(points, color)
