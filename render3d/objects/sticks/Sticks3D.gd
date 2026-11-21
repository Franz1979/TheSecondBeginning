class_name Sticks3D
extends RefCounted

# Oggetto 3D: i bastoni a terra (da raccogliere) di UNA macrocella. Quanti e dove: la stessa regola del 2D
# (MicroCellRenderer._stick_tier_count e _stick_lot_transforms), copiata qui con gli stessi numeri e gli stessi hash,
# così 2D e 3D coincidono: 2, 4 o 6 bastoni per lotto, sparsi attorno al centro del lotto, stessa rotazione e lunghezza.
# Forme: tre bastoni (dritto, forcella, storto) di SOURCES_PER_GIOCO/blender/scripts/ground_sticks.py, lunghi 1 lungo X e
# appoggiati a terra; la forma la sceglie il seme del bastone.

const MODEL_DIR := "res://render3d/assets/models/props/"
const MODELS := ["stick_ground_dritto", "stick_ground_forcella", "stick_ground_storto"]
const SINK := 0.005

static var _meshes: Array = []


static func build(snapshot: SticksSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.quantities.is_empty():
		return null
	if _meshes.is_empty():
		for model_name in MODELS:
			_meshes.append(ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".glb"))
	var buckets: Array = [[], [], []]
	var px := float(MicroCellRenderer.CELL_SIZE)
	var half := px / 2.0
	for lot: Vector2i in snapshot.quantities:
		var count := tier_count(int(snapshot.quantities[lot]))
		var ground := Vector2(lot.x * px + half, lot.y * px + half)
		for i in range(count):
			# Come MicroCellRenderer._stick_lot_transforms (pixel del 2D).
			var seed_base: Vector2i = lot * 31 + Vector2i(i * 9 + 2, i * 17 + 5)
			var angle: float = (float(hash(seed_base + Vector2i(7, 3)) % 1000) / 1000.0) * TAU
			var dist: float = MicroCellRenderer.STICK_SCATTER_RADIUS * (float(hash(seed_base + Vector2i(3, 7)) % 1000) / 1000.0)
			var rotation: float = (float(hash(seed_base + Vector2i(11, 13)) % 1000) / 1000.0) * TAU
			var length_scale: float = lerpf(MicroCellRenderer.STICK_LENGTH_VARIATION_MIN, MicroCellRenderer.STICK_LENGTH_VARIATION_MAX,
				float(hash(seed_base + Vector2i(13, 11)) % 1000) / 1000.0)
			var p := (ground + Vector2(cos(angle), sin(angle)) * dist) / px
			var length := MicroCellRenderer.STICK_HALF_LENGTH * 2.0 * length_scale / px
			var y := GroundHeight3D.land_height(base_global.x + p.x, base_global.y + p.y) - SINK
			# Rotazione del 2D (y in giù) attorno alla verticale del 3D: segno opposto.
			var basis := Basis(Vector3.UP, -rotation).scaled(Vector3.ONE * length)
			buckets[posmod(hash(seed_base), MODELS.size())].append(Transform3D(basis, Vector3(p.x, y, p.y)))
	return MultiMeshGroup3D.build("Sticks", _meshes, buckets, material)


static func tier_count(quantity: int) -> int:
	if quantity <= 0:
		return 0
	if quantity > MicroCellRenderer.STICK_TIER_MANY_THRESHOLD:
		return MicroCellRenderer.STICK_COUNT_MANY
	if quantity > MicroCellRenderer.STICK_TIER_NORMAL_THRESHOLD:
		return MicroCellRenderer.STICK_COUNT_NORMAL
	return MicroCellRenderer.STICK_COUNT_FEW
