extends Node

# Verifica una tantum (non un tool permanente): costruisce un mondo sintetico in memoria (nessuna
# mappa salvata da caricare) con un mix noto di celle acqua/ostili/normali + un branco predatore
# (wolf) sintetico con territorio multi-cella, poi chiama
# FirstStartMacroCellSelectionService.select_starting_cell più volte con tutte e quattro le
# combinazioni di exclude_hostile_zones/exclude_predator_territories (fascia di ricchezza fissa a
# NORMAL), per vedere a schermo il log della cella scelta e verificare che i criteri vengano
# rispettati. In coda verifica anche le tre fasce di ricchezza (RICH/NORMAL/POOR) con la formula
# reale di CellRichnessCalculator: un controllo diretto sui punteggi (cella ricca vs povera) e un
# controllo sul tiering completo (la cella nota per essere ricca non deve MAI uscire dalle fasce
# NORMAL/POOR, per costruzione — non solo statisticamente improbabile).

const TRIALS := 20
# La formula di ricchezza ora fa lavoro vero per candidata (CaloricCalculator su piu' fonti x
# stagioni, non piu' uno stub O(1)) — sul mondo grande (~9900 candidate di terra) ogni estrazione
# ricalcola l'intero batch, quindi poche prove bastano per verificare filtri/tiering senza far
# durare il tool minuti. Le sezioni su mondi piccoli (poche decine di celle) restano a TRIALS.
const BIG_WORLD_TRIALS := 3
const PREDATOR_TERRITORY_CELLS: Array[Vector2i] = [
	Vector2i(50, 50), Vector2i(51, 50), Vector2i(52, 50),
	Vector2i(50, 51), Vector2i(51, 51), Vector2i(52, 51),
]
# Territorio di un branco rabbit (erbivoro, popolazione > 0 su ogni cella tramite
# get_population_by_cell/pesi uguali di default) usato per esercitare
# guarantee_animal_presence — disgiunto da PREDATOR_TERRITORY_CELLS cosi' i due filtri restano
# indipendenti nei test.
const ANIMAL_PRESENT_CELLS: Array[Vector2i] = [
	Vector2i(20, 20), Vector2i(21, 20), Vector2i(20, 21),
]


func _ready() -> void:
	var world := _build_synthetic_world()

	print("=== Mondo sintetico: %d celle totali ===" % world.cells.size())
	_print_cell_counts(world)

	for exclude_hostile in [false, true]:
		for exclude_predator in [false, true]:
			print("\n=== exclude_hostile_zones=%s exclude_predator_territories=%s (%d estrazioni) ===" % [
				exclude_hostile, exclude_predator, BIG_WORLD_TRIALS
			])
			_run_trials(world, exclude_hostile, exclude_predator, "NORMAL", BIG_WORLD_TRIALS)

	print("\n=== guarantee_animal_presence=true (isolato, %d estrazioni) ===" % BIG_WORLD_TRIALS)
	_run_trials(world, false, false, "NORMAL", BIG_WORLD_TRIALS, true)

	print("\n=== guarantee_animal_presence=true combinato con exclude_hostile/exclude_predator (%d estrazioni) ===" % BIG_WORLD_TRIALS)
	_run_trials(world, true, true, "NORMAL", BIG_WORLD_TRIALS, true)

	print("\n=== Fasce di ricchezza (RICH/NORMAL/POOR), pool grande (mondo intero, nessun filtro) ===")
	for preference in ["RICH", "NORMAL", "POOR"]:
		_run_trials(world, false, false, preference, BIG_WORLD_TRIALS)

	print("\n=== Fasce di ricchezza, pool piccolo (< 30 candidate, esercita il fallback a terzi) ===")
	var small_world := _build_small_candidate_world()
	for preference in ["RICH", "NORMAL", "POOR"]:
		_run_trials(small_world, false, false, preference)

	_check_richness_scoring()
	_check_richness_tiering_deterministic()

	print("\n=== Fine verifica ===")
	get_tree().quit()


# Verifica diretta di CellRichnessCalculator.evaluate_richness_batch: una cella "ricca" (albero
# da frutto wild_fruit al massimo + una popolazione erbivora) deve avere un punteggio
# nettamente superiore a una cella "povera" (nessuna risorsa). Non verifica i numeri esatti
# (i pesi/valori sono soggetti a ritaratura), solo l'ordinamento — che e' l'unica cosa che conta
# per il tiering.
func _check_richness_scoring() -> void:
	print("\n=== Verifica diretta punteggi ricchezza (cella ricca vs povera) ===")

	var world := World.new()
	world.cells.clear()
	world.cell_states.clear()
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var cell := MacroCellData.new(x, y)
			cell.terrain_base = GameTypes.TerrainBase.PLAIN
			cell.biome = GameTypes.Biome.GRASSLAND
			world.cells.append(cell)
			world.cell_states.append(MacroCellState.new(x, y))

	var rich_pos := Vector2i(10, 10)
	var poor_pos := Vector2i(90, 90)
	_seed_rich_cell(world, rich_pos)

	var scores := CellRichnessCalculator.new().evaluate_richness_batch(world, [rich_pos, poor_pos])
	var rich_score: float = scores[rich_pos]
	var poor_score: float = scores[poor_pos]
	print("  ricca (%d,%d) = %.2f -- povera (%d,%d) = %.2f" % [rich_pos.x, rich_pos.y, rich_score, poor_pos.x, poor_pos.y, poor_score])

	if rich_score > poor_score:
		print("OK: la cella ricca ha punteggio superiore alla povera.")
	else:
		push_error("MISMATCH: la cella ricca (%.2f) non supera la povera (%.2f)." % [rich_score, poor_score])


# Popola pos con TREE al massimo (dedicated_space pieno) + una popolazione rabbit interamente
# ospitata li' — copre sia la componente vegetale che quella animale della formula in un colpo
# solo. Il sottotipo va seminato tramite InitialResourceSetupService._seed_subtype_composition
# (stesso punto d'ingresso usato dalla generazione mondo reale, riusato qui per istanza esattamente
# come fa ParametricResourceSetupService) e NON con una apply_subtype_space_delta diretta: solo
# quel percorso semina anche age_composition, letta dalla formula calorica per i sottotipi con
# track_age_bands=true (wild_fruit/domesticable_fruit lo sono) — senza age_composition il
# contributo vegetale risultava 0, bug scoperto proprio grazie a questo test dopo la
# normalizzazione (prima mascherato dalla scala enorme della componente vegetale rispetto alle
# altre due).
func _seed_rich_cell(world: World, pos: Vector2i) -> void:
	var cell := world.get_cell_at(pos.x, pos.y)
	var state := world.get_cell_state_at(pos.x, pos.y)

	state.set_dedicated_space(GameTypes.WorldObjectType.TREE, MacroCellState.TOTAL_SPACE)
	state.set_resource_quantity(GameTypes.WorldObjectType.TREE, MacroCellState.TOTAL_SPACE)
	InitialResourceSetupService.new()._seed_subtype_composition(
		state, GameTypes.WorldObjectType.TREE, cell.biome, MacroCellState.TOTAL_SPACE
	)

	var rabbit_group := PopulationGroup.new()
	rabbit_group.id = world.allocate_population_group_id()
	rabbit_group.species_name = "rabbit"
	rabbit_group.population = 50
	rabbit_group.territory = Territory.from_single_cell(pos)
	world.population_groups.append(rabbit_group)


# Verifica il tiering completo su un mondo piccolo (9 candidate di terra, < 30 -> fallback a
# terzi, tier_size=3): una sola cella e' nota per essere ricca (le altre 8 restano a punteggio
# 0), quindi dopo l'ordinamento discendente finisce SEMPRE all'indice 0 -> rientra SEMPRE nella
# fascia RICH (i primi 3) e non puo' MAI rientrare in NORMAL (i 3 centrali) o POOR (gli ultimi
# 3) — non una probabilita' bassa, un'impossibilita' per costruzione. Verificato su piu' prove
# per escludere errori di indicizzazione nel taglio delle fasce.
func _check_richness_tiering_deterministic() -> void:
	print("\n=== Verifica tiering deterministico (cella ricca mai in NORMAL/POOR) ===")

	var world := World.new()
	world.cells.clear()
	world.cell_states.clear()
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var cell := MacroCellData.new(x, y)
			if x < 3 and y < 3:
				cell.terrain_base = GameTypes.TerrainBase.PLAIN
				cell.biome = GameTypes.Biome.GRASSLAND
			else:
				cell.terrain_base = GameTypes.TerrainBase.WATER
				cell.water_type = GameTypes.WaterType.SEA
			world.cells.append(cell)
			world.cell_states.append(MacroCellState.new(x, y))

	var rich_pos := Vector2i(1, 1)
	_seed_rich_cell(world, rich_pos)

	var service := FirstStartMacroCellSelectionService.new()
	var violations := 0
	const DETERMINISTIC_TRIALS := 30
	for preference in ["NORMAL", "POOR"]:
		for i in range(DETERMINISTIC_TRIALS):
			var pos := service.select_starting_cell(world, false, false, preference)
			if pos == rich_pos:
				violations += 1

	if violations == 0:
		print("OK: la cella ricca non e' mai stata scelta sotto preferenza NORMAL/POOR su %d prove ciascuna." % DETERMINISTIC_TRIALS)
	else:
		push_error("MISMATCH: la cella ricca e' stata scelta %d volte sotto NORMAL/POOR (dovrebbe essere impossibile)." % violations)

	var rich_hits := 0
	for i in range(DETERMINISTIC_TRIALS):
		var pos := service.select_starting_cell(world, false, false, "RICH")
		if pos == rich_pos:
			rich_hits += 1
	print("  cella ricca scelta %d/%d volte sotto preferenza RICH (atteso: >0, un terzo delle celle nella fascia)." % [rich_hits, DETERMINISTIC_TRIALS])
	if rich_hits == 0:
		push_error("MISMATCH: la cella ricca non e' mai stata scelta nemmeno sotto preferenza RICH.")


func _run_trials(
	world: World,
	exclude_hostile_zones: bool,
	exclude_predator_territories: bool,
	resource_richness_preference: String,
	trials: int = TRIALS,
	guarantee_animal_presence: bool = false
) -> void:
	var service := FirstStartMacroCellSelectionService.new()
	var mismatches := 0

	for i in range(trials):
		var pos := service.select_starting_cell(
			world, exclude_hostile_zones, exclude_predator_territories, resource_richness_preference,
			guarantee_animal_presence
		)
		var cell := world.get_cell_at(pos.x, pos.y)
		var is_hostile := _is_hostile(cell)
		var is_water := cell.terrain_base == GameTypes.TerrainBase.WATER
		var is_predator := PREDATOR_TERRITORY_CELLS.has(pos)
		var is_animal_present := ANIMAL_PRESENT_CELLS.has(pos)

		if exclude_hostile_zones and (is_hostile or is_water):
			mismatches += 1
		if exclude_predator_territories and is_predator:
			mismatches += 1
		if guarantee_animal_presence and not is_animal_present:
			mismatches += 1

		print("  [%02d] (%d,%d) terrain=%s biome=%s coast=%s predatore=%s animali=%s -- %s" % [
			i,
			pos.x, pos.y,
			GameTypes.TerrainBase.keys()[cell.terrain_base],
			GameTypes.Biome.keys()[cell.biome],
			GameTypes.CoastType.keys()[cell.coast_type],
			is_predator,
			is_animal_present,
			"OSTILE" if is_hostile else ("ACQUA" if is_water else ("PREDATORE" if is_predator else "OK")),
		])

	if exclude_hostile_zones or exclude_predator_territories or guarantee_animal_presence:
		if mismatches == 0:
			print("OK: nessuna estrazione ha violato i filtri attivi su %d prove." % trials)
		else:
			push_error("MISMATCH: %d/%d estrazioni hanno violato i filtri attivi." % [mismatches, trials])


# Mondo piccolo (5x5 = 25 celle, tutta terra normale, nessun predatore) — meno di
# TIER_MIN_CANDIDATES_FOR_FIXED_SIZE (30) candidate, per esercitare il ramo di fallback a terzi
# proporzionali di _pick_cell_by_richness_tier invece del taglio fisso a 10.
func _build_small_candidate_world() -> World:
	var world := World.new()
	world.cells.clear()
	world.cell_states.clear()

	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var cell := MacroCellData.new(x, y)
			if x < 5 and y < 5:
				cell.terrain_base = GameTypes.TerrainBase.PLAIN
				cell.biome = GameTypes.Biome.GRASSLAND
			else:
				cell.terrain_base = GameTypes.TerrainBase.WATER
				cell.water_type = GameTypes.WaterType.SEA
			world.cells.append(cell)
			world.cell_states.append(MacroCellState.new(x, y))

	return world


# Stessa nozione di "ostile" di FirstStartMacroCellSelectionService._is_hostile, reimplementata
# qui apposta per verificare il servizio dall'esterno come un consumatore indipendente, invece di
# chiamare un metodo interno (prefisso _) della classe sotto test.
func _is_hostile(cell: MacroCellData) -> bool:
	if cell.terrain_base == GameTypes.TerrainBase.MOUNTAIN:
		return true
	if cell.biome == GameTypes.Biome.DESERT or cell.biome == GameTypes.Biome.SWAMP or cell.biome == GameTypes.Biome.ROCKY:
		return true
	if cell.coast_type != GameTypes.CoastType.NONE:
		return true
	return false


func _print_cell_counts(world: World) -> void:
	var water := 0
	var hostile_land := 0
	var normal_land := 0

	for cell in world.cells:
		if cell.terrain_base == GameTypes.TerrainBase.WATER:
			water += 1
		elif _is_hostile(cell):
			hostile_land += 1
		else:
			normal_land += 1

	print("  acqua=%d, terra ostile=%d, terra normale=%d, territorio predatore=%d" % [
		water, hostile_land, normal_land, PREDATOR_TERRITORY_CELLS.size()
	])


# Griglia World.WIDTH x World.HEIGHT reale (get_cell_at/l'indicizzazione flat y*WIDTH+x
# assumono sempre queste dimensioni, vedi World.gd) — tutta PLAIN/GRASSLAND (terra normale) tranne
# una colonna di mare, una cella di costa, una montagna, e tre celle a bioma ostile
# (deserto/palude/roccioso), una cella-fiume, e un branco wolf sintetico con territorio
# multi-cella (PREDATOR_TERRITORY_CELLS) — mix scelto per avere rappresentanti di OGNI categoria
# che il servizio deve gestire.
func _build_synthetic_world() -> World:
	var world := World.new()
	world.cells.clear()
	world.cell_states.clear()

	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var cell := MacroCellData.new(x, y)
			cell.terrain_base = GameTypes.TerrainBase.PLAIN
			cell.biome = GameTypes.Biome.GRASSLAND
			world.cells.append(cell)
			world.cell_states.append(MacroCellState.new(x, y))

	for cell in world.cells:
		if cell.x == 0:
			cell.terrain_base = GameTypes.TerrainBase.WATER
			cell.water_type = GameTypes.WaterType.SEA
			cell.biome = GameTypes.Biome.NONE
		elif cell.x == 1:
			cell.coast_type = GameTypes.CoastType.BEACH

	_get_cell(world, 5, 5).terrain_base = GameTypes.TerrainBase.MOUNTAIN
	_get_cell(world, 6, 5).biome = GameTypes.Biome.DESERT
	_get_cell(world, 7, 5).biome = GameTypes.Biome.SWAMP
	_get_cell(world, 8, 5).biome = GameTypes.Biome.ROCKY

	_get_cell(world, 4, 2).water_type = GameTypes.WaterType.RIVER
	_get_cell(world, 4, 2).river_shape = GameTypes.RiverShape.VERTICAL

	var wolf_group := PopulationGroup.new()
	wolf_group.id = world.allocate_population_group_id()
	wolf_group.species_name = "wolf"
	wolf_group.population = 6
	wolf_group.territory = Territory.new(PREDATOR_TERRITORY_CELLS.duplicate())
	world.population_groups.append(wolf_group)

	var rabbit_group := PopulationGroup.new()
	rabbit_group.id = world.allocate_population_group_id()
	rabbit_group.species_name = "rabbit"
	rabbit_group.population = 30
	rabbit_group.territory = Territory.new(ANIMAL_PRESENT_CELLS.duplicate())
	world.population_groups.append(rabbit_group)

	return world


func _get_cell(world: World, x: int, y: int) -> MacroCellData:
	return world.get_cell_at(x, y)
