class_name BuildingModels3D
extends RefCounted

# Oggetto 3D: gli edifici di UNA cella che hanno modelli Blender (.glb in render3d/assets/models/buildings/, ricette in
# render3d/blender/scripts/). Un modello per fase: indice = fase di BuildingConstructionStage (0 = cantiere non
# allestito, 1..N fasi del lavoro), l'ultimo = edificio finito. Se manca il modello di una fase, quell'edificio non si
# disegna (più avanti: cantiere generico). Modelli in metri: x 0,1 (1 microcella = 10 m). Porta verso -Z del modello.

const MODEL_SCALE := 0.1
const MODEL_DIR := "res://render3d/assets/models/buildings/"
const MODELS := {
	# Fase 0 (piazzato, non allestito): nessun modello, solo il cartello — non ha ancora portato niente nessuno.
	"stick_tent": ["", "stick_tent_1_struttura", "stick_tent_2_copertura", "stick_tent_3_finita"],
	"stacked_stones": ["", "stacked_stones_1_base", "stacked_stones_2_meta", "stacked_stones_3_finita"],
}

# Cartello dei cantieri non allestiti, per tutti i tipi (render3d/blender/scripts/wip_sign.py).
const WIP_SIGN := "wip_sign"


static func has_models(type_name: String) -> bool:
	return MODELS.has(type_name)


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non c'è niente da disegnare.
static func build(snapshot: BuildingModelsSnapshot3D, base_global: Vector2) -> Node3D:
	if snapshot.size() == 0:
		return null
	var root := Node3D.new()
	for i in range(snapshot.size()):
		var center := snapshot.centers[i]
		var y := GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y)
		var position := Vector3(center.x, y, center.y)
		# Cartello "cantiere" su ogni edificio piazzato e non ancora allestito (come nel 2D), sempre girato verso sud
		# (la camera guarda da lì); giallo su tutte e due le facce.
		if snapshot.stages[i] == BuildingConstructionStage.NOT_SET_UP:
			var sign_mesh := _load_mesh(WIP_SIGN)
			if sign_mesh != null:
				var sign_instance := MeshInstance3D.new()
				sign_instance.mesh = sign_mesh
				sign_instance.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * MODEL_SCALE), position)
				root.add_child(sign_instance)
		var mesh := _mesh_for(snapshot.type_names[i], snapshot.stages[i])
		if mesh == null:
			continue
		var door := snapshot.doors[i]
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		var basis := Basis.looking_at(Vector3(door.x, 0.0, door.y), Vector3.UP).scaled(Vector3.ONE * MODEL_SCALE)
		instance.transform = Transform3D(basis, position)
		instance.set_meta("building_id", snapshot.ids[i])
		root.add_child(instance)
	if root.get_child_count() == 0:
		root.free()
		return null
	return root


# Modello dell'edificio finito (anteprima del piazzamento, PlacementGhost3D); null se il tipo non ha modelli.
static func finished_mesh(type_name: String) -> Mesh:
	return _mesh_for(type_name, BuildingConstructionStage.COMPLETE)


static func _mesh_for(type_name: String, stage: int) -> Mesh:
	var names: Array = MODELS.get(type_name, [])
	if names.is_empty():
		return null
	var index := names.size() - 1 if stage == BuildingConstructionStage.COMPLETE else stage
	if index < 0 or index >= names.size():
		return null
	if String(names[index]).is_empty():
		return null
	return _load_mesh(names[index])


static func _load_mesh(model_name: String) -> Mesh:
	return ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".glb")
