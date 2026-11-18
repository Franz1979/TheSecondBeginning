class_name DirtGround3D
extends RefCounted

# Oggetto 3D: le mattonelle dell'edificio "Terra battuta" di UNA macrocella (DirtGroundSnapshot3D), proiettate sul
# terreno (Decal), una per microcella come nel 2D. Deve leggersi come lavoro fatto, non come terra dove l'erba non
# cresce: colore chiaro e uniforme del 2D (DirtGroundPattern: colore base e macchie), superficie liscia, bordo netto
# con un orlo sottile più scuro di terra pressata.
# Lati verso un'altra terra battuta o un edificio (dirt_neighbors): dritti e pieni fino al bordo della microcella,
# così le mattonelle unite fanno un'area sola senza giunture. Lati verso il prato: irregolari, appena fuori dalla
# microcella, con l'orlo.
# Una texture per combinazione (lati uniti, variante delle macchie), fatta la prima volta che serve.

const SIDE_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
# Quanto la texture va oltre la microcella (per lato, in microcelle): spazio per il bordo irregolare.
const MARGIN := 0.18
const TEXTURE_SIZE := 96
# Bordo libero: quanto esce dalla microcella (in microcelle) e quanto il rumore lo muove.
const EDGE_OUT := 0.05
const EDGE_JAG := 0.06
const EDGE_FADE := 0.025
# Orlo pressato: larghezza e quanto è più scuro.
const RIM_WIDTH := 0.05
const RIM_DARKEN := 0.22
# Le macchie del 2D stanno lontane dal bordo irregolare.
const SPECKLE_MARGIN := 0.06
const DECAL_HEIGHT := 0.8
const TERRAIN_LAYERS := 1

static var _textures: Dictionary = {}


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non ci sono mattonelle.
static func build(snapshot: DirtGroundSnapshot3D, base_global: Vector2) -> Node3D:
	if snapshot.size() == 0:
		return null
	var node := Node3D.new()
	node.name = "DirtGround"
	var side := 1.0 + MARGIN * 2.0
	for i in range(snapshot.size()):
		var pos := snapshot.positions[i]
		var center := Vector2(pos) + Vector2(0.5, 0.5)
		var variant := posmod(hash(pos), DirtGroundPattern.VARIANT_COUNT)
		var decal := Decal.new()
		decal.name = "Tile"
		decal.size = Vector3(side, DECAL_HEIGHT, side)
		decal.texture_albedo = _get_texture(snapshot.neighbor_masks[i], variant)
		decal.cull_mask = TERRAIN_LAYERS
		decal.position = Vector3(center.x, GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y), center.y)
		node.add_child(decal)
	return node


static func _get_texture(neighbor_mask: int, variant: int) -> ImageTexture:
	var key := neighbor_mask * 100 + variant
	if not _textures.has(key):
		_textures[key] = _build_texture(neighbor_mask, variant)
	return _textures[key]


static func _build_texture(neighbor_mask: int, variant: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 7070 + variant
	noise.frequency = 0.09
	var size := TEXTURE_SIZE
	var side := 1.0 + MARGIN * 2.0
	var speckles := DirtGroundPattern.speckles(variant, SPECKLE_MARGIN)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			# Punto nella microcella: (0, 0) in alto a sinistra (nord-ovest), (1, 1) in basso a destra.
			var p := (Vector2(x + 0.5, y + 0.5) / size) * side - Vector2(MARGIN, MARGIN)
			var distance := _edge_distance(p, neighbor_mask)
			if distance == INF:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Bordo libero spinto un po' fuori e mosso dal rumore; sui lati uniti _edge_distance non conta.
			var edge := distance - (EDGE_OUT + (noise.get_noise_2d(x, y) * 0.5 + 0.5) * EDGE_JAG)
			var alpha := 1.0 - smoothstep(-EDGE_FADE, EDGE_FADE, edge)
			if alpha <= 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var color := _speckle_color(p, speckles)
			color = color.darkened(RIM_DARKEN * (1.0 - smoothstep(-RIM_WIDTH, -RIM_WIDTH * 0.3, edge)) * float(edge > -RIM_WIDTH * 1.5))
			color.a = alpha
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# Distanza dal bordo dei soli lati liberi (negativa dentro la microcella, positiva fuori; angoli arrotondati). INF se il
# punto è oltre un lato unito: lì la mattonella finisce dritta, la continua quella accanto.
static func _edge_distance(p: Vector2, neighbor_mask: int) -> float:
	var outside := Vector2.ZERO
	var inside := -INF
	# Asse x: lato O (3) se a sinistra del centro, E (1) se a destra.
	var x_side := 3 if p.x < 0.5 else 1
	var x_out := absf(p.x - 0.5) - 0.5
	if neighbor_mask & (1 << x_side):
		if x_out > 0.0:
			return INF
		x_out = -1.0
	# Asse y: lato N (0) se sopra il centro, S (2) se sotto.
	var y_side := 0 if p.y < 0.5 else 2
	var y_out := absf(p.y - 0.5) - 0.5
	if neighbor_mask & (1 << y_side):
		if y_out > 0.0:
			return INF
		y_out = -1.0
	outside = Vector2(maxf(x_out, 0.0), maxf(y_out, 0.0))
	inside = minf(maxf(x_out, y_out), 0.0)
	return outside.length() + inside


# Colore del 2D nel punto: colore base, poi chiazze e puntini (DirtGroundPattern, spazio unitario della microcella).
static func _speckle_color(p: Vector2, speckles: Array[Dictionary]) -> Color:
	var color := DirtGroundPattern.BASE_COLOR
	for speckle in speckles:
		var d := p.distance_to(Vector2(speckle["x"], speckle["y"]))
		var r: float = speckle["r"]
		if d < r:
			color = color.lerp(speckle["color"], 1.0 - smoothstep(r * 0.7, r, d))
	return color
