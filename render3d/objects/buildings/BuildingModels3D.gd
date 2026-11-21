class_name BuildingModels3D
extends RefCounted

# Oggetto 3D: gli edifici di UNA cella che hanno modelli Blender (.glb in render3d/assets/models/buildings/, ricette in
# SOURCES_PER_GIOCO/blender/scripts/). Un modello per fase: indice = fase di BuildingConstructionStage (0 = cantiere non
# allestito, 1..N fasi del lavoro), l'ultimo = edificio finito. Se manca il modello di una fase, quell'edificio non si
# disegna (più avanti: cantiere generico). Modelli in metri: x 0,1 (1 microcella = 10 m). Porta verso -Z del modello.

const MODEL_SCALE := 0.1
const MODEL_DIR := "res://render3d/assets/models/buildings/"
const MODELS := {
	# Fase 0 (piazzato, non allestito): nessun modello, solo il cartello — non ha ancora portato niente nessuno.
	"stick_tent": ["", "stick_tent_1_struttura", "stick_tent_2_copertura", "stick_tent_3_finita"],
	"stacked_stones": ["", "stacked_stones_1_base", "stacked_stones_2_meta", "stacked_stones_3_finita"],
	# waste_pit.tres non ha soglie: tutto lo scavo è fase 1.
	"waste_pit": ["", "waste_pit_1_scavo", "waste_pit_2_finita"],
	# drying_rack.tres non ha soglie: tutto il lavoro è fase 1. Il finito è vuoto: i carichi li appende _add_rack_loads.
	"drying_rack": ["", "drying_rack_1_cantiere", "drying_rack_2_finito"],
}

# Essiccatoio (SOURCES_PER_GIOCO/blender/scripts/drying_rack.py): un carico appeso per posto occupato, nell'ordine dei posti, alle
# x di SLOT_X della ricetta. Carne e pesce alla traversa alta, pelle alla bassa (punti in metri, assi di Godot: la y del
# Blender diventa -z). Ingrediente fresco e prodotto secco hanno lo stesso carico.
const RACK_TYPE := "drying_rack"
const RACK_ITEM_BY_RESOURCE := {
	"meat": "carne", "dried_meat": "carne",
	"fish_meat": "pesce", "dried_fish": "pesce",
	"hide": "pelle", "dried_hide": "pelle",
}
const RACK_SLOT_X := [-2.0, -1.2, -0.4, 0.4, 1.2, 2.0]  # graticcio stretto (2026-11-21)
const RACK_TOP_HANG := Vector2(1.78, 0.0)     # (quota, z) traversa alta
const RACK_LOW_HANG := Vector2(1.05, -0.4225) # (quota, z) traversa bassa

# Fossa dei rifiuti (SOURCES_PER_GIOCO/blender/scripts/waste_pit.py): lo strato di rifiuti sale dal fondo alla cima della parete
# e si allarga con lei secondo quanto è piena (BuildingModelsSnapshot3D.fills); piena del tutto = il cumulo stracolmo.
# Misure in metri come nella ricetta (FLOOR_Z, WALL_TOP_Z, FLOOR_RADIUS, WALL_TOP_RADIUS).
const PIT_FILL := "waste_pit_riempimento"
const PIT_FULL := "waste_pit_stracolma"
const PIT_FILL_RISE := 0.45 - 0.03
const PIT_FILL_WIDEN := 3.1 / 2.6 - 1.0

# Cartello dei cantieri non allestiti, per tutti i tipi (SOURCES_PER_GIOCO/blender/scripts/wip_sign.py).
const WIP_SIGN := "wip_sign"

# Niente LOD per gli edifici (2026-11-20, richiesta utente): con la soglia LOD della vista 3D (View3D.MESH_LOD_THRESHOLD,
# 16 px) la semplificazione automatica dell'import cancellava da lontano i pezzi piccoli e staccati (sassi e bastoncini
# delle pietre rituali). Gli edifici sono pochi: si tiene sempre il modello pieno, con una lod_bias altissima su ogni
# MeshInstance3D (anche cartello, riempimento della fossa e carichi dell'essiccatoio).
const NO_LOD_BIAS := 1000.0


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
		if i < snapshot.fills.size() and snapshot.fills[i] > 0.0:
			_add_pit_fill(instance, snapshot.fills[i])
		if i < snapshot.rack_loads.size() and not snapshot.rack_loads[i].is_empty():
			_add_rack_loads(instance, snapshot.rack_loads[i])
	if root.get_child_count() == 0:
		root.free()
		return null
	_disable_lod(root)
	return root


static func _disable_lod(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).lod_bias = NO_LOD_BIAS
	for child in node.get_children():
		_disable_lod(child)


# Riempimento della fossa, figlio del suo modello (stessa scala e rotazione, misure in metri del modello).
static func _add_pit_fill(pit: MeshInstance3D, fill: float) -> void:
	var full := fill >= 1.0
	var mesh := _load_mesh(PIT_FULL if full else PIT_FILL)
	if mesh == null:
		return
	var layer := MeshInstance3D.new()
	layer.mesh = mesh
	if not full:
		var widen := 1.0 + PIT_FILL_WIDEN * fill
		layer.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(widen, 1.0, widen)), Vector3(0.0, PIT_FILL_RISE * fill, 0.0))
	pit.add_child(layer)


# Carichi dell'essiccatoio, figli del suo modello (stessa scala e rotazione, misure in metri del modello).
static func _add_rack_loads(rack: MeshInstance3D, loads: PackedStringArray) -> void:
	for slot in range(mini(loads.size(), RACK_SLOT_X.size())):
		var item := loads[slot]
		if item.is_empty():
			continue
		var mesh := _load_mesh("drying_rack_" + item)
		if mesh == null:
			continue
		var hang: Vector2 = RACK_LOW_HANG if item == "pelle" else RACK_TOP_HANG
		var load_instance := MeshInstance3D.new()
		load_instance.mesh = mesh
		load_instance.position = Vector3(RACK_SLOT_X[slot], hang.x, hang.y)
		rack.add_child(load_instance)


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
