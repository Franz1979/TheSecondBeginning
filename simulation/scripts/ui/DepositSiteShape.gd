class_name DepositSiteShape
extends RefCounted

# Sagoma del Deposit Site (2026-09-19, richiesta utente — "smussa leggermente gli angoli, smussati
# diversamente in modo casuale"; poi "in una modifica precedente si sono persi i lati irregolari,
# più adatti al Paleolitico: rimettili mantenendo gli smussi"): UN SOLO punto che costruisce il
# poligono, condiviso da MicroCellRenderer (edificio piazzato), BuildingGhost (anteprima) e
# DepositSiteIcon (icona in BuildBar).
#
# Quadrato centrato in (0,0) di semilato `half_side` con:
#   - 4 angoli arrotondati da archi di raggio DIVERSO per angolo (frazione di half_side pescata da
#     un RandomNumberGenerator a seed fisso);
#   - 4 lati IRREGOLARI: SIDE_POINT_COUNT punti intermedi per lato, spostati perpendicolarmente al
#     lato (per lo più verso l'interno, poco verso l'esterno) e sfalsati lungo il lato, dallo stesso
#     generatore — niente più segmento retto, ma un profilo "scavato a mano".
# Seed fisso: la sagoma è identica ad ogni chiamata, quindi l'anteprima coincide con l'edificio
# piazzato e con l'icona. Frazioni di half_side, non pixel: la stessa forma scala dall'edificio
# (semilato 4.5) all'icona (semilato ~14).
#
# CACHE (2026-09-19, richiesta utente — "metti in cache il poligono invece di ricalcolarlo a ogni
# _draw"): get_polygon/get_closed_outline calcolano la sagoma UNA volta per half_side e poi
# restituiscono la copia in cache (PackedVector2Array è copy-on-write: nessuna copia reale). Il
# renderer e l'anteprima usano solo half_side=DEPOSIT_SITE_HALF_SIDE, quindi la cache ha una voce;
# build_polygon resta pubblico per chi non vuole la cache (l'icona, che si ridisegna solo al
# resize e ha un half_side variabile).

const SHAPE_SEED: int = 0
# 0.08..0.36 di half_side (a semilato 4.5: circa 0.4..1.6 px) — "leggermente" smussati: nessun
# angolo diventa un cerchio, ma la differenza tra il più netto e il più tondo resta visibile.
const CORNER_RADIUS_MIN_RATIO: float = 0.08
const CORNER_RADIUS_MAX_RATIO: float = 0.36
const ARC_SEGMENTS: int = 4

# Lati irregolari: punti intermedi per lato, spostamento perpendicolare in frazione di half_side
# (negativo = verso l'interno; l'esterno è tenuto molto piccolo così la sagoma resta dentro la
# microcella: semilato 4.5 + 0.05*4.5 < 5) e sfalsamento lungo il lato in frazione della
# lunghezza del tratto rettilineo tra i due archi.
const SIDE_POINT_COUNT: int = 3
const SIDE_OFFSET_INWARD_MAX_RATIO: float = 0.10
const SIDE_OFFSET_OUTWARD_MAX_RATIO: float = 0.05
const SIDE_ALONG_JITTER_RATIO: float = 0.06

# Colori dell'edificio piazzato (STESSI valori di MicroCellRenderer.DEPOSIT_SITE_COLOR/
# DEPOSIT_SITE_OUTLINE_COLOR) — usati dall'icona, così bordo e riempimento coincidono col rendering.
const FILL_COLOR := Color(0.58, 0.48, 0.34, 1.0)
const OUTLINE_COLOR := Color(0.24, 0.18, 0.12, 1.0)

static var _polygon_cache: Dictionary = {}
static var _outline_cache: Dictionary = {}


# Poligono chiuso implicitamente (ultimo vertice != primo), in senso orario sullo schermo (y verso
# il basso): adatto a draw_colored_polygon e, con il primo vertice riaggiunto in coda, a
# draw_polyline per il bordo.
static func build_polygon(half_side: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SHAPE_SEED
	# Angolo alto-destra, basso-destra, basso-sinistra, alto-sinistra: (segno x, segno y, angolo di
	# partenza dell'arco).
	var corner_signs: Array[Vector2] = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	var corner_start_angles: Array[float] = [-PI / 2.0, 0.0, PI / 2.0, PI]
	# Prima gli archi dei 4 angoli (ciascuno: ARC_SEGMENTS+1 punti), poi i punti intermedi dei 4 lati
	# tra la fine di un arco e l'inizio del successivo.
	var arcs: Array[PackedVector2Array] = []
	for corner in range(4):
		var radius: float = half_side * rng.randf_range(CORNER_RADIUS_MIN_RATIO, CORNER_RADIUS_MAX_RATIO)
		var arc_center: Vector2 = corner_signs[corner] * (half_side - radius)
		var arc := PackedVector2Array()
		for step in range(ARC_SEGMENTS + 1):
			var angle: float = corner_start_angles[corner] + (PI / 2.0) * float(step) / float(ARC_SEGMENTS)
			arc.append(arc_center + Vector2(cos(angle), sin(angle)) * radius)
		arcs.append(arc)

	var points := PackedVector2Array()
	for corner in range(4):
		points.append_array(arcs[corner])
		# Lato tra l'ultimo punto di questo arco e il primo del prossimo.
		var side_start: Vector2 = arcs[corner][arcs[corner].size() - 1]
		var side_end: Vector2 = arcs[(corner + 1) % 4][0]
		var side_vector: Vector2 = side_end - side_start
		var side_length: float = side_vector.length()
		if side_length <= 0.0001:
			continue
		var side_direction: Vector2 = side_vector / side_length
		# Normale verso l'esterno per un percorso orario con y verso il basso.
		var outward: Vector2 = Vector2(side_direction.y, -side_direction.x)
		for i in range(SIDE_POINT_COUNT):
			var t: float = (float(i) + 1.0) / float(SIDE_POINT_COUNT + 1)
			t += rng.randf_range(-SIDE_ALONG_JITTER_RATIO, SIDE_ALONG_JITTER_RATIO)
			var offset: float = half_side * rng.randf_range(-SIDE_OFFSET_INWARD_MAX_RATIO, SIDE_OFFSET_OUTWARD_MAX_RATIO)
			points.append(side_start + side_direction * (side_length * t) + outward * offset)
	return points


# Versione in cache di build_polygon.
static func get_polygon(half_side: float) -> PackedVector2Array:
	if not _polygon_cache.has(half_side):
		_polygon_cache[half_side] = build_polygon(half_side)
	return _polygon_cache[half_side]


# Polygon + primo vertice in coda (per draw_polyline chiusa), in cache anch'essa.
static func get_closed_outline(half_side: float) -> PackedVector2Array:
	if not _outline_cache.has(half_side):
		var outline := get_polygon(half_side).duplicate()
		outline.append(outline[0])
		_outline_cache[half_side] = outline
	return _outline_cache[half_side]
