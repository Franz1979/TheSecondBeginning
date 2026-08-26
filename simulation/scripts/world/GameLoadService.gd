class_name GameLoadService
extends RefCounted

func load_game_from_json(file_path: String) -> LoadedGame:
	if not FileAccess.file_exists(file_path):
		print("File salvataggio non trovato: ", file_path)
		return null
	var file := FileAccess.open(file_path, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()
	var data = JSON.parse_string(json_text)
	if data == null:
		print("Errore nella lettura del JSON: ", file_path)
		return null
	if not data.has("file_type") or data["file_type"] != "game_save":
		push_error("Il file selezionato non è una partita salvata.")
		return null

	var game_data := GameData.new()
	game_data.year = int(data["game"]["year"])
	game_data.current_day = int(data["game"].get("current_day", 0))
	# .get(key, default) per compatibilita' con save precedenti l'introduzione della statistica
	# di difficolta' (vedi GameData) — stringhe vuote/-1.0 sono gli stessi default della classe.
	game_data.starting_world_age_mode = String(data["game"].get("starting_world_age_mode", ""))
	game_data.starting_animal_density = String(data["game"].get("starting_animal_density", ""))
	game_data.starting_population_size = String(data["game"].get("starting_population_size", ""))
	game_data.starting_exclude_hostile_start = bool(data["game"].get("starting_exclude_hostile_start", false))
	game_data.starting_exclude_predator_territories = bool(data["game"].get("starting_exclude_predator_territories", false))
	game_data.starting_resource_richness_preference = String(data["game"].get("starting_resource_richness_preference", ""))
	game_data.starting_group_size_preference = String(data["game"].get("starting_group_size_preference", ""))
	game_data.starting_guarantee_animal_presence = bool(data["game"].get("starting_guarantee_animal_presence", false))
	game_data.starting_difficulty_ratio = float(data["game"].get("starting_difficulty_ratio", -1.0))
	# .get(key, -1) per compatibilita' con save precedenti l'introduzione della sede player
	# (vedi GameData) — -1 è lo stesso default "mai inizializzata" della classe.
	game_data.player_macro_cell_x = int(data["game"].get("player_macro_cell_x", -1))
	game_data.player_macro_cell_y = int(data["game"].get("player_macro_cell_y", -1))
	# .get(key, -1.0) per compatibilità con save precedenti l'introduzione della posizione micro
	# del player (vedi GameData) — -1.0 è lo stesso default "mai valorizzata" della classe.
	game_data.player_micro_x = float(data["game"].get("player_micro_x", -1.0))
	game_data.player_micro_y = float(data["game"].get("player_micro_y", -1.0))
	# .get(key, -1.0) per compatibilità con save precedenti l'introduzione dello zoom camera
	# (vedi GameData) — -1.0 è lo stesso default "mai valorizzato" della classe.
	game_data.camera_zoom = float(data["game"].get("camera_zoom", -1.0))

	var world_data = data["world"]
	var world := World.new()

	world.cells.clear()
	for cell_data in world_data["cells"]:
		var cell := MacroCellData.new(
			int(cell_data["x"]),
			int(cell_data["y"])
		)
		cell.terrain_base = int(cell_data["terrain_base"])
		cell.water_type = int(cell_data["water_type"])
		cell.river_shape = int(cell_data.get("river_shape", GameTypes.RiverShape.NONE))
		cell.coast_type = int(cell_data["coast_type"])
		cell.biome = int(cell_data["biome"])
		world.cells.append(cell)

	world.cell_states.clear()
	if world_data.has("cell_states"):
		for state_data in world_data["cell_states"]:
			var state := MacroCellState.new(
				int(state_data["x"]),
				int(state_data["y"])
			)
			var quantity_data = state_data.get("resource_quantity", {})
			for key in quantity_data.keys():
				state.resource_quantity[int(key)] = int(quantity_data[key])
			var dedicated = state_data.get("dedicated_space", {})
			for key in dedicated.keys():
				state.dedicated_space[int(key)] = int(dedicated[key])
			var has_ever_grown_data = state_data.get("has_ever_grown", {})
			for key in has_ever_grown_data.keys():
				state.has_ever_grown[int(key)] = bool(has_ever_grown_data[key])
			var subtype_data = state_data.get("subtype_composition", {})
			for type_key in subtype_data.keys():
				var inner: Dictionary = {}
				for subtype_name in subtype_data[type_key].keys():
					inner[subtype_name] = int(subtype_data[type_key][subtype_name])
				state.subtype_composition[int(type_key)] = inner
			# Stesso pattern di subtype_composition sopra, un livello di nesting in più
			# (WorldObjectType -> subtype_name -> AgeBand -> int). .get(key, {}) per compatibilità
			# con save precedenti a questa feature (che non hanno affatto la chiave).
			var age_data = state_data.get("age_composition", {})
			for type_key in age_data.keys():
				var inner_subtypes: Dictionary = {}
				for subtype_name in age_data[type_key].keys():
					var inner_ages: Dictionary = {}
					for age_key in age_data[type_key][subtype_name].keys():
						inner_ages[int(age_key)] = int(age_data[type_key][subtype_name][age_key])
					inner_subtypes[subtype_name] = inner_ages
				state.age_composition[int(type_key)] = inner_subtypes
			state.river_space = int(state_data.get("river_space", 0))
			var water_space_data = state_data.get("water_dedicated_space", {})
			for key in water_space_data.keys():
				state.water_dedicated_space[int(key)] = int(water_space_data[key])
			var terrestrial_space_data = state_data.get("terrestrial_dedicated_space", {})
			for key in terrestrial_space_data.keys():
				state.terrestrial_dedicated_space[int(key)] = int(terrestrial_space_data[key])
			var pending_surplus_data = state_data.get("pending_migration_surplus", {})
			for key in pending_surplus_data.keys():
				state.pending_migration_surplus[int(key)] = float(pending_surplus_data[key])
			var secondary_stock_data = state_data.get("secondary_resource_stock", {})
			for resource_name in secondary_stock_data.keys():
				state.secondary_resource_stock[resource_name] = float(secondary_stock_data[resource_name])
			state.pending_grass_space_debt = float(state_data.get("pending_grass_space_debt", 0.0))
			state.pending_fish_space_debt = float(state_data.get("pending_fish_space_debt", 0.0))
			state.pending_bird_space_debt = float(state_data.get("pending_bird_space_debt", 0.0))
			if state_data.has("stone_positions"):
				var stone_positions: Array = []
				for pos_data in state_data["stone_positions"]:
					stone_positions.append(Vector2i(int(pos_data["x"]), int(pos_data["y"])))
				state.stone_positions = stone_positions
				state.stone_positions_generated = true
			var bonuses_data = state_data.get("active_growth_bonuses", {})
			for key in bonuses_data.keys():
				var bonus_data = bonuses_data[key]
				state.active_growth_bonuses[int(key)] = {
					"multiplier": float(bonus_data["multiplier"]),
					"trigger_absolute_day": int(bonus_data["trigger_absolute_day"]),
					"duration_years": int(bonus_data["duration_years"])
				}
			world.cell_states.append(state)

	world.population_groups.clear()
	if world_data.has("population_groups"):
		for group_data in world_data["population_groups"]:
			var occupied_cells: Array[Vector2i] = []
			for cell_data in group_data.get("occupied_macrocells", []):
				occupied_cells.append(Vector2i(int(cell_data["x"]), int(cell_data["y"])))
			# Nessuna retrocompatibilità con il vecchio formato home_macrocell_x/y (pre-Territory):
			# un save di prima dello Step 4 non ha "occupied_macrocells" e produrrebbe un Territory
			# vuoto — invalido (Territory.get_primary_cell() richiede almeno una cella) e quindi
			# scartato qui, invece di propagare un gruppo rotto che crasherebbe al primo utilizzo.
			if occupied_cells.is_empty():
				continue
			var group := PopulationGroup.new(
				String(group_data["species_name"]),
				Territory.new(occupied_cells),
				# .get(key, 0) per compatibilità con save precedenti l'introduzione dell'id: 0 =
				# mai assegnato — world.next_population_group_id sotto viene comunque ricalcolato
				# a valle del loop così le prossime allocazioni non collidono con questi gruppi.
				int(group_data.get("id", 0))
			)
			group.population = int(group_data["population"])
			var age_data = group_data.get("age_composition", {})
			for age_key in age_data.keys():
				group.age_composition[int(age_key)] = int(age_data[age_key])
			# .get(key, {}) per compatibilità con save precedenti l'introduzione della mortalità
			# da fame, che non hanno affatto questo campo (vedi AnimalHungerService).
			var hunger_data = group_data.get("hunger_buckets", {})
			for hunger_key in hunger_data.keys():
				group.hunger_buckets[int(hunger_key)] = int(hunger_data[hunger_key])
			# .get(key, 1.0) per compatibilità con save precedenti la correzione del bug
			# (birth_mitigation_multiplier non veniva salvato) — 1.0 = nessuna penalità, stesso
			# default della classe, comportamento invariato per quei save. set_ (non assegnazione
			# diretta) per applicare comunque il clamp a MULTIPLIER_ABUNDANCE_CAP.
			group.set_birth_mitigation_multiplier(float(group_data.get("birth_mitigation_multiplier", 1.0)))
			# .get(key, 1.0) per compatibilità con save precedenti l'introduzione di questo campo
			# (solo per il log, vedi PopulationGroup.birth_mitigation_caloric_ratio) — 1.0 è lo
			# stesso default della classe.
			group.birth_mitigation_caloric_ratio = float(group_data.get("birth_mitigation_caloric_ratio", 1.0))
			# .get(key, -1) per compatibilità con save precedenti l'introduzione dello split
			# (Step 9/10) — -1 = "mai scisso", stesso default della classe, comportamento
			# invariato per quei save.
			group.years_since_last_split = int(group_data.get("years_since_last_split", -1))
			# .get(key, 0) per compatibilità con save precedenti l'introduzione del cooldown
			# (Step 11) — 0 = nessun cooldown attivo, stesso default della classe.
			group.hunger_split_cooldown_days = int(group_data.get("hunger_split_cooldown_days", 0))
			# .get(key, default) per compatibilità con save precedenti l'introduzione dei predatori
			# — 0/1/0.0/0.0 sono gli stessi default di PopulationGroup.gd (percorso mai camminato,
			# nessun debito/surplus). Caricati PRIMA del ricalcolo di patrol_route sotto: quella
			# chiamata deve trovare patrol_index/patrol_direction già al loro valore reale, non li
			# tocca comunque (reset_progress=false), ma l'ordine di scrittura resta esplicito per
			# chiarezza — mai un momento in cui il gruppo ha un indice "vecchio" letto insieme a un
			# percorso "nuovo" incoerente tra loro (qui coincidono comunque, vedi sotto).
			group.patrol_index = int(group_data.get("patrol_index", 0))
			group.patrol_direction = int(group_data.get("patrol_direction", 1))
			group.predation_calorie_debt = float(group_data.get("predation_calorie_debt", 0.0))
			group.predation_surplus_carryover = float(group_data.get("predation_surplus_carryover", 0.0))
			# .get(key, 0.0) per compatibilità con save precedenti l'introduzione della mitigazione
			# natalità predatori (vedi AnimalBirthMitigationService.compute_predator_caloric_ratio) —
			# 0.0/0.0 sono gli stessi default di PopulationGroup.gd.
			group.predation_season_calories_obtained = float(group_data.get("predation_season_calories_obtained", 0.0))
			group.predation_season_calories_required = float(group_data.get("predation_season_calories_required", 0.0))
			# .get(key, 0.0) per compatibilità con save precedenti l'introduzione della mortalità da
			# fame aggregata (AnimalHungerMortalityAggregateService) — 0.0 = nessun debito accumulato,
			# stesso default della classe.
			group.hunger_debt_days = float(group_data.get("hunger_debt_days", 0.0))
			# recent_hunt_log/yearly_prey_totals (tab Fauna 3, UI) — .get(key, []/{}/{})/-1 per
			# compatibilità con save precedenti l'introduzione di questi campi. Ogni valore
			# numerico ri-castato esplicitamente (int/float): JSON non distingue i due tipi allo
			# stesso modo di GDScript, stesso principio già seguito ovunque in questo file.
			for hunt_entry_data in group_data.get("recent_hunt_log", []):
				var captures_data: Dictionary = hunt_entry_data.get("captures", {})
				var captures: Dictionary = {}
				for species_name in captures_data.keys():
					var species_data: Dictionary = captures_data[species_name]
					captures[species_name] = {
						"quantity": int(species_data.get("quantity", 0)),
						"calories": float(species_data.get("calories", 0.0))
					}
				group.recent_hunt_log.append({
					"year": int(hunt_entry_data.get("year", 0)),
					"day": int(hunt_entry_data.get("day", 0)),
					"captures": captures
				})
			var yearly_totals_data: Dictionary = group_data.get("yearly_prey_totals", {})
			for species_name in yearly_totals_data.keys():
				var species_totals: Dictionary = yearly_totals_data[species_name]
				group.yearly_prey_totals[species_name] = {
					"quantity": int(species_totals.get("quantity", 0)),
					"calories": float(species_totals.get("calories", 0.0))
				}
			group.yearly_prey_totals_year = int(group_data.get("yearly_prey_totals_year", -1))
			# patrol_route non è mai salvato (dato derivato, vedi GameSaveService) — per un
			# gruppo predatore va ricostruito qui, una volta, subito dopo che il territorio è
			# stato ricreato sopra (Territory.new(occupied_cells)). reset_progress=false: il
			# territorio non è cambiato rispetto al salvataggio (stesse celle, stesso ordine,
			# stesso _build_route deterministico => percorso identico bit per bit a quello di
			# prima del salvataggio), quindi patrol_index/patrol_direction appena caricati sopra
			# restano validi e NON vanno riazzerati come farebbe una ricostruzione normale
			# (territorio davvero cambiato, vedi PredatorPatrolService.recompute_route). Specie
			# senza PredatorRules (tutti gli erbivori): rules is PredatorRules è false, questo
			# blocco è no-op, patrol_route/patrol_index/patrol_direction restano ai default della
			# classe (mai letti da nessun service erbivoro-generico).
			var rules := AnimalCalculator.get_animal_rules(group.species_name)
			if rules is PredatorRules:
				PredatorPatrolService.new().recompute_route(group, rules as PredatorRules, false)
			world.population_groups.append(group)

	# Nessun campo dedicato per il contatore nel JSON: ricalcolato da max(id caricati)+1 così le
	# prossime allocazioni (world.allocate_population_group_id) non collidono mai con quelli
	# appena caricati, anche se il save è precedente all'introduzione di questo campo (id=0 per
	# tutti i gruppi -> riparte comunque da 1).
	var max_loaded_id := 0
	for group in world.population_groups:
		max_loaded_id = max(max_loaded_id, group.id)
	world.next_population_group_id = max_loaded_id + 1

	# Fog of war (vedi GameSaveService per il formato) — .get(key, []) per compatibilità con save
	# precedenti l'introduzione di questa sezione: un dizionario vuoto è lo stesso comportamento
	# di sempre (GameScene riparte con fog vuota per ogni macrocella, come faceva sempre prima di
	# questa feature).
	var fog_of_war_memories: Dictionary = {}
	for cell_fog_data in data.get("fog_of_war", []):
		var coords := Vector2i(int(cell_fog_data["macro_x"]), int(cell_fog_data["macro_y"]))
		var memory := FogOfWarMemory.new()
		for entry in cell_fog_data.get("last_seen", []):
			var pos := Vector2i(int(entry["x"]), int(entry["y"]))
			memory.last_seen_by_position[pos] = int(entry["day"])
		fog_of_war_memories[coords] = memory

	var loaded_game := LoadedGame.new()
	loaded_game.world = world
	loaded_game.game_data = game_data
	loaded_game.fog_of_war_memories = fog_of_war_memories
	print("Game loaded from JSON: ", file_path)
	return loaded_game
