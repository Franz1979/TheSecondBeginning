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
# SPEGNIMENTO DA LONTANO (2026-11-21, misura FPS): un blocco non si disegna più quando la sua copia più grande sullo
# schermo sarebbe più piccola di MIN_SCREEN_PIXELS (un puntino: ghiande, frutti a terra, sassi, bastoni, piantine da
# lontano). Distanza calcolata da sola per ogni blocco dalla misura della forma e dalla sua copia più grande: le cose
# grandi (alberi, cespugli, rocce) restano sempre accese entro lo zoom massimo. HIDE_MARGIN: tolleranza perché un blocco
# al limite non si accenda e spenga di continuo.
const MIN_SCREEN_PIXELS := 2.0
const HIDE_MARGIN := 0.1

# meshes[i] = forma i; transforms_by_mesh[i] = Array di Transform3D delle sue copie (coordinate locali del nodo).
# colors_by_mesh (facoltativo): colors_by_mesh[i] = Array di Color, uno per copia, che moltiplica il colore dei vertici
# (es. il verde di ogni chioma).
# cast_shadows false: le copie non fanno ombra (2026-11-20, cespugli Quaternius: le foglie in alpha disegnate anche
# per l'ombra costano molto sulla Intel UHD, e l'ombra di un cespuglio basso si nota poco).
# out_slots (facoltativo, 2026-11-21): out_slots[i] = Array vuoto per la forma i; vi si scrive, per ogni copia k, dove è
# finita ([MultiMesh, indice]), così chi l'ha costruita può poi spostarla o nasconderla senza rifare tutto (bacche dei
# cespugli, Shrubs3D.apply_berries).
# shadows_only (2026-11-22): le copie non si vedono e fanno solo l'ombra (sagome semplici al posto di modelli con foglie a
# ritaglio, Trees3D.SHADOW_PROXY).
static func build(node_name: String, meshes: Array, transforms_by_mesh: Array, material: Material, colors_by_mesh: Array = [],
		cast_shadows := true, out_slots: Array = [], shadows_only := false) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	for i in range(meshes.size()):
		var transforms: Array = transforms_by_mesh[i]
		if transforms.is_empty() or meshes[i] == null:
			continue
		var slots: Array = out_slots[i] if i < out_slots.size() else []
		if i < out_slots.size():
			slots.resize(transforms.size())
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
		var mesh_size: float = (meshes[i] as Mesh).get_aabb().get_longest_axis_size()
		for key in chunks:
			var indices: Array = chunks[key]
			var largest_scale := 0.0
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = not colors.is_empty()
			multimesh.mesh = meshes[i]
			multimesh.instance_count = indices.size()
			for n in range(indices.size()):
				var transform: Transform3D = transforms[indices[n]]
				multimesh.set_instance_transform(n, transform)
				var scale := transform.basis.get_scale()
				largest_scale = maxf(largest_scale, maxf(scale.x, maxf(scale.y, scale.z)))
				if i < out_slots.size():
					slots[indices[n]] = [multimesh, n]
				if not colors.is_empty():
					multimesh.set_instance_color(n, colors[indices[n]])
			var instance := MultiMeshInstance3D.new()
			instance.name = "%d_%d_%d" % [i, key.x, key.y]
			instance.multimesh = multimesh
			instance.material_override = material
			if shadows_only:
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			elif not cast_shadows:
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var hide_distance := _hide_distance(mesh_size * largest_scale)
			if hide_distance < Camera3DController.MAX_DISTANCE * 2.0:
				instance.set_meta(&"hide_distance", hide_distance) # TEMPORANEO misura FPS: per il tasto F3 di Perf3D
				if not Perf3D.far_hide_off: # TEMPORANEO misura FPS (a misura finita: sempre)
					instance.visibility_range_end = hide_distance
					instance.visibility_range_end_margin = hide_distance * HIDE_MARGIN
			node.add_child(instance)
	return node


# Distanza dalla camera oltre la quale una cosa larga `size` (unità 3D = microcelle) sullo schermo è sotto
# MIN_SCREEN_PIXELS. Godot misura la distanza dal centro del blocco: si aggiunge mezza diagonale, così nessuna copia del
# blocco sparisce prima del suo limite.
static func _hide_distance(size: float) -> float:
	var screen_height := float(DisplayServer.window_get_size().y)
	if screen_height <= 0.0:
		screen_height = 1080.0
	var pixels_per_unit_at_one := screen_height / (2.0 * tan(deg_to_rad(Camera3DController.FOV_DEG) * 0.5))
	return size * pixels_per_unit_at_one / MIN_SCREEN_PIXELS + CHUNK_SIZE * 0.71
