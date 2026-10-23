class_name TravoisIcon
extends Control

# Icona disegnata del travois (2026-10-23, richiesta utente). Ridisegnata lo stesso giorno più rustica (la prima, una V con
# una pelle liscia, sembrava una tenda): due pali un po' storti e nodosi che si incrociano in cima e sporgono oltre
# l'incrocio, tre traverse a scala legate con piccole X di tendine e un fagotto di pelle arrotolata legato sopra. Stesso
# schema di HideBagIcon: solo _draw(), coordinate relative, nessun randf(). draw_into (statica) condivisa con
# DepositStorageIcons; draw_rustic è lo stesso disegno per il travois trainato (HumanIndividualView).

const POLE_COLOR := Color(0.60, 0.45, 0.27, 1.0)
const POLE_DARK_COLOR := Color(0.32, 0.22, 0.12, 1.0)
const RUNG_COLOR := Color(0.52, 0.39, 0.23, 1.0)
const SINEW_COLOR := Color(0.78, 0.68, 0.50, 1.0)
const BUNDLE_COLOR := Color(0.63, 0.52, 0.37, 1.0)
const BUNDLE_DARK_COLOR := Color(0.48, 0.38, 0.26, 1.0)

# Geometria in coordinate dell'icona (0..1, punta in alto): incrocio dei pali, cime oltre l'incrocio, piedi a terra.
const CROSS := Vector2(0.50, 0.20)
const LEFT_TOP := Vector2(0.62, 0.04)
const RIGHT_TOP := Vector2(0.38, 0.04)
const LEFT_FOOT := Vector2(0.13, 0.95)
const RIGHT_FOOT := Vector2(0.87, 0.95)
# Traverse: posizione lungo i pali (0 = incrocio, 1 = piedi) e quanto sporgono oltre i pali.
const RUNGS: Array[float] = [0.40, 0.58, 0.76]
const RUNG_OVERHANG: float = 0.06
# Piega a metà palo (verso l'esterno) e vertici del fagotto.
const POLE_BEND: float = 0.012
const BUNDLE_VERTICES: int = 14
# Sotto questo spessore dei pali (pixel) le legature non si vedrebbero: non si disegnano.
const MIN_POLE_WIDTH_FOR_LASHINGS: float = 1.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il travois dentro il rettangolo (origin, area) di `canvas`: incrocio in alto, piedi in basso.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var to_canvas := func(icon_point: Vector2) -> Vector2: return origin + icon_point * area
	draw_rustic(canvas, to_canvas, minf(area.x, area.y) * 0.07)


# Il travois rustico: `to_canvas` porta un punto in coordinate dell'icona (0..1) sul canvas (anche ruotato, per il
# trainato); `pole_width` = spessore dei pali in pixel del canvas (traverse, legacci e nodi in proporzione).
static func draw_rustic(canvas: CanvasItem, to_canvas: Callable, pole_width: float) -> void:
	# Traverse (sotto i pali), con il contorno scuro.
	for t in RUNGS:
		var left: Vector2 = CROSS.lerp(LEFT_FOOT, t)
		var right: Vector2 = CROSS.lerp(RIGHT_FOOT, t)
		var start: Vector2 = to_canvas.call(right.lerp(left, 1.0 + RUNG_OVERHANG))
		var end: Vector2 = to_canvas.call(left.lerp(right, 1.0 + RUNG_OVERHANG))
		canvas.draw_line(start, end, POLE_DARK_COLOR, pole_width * 1.2, true)
		canvas.draw_line(start, end, RUNG_COLOR, pole_width * 0.75, true)
	_draw_bundle(canvas, to_canvas, pole_width)
	_draw_bent_pole(canvas, to_canvas, LEFT_TOP, LEFT_FOOT, POLE_BEND, pole_width)
	_draw_bent_pole(canvas, to_canvas, RIGHT_TOP, RIGHT_FOOT, -POLE_BEND, pole_width)
	if pole_width < MIN_POLE_WIDTH_FOR_LASHINGS:
		return
	# Legature a croce: all'incrocio e alle due estremità di ogni traversa.
	_draw_lashing(canvas, to_canvas.call(CROSS), pole_width * 0.75, pole_width)
	for t in RUNGS:
		_draw_lashing(canvas, to_canvas.call(CROSS.lerp(LEFT_FOOT, t)), pole_width * 0.5, pole_width)
		_draw_lashing(canvas, to_canvas.call(CROSS.lerp(RIGHT_FOOT, t)), pole_width * 0.5, pole_width)


# Fagotto di pelle arrotolata sulle traverse: ovale (in coordinate dell'icona, poi portato sul canvas) con il bordo scuro e
# due legacci paralleli alle traverse.
static func _draw_bundle(canvas: CanvasItem, to_canvas: Callable, pole_width: float) -> void:
	var top_left: Vector2 = CROSS.lerp(LEFT_FOOT, 0.5)
	var bottom_right: Vector2 = CROSS.lerp(RIGHT_FOOT, 0.8)
	var bundle_center := Vector2(0.5, (top_left.y + bottom_right.y) / 2.0)
	var radius := Vector2((bottom_right.x - CROSS.lerp(LEFT_FOOT, 0.8).x) * 0.40, (bottom_right.y - top_left.y) * 0.40)
	var outline := PackedVector2Array()
	for i in range(BUNDLE_VERTICES):
		var angle := TAU * float(i) / float(BUNDLE_VERTICES)
		outline.append(to_canvas.call(bundle_center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)))
	canvas.draw_colored_polygon(outline, BUNDLE_COLOR)
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, BUNDLE_DARK_COLOR, pole_width * 0.4, true)
	for k in [-0.35, 0.35]:
		canvas.draw_line(
			to_canvas.call(bundle_center + Vector2(-radius.x * 0.95, radius.y * k)),
			to_canvas.call(bundle_center + Vector2(radius.x * 0.95, radius.y * k)),
			SINEW_COLOR, pole_width * 0.35, true
		)


# Palo con una leggera piega a metà (`bend`, verso l'esterno) e un nodo scuro: contorno scuro, poi il legno.
static func _draw_bent_pole(canvas: CanvasItem, to_canvas: Callable, top: Vector2, foot: Vector2, bend: float, pole_width: float) -> void:
	var normal := Vector2(foot.y - top.y, -(foot.x - top.x)).normalized()
	var middle: Vector2 = top.lerp(foot, 0.55) + normal * bend
	var points: Array[Vector2] = [to_canvas.call(top), to_canvas.call(middle), to_canvas.call(foot)]
	for index in range(2):
		canvas.draw_line(points[index], points[index + 1], POLE_DARK_COLOR, pole_width * 1.55, true)
	for index in range(2):
		canvas.draw_line(points[index], points[index + 1], POLE_COLOR, pole_width, true)
	canvas.draw_circle(points[1].lerp(points[2], 0.35), pole_width * 0.45, POLE_DARK_COLOR)


static func _draw_lashing(canvas: CanvasItem, at: Vector2, half_size: float, pole_width: float) -> void:
	canvas.draw_line(at + Vector2(-half_size, -half_size), at + Vector2(half_size, half_size), SINEW_COLOR, pole_width * 0.4, true)
	canvas.draw_line(at + Vector2(-half_size, half_size), at + Vector2(half_size, -half_size), SINEW_COLOR, pole_width * 0.4, true)
