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
# "carne", "pesce", "pelle"; "" = posto con altro); per l'affumicatoio finito i carichi uno dopo l'altro, senza buchi
# (BuildingModels3D.SMOKEHOUSE_SLOTS); vuoto per tutti gli altri edifici.
var rack_loads: Array[PackedStringArray] = []
# Pezzi a parte, già al loro posto nel modello, secondo quello che c'è davvero: la catasta dell'affumicatoio finito per il
# combustibile che ha (BuildingModels3D.SMOKEHOUSE_FUEL_PILES), gli attrezzi pronti dell'attrezzeria finita
# (BuildingModels3D.TOOLMAKER_TOOL_BY_RESOURCE); vuoto per tutti gli altri edifici.
var fuel_piles: Array[PackedStringArray] = []
# Vicini di un edificio lineare (il vallo), come li calcola il 2D ("linear_neighbors": bit 1 << lato, N E S O); 0 per gli
# altri edifici.
var linear_masks := PackedInt32Array()
# Cantiere con i detriti dei ceppi ancora da portare via ("site_debris" del 2D): sopra ci vanno le macerie
# (BuildingModels3D.RUBBLE_TYPE), come nel 2D; false per tutti gli altri.
var site_debris: Array[bool] = []


func size() -> int:
	return centers.size()
