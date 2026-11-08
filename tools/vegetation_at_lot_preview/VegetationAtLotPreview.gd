extends Node

# Vegetazione a richiesta, passo 2: prova di VegetationAtLotService senza toccare il gioco. Carica una mappa, la popola
# come un mondo vecchio e confronta il generatore di oggi con la funzione nuova: tempi, immagini e controlli automatici.
# Non salva niente della partita: scrive solo le immagini in output/.
#
# Esecuzione (dopo un --import, se la classe è nuova):
#   godot4 --headless --path . res://tools/vegetation_at_lot_preview/VegetationAtLotPreview.tscn

const MAP_FILE_PATH := "user://maps/marealtodx.json"
const OUTPUT_DIR := "res://tools/vegetation_at_lot_preview/output/"
const WORLD_SEED := 12345
const BIOMES: Array[GameTypes.Biome] = [
	GameTypes.Biome.FOREST, GameTypes.Biome.GRASSLAND, GameTypes.Biome.FERTILE,
	GameTypes.Biome.SWAMP, GameTypes.Biome.ROCKY, GameTypes.Biome.DESERT,
]
const YEARS: Array[int] = [0, 20, 40, 60, 80, 100]
const CELLS_PER_BIOME := 5
const TIMING_REPEATS := 5
const SCALE := 2
const GUTTER := 6
const LOTS := VegetationAtLotService.LOTS_PER_CELL
const SAMPLE_LOTS := 40
const SAMPLE_YEARS := 100

const COLOR_BG := Color(0.1, 0.1, 0.1)
const COLOR_BARE := Color(0.72, 0.65, 0.5)
const COLOR_GRASS := Color(0.62, 0.78, 0.38)
const COLOR_SHRUB := Color(0.72, 0.62, 0.15)
const COLOR_TREE_LIGHT := Color(0.2, 0.55, 0.22)
const COLOR_TREE_DARK := Color(0.03, 0.27, 0.1)
const COLOR_DEAD := Color(0.42, 0.25, 0.14)


func _ready() -> void:
	var world := WorldLoadService.new().load_world_from_json(MAP_FILE_PATH)
	if world == null:
		push_error("Impossibile caricare %s." % MAP_FILE_PATH)
		get_tree().quit(1)
		return
	world.ensure_cell_states()
	ParametricResourceSetupService.new().populate_resources(world, GameTypes.WorldAge.OLD)
	VegetationAtLotService.set_world_seed(WORLD_SEED)

	var cells_by_biome := _pick_cells(world)
	_print_noise_spread()
	_print_timings(world, cells_by_biome)
	_write_comparison_image(world, cells_by_biome)
	_print_shares(world, cells_by_biome)
	_print_automatic_checks(cells_by_biome)
	print("=== Fine prova ===")
	get_tree().quit()


# Celle di pianura senza costa né acqua, se ce ne sono; altrimenti le prime del bioma su terra.
func _pick_cells(world: World) -> Dictionary:
	var result: Dictionary = {}
	for biome in BIOMES:
		var preferred: Array = []
		var others: Array = []
		for cell in world.cells:
			if cell.biome != biome or cell.terrain_base == GameTypes.TerrainBase.WATER:
				continue
			if cell.terrain_base == GameTypes.TerrainBase.PLAIN and cell.coast_type == GameTypes.CoastType.NONE and cell.water_type == GameTypes.WaterType.NONE:
				preferred.append(cell)
			else:
				others.append(cell)
		preferred.append_array(others)
		result[biome] = preferred.slice(0, CELLS_PER_BIOME)
		print("%s: %d celle prese (%d in pianura, su %d)" % [GameTypes.Biome.keys()[biome], (result[biome] as Array).size(), mini(preferred.size() - others.size(), CELLS_PER_BIOME), preferred.size()])
	return result


func _print_noise_spread() -> void:
	var values := PackedFloat32Array()
	for y in range(0, 2000, 7):
		for x in range(0, 2000, 7):
			values.append(VegetationAtLotService.raw_noise_at(x, y, (x + y) % 200))
	var total := 0.0
	for value in values:
		total += value
	var mean: float = total / float(values.size())
	var squares := 0.0
	for value in values:
		squares += (value - mean) * (value - mean)
	var deviation: float = sqrt(squares / float(values.size()))
	print("")
	print("=== Rumore === media %.4f, deviazione %.4f, scala logistica adatta %.4f (in uso %.4f)" % [mean, deviation, deviation / 1.81, VegetationAtLotService.NOISE_LOGISTIC_SCALE])


func _print_timings(world: World, cells_by_biome: Dictionary) -> void:
	print("")
	print("=== Tempi per macrocella (ms), mediana === generatore di oggi lanciato due volte di fila, funzione nuova su 100x100 lotti (griglie vuote e pronte). Il rientro in cella del gioco non è misurato qui: rilegge la disposizione tenuta, senza generatore")
	print("%-10s %12s %12s %12s %12s %10s %10s %12s" % ["bioma", "gen. 1a", "gen. 2a", "fun. vuote", "fun. pronte", "su 1a", "su 2a", "us per lotto"])
	for biome in BIOMES:
		var generator_ms := PackedFloat64Array()
		var generator_again_ms := PackedFloat64Array()
		var function_ms := PackedFloat64Array()
		var function_ready_ms := PackedFloat64Array()
		for cell in cells_by_biome[biome]:
			var state := world.get_cell_state_at(cell.x, cell.y)
			var start := Time.get_ticks_usec()
			VegetationPositionService.new().generate_positions(state, {}, 0, 0, {})
			generator_ms.append((Time.get_ticks_usec() - start) / 1000.0)
			start = Time.get_ticks_usec()
			VegetationPositionService.new().generate_positions(state, {}, 0, 0, {})
			generator_again_ms.append((Time.get_ticks_usec() - start) / 1000.0)
			var profile := VegetationAtLotService.make_profile(cell.terrain_base, cell.biome, cell.coast_type)
			for repeat in range(TIMING_REPEATS):
				# Griglie vuote: come arrivare in una cella per la prima volta.
				VegetationAtLotService.clear_maturity_cache()
				start = Time.get_ticks_usec()
				_evaluate_cell(profile, cell, repeat * 7)
				function_ms.append((Time.get_ticks_usec() - start) / 1000.0)
				# Griglie pronte: l'anno dopo nella stessa cella.
				start = Time.get_ticks_usec()
				_evaluate_cell(profile, cell, repeat * 7 + 1)
				function_ready_ms.append((Time.get_ticks_usec() - start) / 1000.0)
		if generator_ms.is_empty():
			print("%-10s nessuna cella sulla mappa" % GameTypes.Biome.keys()[biome])
			continue
		var generator := _median(generator_ms)
		var generator_again := _median(generator_again_ms)
		var function := _median(function_ms)
		var function_ready := _median(function_ready_ms)
		print("%-10s %12.1f %12.1f %12.1f %12.1f %10.2f %10.2f %12.1f" % [
			GameTypes.Biome.keys()[biome], generator, generator_again, function, function_ready,
			function / generator if generator > 0.0 else 0.0, function_ready / generator_again if generator_again > 0.0 else 0.0,
			function_ready * 1000.0 / float(LOTS * LOTS)
		])


func _evaluate_cell(profile: VegetationAtLotService.LotProfile, cell: MacroCellData, year: int) -> void:
	VegetationAtLotService.vegetation_for_lots(profile, cell.x, cell.y, year, _all_lot_codes())


func _all_lot_codes() -> PackedInt32Array:
	var codes := PackedInt32Array()
	codes.resize(LOTS * LOTS)
	for i in range(codes.size()):
		codes[i] = i
	return codes


# Quanti lotti danno una risposta diversa chiedendoli uno alla volta o tutti insieme (piante, prato, segni di pianta morta).
func _batch_differences(profile: VegetationAtLotService.LotProfile, cell: MacroCellData, year: int) -> int:
	var batch: Dictionary = VegetationAtLotService.vegetation_for_lots(profile, cell.x, cell.y, year, _all_lot_codes())
	var batch_trees := _plants_by_lot(batch["trees"])
	var batch_shrubs := _plants_by_lot(batch["shrubs"])
	var batch_grass := {}
	for code in batch["grass"]:
		batch_grass[code] = true
	var batch_dead := {}
	for code in batch["dead"]:
		batch_dead[code] = int(batch_dead.get(code, 0)) + 1
	var differences := 0
	for code in _all_lot_codes():
		var lot_y: int = code / LOTS
		var lot_x: int = code - lot_y * LOTS
		var lot: Dictionary = VegetationAtLotService.vegetation_at(profile, cell.x * LOTS + lot_x, cell.y * LOTS + lot_y, year)
		var same: bool = batch_trees.get(code, PackedInt32Array()) == lot["trees"]
		same = same and batch_shrubs.get(code, PackedInt32Array()) == lot["shrubs"]
		same = same and batch_grass.has(code) == bool(lot["grass"])
		same = same and int(batch_dead.get(code, 0)) == int(lot["dead_trees"]) + int(lot["dead_shrubs"])
		if not same:
			differences += 1
	return differences


# Da [codice lotto, indice, età, sottotipo, ...] a codice lotto -> [indice, età, sottotipo, ...].
func _plants_by_lot(flat: PackedInt32Array) -> Dictionary:
	var by_lot := {}
	for i in range(0, flat.size(), 4):
		var plants: PackedInt32Array = by_lot.get(flat[i], PackedInt32Array())
		plants.append(flat[i + 1])
		plants.append(flat[i + 2])
		plants.append(flat[i + 3])
		by_lot[flat[i]] = plants
	return by_lot


# Una riga per bioma; colonne: generatore di oggi, poi funzione nuova agli anni di YEARS.
func _write_comparison_image(world: World, cells_by_biome: Dictionary) -> void:
	var tile := LOTS * SCALE
	var columns := YEARS.size() + 1
	var width := columns * tile + (columns + 1) * GUTTER
	var height := BIOMES.size() * tile + (BIOMES.size() + 1) * GUTTER
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	image.fill(COLOR_BG)
	for row in range(BIOMES.size()):
		var cells: Array = cells_by_biome[BIOMES[row]]
		if cells.is_empty():
			continue
		var cell: MacroCellData = cells[0]
		var top := GUTTER + row * (tile + GUTTER)
		var state := world.get_cell_state_at(cell.x, cell.y)
		_draw_today(image, Vector2i(GUTTER, top), VegetationPositionService.new().generate_positions(state, {}, 0, 0, {}), cell)
		var profile := VegetationAtLotService.make_profile(cell.terrain_base, cell.biome, cell.coast_type)
		for column in range(YEARS.size()):
			_draw_function(image, Vector2i(GUTTER + (column + 1) * (tile + GUTTER), top), profile, cell, YEARS[column])
	var path := ProjectSettings.globalize_path(OUTPUT_DIR + "confronto_biomi_decenni.png")
	var error := image.save_png(path)
	print("")
	print("=== Immagine === %s (errore %d)" % [path, error])


func _draw_today(image: Image, origin: Vector2i, positions: Dictionary, cell: MacroCellData) -> void:
	var counts: Dictionary = {}
	for key in positions.get(GameTypes.WorldObjectType.TREE, []):
		var lot := Vector2i(key.x, key.y)
		counts[lot] = int(counts.get(lot, 0)) + 1
	var shrubs: Dictionary = {}
	for key in positions.get(GameTypes.WorldObjectType.SHRUB, []):
		shrubs[Vector2i(key.x, key.y)] = true
	var grass: Dictionary = {}
	for lot in positions.get(GameTypes.WorldObjectType.GRASS, []):
		grass[lot] = true
	var max_trees: float = maxf(1.0, ResourceCalculator.get_max_density(GameTypes.WorldObjectType.TREE, cell.terrain_base, cell.biome, cell.coast_type))
	for y in range(LOTS):
		for x in range(LOTS):
			var lot := Vector2i(x, y)
			var color := COLOR_BARE
			if counts.has(lot):
				color = COLOR_TREE_LIGHT.lerp(COLOR_TREE_DARK, clampf(float(counts[lot]) / max_trees, 0.0, 1.0))
			elif shrubs.has(lot):
				color = COLOR_SHRUB
			elif grass.has(lot):
				color = COLOR_GRASS
			_paint(image, origin, x, y, color)


func _draw_function(image: Image, origin: Vector2i, profile: VegetationAtLotService.LotProfile, cell: MacroCellData, year: int) -> void:
	var max_trees: float = maxf(1.0, profile.tree_density)
	for y in range(LOTS):
		for x in range(LOTS):
			var lot: Dictionary = VegetationAtLotService.vegetation_at(profile, cell.x * LOTS + x, cell.y * LOTS + y, year)
			var trees: int = (lot["trees"] as PackedInt32Array).size() / 3
			var color := COLOR_BARE
			if trees > 0:
				color = COLOR_TREE_LIGHT.lerp(COLOR_TREE_DARK, clampf(float(trees) / max_trees, 0.0, 1.0))
			elif not (lot["shrubs"] as PackedInt32Array).is_empty():
				color = COLOR_SHRUB
			elif int(lot["dead_trees"]) + int(lot["dead_shrubs"]) > 0:
				color = COLOR_DEAD
			elif lot["grass"]:
				color = COLOR_GRASS
			_paint(image, origin, x, y, color)


func _paint(image: Image, origin: Vector2i, x: int, y: int, color: Color) -> void:
	for dy in range(SCALE):
		for dx in range(SCALE):
			image.set_pixel(origin.x + x * SCALE + dx, origin.y + y * SCALE + dy, color)


# Quote di lotti e numero di piante: generatore di oggi contro funzione nuova.
func _print_shares(world: World, cells_by_biome: Dictionary) -> void:
	print("")
	print("=== Quote di lotti e piante, prima cella di ogni bioma === con alberi / con arbusti / a prato (%)")
	print("%-10s %-22s %-24s %-24s %-24s" % ["bioma", "oggi", "funzione anno 0", "funzione anno 50", "funzione anno 100"])
	for biome in BIOMES:
		var cells: Array = cells_by_biome[biome]
		if cells.is_empty():
			continue
		var cell: MacroCellData = cells[0]
		var state := world.get_cell_state_at(cell.x, cell.y)
		var today := VegetationPositionService.new().generate_positions(state, {}, 0, 0, {})
		var today_trees: Array = today.get(GameTypes.WorldObjectType.TREE, [])
		var today_shrubs: Array = today.get(GameTypes.WorldObjectType.SHRUB, [])
		var today_text := "%s/%s/%s %dA %dR" % [
			_percent(_unique_lots(today_trees)), _percent(_unique_lots(today_shrubs)),
			_percent((today.get(GameTypes.WorldObjectType.GRASS, []) as Array).size()), today_trees.size(), today_shrubs.size()
		]
		var profile := VegetationAtLotService.make_profile(cell.terrain_base, cell.biome, cell.coast_type)
		print("%-10s %-22s %-24s %-24s %-24s" % [
			GameTypes.Biome.keys()[biome], today_text, _function_summary(profile, cell, 0),
			_function_summary(profile, cell, 50), _function_summary(profile, cell, 100)
		])
	print("A = alberi, R = arbusti")


func _unique_lots(individuals: Array) -> int:
	var lots: Dictionary = {}
	for key in individuals:
		lots[Vector2i(key.x, key.y)] = true
	return lots.size()


func _percent(lots: int) -> String:
	return "%.0f" % (100.0 * float(lots) / float(LOTS * LOTS))


func _function_summary(profile: VegetationAtLotService.LotProfile, cell: MacroCellData, year: int) -> String:
	var tree_lots := 0
	var shrub_lots := 0
	var grass_lots := 0
	var trees := 0
	var shrubs := 0
	for y in range(LOTS):
		for x in range(LOTS):
			var lot: Dictionary = VegetationAtLotService.vegetation_at(profile, cell.x * LOTS + x, cell.y * LOTS + y, year)
			var lot_trees: int = (lot["trees"] as PackedInt32Array).size() / 3
			var lot_shrubs: int = (lot["shrubs"] as PackedInt32Array).size() / 3
			trees += lot_trees
			shrubs += lot_shrubs
			if lot_trees > 0:
				tree_lots += 1
			if lot_shrubs > 0:
				shrub_lots += 1
			if lot["grass"]:
				grass_lots += 1
	return "%s/%s/%s %dA %dR" % [_percent(tree_lots), _percent(shrub_lots), _percent(grass_lots), trees, shrubs]


# Su un campione di lotti per bioma, anno per anno: stessa risposta alla stessa domanda, salti di fascia, primo albero
# senza arbusti nei 15 anni prima, piante morte per anno, lotti che cambiano fascia in 50 anni.
func _print_automatic_checks(cells_by_biome: Dictionary) -> void:
	print("")
	print("=== Controlli automatici === %dx%d lotti, %d anni" % [SAMPLE_LOTS, SAMPLE_LOTS, SAMPLE_YEARS])
	print("%-10s %-8s %-10s %-16s %-22s %-14s %-12s %-14s %-10s" % ["bioma", "uguale", "salti", "alberi senza R", "morti/anno min-med-max", "max % morti", "cambio 50a", "piante perse", "lotti diversi"])
	for biome in BIOMES:
		var cells: Array = cells_by_biome[biome]
		if cells.is_empty():
			continue
		var cell: MacroCellData = cells[0]
		var profile := VegetationAtLotService.make_profile(cell.terrain_base, cell.biome, cell.coast_type)
		var identical := true
		var band_jumps := 0
		var trees_without_shrubs := 0
		var changed_in_50_years := 0
		var dead_by_year := PackedInt32Array()
		dead_by_year.resize(SAMPLE_YEARS)
		var alive_total := 0
		var exact_total := 0
		for y in range(SAMPLE_LOTS):
			for x in range(SAMPLE_LOTS):
				var world_x: int = cell.x * LOTS + x
				var world_y: int = cell.y * LOTS + y
				var previous_band := -1
				var had_trees := false
				var last_shrub_year := -1000
				var band_at_start := VegetationAtLotService.band_of(profile, VegetationAtLotService.maturity_at(world_x, world_y, 0))
				var band_at_50 := VegetationAtLotService.band_of(profile, VegetationAtLotService.maturity_at(world_x, world_y, 50))
				if band_at_start != band_at_50:
					changed_in_50_years += 1
				for year in range(SAMPLE_YEARS):
					var lot: Dictionary = VegetationAtLotService.vegetation_at(profile, world_x, world_y, year)
					var again: Dictionary = VegetationAtLotService.vegetation_at(profile, world_x, world_y, year)
					if lot != again:
						identical = false
					var exact: Dictionary = VegetationAtLotService.vegetation_at(profile, world_x, world_y, year, true)
					exact_total += (exact["trees"] as PackedInt32Array).size() / 3 + (exact["shrubs"] as PackedInt32Array).size() / 3
					var band := _band_rank(profile, VegetationAtLotService.band_of(profile, float(lot["maturity"])))
					if previous_band != -1 and absi(band - previous_band) > 1:
						band_jumps += 1
					previous_band = band
					var has_trees: bool = not (lot["trees"] as PackedInt32Array).is_empty()
					var has_shrubs: bool = not (lot["shrubs"] as PackedInt32Array).is_empty()
					if has_shrubs:
						last_shrub_year = year
					if has_trees and not had_trees and year > 0 and year - last_shrub_year > 15:
						trees_without_shrubs += 1
					had_trees = has_trees
					dead_by_year[year] += int(lot["dead_trees"]) + int(lot["dead_shrubs"])
					alive_total += (lot["trees"] as PackedInt32Array).size() / 3 + (lot["shrubs"] as PackedInt32Array).size() / 3
		var sorted_dead := dead_by_year.duplicate()
		sorted_dead.sort()
		var alive_per_year: float = float(alive_total) / float(SAMPLE_YEARS)
		print("%-10s %-8s %-10d %-16d %-22s %-14s %-12s %-14s %-10s" % [
			GameTypes.Biome.keys()[biome], "si" if identical else "NO", band_jumps, trees_without_shrubs,
			"%d-%d-%d" % [sorted_dead[0], sorted_dead[sorted_dead.size() / 2], sorted_dead[sorted_dead.size() - 1]],
			"%.1f%%" % (100.0 * float(sorted_dead[sorted_dead.size() - 1]) / maxf(1.0, alive_per_year)),
			"%.0f%%" % (100.0 * float(changed_in_50_years) / float(SAMPLE_LOTS * SAMPLE_LOTS)),
			"%.2f%%" % (100.0 * float(exact_total - alive_total) / maxf(1.0, float(exact_total))),
			str(_batch_differences(profile, cell, 37))
		])


# Fascia contata tra quelle che il bioma ha davvero: nel deserto, senza prato, da terra si passa subito agli arbusti.
func _band_rank(profile: VegetationAtLotService.LotProfile, band: int) -> int:
	var rank := 0
	if band >= VegetationAtLotService.BAND_GRASS and profile.grass_share > 0.0:
		rank += 1
	if band >= VegetationAtLotService.BAND_SHRUB and profile.shrub_share > 0.0:
		rank += 1
	if band >= VegetationAtLotService.BAND_TREE and profile.tree_share > 0.0:
		rank += 1
	return rank


func _median(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
