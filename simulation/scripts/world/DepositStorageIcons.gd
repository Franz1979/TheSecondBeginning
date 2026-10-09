class_name DepositStorageIcons
extends RefCounted

# Icone "da magazzino" delle risorse (2026-09-26, richiesta utente): le stesse geometrie disegnate da sempre
# nella griglia degli slot di un magazzino (MicroCellRenderer._draw_deposit_site_storage_grid), spostate qui
# senza modifiche al disegno perché servono anche ai mucchi a terra (GroundPileView). Prima erano metodi
# privati di MicroCellRenderer che disegnavano solo su se stesso; ora sono funzioni statiche che disegnano su
# un `canvas` qualunque (un CanvasItem nel suo _draw), nello spazio locale del canvas: `top_left` è l'angolo
# del quadrato dell'icona e `side` il suo lato, in pixel. Per ruotare o spostare un'icona il chiamante usa
# canvas.draw_set_transform prima di draw_icon.
#
# Aggiungere un'icona per una risorsa nuova: una riga in DEPOSIT_STORAGE_ICON_DRAW_METHODS e la sua funzione
# _draw_deposit_storage_*_icon(canvas, top_left, side) qui sotto.


# Disegna l'icona magazzino di `resource_name` su `canvas`. Ritorna false (senza disegnare nulla) se la risorsa
# non ha un'icona dedicata: il chiamante disegna il proprio ripiego (pallino nel colore della risorsa).
# Precedenza (2026-10-04, richiesta utente): se c'è un'immagine in IconRegistry.ICON_TEXTURE_DIR la disegna nel
# quadrato (proporzioni mantenute, centrata), altrimenti la funzione di disegno — stessa regola dei pannelli
# (IconRegistry.get_resource_icon_node).
static func draw_icon(canvas: CanvasItem, resource_name: String, top_left: Vector2, side: float) -> bool:
	var texture := IconRegistry.get_icon_texture(resource_name)
	if texture != null:
		var texture_size := texture.get_size()
		var scale: float = side / maxf(maxf(texture_size.x, texture_size.y), 1.0)
		var drawn_size := texture_size * scale
		canvas.draw_texture_rect(texture, Rect2(top_left + (Vector2(side, side) - drawn_size) * 0.5, drawn_size), false)
		return true
	var method: String = DEPOSIT_STORAGE_ICON_DRAW_METHODS.get(resource_name, "")
	if method == "":
		return false
	_dispatcher().call(method, canvas, top_left, side)
	return true


# Istanza usata solo per invocare per nome le funzioni statiche della tabella qui sotto.
static var _dispatcher_instance: DepositStorageIcons = null


static func _dispatcher() -> DepositStorageIcons:
	if _dispatcher_instance == null:
		_dispatcher_instance = DepositStorageIcons.new()
	return _dispatcher_instance


# Collegamento resource_name -> funzione di disegno (2026-09-19, refactor lot_source: un Dictionary invece
# di un match scritto a mano, coerente con IconRegistry). Una risorsa assente usa il ripiego del chiamante.
const DEPOSIT_STORAGE_ICON_DRAW_METHODS := {
	"pebble": "_draw_deposit_storage_pebble_icon",
	"stick": "_draw_deposit_storage_stick_icon",
	"plant_fiber": "_draw_deposit_storage_plant_fiber_icon",
	"berry": "_draw_deposit_storage_berry_icon",
	"acorn": "_draw_deposit_storage_acorn_icon",
	"fruit": "_draw_deposit_storage_fruit_icon",
	"mushroom": "_draw_deposit_storage_mushroom_icon",
	"eggs": "_draw_deposit_storage_eggs_icon",
	"wild_vegetables": "_draw_deposit_storage_wild_vegetables_icon",
	"medicinal_herbs": "_draw_deposit_storage_medicinal_herbs_icon",
	"fiber_rope": "_draw_deposit_storage_fiber_rope_icon",
	"wooden_spear": "_draw_deposit_storage_wooden_spear_icon",
	"stone_spear": "_draw_deposit_storage_stone_spear_icon",
	"bow": "_draw_deposit_storage_bow_icon",
	"stone_axe": "_draw_deposit_storage_stone_axe_icon",
	"arrow_bundle": "_draw_deposit_storage_arrow_bundle_icon",
	"stone_knife": "_draw_deposit_storage_stone_knife_icon",
	"bone_awl": "_draw_deposit_storage_bone_awl_icon",
	"hide_bag": "_draw_deposit_storage_hide_bag_icon",
	"dried_hide_bag": "_draw_deposit_storage_dried_hide_bag_icon",
	"meat": "_draw_deposit_storage_meat_icon",
	"cooked_meat": "_draw_deposit_storage_cooked_meat_icon",
	"hide": "_draw_deposit_storage_hide_icon",
	"dried_meat": "_draw_deposit_storage_dried_meat_icon",
	"dried_hide": "_draw_deposit_storage_dried_hide_icon",
	"smoked_meat": "_draw_deposit_storage_smoked_meat_icon",
	"smoked_hide": "_draw_deposit_storage_smoked_hide_icon",
	"sinew": "_draw_deposit_storage_sinew_icon",
	"bone": "_draw_deposit_storage_bone_icon",
}


# Replica in world-space (immediate-mode Node2D, NON riusabile da PebbleIcon.gd che è Control._draw
# — stesso principio "duplicata apposta" già seguito altrove in questo file, es. _draw_deposit_site
# vs BuildingGhost) della geometria/colori di PebbleIcon.gd: stessi punti/raggi frazionari (0..1),
# qui scalati per `side` invece che per size.x/size.y di un Control, e traslati su `top_left`
# (angolo in alto a sinistra del quadrato di sfondo, non il centro — stessa convenzione di
# PebbleIcon, dove i punti sono frazioni dell'intero rettangolo, non del centro).
const DEPOSIT_STORAGE_PEBBLE_COLOR := Color(0.58, 0.57, 0.54, 1.0)
const DEPOSIT_STORAGE_PEBBLE_OUTLINE_COLOR := Color(0.32, 0.31, 0.29, 1.0)
const DEPOSIT_STORAGE_PEBBLES := [
	Vector3(0.22, 0.28, 0.12), Vector3(0.55, 0.18, 0.10), Vector3(0.78, 0.35, 0.13),
	Vector3(0.35, 0.55, 0.11), Vector3(0.65, 0.60, 0.09), Vector3(0.85, 0.72, 0.10),
	Vector3(0.15, 0.75, 0.09), Vector3(0.48, 0.82, 0.08),
]

static func _draw_deposit_storage_pebble_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	for pebble in DEPOSIT_STORAGE_PEBBLES:
		var center: Vector2 = top_left + Vector2(pebble.x * side, pebble.y * side)
		var radius: float = pebble.z * side
		canvas.draw_circle(center, radius, DEPOSIT_STORAGE_PEBBLE_COLOR)
		canvas.draw_arc(center, radius, 0.0, TAU, 8, DEPOSIT_STORAGE_PEBBLE_OUTLINE_COLOR, side * 0.04, true)


# Replica world-space di StickIcon.gd (stesso principio del blocco pebble sopra) — 3 "rametti"
# (linee spezzate a due segmenti, non rette) in tre bruni diversi, stessi punti frazionari/stessi
# spessori relativi (h*0.09/0.07/0.06 in StickIcon, qui side al posto di h: icona sempre quadrata
# quindi w=h=side, nessuna distinzione necessaria).
const DEPOSIT_STORAGE_STICK_COLOR_MAIN := Color(0.42, 0.30, 0.16, 1.0)
const DEPOSIT_STORAGE_STICK_COLOR_LIGHT := Color(0.55, 0.40, 0.22, 1.0)
const DEPOSIT_STORAGE_STICK_COLOR_DARK := Color(0.32, 0.22, 0.11, 1.0)

static func _draw_deposit_storage_stick_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	_draw_deposit_storage_twig(canvas,
		top_left + Vector2(side * 0.18, side * 0.78), top_left + Vector2(side * 0.52, side * 0.42),
		top_left + Vector2(side * 0.82, side * 0.20), DEPOSIT_STORAGE_STICK_COLOR_MAIN, side * 0.09
	)
	_draw_deposit_storage_twig(canvas,
		top_left + Vector2(side * 0.15, side * 0.30), top_left + Vector2(side * 0.48, side * 0.58),
		top_left + Vector2(side * 0.85, side * 0.75), DEPOSIT_STORAGE_STICK_COLOR_LIGHT, side * 0.07
	)
	_draw_deposit_storage_twig(canvas,
		top_left + Vector2(side * 0.35, side * 0.85), top_left + Vector2(side * 0.55, side * 0.50),
		top_left + Vector2(side * 0.68, side * 0.15), DEPOSIT_STORAGE_STICK_COLOR_DARK, side * 0.06
	)


static func _draw_deposit_storage_twig(canvas: CanvasItem, from: Vector2, mid: Vector2, to: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(from, mid, color, width, true)
	canvas.draw_line(mid, to, color, width, true)


# Replica world-space di PlantFiberIcon.gd (stesso principio dei due blocchi sopra) — 4 fili
# curvi (curva quadratica campionata, non spezzata come i rametti) che convergono in un nodo di
# spago, stessi punti/spessori frazionari di PlantFiberIcon, `side` al posto di w/h (icona sempre
# quadrata qui, w=h=side).
const DEPOSIT_STORAGE_FIBER_COLOR_MAIN := Color(0.624, 0.682, 0.361, 1.0)
const DEPOSIT_STORAGE_FIBER_COLOR_LIGHT := Color(0.765, 0.820, 0.498, 1.0)
const DEPOSIT_STORAGE_FIBER_COLOR_DARK := Color(0.439, 0.498, 0.247, 1.0)
const DEPOSIT_STORAGE_FIBER_TIE_COLOR := Color(0.420, 0.290, 0.169, 1.0)
const DEPOSIT_STORAGE_FIBER_STRANDS := [
	{"end": Vector2(0.16, 0.12), "ctrl": Vector2(0.22, 0.42), "color": DEPOSIT_STORAGE_FIBER_COLOR_DARK, "width": 0.055},
	{"end": Vector2(0.38, 0.08), "ctrl": Vector2(0.40, 0.40), "color": DEPOSIT_STORAGE_FIBER_COLOR_LIGHT, "width": 0.06},
	{"end": Vector2(0.62, 0.09), "ctrl": Vector2(0.58, 0.42), "color": DEPOSIT_STORAGE_FIBER_COLOR_MAIN, "width": 0.062},
	{"end": Vector2(0.84, 0.16), "ctrl": Vector2(0.76, 0.44), "color": DEPOSIT_STORAGE_FIBER_COLOR_DARK, "width": 0.05},
]
const DEPOSIT_STORAGE_FIBER_CURVE_SEGMENTS: int = 8

static func _draw_deposit_storage_plant_fiber_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	var base: Vector2 = top_left + Vector2(side * 0.50, side * 0.86)
	for strand in DEPOSIT_STORAGE_FIBER_STRANDS:
		var ctrl: Vector2 = top_left + Vector2(strand["ctrl"].x, strand["ctrl"].y) * side
		var end: Vector2 = top_left + Vector2(strand["end"].x, strand["end"].y) * side
		_draw_deposit_storage_fiber_strand(canvas, base, ctrl, end, strand["color"], side * strand["width"])
	_draw_deposit_storage_fiber_tie_knot(canvas, base, side)


static func _draw_deposit_storage_fiber_strand(canvas: CanvasItem, base: Vector2, ctrl: Vector2, end: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_FIBER_CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(DEPOSIT_STORAGE_FIBER_CURVE_SEGMENTS)
		var one_minus_t: float = 1.0 - t
		points.append(base * (one_minus_t * one_minus_t) + ctrl * (2.0 * one_minus_t * t) + end * (t * t))
	canvas.draw_polyline(points, color, width, true)


static func _draw_deposit_storage_fiber_tie_knot(canvas: CanvasItem, base: Vector2, side: float) -> void:
	var center: Vector2 = base + Vector2(0.0, -side * 0.06)
	var rx: float = side * 0.14
	var ry: float = side * 0.075
	var rotation: float = -0.12
	var points := PackedVector2Array()
	const KNOT_SEGMENTS: int = 16
	for i in range(KNOT_SEGMENTS):
		var angle: float = TAU * float(i) / float(KNOT_SEGMENTS)
		var local_point := Vector2(cos(angle) * rx, sin(angle) * ry)
		points.append(center + local_point.rotated(rotation))
	canvas.draw_colored_polygon(points, DEPOSIT_STORAGE_FIBER_TIE_COLOR)


# Replica world-space di BerryIcon.gd (2026-09-17, richiesta utente — bugfix "pallino giallo nel
# magazzino": mancava del tutto qui, cadeva nel fallback generico _: di _draw_deposit_site_
# storage_grid, MAI nell'icona vera — la UI Control di BerryIcon.gd non ha mai avuto nulla a che
# fare con questo bug, è un sistema di disegno completamente separato) — stesso principio dei tre
# blocchi sopra: stessi punti/raggi/colori frazionari (0..1) di BerryIcon.gd, qui scalati per
# `side` e traslati su `top_left` invece che per size.x/size.y di un Control.
const DEPOSIT_STORAGE_BERRY_COLOR_MAIN := Color(0.75, 0.08, 0.10, 1.0)
const DEPOSIT_STORAGE_BERRY_COLOR_DARK := Color(0.55, 0.05, 0.08, 1.0)
const DEPOSIT_STORAGE_BERRY_COLOR_HIGHLIGHT := Color(0.93, 0.65, 0.63, 0.85)
const DEPOSIT_STORAGE_BERRY_COLOR_STEM := Color(0.361, 0.420, 0.196, 1.0)
const DEPOSIT_STORAGE_BERRY_COLOR_LEAF := Color(0.298, 0.518, 0.235, 1.0)
const DEPOSIT_STORAGE_BERRIES := [
	{"cx": 0.36, "cy": 0.58, "r": 0.175, "color": DEPOSIT_STORAGE_BERRY_COLOR_DARK},
	{"cx": 0.64, "cy": 0.56, "r": 0.17, "color": DEPOSIT_STORAGE_BERRY_COLOR_MAIN},
	{"cx": 0.50, "cy": 0.80, "r": 0.195, "color": DEPOSIT_STORAGE_BERRY_COLOR_MAIN},
]
const DEPOSIT_STORAGE_BERRY_CURVE_SEGMENTS: int = 8

static func _draw_deposit_storage_berry_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	_draw_deposit_storage_berry_stem(canvas, top_left, side)
	_draw_deposit_storage_berry_leaf(canvas, top_left, side)
	for berry in DEPOSIT_STORAGE_BERRIES:
		var center: Vector2 = top_left + Vector2(berry["cx"], berry["cy"]) * side
		var radius: float = side * berry["r"]
		canvas.draw_circle(center, radius, berry["color"])
		var highlight_center: Vector2 = center - Vector2(radius * 0.32, radius * 0.34)
		canvas.draw_circle(highlight_center, radius * 0.32, DEPOSIT_STORAGE_BERRY_COLOR_HIGHLIGHT)


static func _draw_deposit_storage_berry_stem(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	var base: Vector2 = top_left + Vector2(0.50, 0.58) * side
	var ctrl: Vector2 = top_left + Vector2(0.58, 0.38) * side
	var tip: Vector2 = top_left + Vector2(0.52, 0.20) * side
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_BERRY_CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(DEPOSIT_STORAGE_BERRY_CURVE_SEGMENTS)
		var one_minus_t: float = 1.0 - t
		points.append(base * (one_minus_t * one_minus_t) + ctrl * (2.0 * one_minus_t * t) + tip * (t * t))
	canvas.draw_polyline(points, DEPOSIT_STORAGE_BERRY_COLOR_STEM, side * 0.045, true)


static func _draw_deposit_storage_berry_leaf(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	var base: Vector2 = top_left + Vector2(0.55, 0.30) * side
	var tip: Vector2 = top_left + Vector2(0.76, 0.20) * side
	var ctrl_top: Vector2 = top_left + Vector2(0.72, 0.18) * side
	var ctrl_bottom: Vector2 = top_left + Vector2(0.62, 0.32) * side
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_BERRY_CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(DEPOSIT_STORAGE_BERRY_CURVE_SEGMENTS)
		var one_minus_t: float = 1.0 - t
		points.append(base * (one_minus_t * one_minus_t) + ctrl_top * (2.0 * one_minus_t * t) + tip * (t * t))
	for i in range(1, DEPOSIT_STORAGE_BERRY_CURVE_SEGMENTS):
		var t: float = float(i) / float(DEPOSIT_STORAGE_BERRY_CURVE_SEGMENTS)
		var one_minus_t: float = 1.0 - t
		points.append(tip * (one_minus_t * one_minus_t) + ctrl_bottom * (2.0 * one_minus_t * t) + base * (t * t))
	canvas.draw_colored_polygon(points, DEPOSIT_STORAGE_BERRY_COLOR_LEAF)


# Replica world-space di AcornIcon.gd (2026-09-17, richiesta utente — seconda risorsa della catena
# "fruit stock" generica dopo berry, stesso schema/stesso principio del blocco berry sopra): due
# ghiande, ciascuna corpo+riflesso+cappuccio ellittici + piccolo stelo, stessi punti/raggi/colori
# frazionari (0..1) di AcornIcon.gd, qui scalati per `side` e traslati su `top_left` invece che per
# size.x/size.y di un Control.
const DEPOSIT_STORAGE_ACORN_COLOR_BODY := Color(0.72, 0.52, 0.28, 1.0)
const DEPOSIT_STORAGE_ACORN_COLOR_BODY_DARK := Color(0.60, 0.42, 0.20, 1.0)
const DEPOSIT_STORAGE_ACORN_COLOR_HIGHLIGHT := Color(0.88, 0.72, 0.48, 0.85)
const DEPOSIT_STORAGE_ACORN_COLOR_CAP := Color(0.42, 0.28, 0.14, 1.0)
const DEPOSIT_STORAGE_ACORN_COLOR_STEM := Color(0.35, 0.30, 0.15, 1.0)
const DEPOSIT_STORAGE_ACORN_ELLIPSE_SEGMENTS: int = 14
const DEPOSIT_STORAGE_ACORNS := [
	{"cx": 0.34, "cy": 0.58, "rx": 0.15, "ry": 0.19, "rot": -0.25, "color": DEPOSIT_STORAGE_ACORN_COLOR_BODY_DARK},
	{"cx": 0.62, "cy": 0.62, "rx": 0.19, "ry": 0.235, "rot": 0.18, "color": DEPOSIT_STORAGE_ACORN_COLOR_BODY},
]

static func _draw_deposit_storage_acorn_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	for acorn in DEPOSIT_STORAGE_ACORNS:
		_draw_deposit_storage_acorn(canvas,
			top_left, side, acorn["cx"], acorn["cy"], acorn["rx"], acorn["ry"], acorn["rot"], acorn["color"]
		)


static func _draw_deposit_storage_acorn(canvas: CanvasItem,
	top_left: Vector2, side: float, cx: float, cy: float, rx: float, ry: float, rotation: float, body_color: Color
) -> void:
	var center: Vector2 = top_left + Vector2(cx, cy) * side
	var body_radius := Vector2(rx * side, ry * side)
	_draw_deposit_storage_ellipse(canvas, center, body_radius, rotation, body_color)

	var highlight_offset: Vector2 = Vector2(-body_radius.x * 0.35, -body_radius.y * 0.3).rotated(rotation)
	_draw_deposit_storage_ellipse(canvas, center + highlight_offset, body_radius * 0.35, rotation, DEPOSIT_STORAGE_ACORN_COLOR_HIGHLIGHT)

	var cap_center: Vector2 = center + Vector2(0.0, -body_radius.y * 0.62).rotated(rotation)
	var cap_radius := Vector2(body_radius.x * 1.05, body_radius.y * 0.5)
	_draw_deposit_storage_ellipse(canvas, cap_center, cap_radius, rotation, DEPOSIT_STORAGE_ACORN_COLOR_CAP)

	var stem_base: Vector2 = cap_center + Vector2(0.0, -cap_radius.y * 0.7).rotated(rotation)
	var stem_tip: Vector2 = stem_base + Vector2(0.0, -body_radius.y * 0.35).rotated(rotation)
	canvas.draw_line(stem_base, stem_tip, DEPOSIT_STORAGE_ACORN_COLOR_STEM, side * 0.04, true)


static func _draw_deposit_storage_ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, rotation: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_ACORN_ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(DEPOSIT_STORAGE_ACORN_ELLIPSE_SEGMENTS)
		var local_point := Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		points.append(center + local_point.rotated(rotation))
	canvas.draw_colored_polygon(points, color)


# Replica world-space di FruitIcon.gd (2026-09-17, richiesta utente — terza risorsa della catena
# "fruit stock" generica dopo berry/acorn, stesso schema/stesso principio dei due blocchi sopra):
# stessi punti/raggi/colori frazionari (0..1) di FruitIcon.gd, qui scalati per `side` e traslati su
# `top_left` invece che per size.x/size.y di un Control.
const DEPOSIT_STORAGE_FRUIT_COLOR_BODY := Color(0.80, 0.16, 0.14, 1.0)
const DEPOSIT_STORAGE_FRUIT_COLOR_BODY_DARK := Color(0.62, 0.10, 0.10, 1.0)
const DEPOSIT_STORAGE_FRUIT_COLOR_HIGHLIGHT := Color(0.96, 0.62, 0.55, 0.85)
const DEPOSIT_STORAGE_FRUIT_COLOR_STEM := Color(0.35, 0.30, 0.15, 1.0)
const DEPOSIT_STORAGE_FRUIT_COLOR_LEAF := Color(0.30, 0.55, 0.20, 1.0)
const DEPOSIT_STORAGE_FRUIT_CURVE_SEGMENTS: int = 8
const DEPOSIT_STORAGE_APPLES := [
	{"cx": 0.36, "cy": 0.60, "r": 0.185, "color": DEPOSIT_STORAGE_FRUIT_COLOR_BODY_DARK},
	{"cx": 0.64, "cy": 0.58, "r": 0.22, "color": DEPOSIT_STORAGE_FRUIT_COLOR_BODY},
]

static func _draw_deposit_storage_fruit_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	for apple in DEPOSIT_STORAGE_APPLES:
		_draw_deposit_storage_apple(canvas, top_left, side, apple["cx"], apple["cy"], apple["r"], apple["color"])


static func _draw_deposit_storage_apple(canvas: CanvasItem, top_left: Vector2, side: float, cx: float, cy: float, r: float, body_color: Color) -> void:
	var center: Vector2 = top_left + Vector2(cx, cy) * side
	var radius: float = r * side
	canvas.draw_circle(center, radius, body_color)

	var highlight_center: Vector2 = center - Vector2(radius * 0.35, radius * 0.38)
	canvas.draw_circle(highlight_center, radius * 0.30, DEPOSIT_STORAGE_FRUIT_COLOR_HIGHLIGHT)

	var stem_base: Vector2 = center + Vector2(0.0, -radius * 0.95)
	var stem_tip: Vector2 = stem_base + Vector2(radius * 0.05, -radius * 0.55)
	canvas.draw_line(stem_base, stem_tip, DEPOSIT_STORAGE_FRUIT_COLOR_STEM, side * 0.045, true)

	_draw_deposit_storage_fruit_leaf(canvas, stem_tip, radius)


static func _draw_deposit_storage_fruit_leaf(canvas: CanvasItem, stem_tip: Vector2, radius: float) -> void:
	var base: Vector2 = stem_tip
	var tip: Vector2 = stem_tip + Vector2(radius * 0.55, -radius * 0.15)
	var ctrl_top: Vector2 = stem_tip + Vector2(radius * 0.42, -radius * 0.35)
	var ctrl_bottom: Vector2 = stem_tip + Vector2(radius * 0.30, radius * 0.05)
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_FRUIT_CURVE_SEGMENTS + 1):
		var t: float = float(i) / float(DEPOSIT_STORAGE_FRUIT_CURVE_SEGMENTS)
		var one_minus_t: float = 1.0 - t
		points.append(base * (one_minus_t * one_minus_t) + ctrl_top * (2.0 * one_minus_t * t) + tip * (t * t))
	for i in range(1, DEPOSIT_STORAGE_FRUIT_CURVE_SEGMENTS):
		var t: float = float(i) / float(DEPOSIT_STORAGE_FRUIT_CURVE_SEGMENTS)
		var one_minus_t: float = 1.0 - t
		points.append(tip * (one_minus_t * one_minus_t) + ctrl_bottom * (2.0 * one_minus_t * t) + base * (t * t))
	# Icona piccola (2026-10-09, errore "Invalid polygon data, triangulation failed"): con pochi pixel i punti della foglia
	# quasi coincidono e la triangolazione fallisce — si disegna solo se il poligono si triangola, altrimenti una lineetta.
	if Geometry2D.triangulate_polygon(points).is_empty():
		canvas.draw_line(base, tip, DEPOSIT_STORAGE_FRUIT_COLOR_LEAF, maxf(radius * 0.12, 1.0), true)
		return
	canvas.draw_colored_polygon(points, DEPOSIT_STORAGE_FRUIT_COLOR_LEAF)


# Replica world-space di MushroomIcon.gd (2026-09-18, richiesta utente — bugfix "pallino giallo nel
# magazzino": mancava del tutto qui, cadeva nel fallback generico _: di _draw_deposit_site_
# storage_grid, STESSO identico bug già risolto in passato per berry) — stessi punti/raggi/colori
# frazionari (0..1) di MushroomIcon.gd, qui scalati per `side` e traslati su `top_left` invece che
# per size.x/size.y di un Control.
const DEPOSIT_STORAGE_MUSHROOM_COLOR_CAP := Color(0.62, 0.32, 0.18, 1.0)
const DEPOSIT_STORAGE_MUSHROOM_COLOR_CAP_DARK := Color(0.48, 0.24, 0.13, 1.0)
const DEPOSIT_STORAGE_MUSHROOM_COLOR_GILLS := Color(0.85, 0.78, 0.62, 1.0)
const DEPOSIT_STORAGE_MUSHROOM_COLOR_STEM := Color(0.92, 0.87, 0.74, 1.0)
const DEPOSIT_STORAGE_MUSHROOM_ELLIPSE_SEGMENTS: int = 14
const DEPOSIT_STORAGE_MUSHROOMS := [
	{"cx": 0.33, "cy": 0.62, "cap_rx": 0.15, "cap_ry": 0.11, "color": DEPOSIT_STORAGE_MUSHROOM_COLOR_CAP_DARK},
	{"cx": 0.62, "cy": 0.58, "cap_rx": 0.20, "cap_ry": 0.145, "color": DEPOSIT_STORAGE_MUSHROOM_COLOR_CAP},
]

static func _draw_deposit_storage_mushroom_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	for mushroom in DEPOSIT_STORAGE_MUSHROOMS:
		_draw_deposit_storage_mushroom(canvas,
			top_left, side, mushroom["cx"], mushroom["cy"], mushroom["cap_rx"], mushroom["cap_ry"], mushroom["color"]
		)


static func _draw_deposit_storage_mushroom(canvas: CanvasItem,
	top_left: Vector2, side: float, cx: float, cy: float, cap_rx: float, cap_ry: float, cap_color: Color
) -> void:
	var cap_center: Vector2 = top_left + Vector2(cx, cy) * side
	var cap_radius := Vector2(cap_rx * side, cap_ry * side)

	var stem_width: float = cap_radius.x * 0.5
	var stem_height: float = cap_radius.y * 2.4
	var stem_top: Vector2 = cap_center + Vector2(0.0, cap_radius.y * 0.5)
	canvas.draw_rect(Rect2(stem_top - Vector2(stem_width * 0.5, 0.0), Vector2(stem_width, stem_height)), DEPOSIT_STORAGE_MUSHROOM_COLOR_STEM)

	var rim_center: Vector2 = cap_center + Vector2(0.0, cap_radius.y * 0.35)
	var rim_radius := Vector2(cap_radius.x * 1.1, cap_radius.y * 0.65)
	_draw_deposit_storage_mushroom_ellipse(canvas, rim_center, rim_radius, DEPOSIT_STORAGE_MUSHROOM_COLOR_GILLS)

	_draw_deposit_storage_mushroom_ellipse(canvas, cap_center, cap_radius, cap_color)


static func _draw_deposit_storage_mushroom_ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_MUSHROOM_ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(DEPOSIT_STORAGE_MUSHROOM_ELLIPSE_SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	canvas.draw_colored_polygon(points, color)


# Replica world-space per "eggs" (2026-09-18, richiesta utente — bugfix "vedo solo il pallino
# blu nel magazzino": mancava del tutto qui, cadeva nel fallback generico _: di _draw_deposit_
# site_storage_grid — STESSO identico bug già risolto per mushroom sopra, vedi quel commento). A
# differenza di berry/acorn/fruit/mushroom (icone Control dedicate in simulation/scripts/ui/,
# replicate qui 1:1) eggs usa solo un emoji altrove (IconRegistry.RESOURCE_ICONS — un'emoji non è
# replicabile in world-space, nessun *Icon.gd da cui copiare punti/colori): geometria disegnata
# direttamente qui, TRE piccole ellissi color guscio ravvicinate ("2 o 3 uova vicine", richiesta
# esplicita utente) invece di un singolo ovale — niente stelo/foglia, non è un frutto. Stessa forma
# ovale asimmetrica (più stretta verso l'alto) della mesh del nido a terra (vedi _ensure_egg_mesh
# più sotto in questo file), per coerenza visiva tra i due punti di rendering di questa risorsa.
const DEPOSIT_STORAGE_EGG_COLOR := Color(0.93, 0.88, 0.74, 1.0)
const DEPOSIT_STORAGE_EGG_COLOR_SHADOW := Color(0.80, 0.74, 0.58, 1.0)
const DEPOSIT_STORAGE_EGG_ELLIPSE_SEGMENTS: int = 12
const DEPOSIT_STORAGE_EGGS := [
	{"cx": 0.33, "cy": 0.62, "rx": 0.13, "ry": 0.17, "rot": -0.2, "color": DEPOSIT_STORAGE_EGG_COLOR_SHADOW},
	{"cx": 0.57, "cy": 0.68, "rx": 0.14, "ry": 0.185, "rot": 0.05, "color": DEPOSIT_STORAGE_EGG_COLOR},
	{"cx": 0.68, "cy": 0.46, "rx": 0.125, "ry": 0.165, "rot": 0.3, "color": DEPOSIT_STORAGE_EGG_COLOR_SHADOW},
]

static func _draw_deposit_storage_eggs_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	for egg in DEPOSIT_STORAGE_EGGS:
		_draw_deposit_storage_egg(canvas, top_left, side, egg["cx"], egg["cy"], egg["rx"], egg["ry"], egg["rot"], egg["color"])


static func _draw_deposit_storage_egg(canvas: CanvasItem,
	top_left: Vector2, side: float, cx: float, cy: float, rx: float, ry: float, rotation: float, color: Color
) -> void:
	var center: Vector2 = top_left + Vector2(cx, cy) * side
	var radius := Vector2(rx * side, ry * side)
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_EGG_ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(DEPOSIT_STORAGE_EGG_ELLIPSE_SEGMENTS)
		var width_scale: float = lerp(0.72, 1.0, (1.0 - cos(angle)) * 0.5)
		var local_point := Vector2(sin(angle) * radius.x * width_scale, -cos(angle) * radius.y)
		points.append(center + local_point.rotated(rotation))
	canvas.draw_colored_polygon(points, color)


# Replica world-space per "wild_vegetables" (2026-09-19, richiesta utente — verdure selvatiche
# raccoglibili per microcella; TRE foglie invece di due, una più grande delle altre, dal
# 2026-09-19 — richiesta utente): STESSO principio di eggs sopra (nessuna icona Control dedicata
# da replicare, geometria disegnata direttamente qui) — TRE foglie ellittiche allungate che si
# aprono a ventaglio da una base comune + un piccolo stelo/radice, invece di un frutto rotondo:
# la foglia centrale è più grande e punta dritta verso l'alto (rot=0), le due laterali sono più
# piccole e simmetriche, stesso principio "una dominante, le altre di contorno" già usato per gli
# eggs (2 gusci d'ombra + 1 pieno). Stessa forma (ellisse semplice, nessuna asimmetria come
# l'uovo) sia qui sia nella mesh a terra (vedi _get_grass_patch_multimesh più sotto in questo
# file, che riusa DIRETTAMENTE questo stesso Array), per coerenza visiva tra i due punti di
# rendering di questa risorsa.
const DEPOSIT_STORAGE_WILD_VEGETABLES_COLOR_LEAF_MAIN := Color(0.42, 0.62, 0.22, 1.0)
const DEPOSIT_STORAGE_WILD_VEGETABLES_COLOR_LEAF_DARK := Color(0.30, 0.48, 0.16, 1.0)
const DEPOSIT_STORAGE_WILD_VEGETABLES_COLOR_STEM := Color(0.55, 0.42, 0.20, 1.0)
const DEPOSIT_STORAGE_WILD_VEGETABLES_ELLIPSE_SEGMENTS: int = 12
const DEPOSIT_STORAGE_WILD_VEGETABLES_LEAVES := [
	{"cx": 0.32, "cy": 0.46, "rx": 0.13, "ry": 0.22, "rot": -0.65, "color": DEPOSIT_STORAGE_WILD_VEGETABLES_COLOR_LEAF_DARK},
	{"cx": 0.50, "cy": 0.34, "rx": 0.19, "ry": 0.32, "rot": 0.0, "color": DEPOSIT_STORAGE_WILD_VEGETABLES_COLOR_LEAF_MAIN},
	{"cx": 0.68, "cy": 0.46, "rx": 0.13, "ry": 0.22, "rot": 0.65, "color": DEPOSIT_STORAGE_WILD_VEGETABLES_COLOR_LEAF_DARK},
]

static func _draw_deposit_storage_wild_vegetables_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	var stem_base: Vector2 = top_left + Vector2(0.5, 0.68) * side
	var stem_top: Vector2 = top_left + Vector2(0.5, 0.5) * side
	canvas.draw_line(stem_base, stem_top, DEPOSIT_STORAGE_WILD_VEGETABLES_COLOR_STEM, side * 0.05, true)
	for leaf in DEPOSIT_STORAGE_WILD_VEGETABLES_LEAVES:
		_draw_deposit_storage_wild_vegetables_leaf(canvas,
			top_left, side, leaf["cx"], leaf["cy"], leaf["rx"], leaf["ry"], leaf["rot"], leaf["color"]
		)


static func _draw_deposit_storage_wild_vegetables_leaf(canvas: CanvasItem,
	top_left: Vector2, side: float, cx: float, cy: float, rx: float, ry: float, rotation: float, color: Color
) -> void:
	var center: Vector2 = top_left + Vector2(cx, cy) * side
	var radius := Vector2(rx * side, ry * side)
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_WILD_VEGETABLES_ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(DEPOSIT_STORAGE_WILD_VEGETABLES_ELLIPSE_SEGMENTS)
		var local_point := Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		points.append(center + local_point.rotated(rotation))
	canvas.draw_colored_polygon(points, color)


# Replica world-space per "medicinal_herbs" (2026-09-19, richiesta utente — icona nel deposito,
# altrimenti cadeva nel pallino di fallback di _draw_deposit_site_storage_grid): un piccolo stelo
# con due paia di foglioline ovali basse e larghe (verde-azzurro, DIVERSO dal verde-giallo di
# wild_vegetables) e un fiorellino viola in cima — il fiore è ciò che le distingue a colpo d'occhio
# da una verdura commestibile. Stesso principio di wild_vegetables sopra: nessuna icona Control da
# replicare, geometria disegnata direttamente qui; la STESSA lista DEPOSIT_STORAGE_MEDICINAL_HERBS_
# LEAVES è la fonte di verità anche per il marker a terra (vedi GRASS_PATCH_MARKER_SHAPES). Le
# ellissi passano da _draw_deposit_storage_wild_vegetables_leaf, che è di fatto un disegna-ellisse
# generico (cos/sin + rotazione, nessuna specificità verdura) — nessuna copia.
const DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_LEAF_MAIN := Color(0.35, 0.58, 0.42, 1.0)
const DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_LEAF_DARK := Color(0.24, 0.44, 0.32, 1.0)
const DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_FLOWER := Color(0.62, 0.42, 0.75, 1.0)
const DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_STEM := Color(0.35, 0.45, 0.25, 1.0)
const DEPOSIT_STORAGE_MEDICINAL_HERBS_LEAVES := [
	{"cx": 0.34, "cy": 0.58, "rx": 0.15, "ry": 0.08, "rot": -0.5, "color": DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_LEAF_DARK},
	{"cx": 0.66, "cy": 0.58, "rx": 0.15, "ry": 0.08, "rot": 0.5, "color": DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_LEAF_DARK},
	{"cx": 0.38, "cy": 0.42, "rx": 0.13, "ry": 0.07, "rot": -0.4, "color": DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_LEAF_MAIN},
	{"cx": 0.62, "cy": 0.42, "rx": 0.13, "ry": 0.07, "rot": 0.4, "color": DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_LEAF_MAIN},
	{"cx": 0.50, "cy": 0.24, "rx": 0.09, "ry": 0.09, "rot": 0.0, "color": DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_FLOWER},
]

static func _draw_deposit_storage_medicinal_herbs_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	var stem_base: Vector2 = top_left + Vector2(0.5, 0.75) * side
	var stem_top: Vector2 = top_left + Vector2(0.5, 0.3) * side
	canvas.draw_line(stem_base, stem_top, DEPOSIT_STORAGE_MEDICINAL_HERBS_COLOR_STEM, side * 0.05, true)
	for leaf in DEPOSIT_STORAGE_MEDICINAL_HERBS_LEAVES:
		_draw_deposit_storage_wild_vegetables_leaf(canvas,
			top_left, side, leaf["cx"], leaf["cy"], leaf["rx"], leaf["ry"], leaf["rot"], leaf["color"]
		)


# Corda di fibre (2026-09-23, richiesta utente — prima era il pallino giallo di fallback): un rotolo a
# spirale (2,5 giri, raggio crescente dal centro) color canapa con un capo libero verso l'angolo in
# basso a destra. Ogni tratto è disegnato due volte — prima più spesso e scuro, poi più sottile e
# chiaro — così il cordone ha un bordo e le spire restano distinguibili anche a questa scala.
const DEPOSIT_STORAGE_FIBER_ROPE_COLOR := Color(0.78, 0.64, 0.40, 1.0)
const DEPOSIT_STORAGE_FIBER_ROPE_OUTLINE_COLOR := Color(0.42, 0.31, 0.16, 1.0)
const DEPOSIT_STORAGE_FIBER_ROPE_TURNS: float = 2.5
const DEPOSIT_STORAGE_FIBER_ROPE_SEGMENTS: int = 40

# Primi attrezzi (2026-09-24, richiesta utente) — stessa geometria delle icone del pannello
# (WoodenSpearIcon/StoneKnifeIcon.draw_into), un solo disegno per entrambi i punti.
static func _draw_deposit_storage_wooden_spear_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	WoodenSpearIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_stone_knife_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	StoneKnifeIcon.draw_into(canvas, top_left, Vector2(side, side))


# Punteruolo d'osso (2026-09-27): stessa geometria dell'icona del pannello (BoneAwlIcon.draw_into).
static func _draw_deposit_storage_bone_awl_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	BoneAwlIcon.draw_into(canvas, top_left, Vector2(side, side))


# Sacca di pelle (2026-09-27): stessa geometria dell'icona del pannello (HideBagIcon.draw_into).
static func _draw_deposit_storage_hide_bag_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	HideBagIcon.draw_into(canvas, top_left, Vector2(side, side))


# Lancia con punta di pietra (2026-10-04): stessa geometria dell'icona del pannello (StoneSpearIcon.draw_into); la usa
# anche il segnaposto dell'arma lanciata a terra (DroppedWeaponMarker).
static func _draw_deposit_storage_stone_spear_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	StoneSpearIcon.draw_into(canvas, top_left, Vector2(side, side))


# Accetta rudimentale (2026-10-04): stessa geometria dell'icona del pannello (StoneAxeIcon.draw_into).
static func _draw_deposit_storage_stone_axe_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	StoneAxeIcon.draw_into(canvas, top_left, Vector2(side, side))


# Arco e mazzo di frecce (2026-10-04): stessa geometria delle icone del pannello (BowIcon/ArrowBundleIcon.draw_into).
static func _draw_deposit_storage_bow_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	BowIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_arrow_bundle_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	ArrowBundleIcon.draw_into(canvas, top_left, Vector2(side, side))


# Sacca di pelle essiccata (2026-10-04): stessa geometria dell'icona del pannello (DriedHideBagIcon.draw_into).
static func _draw_deposit_storage_dried_hide_bag_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	DriedHideBagIcon.draw_into(canvas, top_left, Vector2(side, side))


# Prodotti della macellazione (2026-09-26, icone provvisorie): stessa geometria delle icone del pannello
# (MeatIcon/HideIcon/SinewIcon/BoneIcon.draw_into), un solo disegno per entrambi i punti.
static func _draw_deposit_storage_meat_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	MeatIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_cooked_meat_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	CookedMeatIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_hide_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	HideIcon.draw_into(canvas, top_left, Vector2(side, side))


# Prodotti dell'essiccazione (2026-10-03, icone provvisorie): stessa geometria delle icone del pannello
# (DriedMeatIcon/DriedHideIcon.draw_into).
static func _draw_deposit_storage_dried_meat_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	DriedMeatIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_dried_hide_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	DriedHideIcon.draw_into(canvas, top_left, Vector2(side, side))


# Prodotti dell'affumicatoio (2026-10-03, icone provvisorie): stessa geometria delle icone del pannello
# (SmokedMeatIcon/SmokedHideIcon.draw_into).
static func _draw_deposit_storage_smoked_meat_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	SmokedMeatIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_smoked_hide_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	SmokedHideIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_sinew_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	SinewIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_bone_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	BoneIcon.draw_into(canvas, top_left, Vector2(side, side))


static func _draw_deposit_storage_fiber_rope_icon(canvas: CanvasItem, top_left: Vector2, side: float) -> void:
	var center: Vector2 = top_left + Vector2(0.46, 0.46) * side
	var points := PackedVector2Array()
	for i in range(DEPOSIT_STORAGE_FIBER_ROPE_SEGMENTS + 1):
		var t: float = float(i) / float(DEPOSIT_STORAGE_FIBER_ROPE_SEGMENTS)
		var angle: float = t * TAU * DEPOSIT_STORAGE_FIBER_ROPE_TURNS
		var radius: float = side * (0.05 + 0.28 * t)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	# Capo libero: dall'ultima spira verso l'angolo in basso a destra.
	points.append(top_left + Vector2(0.88, 0.88) * side)
	canvas.draw_polyline(points, DEPOSIT_STORAGE_FIBER_ROPE_OUTLINE_COLOR, side * 0.13, true)
	canvas.draw_polyline(points, DEPOSIT_STORAGE_FIBER_ROPE_COLOR, side * 0.08, true)
