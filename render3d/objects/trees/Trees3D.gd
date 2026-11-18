class_name Trees3D
extends RefCounted

# Oggetto 3D: gli alberi vivi di UNA macrocella, nelle stesse posizioni e con la stessa taglia relativa del 2D
# (TreeSnapshot3D). Tronco comune (TreeTrunk3D), chioma tonda a nuvole per le latifoglie (BroadleafCrown3D), a coni per le
# conifere (ConiferCrown3D). Il verde di ogni chioma varia un poco per albero. Stagioni e frutti: più avanti.
# Le misure del 2D sono pensate per la vista dall'alto; qui si allungano (fattori *_SCALE) per un albero adulto alto
# circa 2 microcelle con la chioma larga circa 1.

const TRUNK_HEIGHT_SCALE := 2.4
const TRUNK_RADIUS_SCALE := 0.45
const CROWN_SCALE := 1.5
const CONIFER_CROWN_SCALE := 1.5
const SINK := 0.05

const BROADLEAF_GREEN_A := Color("4d7433")
const BROADLEAF_GREEN_B := Color("6f8f3c")
const CONIFER_GREEN_A := Color("2c5232")
const CONIFER_GREEN_B := Color("3e6a3a")


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non ci sono alberi.
static func build(snapshot: TreeSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.size() == 0:
		return null
	var broadleaf_meshes := BroadleafCrown3D.meshes()
	var conifer_meshes := ConiferCrown3D.meshes()
	var trunk_transforms: Array = []
	var broadleaf_transforms: Array = []
	var broadleaf_colors: Array = []
	var conifer_transforms: Array = []
	var conifer_colors: Array = []
	for i in range(broadleaf_meshes.size()):
		broadleaf_transforms.append([])
		broadleaf_colors.append([])
	for i in range(conifer_meshes.size()):
		conifer_transforms.append([])
		conifer_colors.append([])

	for i in range(snapshot.size()):
		var ground := snapshot.grounds[i]
		var tree_seed := snapshot.seeds[i]
		var y := GroundHeight3D.land_height(base_global.x + ground.x, base_global.y + ground.y) - SINK
		var foot := Vector3(ground.x, y, ground.y)
		var yaw := float(posmod(tree_seed, 3600)) / 3600.0 * TAU
		var tone := float(posmod(tree_seed / 7, 1000)) / 1000.0
		var trunk_height := snapshot.trunk_heights[i] * TRUNK_HEIGHT_SCALE
		var trunk_radius := snapshot.trunk_widths[i] * TRUNK_RADIUS_SCALE * 0.5
		var crown_radius := snapshot.canopy_radii[i] * CROWN_SCALE
		var is_conifer := snapshot.conifer[i] == 1
		if is_conifer:
			# Il tronco si vede appena sotto i rami bassi.
			trunk_height *= 0.45
		trunk_transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(trunk_radius, trunk_height, trunk_radius)), foot))
		if is_conifer:
			var crown_scale := snapshot.canopy_radii[i] * CONIFER_CROWN_SCALE
			var variant := posmod(tree_seed / 13, conifer_meshes.size())
			conifer_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(crown_scale, crown_scale * 1.05, crown_scale)),
				foot + Vector3(0.0, trunk_height * 0.8, 0.0)))
			conifer_colors[variant].append(CONIFER_GREEN_A.lerp(CONIFER_GREEN_B, tone))
		else:
			var variant := posmod(tree_seed / 13, broadleaf_meshes.size())
			broadleaf_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(crown_radius, crown_radius * 0.85, crown_radius)),
				foot + Vector3(0.0, trunk_height + crown_radius * 0.45, 0.0)))
			broadleaf_colors[variant].append(BROADLEAF_GREEN_A.lerp(BROADLEAF_GREEN_B, tone))

	var node := Node3D.new()
	node.name = "Trees"
	node.add_child(MultiMeshGroup3D.build("Trunks", [TreeTrunk3D.mesh()], [trunk_transforms], material))
	node.add_child(MultiMeshGroup3D.build("BroadleafCrowns", broadleaf_meshes, broadleaf_transforms, material, broadleaf_colors))
	node.add_child(MultiMeshGroup3D.build("ConiferCrowns", conifer_meshes, conifer_transforms, material, conifer_colors))
	return node
