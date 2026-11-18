class_name DepositSite3D
extends RefCounted

# Oggetto 3D: i siti di deposito finiti di UNA macrocella. Per ora solo lo spiazzo, senza i mucchi: una chiazza di terra
# battuta proiettata sul terreno (Decal), con la stessa sagoma del 2D (DepositSiteShape: quadrato coi lati irregolari e
# gli angoli smussati, lato MicroCellRenderer.DEPOSIT_SITE_HALF_SIDE) e lo stesso colore, più grana, qualche segno di
# passaggio e un bordo che sfuma nel prato. Ai quattro angoli un paletto appuntito che segna lo spiazzo (richiesta utente).

# Margine attorno alla sagoma (px del 2D) per la sfumatura del bordo.
const MARGIN_PX := 2.0
const TEXTURE_SIZE := 128
# Larghezza della sfumatura del bordo (px del 2D) e quanto il rumore la muove.
const EDGE_FADE_PX := 0.9
const EDGE_NOISE_PX := 0.6
const DECAL_HEIGHT := 0.8
# Gli altri oggetti (rocce, alberi…) stanno sul livello 1 come il terreno, ma in un deposito non ce ne sono.
const TERRAIN_LAYERS := 1

# Paletti agli angoli: alti circa un metro (1 microcella = 10 m), un po' dentro gli angoli smussati della sagoma.
const STAKE_HEIGHT := 0.12
const STAKE_RADIUS := 0.012
const STAKE_SIDES := 6
const STAKE_INSET := 0.06
const STAKE_COLOR := Color("6b5232")
const STAKE_SINK := 0.015

static var _texture: ImageTexture
static var _stake_mesh: ArrayMesh


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non ci sono depositi.
static func build(snapshot: BuildingPlacesSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.size() == 0:
		return null
	var node := Node3D.new()
	node.name = "DepositSites"
	var side := _texture_side_px() / float(MicroCellRenderer.CELL_SIZE)
	var corner := MicroCellRenderer.DEPOSIT_SITE_HALF_SIDE / float(MicroCellRenderer.CELL_SIZE) - STAKE_INSET
	var stake_transforms: Array = []
	for i in range(snapshot.size()):
		var center := snapshot.centers[i]
		var decal := Decal.new()
		decal.name = "DepositSite"
		decal.size = Vector3(side, DECAL_HEIGHT, side)
		decal.texture_albedo = _get_texture()
		decal.cull_mask = TERRAIN_LAYERS
		decal.position = Vector3(center.x, GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y), center.y)
		node.add_child(decal)
		var rng := RandomNumberGenerator.new()
		rng.seed = snapshot.seeds[i]
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var local: Vector2 = center + offset * corner
			var y := GroundHeight3D.land_height(base_global.x + local.x, base_global.y + local.y) - STAKE_SINK
			# Un po' storto e girato, ognuno a modo suo.
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
			basis = basis * Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08))
			var height := rng.randf_range(0.9, 1.1)
			stake_transforms.append(Transform3D(basis.scaled(Vector3(1.0, height, 1.0)), Vector3(local.x, y, local.y)))
	node.add_child(MultiMeshGroup3D.build("Stakes", [_get_stake_mesh()], [stake_transforms], material))
	return node


# Paletto: prisma a facce piatte un po' rastremato, con la punta.
static func _get_stake_mesh() -> ArrayMesh:
	if _stake_mesh != null:
		return _stake_mesh
	var builder := FlatMeshBuilder.new()
	var body_top := STAKE_HEIGHT * 0.82
	var tip := Vector3(0.0, STAKE_HEIGHT, 0.0)
	for k in range(STAKE_SIDES):
		var a0 := TAU * k / STAKE_SIDES
		var a1 := TAU * (k + 1) / STAKE_SIDES
		var b0 := Vector3(cos(a0), 0.0, sin(a0)) * STAKE_RADIUS
		var b1 := Vector3(cos(a1), 0.0, sin(a1)) * STAKE_RADIUS
		var t0 := Vector3(cos(a0) * STAKE_RADIUS * 0.85, body_top, sin(a0) * STAKE_RADIUS * 0.85)
		var t1 := Vector3(cos(a1) * STAKE_RADIUS * 0.85, body_top, sin(a1) * STAKE_RADIUS * 0.85)
		var shade := 0.85 + 0.15 * float(k % 2)
		var color := Color(STAKE_COLOR.r * shade, STAKE_COLOR.g * shade, STAKE_COLOR.b * shade)
		# Senso orario visto da fuori (FlatMeshBuilder).
		builder.add_quad(b1, t1, t0, b0, color)
		builder.add_triangle(t1, tip, t0, color.lightened(0.15))
	_stake_mesh = builder.build()
	return _stake_mesh


static func _texture_side_px() -> float:
	return (MicroCellRenderer.DEPOSIT_SITE_HALF_SIDE + MARGIN_PX) * 2.0


# Una sola texture per tutti i depositi (la sagoma del 2D è fissa): colore del 2D con grana, segni di passaggio e bordo
# sfumato e mosso.
static func _get_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var polygon := DepositSiteShape.get_polygon(MicroCellRenderer.DEPOSIT_SITE_HALF_SIDE)
	var base_color: Color = MicroCellRenderer.DEPOSIT_SITE_COLOR
	var edge_noise := FastNoiseLite.new()
	edge_noise.seed = 5151
	edge_noise.frequency = 0.06
	var grain_noise := FastNoiseLite.new()
	grain_noise.seed = 5152
	grain_noise.frequency = 0.35
	var rng := RandomNumberGenerator.new()
	rng.seed = 5153
	var size := TEXTURE_SIZE
	var side_px := _texture_side_px()
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			# Punto in px del 2D, centro della sagoma in (0, 0).
			var p := (Vector2(x + 0.5, y + 0.5) / size - Vector2(0.5, 0.5)) * side_px
			var distance := _signed_distance(p, polygon) + edge_noise.get_noise_2d(x, y) * EDGE_NOISE_PX
			var alpha := 1.0 - smoothstep(-EDGE_FADE_PX, EDGE_FADE_PX * 0.5, distance)
			if alpha <= 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var grain := grain_noise.get_noise_2d(x, y) * 0.07 + rng.randf_range(-0.035, 0.035)
			var color := Color(base_color.r + grain, base_color.g + grain * 0.9, base_color.b + grain * 0.7)
			# Bordo un po' più scuro (terra smossa) prima della sfumatura.
			color = color.darkened(0.12 * smoothstep(-EDGE_FADE_PX * 2.5, 0.0, distance))
			color.a = alpha * 0.95
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture


# Distanza dal bordo della sagoma: negativa dentro, positiva fuori.
static func _signed_distance(p: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		best = minf(best, p.distance_to(closest))
	return -best if Geometry2D.is_point_in_polygon(p, polygon) else best
