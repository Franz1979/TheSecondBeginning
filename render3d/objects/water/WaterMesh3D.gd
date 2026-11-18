class_name WaterMesh3D
extends RefCounted

# Oggetto 3D: la superficie dell'acqua di UNA macrocella (mare, lago, fiume, ruscello), piatta e un po' trasparente
# sopra il fondale del terreno. Un quadrato per microcella d'acqua.

const KIND_COLORS := {
	0: Palette3D.WATER_SEA,
	1: Palette3D.WATER_LAKE,
	2: Palette3D.WATER_RIVER,
}


# water_cells: Vector2i -> tipo d'acqua (vedi Cell3D.WATER_*). null se nella cella non c'è acqua.
static func build(water_cells: Dictionary, material: Material) -> MeshInstance3D:
	if water_cells.is_empty():
		return null
	var y := GroundHeight3D.WATER_SURFACE
	var builder := FlatMeshBuilder.new()
	for pos in water_cells:
		var color: Color = KIND_COLORS.get(water_cells[pos], Palette3D.WATER_RIVER)
		color.a = Palette3D.WATER_ALPHA
		builder.add_quad(
			Vector3(pos.x, y, pos.y), Vector3(pos.x + 1, y, pos.y), Vector3(pos.x + 1, y, pos.y + 1), Vector3(pos.x, y, pos.y + 1),
			color)
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = builder.build()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# Materiale dell'acqua: colore dei vertici con trasparenza, lucido.
static func make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.12
	material.metallic_specular = 0.7
	return material
