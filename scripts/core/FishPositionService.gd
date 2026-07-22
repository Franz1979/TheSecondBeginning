class_name FishPositionService
extends RefCounted

# STEP 1: solo SEA/LAKE (l'intera macrocella è acqua, nessuna porzione da escludere). STEP 2
# (RIVER) userà `occupied` per confinare le posizioni alla sola porzione di cella coperta da
# RiverMicrocellService.get_river_positions(), marcando come "occupato" tutto il resto —
# stesso meccanismo di esclusione già usato per stone/river_positions in MacroCellScene, solo
# invertito (qui serve escludere la terra, non l'acqua).
const NOISE_FREQUENCY: float = 0.05
const NOISE_THRESHOLD: float = 0.35


# Come VegetationPositionService (non persistito, a differenza di stone): la quantità di FISH
# cambia ogni anno per crescita (FaunaGrowthService), quindi le posizioni vanno ricalcolate a
# ogni apertura/avanzamento invece di restare fisse. Il conteggio segue water_dedicated_space
# (spazio occupato), non resource_quantity — stessa convenzione di
# VegetationPositionService.generate_positions, che usa get_dedicated_space e non
# get_resource_quantity, per non dover disegnare un'istanza per ogni singola unità di quantità.
func generate_positions(macro_state: MacroCellState, occupied: Dictionary = {}) -> Array:
	var count: int = macro_state.get_water_space(GameTypes.WorldObjectType.FISH)
	var noise_seed: int = hash(str(macro_state.micro_seed) + "_" + str(GameTypes.WorldObjectType.FISH))

	return ResourcePositionService.generate_positions(
		noise_seed, count, occupied, NOISE_FREQUENCY, NOISE_THRESHOLD
	)
