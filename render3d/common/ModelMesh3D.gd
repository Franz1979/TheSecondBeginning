class_name ModelMesh3D
extends RefCounted

# Carica la forma (Mesh) di un modello Blender/Quaternius (.glb o .gltf in render3d/assets/models/), una volta sola per
# percorso. Con la forma sola gli oggetti numerosi la usano nei MultiMesh; i materiali (anche con texture) restano
# nelle superfici della forma.

static var _cache: Dictionary = {} # percorso -> Mesh (null se non si carica)


static func load_mesh(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	var mesh: Mesh = null
	var scene := load(path) as PackedScene
	if scene != null:
		var node := scene.instantiate()
		var found := first_mesh_instance(node)
		if found != null:
			mesh = found.mesh
		node.free()
	if mesh == null:
		push_warning("ModelMesh3D: modello mancante o vuoto: %s" % path)
	_cache[path] = mesh
	return mesh


# Forme di più modelli della stessa cartella, nell'ordine dei nomi (estensione compresa nel suffisso).
static func load_meshes(folder: String, names: Array, extension := ".gltf") -> Array:
	var meshes: Array = []
	for model_name in names:
		meshes.append(load_mesh(folder + model_name + extension))
	return meshes


static func first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := first_mesh_instance(child)
		if found != null:
			return found
	return null
