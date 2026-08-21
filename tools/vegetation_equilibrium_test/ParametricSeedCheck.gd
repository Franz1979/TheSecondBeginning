extends Node

# Verifica visiva minima (non un test automatizzato): carica marealtodx.json, chiama
# ParametricResourceSetupService.populate_resources(world, age) UNA VOLTA (nessun avanzamento di
# anni, a differenza di VegetationEquilibriumTest.gd nella stessa cartella) e stampa lo stato
# risultante — dedicated_space GRASS/SHRUB/TREE per le stesse celle campione bioma x terreno gia'
# usate nei test di saturazione, piu' un riepilogo FISH/BIRDS — solo per confermare a colpo
# d'occhio che le proporzioni configurate vengano rispettate. NON tocca il motore: chiama solo
# l'API pubblica di ParametricResourceSetupService.
#
# Esecuzione (headless, dalla cartella del progetto), age passato come primo argomento
# posizionale dopo "--" (YOUNG/ADULT/OLD, default OLD se omesso):
#   godot4 --headless --path . res://tools/vegetation_equilibrium_test/ParametricSeedCheck.tscn -- OLD

const MAP_FILE_PATH := "user://maps/marealtodx.json"


func _ready() -> void:
	var age := _parse_age_arg()
	print("=== ParametricResourceSetupService check (age=%s) ===" % GameTypes.WorldAge.keys()[age])
	print("Mappa: %s" % MAP_FILE_PATH)

	var load_service := WorldLoadService.new()
	var world := load_service.load_world_from_json(MAP_FILE_PATH)
	if world == null:
		push_error("Impossibile caricare la mappa %s." % MAP_FILE_PATH)
		get_tree().quit(1)
		return
	world.ensure_cell_states()
	print("Mappa caricata: %d celle." % world.cells.size())

	ParametricResourceSetupService.new().populate_resources(world, age)

	var samples := _pick_representative_cells(world)
	var keys := samples.keys()
	keys.sort()

	print("")
	print("=== Vegetazione (GRASS/SHRUB/TREE) per cella campione ===")
	print("%-22s %-8s %-8s %-8s %-8s %-8s %-9s %-14s" % [
		"bioma|terreno", "GRASS", "SHRUB", "TREE", "totale", "cap", "pct_cap", "mix G/S/T %"
	])
	for key in keys:
		var info: Dictionary = samples[key]
		if info["terrain"] == GameTypes.TerrainBase.WATER:
			continue
		var coords: Vector2i = info["coords"]
		var state := world.get_cell_state_at(coords.x, coords.y)
		var g := state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
		var s := state.get_dedicated_space(GameTypes.WorldObjectType.SHRUB)
		var t := state.get_dedicated_space(GameTypes.WorldObjectType.TREE)
		var total := g + s + t
		var cap := MacroCellState.TOTAL_SPACE - state.get_river_space()
		var pct := (float(total) / float(cap) * 100.0) if cap > 0 else 0.0
		var grass_pct := (float(g) / float(total) * 100.0) if total > 0 else 0.0
		var shrub_pct := (float(s) / float(total) * 100.0) if total > 0 else 0.0
		var tree_pct := (float(t) / float(total) * 100.0) if total > 0 else 0.0
		print("%-22s %-8d %-8d %-8d %-8d %-8d %-9s %-14s" % [
			key, g, s, t, total, cap,
			"%.1f%%" % pct, "%.0f/%.0f/%.0f" % [grass_pct, shrub_pct, tree_pct]
		])

	print("")
	print("=== FISH/BIRDS per cella campione (dove applicabile) ===")
	print("%-22s %-14s %-14s" % ["bioma|terreno", "FISH", "BIRDS"])
	for key in keys:
		var info: Dictionary = samples[key]
		var coords: Vector2i = info["coords"]
		var cell := world.get_cell_at(coords.x, coords.y)
		var state := world.get_cell_state_at(coords.x, coords.y)

		var fish_cap := ResourceCalculator.get_water_usable_capacity_space(GameTypes.WorldObjectType.FISH, cell, state)
		var fish_label := "N/A"
		if fish_cap > 0:
			var fish_space := state.get_water_space(GameTypes.WorldObjectType.FISH)
			fish_label = "%d/%d (%.1f%%)" % [fish_space, fish_cap, float(fish_space) / float(fish_cap) * 100.0]

		var birds_cap := ResourceCalculator.get_land_usable_capacity_space(GameTypes.WorldObjectType.BIRDS, cell, state)
		var birds_label := "N/A"
		if birds_cap > 0:
			var birds_space := state.get_terrestrial_space(GameTypes.WorldObjectType.BIRDS)
			birds_label = "%d/%d (%.1f%%)" % [birds_space, birds_cap, float(birds_space) / float(birds_cap) * 100.0]

		print("%-22s %-14s %-14s" % [key, fish_label, birds_label])

	print("")
	print("=== Fine verifica ===")
	get_tree().quit()


func _parse_age_arg() -> GameTypes.WorldAge:
	for arg in OS.get_cmdline_user_args():
		var upper := arg.to_upper()
		if upper == "YOUNG":
			return GameTypes.WorldAge.YOUNG
		if upper == "ADULT":
			return GameTypes.WorldAge.ADULT
		if upper == "OLD":
			return GameTypes.WorldAge.OLD
	return GameTypes.WorldAge.OLD


# Stessa logica di VegetationEquilibriumTest.gd (_combo_key/_pick_representative_cells): una
# cella per combinazione bioma|terreno, con water_type incluso nella chiave quando il terreno e'
# WATER (distingue mare e lago, che condividono biome=NONE/terrain=WATER — vedi analisi
# precedente), preferendo coast_type==NONE come baseline.
func _combo_key(cell: MacroCellData) -> String:
	if cell.terrain_base == GameTypes.TerrainBase.WATER:
		return "%s|%s|%s" % [
			GameTypes.Biome.keys()[cell.biome], GameTypes.TerrainBase.keys()[cell.terrain_base],
			GameTypes.WaterType.keys()[cell.water_type],
		]
	return "%s|%s" % [GameTypes.Biome.keys()[cell.biome], GameTypes.TerrainBase.keys()[cell.terrain_base]]


func _pick_representative_cells(world: World) -> Dictionary:
	var samples: Dictionary = {}

	for cell in world.cells:
		var key := _combo_key(cell)
		if cell.coast_type != GameTypes.CoastType.NONE:
			continue
		if samples.has(key):
			continue
		samples[key] = {"coords": Vector2i(cell.x, cell.y), "coast": cell.coast_type, "water_type": cell.water_type, "terrain": cell.terrain_base}

	for cell in world.cells:
		var key := _combo_key(cell)
		if samples.has(key):
			continue
		samples[key] = {"coords": Vector2i(cell.x, cell.y), "coast": cell.coast_type, "water_type": cell.water_type, "terrain": cell.terrain_base}

	return samples
