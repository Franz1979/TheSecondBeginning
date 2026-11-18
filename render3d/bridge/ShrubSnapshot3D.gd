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


func size() -> int:
	return centers.size()
