class_name Rock3D
extends RefCounted

# Oggetto 3D: le rocce (quelle della cava) di UNA macrocella. Pietre a facce piatte larghe quasi una microcella,
# nelle stesse posizioni del 2D; le esaurite non compaiono. VARIANT_COUNT forme costruite una volta sola, scelte per
# microcella come fa il 2D, poi girate e scalate un po' per roccia. Tutte le rocce di una forma = un solo disegno
# (MultiMesh).

const VARIANT_COUNT := 12
const RADIUS := 0.42
const HEIGHT_MIN := 0.35
const HEIGHT_MAX := 0.65
const SIDES := 7
const JITTER := 0.18
const SCALE_MIN := 0.9
const SCALE_MAX := 1.1
# Quanto la roccia affonda nel terreno, per non sembrare appoggiata su un piano.
const SINK := 0.05

static var _variant_meshes: Array = []


# base_global: angolo della macrocella in microcelle assolute (per l'altezza del terreno). null se non ci sono rocce.
static func build(snapshot: StoneSnapshot3D, base_global: Vector2, material: Material) -> Node3D:
	if snapshot.rock_centers.is_empty():
		return null
	_ensure_variants()
	var buckets: Array = []
	for i in range(VARIANT_COUNT):
		buckets.append([])
	for pos: Vector2i in snapshot.rock_centers:
		var center: Vector2 = snapshot.rock_centers[pos]
		var variant: int = posmod(hash(pos), VARIANT_COUNT)
		var angle := float(hash(pos * 13 + Vector2i(31, 17)) % 1000) / 1000.0 * TAU
		var size := lerpf(SCALE_MIN, SCALE_MAX, float(hash(pos * 19 + Vector2i(3, 41)) % 1000) / 1000.0)
		var y := GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y) - SINK
		var basis := Basis(Vector3.UP, angle).scaled(Vector3(size, size, size))
		buckets[variant].append(Transform3D(basis, Vector3(center.x, y, center.y)))
	return MultiMeshGroup3D.build("Rocks", _variant_meshes, buckets, material)


static func _ensure_variants() -> void:
	if not _variant_meshes.is_empty():
		return
	for variant in range(VARIANT_COUNT):
		var height := lerpf(HEIGHT_MIN, HEIGHT_MAX, float(variant % 4) / 3.0)
		_variant_meshes.append(FacetedStoneMesh.build(RADIUS, height, SIDES, JITTER, variant))
