class_name StonePositionService
extends RefCounted

const NOISE_FREQUENCY: float = 0.05
const NOISE_THRESHOLD: float = 0.4


# Genera, solo alla prima apertura di una macrocella in MacroCellScene, le posizioni
# microcella (100x100) occupate da stone. Usa macro_state.micro_seed (già deterministico
# per coordinate x,y) così la disposizione è sempre riproducibile per quella macrocella,
# senza dover generare/salvare nulla per le macrocelle mai visitate. A differenza delle
# risorse rinnovabili (vedi VegetationPositionService), qui il risultato va persistito:
# stone è potenzialmente estraibile in futuro, quindi le posizioni devono restare stabili.
func generate_if_needed(macro_state: MacroCellState) -> void:
	if macro_state.stone_positions_generated:
		return

	var count: int = clamp(
		macro_state.get_dedicated_space(GameTypes.WorldObjectType.ROCK),
		0,
		World.WIDTH * World.HEIGHT
	)

	macro_state.stone_positions = ResourcePositionService.generate_positions(
		macro_state.micro_seed, count, {}, NOISE_FREQUENCY, NOISE_THRESHOLD
	)
	macro_state.stone_positions_generated = true
