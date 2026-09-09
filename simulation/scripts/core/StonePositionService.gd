class_name StonePositionService
extends RefCounted

const NOISE_FREQUENCY: float = 0.05
const NOISE_THRESHOLD: float = 0.4

# PEBBLE/sassi (2026-09-08, richiesta utente) — quantità per singola posizione di stone_positions,
# formula: 100.0 (base PEBBLE) × density_factor (get_max_density(ROCK,...) normalizzato sul
# base_density di ROCK, cioè il prodotto puro dei moltiplicatori terrain/biome/coast di QUESTA
# macrocella, riusando esattamente lo stesso get_max_density già chiamato da
# InitialResourceSetupService.populate_stone — nessun nuovo ResourceDensityRules per PEBBLE) ×
# disturbance (±20% INDIPENDENTE per singola posizione, non uniforme per l'intera macrocella —
# ogni sasso può avere un valore leggermente diverso).
const PEBBLE_BASE_QUANTITY: float = 100.0
const PEBBLE_DISTURBANCE_MIN: float = 0.8
const PEBBLE_DISTURBANCE_MAX: float = 1.2


# Genera, solo alla prima apertura di una macrocella in MacroCellScene, le posizioni
# microcella (100x100) occupate da stone. Usa macro_state.micro_seed (già deterministico
# per coordinate x,y) così la disposizione è sempre riproducibile per quella macrocella,
# senza dover generare/salvare nulla per le macrocelle mai visitate. A differenza delle
# risorse rinnovabili (vedi VegetationPositionService), qui il risultato va persistito:
# stone è potenzialmente estraibile in futuro, quindi le posizioni devono restare stabili.
#
# `cell` (MacroCellData, 2026-09-08, richiesta utente — aggiunto per PEBBLE) — serve SOLO per
# risolvere terrain_base/biome/coast_type, necessari a ResourceCalculator.get_max_density(ROCK,...)
# qui sotto: macro_state da solo non basta più (prima non serviva alcuna geografia per generare
# le sole posizioni). Entrambi i chiamanti (GameScene._activate_live_cell/MacroCellScene) hanno
# già un riferimento MacroCellData vivo esattamente accanto al macro_state passato qui (cell.
# macro_cell / macro_cell), nessun nuovo lookup necessario da parte loro.
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

	# PEBBLE — stesso istante, subito dopo che stone_positions è popolato per questa macrocella
	# (richiesta esplicita: non un servizio a sé con una propria schedulazione). density_factor è
	# lo STESSO per ogni posizione di questa macrocella (dipende solo da terrain/biome/coast della
	# cella, non dalla singola posizione) — calcolato una volta fuori dal ciclo; solo `disturbance`
	# varia per posizione.
	var rock_base_density := ResourceCalculator.get_base_density(GameTypes.WorldObjectType.ROCK)
	var rock_max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.ROCK, cell.terrain_base, cell.biome, cell.coast_type
	)
	var density_factor: float = rock_max_density / rock_base_density if rock_base_density > 0.0 else 0.0

	macro_state.pebble_quantities.clear()
	for pos in macro_state.stone_positions:
		var disturbance := randf_range(PEBBLE_DISTURBANCE_MIN, PEBBLE_DISTURBANCE_MAX)
		macro_state.pebble_quantities[pos] = int(round(PEBBLE_BASE_QUANTITY * density_factor * disturbance))
