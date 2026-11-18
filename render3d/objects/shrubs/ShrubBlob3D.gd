class_name ShrubBlob3D
extends RefCounted

# Forma di UNA bolla di cespuglio: la stessa "nuvola" tonda e bitorzoluta delle chiome degli alberi (BroadleafCrown3D:
# stessa sfera, stesse bozze, più chiara in alto), da sola. Il cespuglio ne mette insieme alcune, schiacciate, dove il
# 2D mette i suoi lobi (Shrubs3D). Raggio 1, centro in (0, 0, 0). Qualche variante fissa.

const VARIANTS := 4


static var _meshes: Array = []


static func meshes() -> Array:
	if _meshes.is_empty():
		for variant in range(VARIANTS):
			_meshes.append(_build(variant))
	return _meshes


static func _build(variant: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 517 + variant
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.6

	var sphere := SphereMesh.new()
	sphere.radial_segments = BroadleafCrown3D.BLOB_SEGMENTS
	sphere.rings = BroadleafCrown3D.BLOB_RINGS
	var sphere_arrays := sphere.get_mesh_arrays()
	var unit_vertices: PackedVector3Array = sphere_arrays[Mesh.ARRAY_VERTEX]

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for v in unit_vertices:
		var direction := v.normalized()
		var bump := 1.0 + noise.get_noise_3dv(direction * 2.0) * BroadleafCrown3D.BUMP_AMOUNT * 1.4
		var point := direction * bump
		vertices.append(point)
		normals.append(direction)
		var shade := lerpf(BroadleafCrown3D.SHADE_BOTTOM, BroadleafCrown3D.SHADE_TOP, smoothstep(-0.8, 0.9, point.y))
		colors.append(Color(shade, shade, shade))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = sphere_arrays[Mesh.ARRAY_INDEX]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
