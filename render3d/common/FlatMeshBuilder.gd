class_name FlatMeshBuilder
extends RefCounted

# Costruttore di mesh a facce piatte (low-poly): ogni triangolo ha la sua normale e il suo colore, niente vertici
# condivisi. Usato da tutti gli oggetti 3D fatti da codice. Triangoli in senso orario visti dal lato esterno (Godot).

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


func add_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	_vertices.append(a)
	_vertices.append(b)
	_vertices.append(c)
	_normals.append(normal)
	_normals.append(normal)
	_normals.append(normal)
	_colors.append(color)
	_colors.append(color)
	_colors.append(color)


# Come add_triangle, ma con un colore per vertice (sfumato sulla faccia): per superfici che devono sfumare come nel 2D.
func add_triangle_colors(a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	_vertices.append(a)
	_vertices.append(b)
	_vertices.append(c)
	_normals.append(normal)
	_normals.append(normal)
	_normals.append(normal)
	_colors.append(color_a)
	_colors.append(color_b)
	_colors.append(color_c)


# Triangolo di una superficie a terra (acqua, fango): girato da solo in modo da guardare in alto.
func add_ground_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (c - a).cross(b - a).y < 0.0:
		add_triangle(a, c, b, color)
	else:
		add_triangle(a, b, c, color)


# Quadrilatero a-b-c-d (in senso orario visto dal lato esterno), spezzato in due triangoli con colori leggermente
# diversi per l'aspetto sfaccettato.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, facet_shade: float = 0.0) -> void:
	add_triangle(a, b, c, color.lightened(facet_shade) if facet_shade > 0.0 else color)
	add_triangle(a, c, d, color.darkened(facet_shade) if facet_shade > 0.0 else color)


func is_empty() -> bool:
	return _vertices.is_empty()


func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Materiale opaco che usa il colore dei vertici: uno solo per tutti gli oggetti low-poly.
static func vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# I colori dei vertici sono normali colori sRGB (come nel 2D): senza questo Godot li schiarisce.
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.2
	return material
