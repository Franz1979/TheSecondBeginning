class_name PlantFiberIcon
extends Control

# Icona stilizzata "fascio di fibre legate" per il riquadro risorsa trasportata (2026-09-16,
# richiesta utente — proposta mostrata in artifact e approvata: "va benissimo"). Stesso principio
# di StickIcon/PebbleIcon: nessun emoji Unicode rende bene "fibra vegetale", quindi disegnata a
# mano. Control minimale, solo _draw(): riempie il proprio Rect2 (vedi IconRegistry.
# get_resource_icon_node, il consumatore), scala automaticamente con qualunque dimensione senza
# valori hardcoded.
#
# Quattro fili CURVI (non spezzati/dritti come i rametti di StickIcon: la curva è ciò che
# distingue "fibra flessibile" da "ramo rigido") che convergono in un nodo di spago vicino alla
# base — legge come "fascio raccolto e legato", non come cespuglio/pianta intera. Offset FISSI
# (mai randf(): icona statica, stesso principio già seguito da StickIcon/PebbleIcon).

const FIBER_COLOR_MAIN := Color(0.624, 0.682, 0.361, 1.0)
const FIBER_COLOR_LIGHT := Color(0.765, 0.820, 0.498, 1.0)
const FIBER_COLOR_DARK := Color(0.439, 0.498, 0.247, 1.0)
const TIE_COLOR := Color(0.420, 0.290, 0.169, 1.0)

# (end_ratio, ctrl_ratio, color, width_ratio) — curva quadratica base->ctrl->end, stessa idea di
# StickIcon._draw_twig ma con un kink morbido campionato invece di due segmenti dritti.
const STRANDS := [
	{"end": Vector2(0.16, 0.12), "ctrl": Vector2(0.22, 0.42), "color": FIBER_COLOR_DARK, "width": 0.055},
	{"end": Vector2(0.38, 0.08), "ctrl": Vector2(0.40, 0.40), "color": FIBER_COLOR_LIGHT, "width": 0.06},
	{"end": Vector2(0.62, 0.09), "ctrl": Vector2(0.58, 0.42), "color": FIBER_COLOR_MAIN, "width": 0.062},
	{"end": Vector2(0.84, 0.16), "ctrl": Vector2(0.76, 0.44), "color": FIBER_COLOR_DARK, "width": 0.05},
]

const CURVE_SEGMENTS: int = 8


func _ready() -> void:
	# IGNORE (stesso principio di StickIcon/PebbleIcon): puro disegno, mai un bersaglio di input —
	# il tooltip sul riquadro trasportato vive sul CONTENITORE, non su questa icona.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var base := Vector2(w * 0.50, h * 0.86)
	for strand in STRANDS:
		var ctrl := Vector2(w * strand["ctrl"].x, h * strand["ctrl"].y)
		var end := Vector2(w * strand["end"].x, h * strand["end"].y)
		_draw_fiber_strand(base, ctrl, end, strand["color"], h * strand["width"])
	_draw_tie_knot(base, w, h)


# Curva quadratica campionata a segmenti (draw_polyline, non draw_line ripetuto: un'unica
# polilinea antialiasata invece di N chiamate separate).
func _draw_fiber_strand(base: Vector2, ctrl: Vector2, end: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(CURVE_SEGMENTS)
		points.append(_quadratic_point(base, ctrl, end, t))
	draw_polyline(points, color, width, true)


func _quadratic_point(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var one_minus_t: float = 1.0 - t
	return p0 * (one_minus_t * one_minus_t) + p1 * (2.0 * one_minus_t * t) + p2 * (t * t)


# Nodo di spago che lega il fascio — ellisse piena leggermente ruotata, approssimata a poligono
# (Godot non ha un draw_ellipse nativo, stesso approccio già visto altrove nel progetto per forme
# non circolari).
func _draw_tie_knot(base: Vector2, w: float, h: float) -> void:
	var center := Vector2(w * 0.50, h * 0.80)
	var rx: float = w * 0.14
	var ry: float = h * 0.075
	var rotation: float = -0.12
	var points := PackedVector2Array()
	const KNOT_SEGMENTS: int = 16
	for i in range(KNOT_SEGMENTS):
		var angle: float = TAU * float(i) / float(KNOT_SEGMENTS)
		var local_point := Vector2(cos(angle) * rx, sin(angle) * ry)
		points.append(center + local_point.rotated(rotation))
	draw_colored_polygon(points, TIE_COLOR)
