class_name MultiMeshGroup3D
extends RefCounted

# Mette insieme molte copie di poche forme: una MultiMeshInstance3D per forma, tutte figlie di un nodo. Usato da tutti
# gli oggetti numerosi (rocce, sassi, e poi alberi, cespugli, erba): un disegno per forma invece di uno per oggetto.

# meshes[i] = forma i; transforms_by_mesh[i] = Array di Transform3D delle sue copie. colors_by_mesh (facoltativo):
# colors_by_mesh[i] = Array di Color, uno per copia, che moltiplica il colore dei vertici (es. il verde di ogni chioma).
static func build(node_name: String, meshes: Array, transforms_by_mesh: Array, material: Material, colors_by_mesh: Array = []) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	for i in range(meshes.size()):
		var transforms: Array = transforms_by_mesh[i]
		if transforms.is_empty():
			continue
		var colors: Array = colors_by_mesh[i] if i < colors_by_mesh.size() else []
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = not colors.is_empty()
		multimesh.mesh = meshes[i]
		multimesh.instance_count = transforms.size()
		for k in range(transforms.size()):
			multimesh.set_instance_transform(k, transforms[k])
			if not colors.is_empty():
				multimesh.set_instance_color(k, colors[k])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		node.add_child(instance)
	return node
