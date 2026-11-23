class_name PebbleCircle3D
extends RefCounted

# Oggetto 3D: i cerchi di sassi finiti di UNA macrocella. Come il 2D (MicroCellRenderer._draw_pebble_circle):
# PEBBLE_CIRCLE_PEBBLE_COUNT sassolini chiari equidistanti su un anello di raggio PEBBLE_CIRCLE_RING_RADIUS, alla
# stessa misura del 2D (già largo quasi tutta la microcella: allargato uscirebbe dalla cella). Sassi piatti a facce piatte (FacetedStoneMesh), poche forme fisse; ogni sasso
# girato, scalato e spostato un poco. Tutti i sassi di una forma = un solo disegno (MultiMesh).

# Spento il 2026-11-21 (richiesta utente): il cerchio è ora il modello Blender (BuildingModels3D.MODELS["pebble_circle"],
# SOURCES_PER_GIOCO/blender/scripts/pebble_circle.py), con lo stesso stile e più sassi più piccoli. true = com'era prima.
const SHOW := false
const SCALE := 1.0
const STONE_SIZE := 0.05
const STONE_HEIGHT_RATIO := 0.5
const VARIANTS := 4
# Quanto il sasso affonda nel terreno.
const SINK := 0.01

static var _meshes: Array = []


# base_global: angolo della cella in microcelle assolute (per l'altezza del terreno). null se non ci sono cerchi.
static func build(snapshot: BuildingPlacesSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if not SHOW or snapshot.size() == 0:
		return null
	_ensure_meshes()
	var transforms: Array = []
	for i in range(VARIANTS):
		transforms.append([])
	var cell_size := float(MicroCellRenderer.CELL_SIZE)
	var ring_radius := MicroCellRenderer.PEBBLE_CIRCLE_RING_RADIUS / cell_size * SCALE
	var count := MicroCellRenderer.PEBBLE_CIRCLE_PEBBLE_COUNT
	for i in range(snapshot.size()):
		var center := snapshot.centers[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = snapshot.seeds[i]
		for k in range(count):
			var angle := TAU * k / count + rng.randf_range(-0.04, 0.04)
			var radius := ring_radius * rng.randf_range(0.97, 1.03)
			var local := center + Vector2(cos(angle), sin(angle)) * radius
			var size := STONE_SIZE * rng.randf_range(0.85, 1.2)
			var y := GroundHeight3D.land_height(base_global.x + local.x, base_global.y + local.y) - SINK
			transforms[rng.randi_range(0, VARIANTS - 1)].append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size * 1.15)), Vector3(local.x, y, local.y)))
	return MultiMeshGroup3D.build("PebbleCircles", _meshes, transforms, material)


static func _ensure_meshes() -> void:
	if not _meshes.is_empty():
		return
	for variant in range(VARIANTS):
		_meshes.append(FacetedStoneMesh.build(1.0, STONE_HEIGHT_RATIO * 2.0, 6, 0.3, 500 + variant,
			MicroCellRenderer.PEBBLE_CIRCLE_COLOR))
