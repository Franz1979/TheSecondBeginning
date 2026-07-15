class_name ResourceMortalityService
extends RefCounted

const MORTAL_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
]

const FILL_THRESHOLD_LOW := 0.50
const FILL_THRESHOLD_MID := 0.80
const FILL_THRESHOLD_HIGH := 0.90

const MULTIPLIER_LOW := 0.025
const MULTIPLIER_MID := 0.05
const MULTIPLIER_HIGH := 0.075


func apply_mortality(world: World) -> void:
	var ordered_types := ResourceCalculator.get_types_ordered_by_succession(MORTAL_TYPES)

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in ordered_types:
			_apply_mortality_in_cell(cell, state, resource_type)


func _apply_mortality_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType
) -> void:
	var current_space: int = state.get_dedicated_space(resource_type)
	if current_space <= 0:
		return

	var current_quantity: int = state.get_resource_quantity(resource_type)
	if current_quantity <= 0:
		return

	# Fill ratio is whole-cell (all resources + river), read fresh so a resource
	# processed later in the same cell/year sees space freed by an earlier one.
	var fill_ratio: float = float(state.get_total_dedicated_space()) / float(MacroCellState.TOTAL_SPACE)
	var multiplier := _get_multiplier(fill_ratio)

	if cell.x == 50 and cell.y == 50:
		print("[MORTALITY 50,50] %s: fill_ratio=%.3f multiplier=%.2f dedicated_space=%d quantity=%d" % [
			GameTypes.WorldObjectType.keys()[resource_type], fill_ratio, multiplier, current_space, current_quantity
		])

	if multiplier <= 0.0:
		return

	var growth_rate := ResourceCalculator.get_growth_rate(
		resource_type, cell.terrain_base, cell.biome, cell.coast_type
	)
	if growth_rate <= 0.0:
		return

	# Mortality mirrors growth's own rate (already per-resource/terrain/biome scaled)
	# rather than a separate tuned field, so fast growers thin out faster and slow
	# growers stay stable, same as growth without needing a matching absolute cap.
	var mortality_rate: float = growth_rate * multiplier
	var quantity_lost: float = current_quantity * mortality_rate
	if quantity_lost <= 0.0:
		return

	var max_density := ResourceCalculator.get_max_density(
		resource_type, cell.terrain_base, cell.biome, cell.coast_type
	)
	if max_density <= 0.0:
		return

	var space_lost: int = min(int(round(quantity_lost / max_density)), current_space)
	if space_lost <= 0:
		return

	var new_space: int = current_space - space_lost
	var new_quantity: int = current_quantity - int(round(quantity_lost))

	if cell.x == 50 and cell.y == 50:
		print("[MORTALITY 50,50] %s: growth_rate=%.4f mortality_rate=%.4f quantity_lost=%.3f space %d -> %d | quantity -> %d" % [
			GameTypes.WorldObjectType.keys()[resource_type], growth_rate, mortality_rate, quantity_lost,
			current_space, new_space, max(new_quantity, 0)
		])

	state.set_dedicated_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, max(new_quantity, 0))


func _get_multiplier(fill_ratio: float) -> float:
	if fill_ratio < FILL_THRESHOLD_LOW:
		return 0.0
	if fill_ratio < FILL_THRESHOLD_MID:
		return MULTIPLIER_LOW
	if fill_ratio < FILL_THRESHOLD_HIGH:
		return MULTIPLIER_MID
	return MULTIPLIER_HIGH
