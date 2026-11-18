class_name MultiMeshGroup3D
extends RefCounted

# Mette insieme molte copie di poche forme: una MultiMeshInstance3D per forma, tutte figlie di un nodo. Usato da tutti
# gli oggetti numerosi (rocce, sassi, e poi alberi, cespugli, erba): un disegno per forma invece di uno per oggetto.

# meshes[i] = forma i; transforms_by_mesh[i] = Array di Transform3D delle sue copie.
static func build(node_name: String, meshes: Array, transforms_by_mesh: Array, material: Material) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	for i in range(meshes.size()):
		var transforms: Array = transforms_by_mesh[i]
		if transforms.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[i]
		multimesh.instance_count = transforms.size()
		for k in range(transforms.size()):
			multimesh.set_instance_transform(k, transforms[k])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		node.add_child(instance)
	return node
