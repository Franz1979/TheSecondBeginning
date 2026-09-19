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
#
# `cell` (MacroCellData, 2026-09-08, richiesta utente — aggiunto per PEBBLE) — serve SOLO per
# risolvere terrain_base/biome/coast_type, necessari a LotCapacityService.seed_stone_lot_capacity
# sotto (ResourceCalculator.get_max_density(ROCK,...)): macro_state da solo non basta più (prima
# non serviva alcuna geografia per generare le sole posizioni). Entrambi i chiamanti (GameScene.
# _activate_live_cell/MacroCellScene) hanno già un riferimento MacroCellData vivo esattamente
# accanto al macro_state passato qui (cell.macro_cell / macro_cell), nessun nuovo lookup
# necessario da parte loro.
#
# Il seeding delle risorse STONE_POSITION (pebble) — RISPOSTATO in LotCapacityService.
# seed_stone_lot_capacity (2026-09-19, refactor lot_source) — resta comunque chiamato allo STESSO
# istante, subito dopo che stone_positions è popolato per questa macrocella (richiesta esplicita
# originale: non un servizio a sé con una propria schedulazione), solo il codice che lo fa vive
# ora nel servizio generico "capacità per lotto" invece che qui.
func generate_if_needed(macro_state: MacroCellState, cell: MacroCellData) -> void:
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

	LotCapacityService.seed_stone_lot_capacity(macro_state, cell)
