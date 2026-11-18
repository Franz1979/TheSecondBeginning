class_name BroadleafCrown3D
extends RefCounted

# Forma della chioma di una latifoglia: un grappolo di 5-7 "nuvole" tonde e un po' bitorzolute, più chiare in alto e più
# scure in basso (il verde vero lo dà il colore dell'istanza, Trees3D). Qualche variante fissa, scelta per albero.
# Centro in (0, 0, 0), ingombro circa raggio 1 (ogni albero la scala alla sua chioma).

const VARIANTS := 6
const BLOB_SEGMENTS := 12
const BLOB_RINGS := 7
const BUMP_AMOUNT := 0.12
const SHADE_BOTTOM := 0.6
const SHADE_TOP := 1.1

static var _meshes: Array = []


static func meshes() -> Array:
	if _meshes.is_empty():
		for variant in range(VARIANTS):
			_meshes.append(_build(variant))
	return _meshes


static func _build(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409 * (variant + 1)
	var noise := FastNoiseLite.new()
	noise.seed = 77 + variant
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.6

	var sphere := SphereMesh.new()
	sphere.radial_segments = BLOB_SEGMENTS
	sphere.rings = BLOB_RINGS
	var sphere_arrays := sphere.get_mesh_arrays()
	var unit_vertices: PackedVector3Array = sphere_arrays[Mesh.ARRAY_VERTEX]
	var unit_indices: PackedInt32Array = sphere_arrays[Mesh.ARRAY_INDEX]

	# Nuvole: una centrale in alto e le altre attorno, un po' più in basso.
	var blobs: Array = [[Vector3(0.0, 0.2, 0.0), rng.randf_range(0.55, 0.62)]]
	var count := rng.randi_range(4, 6)
	var phase := rng.randf() * TAU
	for k in range(count):
		var angle := phase + TAU * k / count + rng.randf_range(-0.3, 0.3)
		var distance := rng.randf_range(0.38, 0.5)
		blobs.append([Vector3(cos(angle) * distance, rng.randf_range(-0.2, 0.15), sin(angle) * distance), rng.randf_range(0.4, 0.52)])

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for blob in blobs:
		var center: Vector3 = blob[0]
		var radius: float = blob[1]
		var offset := vertices.size()
		var blob_shade := rng.randf_range(-0.05, 0.05)
		for v in unit_vertices:
			var direction := v.normalized()
			var point := center + direction * radius
			var bump := 1.0 + noise.get_noise_3dv(point * 2.0) * BUMP_AMOUNT
			point = center + direction * radius * bump
			vertices.append(point)
			normals.append(direction)
			var shade := lerpf(SHADE_BOTTOM, SHADE_TOP, smoothstep(-0.7, 0.8, point.y)) + blob_shade
			colors.append(Color(shade, shade, shade))
		for index in unit_indices:
			indices.append(index + offset)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
