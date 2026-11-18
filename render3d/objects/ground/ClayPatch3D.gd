class_name ClayPatch3D
extends RefCounted

# Oggetto 3D: il giacimento d'argilla di UNA macrocella, come pozza nel terreno (non una lastra appoggiata sopra).
# Per ogni angolo della griglia calcola "quanta argilla c'è qui attorno" (corner_weights), sfumato su un piccolo raggio
# e reso un po' irregolare: il terreno (TerrainMesh3D) lo usa per scendere a conca e sfumare dal prato al rossiccio,
# così gli spigoli delle caselle si arrotondano da soli. Le microcelle sono le stesse del 2D (clay_positions).
# Qui si mettono anche le crepe e le poche zolle, solo nel pieno della pozza (decoro fisso per microcella).

const COLOR_DARK := Color(0.44, 0.30, 0.22)
const COLOR_LIGHT := Color(0.56, 0.39, 0.28)
const CRACK_COLOR := Color("4a2e1c")
const LUMP_COLOR := Color("7a4e34")
# Profondità del fondo della pozza sotto il prato.
const DEPTH := 0.16
# Raggio della sfumatura attorno a ogni angolo, in microcelle, e irregolarità del contorno.
const BLUR_RADIUS := 1.6
const EDGE_NOISE := 0.18
const EDGE_NOISE_FREQUENCY := 0.35
# Sopra questa "quantità d'argilla" si è nel pieno della pozza (crepe e zolle).
const FULL_WEIGHT := 0.85
const CRACK_CHANCE := 0.18
const CRACK_HALF_WIDTH := 0.016
const LUMP_CHANCE := 0.15
const LUMP_VARIANTS := 4

static var _lump_meshes: Array = []
static var _edge_noise: FastNoiseLite


# Quantità d'argilla 0..1 per angolo della griglia ((World.WIDTH+1)^2, indice j * (WIDTH+1) + i). Vuoto se niente argilla.
static func corner_weights(source: Cell3DSource) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	if source.clay_positions.is_empty():
		return weights
	var size := World.WIDTH
	weights.resize((size + 1) * (size + 1))
	var reach := int(ceil(BLUR_RADIUS))
	var base_x := source.coords.x * World.WIDTH
	var base_y := source.coords.y * World.HEIGHT
	for j in range(size + 1):
		for i in range(size + 1):
			var total := 0.0
			var clay := 0.0
			# Celle attorno all'angolo, pesate per distanza dal loro centro (sfumatura morbida, contorno tondo).
			for cy in range(j - reach, j + reach):
				for cx in range(i - reach, i + reach):
					var d := Vector2(cx + 0.5 - i, cy + 0.5 - j).length()
					if d > BLUR_RADIUS:
						continue
					var w := 1.0 - d / BLUR_RADIUS
					total += w
					if source.clay_positions.has(Vector2i(cx, cy)):
						clay += w
			var value := clay / total if total > 0.0 else 0.0
			if value > 0.0 and value < 1.0:
				value = clampf(value + _edge_noise_at(base_x + i, base_y + j) * EDGE_NOISE, 0.0, 1.0)
			weights[j * (size + 1) + i] = value
	return weights


# Quanto scende il terreno con quella quantità d'argilla.
static func depth_for(weight: float) -> float:
	return DEPTH * smoothstep(0.15, 0.85, weight)


# Colore dell'angolo: dal prato all'argilla, sfumando.
static func blend_color(ground: Color, corner: Vector2i, weight: float) -> Color:
	var clay := COLOR_DARK.lerp(COLOR_LIGHT, Noise2DMatch.value(corner, 6))
	return ground.lerp(clay, smoothstep(0.3, 0.6, weight))


# Crepe e zolle nel pieno della pozza. null se non ce ne sono.
static func build(source: Cell3DSource, weights: PackedFloat32Array, material: Material) -> Node3D:
	if weights.is_empty():
		return null
	_ensure_lumps()
	var size := World.WIDTH
	var base := Vector2(source.coords.x * World.WIDTH, source.coords.y * World.HEIGHT)
	var builder := FlatMeshBuilder.new()
	var lump_buckets: Array = []
	for i in range(LUMP_VARIANTS):
		lump_buckets.append([])
	for pos: Vector2i in source.clay_positions:
		if pos.x < 0 or pos.y < 0 or pos.x >= size or pos.y >= size:
			continue
		if not _is_full(weights, pos, size):
			continue
		if Noise2DMatch.value(pos, 7) < CRACK_CHANCE:
			_add_crack(builder, base, pos)
		if Noise2DMatch.value(pos, 9) < LUMP_CHANCE:
			var p := Vector2(pos) + Vector2(0.5, 0.5) + Vector2(Noise2DMatch.value(pos, 10) - 0.5, Noise2DMatch.value(pos, 11) - 0.5) * 0.6
			var angle := Noise2DMatch.value(pos, 12) * TAU
			lump_buckets[posmod(hash(pos), LUMP_VARIANTS)].append(Transform3D(Basis(Vector3.UP, angle), _bottom_point(base, p)))
	var node := Node3D.new()
	node.name = "Clay"
	if not builder.is_empty():
		var cracks := MeshInstance3D.new()
		cracks.mesh = builder.build()
		cracks.material_override = material
		cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(cracks)
	node.add_child(MultiMeshGroup3D.build("Lumps", _lump_meshes, lump_buckets, material))
	return node


static func _is_full(weights: PackedFloat32Array, pos: Vector2i, size: int) -> bool:
	for corner in [pos, pos + Vector2i(1, 0), pos + Vector2i(1, 1), pos + Vector2i(0, 1)]:
		if weights[corner.y * (size + 1) + corner.x] < FULL_WEIGHT:
			return false
	return true


# Punto sul fondo della pozza (dove l'argilla è piena il terreno è sceso di DEPTH).
static func _bottom_point(base: Vector2, p: Vector2) -> Vector3:
	return Vector3(p.x, GroundHeight3D.land_height(base.x + p.x, base.y + p.y) - DEPTH, p.y)


# Crepa a zig-zag dentro la microcella: due tratti sottili appena sopra il fondo.
static func _add_crack(builder: FlatMeshBuilder, base: Vector2, pos: Vector2i) -> void:
	var origin := Vector2(pos)
	var a := origin + Vector2(0.2 + 0.2 * Noise2DMatch.value(pos, 13), 0.25)
	var b := origin + Vector2(0.4 + 0.3 * Noise2DMatch.value(pos, 14), 0.5)
	var c := origin + Vector2(0.3 + 0.4 * Noise2DMatch.value(pos, 15), 0.78)
	var lift := Vector3(0.0, 0.012, 0.0)
	for segment in [[a, b], [b, c]]:
		var from: Vector2 = segment[0]
		var to: Vector2 = segment[1]
		var side := (to - from).normalized().orthogonal() * CRACK_HALF_WIDTH
		var p0 := _bottom_point(base, from + side) + lift
		var p1 := _bottom_point(base, from - side) + lift
		var p2 := _bottom_point(base, to - side) + lift
		var p3 := _bottom_point(base, to + side) + lift
		builder.add_ground_triangle(p0, p1, p2, CRACK_COLOR)
		builder.add_ground_triangle(p0, p2, p3, CRACK_COLOR)


static func _edge_noise_at(gx: float, gy: float) -> float:
	if _edge_noise == null:
		_edge_noise = FastNoiseLite.new()
		_edge_noise.seed = 5151
		_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_edge_noise.frequency = EDGE_NOISE_FREQUENCY
	return _edge_noise.get_noise_2d(gx, gy)


static func _ensure_lumps() -> void:
	if not _lump_meshes.is_empty():
		return
	for variant in range(LUMP_VARIANTS):
		var radius := lerpf(0.05, 0.075, float(variant) / float(LUMP_VARIANTS - 1))
		_lump_meshes.append(FacetedStoneMesh.build(radius, radius * 0.7, 5, 0.25, 300 + variant, LUMP_COLOR))
