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


func size() -> int:
	return positions.size()
