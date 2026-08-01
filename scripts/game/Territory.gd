class_name Territory
extends RefCounted

# Insieme delle macrocelle occupate da un PopulationGroup. Step 4 del refactoring fauna:
# introduce l'entità ma la mantiene deliberatamente minima — oggi ogni gruppo occupa sempre e
# solo una cella (occupied_macrocells.size() == 1), nessuna logica di espansione/capacità
# portante/distribuzione multi-cella (prompt futuro, Step 5+). Non serializzato come .tres,
# stesso trattamento di PopulationGroup/MacroCellState — solo salvato/caricato come dato di
# partita (vedi GameSaveService/GameLoadService).
var occupied_macrocells: Array[Vector2i] = []

func _init(_occupied_macrocells: Array[Vector2i]) -> void:
	occupied_macrocells = _occupied_macrocells


# Factory per il caso di oggi: un gruppo con una sola cella (bottone debug, caricamento save).
static func from_single_cell(coords: Vector2i) -> Territory:
	return Territory.new([coords])


func get_cell_count() -> int:
	return occupied_macrocells.size()


func contains(coords: Vector2i) -> bool:
	return occupied_macrocells.has(coords)


# Punto di transizione unico per i chiamanti che oggi assumono un solo "home" per gruppo
# (rendering, debug, persistenza): oggi occupied_macrocells ha sempre esattamente un elemento,
# quindi restituisce sempre quello. Quando arriverà il multi-cella (Step 5+), si rivede solo
# questo metodo, non ogni singolo chiamante.
func get_primary_cell() -> Vector2i:
	return occupied_macrocells[0]
