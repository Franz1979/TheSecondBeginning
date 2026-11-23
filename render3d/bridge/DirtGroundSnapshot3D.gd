class_name DirtGroundSnapshot3D
extends RefCounted

# Le mattonelle dell'edificio "Terra battuta" di una cella (e, se BEATEN_UNDER_BUILDINGS, la terra sotto gli altri edifici), come le disegna il 2D: microcella e lati che
# confinano con un altro fondo o edificio ("dirt_neighbors", bit 1 << lato, ordine N, E, S, O). Array paralleli.

var positions: Array[Vector2i] = []
var neighbor_masks := PackedByteArray()
# Quanto è battuta, tra 0 e 1: 1 = finita; in cantiere = lavoro fatto (BuildingConstructionStage.labor_progress).
var strengths := PackedFloat32Array()
# Quanto è più scura, tra 0 e 1 (es. sotto il sito di deposito): canale G della maschera, letto dallo shader.
var shades := PackedFloat32Array()
# 1 = mattonella dell'edificio "Terra battuta" (marrone scuro nel 3D), 0 = terra sotto un altro edificio (chiara):
# canale B della maschera (2026-11-21, richiesta utente).
var tiles := PackedByteArray()


func size() -> int:
	return positions.size()
