class_name ShrubCanes3D
extends RefCounted

# Forme dei tralci di rovo: archi sottili che partono dal centro, salgono e ricadono fino a terra.
# - leafy_meshes(): tralci rosso-bruni con qualche foglia (piccola bolla verde) lungo l'arco, per i cespugli da frutto
#   (Shrubs3D li mette sopra la cupola di bolle).
# - bare_meshes(): tralci spogli, più corti e più dritti, per i cespugli tagliati (i rovi del 2D).
# Base in (0, 0, 0), ingombro circa raggio 1 (ogni cespuglio li scala alla sua taglia). Qualche variante fissa.
# Colori nei vertici (l'istanza li lascia così: colore bianco).

const VARIANTS := 4
const TUBE_SEGMENTS := 8
const TUBE_SIDES := 5
const CANE_COLOR := Color("6e3f2c")
const BARE_COLOR := Color("5e4630")
const LEAF_COLOR_A := Color("4f6e2e")
const LEAF_COLOR_B := Color("667f37")

static var _leafy: Array = []
static var _bare: Array = []


static func leafy_meshes() -> Array:
	if _leafy.is_empty():
		for variant in range(VARIANTS):
			_leafy.append(_build(variant, true))
	return _leafy


static func bare_meshes() -> Array:
	if _bare.is_empty():
		for variant in range(VARIANTS):
			_bare.append(_build(variant, false))
	return _bare


static func _build(variant: int, leafy: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = (9157 if leafy else 3271) * (variant + 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var count := rng.randi_range(6, 8) if leafy else rng.randi_range(8, 10)
	var phase := rng.randf() * TAU
	for k in range(count):
		var angle := phase + TAU * k / count + rng.randf_range(-0.35, 0.35)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var reach := rng.randf_range(0.8, 1.0) if leafy else rng.randf_range(0.45, 0.8)
		var lift := rng.randf_range(0.55, 0.75) if leafy else rng.randf_range(0.6, 0.9)
		var start := direction * 0.12 + Vector3(0.0, 0.15 if leafy else 0.0, 0.0)
		var end := direction * reach + Vector3(0.0, 0.0 if leafy else lift * 0.45, 0.0)
		var control := direction * reach * 0.5 + Vector3(0.0, lift, 0.0)
		var radius := 0.03 if leafy else 0.035
		var color := CANE_COLOR if leafy else BARE_COLOR
		_add_tube(vertices, normals, colors, indices, start, control, end, radius, color)
		if leafy:
			for leaf in range(3):
				var t := 0.4 + leaf * 0.2 + rng.randf_range(-0.05, 0.05)
				var leaf_color := LEAF_COLOR_A.lerp(LEAF_COLOR_B, rng.randf())
				_add_leaf(vertices, normals, colors, indices, _bezier(start, control, end, t), rng.randf_range(0.07, 0.1), leaf_color)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


# Tubo lungo l'arco, più sottile in punta.
static func _add_tube(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, radius: float, color: Color) -> void:
	var offset := vertices.size()
	for s in range(TUBE_SEGMENTS + 1):
		var t := float(s) / TUBE_SEGMENTS
		var point := _bezier(a, b, c, t)
		var tangent := (_bezier(a, b, c, minf(t + 0.01, 1.0)) - _bezier(a, b, c, maxf(t - 0.01, 0.0))).normalized()
		var side := tangent.cross(Vector3.UP)
		if side.length() < 0.001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(tangent).normalized()
		var r := radius * lerpf(1.0, 0.4, t)
		var shade := lerpf(0.75, 1.05, t)
		for k in range(TUBE_SIDES):
			var angle := TAU * k / TUBE_SIDES
			var n := side * cos(angle) + up * sin(angle)
			vertices.append(point + n * r)
			normals.append(n)
			colors.append(Color(color.r * shade, color.g * shade, color.b * shade))
	for s in range(TUBE_SEGMENTS):
		for k in range(TUBE_SIDES):
			var i0 := offset + s * TUBE_SIDES + k
			var i1 := offset + s * TUBE_SIDES + (k + 1) % TUBE_SIDES
			var i2 := i0 + TUBE_SIDES
			var i3 := i1 + TUBE_SIDES
			# Senso orario visto da fuori (faccia davanti per Godot).
			indices.append_array([i0, i1, i2, i1, i3, i2])


# Foglia: una piccola bolla un po' schiacciata.
static func _add_leaf(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, center: Vector3, radius: float, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 3
	var arrays := sphere.get_mesh_arrays()
	var offset := vertices.size()
	for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var direction := v.normalized()
		vertices.append(center + Vector3(direction.x, direction.y * 0.6, direction.z) * radius)
		normals.append(direction)
		var shade := lerpf(0.7, 1.05, direction.y * 0.5 + 0.5)
		colors.append(Color(color.r * shade, color.g * shade, color.b * shade))
	for index in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		indices.append(index + offset)
