class_name Piles3D
extends RefCounted

# Oggetto 3D: i mucchietti SEGNAPOSTO delle scorte di UNA cella (StoragePilesSnapshot3D). Un solo modello neutro per forma
# (SOURCES_PER_GIOCO/blender/scripts/pile.py: cumulo, fagotti, sacchi), colorato per risorsa col colore del gioco
# (IconRegistry.get_resource_color) come colore dell'istanza; un MultiMesh per forma. La forma dipende dal tipo di risorsa:
# sacchi per cibo, granaglie e medicinali, fagotti per lavorati, attrezzi e vestiario, cumulo per le materie prime.
# Quando una risorsa avrà il suo mucchio vero, avrà qui la sua forma e le altre restano col segnaposto.

const MODEL_DIR := "res://render3d/assets/models/props/"
const SHAPES := ["pile_cumulo", "pile_fagotti", "pile_sacchi"]
const CUMULO := 0
const FAGOTTI := 1
const SACCHI := 2
const MODEL_SCALE := 0.1
const SCALE_JITTER := 0.12

# Carcasse (SOURCES_PER_GIOCO/blender/scripts/carcass.py): lunghe 1, pelo chiaro tinto dal colore della specie.
const CARCASS_DIR := "res://render3d/assets/models/animals/carcass/"
const CARCASS_MODELS := ["carcass_quadruped", "carcass_bird"]

static var _meshes: Array = []
static var _carcass_meshes: Array = []
static var _shape_by_resource: Dictionary = {}


# base_global: angolo della cella in microcelle assolute (altezza del terreno). null se non ci sono mucchietti.
static func build(snapshot: StoragePilesSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Piles"
	if snapshot.size() > 0:
		root.add_child(_build_piles(snapshot, base_global, material))
	if not snapshot.carcass_positions.is_empty():
		root.add_child(_build_carcasses(snapshot, base_global))
	return root


static func _build_piles(snapshot: StoragePilesSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	var meshes := _get_meshes()
	var transforms: Array = [[], [], []]
	var colors: Array = [[], [], []]
	for i in range(snapshot.size()):
		var position := snapshot.positions[i]
		var name := snapshot.resource_names[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = snapshot.seeds[i]
		var shape := shape_for(name)
		var y := GroundHeight3D.land_height(base_global.x + position.x, base_global.y + position.y)
		var size := MODEL_SCALE * snapshot.scales[i] * (1.0 + (rng.randf() - 0.5) * 2.0 * SCALE_JITTER)
		# Modelli Blender: Z in alto = Y in Godot (l'import glTF lo fa già); qui solo un giro attorno all'asse verticale.
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
		transforms[shape].append(Transform3D(basis, Vector3(position.x, y, position.y)))
		colors[shape].append(IconRegistry.get_resource_color(name))
	return MultiMeshGroup3D.build("Piles", meshes, transforms, material, colors)


# Carcasse: modello lungo 1 (testa verso +X) scalato alla lunghezza del 2D e girato come il 2D attorno alla verticale.
static func _build_carcasses(snapshot: StoragePilesSnapshot3D, base_global: Vector2) -> Node3D:
	var transforms: Array = [[], []]
	var colors: Array = [[], []]
	for i in range(snapshot.carcass_positions.size()):
		var position := snapshot.carcass_positions[i]
		var kind := int(snapshot.carcass_bird[i])
		var y := GroundHeight3D.land_height(base_global.x + position.x, base_global.y + position.y)
		var basis := Basis(Vector3.UP, -snapshot.carcass_rotations[i]).scaled(Vector3.ONE * snapshot.carcass_lengths[i])
		transforms[kind].append(Transform3D(basis, Vector3(position.x, y, position.y)))
		colors[kind].append(snapshot.carcass_colors[i])
	return MultiMeshGroup3D.build("Carcasses", _get_carcass_meshes(), transforms, null, colors)


# Forme delle carcasse con i materiali del pelo che prendono il colore dell'istanza (vertex_color_use_as_albedo); sangue,
# zoccoli e becco restano del loro colore.
static func _get_carcass_meshes() -> Array:
	if _carcass_meshes.is_empty():
		for model_name in CARCASS_MODELS:
			var mesh := ModelMesh3D.load_mesh(CARCASS_DIR + model_name + ".gltf")
			if mesh != null:
				mesh = mesh.duplicate() as Mesh
				for s in range(mesh.get_surface_count()):
					var surface_material := mesh.surface_get_material(s) as BaseMaterial3D
					if surface_material != null and (surface_material.resource_name.contains("Fur") or surface_material.resource_name.contains("Belly")):
						surface_material = surface_material.duplicate() as BaseMaterial3D
						surface_material.vertex_color_use_as_albedo = true
						mesh.surface_set_material(s, surface_material)
			_carcass_meshes.append(mesh)
	return _carcass_meshes


# Forma del mucchietto per una risorsa, dalla sua categoria (SecondaryResourceRules.category); cumulo se sconosciuta.
static func shape_for(resource_name: String) -> int:
	if _shape_by_resource.has(resource_name):
		return _shape_by_resource[resource_name]
	var shape := CUMULO
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules != null:
		match rules.category:
			SecondaryResourceTypes.Category.FOOD, SecondaryResourceTypes.Category.GRAIN, SecondaryResourceTypes.Category.MEDICINAL:
				shape = SACCHI
			SecondaryResourceTypes.Category.SEMI_FINISHED, SecondaryResourceTypes.Category.TOOL, SecondaryResourceTypes.Category.APPAREL:
				shape = FAGOTTI
	_shape_by_resource[resource_name] = shape
	return shape


static func _get_meshes() -> Array:
	if _meshes.is_empty():
		for model_name in SHAPES:
			_meshes.append(ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".glb"))
	return _meshes
