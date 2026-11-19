class_name SelectionSnapshot3D
extends RefCounted

# Cosa è selezionato (o sotto il mouse) dentro UNA cella, preso dalle selezioni del 2D (MicroCellRenderer._selected_*):
# aloni a terra attorno agli oggetti (edifici, alberi, cespugli, rocce), quadrati sulle microcelle (ispezione, lotto di
# bastoni) e gli edifici col modello Blender da contornare. Microcelle, coordinate locali della cella.

# Intensità: SELECTED = selezionato, HOVER = sotto il mouse (più leggero).
const SELECTED := 1.0
const HOVER := 0.45

var halo_centers := PackedVector2Array()
var halo_radii := PackedFloat32Array()
var halo_strengths := PackedFloat32Array()
var squares: Array[Vector2i] = []
var selected_building_id: int = -1
var hovered_building_id: int = -1


func is_empty() -> bool:
	return halo_centers.is_empty() and squares.is_empty()


# Impronta per Cell3D.needs_refresh.
func signature() -> Array:
	var signature: Array = [halo_centers, halo_radii, halo_strengths, selected_building_id, hovered_building_id]
	signature.append_array(squares)
	return signature
