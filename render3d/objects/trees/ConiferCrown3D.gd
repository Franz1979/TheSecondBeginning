class_name ConiferCrown3D
extends RefCounted

# Forma della chioma di una conifera: tre coni sovrapposti, il più largo in basso, un po' storti per variante. Base in
# (0, 0, 0), alta UNIT_HEIGHT e larga circa raggio 1 alla base (ogni albero la scala). Più chiara in punta.

const VARIANTS := 4
const UNIT_HEIGHT := 2.6
const SIDES := 9
const SHADE_BOTTOM := 0.65
const SHADE_TOP := 1.05

static var _meshes: Array = []


static func meshes() -> Array:
	if _meshes.is_empty():
		for variant in range(VARIANTS):
			_meshes.append(_build(variant))
	return _meshes


static func _build(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3313 * (variant + 1)
	# [quota della base, altezza, raggio della base] dei tre coni.
	var tiers := [[0.0, 1.3, 1.0], [0.75, 1.15, 0.78], [1.4, 1.2, 0.52]]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for tier in tiers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = float(tier[2]) * rng.randf_range(0.92, 1.08)
		cone.height = float(tier[1]) * rng.randf_range(0.95, 1.05)
		cone.radial_segments = SIDES
		cone.rings = 1
		var arrays := cone.get_mesh_arrays()
		var offset := vertices.size()
		var lift := float(tier[0]) + cone.height * 0.5
		var lean := Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.04, 0.04))
		for k in range((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()):
			var v: Vector3 = arrays[Mesh.ARRAY_VERTEX][k]
			var point := v + Vector3(0.0, lift, 0.0) + lean * (v.y + cone.height * 0.5)
			vertices.append(point)
			normals.append(arrays[Mesh.ARRAY_NORMAL][k])
			var shade := lerpf(SHADE_BOTTOM, SHADE_TOP, clampf(point.y / UNIT_HEIGHT, 0.0, 1.0))
			# Il bordo in basso di ogni cono un po' più scuro: si leggono i "palchi" dei rami.
			if v.y < 0.0:
				shade *= lerpf(0.85, 1.0, clampf((v.y + cone.height * 0.5) / (cone.height * 0.5), 0.0, 1.0))
			colors.append(Color(shade, shade, shade))
		for index in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
			indices.append(index + offset)

	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_COLOR] = colors
	result[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result)
	return mesh
