class_name TreeSnapshot3D
extends RefCounted

# Gli alberi vivi di una cella come li disegna il 2D (MicroCellRenderer._compute_tree_visual), in forma semplice per il
# 3D. Misure in microcelle (pixel del 2D / CELL_SIZE), posizioni in coordinate locali della cella. Array paralleli.

var grounds := PackedVector2Array()
var trunk_heights := PackedFloat32Array()
var trunk_widths := PackedFloat32Array()
var canopy_radii := PackedFloat32Array()
# Seme fisso per individuo (rotazione, variante di forma, sfumatura di colore).
var seeds := PackedInt32Array()
var conifer := PackedByteArray()


func size() -> int:
	return grounds.size()
