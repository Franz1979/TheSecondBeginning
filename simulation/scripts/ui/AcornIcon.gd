class_name AcornIcon
extends Control

# Icona stilizzata "due ghiande" per il riquadro risorsa trasportata e la griglia slot magazzino
# (2026-09-17, richiesta utente — prima risorsa aggiunta con TerrainScatteredResourceService.
# FRUIT_STOCK_SOURCES dopo berry, stesso schema icona di BerryIcon.gd). Nessun emoji Unicode rende
# bene "ghianda" (🌰 legge come castagna/marrone glacé, forma e colore sbagliati), quindi
# disegnata a mano — stesso principio già seguito per Pebble/Stick/PlantFiber/Berry.
#
# Corpo ellittico + cappuccio ellittico più scuro sovrapposto in alto + piccolo stelo: la sagoma
# "due ellissi sovrapposte" è la scorciatoia standard per leggere "ghianda" a colpo d'occhio anche
# a dimensione minuscola, senza bisogno della vera trama a scaglie del cappuccio. DUE ghiande (non
# una sola, che leggerebbe come "goccia marrone" anonima — stesso principio già seguito da
# BerryIcon per le tre bacche), dimensioni/rotazioni leggermente diverse per un aspetto "raccolto a
# mano", non stampato. Offset FISSI (mai randf(): icona statica, stesso principio di tutte le
# altre).

const COLOR_ACORN_BODY := Color(0.72, 0.52, 0.28, 1.0)
const COLOR_ACORN_BODY_DARK := Color(0.60, 0.42, 0.20, 1.0)
const COLOR_ACORN_HIGHLIGHT := Color(0.88, 0.72, 0.48, 0.85)
const COLOR_ACORN_CAP := Color(0.42, 0.28, 0.14, 1.0)
const COLOR_ACORN_STEM := Color(0.35, 0.30, 0.15, 1.0)

const ELLIPSE_SEGMENTS: int = 14

# (cx, cy, rx, ry, rotazione, colore corpo) — ordine di disegno back-to-front: la ghianda più
# piccola/retrostante prima.
const ACORNS := [
	{"cx": 0.34, "cy": 0.58, "rx": 0.15, "ry": 0.19, "rot": -0.25, "color": COLOR_ACORN_BODY_DARK},
	{"cx": 0.62, "cy": 0.62, "rx": 0.19, "ry": 0.235, "rot": 0.18, "color": COLOR_ACORN_BODY},
]


func _ready() -> void:
	# IGNORE (stesso principio di Pebble/Stick/PlantFiber/BerryIcon): puro disegno, mai un
	# bersaglio di input — il tooltip sul riquadro trasportato vive sul CONTENITORE.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	for acorn in ACORNS:
		_draw_acorn(w, h, acorn["cx"], acorn["cy"], acorn["rx"], acorn["ry"], acorn["rot"], acorn["color"])


# Corpo (ellisse piena) + riflesso (piccola ellisse chiara) + cappuccio (ellisse più corta/più
# scura, sovrapposta in alto, stessa rotazione del corpo) + piccolo stelo (linea) — una ghianda
# completa, riusata per entrambe le posizioni in ACORNS sopra.
func _draw_acorn(w: float, h: float, cx: float, cy: float, rx: float, ry: float, rotation: float, body_color: Color) -> void:
	var center := Vector2(w * cx, h * cy)
	var body_radius := Vector2(w * rx, h * ry)
	_draw_ellipse(center, body_radius, rotation, body_color)

	var highlight_offset: Vector2 = Vector2(-body_radius.x * 0.35, -body_radius.y * 0.3).rotated(rotation)
	_draw_ellipse(center + highlight_offset, body_radius * 0.35, rotation, COLOR_ACORN_HIGHLIGHT)

	var cap_center: Vector2 = center + Vector2(0.0, -body_radius.y * 0.62).rotated(rotation)
	var cap_radius := Vector2(body_radius.x * 1.05, body_radius.y * 0.5)
	_draw_ellipse(cap_center, cap_radius, rotation, COLOR_ACORN_CAP)

	var stem_base: Vector2 = cap_center + Vector2(0.0, -cap_radius.y * 0.7).rotated(rotation)
	var stem_tip: Vector2 = stem_base + Vector2(0.0, -body_radius.y * 0.35).rotated(rotation)
	draw_line(stem_base, stem_tip, COLOR_ACORN_STEM, h * 0.04, true)


# Ellisse piena approssimata a poligono (Godot non ha un draw_ellipse nativo) — stesso principio
# già usato da PlantFiberIcon._draw_tie_knot, qui promosso a helper riusato per corpo/cappuccio/
# riflesso di ENTRAMBE le ghiande (nessuna condivisione con altre icone: resta privato a questo
# file, stesso principio "nessuna classe condivisa tra usi diversi" già seguito ovunque nel
# progetto).
func _draw_ellipse(center: Vector2, radius: Vector2, rotation: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(ELLIPSE_SEGMENTS)
		var local_point := Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		points.append(center + local_point.rotated(rotation))
	draw_colored_polygon(points, color)
