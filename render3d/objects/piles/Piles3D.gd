class_name Piles3D
extends RefCounted

# Oggetto 3D: i mucchietti SEGNAPOSTO delle scorte di UNA cella (StoragePilesSnapshot3D). Un solo modello neutro per forma
# (render3d/blender/scripts/pile.py: cumulo, fagotti, sacchi), colorato per risorsa col colore del gioco
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

static var _meshes: Array = []
static var _shape_by_resource: Dictionary = {}


# base_global: angolo della cella in microcelle assolute (altezza del terreno). null se non ci sono mucchietti.
static func build(snapshot: StoragePilesSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.size() == 0:
		return null
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
