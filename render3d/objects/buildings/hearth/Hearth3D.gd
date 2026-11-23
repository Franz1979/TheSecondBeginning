class_name Hearth3D
extends RefCounted

# Oggetto 3D: i focolari finiti di UNA macrocella (HearthSnapshot3D), uno HearthFire3D per focolare, nello stato letto
# dal gioco (acceso, braci, spento). Il cantiere non si vede, come la sagoma vera nel 2D.

# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non ci sono focolari.
static func build(snapshot: HearthSnapshot3D, base_global: Vector2, vertex_material: Material) -> Node3D:
	if snapshot.size() == 0:
		return null
	var node := Node3D.new()
	node.name = "Hearths"
	for i in range(snapshot.size()):
		var center := snapshot.centers[i]
		var hearth := HearthFire3D.new()
		var with_stones := i >= snapshot.with_stones.size() or snapshot.with_stones[i] != 0
		hearth.setup(snapshot.states[i], snapshot.seeds[i], vertex_material, with_stones)
		hearth.position = Vector3(center.x, GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y), center.y)
		node.add_child(hearth)
	return node
