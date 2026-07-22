class_name FaunaGrowthService
extends RefCounted

# Servizio indipendente dalla pipeline vegetale (ResourceGrowthService/Encroachment/Migration/
# Mortality, che gira su dedicated_space con lo schema "seed bank" a due tempi stagionali):
# niente encroachment né rinvio all'anno successivo. Growth/migration/mortality per FISH restano
# tre checkpoint stagionali separati (vedi WorldTimeService: fine primavera/estate/autunno),
# ciascuno nel proprio servizio (FaunaGrowthService/FaunaMigrationService/FaunaMortalityService).
# Nome generico ("Fauna", non "Fish") perché FISH non sarà probabilmente l'unica risorsa non
# vegetale a usare questa forma di pipeline in futuro; l'implementazione oggi gestisce solo FISH
# (GROWABLE_TYPES), senza generalizzare oltre il bisogno concreto attuale.
const GROWABLE_TYPES := [
	GameTypes.WorldObjectType.FISH,
]


func grow_fauna(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in GROWABLE_TYPES:
			_grow_resource_in_cell(cell, state, resource_type)


func _grow_resource_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType
) -> void:
	# Capacità sfruttabile (usable_capacity_ratio), non fisica: la crescita satura verso questo
	# tetto ridotto, non verso TOTAL_SPACE/river_space — vedi
	# ResourceCalculator.get_water_usable_capacity_space.
	var capacity := ResourceCalculator.get_water_usable_capacity_space(resource_type, cell, state)
	if capacity <= 0:
		return

	var current_space: int = state.get_water_space(resource_type)
	if current_space <= 0:
		return

	var growth_rate := ResourceCalculator.get_water_growth_rate(resource_type, cell.water_type)
	if growth_rate <= 0.0:
		return

	var empty_space: int = state.get_empty_water_space(capacity)
	var max_reachable_space: int = current_space + empty_space
	if max_reachable_space <= 0:
		return

	var new_space_float: float = current_space + growth_rate * current_space * (1.0 - float(current_space) / float(max_reachable_space))
	var new_space: int = int(round(min(new_space_float, max_reachable_space)))

	var max_density := ResourceCalculator.get_water_max_density(resource_type, cell.water_type)
	var new_quantity: int = int(round(new_space * max_density))

	state.set_water_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, new_quantity)
