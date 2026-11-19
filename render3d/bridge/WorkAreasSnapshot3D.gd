class_name WorkAreasSnapshot3D
extends RefCounted

# Le aree di lavoro da mostrare in UNA cella, come le mostra il 2D in quel momento (WorkAreaOverlay: layer acceso, sola
# zona selezionata o scelta manuale della zona; WorkAreaDragPreview: rettangolo mentre lo si trascina). Rettangoli in
# microcelle locali della cella. Array paralleli.

var rects: Array[Rect2i] = []
var colors: Array[Color] = []
# Spessore del bordo e trasparenza del riempimento, le stesse del 2D (pixel di bordo su CELL_SIZE in WorkAreas3D).
var border_widths := PackedFloat32Array()
var fill_alphas := PackedFloat32Array()
# Scritta all'angolo in alto a sinistra: nome della zona o misure del trascinamento ("7×4").
var labels := PackedStringArray()
# Icone dei lavori abilitati sotto il nome (WorkAreaOverlay.job_icon_keys), una PackedStringArray per zona.
var icons: Array[PackedStringArray] = []


func size() -> int:
	return rects.size()


func add(rect: Rect2i, color: Color, border_width: float, fill_alpha: float, label: String, icon_keys := PackedStringArray()) -> void:
	rects.append(rect)
	colors.append(color)
	border_widths.append(border_width)
	fill_alphas.append(fill_alpha)
	labels.append(label)
	icons.append(icon_keys)


# Impronta per Cell3D.needs_refresh.
func signature() -> Array:
	# Solo valori (confrontati per valore da Cell3D): niente Array nuovi, che sembrerebbero sempre cambiati.
	var signature: Array = [border_widths, fill_alphas, labels]
	for i in range(rects.size()):
		signature.append(rects[i])
		signature.append(colors[i])
		signature.append(",".join(icons[i]))
	return signature
