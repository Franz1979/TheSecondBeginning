class_name PlacementGhost3D
extends Node3D

# Sovrapposizione 3D: l'anteprima del piazzamento di un edificio (PlacementGhostSnapshot3D, dal BuildingGhost del gioco).
# - Rettangolo occupato poggiato sul terreno, come le aree di lavoro (WorkAreas3D): verde se si può costruire, rosso se
#   no (rosso del fantasma 2D, BuildingGhost.INVALID_COLOR).
# - Se il tipo ha un modello Blender (BuildingModels3D), il modello finito semitrasparente, girato con la porta (tasto R),
#   tinto di rosso quando non si può costruire.
# - Freccia a terra fuori dal lato della porta.
# Un nodo solo sotto la radice del mondo 3D (segue il mouse, non appartiene a una cella), aggiornato a ogni fotogramma da
# View3D; il rettangolo e la freccia si rifanno solo quando cambiano.

# Verde quando si può costruire (2026-11-19, richiesta utente: il marrone del 2D sembrava un rosso sbiadito), rosso
# del fantasma 2D quando no.
const VALID_COLOR := Color(0.35, 0.80, 0.35, 0.75)
const FILL_ALPHA := 0.35
const BORDER_WIDTH_PX := 2.0
const MODEL_ALPHA := 0.55
const MODEL_TINT_VALID := Color(1.0, 0.97, 0.9)
const MODEL_TINT_INVALID := Color(1.0, 0.3, 0.25)
const ARROW_LENGTH := 0.55
const ARROW_WIDTH := 0.5
const ARROW_GAP := 0.15
const ARROW_ALPHA := 0.85

var _signature: Array = []
var _ground: Node3D
var _model: MeshInstance3D
var _model_material: StandardMaterial3D


func update(snapshot: PlacementGhostSnapshot3D) -> void:
	visible = snapshot.active
	if not snapshot.active:
		return
	position = Vector3(snapshot.origin.x, 0.0, snapshot.origin.y)
	var signature := snapshot.signature()
	if signature != _signature:
		_signature = signature
		_rebuild(snapshot)


func _rebuild(snapshot: PlacementGhostSnapshot3D) -> void:
	if _ground != null:
		_ground.queue_free()
		_ground = null
	var base_global := Vector2(snapshot.coords.x * World.WIDTH, snapshot.coords.y * World.HEIGHT)
	var color: Color = VALID_COLOR if snapshot.buildable else BuildingGhost.INVALID_COLOR
	var areas := WorkAreasSnapshot3D.new()
	areas.add(Rect2i(snapshot.rect), color, BORDER_WIDTH_PX, FILL_ALPHA, "")
	_ground = WorkAreas3D.build(areas, base_global)
	if _ground != null:
		var arrow := _make_door_arrow(snapshot, color, base_global)
		if arrow != null:
			_ground.add_child(arrow)
		add_child(_ground)
	_update_model(snapshot, base_global)


func _update_model(snapshot: PlacementGhostSnapshot3D, base_global: Vector2) -> void:
	var mesh := BuildingModels3D.finished_mesh(snapshot.type_name, snapshot.linear_mask)
	if mesh == null:
		if _model != null:
			_model.visible = false
		return
	if _model == null:
		_model = MeshInstance3D.new()
		_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model_material = StandardMaterial3D.new()
		_model_material.vertex_color_use_as_albedo = true
		_model_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_model.material_override = _model_material
		add_child(_model)
	_model.visible = true
	_model.mesh = mesh
	var tint := MODEL_TINT_VALID if snapshot.buildable else MODEL_TINT_INVALID
	_model_material.albedo_color = Color(tint.r, tint.g, tint.b, MODEL_ALPHA)
	var center := snapshot.rect.get_center()
	var y := GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y)
	var door := snapshot.door_direction
	var basis := Basis.looking_at(Vector3(door.x, 0.0, door.y), Vector3.UP).scaled(Vector3.ONE * BuildingModels3D.MODEL_SCALE)
	_model.transform = Transform3D(basis, Vector3(center.x, y, center.y))


# Triangolo a terra appena fuori dal lato della porta, punta verso fuori. null se l'edificio non ha porta.
func _make_door_arrow(snapshot: PlacementGhostSnapshot3D, color: Color, base_global: Vector2) -> MeshInstance3D:
	if snapshot.door_offset == Vector2.INF:
		return null
	var out := snapshot.door_direction.normalized()
	var side := Vector2(-out.y, out.x)
	var base := snapshot.rect.get_center() + snapshot.door_offset + out * ARROW_GAP
	var a := base + side * ARROW_WIDTH / 2.0
	var b := base - side * ARROW_WIDTH / 2.0
	var tip := base + out * ARROW_LENGTH
	var arrow_color := Color(color.r, color.g, color.b, ARROW_ALPHA)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		WorkAreas3D._on_ground(a, base_global), WorkAreas3D._on_ground(tip, base_global), WorkAreas3D._on_ground(b, base_global),
	])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([arrow_color, arrow_color, arrow_color])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = WorkAreas3D._get_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
