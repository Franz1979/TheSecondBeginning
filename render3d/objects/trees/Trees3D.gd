class_name Trees3D
extends RefCounted

# Oggetto 3D: gli alberi vivi di UNA macrocella, nelle stesse posizioni e con la stessa taglia relativa del 2D
# (TreeSnapshot3D). Latifoglie: tronco comune (TreeTrunk3D) e chioma tonda a nuvole (BroadleafCrown3D). Conifere: i 5 pini
# Quaternius (CC0) con le loro texture, preparati da render3d/blender/scripts/pines.py (origine al piede, misure in metri).
# Il verde di ogni chioma varia un poco per albero. Stagioni e frutti: più avanti.
# Le misure del 2D sono pensate per la vista dall'alto; qui si allungano (fattori *_SCALE) per un albero adulto alto
# circa 2 microcelle con la chioma larga circa 1.

const TRUNK_HEIGHT_SCALE := 2.4
const TRUNK_RADIUS_SCALE := 0.45
const CROWN_SCALE := 1.5
const SINK := 0.05

const BROADLEAF_GREEN_A := Color("4d7433")
const BROADLEAF_GREEN_B := Color("6f8f3c")

# Pini: stessa altezza totale delle conifere di prima (tronco corto + chioma conica alta 2,6 volte il suo raggio),
# divisa per l'altezza media dei modelli in metri; ogni variante tiene la sua proporzione (pine_4 è il più alto).
const PINE_DIR := "res://render3d/assets/models/vegetation/pines/"
const PINE_MODELS := ["pine_1", "pine_2", "pine_3", "pine_4", "pine_5"]
const PINE_REFERENCE_HEIGHT := 8.2 # m, media dei 5 modelli
const CONIFER_TRUNK_SHARE := 0.45 * 0.8
const CONIFER_CROWN_HEIGHT := 1.5 * 1.05 * 2.6
# Leggera variazione di tono per albero (moltiplica la texture, se il materiale usa il colore dei vertici).
const PINE_TONE_A := Color(0.88, 0.92, 0.88)
const PINE_TONE_B := Color(1.0, 1.0, 1.0)

static var _pine_meshes: Array = []


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non ci sono alberi.
static func build(snapshot: TreeSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.size() == 0:
		return null
	var broadleaf_meshes := BroadleafCrown3D.meshes()
	var pine_meshes := _get_pine_meshes()
	var trunk_transforms: Array = []
	var broadleaf_transforms: Array = []
	var broadleaf_colors: Array = []
	var pine_transforms: Array = []
	var pine_colors: Array = []
	for i in range(broadleaf_meshes.size()):
		broadleaf_transforms.append([])
		broadleaf_colors.append([])
	for i in range(pine_meshes.size()):
		pine_transforms.append([])
		pine_colors.append([])

	for i in range(snapshot.size()):
		var ground := snapshot.grounds[i]
		var tree_seed := snapshot.seeds[i]
		var y := GroundHeight3D.land_height(base_global.x + ground.x, base_global.y + ground.y) - SINK
		var foot := Vector3(ground.x, y, ground.y)
		var yaw := float(posmod(tree_seed, 3600)) / 3600.0 * TAU
		var tone := float(posmod(tree_seed / 7, 1000)) / 1000.0
		var trunk_height := snapshot.trunk_heights[i] * TRUNK_HEIGHT_SCALE
		if snapshot.conifer[i] == 1:
			var height := trunk_height * CONIFER_TRUNK_SHARE + snapshot.canopy_radii[i] * CONIFER_CROWN_HEIGHT
			var size := height / PINE_REFERENCE_HEIGHT
			var variant := posmod(tree_seed / 13, pine_meshes.size())
			pine_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), foot))
			pine_colors[variant].append(PINE_TONE_A.lerp(PINE_TONE_B, tone))
			continue
		var trunk_radius := snapshot.trunk_widths[i] * TRUNK_RADIUS_SCALE * 0.5
		var crown_radius := snapshot.canopy_radii[i] * CROWN_SCALE
		trunk_transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(trunk_radius, trunk_height, trunk_radius)), foot))
		var variant := posmod(tree_seed / 13, broadleaf_meshes.size())
		broadleaf_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(crown_radius, crown_radius * 0.85, crown_radius)),
			foot + Vector3(0.0, trunk_height + crown_radius * 0.45, 0.0)))
		broadleaf_colors[variant].append(BROADLEAF_GREEN_A.lerp(BROADLEAF_GREEN_B, tone))

	var node := Node3D.new()
	node.name = "Trees"
	node.add_child(MultiMeshGroup3D.build("Trunks", [TreeTrunk3D.mesh()], [trunk_transforms], material))
	node.add_child(MultiMeshGroup3D.build("BroadleafCrowns", broadleaf_meshes, broadleaf_transforms, material, broadleaf_colors))
	# Nessun materiale sostitutivo: i pini usano i loro (corteccia e aghi con texture).
	node.add_child(MultiMeshGroup3D.build("Pines", pine_meshes, pine_transforms, null, pine_colors))
	return node


static func _get_pine_meshes() -> Array:
	if _pine_meshes.is_empty():
		_pine_meshes = ModelMesh3D.load_meshes(PINE_DIR, PINE_MODELS)
	return _pine_meshes
