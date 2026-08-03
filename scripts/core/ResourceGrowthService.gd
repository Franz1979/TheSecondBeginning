class_name ResourceGrowthService
extends RefCounted

const GROWABLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
]


func grow_resources(world: World, game_data: GameData) -> void:
	# Growth deliberately reverses the shared ascending-succession order (used as-is by
	# encroachment/migration/mortality): each type's growth is capped by empty_space read
	# fresh at call time, so whichever type grows first claims the cell's freed space first.
	# Highest succession (TREE) goes first here so the climax type gets first claim on newly
	# freed space, matching real succession (mature stands hold ground rather than losing it
	# back to pioneer species every year). Temporary fix — will need rethinking once growth
	# moves to day-granularity/seasons.
	var ordered_types := ResourceCalculator.get_types_ordered_by_succession(GROWABLE_TYPES)
	ordered_types.reverse()

	var current_absolute_day := game_data.get_absolute_day()
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in ordered_types:
			_grow_resource_in_cell(world, cell, state, resource_type, current_absolute_day)


func _grow_resource_in_cell(
	world: World,
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	current_absolute_day: int
) -> void:
	var current_space: int = state.get_dedicated_space(resource_type)

	#print("DEBUG growth cella (", cell.x, ",", cell.y, ") current_space=", current_space)

	var growth_rate := ResourceCalculator.get_growth_rate(
		resource_type,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	#print("DEBUG growth_rate=", growth_rate)
	if growth_rate <= 0.0:
		return

	growth_rate *= state.get_active_growth_multiplier(current_absolute_day)

	var empty_space: int = state.get_empty_space()
	var max_reachable_space: int = current_space + empty_space
	#print("DEBUG empty_space=", empty_space, " max_reachable=", max_reachable_space)
	if max_reachable_space <= 0:
		return

	var new_space_float: float = current_space + growth_rate * current_space * (1.0 - float(current_space) / float(max_reachable_space))
	var new_space: int = int(round(min(new_space_float, max_reachable_space)))
	#print("DEBUG new_space_float=", new_space_float, " new_space=", new_space)

	# Floor di ricrescita minima ("seed rain"): la logistica pura sopra resta a 0 per sempre una
	# volta che current_space tocca 0 (proporzionale a se stessa). Banche di semi/radici residue
	# garantiscono almeno 1 microcella equivalente di ricrescita per checkpoint quando c'è ancora
	# spazio libero — ma SOLO se questa cella ha già ospitato questa risorsa in passato
	# (has_ever_grown): una radura mai popolata dal world generator deve poter restare a 0
	# all'infinito, il floor non deve mai crearla dal nulla. Si applica dopo il gate di idoneità
	# bioma/terrain sopra (growth_rate <= 0.0 già uscito) e non supera mai lo spazio libero
	# (max_reachable_space): max(), mai addizione, così non gonfia una crescita già sana.
	if state.has_resource_ever_grown(resource_type):
		var floor_space: int = min(1, max_reachable_space - current_space)
		if floor_space > 0 and (new_space - current_space) < floor_space:
			new_space = current_space + floor_space

	var max_density := ResourceCalculator.get_max_density(
		resource_type,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	var new_quantity: int = int(round(new_space * max_density))
	#print("DEBUG new_quantity=", new_quantity)

	if DebugLogging.ENABLED and cell.x == 50 and cell.y == 50:
		print("[GROWTH 50,50] %s: space %d -> %d | quantity -> %d" % [
			GameTypes.WorldObjectType.keys()[resource_type], current_space, new_space, new_quantity
		])

	var subtype_weights := ResourceCalculator.get_biome_weighted_subtype_composition(resource_type, state, cell.biome)
	# Composizione locale interamente a zero (tipico di una cella che riparte dal floor sopra,
	# dopo essere stata svuotata su tutti i sottotipi): nessuna proporzione locale da cui pesare
	# la ripartizione. Ricade sugli stessi pesi initial_ratio_by_biome usati alla generazione del
	# mondo, invece di lasciare dedicated_space e subtype_composition disallineati (vedi
	# ResourceCalculator.get_initial_ratio_subtype_weights). Se resource_type non ha sottotipi
	# (es. GRASS) get_initial_ratio_subtype_weights torna {} e il comportamento resta invariato.
	if subtype_weights.is_empty() and new_space > current_space:
		subtype_weights = ResourceCalculator.get_initial_ratio_subtype_weights(resource_type, cell.biome)
	var gain_split := state.apply_subtype_space_delta(resource_type, new_space - current_space, subtype_weights)
	_apply_age_band_gains(resource_type, state, gain_split)
	state.set_dedicated_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, new_quantity)


# Le nuove unità di crescita sono sempre "nate" quest'anno (età 0): finiscono per intero in
# YOUNG, mai spostando individui già maturi — solo per i sottotipi con track_age_bands=true
# (oggi solo SHRUB), no-op per gli altri.
func _apply_age_band_gains(resource_type: GameTypes.WorldObjectType, state: MacroCellState, split: Dictionary) -> void:
	for subtype_name in split.keys():
		var rule := ResourceCalculator.get_subtype_rule(resource_type, subtype_name)
		if rule == null or not rule.track_age_bands:
			continue
		state.add_age_band_gain(resource_type, subtype_name, int(split[subtype_name]))
