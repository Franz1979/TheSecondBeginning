class_name MushroomIcon
extends Control

# Icona stilizzata "due funghi" per il riquadro risorsa trasportata e la griglia slot magazzino
# (2026-09-17, richiesta utente — quarta risorsa TERRAIN_SCATTERED a capacità propria per lotto
# dopo pebble/stick/plant_fiber, stesso schema/stessa firma di BerryIcon.gd/AcornIcon.gd/
# FruitIcon.gd). Nessun emoji Unicode scelto di proposito per restare coerenti con la stessa
# famiglia di icone disegnate a mano.
#
# Cappello ellittico (dome appiattito) + un piccolo bordo più chiaro appena sotto (le lamelle,
# leggibili anche in miniatura come "sotto del cappello") + gambo rettangolare chiaro — un fungo
# completo, riusato per entrambe le posizioni in MUSHROOMS sotto. DUE funghi (non uno solo, stesso
# principio "mai un elemento isolato" già seguito da Berry/Acorn/Fruit), dimensioni leggermente
# diverse per un aspetto "raccolto a mano". Offset FISSI (mai randf(): icona statica, stesso
# principio di tutte le altre).

const COLOR_MUSHROOM_CAP := Color(0.62, 0.32, 0.18, 1.0)
const COLOR_MUSHROOM_CAP_DARK := Color(0.48, 0.24, 0.13, 1.0)
const COLOR_MUSHROOM_GILLS := Color(0.85, 0.78, 0.62, 1.0)
const COLOR_MUSHROOM_STEM := Color(0.92, 0.87, 0.74, 1.0)

const ELLIPSE_SEGMENTS: int = 14

# (cx, cy, cap_rx, cap_ry, colore cappello) — ordine di disegno back-to-front: il fungo più
# piccolo/retrostante prima.
const MUSHROOMS := [
	{"cx": 0.33, "cy": 0.62, "cap_rx": 0.15, "cap_ry": 0.11, "color": COLOR_MUSHROOM_CAP_DARK},
	{"cx": 0.62, "cy": 0.58, "cap_rx": 0.20, "cap_ry": 0.145, "color": COLOR_MUSHROOM_CAP},
]


func _ready() -> void:
	# IGNORE (stesso principio di Pebble/Stick/PlantFiber/Berry/Acorn/FruitIcon): puro disegno,
	# mai un bersaglio di input — il tooltip sul riquadro trasportato vive sul CONTENITORE.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	for mushroom in MUSHROOMS:
		_draw_mushroom(w, h, mushroom["cx"], mushroom["cy"], mushroom["cap_rx"], mushroom["cap_ry"], mushroom["color"])


# Gambo (rettangolo, disegnato PRIMA quindi sotto) + lamelle (ellisse più chiara/più larga del
# cappello, spostata leggermente in basso così un bordo resta visibile appena sotto il cappello) +
# cappello (ellisse piena, disegnato per ULTIMO quindi sopra) — un fungo completo.
func _draw_mushroom(w: float, h: float, cx: float, cy: float, cap_rx: float, cap_ry: float, cap_color: Color) -> void:
	var cap_center := Vector2(w * cx, h * cy)
	var cap_radius := Vector2(w * cap_rx, h * cap_ry)

	var stem_width: float = cap_radius.x * 0.5
	var stem_height: float = cap_radius.y * 2.4
	var stem_top: Vector2 = cap_center + Vector2(0.0, cap_radius.y * 0.5)
	draw_rect(Rect2(stem_top - Vector2(stem_width * 0.5, 0.0), Vector2(stem_width, stem_height)), COLOR_MUSHROOM_STEM)

	var rim_center: Vector2 = cap_center + Vector2(0.0, cap_radius.y * 0.35)
	var rim_radius := Vector2(cap_radius.x * 1.1, cap_radius.y * 0.65)
	_draw_ellipse(rim_center, rim_radius, COLOR_MUSHROOM_GILLS)

	_draw_ellipse(cap_center, cap_radius, cap_color)


# Ellisse piena approssimata a poligono (Godot non ha un draw_ellipse nativo) — stesso principio
# già usato da AcornIcon._draw_ellipse, qui privato a questo file (nessuna condivisione tra icone
# diverse, stesso principio "nessuna classe condivisa tra usi diversi" già seguito ovunque).
func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(ELLIPSE_SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
