class_name FaunaMortalityService
extends RefCounted

# Stesso schema density-dependent self-thinning di ResourceMortalityService (fill ratio a bande
# -> moltiplicatore -> mortality_rate = growth_rate * moltiplicatore), applicato a due budget
# fisicamente separati: acqua (water_dedicated_space, FISH) e terra (terrestrial_dedicated_space,
# BIRDS) — vedi _apply_water_mortality_in_cell/_apply_land_mortality_in_cell. Fill ratio è
# sempre calcolato contro la capacità SFRUTTABILE del rispettivo dominio (get_water_
# usable_capacity_space / get_land_usable_capacity_space), non quella fisica. Nessuna gestione
# sottotipi (né FISH né BIRDS ne hanno).
const WATER_MORTAL_TYPES := [
	GameTypes.WorldObjectType.FISH,
]
const LAND_MORTAL_TYPES := [
	GameTypes.WorldObjectType.BIRDS,
]

# Stessi valori di ResourceMortalityService (vegetazione): il contenimento del banco/stormo è
# demandato a usable_capacity_ratio (vedi ResourceGrowthRules e
# ResourceCalculator.get_water_usable_capacity_space/get_land_usable_capacity_space), non a
# soglie di mortalità aggressive — con soglie basse la cella non si avvicinava mai al proprio
# tetto (fisico o sfruttabile), quindi il surplus non veniva mai generato e la migrazione restava
# inattiva. fill_ratio sotto usa la capacità SFRUTTABILE come denominatore (non quella fisica):
# mantiene la mortalità come freno secondario quando ci si avvicina/supera il proprio tetto
# ecologico (es. per pressione migratoria da celle vicine), analogo a come la mortalità terrestre
# vegetale misura il fill_ratio contro lo stesso tetto (TOTAL_SPACE) a cui punta la sua crescita.
# Condivise tra i due domini: stesse bande per FISH e BIRDS (nessuna richiesta di differenziarle).
const FILL_THRESHOLD_LOW := 0.50
const FILL_THRESHOLD_MID := 0.80
const FILL_THRESHOLD_HIGH := 0.90

const MULTIPLIER_LOW := 0.025
const MULTIPLIER_MID := 0.05
const MULTIPLIER_HIGH := 0.075


func apply_fauna_mortality(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in WATER_MORTAL_TYPES:
			_apply_water_mortality_in_cell(cell, state, resource_type)
		for resource_type in LAND_MORTAL_TYPES:
			_apply_land_mortality_in_cell(cell, state, resource_type)


func _apply_water_mortality_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType
) -> void:
	var current_space: int = state.get_water_space(resource_type)
	if current_space <= 0:
		return

	var current_quantity: int = state.get_resource_quantity(resource_type)
	if current_quantity <= 0:
		return

	var capacity := ResourceCalculator.get_water_usable_capacity_space(resource_type, cell, state)
	if capacity <= 0:
		return

	var fill_ratio: float = float(state.get_total_water_dedicated_space()) / float(capacity)
	var multiplier := _get_multiplier(fill_ratio)

	if DebugLogging.ENABLED and cell.x == 57 and cell.y == 38:
		print("[FAUNA MORTALITY 57,38] %s: fill_ratio=%.3f multiplier=%.2f" % [
			GameTypes.WorldObjectType.keys()[resource_type], fill_ratio, multiplier
		])

	if multiplier <= 0.0:
		return

	var growth_rate := ResourceCalculator.get_water_growth_rate(resource_type, cell.water_type)
	if growth_rate <= 0.0:
		return

	var mortality_rate: float = growth_rate * multiplier
	var quantity_lost: float = current_quantity * mortality_rate
	if quantity_lost <= 0.0:
		return

	var max_density := ResourceCalculator.get_water_max_density(resource_type, cell.water_type)
	if max_density <= 0.0:
		return

	var space_lost: int = min(int(round(quantity_lost / max_density)), current_space)
	if space_lost <= 0:
		return

	var new_space: int = current_space - space_lost
	var new_quantity: int = current_quantity - int(round(quantity_lost))

	if DebugLogging.ENABLED and cell.x == 57 and cell.y == 38:
		print("[FAUNA MORTALITY 57,38] %s: quantity_lost=%.3f quantity %d -> %d" % [
			GameTypes.WorldObjectType.keys()[resource_type], quantity_lost, current_quantity, max(new_quantity, 0)
		])

	state.set_water_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, max(new_quantity, 0))


# Gemella di _apply_water_mortality_in_cell sopra, sul budget terrestrial_dedicated_space:
# stessa identica formula (fill_ratio -> _get_multiplier condiviso -> mortality_rate), solo le
# funzioni/accessori sono quelli del dominio terra.
func _apply_land_mortality_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType
) -> void:
	var current_space: int = state.get_terrestrial_space(resource_type)
	if current_space <= 0:
		return

	var current_quantity: int = state.get_resource_quantity(resource_type)
	if current_quantity <= 0:
		return

	var capacity := ResourceCalculator.get_land_usable_capacity_space(resource_type, cell, state)
	if capacity <= 0:
		return

	var fill_ratio: float = float(state.get_total_terrestrial_dedicated_space()) / float(capacity)
	var multiplier := _get_multiplier(fill_ratio)
	if multiplier <= 0.0:
		return

	var growth_rate := ResourceCalculator.get_growth_rate(resource_type, cell.terrain_base, cell.biome, cell.coast_type)
	if growth_rate <= 0.0:
		return

	var mortality_rate: float = growth_rate * multiplier
	var quantity_lost: float = current_quantity * mortality_rate
	if quantity_lost <= 0.0:
		return

	var max_density := ResourceCalculator.get_max_density(resource_type, cell.terrain_base, cell.biome, cell.coast_type)
	if max_density <= 0.0:
		return

	var space_lost: int = min(int(round(quantity_lost / max_density)), current_space)
	if space_lost <= 0:
		return

	var new_space: int = current_space - space_lost
	var new_quantity: int = current_quantity - int(round(quantity_lost))

	state.set_terrestrial_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, max(new_quantity, 0))


func _get_multiplier(fill_ratio: float) -> float:
	if fill_ratio < FILL_THRESHOLD_LOW:
		return 0.0
	if fill_ratio < FILL_THRESHOLD_MID:
		return MULTIPLIER_LOW
	if fill_ratio < FILL_THRESHOLD_HIGH:
		return MULTIPLIER_MID
	return MULTIPLIER_HIGH
