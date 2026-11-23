class_name ShrubSnapshot3D
extends RefCounted

# I cespugli di una cella come li disegna il 2D (MicroCellRenderer._compute_shrub_geometry e
# _build_shrub_stump_transform), in forma semplice per il 3D. Misure in microcelle (pixel del 2D / CELL_SIZE),
# posizioni in coordinate locali della cella. Array paralleli.

# --- Cespugli vivi: uno per individuo ---
var centers := PackedVector2Array()
# Seme fisso per individuo (rotazione, variante di forma).
var seeds := PackedInt32Array()
# 1 = cespuglio da frutto (rovo, coi tralci), 0 = solo legno (macchia).
var fruit_bearing := PackedByteArray()
# Solo per i cespugli da frutto, con le regole del 2D (stagione, età, raccolta): FRUIT_FLOWERS in primavera, FRUIT_BERRIES
# in estate e autunno se le bacche di quel cespuglio sono ancora da raccogliere, FRUIT_BARE altrimenti (raccolte,
# cespuglio giovane, inverno). 0 per i cespugli solo legno.
const FRUIT_FLOWERS := 0
const FRUIT_BERRIES := 1
const FRUIT_BARE := 2
var fruit_state := PackedByteArray()
# Cespugli che in questa stagione possono avere le bacche (da frutto, adulti, estate o autunno): indice in centers,
# individuo e jitter del 2D. Con questi, quando si raccolgono o ricrescono le bacche, si cambiano solo loro
# (GameStateReader.shrub_berries_shown, Shrubs3D.apply_berries) invece di rifare tutti i cespugli della cella.
var berry_index := PackedInt32Array()
var berry_keys: Array = [] # Vector3i
var berry_jitters: Array = [] # Vector2i
# Bolle del 2D dell'individuo: dove iniziano in blob_* (blob_starts[i] .. blob_starts[i + 1]).
var blob_starts := PackedInt32Array()

# --- Bolle (lobi del 2D), di tutti i cespugli in fila ---
var blob_centers := PackedVector2Array()
var blob_radii := PackedFloat32Array()
var blob_colors := PackedColorArray()

# --- Cespugli tagliati (rovi spogli del 2D) ---
var cut_centers := PackedVector2Array()
var cut_radii := PackedFloat32Array()
var cut_seeds := PackedInt32Array()

# --- Cespugli morti (pianta secca del 2D, _build_dead_marker_transform) ---
var dead_centers := PackedVector2Array()
var dead_radii := PackedFloat32Array()
var dead_seeds := PackedInt32Array()


func size() -> int:
	return centers.size()
