class_name GridLines3D
extends RefCounted

# Oggetto 3D: la griglia delle microcelle di UNA macrocella, linee sottili appoggiate sul terreno (seguono
# GroundHeight3D). Accesa e spenta dall'opzione "mostra griglia" del gioco (vedi View3D).

const LIFT := 0.06
const COLOR := Color(0.0, 0.0, 0.0, 0.35)


static func build(source: Cell3DSource, material: Material) -> MeshInstance3D:
	var size := World.WIDTH
	var base_x := source.coords.x * World.WIDTH
	var base_y := source.coords.y * World.HEIGHT
	var vertices := PackedVector3Array()
	for k in range(size + 1):
		for s in range(size):
			# Linea lungo x (y = k) e linea lungo y (x = k), un pezzo per microcella.
			vertices.append(Vector3(s, GroundHeight3D.land_height(base_x + s, base_y + k) + LIFT, k))
			vertices.append(Vector3(s + 1, GroundHeight3D.land_height(base_x + s + 1, base_y + k) + LIFT, k))
			vertices.append(Vector3(k, GroundHeight3D.land_height(base_x + k, base_y + s) + LIFT, s))
			vertices.append(Vector3(k, GroundHeight3D.land_height(base_x + k, base_y + s + 1) + LIFT, s + 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "Grid"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = COLOR
	return material
