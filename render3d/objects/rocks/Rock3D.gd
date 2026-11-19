class_name Rock3D
extends RefCounted

# Oggetto 3D: le rocce (quelle della cava) di UNA macrocella, larghe quasi una microcella, nelle stesse posizioni del 2D;
# le esaurite non compaiono. Forme: le 3 rocce Quaternius (CC0) con la loro texture, preparate da
# render3d/blender/scripts/rocks.py (origine al centro della base, larghezza 1). Forma scelta per microcella come fa il
# 2D, poi girata, scalata e un po' alzata per roccia. Tutte le rocce di una forma = un solo disegno (MultiMesh).

const MODEL_DIR := "res://render3d/assets/models/rocks/"
const MODELS := ["rock_medium_1", "rock_medium_2", "rock_medium_3"]
const RADIUS := 0.42
const SCALE_MIN := 0.9
const SCALE_MAX := 1.1
# I modelli sono bassi (alti ~0,4 della larghezza): un po' più alti per roccia, come le rocce di prima (0,4-0,8).
const HEIGHT_STRETCH_MIN := 1.0
const HEIGHT_STRETCH_MAX := 1.6
# Quanto la roccia affonda nel terreno, per non sembrare appoggiata su un piano.
const SINK := 0.05

static var _meshes: Array = []


# base_global: angolo della macrocella in microcelle assolute (per l'altezza del terreno). null se non ci sono rocce.
# I modelli hanno il loro materiale con texture: _material resta per uniformità con gli altri oggetti.
static func build(snapshot: StoneSnapshot3D, base_global: Vector2, _material: Material) -> Node3D:
	if snapshot.rock_centers.is_empty():
		return null
	if _meshes.is_empty():
		_meshes = ModelMesh3D.load_meshes(MODEL_DIR, MODELS)
	var buckets: Array = []
	for i in range(_meshes.size()):
		buckets.append([])
	for pos: Vector2i in snapshot.rock_centers:
		var center: Vector2 = snapshot.rock_centers[pos]
		var variant: int = posmod(hash(pos), _meshes.size())
		var angle := float(hash(pos * 13 + Vector2i(31, 17)) % 1000) / 1000.0 * TAU
		var size := lerpf(SCALE_MIN, SCALE_MAX, float(hash(pos * 19 + Vector2i(3, 41)) % 1000) / 1000.0)
		var stretch := lerpf(HEIGHT_STRETCH_MIN, HEIGHT_STRETCH_MAX, float(hash(pos * 7 + Vector2i(11, 29)) % 1000) / 1000.0)
		var width := RADIUS * 2.0 * size
		var y := GroundHeight3D.land_height(base_global.x + center.x, base_global.y + center.y) - SINK
		var basis := Basis(Vector3.UP, angle).scaled(Vector3(width, width * stretch, width))
		buckets[variant].append(Transform3D(basis, Vector3(center.x, y, center.y)))
	return MultiMeshGroup3D.build("Rocks", _meshes, buckets, null)
