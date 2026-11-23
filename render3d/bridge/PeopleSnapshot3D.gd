class_name PeopleSnapshot3D
extends RefCounted

# Le persone visibili, rilette a ogni fotogramma (si muovono sempre). Lo stesso oggetto si riusa ogni volta (clear()),
# niente allocazioni nuove per fotogramma. Array paralleli.

# Posizione nel mondo 3D (x, z) in microcelle, come il centro della cella più la posizione nella cella.
# Id della persona (per il passo del 3D, che segue la strada fatta da ognuna).
var ids := PackedInt32Array()
var positions := PackedVector2Array()
# Posizione in microcelle assolute del mondo (per l'altezza del terreno, GroundHeight3D).
var grounds := PackedVector2Array()
# Direzione di marcia come nel 2D (x = est, y = sud).
var facings := PackedVector2Array()
# Grandezza rispetto a un adulto maschio (età × sesso, la stessa del 2D).
var sizes := PackedFloat32Array()
# Fase del passo (0 = fermo), come la HumanIndividualView del 2D.
var walk_phases := PackedFloat32Array()
var body_colors := PackedColorArray()
var hair_colors := PackedColorArray()
# Copricapo: trasparente se non c'è.
var cap_colors := PackedColorArray()
var females := PackedByteArray()
var pregnant := PackedByteArray()
var selected := PackedByteArray()

# Morti a terra (2026-11-21, DeadBodyView del 2D): stessi pupazzi, distesi a faccia in giù. Array paralleli a parte.
# Centro del corpo (busto) come `positions`/`grounds`; `dead_heads` = direzione dalla vita alla testa (x = est, y = sud).
var dead_positions := PackedVector2Array()
var dead_grounds := PackedVector2Array()
var dead_heads := PackedVector2Array()
var dead_sizes := PackedFloat32Array()
var dead_body_colors := PackedColorArray()
var dead_hair_colors := PackedColorArray()
var dead_females := PackedByteArray()
var dead_selected := PackedByteArray()


func clear() -> void:
	ids.clear()
	positions.clear()
	grounds.clear()
	facings.clear()
	sizes.clear()
	walk_phases.clear()
	body_colors.clear()
	hair_colors.clear()
	cap_colors.clear()
	females.clear()
	pregnant.clear()
	selected.clear()
	dead_positions.clear()
	dead_grounds.clear()
	dead_heads.clear()
	dead_sizes.clear()
	dead_body_colors.clear()
	dead_hair_colors.clear()
	dead_females.clear()
	dead_selected.clear()


func size() -> int:
	return positions.size()
