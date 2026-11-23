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
# 1 = latifoglia da frutto (wild_fruit / domesticable_fruit), 0 = wood_only o conifera.
var fruit_bearing := PackedByteArray()
# 1 = domesticable_fruit (frutti rossi), 0 = wild_fruit (ghiande) o non da frutto.
var domesticable := PackedByteArray()
# 1 = frutti in vista, con la regola del 2D (non giovane, FRUITING_SEASONS, lotto non ancora raccolto: _fruit_stock_shows).
var fruit_shown := PackedByteArray()
# Stagione della cella (MicroCellRenderer.current_season): latifoglie verdi, d'autunno o spoglie, come il 2D.
var season: int = GameTypes.Season.SUMMER

# --- Ceppi (alberi tagliati, _build_tree_stump_transform del 2D): piede, larghezza del tronco tagliato, seme ---
var stump_grounds := PackedVector2Array()
var stump_widths := PackedFloat32Array()
var stump_seeds := PackedInt32Array()

# --- Alberi morti in piedi (_build_dead_tree_transform del 2D): piede, altezza del tronco morto, seme ---
var dead_grounds := PackedVector2Array()
var dead_heights := PackedFloat32Array()
var dead_seeds := PackedInt32Array()


func size() -> int:
	return grounds.size()
