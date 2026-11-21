class_name MultiMeshGroup3D
extends RefCounted

# Mette insieme molte copie di poche forme: tutte figlie di un nodo, un disegno per forma invece di uno per oggetto.
# Usato da tutti gli oggetti numerosi (rocce, sassi, alberi, cespugli, erba, mucchi...).
#
# BLOCCHI (2026-11-20, scena di prova render3d/tests/TreeStressTest: da vicino 24 -> 40 fps con 350 alberi): le copie
# sono divise in blocchi di CHUNK_SIZE x CHUNK_SIZE microcelle secondo la loro posizione, una MultiMeshInstance3D per
# blocco e per forma. Godot scarta da solo, nell'inquadratura e nelle ombre, i blocchi che non si vedono, e sceglie il
# LOD di ogni blocco secondo la sua distanza; con un MultiMesh unico grande quanto la cella disegnava sempre tutto.

const CHUNK_SIZE := 10.0

# meshes[i] = forma i; transforms_by_mesh[i] = Array di Transform3D delle sue copie (coordinate locali del nodo).
# colors_by_mesh (facoltativo): colors_by_mesh[i] = Array di Color, uno per copia, che moltiplica il colore dei vertici
# (es. il verde di ogni chioma).
# cast_shadows false: le copie non fanno ombra (2026-11-20, cespugli Quaternius: le foglie in alpha disegnate anche
# per l'ombra costano molto sulla Intel UHD, e l'ombra di un cespuglio basso si nota poco).
static func build(node_name: String, meshes: Array, transforms_by_mesh: Array, material: Material, colors_by_mesh: Array = [],
		cast_shadows := true) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	for i in range(meshes.size()):
		var transforms: Array = transforms_by_mesh[i]
		if transforms.is_empty() or meshes[i] == null:
			continue
		var colors: Array = colors_by_mesh[i] if i < colors_by_mesh.size() else []
		# blocco -> indici delle copie che ci cadono. Array normale e non PackedInt32Array: un Packed letto dal
		# Dictionary è una copia, e gli append finivano nella copia (blocchi vuoti, niente disegnato).
		var chunks: Dictionary = {}
		for k in range(transforms.size()):
			var origin: Vector3 = (transforms[k] as Transform3D).origin
			var key := Vector2i(floori(origin.x / CHUNK_SIZE), floori(origin.z / CHUNK_SIZE))
			if not chunks.has(key):
				chunks[key] = []
			(chunks[key] as Array).append(k)
		for key in chunks:
			var indices: Array = chunks[key]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = not colors.is_empty()
			multimesh.mesh = meshes[i]
			multimesh.instance_count = indices.size()
			for n in range(indices.size()):
				multimesh.set_instance_transform(n, transforms[indices[n]])
				if not colors.is_empty():
					multimesh.set_instance_color(n, colors[indices[n]])
			var instance := MultiMeshInstance3D.new()
			instance.name = "%d_%d_%d" % [i, key.x, key.y]
			instance.multimesh = multimesh
			instance.material_override = material
			if not cast_shadows:
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(instance)
	return node
