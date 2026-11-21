class_name BuildingModelsSnapshot3D
extends RefCounted

# Gli edifici di UNA cella che in 3D hanno un modello Blender (render3d/assets/models/), finiti o in cantiere: dove
# sono, verso dove guarda la porta e in che fase sono (BuildingConstructionStage, decisa dal gioco). Posizioni in
# microcelle, coordinate locali della cella. Array paralleli.

var type_names := PackedStringArray()
# Id dell'edificio (contorno di selezione, Outline3D).
var ids := PackedInt32Array()
var centers := PackedVector2Array()
# Direzione della porta come nel 2D (TentShapes.direction_vector): x = est, y = sud.
var doors := PackedVector2Array()
# BuildingConstructionStage: COMPLETE (-1), 0 = cantiere non allestito, 1..N fasi del lavoro.
var stages := PackedInt32Array()
# Quanto è piena una fossa dei rifiuti finita (WasteDisposalService.get_pit_fill / waste_capacity, tra 0 e 1); -1 per
# tutti gli altri edifici.
var fills := PackedFloat32Array()
# Carichi appesi all'essiccatoio finito, uno per posto occupato nell'ordine dei posti (BuildingModels3D.RACK_ITEMS:
# "carne", "pesce", "pelle"; "" = posto con altro); vuoto per tutti gli altri edifici.
var rack_loads: Array[PackedStringArray] = []


func size() -> int:
	return centers.size()
