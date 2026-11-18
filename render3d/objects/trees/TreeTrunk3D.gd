class_name TreeTrunk3D
extends RefCounted

# Forma del tronco, comune a latifoglie e conifere: cilindro un po' rastremato, base in (0, 0, 0), altezza 1 e raggio 1
# alla base (ogni albero lo scala alle sue misure). Corteccia più scura in basso.

const COLOR_BARK := Color("5b4532")
const TOP_RADIUS_RATIO := 0.6
const SIDES := 7

static var _mesh: ArrayMesh


static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = TOP_RADIUS_RATIO
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = SIDES
	cylinder.rings = 1
	cylinder.cap_bottom = false
	var arrays := cylinder.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for k in range(vertices.size()):
		vertices[k].y += 0.5
		colors.append(COLOR_BARK.darkened(0.25 * (1.0 - clampf(vertices[k].y, 0.0, 1.0))))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh
