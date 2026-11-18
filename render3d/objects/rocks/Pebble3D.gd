class_name Pebble3D
extends RefCounted

# Oggetto 3D: i sassi (pebble, da raccogliere) di UNA macrocella. Piccole pietre a facce, un po' schiacciate, sparse
# attorno alle rocce. Quanti e dove: la stessa regola del 2D (MicroCellRenderer._pebble_tier_count e
# _rebuild_pebble_multimeshes), copiata qui con gli stessi numeri e gli stessi hash, così 2D e 3D coincidono.

const VARIANT_COUNT := 6
const RADIUS_MIN := 0.045
const RADIUS_MAX := 0.07
# Altezza rispetto alla mezza larghezza: più schiacciati delle rocce.
const HEIGHT_RATIO := 0.75
const SIDES := 5
const JITTER := 0.2
# Fasce di quantità del 2D: oltre MANY -> COUNT_MANY sassi, da NORMAL -> COUNT_NORMAL, sotto -> COUNT_FEW.
const TIER_MANY_THRESHOLD := 100
const TIER_NORMAL_THRESHOLD := 50
const COUNT_FEW := 4
const COUNT_NORMAL := 8
const COUNT_MANY := 14
# Distanza dal centro della roccia, in microcelle (2D: 3,6-4,2 px).
const SCATTER_MIN := 0.36
const SCATTER_MAX := 0.42
const SINK := 0.01

static var _variant_meshes: Array = []


static func build(snapshot: StoneSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.pebble_quantities.is_empty():
		return null
	_ensure_variants()
	var buckets: Array = []
	for i in range(VARIANT_COUNT):
		buckets.append([])
	for pos: Vector2i in snapshot.all_centers:
		var count := tier_count(int(snapshot.pebble_quantities.get(pos, 0)))
		if count <= 0:
			continue
		var center: Vector2 = snapshot.all_centers[pos]
		for i in range(count):
			var seed_base: Vector2i = pos * 23 + Vector2i(i * 7 + 1, i * 13 + 4)
			var variant: int = posmod(hash(seed_base), VARIANT_COUNT)
			var angle := float(hash(seed_base + Vector2i(3, 9)) % 1000) / 1000.0 * TAU
			var dist := lerpf(SCATTER_MIN, SCATTER_MAX, float(hash(seed_base + Vector2i(9, 3)) % 1000) / 1000.0)
			var p := center + Vector2(cos(angle), sin(angle)) * dist
			var rotation := float(hash(seed_base + Vector2i(5, 17)) % 1000) / 1000.0 * TAU
			var size := lerpf(0.85, 1.15, float(hash(seed_base + Vector2i(17, 5)) % 1000) / 1000.0)
			var y := GroundHeight3D.land_height(base_global.x + p.x, base_global.y + p.y) - SINK
			var basis := Basis(Vector3.UP, rotation).scaled(Vector3(size, size, size))
			buckets[variant].append(Transform3D(basis, Vector3(p.x, y, p.y)))
	return MultiMeshGroup3D.build("Pebbles", _variant_meshes, buckets, material)


static func tier_count(quantity: int) -> int:
	if quantity <= 0:
		return 0
	if quantity > TIER_MANY_THRESHOLD:
		return COUNT_MANY
	if quantity >= TIER_NORMAL_THRESHOLD:
		return COUNT_NORMAL
	return COUNT_FEW


static func _ensure_variants() -> void:
	if not _variant_meshes.is_empty():
		return
	for variant in range(VARIANT_COUNT):
		var radius := lerpf(RADIUS_MIN, RADIUS_MAX, float(variant) / float(VARIANT_COUNT - 1))
		_variant_meshes.append(FacetedStoneMesh.build(radius, radius * HEIGHT_RATIO, SIDES, JITTER, 100 + variant))
