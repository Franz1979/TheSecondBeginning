class_name DepositSite3D
extends RefCounted

# Oggetto 3D: i siti di deposito finiti di UNA macrocella. Il contorno di bastoni è il modello Blender
# (BuildingModels3D.MODELS["deposit_site"]); qui il fondo (2026-11-21, richiesta utente): 9 zone d'appoggio più chiare
# dove stanno i mucchi (griglia 3x3 di MicroCellRenderer.DEPOSIT_SITE_STORAGE_GRID_*), a macchia irregolare e sfumata, mai
# squadrate, e i passaggi tra l'una e l'altra un po' più scuri, come terra calpestata; verso il bordo della sagoma del 2D
# (DepositSiteShape) si perde nella terra battuta chiara sotto l'edificio. Non è un Decal: tingerebbe anche i mucchi e i
# loro adesivi, che stanno sullo stesso livello del terreno. È una superficie sottilissima che segue il terreno, appena
# sopra. Fino al 2026-11-21 c'erano quattro paletti agli angoli: il codice resta, spento da SHOW_STAKES.

# Margine attorno alla sagoma (px del 2D) per la sfumatura del bordo.
const MARGIN_PX := 2.0
const TEXTURE_SIZE := 128
# Larghezza della sfumatura del bordo (px del 2D) e quanto il rumore la muove.
const EDGE_FADE_PX := 0.9
const EDGE_NOISE_PX := 0.6

# Zone d'appoggio e passaggi (px del 2D = metri). Raggio medio di una zona (i posti sono a 2,4 m l'uno dall'altro: tra due
# zone resta un passaggio di circa mezzo metro), quanto varia da zona a zona, quanto il rumore ne muove il bordo e quanto
# è larga la sfumatura.
const SLOT_RADIUS_PX := 0.95
const SLOT_RADIUS_JITTER_PX := 0.12
const SLOT_WARP_PX := 0.35
const SLOT_FADE_PX := 0.3
# Fin dove arrivano i passaggi calpestati attorno alla griglia, prima di perdersi nella terra battuta.
const PATHS_REACH_PX := 3.7
const PATHS_FADE_PX := 0.7
# Colori: la terra battuta è beaten_color di terrain.gdshader (0.74, 0.62, 0.44); le zone un po' più chiare, i passaggi
# un po' più scuri. Opacità sopra la terra battuta.
const SLOT_COLOR := Color(0.82, 0.71, 0.53)
const PATH_COLOR := Color(0.60, 0.49, 0.34)
const SLOT_ALPHA := 0.75
const PATH_ALPHA := 0.45
# Quanto sta sopra il terreno (microcelle: 0,004 = 4 cm) e in quanti quadratini si piega per seguirlo.
const GROUND_LIFT := 0.004
const GROUND_SUBDIVISIONS := 12

# Paletti agli angoli: alti circa un metro (1 microcella = 10 m), un po' dentro gli angoli smussati della sagoma.
const STAKE_HEIGHT := 0.12
const STAKE_RADIUS := 0.012
const STAKE_SIDES := 6
const STAKE_INSET := 0.06
const STAKE_COLOR := Color("6b5232")
const STAKE_SINK := 0.015

static var _texture: ImageTexture
static var _stake_mesh: ArrayMesh
static var _ground_material: StandardMaterial3D


# Fondo a zone (false = niente: resta la sola terra battuta chiara sotto l'edificio).
const SHOW_GROUND_PATCH := true
# Paletti agli angoli (false = senza). Spenti il 2026-11-21 (richiesta utente): al loro posto il modello Blender coi bastoni
# sdraiati sul contorno (BuildingModels3D.MODELS["deposit_site"]).
const SHOW_STAKES := false


# Superficie del fondo: griglia di GROUND_SUBDIVISIONS² quadratini centrata sull'edificio, ogni vertice all'altezza del
# terreno più GROUND_LIFT, con la texture delle zone.
static func _make_patch(center: Vector2, side: float, base_global: Vector2) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := GROUND_SUBDIVISIONS
	for j in range(n + 1):
		for i in range(n + 1):
			var uv := Vector2(float(i) / n, float(j) / n)
			var local := center + (uv - Vector2(0.5, 0.5)) * side
			var y := GroundHeight3D.land_height(base_global.x + local.x, base_global.y + local.y) + GROUND_LIFT
			st.set_uv(uv)
			st.add_vertex(Vector3(local.x, y, local.y))
	for j in range(n):
		for i in range(n):
			var k := j * (n + 1) + i
			# Faccia verso l'alto (y = +z del mondo verso il basso dell'immagine).
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + n + 1)
			st.add_index(k + 1)
			st.add_index(k + n + 2)
			st.add_index(k + n + 1)
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = "DepositGround"
	instance.mesh = st.commit()
	instance.material_override = _get_ground_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _get_ground_material() -> StandardMaterial3D:
	if _ground_material != null:
		return _ground_material
	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_texture = _get_texture()
	_ground_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ground_material.roughness = 1.0
	_ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ground_material


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
		if SHOW_GROUND_PATCH:
			node.add_child(_make_patch(center, side, base_global))
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
	if SHOW_STAKES:
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


# Una sola texture per tutti i depositi (sagoma del 2D e griglia dei posti fisse): 9 zone chiare a macchia sui posti,
# passaggi più scuri tra l'una e l'altra, grana, e il tutto che si perde verso il bordo della sagoma.
static func _get_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var polygon := DepositSiteShape.get_polygon(MicroCellRenderer.DEPOSIT_SITE_HALF_SIDE)
	var spacing: float = MicroCellRenderer.DEPOSIT_SITE_STORAGE_GRID_CELL_SPACING
	var columns: int = MicroCellRenderer.DEPOSIT_SITE_STORAGE_GRID_COLUMNS
	var edge_noise := FastNoiseLite.new()
	edge_noise.seed = 5151
	edge_noise.frequency = 0.06
	var grain_noise := FastNoiseLite.new()
	grain_noise.seed = 5152
	grain_noise.frequency = 0.35
	var warp_x := FastNoiseLite.new()
	warp_x.seed = 5154
	warp_x.frequency = 0.05
	var warp_y := FastNoiseLite.new()
	warp_y.seed = 5155
	warp_y.frequency = 0.05
	var rng := RandomNumberGenerator.new()
	rng.seed = 5153
	# Centri e raggi delle zone (stesso ordine e stesse posizioni dei mucchi), ognuna un po' spostata e di misura sua.
	var slot_centers: Array[Vector2] = []
	var slot_radii: Array[float] = []
	for i in range(columns * columns):
		var c := Vector2((float(i % columns) - 1.0) * spacing, (float(i / columns) - 1.0) * spacing)
		slot_centers.append(c + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)))
		slot_radii.append(SLOT_RADIUS_PX + rng.randf_range(-SLOT_RADIUS_JITTER_PX, SLOT_RADIUS_JITTER_PX))
	var size := TEXTURE_SIZE
	var side_px := _texture_side_px()
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			# Punto in px del 2D, centro della sagoma in (0, 0).
			var p := (Vector2(x + 0.5, y + 0.5) / size - Vector2(0.5, 0.5)) * side_px
			var distance := _signed_distance(p, polygon) + edge_noise.get_noise_2d(x, y) * EDGE_NOISE_PX
			var edge := 1.0 - smoothstep(-EDGE_FADE_PX * 2.0, EDGE_FADE_PX * 0.5, distance)
			if edge <= 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Punto mosso dal rumore: i bordi delle zone diventano macchie irregolari.
			var q := p + Vector2(warp_x.get_noise_2d(x, y), warp_y.get_noise_2d(x, y)) * SLOT_WARP_PX * 2.0
			var slot := 0.0
			for i in range(slot_centers.size()):
				var d := q.distance_to(slot_centers[i])
				slot = maxf(slot, 1.0 - smoothstep(slot_radii[i] - SLOT_FADE_PX, slot_radii[i] + SLOT_FADE_PX, d))
			# Passaggi calpestati: dentro la griglia, sfumando verso i bastoni (misura tra quadrato e cerchio).
			var reach := maxf(absf(q.x), absf(q.y)) * 0.6 + q.length() * 0.4
			var paths := 1.0 - smoothstep(PATHS_REACH_PX - PATHS_FADE_PX, PATHS_REACH_PX + PATHS_FADE_PX, reach)
			var grain := grain_noise.get_noise_2d(x, y) * 0.06 + rng.randf_range(-0.03, 0.03)
			var color := PATH_COLOR.lerp(SLOT_COLOR, slot)
			color = Color(color.r + grain, color.g + grain * 0.9, color.b + grain * 0.7)
			color.a = maxf(slot * SLOT_ALPHA, paths * PATH_ALPHA) * edge
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
