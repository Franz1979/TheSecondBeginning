class_name LinearShape
extends RefCounted

# Disegno comune degli edifici LINEARI (2026-10-04, richiesta utente — estratto dal vallo difensivo, EarthworkShape, per
# futuri edifici lineari come mura o strade). Un edificio lineare è fatto di pezzi da una microcella (BuildingRules.
# is_linear) che si collegano ai vicini dello stesso gruppo (BuildingRules.linear_link_group) solo sui quattro lati; la
# maschera dei vicini la calcola GameScene (_linear_shape_at). Lo stile (larghezza, colori, ciglio) arriva da chi chiama
# (LinearShapeStyle); questa classe non sa di quale edificio si tratta.
#
# Forma di un pezzo, da `neighbor_mask` (bit 1 << lato, lati N, E, S, W = 0..3, stesso ordine della maschera della terra
# battuta):
#   - isolato: solo il centro (un disco del raggio della larghezza);
#   - un vicino: terminale (centro più un braccio); due opposti: dritto; tre o quattro: T o croce — un braccio largo
#     quanto il centro verso ogni vicino, fino al bordo della microcella, dove incontra quello del pezzo accanto;
#   - ANGOLO (due vicini su lati adiacenti): un unico tratto spesso dal punto medio di un lato collegato al punto medio
#     dell'altro, con le estremità arrotondate (capsula, Geometry2D.offset_polyline con END_ROUND); il ciglio segue lo
#     stesso tratto. Raccordi al bordo, lato per lato:
#       - verso un altro pezzo ad angolo (`clip_mask`, calcolata da chi chiama): la capsula si taglia sul bordo; due
#         angoli consecutivi a scaletta stanno sulla stessa diagonale, quindi le metà si ricompongono in una diagonale
#         continua, senza gradini né rigonfiamenti;
#       - verso un pezzo non ad angolo: la capsula non si taglia e il suo capo arrotondato sporge di poco sopra il braccio
#         dritto del vicino (stesso colore): raccordo arrotondato. Il capo coprirebbe l'inizio del ciglio del vicino, che
#         lì è sempre una linea dritta dal punto medio verso il suo centro: viene ridisegnato qui (moncone di ciglio).
#     Un angolo isolato (due vicini non ad angolo) risulta una curva smussata.
# Ciglio (opzionale, style.crest_width > 0): una linea scura lungo l'asse di ogni braccio, unita al centro; un pezzo
# isolato ha solo un punto (style.crest_dot_radius).
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10); `scale` per le icone.

const HALF_CELL: float = 5.0
# Taglio "infinito" per i lati della capsula che non vanno tagliati.
const CLIP_FAR: float = 100.0
const SIDE_DIRECTIONS: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
# Lati di un tratto dritto orizzontale (E | W): l'aspetto tipico di un'icona.
const STRAIGHT_MASK: int = (1 << 1) | (1 << 3)

# Poligoni delle capsule degli angoli in unità della mappa centrate su (0,0), per "mask:clip:raggio": calcolati una volta.
static var _corner_polygon_cache: Dictionary = {}


# true se `neighbor_mask` ha esattamente due lati e sono adiacenti (non opposti): un pezzo ad angolo.
static func is_corner_mask(neighbor_mask: int) -> bool:
	return neighbor_mask in [0b0011, 0b0110, 0b1100, 0b1001]


# `invalid` = anteprima su una posizione non edificabile (tinta style.invalid_tint); `alpha` per l'anteprima
# semitrasparente; `clip_mask` = lati (tra quelli di `neighbor_mask`) il cui vicino è a sua volta un angolo.
static func draw(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, style: LinearShapeStyle, invalid: bool = false,
	alpha: float = 1.0, scale: float = 1.0, clip_mask: int = 0
) -> void:
	var tint := func(color: Color) -> Color:
		var base: Color = style.invalid_tint if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)
	var body: Color = tint.call(style.body_color)
	var crest: Color = tint.call(style.crest_color)
	var has_crest: bool = style.crest_width > 0.0
	if is_corner_mask(neighbor_mask):
		_draw_corner(canvas, center, neighbor_mask, clip_mask & neighbor_mask, style, body, crest, has_crest, scale)
		return
	var radius: float = style.half_width * scale
	# Corpo: bracci (rettangoli dal centro al bordo, larghi quanto il centro) e centro, nello stesso colore.
	for side in range(4):
		if (neighbor_mask & (1 << side)) == 0:
			continue
		var direction: Vector2 = SIDE_DIRECTIONS[side]
		var across := Vector2(-direction.y, direction.x) * radius
		var tip: Vector2 = center + direction * HALF_CELL * scale
		canvas.draw_colored_polygon(PackedVector2Array([center + across, tip + across, tip - across, center - across]), body)
	canvas.draw_circle(center, radius, body)
	if not has_crest:
		return
	# Ciglio: una linea dal centro al bordo lungo ogni braccio, unita al centro da un punto dello stesso spessore (un pezzo
	# isolato ha solo il punto, di raggio style.crest_dot_radius).
	var has_arm := false
	for side in range(4):
		if (neighbor_mask & (1 << side)) == 0:
			continue
		has_arm = true
		canvas.draw_line(center, center + SIDE_DIRECTIONS[side] * HALF_CELL * scale, crest, style.crest_width * scale)
	canvas.draw_circle(center, (style.crest_width * 0.5 if has_arm else style.crest_dot_radius) * scale, crest)


# Fondo sotto un pezzo lineare (2026-10-04, richiesta utente): una striscia di colore `color` che segue lo stesso
# tracciato del pezzo (centro, bracci, angoli smussati, diagonali, estremità), larga style.ground_half_width per parte
# (0 = nessun fondo), più la metà di microcella verso ogni lato di `fill_mask` (un vicino con il proprio fondo, edificio
# o terra battuta, ma non un pezzo dello stesso gruppo): i due fondi si saldano al bordo, senza erba in mezzo.
# Angoli: stessa capsula del corpo con la larghezza della striscia; verso un vicino ad angolo si taglia sul bordo come il
# corpo. Verso un vicino non ad angolo il raccordo interno della curva cade per forza nella microcella accanto, quindi la
# striscia sporge lì, ma SOLO fuori dalla fascia larga quanto il corpo attorno all'asse del braccio del vicino: quella
# fascia è comunque coperta dal fondo del vicino (stesso colore), e così la sporgenza non copre mai il suo argine né il
# suo ciglio, nemmeno quando il vicino sta in un'altra macrocella e la sua cella viene disegnata prima di questa.
static func draw_ground(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, clip_mask: int, fill_mask: int, style: LinearShapeStyle,
	color: Color, scale: float = 1.0
) -> void:
	var half_width: float = style.ground_half_width
	if half_width <= 0.0:
		return
	var radius: float = half_width * scale
	if is_corner_mask(neighbor_mask):
		for polygon in _corner_ground_polygons(neighbor_mask, clip_mask & neighbor_mask, half_width, style.half_width):
			canvas.draw_colored_polygon(_placed(polygon, center, scale), color)
	else:
		for side in range(4):
			if (neighbor_mask & (1 << side)) == 0:
				continue
			var direction: Vector2 = SIDE_DIRECTIONS[side]
			var across := Vector2(-direction.y, direction.x) * radius
			var tip: Vector2 = center + direction * HALF_CELL * scale
			canvas.draw_colored_polygon(PackedVector2Array([center + across, tip + across, tip - across, center - across]), color)
		canvas.draw_circle(center, radius, color)
	# Metà microcella verso i vicini con il proprio fondo.
	var half_cell: float = HALF_CELL * scale
	# Angolo con un vicino con fondo (2026-10-04, bugfix — tacca d'erba): la metà di cella da sola lasciava un'insenatura
	# d'erba tra il tratto diagonale e il riempimento. I lati con fondo di un angolo stanno sempre dal lato interno della
	# curva (quelli esterni sono i due collegati): si riempie tutto il lato interno, dalla linea che unisce i due punti
	# medi collegati fino ai bordi opposti — fondo continuo dalla striscia al vicino, senza fessure agli spigoli.
	if is_corner_mask(neighbor_mask) and fill_mask != 0:
		canvas.draw_colored_polygon(_placed(_corner_inner_polygon(neighbor_mask), center, scale), color)
	for side in range(4):
		if (fill_mask & (1 << side)) == 0:
			continue
		var direction: Vector2 = SIDE_DIRECTIONS[side]
		var across := Vector2(-direction.y, direction.x) * half_cell
		var edge: Vector2 = center + direction * half_cell
		canvas.draw_colored_polygon(PackedVector2Array([center + across, edge + across, edge - across, center - across]), color)


static func _draw_corner(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, clip_mask: int, style: LinearShapeStyle,
	body: Color, crest: Color, has_crest: bool, scale: float
) -> void:
	for polygon in _corner_polygons(neighbor_mask, clip_mask, style.half_width):
		canvas.draw_colored_polygon(_placed(polygon, center, scale), body)
	if not has_crest:
		return
	for polygon in _corner_polygons(neighbor_mask, clip_mask, style.crest_width * 0.5):
		canvas.draw_colored_polygon(_placed(polygon, center, scale), crest)
	# Moncone del ciglio del vicino non ad angolo, coperto dal capo arrotondato che sporge (vedi testa del file): poco più
	# lungo di quanto sporge il capo.
	var stub_length: float = style.half_width + 0.3
	for side in range(4):
		if (neighbor_mask & (1 << side)) == 0 or (clip_mask & (1 << side)) != 0:
			continue
		var edge_mid: Vector2 = SIDE_DIRECTIONS[side] * HALF_CELL
		canvas.draw_line(
			center + edge_mid * scale, center + (edge_mid + SIDE_DIRECTIONS[side] * stub_length) * scale,
			crest, style.crest_width * scale
		)


# Capsula dal punto medio di un lato collegato al punto medio dell'altro, di raggio `radius`, tagliata sui lati di
# `clip_mask` al bordo della microcella. In unità della mappa centrate su (0,0), dalla cache.
static func _corner_polygons(neighbor_mask: int, clip_mask: int, radius: float) -> Array:
	var key := "%d:%d:%s" % [neighbor_mask, clip_mask, str(radius)]
	if _corner_polygon_cache.has(key):
		return _corner_polygon_cache[key]
	var ends: Array[Vector2] = []
	for side in range(4):
		if (neighbor_mask & (1 << side)) != 0:
			ends.append(SIDE_DIRECTIONS[side] * HALF_CELL)
	var capsules: Array = Geometry2D.offset_polyline(
		PackedVector2Array(ends), radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND
	)
	# Rettangolo di taglio: al bordo della microcella sui lati da tagliare, lontanissimo sugli altri.
	var top: float = -HALF_CELL if (clip_mask & (1 << 0)) != 0 else -CLIP_FAR
	var right: float = HALF_CELL if (clip_mask & (1 << 1)) != 0 else CLIP_FAR
	var bottom: float = HALF_CELL if (clip_mask & (1 << 2)) != 0 else CLIP_FAR
	var left: float = -HALF_CELL if (clip_mask & (1 << 3)) != 0 else -CLIP_FAR
	var clip_rect := PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)])
	var result: Array = []
	for capsule in capsules:
		for clipped in Geometry2D.intersect_polygons(capsule, clip_rect):
			result.append(clipped)
	_corner_polygon_cache[key] = result
	return result


# Fondo di un angolo (vedi draw_ground): capsula di raggio `ground_half_width` tagliata alla microcella, più le parti che
# sporgono verso i vicini non ad angolo fuori dalla fascia |offset lungo il bordo| < `body_half_width`. In unità della
# mappa centrate su (0,0), dalla cache.
static func _corner_ground_polygons(neighbor_mask: int, clip_mask: int, ground_half_width: float, body_half_width: float) -> Array:
	var key := "ground:%d:%d:%s:%s" % [neighbor_mask, clip_mask, str(ground_half_width), str(body_half_width)]
	if _corner_polygon_cache.has(key):
		return _corner_polygon_cache[key]
	var ends: Array[Vector2] = []
	for side in range(4):
		if (neighbor_mask & (1 << side)) != 0:
			ends.append(SIDE_DIRECTIONS[side] * HALF_CELL)
	var capsules: Array = Geometry2D.offset_polyline(
		PackedVector2Array(ends), ground_half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND
	)
	var regions: Array[PackedVector2Array] = [PackedVector2Array([
		Vector2(-HALF_CELL, -HALF_CELL), Vector2(HALF_CELL, -HALF_CELL), Vector2(HALF_CELL, HALF_CELL), Vector2(-HALF_CELL, HALF_CELL),
	])]
	for side in range(4):
		if (neighbor_mask & (1 << side)) == 0 or (clip_mask & (1 << side)) != 0:
			continue
		var direction: Vector2 = SIDE_DIRECTIONS[side]
		var along := Vector2(-direction.y, direction.x)
		var edge: Vector2 = direction * HALF_CELL
		for side_sign in [1.0, -1.0]:
			var near: Vector2 = edge + along * body_half_width * side_sign
			var far: Vector2 = edge + along * HALF_CELL * side_sign
			regions.append(PackedVector2Array([near, far, far + direction * HALF_CELL, near + direction * HALF_CELL]))
	var result: Array = []
	for capsule in capsules:
		for region in regions:
			for clipped in Geometry2D.intersect_polygons(capsule, region):
				result.append(clipped)
	_corner_polygon_cache[key] = result
	return result


# Lato interno di un angolo: la microcella senza il triangolo esterno (lo spigolo tra i due lati collegati), cioè il
# pentagono che parte dal punto medio di un lato collegato, passa per quello dell'altro e gira lungo i bordi restanti.
static func _corner_inner_polygon(neighbor_mask: int) -> PackedVector2Array:
	var corners: Array[Vector2] = [
		Vector2(-HALF_CELL, -HALF_CELL), Vector2(HALF_CELL, -HALF_CELL), Vector2(HALF_CELL, HALF_CELL), Vector2(-HALF_CELL, HALF_CELL),
	]
	var outer := Vector2.ZERO
	for side in range(4):
		if (neighbor_mask & (1 << side)) != 0:
			outer += SIDE_DIRECTIONS[side] * HALF_CELL
	var polygon := PackedVector2Array()
	for i in range(4):
		if corners[i].is_equal_approx(outer):
			polygon.append((corners[(i + 3) % 4] + corners[i]) * 0.5)
			polygon.append((corners[i] + corners[(i + 1) % 4]) * 0.5)
		else:
			polygon.append(corners[i])
	return polygon


static func _placed(polygon: PackedVector2Array, center: Vector2, scale: float) -> PackedVector2Array:
	var placed := PackedVector2Array()
	for point in polygon:
		placed.append(center + point * scale)
	return placed
