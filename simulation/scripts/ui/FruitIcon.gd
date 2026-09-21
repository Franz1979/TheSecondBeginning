class_name FruitIcon
extends Control

# Icona stilizzata "due mele" per il riquadro risorsa trasportata e la griglia slot magazzino
# (2026-09-17, richiesta utente — terza risorsa della catena "fruit stock" generica, TREE/
# domesticable_fruit, dopo berry/acorn, stesso schema/stessa firma di BerryIcon.gd/AcornIcon.gd).
# Nessun emoji Unicode scelto di proposito per restare coerenti con la stessa famiglia di icone
# disegnate a mano (Pebble/Stick/PlantFiber/Berry/Acorn), anche se 🍎 esisterebbe già.
#
# Corpo circolare + riflesso + piccolo stelo + fogliolina (stesso stelo/fogliolina di BerryIcon,
# stesso ruolo: "appena staccata dalla pianta") — una mela completa, riusata per entrambe le
# posizioni in APPLES sotto. DUE mele (non una sola, stesso principio "mai un elemento isolato" già
# seguito da Berry/Acorn), dimensioni leggermente diverse per un aspetto "raccolto a mano". Offset
# FISSI (mai randf(): icona statica, stesso principio di tutte le altre).

const COLOR_FRUIT_BODY := Color(0.80, 0.16, 0.14, 1.0)
const COLOR_FRUIT_BODY_DARK := Color(0.62, 0.10, 0.10, 1.0)
const COLOR_FRUIT_HIGHLIGHT := Color(0.96, 0.62, 0.55, 0.85)
const COLOR_FRUIT_STEM := Color(0.35, 0.30, 0.15, 1.0)
const COLOR_FRUIT_LEAF := Color(0.30, 0.55, 0.20, 1.0)

const CURVE_SEGMENTS: int = 8

# (cx, cy, r, colore corpo) — ordine di disegno back-to-front: la mela più piccola/retrostante prima.
const APPLES := [
	{"cx": 0.36, "cy": 0.60, "r": 0.185, "color": COLOR_FRUIT_BODY_DARK},
	{"cx": 0.64, "cy": 0.58, "r": 0.22, "color": COLOR_FRUIT_BODY},
]


func _ready() -> void:
	# IGNORE (stesso principio di Pebble/Stick/PlantFiber/Berry/AcornIcon): puro disegno, mai un
	# bersaglio di input — il tooltip sul riquadro trasportato vive sul CONTENITORE.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	for apple in APPLES:
		_draw_apple(w, h, apple["cx"], apple["cy"], apple["r"], apple["color"])


# Corpo (cerchio pieno) + riflesso (piccolo cerchio chiaro) + stelo (linea) + fogliolina (poligono,
# stessa tecnica di BerryIcon._draw_leaf) — una mela completa.
func _draw_apple(w: float, h: float, cx: float, cy: float, r: float, body_color: Color) -> void:
	var center := Vector2(w * cx, h * cy)
	var radius: float = h * r
	draw_circle(center, radius, body_color)

	var highlight_center: Vector2 = center - Vector2(radius * 0.35, radius * 0.38)
	draw_circle(highlight_center, radius * 0.30, COLOR_FRUIT_HIGHLIGHT)

	var stem_base: Vector2 = center + Vector2(0.0, -radius * 0.95)
	var stem_tip: Vector2 = stem_base + Vector2(radius * 0.05, -radius * 0.55)
	draw_line(stem_base, stem_tip, COLOR_FRUIT_STEM, h * 0.045, true)

	_draw_leaf(stem_tip, radius)


# Fogliolina appuntita: due curve quadratiche (base->punta, punta->base) campionate insieme in UN
# solo poligono chiuso — stessa idea di BerryIcon._draw_leaf, qui ancorata alla punta dello stelo
# (relativa al raggio della mela) invece che a un punto fisso di w/h, visto che le due mele di
# APPLES sopra hanno raggi diversi.
func _draw_leaf(stem_tip: Vector2, radius: float) -> void:
	var base: Vector2 = stem_tip
	var tip: Vector2 = stem_tip + Vector2(radius * 0.55, -radius * 0.15)
	var ctrl_top: Vector2 = stem_tip + Vector2(radius * 0.42, -radius * 0.35)
	var ctrl_bottom: Vector2 = stem_tip + Vector2(radius * 0.30, radius * 0.05)

	var points := PackedVector2Array()
	for i in range(CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(CURVE_SEGMENTS)
		points.append(_quadratic_point(base, ctrl_top, tip, t))
	for i in range(1, CURVE_SEGMENTS):
		var t: float = float(i) / float(CURVE_SEGMENTS)
		points.append(_quadratic_point(tip, ctrl_bottom, base, t))
	draw_colored_polygon(points, COLOR_FRUIT_LEAF)


func _quadratic_point(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var one_minus_t: float = 1.0 - t
	return p0 * (one_minus_t * one_minus_t) + p1 * (2.0 * one_minus_t * t) + p2 * (t * t)
