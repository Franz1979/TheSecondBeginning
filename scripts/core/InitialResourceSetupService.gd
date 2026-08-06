class_name InitialResourceSetupService
extends RefCounted

const MIN_STONE_MICROCELLS: int = 50
const MAX_STONE_MICROCELLS: int = 500
const MIN_TREE_MICROCELLS: int = 50
const MAX_TREE_MICROCELLS: int = 500
const MIN_GRASS_MICROCELLS: int = 50
const MAX_GRASS_MICROCELLS: int = 200
const MIN_SHRUB_MICROCELLS: int = 50
const MAX_SHRUB_MICROCELLS: int = 200
const RIVER_SPACE: int = 3000
# Range condiviso da ogni risorsa "fauna" (oggi FISH su acqua, BIRDS su terra — vedi
# populate_fish/populate_birds sotto): una cella che supera il tiro di presence_chance parte
# comunque popolata solo a questa frazione della propria capacità, mai piena.
const MIN_FAUNA_SEED_CAPACITY_RATIO: float = 0.02
const MAX_FAUNA_SEED_CAPACITY_RATIO: float = 0.06


func populate_resources(world: World) -> void:
	reserve_river_space(world)
	populate_fish(world)
	populate_birds(world)
	populate_stone(world)
	populate_trees(world)
	populate_grass(world)
	populate_shrub(world)


# Come stone/trees/grass/shrub sotto: tira get_water_presence_chance (asse WaterType, vedi
# ResourceCalculator) e, se supera il tiro, assegna una quantità. Il tetto resta comunque la
# capacità fisica d'acqua della cella (ResourceCalculator.get_water_capacity_space) — il tiro di
# presenza decide SE la cella riceve FISH, la capacità decide QUANTO al massimo.
func populate_fish(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var capacity := ResourceCalculator.get_water_capacity_space(cell, state)
		if capacity <= 0:
			continue

		var chance := ResourceCalculator.get_water_presence_chance(GameTypes.WorldObjectType.FISH, cell.water_type)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_water_max_density(GameTypes.WorldObjectType.FISH, cell.water_type)
		if max_density <= 0.0:
			continue

		var dedicated_space: int = int(round(capacity * randf_range(MIN_FAUNA_SEED_CAPACITY_RATIO, MAX_FAUNA_SEED_CAPACITY_RATIO)))
		if dedicated_space <= 0:
			continue
		var quantity: int = int(round(max_density * dedicated_space))

		state.set_water_space(GameTypes.WorldObjectType.FISH, dedicated_space)
		state.set_resource_quantity(GameTypes.WorldObjectType.FISH, quantity)


# Gemella di populate_fish sopra, sul budget terrestrial_dedicated_space: gate su capacità di
# terra libera dal fiume (ResourceCalculator.get_land_capacity_space) E su un tiro di
# get_presence_chance (asse Terrain/Biome/Coast, la stessa già usata da get_max_density — nessuna
# funzione "water" gemella necessaria qui, a differenza di FISH).
func populate_birds(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var capacity := ResourceCalculator.get_land_capacity_space(cell, state)
		if capacity <= 0:
			continue

		var chance := ResourceCalculator.get_presence_chance(
			GameTypes.WorldObjectType.BIRDS, cell.terrain_base, cell.biome, cell.coast_type
		)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_max_density(
			GameTypes.WorldObjectType.BIRDS, cell.terrain_base, cell.biome, cell.coast_type
		)
		if max_density <= 0.0:
			continue

		var dedicated_space: int = int(round(capacity * randf_range(MIN_FAUNA_SEED_CAPACITY_RATIO, MAX_FAUNA_SEED_CAPACITY_RATIO)))
		if dedicated_space <= 0:
			continue
		var quantity: int = int(round(max_density * dedicated_space))

		state.set_terrestrial_space(GameTypes.WorldObjectType.BIRDS, dedicated_space)
		state.set_resource_quantity(GameTypes.WorldObjectType.BIRDS, quantity)


func reserve_river_space(world: World) -> void:
	var river_count := 0
	for cell in world.cells:
		if cell.water_type == GameTypes.WaterType.RIVER:
			river_count += 1
			var state := world.get_cell_state_at(cell.x, cell.y)
			if state != null:
				state.set_river_space(RIVER_SPACE)

# Stessa forma per stone/trees/grass/shrub: per ogni cella della mappa, tira get_presence_chance
# (bioma/terreno/coast-driven, dai .tres di resource_density) e, se supera il tiro, assegna una
# quantità random in [MIN,MAX]_*_MICROCELLS capata allo spazio libero residuo della cella. Prima di
# questa versione, trees/grass/shrub seminavano solo la cella hardcoded (50,50) ("TEST
# TEMPORANEO") mentre stone restava confinato a un riquadro 10x10 di test — entrambi residui di
# sviluppo iniziale. Ordine di chiamata (stone, poi trees, grass, shrub — vedi populate_resources)
# invariato: ogni tipo consuma get_empty_space() al momento della propria chiamata, quindi chi
# gira prima ha priorità sullo spazio libero condiviso della cella, esattamente come già avveniva.
func populate_stone(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var chance := ResourceCalculator.get_presence_chance(
			GameTypes.WorldObjectType.ROCK, cell.terrain_base, cell.biome, cell.coast_type
		)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_max_density(
			GameTypes.WorldObjectType.ROCK, cell.terrain_base, cell.biome, cell.coast_type
		)
		if max_density <= 0.0:
			continue

		var available_space: int = state.get_empty_space()
		if available_space <= 0:
			continue

		var max_possible: int = min(MAX_STONE_MICROCELLS, available_space)
		var min_possible: int = min(MIN_STONE_MICROCELLS, max_possible)
		var dedicated_microcells: int = randi_range(min_possible, max_possible)
		var quantity: int = int(round(max_density * dedicated_microcells))

		state.set_resource_quantity(GameTypes.WorldObjectType.ROCK, quantity)
		state.set_dedicated_space(GameTypes.WorldObjectType.ROCK, dedicated_microcells)

	print("Stone popolato sull'intera mappa")


func populate_trees(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var chance := ResourceCalculator.get_presence_chance(
			GameTypes.WorldObjectType.TREE, cell.terrain_base, cell.biome, cell.coast_type
		)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_max_density(
			GameTypes.WorldObjectType.TREE, cell.terrain_base, cell.biome, cell.coast_type
		)
		if max_density <= 0.0:
			continue

		var available_space: int = state.get_empty_space()
		if available_space <= 0:
			continue

		var max_possible: int = min(MAX_TREE_MICROCELLS, available_space)
		var min_possible: int = min(MIN_TREE_MICROCELLS, max_possible)
		var dedicated_microcells: int = randi_range(min_possible, max_possible)
		var quantity: int = int(round(max_density * dedicated_microcells))

		state.set_resource_quantity(GameTypes.WorldObjectType.TREE, quantity)
		state.set_dedicated_space(GameTypes.WorldObjectType.TREE, dedicated_microcells)
		_seed_subtype_composition(state, GameTypes.WorldObjectType.TREE, cell.biome, dedicated_microcells)

	print("Trees popolato sull'intera mappa")


func populate_grass(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var chance := ResourceCalculator.get_presence_chance(
			GameTypes.WorldObjectType.GRASS, cell.terrain_base, cell.biome, cell.coast_type
		)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_max_density(
			GameTypes.WorldObjectType.GRASS, cell.terrain_base, cell.biome, cell.coast_type
		)
		if max_density <= 0.0:
			continue

		var available_space: int = state.get_empty_space()
		if available_space <= 0:
			continue

		var max_possible: int = min(MAX_GRASS_MICROCELLS, available_space)
		var min_possible: int = min(MIN_GRASS_MICROCELLS, max_possible)
		var dedicated_microcells: int = randi_range(min_possible, max_possible)
		var quantity: int = int(round(max_density * dedicated_microcells))

		state.set_resource_quantity(GameTypes.WorldObjectType.GRASS, quantity)
		state.set_dedicated_space(GameTypes.WorldObjectType.GRASS, dedicated_microcells)

	print("Grass popolato sull'intera mappa")


func populate_shrub(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var chance := ResourceCalculator.get_presence_chance(
			GameTypes.WorldObjectType.SHRUB, cell.terrain_base, cell.biome, cell.coast_type
		)
		if randf() > chance:
			continue

		var max_density := ResourceCalculator.get_max_density(
			GameTypes.WorldObjectType.SHRUB, cell.terrain_base, cell.biome, cell.coast_type
		)
		if max_density <= 0.0:
			continue

		var available_space: int = state.get_empty_space()
		if available_space <= 0:
			continue

		var max_possible: int = min(MAX_SHRUB_MICROCELLS, available_space)
		var min_possible: int = min(MIN_SHRUB_MICROCELLS, max_possible)
		var dedicated_microcells: int = randi_range(min_possible, max_possible)
		var quantity: int = int(round(max_density * dedicated_microcells))

		state.set_resource_quantity(GameTypes.WorldObjectType.SHRUB, quantity)
		state.set_dedicated_space(GameTypes.WorldObjectType.SHRUB, dedicated_microcells)
		_seed_subtype_composition(state, GameTypes.WorldObjectType.SHRUB, cell.biome, dedicated_microcells)

	print("Shrub popolato sull'intera mappa")


# Semina la composizione iniziale dei sottotipi (se registrati per resource_type) in proporzione
# a initial_ratio_by_biome del bioma della cella. Se nessun sottotipo ha un rapporto positivo per
# quel bioma (biome non coperto nei dati), ripiega su pesi uguali per non lasciare
# sum(subtype_composition) disallineato da dedicated_space appena assegnato sopra.
func _seed_subtype_composition(
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	biome: GameTypes.Biome,
	total_space: int
) -> void:
	var subtype_rules := ResourceCalculator.get_subtype_rules(resource_type)
	if subtype_rules.is_empty() or total_space <= 0:
		return

	var weights := ResourceCalculator.get_initial_ratio_subtype_weights(resource_type, biome)
	var split := state.apply_subtype_space_delta(resource_type, total_space, weights)
	_seed_age_band_composition(state, resource_type, subtype_rules, split)


# Per i sottotipi con track_age_bands=true, semina age_composition secondo
# SubtypeRules.initial_age_ratio invece che 100% YOUNG (il gain "sempre YOUNG" vale solo per la
# simulazione a regime — vedi MacroCellState.add_age_band_gain — un mondo nuovo può partire già
# come un ecosistema stabilito). Ratio assente/tutta a 0 => pesi uguali tra le tre fasce, stesso
# fallback di initial_ratio_by_biome sopra.
func _seed_age_band_composition(
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	subtype_rules: Array,
	split: Dictionary
) -> void:
	var rules_by_name: Dictionary = {}
	for rule in subtype_rules:
		rules_by_name[rule.subtype_name] = rule

	for subtype_name in split.keys():
		var rule: SubtypeRules = rules_by_name.get(subtype_name)
		if rule == null or not rule.track_age_bands:
			continue
		var subtype_space: int = int(split[subtype_name])
		if subtype_space <= 0:
			continue

		var age_weights: Dictionary = {}
		for age_band in [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]:
			var ratio: float = float(rule.initial_age_ratio.get(age_band, 0.0))
			if ratio > 0.0:
				age_weights[age_band] = ratio
		if age_weights.is_empty():
			for age_band in [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]:
				age_weights[age_band] = 1.0

		state.seed_age_band_composition(resource_type, subtype_name, subtype_space, age_weights)
