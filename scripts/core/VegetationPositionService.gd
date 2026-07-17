class_name VegetationPositionService
extends RefCounted

# Frequency/threshold per tipo: GRASS diffusa e quasi "riempitiva" (macchie ampie, soglia
# permissiva), SHRUB intermedia (stessi valori di partenza di stone), TREE concentrata in
# boschetti densi e ben distinti (macchie piccole, soglia selettiva).
const NOISE_PARAMS := {
	GameTypes.WorldObjectType.TREE: {"frequency": 0.07, "threshold": 0.45},
	GameTypes.WorldObjectType.SHRUB: {"frequency": 0.05, "threshold": 0.4},
	GameTypes.WorldObjectType.GRASS: {"frequency": 0.03, "threshold": 0.3},
}

# Ordine di rivendicazione delle celle: dal tipo dominante (TREE) al più diffuso (GRASS),
# così ciascuno prenota le celle migliori del proprio campo di noise prima che il successivo
# scelga tra quelle rimaste libere — nessuna vera contesa, solo una sequenza di priorità.
const CLAIM_ORDER := [
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.GRASS,
]


# A differenza di stone, queste posizioni NON vanno mai persistite: quantità e disposizione
# di grass/shrub/tree cambiano ogni anno (growth/encroachment/mortality/migration), quindi
# vanno ricalcolate a ogni apertura della scena a partire dalle quantità correnti. `occupied`
# è opzionale: passare le posizioni stone già generate per non disegnare vegetazione sopra
# le rocce.
func generate_positions(macro_state: MacroCellState, occupied: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}

	for resource_type in CLAIM_ORDER:
		var count: int = macro_state.get_dedicated_space(resource_type)
		var params: Dictionary = NOISE_PARAMS[resource_type]
		var noise_seed: int = hash(str(macro_state.micro_seed) + "_" + str(resource_type))

		result[resource_type] = ResourcePositionService.generate_positions(
			noise_seed, count, occupied, params["frequency"], params["threshold"]
		)

	return result
