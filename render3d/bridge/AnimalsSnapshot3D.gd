class_name AnimalsSnapshot3D
extends RefCounted

# Gli animali visibili (selvatici, di passaggio, domestici, condotti), riletti a ogni fotogramma come le persone. Lo
# stesso oggetto si riusa ogni volta (clear()). Array paralleli.

# Id dell'animale (unico in tutto il gioco, per il passo che segue la strada fatta).
var ids := PackedInt32Array()
# Specie selvatica della sagoma (anche per i domestici: cane = "wolf", come nel 2D).
var species := PackedStringArray()
# Posizione nel mondo 3D (x, z) in microcelle.
var positions := PackedVector2Array()
# Posizione in microcelle assolute del mondo (altezza del terreno).
var grounds := PackedVector2Array()
# Direzione di marcia come nel 2D (x = est, y = sud).
var facings := PackedVector2Array()
# Lunghezza della sagoma 2D (coda e orecchie comprese) in microcelle, già con la grandezza per età.
var lengths := PackedFloat32Array()
# Colore della sagoma 2D (i domestici col loro colore).
var colors := PackedColorArray()
var selected := PackedByteArray()


func clear() -> void:
	ids.clear()
	species.clear()
	positions.clear()
	grounds.clear()
	facings.clear()
	lengths.clear()
	colors.clear()
	selected.clear()


func size() -> int:
	return positions.size()
