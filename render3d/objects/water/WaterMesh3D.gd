class_name WaterMesh3D
extends RefCounted

# Oggetto 3D: la superficie dell'acqua di UNA macrocella (mare, lago, fiume, ruscello), piatta e un po' trasparente
# sopra il fondale del terreno. Un quadrato per microcella d'acqua.

const SHADER_PATH := "res://render3d/objects/water/water.gdshader"
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


# Materiale dell'acqua (water.gdshader): colore dei vertici con trasparenza, lucido, più la nebbia del 2D. Il rumore dei
# bordi è quello del terreno (`terrain`), così il confine della nebbia è lo stesso.
static func make_material(terrain: ShaderMaterial) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter("edge_noise", terrain.get_shader_parameter("edge_noise"))
	return material


# Copia del materiale per una cella (la nebbia è una texture per cella): stesso rumore, più il suo angolo in microcelle
# assolute.
static func for_cell(shared: ShaderMaterial, cell_origin: Vector2) -> ShaderMaterial:
	var material := shared.duplicate() as ShaderMaterial
	material.set_shader_parameter("cell_origin", cell_origin)
	material.set_shader_parameter("cell_size", float(World.WIDTH))
	return material
