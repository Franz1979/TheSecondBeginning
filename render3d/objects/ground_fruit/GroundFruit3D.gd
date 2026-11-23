class_name GroundFruit3D
extends RefCounted

# Oggetto 3D: i frutti caduti a terra (da raccogliere) di UNA macrocella, uno strato solo per tutte le risorse degli alberi
# da frutto, un modello per risorsa (2026-11-21): ghiande sotto le querce, ciliegie sotto gli alberi da frutto
# domesticabili (modelli di SOURCES_PER_GIOCO/blender/scripts/ground_fruit.py).
# Per lotto 2, 4 o 6 mucchietti (3-5 frutti l'uno) come i bastoni, secondo la quota rimasta (vedi GroundFruitSnapshot3D):
# piena (autunno) tanti, metà (inverno) normali, poca (primavera, o lotto quasi raccolto) pochi, niente se vuoto.
# Sparsi in un anello attorno al centro del lotto, sul bordo della chioma: dall'alto la chioma coprirebbe quelli sotto il
# tronco. Posizioni da hash del lotto: sempre le stesse a ogni ridisegno.

const MODEL_DIR := "res://render3d/assets/models/props/"
const MODELS_BY_RESOURCE := {
	"acorn": ["fruit_ground_acorns_a", "fruit_ground_acorns_b", "fruit_ground_acorns_c"],
	"fruit": ["fruit_ground_fruits_a", "fruit_ground_fruits_b", "fruit_ground_fruits_c"],
}
const COUNT_FEW := 2
const COUNT_NORMAL := 4
const COUNT_MANY := 6
const TIER_NORMAL_FRACTION := 0.34
const TIER_MANY_FRACTION := 0.67
const RING_MIN := 0.32    # microcelle dal centro del lotto
const RING_MAX := 0.55
const MODEL_SCALE := 0.1  # modelli in metri, 1 microcella = 10 m
const SINK := 0.003

static var _meshes_by_resource: Dictionary = {}


static func build(snapshot: GroundFruitSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	var root: Node3D = null
	for resource_name: String in snapshot.fractions_by_resource:
		if not MODELS_BY_RESOURCE.has(resource_name):
			continue
		var meshes := _get_meshes(resource_name)
		var buckets: Array = []
		for _i in range(meshes.size()):
			buckets.append([])
		var fractions: Dictionary = snapshot.fractions_by_resource[resource_name]
		for lot: Vector2i in fractions:
			var count := tier_count(float(fractions[lot]))
			for i in range(count):
				# Seme diverso per risorsa: su un lotto con quercia e albero da frutto ghiande e ciliegie non finiscono
				# negli stessi punti.
				var resource_offset := MODELS_BY_RESOURCE.keys().find(resource_name)
				var seed_base: Vector2i = lot * 37 + Vector2i(i * 11 + 3 + resource_offset * 101, i * 19 + 7 + resource_offset * 53)
				# Anello diviso in spicchi uguali: i mucchietti non si ammassano da una parte. Ogni risorsa parte da un
				# angolo diverso (mezzo spicchio), così le due serie si alternano invece di sovrapporsi.
				var angle := (float(i) + 0.5 * float(resource_offset) + float(hash(seed_base + Vector2i(5, 9)) % 1000) / 1000.0 * 0.4) / float(count) * TAU
				var dist := lerpf(RING_MIN, RING_MAX, float(hash(seed_base + Vector2i(9, 5)) % 1000) / 1000.0)
				var p := Vector2(lot) + Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * dist
				var y := GroundHeight3D.land_height(base_global.x + p.x, base_global.y + p.y) - SINK
				var yaw := float(hash(seed_base + Vector2i(13, 2)) % 1000) / 1000.0 * TAU
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * MODEL_SCALE)
				buckets[posmod(hash(seed_base), meshes.size())].append(Transform3D(basis, Vector3(p.x, y, p.y)))
		var group := MultiMeshGroup3D.build("GroundFruit_" + resource_name, meshes, buckets, material)
		if group == null:
			continue
		if root == null:
			root = Node3D.new()
			root.name = "GroundFruit"
		root.add_child(group)
	return root


static func tier_count(fraction: float) -> int:
	if fraction <= 0.0:
		return 0
	if fraction >= TIER_MANY_FRACTION:
		return COUNT_MANY
	if fraction >= TIER_NORMAL_FRACTION:
		return COUNT_NORMAL
	return COUNT_FEW


static func _get_meshes(resource_name: String) -> Array:
	if not _meshes_by_resource.has(resource_name):
		var meshes: Array = []
		for model_name in MODELS_BY_RESOURCE[resource_name]:
			meshes.append(ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".glb"))
		_meshes_by_resource[resource_name] = meshes
	return _meshes_by_resource[resource_name]
