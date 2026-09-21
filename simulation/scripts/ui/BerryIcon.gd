class_name BerryIcon
extends Control

# Icona stilizzata "grappolo di bacche appena raccolte" per il riquadro risorsa trasportata e la
# griglia slot magazzino (2026-09-17, richiesta utente — proposta mostrata in artifact e approvata:
# "ok bello"). Stesso principio di Pebble/Stick/PlantFiberIcon: nessun emoji Unicode rende bene
# "bacche" senza leggere come frutta lavorata (🍇/🍓) o come un singolo frutto isolato, quindi
# disegnata a mano. Control minimale, solo _draw(): riempie il proprio Rect2 (vedi IconRegistry.
# get_resource_icon_node, il consumatore), scala automaticamente con qualunque dimensione senza
# valori hardcoded.
#
# Tre bacche SOVRAPPOSTE (non una singola bacca isolata, che leggerebbe come "punto rosso" anonimo)
# con un piccolo riflesso lucido su ciascuna — distingue "bacca succosa" dai sassolini opachi di
# PebbleIcon. Stelo+fogliolina in alto: stesso ruolo del nodo di spago di PlantFiberIcon/dei
# rametti di StickIcon, l'elemento che dice "appena staccato dalla pianta". Offset FISSI (mai
# randf(): icona statica, stesso principio già seguito da tutte le altre).
#
# COLOR_BERRY_MAIN è lo STESSO Color(0.75, 0.08, 0.10) già usato per i puntini bacca sulla mappa
# (MicroCellRenderer.COLOR_SHRUB_BERRY) — stessa risorsa, stesso colore ovunque nella UI, invece di
# una tinta scelta a parte per questa sola icona.

const COLOR_BERRY_MAIN := Color(0.75, 0.08, 0.10, 1.0)
const COLOR_BERRY_DARK := Color(0.55, 0.05, 0.08, 1.0)
const COLOR_BERRY_HIGHLIGHT := Color(0.93, 0.65, 0.63, 0.85)
const COLOR_STEM := Color(0.361, 0.420, 0.196, 1.0)
const COLOR_LEAF := Color(0.298, 0.518, 0.235, 1.0)

# (cx_ratio, cy_ratio, radius_ratio, color) — ordine di disegno back-to-front: le due bacche
# retrostanti prima, quella in primo piano (leggermente più grande) per ultima, ciascuna col
# proprio riflesso subito dopo così non finisce mai sopra la bacca successiva.
const BERRIES := [
	{"cx": 0.36, "cy": 0.58, "r": 0.175, "color": COLOR_BERRY_DARK},
	{"cx": 0.64, "cy": 0.56, "r": 0.17, "color": COLOR_BERRY_MAIN},
	{"cx": 0.50, "cy": 0.80, "r": 0.195, "color": COLOR_BERRY_MAIN},
]

const CURVE_SEGMENTS: int = 8


func _ready() -> void:
	# IGNORE (stesso principio di Pebble/Stick/PlantFiberIcon): puro disegno, mai un bersaglio di
	# input — il tooltip sul riquadro trasportato vive sul CONTENITORE, non su questa icona.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	_draw_stem(w, h)
	_draw_leaf(w, h)
	for berry in BERRIES:
		var center := Vector2(w * berry["cx"], h * berry["cy"])
		var radius: float = h * berry["r"]
		draw_circle(center, radius, berry["color"])
		var highlight_center := center - Vector2(radius * 0.32, radius * 0.34)
		draw_circle(highlight_center, radius * 0.32, COLOR_BERRY_HIGHLIGHT)


# Curva quadratica campionata a segmenti (draw_polyline, stessa tecnica di PlantFiberIcon.
# _draw_fiber_strand) dal centro del grappolo verso l'alto — è quello che le bacche "pendono da".
func _draw_stem(w: float, h: float) -> void:
	var base := Vector2(w * 0.50, h * 0.58)
	var ctrl := Vector2(w * 0.58, h * 0.38)
	var tip := Vector2(w * 0.52, h * 0.20)
	var points := PackedVector2Array()
	for i in range(CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(CURVE_SEGMENTS)
		points.append(_quadratic_point(base, ctrl, tip, t))
	draw_polyline(points, COLOR_STEM, h * 0.045, true)


# Fogliolina appuntita: due curve quadratiche (base->punta, punta->base) campionate insieme in UN
# solo poligono chiuso — stessa idea del nodo di spago di PlantFiberIcon (ellisse approssimata a
# poligono), qui con due curve invece di un'ellisse per ottenere una punta invece di un ovale.
func _draw_leaf(w: float, h: float) -> void:
	var base := Vector2(w * 0.55, h * 0.30)
	var tip := Vector2(w * 0.76, h * 0.20)
	var ctrl_top := Vector2(w * 0.72, h * 0.18)
	var ctrl_bottom := Vector2(w * 0.62, h * 0.32)

	var points := PackedVector2Array()
	for i in range(CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(CURVE_SEGMENTS)
		points.append(_quadratic_point(base, ctrl_top, tip, t))
	for i in range(1, CURVE_SEGMENTS):
		var t: float = float(i) / float(CURVE_SEGMENTS)
		points.append(_quadratic_point(tip, ctrl_bottom, base, t))
	draw_colored_polygon(points, COLOR_LEAF)


func _quadratic_point(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var one_minus_t: float = 1.0 - t
	return p0 * (one_minus_t * one_minus_t) + p1 * (2.0 * one_minus_t * t) + p2 * (t * t)
