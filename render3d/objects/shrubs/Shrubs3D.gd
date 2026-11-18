class_name Shrubs3D
extends RefCounted

# Oggetto 3D: i cespugli di UNA macrocella, nelle stesse posizioni e con le stesse bolle del 2D (ShrubSnapshot3D).
# - Cespuglio solo legno: "macchia", una cupola bassa fatta delle bolle del 2D (ShrubBlob3D, stesso stile delle chiome
#   degli alberi), schiacciate.
# - Cespuglio da frutto: "rovo", le stesse bolle più tralci ad arco con qualche foglia (ShrubCanes3D).
# - Cespuglio tagliato: solo tralci spogli (come i rovi del 2D).
# Il colore di ogni bolla è quello del 2D (verde-bruno), scurito un poco verso il verde delle chiome. Bacche e stagioni:
# più avanti.

# Le misure del 2D sono pensate per la vista dall'alto: qui si allargano come le chiome (Trees3D.CROWN_SCALE).
const SPREAD_SCALE := 1.5
const BLOB_SCALE := 1.5
const BLOB_SQUASH := 0.62
# Quanto la bolla resta sotto terra (frazione dell'altezza): la cupola sembra uscire dal suolo.
const BLOB_SINK := 0.35
const CANE_SCALE := 1.15
const CUT_SCALE := 1.6
const COLOR_TOWARD := Color("4f6e2e")
const COLOR_TOWARD_AMOUNT := 0.35


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non c'è niente.
static func build(snapshot: ShrubSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.size() == 0 and snapshot.cut_centers.is_empty():
		return null
	var blob_meshes := ShrubBlob3D.meshes()
	var leafy_meshes := ShrubCanes3D.leafy_meshes()
	var bare_meshes := ShrubCanes3D.bare_meshes()
	var blob_transforms := _empty_lists(blob_meshes.size())
	var blob_colors := _empty_lists(blob_meshes.size())
	var leafy_transforms := _empty_lists(leafy_meshes.size())
	var bare_transforms := _empty_lists(bare_meshes.size())

	for i in range(snapshot.size()):
		var center := snapshot.centers[i]
		var shrub_seed := snapshot.seeds[i]
		var yaw := float(posmod(shrub_seed, 3600)) / 3600.0 * TAU
		var extent := 0.0
		for b in range(snapshot.blob_starts[i], snapshot.blob_starts[i + 1]):
			var offset := (snapshot.blob_centers[b] - center) * SPREAD_SCALE
			var radius := snapshot.blob_radii[b] * BLOB_SCALE
			extent = maxf(extent, offset.length() + radius)
			var ground := center + offset
			var height := radius * BLOB_SQUASH
			var y := _height(base_global, ground) + height * (1.0 - BLOB_SINK)
			var variant := posmod(shrub_seed / 13 + b, blob_meshes.size())
			blob_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw + b).scaled(Vector3(radius, height, radius)),
				Vector3(ground.x, y, ground.y)))
			var color := snapshot.blob_colors[b].lerp(COLOR_TOWARD, COLOR_TOWARD_AMOUNT)
			color.a = 1.0
			blob_colors[variant].append(color)
		if snapshot.fruit_bearing[i] == 1 and extent > 0.0:
			var reach := extent * CANE_SCALE
			var variant := posmod(shrub_seed / 17, leafy_meshes.size())
			leafy_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(reach, reach * 0.8, reach)),
				Vector3(center.x, _height(base_global, center), center.y)))

	for i in range(snapshot.cut_centers.size()):
		var center := snapshot.cut_centers[i]
		var cut_seed := snapshot.cut_seeds[i]
		var reach := snapshot.cut_radii[i] * CUT_SCALE
		var yaw := float(posmod(cut_seed, 3600)) / 3600.0 * TAU
		var variant := posmod(cut_seed / 13, bare_meshes.size())
		bare_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(reach, reach, reach)),
			Vector3(center.x, _height(base_global, center), center.y)))

	var node := Node3D.new()
	node.name = "Shrubs"
	node.add_child(MultiMeshGroup3D.build("Blobs", blob_meshes, blob_transforms, material, blob_colors))
	node.add_child(MultiMeshGroup3D.build("Canes", leafy_meshes, leafy_transforms, material))
	node.add_child(MultiMeshGroup3D.build("CutCanes", bare_meshes, bare_transforms, material))
	return node


static func _height(base_global: Vector2, local: Vector2) -> float:
	return GroundHeight3D.land_height(base_global.x + local.x, base_global.y + local.y)


static func _empty_lists(count: int) -> Array:
	var lists: Array = []
	for i in range(count):
		lists.append([])
	return lists
