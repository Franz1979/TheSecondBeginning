extends Node

# Harness di misura standalone: NON fa parte del flusso di gioco (non e' referenziato da
# nessuna scena in simulation/ o gameplay/, ne' chiamato da alcun service). Carica una mappa
# salvata reale (stesso WorldLoadService.load_world_from_json usato dal menu "Scegli scenario",
# vedi new_game_menu.gd/_on_open_scenario_file_selected), la popola con
# InitialResourceSetupService.populate_resources come una nuova partita, NON crea alcun
# PopulationGroup, poi fa avanzare la simulazione per YEARS_TO_RUN anni tramite
# WorldTimeService.force_advance_to_year_end (lo stesso metodo usato in game dal bottone debug
# "+1"), campionando ogni anno — per una cella rappresentativa di ogni combinazione bioma x
# terreno effettivamente presente sulla mappa caricata — la SATURAZIONE COMPLESSIVA dello
# spazio terrestre (ROCK+TREE+GRASS+SHRUB come percentuale del budget disponibile, non
# l'equilibrio "puro" per singola risorsa), la sua SCOMPOSIZIONE per singola risorsa all'anno di
# saturazione, e separatamente la saturazione di FISH/BIRDS verso la propria capacita'
# sfruttabile. Nessun service di simulation/scripts/core/ viene toccato: questo script si
# limita a chiamare l'API pubblica gia' esistente.
#
# Esecuzione (headless, dalla cartella del progetto) — E' UNA SCENA runnable, non un
# --script/MainLoop override: quest'ultima modalita' compila l'intero grafo di dipendenze
# (incluso World, che referenzia l'autoload GameSettings) PRIMA che gli autoload siano
# registrati, e fallisce con "Identifier not found: GameSettings". Una scena normale invece
# segue il bootstrap standard del progetto (autoload pronti prima di qualsiasi _ready()),
# esattamente come la partita vera:
#   godot4 --headless --path . res://tools/vegetation_equilibrium_test/VegetationEquilibriumTest.tscn
#
# Riutilizzabile in futuro per ritarare le soglie di maturita' del seeding automatico degli
# animali, o per verificare l'effetto di modifiche ai *_growth.tres / *_density.tres sul tempo
# di saturazione. Il file equilibrium_composition.json prodotto a fine run e' pensato come dato
# di calibrazione per un'eventuale futura scelta "mondo giovane vs maturo" — questo script non
# implementa ne' modifica alcun meccanismo di seeding, si limita a misurare.

const MAP_FILE_PATH := "user://maps/marealtodx.json"
const OUTPUT_JSON_PATH := "res://tools/vegetation_equilibrium_test/equilibrium_composition.json"

const YEARS_TO_RUN := 100
const SATURATION_THRESHOLD := 0.90
const SATURATION_STREAK_REQUIRED := 3

# Tipi che competono per lo stesso budget terrestre condiviso (MacroCellState.dedicated_space +
# river_space, vedi get_total_dedicated_space/get_empty_space) — "quanto e' piena la cella"
# indipendentemente da come si divide tra loro. ROCK incluso: occupa lo stesso budget anche se
# non ricresce mai (nessun *_growth.tres per ROCK).
const VEGETATION_TYPES := [
	GameTypes.WorldObjectType.ROCK,
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.TREE,
]


func _ready() -> void:
	print("=== Vegetation Saturation + Composition Test (%d years, no animals, mappa reale) ===" % YEARS_TO_RUN)
	print("Mappa: %s" % MAP_FILE_PATH)

	var load_service := WorldLoadService.new()
	var world := load_service.load_world_from_json(MAP_FILE_PATH)
	if world == null:
		push_error("Impossibile caricare la mappa %s — vedi il messaggio sopra." % MAP_FILE_PATH)
		get_tree().quit(1)
		return
	world.ensure_cell_states()
	print("Mappa caricata: %d celle." % world.cells.size())

	InitialResourceSetupService.new().populate_resources(world)

	var game_data := GameData.new()

	var samples := _pick_representative_cells(world)
	print("Combinazioni bioma x terreno campionate: %d" % samples.size())
	for key in samples.keys():
		var info: Dictionary = samples[key]
		var coords: Vector2i = info["coords"]
		print("  %s -> cella (%d,%d) coast=%s water=%s" % [
			key, coords.x, coords.y,
			GameTypes.CoastType.keys()[info["coast"]],
			GameTypes.WaterType.keys()[info["water_type"]],
		])

	# Cella FISH per combinazione: di norma la stessa cella campione sopra, ma ricampionata su
	# un'altra cella della STESSA combinazione bioma|terreno se il seed iniziale di FISH e'
	# fallito li' (dedicated_space rimasto 0 dopo populate_resources) mentre la cella ha comunque
	# acqua sfruttabile — vedi _pick_fish_sample_cells. null se la combinazione non ha proprio
	# acqua sfruttabile in nessuna cella (FISH non applicabile).
	var fish_samples := _pick_fish_sample_cells(world, samples)
	for key in fish_samples.keys():
		var info = fish_samples[key]
		if info == null:
			continue
		if info["resampled"]:
			print("  [FISH] %s: seed fallito sulla cella campione, ricampionato su (%d,%d)" % [key, info["coords"].x, info["coords"].y])
		elif info.get("seed_failed_no_alternative", false):
			print("  [FISH] %s: seed fallito sulla cella campione E nessuna cella alternativa della stessa combinazione ha un seed riuscito — dato FISH resta a 0" % key)

	# veg_pct_history[key] / veg_abs_history[key] = Array[float]/Array[int] (0..1 percentuale,
	# microcelle assolute) anno per anno, per il TOTALE ROCK+TREE+GRASS+SHRUB.
	# veg_breakdown_history[key][resource_type] = Array[int], stessa serie ma per singola
	# risorsa (necessaria per la scomposizione richiesta, non solo il totale).
	# veg_cap[key] = int, costante (TOTAL_SPACE - river_space).
	var veg_pct_history: Dictionary = {}
	var veg_abs_history: Dictionary = {}
	var veg_breakdown_history: Dictionary = {}
	var veg_cap: Dictionary = {}

	var fish_pct_history: Dictionary = {}
	var fish_abs_history: Dictionary = {}
	var fish_cap: Dictionary = {}
	var birds_pct_history: Dictionary = {}
	var birds_abs_history: Dictionary = {}
	var birds_cap: Dictionary = {}

	for key in samples.keys():
		veg_pct_history[key] = []
		veg_abs_history[key] = []
		veg_breakdown_history[key] = {}
		for rt in VEGETATION_TYPES:
			veg_breakdown_history[key][rt] = []
		fish_pct_history[key] = []
		fish_abs_history[key] = []
		birds_pct_history[key] = []
		birds_abs_history[key] = []

	_record_year(
		world, samples, fish_samples,
		veg_pct_history, veg_abs_history, veg_breakdown_history, veg_cap,
		fish_pct_history, fish_abs_history, fish_cap,
		birds_pct_history, birds_abs_history, birds_cap
	)

	var time_service := WorldTimeService.new()
	var start_usec := Time.get_ticks_usec()
	for year in range(YEARS_TO_RUN):
		time_service.force_advance_to_year_end(world, game_data)
		_record_year(
			world, samples, fish_samples,
			veg_pct_history, veg_abs_history, veg_breakdown_history, veg_cap,
			fish_pct_history, fish_abs_history, fish_cap,
			birds_pct_history, birds_abs_history, birds_cap
		)
		if (year + 1) % 10 == 0:
			var elapsed_sec := (Time.get_ticks_usec() - start_usec) / 1000000.0
			print("  ...anno %d/%d completato (%.1fs trascorsi)" % [year + 1, YEARS_TO_RUN, elapsed_sec])

	_report_saturation_tables(samples, fish_samples, veg_pct_history, veg_abs_history, veg_cap, fish_pct_history, fish_abs_history, fish_cap, birds_pct_history, birds_abs_history, birds_cap)

	var composition := _build_composition_report(
		samples, fish_samples,
		veg_pct_history, veg_abs_history, veg_breakdown_history, veg_cap,
		fish_pct_history, fish_abs_history, fish_cap,
		birds_pct_history, birds_abs_history, birds_cap
	)
	_print_composition_report(composition)
	_write_composition_json(composition)

	print("=== Fine test ===")
	get_tree().quit()


# Chiave di raggruppamento di una cella. Su terreno WATER, biome e terrain_base da soli non
# distinguono mare da lago (entrambi biome=NONE/terrain=WATER — vedi analisi: il campo che li
# separa e' water_type, GameTypes.WaterType.SEA vs LAKE) — includerlo nella chiave SOLO li'
# evita che _pick_representative_cells campioni una sola cella d'acqua "a caso" tra le due,
# scartando silenziosamente l'altro corpo idrico. Fuori da WATER (es. RIVER su terreno PLAIN)
# bioma+terreno restano sufficienti, invariato.
func _combo_key(cell: MacroCellData) -> String:
	if cell.terrain_base == GameTypes.TerrainBase.WATER:
		return "%s|%s|%s" % [
			GameTypes.Biome.keys()[cell.biome], GameTypes.TerrainBase.keys()[cell.terrain_base],
			GameTypes.WaterType.keys()[cell.water_type],
		]
	return "%s|%s" % [GameTypes.Biome.keys()[cell.biome], GameTypes.TerrainBase.keys()[cell.terrain_base]]


# Una cella per combinazione (biome, terrain_base, e water_type se terrain==WATER): preferisce
# coast_type == NONE per una baseline "pulita" (senza il moltiplicatore costa), ripiegando su
# qualunque coast disponibile se quella combinazione non esiste mai senza costa.
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


# Per ogni combinazione: se la cella campione di _pick_representative_cells ha acqua sfruttabile
# (capacita' > 0) MA il seed iniziale di FISH e' fallito li' (water_space rimasto 0 dopo
# populate_resources — nessun floor di "seed rain" per FISH, a differenza di GRASS/SHRUB/TREE,
# vedi analisi precedente), cerca un'altra cella della STESSA combinazione bioma|terreno con
# acqua sfruttabile E seed riuscito, e usa quella per il tracciamento FISH di questa
# combinazione. Va chiamata SUBITO dopo populate_resources, prima di far avanzare anni, cosi'
# "seed riuscito" riflette il tiro iniziale e non l'effetto di crescita/migrazione successivi.
func _pick_fish_sample_cells(world: World, samples: Dictionary) -> Dictionary:
	var fish_samples: Dictionary = {}

	for key in samples.keys():
		var primary_coords: Vector2i = samples[key]["coords"]
		var primary_cell := world.get_cell_at(primary_coords.x, primary_coords.y)
		var primary_state := world.get_cell_state_at(primary_coords.x, primary_coords.y)
		var primary_cap := ResourceCalculator.get_water_usable_capacity_space(GameTypes.WorldObjectType.FISH, primary_cell, primary_state)

		if primary_cap <= 0:
			fish_samples[key] = null
			continue

		if primary_state.get_water_space(GameTypes.WorldObjectType.FISH) > 0:
			fish_samples[key] = {"coords": primary_coords, "resampled": false, "capacity": primary_cap}
			continue

		var found := false
		for cell in world.cells:
			var k := _combo_key(cell)
			if k != key:
				continue
			var state := world.get_cell_state_at(cell.x, cell.y)
			var cap := ResourceCalculator.get_water_usable_capacity_space(GameTypes.WorldObjectType.FISH, cell, state)
			if cap <= 0:
				continue
			if state.get_water_space(GameTypes.WorldObjectType.FISH) > 0:
				fish_samples[key] = {"coords": Vector2i(cell.x, cell.y), "resampled": true, "capacity": cap}
				found = true
				break

		if not found:
			fish_samples[key] = {
				"coords": primary_coords, "resampled": false, "capacity": primary_cap,
				"seed_failed_no_alternative": true,
			}

	return fish_samples


func _record_year(
	world: World, samples: Dictionary, fish_samples: Dictionary,
	veg_pct_history: Dictionary, veg_abs_history: Dictionary, veg_breakdown_history: Dictionary, veg_cap: Dictionary,
	fish_pct_history: Dictionary, fish_abs_history: Dictionary, fish_cap: Dictionary,
	birds_pct_history: Dictionary, birds_abs_history: Dictionary, birds_cap: Dictionary
) -> void:
	for key in samples.keys():
		var coords: Vector2i = samples[key]["coords"]
		var cell := world.get_cell_at(coords.x, coords.y)
		var state := world.get_cell_state_at(coords.x, coords.y)

		# --- Saturazione vegetazione+stone: budget condiviso TOTAL_SPACE - river_space ---
		var cap: int = MacroCellState.TOTAL_SPACE - state.get_river_space()
		veg_cap[key] = cap
		var total_occupied := 0
		for rt in VEGETATION_TYPES:
			var rt_space: int = state.get_dedicated_space(rt)
			veg_breakdown_history[key][rt].append(rt_space)
			total_occupied += rt_space
		veg_abs_history[key].append(total_occupied)
		veg_pct_history[key].append(float(total_occupied) / float(cap) if cap > 0 else 0.0)

		# --- FISH: cella dedicata (eventualmente ricampionata), capacita' sfruttabile in acqua ---
		var fish_info = fish_samples.get(key)
		if fish_info == null:
			fish_abs_history[key].append(0)
			fish_pct_history[key].append(-1.0) # sentinella: non applicabile
			fish_cap[key] = 0
		else:
			var f_coords: Vector2i = fish_info["coords"]
			var f_cell := world.get_cell_at(f_coords.x, f_coords.y)
			var f_state := world.get_cell_state_at(f_coords.x, f_coords.y)
			var f_cap := ResourceCalculator.get_water_usable_capacity_space(GameTypes.WorldObjectType.FISH, f_cell, f_state)
			fish_cap[key] = f_cap
			var f_space := f_state.get_water_space(GameTypes.WorldObjectType.FISH)
			fish_abs_history[key].append(f_space)
			fish_pct_history[key].append(float(f_space) / float(f_cap) if f_cap > 0 else -1.0)

		# --- BIRDS: capacita' sfruttabile su terra, budget indipendente da ROCK/TREE/GRASS/SHRUB ---
		var b_cap := ResourceCalculator.get_land_usable_capacity_space(GameTypes.WorldObjectType.BIRDS, cell, state)
		birds_cap[key] = b_cap
		if b_cap > 0:
			var b_space := state.get_terrestrial_space(GameTypes.WorldObjectType.BIRDS)
			birds_abs_history[key].append(b_space)
			birds_pct_history[key].append(float(b_space) / float(b_cap))
		else:
			birds_abs_history[key].append(0)
			birds_pct_history[key].append(-1.0)


# Primo anno t (>=0) in cui pct_series[t..t+STREAK-1] sono tutti >= threshold, oppure -1 se mai
# raggiunto entro la serie.
func _find_saturation_year(pct_series: Array, threshold: float) -> int:
	var streak := 0
	for t in range(pct_series.size()):
		if pct_series[t] >= threshold:
			streak += 1
			if streak >= SATURATION_STREAK_REQUIRED:
				return t - SATURATION_STREAK_REQUIRED + 1
		else:
			streak = 0
	return -1


func _report_saturation_tables(
	samples: Dictionary, fish_samples: Dictionary,
	veg_pct_history: Dictionary, veg_abs_history: Dictionary, veg_cap: Dictionary,
	fish_pct_history: Dictionary, fish_abs_history: Dictionary, fish_cap: Dictionary,
	birds_pct_history: Dictionary, birds_abs_history: Dictionary, birds_cap: Dictionary
) -> void:
	var keys := samples.keys()
	keys.sort()

	print("")
	print("=== TABELLA: bioma x terreno -> anno di saturazione totale (soglia %.0f%%) ===" % [SATURATION_THRESHOLD * 100.0])
	print("%-22s %-10s %-14s %-14s" % ["bioma|terreno", "cap_max", "eq_anno", "val_anno100"])
	for key in keys:
		var sample_info: Dictionary = samples[key]
		if sample_info["terrain"] == GameTypes.TerrainBase.WATER:
			continue
		var cap: int = veg_cap[key]
		var pct_series: Array = veg_pct_history[key]
		var abs_series: Array = veg_abs_history[key]
		var last_pct: float = pct_series[pct_series.size() - 1]
		var last_abs: int = abs_series[abs_series.size() - 1]
		var y := _find_saturation_year(pct_series, SATURATION_THRESHOLD)
		print("%-22s %-10d %-14s %-14s" % [
			key, cap, (str(y) if y != -1 else "MAI"), "%d (%.1f%%)" % [last_abs, last_pct * 100.0]
		])

	print("")
	print("=== TABELLA: FISH — anno di saturazione (soglia %.0f%%) ===" % [SATURATION_THRESHOLD * 100.0])
	print("%-22s %-10s %-14s %-14s" % ["bioma|terreno", "cap_usab.", "eq_anno", "val_anno100"])
	for key in keys:
		var cap: int = fish_cap.get(key, 0)
		if cap <= 0:
			continue
		var pct_series: Array = fish_pct_history[key]
		var abs_series: Array = fish_abs_history[key]
		var last_pct: float = pct_series[pct_series.size() - 1]
		var last_abs: int = abs_series[abs_series.size() - 1]
		var y := _find_saturation_year(pct_series, SATURATION_THRESHOLD)
		print("%-22s %-10d %-14s %-14s" % [
			key, cap, (str(y) if y != -1 else "MAI"), "%d (%.1f%%)" % [last_abs, last_pct * 100.0]
		])

	print("")
	print("=== TABELLA: BIRDS — anno di saturazione (soglia %.0f%%) ===" % [SATURATION_THRESHOLD * 100.0])
	print("%-22s %-10s %-14s %-14s" % ["bioma|terreno", "cap_usab.", "eq_anno", "val_anno100"])
	for key in keys:
		var cap: int = birds_cap.get(key, 0)
		if cap <= 0:
			continue
		var pct_series: Array = birds_pct_history[key]
		var abs_series: Array = birds_abs_history[key]
		var last_pct: float = pct_series[pct_series.size() - 1]
		var last_abs: int = abs_series[abs_series.size() - 1]
		var y := _find_saturation_year(pct_series, SATURATION_THRESHOLD)
		print("%-22s %-10d %-14s %-14s" % [
			key, cap, (str(y) if y != -1 else "MAI"), "%d (%.1f%%)" % [last_abs, last_pct * 100.0]
		])


# Costruisce il Dictionary esportato in JSON: per ogni combinazione, la scomposizione
# GRASS/SHRUB/TREE/ROCK all'anno di saturazione del TOTALE (o all'ultimo anno campionato se mai
# saturo), e FISH/BIRDS (valore + percentuale sulla propria capacita') al proprio anno di
# saturazione specifico (o ultimo anno se mai saturo).
func _build_composition_report(
	samples: Dictionary, fish_samples: Dictionary,
	veg_pct_history: Dictionary, veg_abs_history: Dictionary, veg_breakdown_history: Dictionary, veg_cap: Dictionary,
	fish_pct_history: Dictionary, fish_abs_history: Dictionary, fish_cap: Dictionary,
	birds_pct_history: Dictionary, birds_abs_history: Dictionary, birds_cap: Dictionary
) -> Dictionary:
	var keys := samples.keys()
	keys.sort()

	var combinations: Dictionary = {}

	for key in keys:
		var coords: Vector2i = samples[key]["coords"]
		var entry: Dictionary = {
			"sample_coords": [coords.x, coords.y],
		}

		if samples[key]["terrain"] != GameTypes.TerrainBase.WATER:
			var pct_series: Array = veg_pct_history[key]
			var abs_series: Array = veg_abs_history[key]
			var cap: int = veg_cap[key]
			var y := _find_saturation_year(pct_series, SATURATION_THRESHOLD)
			var used_year: int = y if y != -1 else (pct_series.size() - 1)
			var total_abs: int = abs_series[used_year]

			var breakdown: Dictionary = {}
			for rt in VEGETATION_TYPES:
				var rt_series: Array = veg_breakdown_history[key][rt]
				var rt_abs: int = rt_series[used_year]
				var rt_name: String = GameTypes.WorldObjectType.keys()[rt]
				breakdown[rt_name] = {
					"absolute": rt_abs,
					"pct_of_total_occupied": (float(rt_abs) / float(total_abs)) if total_abs > 0 else 0.0,
				}

			entry["vegetation"] = {
				"saturation_year": y, # -1 = mai saturo entro YEARS_TO_RUN
				"year_used_for_snapshot": used_year,
				"total_capacity": cap,
				"total_absolute": total_abs,
				"total_pct_of_capacity": float(total_abs) / float(cap) if cap > 0 else 0.0,
				"breakdown": breakdown,
			}

		var fish_info = fish_samples.get(key)
		if fish_info == null:
			entry["fish"] = null
		else:
			var f_pct_series: Array = fish_pct_history[key]
			var f_abs_series: Array = fish_abs_history[key]
			var f_cap: int = fish_cap.get(key, 0)
			var fy := _find_saturation_year(f_pct_series, SATURATION_THRESHOLD)
			var f_used_year: int = fy if fy != -1 else (f_pct_series.size() - 1)
			entry["fish"] = {
				"sample_coords": [fish_info["coords"].x, fish_info["coords"].y],
				"resampled_due_to_failed_seed": fish_info.get("resampled", false),
				"seed_failed_no_alternative_found": fish_info.get("seed_failed_no_alternative", false),
				"saturation_year": fy,
				"year_used_for_snapshot": f_used_year,
				"capacity": f_cap,
				"absolute": f_abs_series[f_used_year],
				"pct_of_capacity": float(f_abs_series[f_used_year]) / float(f_cap) if f_cap > 0 else 0.0,
			}

		var b_cap: int = birds_cap.get(key, 0)
		if b_cap <= 0:
			entry["birds"] = null
		else:
			var b_pct_series: Array = birds_pct_history[key]
			var b_abs_series: Array = birds_abs_history[key]
			var by := _find_saturation_year(b_pct_series, SATURATION_THRESHOLD)
			var b_used_year: int = by if by != -1 else (b_pct_series.size() - 1)
			entry["birds"] = {
				"saturation_year": by,
				"year_used_for_snapshot": b_used_year,
				"capacity": b_cap,
				"absolute": b_abs_series[b_used_year],
				"pct_of_capacity": float(b_abs_series[b_used_year]) / float(b_cap) if b_cap > 0 else 0.0,
			}

		combinations[key] = entry

	return {
		"map_file": MAP_FILE_PATH,
		"years_simulated": YEARS_TO_RUN,
		"saturation_threshold": SATURATION_THRESHOLD,
		"saturation_streak_required_years": SATURATION_STREAK_REQUIRED,
		"note": "saturation_year = -1 significa soglia mai raggiunta/mantenuta entro years_simulated; in quel caso year_used_for_snapshot e' l'ultimo anno campionato (asintotico, non un vero equilibrio). Nessun animale (PopulationGroup) presente durante questa misura.",
		"combinations": combinations,
	}


func _print_composition_report(composition: Dictionary) -> void:
	print("")
	print("=== SCOMPOSIZIONE ALL'ANNO DI SATURAZIONE (o ultimo anno campionato se mai saturo) ===")
	var combos: Dictionary = composition["combinations"]
	var keys := combos.keys()
	keys.sort()
	for key in keys:
		var entry: Dictionary = combos[key]
		print("--- %s ---" % key)
		if entry.has("vegetation"):
			var v: Dictionary = entry["vegetation"]
			var y_label := str(v["saturation_year"]) if v["saturation_year"] != -1 else ("MAI (asintotico anno %d)" % v["year_used_for_snapshot"])
			print("  Vegetazione: anno=%s totale=%d/%d (%.1f%%)" % [
				y_label, v["total_absolute"], v["total_capacity"], v["total_pct_of_capacity"] * 100.0
			])
			for rt_name in v["breakdown"].keys():
				var b: Dictionary = v["breakdown"][rt_name]
				print("    %-6s abs=%-6d pct_su_totale=%.1f%%" % [rt_name, b["absolute"], b["pct_of_total_occupied"] * 100.0])
		else:
			print("  Vegetazione: N/A (cella acquatica)")

		if entry["fish"] == null:
			print("  FISH: N/A (nessuna acqua sfruttabile per questa combinazione)")
		else:
			var f: Dictionary = entry["fish"]
			var fy_label := str(f["saturation_year"]) if f["saturation_year"] != -1 else ("MAI (asintotico anno %d)" % f["year_used_for_snapshot"])
			var resample_note := " [ricampionato]" if f["resampled_due_to_failed_seed"] else ""
			print("  FISH%s: anno=%s val=%d/%d (%.1f%%)" % [
				resample_note, fy_label, f["absolute"], f["capacity"], f["pct_of_capacity"] * 100.0
			])

		if entry["birds"] == null:
			print("  BIRDS: N/A")
		else:
			var b2: Dictionary = entry["birds"]
			var by_label := str(b2["saturation_year"]) if b2["saturation_year"] != -1 else ("MAI (asintotico anno %d)" % b2["year_used_for_snapshot"])
			print("  BIRDS: anno=%s val=%d/%d (%.1f%%)" % [
				by_label, b2["absolute"], b2["capacity"], b2["pct_of_capacity"] * 100.0
			])


func _write_composition_json(composition: Dictionary) -> void:
	var file := FileAccess.open(OUTPUT_JSON_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Impossibile scrivere %s (errore %d)" % [OUTPUT_JSON_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(composition, "\t"))
	file.close()
	print("")
	print("Composizione di equilibrio esportata in: %s" % OUTPUT_JSON_PATH)
