class_name ClayPatch3D
extends RefCounted

# Oggetto 3D: il giacimento d'argilla di UNA macrocella, come pozza nel terreno (non una lastra appoggiata sopra).
# Per ogni angolo della griglia calcola "quanta argilla c'è qui attorno" (corner_weights), sfumato su un piccolo raggio
# e reso un po' irregolare: il terreno (TerrainMesh3D) lo usa per scendere a conca e lo passa allo shader del terreno,
# che disegna argilla e orlo bagnato con un bordo frastagliato. Le microcelle sono le stesse del 2D (clay_positions).
# Qui si mettono anche le poche zolle, solo nel pieno della pozza (decoro fisso per microcella).

const LUMP_COLOR := Color("7a4e34")
# Profondità del fondo della pozza sotto il prato.
const DEPTH := 0.16
# Raggio della sfumatura attorno a ogni angolo, in microcelle, e irregolarità del contorno.
const BLUR_RADIUS := 1.6
const EDGE_NOISE := 0.18
const EDGE_NOISE_FREQUENCY := 0.35
# Sopra questa "quantità d'argilla" si è nel pieno della pozza (zolle).
const FULL_WEIGHT := 0.85
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


# Zolle nel pieno della pozza, tranne sulle microcelle di `hidden` (sotto il nero della nebbia: non si creano). null se
# non ce ne sono.
static func build(source: Cell3DSource, weights: PackedFloat32Array, material: Material, hidden: Dictionary = {}) -> Node3D:
	if weights.is_empty():
		return null
	_ensure_lumps()
	var size := World.WIDTH
	var base := Vector2(source.coords.x * World.WIDTH, source.coords.y * World.HEIGHT)
	var lump_buckets: Array = []
	for i in range(LUMP_VARIANTS):
		lump_buckets.append([])
	for pos: Vector2i in source.clay_positions:
		if pos.x < 0 or pos.y < 0 or pos.x >= size or pos.y >= size:
			continue
		if not _is_full(weights, pos, size) or hidden.has(pos):
			continue
		if Noise2DMatch.value(pos, 9) < LUMP_CHANCE:
			var p := Vector2(pos) + Vector2(0.5, 0.5) + Vector2(Noise2DMatch.value(pos, 10) - 0.5, Noise2DMatch.value(pos, 11) - 0.5) * 0.6
			var angle := Noise2DMatch.value(pos, 12) * TAU
			lump_buckets[posmod(hash(pos), LUMP_VARIANTS)].append(Transform3D(Basis(Vector3.UP, angle), _bottom_point(base, p)))
	var node := Node3D.new()
	node.name = "Clay"
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
