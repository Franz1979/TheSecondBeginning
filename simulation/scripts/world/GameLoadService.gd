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

	# TaskDebugRegistry (2026-09-12, richiesta utente — fix righe duplicate/fantasma nel pannello di
	# debug 🐞) — registro STATIC (vita di processo), mai svuotato automaticamente tra due
	# caricamenti nella stessa sessione di Godot: senza questo clear(), un individuo con una Task
	# ancora "in corso" al momento del salvataggio manterrebbe qui la sua vecchia riga aperta (mai
	# chiusa, dato che un salvataggio non passa da stop()/assign_task), e la riga NUOVA registrata
	# poco sotto per la Task ricostruita da questo stesso reload si affiancherebbe ad essa invece di
	# continuarla — due righe "in corso" per lo stesso individuo. clear() qui rende vero quanto già
	# documentato in TaskDebugRegistry.gd ("un reload parte con la lista vuota"), PRIMA che
	# individui/Task vengano ricostruiti sotto.
	TaskDebugRegistry.clear()

	var game_data := GameData.new()
	game_data.year = int(data["game"]["year"])
	game_data.current_day = int(data["game"].get("current_day", 0))
	# Sincronizza SUBITO il giorno assoluto noto a TaskDebugRegistry (2026-09-13, richiesta utente,
	# pulizia temporale del pannello debug 🐞) — senza questa riga, _current_absolute_day
	# resterebbe al valore stantio di una sessione precedente (o 0, mai avanzato in questa sessione
	# di Godot) fino al prossimo vero avanzamento giorno, rischiando di stampare un
	# closed_at_absolute_day sbagliato su un'entry chiusa PRIMA di quel prossimo tick (es. un
	# individuo che finisce/interrompe la propria Task ricostruita nello stesso frame del reload).
	TaskDebugRegistry.on_day_advanced(game_data.get_absolute_day())
	# .get(key, default) per compatibilità con save precedenti l'introduzione dell'Era (vedi
	# GameData) — "paleolithic"/[] sono gli stessi default della classe (cache vuota finché nessuno
	# ha mai chiamato set_current_era, esattamente come una partita nuova oggi).
	game_data.current_era_name = String(data["game"].get("current_era_name", "paleolithic"))
	game_data.era_effective_age_band_durations_male = _float_array_from_json(
		data["game"].get("era_effective_age_band_durations_male", [])
	)
	game_data.era_effective_age_band_durations_female = _float_array_from_json(
		data["game"].get("era_effective_age_band_durations_female", [])
	)
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
	game_data.starting_guarantee_stone_presence = bool(data["game"].get("starting_guarantee_stone_presence", false))
	game_data.starting_difficulty_ratio = float(data["game"].get("starting_difficulty_ratio", -1.0))
	# .get(key, -1) per compatibilita' con save precedenti l'introduzione della sede player
	# (vedi GameData) — -1 è lo stesso default "mai inizializzata" della classe.
	game_data.player_macro_cell_x = int(data["game"].get("player_macro_cell_x", -1))
	game_data.player_macro_cell_y = int(data["game"].get("player_macro_cell_y", -1))
	# .get(key, -1) — -1 è lo stesso default "nessun bersaglio persistito" della classe (vedi
	# GameData — sostituisce player_micro_x/y, rimossi: la posizione viaggia ora dentro la sezione
	# "human" sotto, per ogni individuo).
	game_data.player_individual_id = int(data["game"].get("player_individual_id", -1))
	# .get(key, -1.0) per compatibilità con save precedenti l'introduzione dello zoom camera
	# (vedi GameData) — -1.0 è lo stesso default "mai valorizzato" della classe.
	game_data.camera_zoom = float(data["game"].get("camera_zoom", -1.0))
	# .get(key, 0.0/0.0/false) per compatibilità con save precedenti l'introduzione della posizione
	# camera (vedi GameData) — stessi default "mai valorizzata" della classe.
	game_data.camera_x = float(data["game"].get("camera_x", 0.0))
	game_data.camera_y = float(data["game"].get("camera_y", 0.0))
	game_data.camera_position_saved = bool(data["game"].get("camera_position_saved", false))
	game_data.thought_building_tech_tree_shown = bool(data["game"].get("thought_building_tech_tree_shown", false))
	# .get(key, 0) per compatibilità con save precedenti l'introduzione della pulizia
	# periodica del fog of war (vedi GameData) — 0 è lo stesso default della classe.
	game_data.fog_of_war_last_prune_absolute_day = int(data["game"].get("fog_of_war_last_prune_absolute_day", 0))
	# .get(key, []) per compatibilità con save precedenti l'introduzione del log morti (Step 8,
	# vedi GameData.death_events) — [] è lo stesso default della classe.
	game_data.death_events = _dictionary_array_from_json(data["game"].get("death_events", []))
	# .get(key, []) per compatibilità con save precedenti l'introduzione del log nascite (Step 2
	# piano statistiche, 2026-09-06, vedi GameData.birth_events) — [] è lo stesso default della
	# classe, stesso trattamento di death_events sopra.
	game_data.birth_events = _dictionary_array_from_json(data["game"].get("birth_events", []))
	# .get(key, {}) per compatibilità con save precedenti l'introduzione dello snapshot
	# popolazione (Step 3 piano statistiche, 2026-09-06, vedi GameData.population_snapshots) — {}
	# è lo stesso default della classe. _population_snapshots_from_json riconverte le chiavi da
	# String (sempre così dopo JSON.parse_string, JSON non ha chiavi non-stringa) a int.
	game_data.population_snapshots = _population_snapshots_from_json(data["game"].get("population_snapshots", {}))
	# .get(key, {}) per compatibilità con save precedenti l'introduzione dello snapshot edifici
	# (2026-09-12, tab Statistiche/Edifici, vedi GameData.building_snapshots) — {} è lo stesso
	# default della classe. Riusa _population_snapshots_from_json (stesso identico schema chiave
	# int -> valore int, nessuna seconda funzione identica da mantenere in parallelo).
	game_data.building_snapshots = _population_snapshots_from_json(data["game"].get("building_snapshots", {}))
	# .get(key, []) per compatibilità con save precedenti l'introduzione degli oggetti-scaduti
	# (Step 2, vedi GameData.expired_objects) — [] è lo stesso default della classe.
	game_data.expired_objects = _expired_objects_from_json(data["game"].get("expired_objects", []))
	# .get(key, 1) per compatibilità con save precedenti l'introduzione dell'allocatore id
	# HumanIndividual (vedi GameData.next_human_id) — 1 è lo stesso default della classe. Letto
	# diretto dal JSON, MAI ricalcolato da max(id caricati)+1: vedi il commento sul campo per il
	# perché quel pattern (usato invece per next_population_group_id/next_building_id sotto)
	# sarebbe sbagliato qui.
	game_data.next_human_id = int(data["game"].get("next_human_id", 1))

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
			# LOD0: assente = false (mai scoperta), vedi GameSaveService per il perché è condizionale.
			state.has_ever_been_discovered = bool(state_data.get("has_ever_been_discovered", false))
			state.vegetation_feeding_active = bool(state_data.get("vegetation_feeding_active", false))
			state.grass_seed_baseline = int(state_data.get("grass_seed_baseline", -1))
			if state_data.has("stone_positions"):
				var stone_positions: Array = []
				for pos_data in state_data["stone_positions"]:
					stone_positions.append(Vector2i(int(pos_data["x"]), int(pos_data["y"])))
				state.stone_positions = stone_positions
				state.stone_positions_generated = true
				# PEBBLE — nasce/vive insieme a stone_positions (vedi GameSaveService), ora
				# ricaricato dal registro unificato "lot_registry" sotto, non più da una sezione
				# dedicata.
			for pos_data in state_data.get("vegetation_cut_exceptions", []):
				var cut_key := Vector3i(int(pos_data["x"]), int(pos_data["y"]), int(pos_data["i"]))
				state.vegetation_cut_exceptions[cut_key] = {
					"origin_type": int(pos_data["origin_type"]),
					"cut_year": int(pos_data["cut_year"]),
					"size_multiplier": float(pos_data.get("size_multiplier", 1.0))
				}
			# Vector3i: "i" assente (.get(..., 0)) copre solo le entry già scritte in questa stessa
			# sessione di sviluppo col vecchio formato bacato (x,y senza indice) — non un requisito
			# di compatibilità reale, dato lo stadio del progetto.
			for pos_data in state_data.get("tree_virtual_birth_year", []):
				var tree_key := Vector3i(int(pos_data["x"]), int(pos_data["y"]), int(pos_data.get("i", 0)))
				state.tree_virtual_birth_year[tree_key] = int(pos_data["year"])
			for pos_data in state_data.get("shrub_virtual_birth_year", []):
				var shrub_key := Vector3i(int(pos_data["x"]), int(pos_data["y"]), int(pos_data.get("i", 0)))
				state.shrub_virtual_birth_year[shrub_key] = int(pos_data["year"])
			for pos_data in state_data.get("tree_individual_subtype", []):
				var tree_subtype_key := Vector3i(int(pos_data["x"]), int(pos_data["y"]), int(pos_data["i"]))
				state.tree_individual_subtype[tree_subtype_key] = String(pos_data["subtype"])
			for pos_data in state_data.get("shrub_individual_subtype", []):
				var shrub_subtype_key := Vector3i(int(pos_data["x"]), int(pos_data["y"]), int(pos_data["i"]))
				state.shrub_individual_subtype[shrub_subtype_key] = String(pos_data["subtype"])
			for pos_data in state_data.get("tree_claimed_lots", []):
				state.tree_claimed_lots[Vector2i(int(pos_data["x"]), int(pos_data["y"]))] = true
			for pos_data in state_data.get("shrub_claimed_lots", []):
				state.shrub_claimed_lots[Vector2i(int(pos_data["x"]), int(pos_data["y"]))] = true
			# Registro unificato "capacita per lotto" (2026-09-19, richiesta utente, refactor
			# lot_source) - un solo loop su tutte le entry salvate (una per resource_name presente:
			# pebble/stick/plant_fiber/mushroom/wild_vegetables), stesso principio gia in uso per
			# berry_harvested_by_lot sotto. resource_entry.get("resource_name", "") vuoto -> entry
			# scartata (mai un formato precedente a questo refactor: "NON serve retrocompatibilita
			# con i salvataggi esistenti", richiesta esplicita utente). Solo il registro
			# "raccolto/residuo" viene ricaricato qui - la "capacity" delle risorse non-STONE_
			# POSITION e una cache RUNTIME (MacroCellState.lot_capacity_cache), mai persistita, si
			# ripopola da sola alla prima query/refresh dopo il load.
			for resource_entry in state_data.get("lot_registry", []):
				var lot_resource_name: String = String(resource_entry.get("resource_name", ""))
				if lot_resource_name == "":
					continue
				var lot_registry_per_lot: Dictionary = {}
				for pos_data in resource_entry.get("lots", []):
					lot_registry_per_lot[Vector2i(int(pos_data["x"]), int(pos_data["y"]))] = int(pos_data["v"])
				state.lot_registry[lot_resource_name] = lot_registry_per_lot
			# Raccolto per lotto delle risorse "fruit stock" (2026-09-17, richiesta utente — poi
			# GENERALIZZATO in preparazione di fruit/acorn, nessun cambio di comportamento per
			# berry) — un solo blocco che itera le entry salvate (una per resource_name presente,
			# oggi solo "berry"), .get() con default [] per compatibilità coi save precedenti a
			# questo campo. resource_entry.get("resource_name", "") (BUGFIX, non un ["resource_
			# name"] diretto: un save precedente al formato annidato per risorsa aveva qui il
			# vecchio formato flat {x,y,harvested} SENZA questa chiave — "Invalid access to
			# property or key" su un salvataggio vecchio, segnalato dall'utente) — resource_name
			# vuoto = entry nel vecchio formato, scartata: nessuna migrazione del raccolto pre-
			# refactor, comportamento accettato esplicitamente dall'utente ("non è retrocompatibile,
			# non fa niente").
			for resource_entry in state_data.get("berry_harvested_by_lot", []):
				var resource_name: String = String(resource_entry.get("resource_name", ""))
				if resource_name == "":
					continue
				var per_lot: Dictionary = {}
				for pos_data in resource_entry.get("lots", []):
					per_lot[Vector2i(int(pos_data["x"]), int(pos_data["y"]))] = int(pos_data["harvested"])
				state.berry_harvested_by_lot[resource_name] = per_lot
			# Raccolto per nido di "eggs" (2026-09-18, richiesta utente) — SIBLING del blocco
			# berry_harvested_by_lot sopra, formato FLAT {x,y,harvested} (stesso motivo di
			# GameSaveService — eggs è l'unica risorsa di questa famiglia, vedi MacroCellState.
			# eggs_harvested_by_lot). .get() con default [] per compatibilità coi save precedenti a
			# questo campo, stesso principio di ogni altro blocco opzionale in questa funzione.
			for pos_data in state_data.get("eggs_harvested_by_lot", []):
				var eggs_pos := Vector2i(int(pos_data["x"]), int(pos_data["y"]))
				state.eggs_harvested_by_lot[eggs_pos] = int(pos_data["harvested"])
			# wild_vegetables (2026-09-19) — ora nel registro unificato "lot_registry" sopra, non
			# più in una sezione dedicata.
			for pos_data in state_data.get("vegetation_death_exceptions", []):
				var death_key := Vector3i(int(pos_data["x"]), int(pos_data["y"]), int(pos_data["i"]))
				state.vegetation_death_exceptions[death_key] = {
					"origin_type": int(pos_data["origin_type"]),
					"death_year": int(pos_data["death_year"]),
					"size_multiplier": float(pos_data.get("size_multiplier", 1.0))
				}
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

	# Edifici piazzati (vedi GameSaveService per il formato) — .get(key, []) per compatibilità con
	# save precedenti l'introduzione del sistema di building: nessuna chiave "buildings" -> array
	# vuoto, stesso comportamento di un mondo appena creato senza edifici. Un building_type_name
	# non più risolvibile in BuildingCalculator (rules == null, es. .tres rimosso/rinominato) viene
	# scartato invece di propagare un Building con rules nulla che crasherebbe al primo utilizzo.
	world.buildings.clear()
	if world_data.has("buildings"):
		for building_data in world_data["buildings"]:
			var building_type_name := String(building_data.get("building_type_name", ""))
			var building_rules := BuildingCalculator.get_building_rules(building_type_name)
			if building_rules == null:
				continue
			var building := Building.new(
				building_rules,
				int(building_data["macro_x"]),
				int(building_data["macro_y"]),
				building_type_name
			)
			building.id = int(building_data.get("id", 0))
			building.micro_x = int(building_data.get("micro_x", 0))
			building.micro_y = int(building_data.get("micro_y", 0))
			building.construction_started_day = int(building_data.get("construction_started_day", -1))
			building.is_complete = bool(building_data.get("is_complete", false))
			# site_setup_complete (2026-09-11, richiesta utente) — .get(key, building.is_complete),
			# non un semplice `false`, per compatibilità con save salvati PRIMA che questo campo
			# esistesse: quei save non conoscevano la fase "cantiere in attesa" e ogni edificio lì
			# presente era già completo (is_complete=true — MicroCellRenderer non usa comunque
			# site_setup_complete quando is_complete è true, vedi _draw_buildings) — usare is_complete
			# come fallback evita comportamenti diversi tra un edificio pre-esistente e uno nuovo, pur
			# senza che sia mai osservabile oggi (nessun save pre-esistente ha davvero is_complete=
			# false, la Build Task è arrivata dopo).
			building.site_setup_complete = bool(building_data.get("site_setup_complete", building.is_complete))
			building.current_durability = int(building_data.get("current_durability", 0))
			building.built_year = int(building_data.get("built_year", -1))
			# stored_resources (2026-09-09, richiesta utente, Step 3 decadimento) — formato cambiato
			# da resource_name -> int diretto a resource_name -> {"quantity","decay_fraction"} (vedi
			# BuildingStorageService/Building.gd). _parse_stored_resources sotto gestisce ENTRAMBI i
			# formati per voce, cosi' un save salvato PRIMA di questo passo (dove stored_resources
			# era comunque sempre vuoto in pratica, ma la retrocompatibilità resta corretta anche se
			# non lo fosse stato) continua a caricare senza perdere dati — un intero vecchio letto
			# come {"quantity": vecchio_intero, "decay_fraction": 0.0}, mai un breaking change.
			building.stored_resources = _parse_stored_resources(building_data.get("stored_resources", {}))
			# construction_progress (2026-09-10, richiesta utente — preparazione Build Task; primi
			# consumatori arrivati il 2026-09-11 con BuildAction/SetupSiteAction/ClearAction) —
			# .get(key, {}) per compatibilità con save precedenti l'introduzione del campo, stesso
			# pattern già usato per ogni altro campo opzionale in questo file. Nessun parsing dedicato
			# come _parse_stored_resources sopra: il contenuto ("site_setup_days_done"/
			# "clear_days_done"/"labor_accumulated", tutti float) passa così com'è — CONFERMATO
			# (2026-09-11) che basta per tutte e tre: ognuna delle tre Action legge sempre con
			# float(...get(key, 0.0)), quindi tollera sia un float che un intero tornato dal parsing
			# JSON (che non distingue int/float, ogni numero torna come float), nessun cast/
			# retrocompatibilità aggiuntiva necessaria qui.
			building.construction_progress = building_data.get("construction_progress", {})
			# enabled_categories (2026-09-09, richiesta utente) — .get(key, []) per compatibilità
			# con save precedenti l'introduzione del campo, stesso principio già usato per ogni
			# altro campo opzionale in questo file. int() esplicito per voce (non un .assign()
			# diretto): JSON non distingue int/float, ogni numero torna dal parsing come float
			# (stesso motivo per cui tree_claimed_lots sopra fa int(pos_data["x"]) invece di un
			# cast di massa) — un float lasciato dentro un Array[SecondaryResourceTypes.Category]
			# (Array tipizzato int-backed) sarebbe un dato incoerente rispetto a come questo stesso
			# campo viene scritto altrove (sempre veri int).
			var enabled_categories: Array[SecondaryResourceTypes.Category] = []
			for category_value in building_data.get("enabled_categories", []):
				enabled_categories.append(int(category_value))
			building.enabled_categories = enabled_categories
			building.rotation = int(building_data.get("rotation", GameTypes.Direction.SOUTH))
			# is_awaiting_material (2026-09-14, richiesta utente) — .get(key, false) per compatibilità
			# con save precedenti l'introduzione del campo, stesso principio di enabled_categories
			# sopra: un cantiere di un save vecchio riparte semplicemente "non in attesa" (il prossimo
			# controllo giornaliero/attivazione di SetupSiteAction lo ricalcola comunque da zero se
			# necessario, vedi Building.gd).
			building.is_awaiting_material = bool(building_data.get("is_awaiting_material", false))
			world.buildings.append(building)

	var max_loaded_building_id := 0
	for building in world.buildings:
		max_loaded_building_id = max(max_loaded_building_id, building.id)
	world.next_building_id = max_loaded_building_id + 1

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

	# Popolo umano del player (vedi GameSaveService per il formato) — assente (nessuna chiave
	# "human") per un salvataggio precedente questa feature o mai passato da una partita con
	# popolo seminato: in quel caso i tre campi restano ai default di LoadedGame (null/null/[]) e
	# GameScene prende il ramo "semina fresco", esattamente come farebbe senza alcuna sezione
	# "human" scritta. human_rules_ref (Folk) NON è valorizzato qui — path fisso di competenza di
	# GameScene (stesso motivo per cui HumanSeedingService non lo carica da sé, vedi lì: "un domani
	# con piu' Folk questo path fisso andra' sostituito da una vera risoluzione per Folk", non
	# ancora il caso), il chiamante lo assegna dopo aver ricevuto questo Folk esattamente come fa
	# già per un Folk appena seminato.
	var human_folk: Folk = null
	var human_population_group: HumanPopulationGroup = null
	var human_individuals: Array[HumanIndividual] = []
	if data.has("human"):
		var human_data: Dictionary = data["human"]
		human_folk = Folk.new()
		human_folk.id = int(human_data["folk"]["id"])
		human_folk.name = String(human_data["folk"]["name"])
		# .get() con un default per ciascuno (2026-09-07, richiesta utente) — a differenza di
		# id/name sopra, questi campi sono più recenti dei salvataggi esistenti: compatibilità coi
		# save precedenti, stesso principio già usato altrove nel file per campi opzionali. Dictionary/
		# Array assegnati diretti (stesso trattamento di Building.stored_resources sopra), nessun
		# ciclo di conversione per-valore necessario.
		human_folk.thoughts_count = int(human_data["folk"].get("thoughts_count", 0))
		human_folk.active_idea_id = String(human_data["folk"].get("active_idea_id", ""))
		human_folk.thoughts_invested = human_data["folk"].get("thoughts_invested", {})
		var completed_ideas: Array = human_data["folk"].get("completed_ideas", [])
		human_folk.completed_ideas.assign(completed_ideas)
		# Default {} per i salvataggi precedenti al decadimento dei pensieri (IdeaDecayService inizializza
		# da sé le scadenze mancanti). JSON legge i numeri come float: convertiti a int per-valore.
		var decay_due_day: Dictionary = human_data["folk"].get("idea_decay_due_day", {})
		for decay_idea_id in decay_due_day:
			human_folk.idea_decay_due_day[String(decay_idea_id)] = int(decay_due_day[decay_idea_id])

		human_population_group = HumanPopulationGroup.new()
		human_population_group.id = int(human_data["group"]["id"])
		human_population_group.folk_ref = human_folk
		human_population_group.home_macro_coords = Vector2i(
			int(human_data["group"]["home_macro_x"]), int(human_data["group"]["home_macro_y"])
		)
		human_population_group.total_count = int(human_data["group"]["total_count"])

		for individual_data in human_data["individuals"]:
			var individual := HumanIndividual.new()
			individual.id = int(individual_data["id"])
			individual.sex = int(individual_data["sex"])
			individual.birth_year_virtual = int(individual_data["birth_year_virtual"])
			individual.mother_id = int(individual_data["mother_id"])
			individual.father_id = int(individual_data["father_id"])
			individual.partner_id = int(individual_data["partner_id"])
			# Campo base Rest Task esplicita (2026-09-12, richiesta utente) — .get() con default -1,
			# stesso trattamento di scheduled_death_day/is_pregnant sopra: compatibilità coi save
			# precedenti a questo campo.
			individual.house_id = int(individual_data.get("house_id", -1))
			individual.name = String(individual_data["name"])
			individual.position = Vector2(float(individual_data["position_x"]), float(individual_data["position_y"]))
			individual.home_macro_coords = Vector2i(
				int(individual_data["home_macro_x"]), int(individual_data["home_macro_y"])
			)
			individual.hair_color = int(individual_data["hair_color"])
			individual.clothing_color = int(individual_data["clothing_color"])
			# Carnagione (2026-09-06) — accesso diretto, stesso trattamento di hair_color/
			# clothing_color sopra, nessuna retrocompatibilità richiesta.
			individual.skin_color = int(individual_data["skin_color"])
			individual.facing_direction = Vector2(
				float(individual_data["facing_direction_x"]), float(individual_data["facing_direction_y"])
			)
			# Step 4 piano mortalità (2026-09-05) — .get() con default -1 (a differenza dei campi
			# sopra, qui serve compatibilità coi save precedenti a questo campo, mai confermata
			# come non necessaria).
			individual.scheduled_death_day = int(individual_data.get("scheduled_death_day", -1))
			# Step 9 piano mortalità (2026-09-05) — accesso diretto, non .get(): nessuna
			# retrocompatibilità richiesta (confermato con l'utente), stesso trattamento di
			# hair_color/clothing_color/facing_direction sopra.
			individual.scheduled_death_cause = int(individual_data["scheduled_death_cause"])
			# Step 3 piano riproduzione (2026-09-06) — .get() con default false, stesso trattamento
			# di scheduled_death_day sopra: compatibilità coi save precedenti a questo campo.
			individual.is_pregnant = bool(individual_data.get("is_pregnant", false))
			# Step 2 piano riproduzione (2026-09-06) — accesso diretto, stesso trattamento di
			# scheduled_death_cause sopra: nessuna retrocompatibilità richiesta.
			individual.pending_child_hair_color = int(individual_data["pending_child_hair_color"])
			individual.pending_child_skin_color = int(individual_data["pending_child_skin_color"])
			individual.pending_child_father_id = int(individual_data["pending_child_father_id"])
			# Piano "trasporto neonati" (2026-09-06) — accesso diretto, nessuna retrocompatibilità
			# richiesta, stesso trattamento dei campi pending_child_* sopra.
			individual.dependent_child_id = int(individual_data["dependent_child_id"])
			individual.source_group_ref = human_population_group
			# Stamina (2026-09-08, richiesta utente) — .get() con i vecchi fallback di classe come
			# default (FALLBACK_MAX_STAMINA per entrambi, stesso valore usato da _init/
			# HumanStaminaIndividualService quando la catena Rules non è risolvibile): un save
			# precedente a questo campo non aveva alcuno stato reale da perdere (nessun consumo
			# esisteva ancora), quindi il fallback resta un valore onesto anche qui.
			individual.current_stamina = float(individual_data.get("current_stamina", HumanIndividual.FALLBACK_MAX_STAMINA))
			individual.max_stamina = float(individual_data.get("max_stamina", HumanIndividual.FALLBACK_MAX_STAMINA))
			# 5 nuovi parametri vitali (2026-09-13, richiesta utente) — .get() con FALLBACK_MAX_VITAL
			# come default (stesso valore usato da _init/HumanVitalsIndividualService quando la
			# catena Rules non è risolvibile), stesso trattamento di current_stamina/max_stamina
			# sopra: un save precedente a questi campi non aveva alcuno stato reale da perdere
			# (nessun consumo esisteva ancora), quindi il fallback resta un valore onesto anche qui.
			# Saccoccia del cibo (2026-09-19): se ENTRAMBE le chiavi del contenuto ci sono le si usa
			# cosi' come sono; se ne manca una (salvataggi precedenti) l'individuo mantiene il riempimento
			# di frutta dell'_init e food_pouch_resolved resta false: HumanCarryCapacityIndividualService lo
			# rifa' con la capacita' vera all'ingresso in scena (la capacita' non e' persistita e qui non e'
			# ancora nota). Le vecchie chiavi hunger sono ignorate.
			if individual_data.has("food_space_used") and individual_data.has("food_calories_held"):
				individual.food_space_used = float(individual_data["food_space_used"])
				individual.food_calories_held = float(individual_data["food_calories_held"])
				individual.food_pouch_resolved = true
			# Riserva corporea (2026-09-19): se la chiave manca (salvataggi precedenti) l'individuo resta al
			# pieno dell'_init e body_calories_resolved a false: HumanCarryCapacityIndividualService lo riporta
			# al pieno vero all'ingresso in scena.
			if individual_data.has("body_calories"):
				individual.body_calories = float(individual_data["body_calories"])
				individual.body_calories_resolved = true
			individual.body_reserve_in_use = bool(individual_data.get("body_reserve_in_use", false))
			individual.starvation_days = int(individual_data.get("starvation_days", 0))
			individual.current_thirst = float(individual_data.get("current_thirst", HumanIndividual.FALLBACK_MAX_VITAL))
			individual.max_thirst = float(individual_data.get("max_thirst", HumanIndividual.FALLBACK_MAX_VITAL))
			individual.current_health = float(individual_data.get("current_health", HumanIndividual.FALLBACK_MAX_VITAL))
			individual.max_health = float(individual_data.get("max_health", HumanIndividual.FALLBACK_MAX_VITAL))
			individual.current_happiness = float(individual_data.get("current_happiness", HumanIndividual.FALLBACK_MAX_VITAL))
			individual.max_happiness = float(individual_data.get("max_happiness", HumanIndividual.FALLBACK_MAX_VITAL))
			individual.current_loyalty = float(individual_data.get("current_loyalty", HumanIndividual.FALLBACK_MAX_VITAL))
			individual.max_loyalty = float(individual_data.get("max_loyalty", HumanIndividual.FALLBACK_MAX_VITAL))
			# 6 nuove skill (2026-09-13, richiesta utente) — .get() con default 0.0: un save precedente
			# a questi campi non può avere mai avuto una skill diversa da 0.0 (nessuna crescita esiste
			# ancora), quindi il default è sempre corretto, non solo un ripiego onesto (stesso
			# trattamento di carried_resources sotto).
			individual.skill_leadership = float(individual_data.get("skill_leadership", 0.0))
			individual.skill_builder = float(individual_data.get("skill_builder", 0.0))
			individual.skill_management = float(individual_data.get("skill_management", 0.0))
			individual.skill_transporter = float(individual_data.get("skill_transporter", 0.0))
			individual.skill_gathering = float(individual_data.get("skill_gathering", 0.0))
			individual.skill_cognition = float(individual_data.get("skill_cognition", 0.0))
			individual.skill_hunting = float(individual_data.get("skill_hunting", 0.0))
			# Capacità di trasporto (2026-09-08, richiesta utente) — .get() con default "non sta
			# trasportando nulla": un save precedente a questo campo non può avere mai avuto un
			# individuo in trasporto (nessun PickUp esiste ancora), quindi il default è sempre
			# corretto, non solo un ripiego.
			# Zaino multi-risorsa (2026-09-20, richiesta utente): "carried_resources" = nome ->
			# {"quantity", "decay_fraction"}. Un salvataggio precedente porta invece i tre vecchi campi
			# carried_resource_name/carried_quantity/carried_decay_fraction (decay 2026-09-09, .get() con
			# default 0.0): se "carried_resources" manca e il vecchio nome non è vuoto con quantità > 0, si
			# converte in UNA voce del dizionario. Le entry con quantity <= 0 vengono scartate (invariante
			# del modello: mai una entry vuota).
			individual.carried_resources = {}
			if individual_data.has("carried_resources"):
				var saved_carried: Dictionary = individual_data["carried_resources"]
				for saved_resource_name in saved_carried.keys():
					var saved_entry: Dictionary = saved_carried[saved_resource_name]
					var saved_quantity: int = int(saved_entry.get("quantity", 0))
					if saved_quantity <= 0:
						continue
					individual.carried_resources[String(saved_resource_name)] = {
						"quantity": saved_quantity,
						"decay_fraction": float(saved_entry.get("decay_fraction", 0.0)),
					}
			else:
				var legacy_resource_name := String(individual_data.get("carried_resource_name", ""))
				var legacy_quantity := int(individual_data.get("carried_quantity", 0))
				if legacy_resource_name != "" and legacy_quantity > 0:
					individual.carried_resources[legacy_resource_name] = {
						"quantity": legacy_quantity,
						"decay_fraction": float(individual_data.get("carried_decay_fraction", 0.0)),
					}
			# Task/Action in corso (2026-09-08, richiesta utente) — "current_task" assente (save
			# precedente a questo campo) o esplicitamente null (individuo a Rest implicito al
			# momento del salvataggio) lasciano individual.current_task al default null, nessuna
			# Task ricostruita. Quando presente, TaskPersistenceService.deserialize_task ricostruisce
			# l'intera sequenza di step; activate() sullo step corrente RIPRISTINA gli effetti
			# collaterali che un Task vivo avrebbe già applicato (es. WalkAction.activate scrive
			# individual.target_position/is_moving, MAI persistiti a parte — si ricavano SOLO da
			# qui) — senza, un individuo a metà camminata ricomparirebbe fermo, con una Task "Walk"
			# assegnata ma nessun movimento visibile finché non arriva un nuovo comando.
			# macro_state della cella HOME dell'individuo (2026-09-09, richiesta utente, persistenza
			# PickUpAction) — risolto QUI, incondizionatamente (spostato fuori dal ramo current_task
			# 2026-09-13: serve anche alla deserializzazione di task_queue sotto, stesso identico
			# bisogno) perché deserialize_task non può raggiungere World da sé (JSON non trasporta
			# riferimenti a oggetti vivi, vedi TaskPersistenceService per il perché). null se
			# home_macro_coords non è (ancora) valido — get_cell_state_at valida le coordinate da sé,
			# PickUpAction tratta un macro_state null in modo difensivo. `world` passato anche per
			# intero (2026-09-09, persistenza UnloadAction ramo fisico) — world.buildings è già
			# popolato a questo punto (caricato prima degli individui, vedi sopra), TaskPersistenceService.
			# _find_building_by_id lo scansiona per risolvere target_building_id.
			var task_macro_state: MacroCellState = world.get_cell_state_at(
				individual.home_macro_coords.x, individual.home_macro_coords.y
			)
			var current_task_data: Variant = individual_data.get("current_task")
			if current_task_data is Dictionary:
				# null (2026-09-21): task scartata perché il suo edificio target non esiste più — nessuna
				# current_task, l'individuo verrà trattato come libero da GameScene._ready.
				individual.current_task = TaskPersistenceService.deserialize_task(current_task_data, task_macro_state, world)
				# TaskDebugRegistry (2026-09-12, richiesta utente — tab di debug 🐞) — questo percorso
				# scrive current_task DIRETTAMENTE (non passa da HumanIndividual.assign_task, l'unico
				# altro punto che registra — vedi TaskDebugRegistry.gd), quindi va registrato qui a
				# parte perché una Task in corso al momento del salvataggio compaia comunque nella tab
				# dopo un reload, invece di restare invisibile finché non viene chiusa.
				if individual.current_task != null:
					TaskDebugRegistry.on_task_assigned(individual, individual.current_task)
					if not individual.current_task.is_finished():
						individual.current_task.get_current_action().activate(individual, individual.current_task.context)
			# Coda personale di Task sospese (2026-09-13, richiesta utente) — "task_queue" assente
			# (save precedente a questo campo) o vuoto lasciano individual.task_queue al default []
			# (.get() con default [], stesso principio di ogni campo opzionale in questo file).
			# STESSO meccanismo di current_task sopra (TaskPersistenceService.deserialize_task,
			# stesso macro_state/world), ma NESSUN activate()/TaskDebugRegistry qui: queste Task
			# sono SOSPESE, non in esecuzione — activate() riapplicherebbe erroneamente gli effetti
			# collaterali (es. WalkAction.activate scrive is_moving/target_position) di uno step che
			# non deve muovere l'individuo finché non viene ripresa da TaskQueueService.
			# pop_suspended_task (logica di ripresa non ancora scritta, arriverà insieme al vero
			# trigger di interrupt).
			var raw_task_queue: Array = individual_data.get("task_queue", [])
			for queued_task_data in raw_task_queue:
				if queued_task_data is Dictionary:
					var queued_task := TaskPersistenceService.deserialize_task(queued_task_data, task_macro_state, world)
					# null = task scartata (edificio target inesistente), non messa in coda.
					if queued_task != null:
						individual.task_queue.append(queued_task)
			human_individuals.append(individual)

	var loaded_game := LoadedGame.new()
	loaded_game.world = world
	loaded_game.game_data = game_data
	loaded_game.fog_of_war_memories = fog_of_war_memories
	loaded_game.human_folk = human_folk
	loaded_game.human_population_group = human_population_group
	loaded_game.human_individuals = human_individuals
	print("Game loaded from JSON: ", file_path)
	return loaded_game


# JSON.parse_string ritorna un Array untyped (Variant per elemento) — serve una conversione
# esplicita elemento per elemento verso Array[float], nessun costruttore diretto usato altrove nel
# progetto per farlo da un save JSON (vedi GameData.era_effective_age_band_durations_male/female,
# unico consumatore oggi).
func _float_array_from_json(raw: Array) -> Array[float]:
	var result: Array[float] = []
	for value in raw:
		result.append(float(value))
	return result


func _dictionary_array_from_json(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in raw:
		result.append(value as Dictionary)
	return result


# Controparte di GameSaveService (population_snapshots) — JSON.parse_string ritorna SEMPRE
# Dictionary con chiavi String (JSON non supporta chiavi non-stringa, vedi GameData.
# population_snapshots per il perché va riconvertito esplicitamente), qui riportate a int così
# come sono scritte a runtime (GameTimeService._on_year_rolled_over le usa come year: int).
func _population_snapshots_from_json(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for year_key in raw.keys():
		result[int(year_key)] = int(raw[year_key])
	return result


# Controparte di GameSaveService._expired_objects_to_json — ricostruisce position come Vector2
# vero (era appiattito in position_x/position_y solo per il salvataggio, vedi GameData.
# expired_objects per il perché).
func _expired_objects_from_json(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in raw:
		var entry: Dictionary = value as Dictionary
		result.append({
			"object_type": int(entry["object_type"]),
			"individual_id": int(entry["individual_id"]),
			"position": Vector2(float(entry["position_x"]), float(entry["position_y"])),
			# Step 6 (2026-09-05) — necessario per il hit-test di selezione, stessa convenzione di
			# HumanIndividual.home_macro_coords poco sotto.
			"home_macro_coords": Vector2i(int(entry["home_macro_x"]), int(entry["home_macro_y"])),
			"appeared_at_year": int(entry["appeared_at_year"]),
			"appeared_at_day": int(entry["appeared_at_day"]),
			# Step 5 (2026-09-05) — Dictionary annidato passato COSÌ COM'È (vedi
			# GameSaveService._expired_objects_to_json): il contenuto è specifico del object_type,
			# questo livello generico non lo interpreta mai. .get(key, {}) perché è dato
			# type-specific/opzionale per costruzione (non tutti gli ExpiredObjectType futuri
			# potrebbero averne bisogno), oltre a coprire i save precedenti a questo campo.
			"type_specific_data": entry.get("type_specific_data", {}) as Dictionary,
		})
	return result


# Controparte di Building.stored_resources (2026-09-09, richiesta utente, Step 3 decadimento) —
# RETROCOMPATIBILITÀ ESPLICITA col formato precedente (resource_name -> int diretto, PRIMA che
# esistesse decay_fraction): ogni voce viene ispezionata singolarmente, non un unico controllo sul
# Dictionary intero, perché in teoria un save potrebbe (non nella pratica attuale, dove stored_
# resources è comunque sempre vuoto, ma la funzione resta corretta a prescindere) mescolare voci
# vecchie e nuove se modificato a mano. Un valore che risponde a `is Dictionary` è già nel formato
# nuovo (letto con .get() per i due campi, comunque difensivo); qualunque altro tipo (il vecchio
# int, o un float — JSON non distingue i due) viene reinterpretato come "vecchio formato":
# {"quantity": quel numero, "decay_fraction": 0.0} — mai un breaking change per un save preesistente.
func _parse_stored_resources(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for resource_name in raw.keys():
		var value = raw[resource_name]
		if value is Dictionary:
			result[resource_name] = {
				"quantity": int(value.get("quantity", 0)),
				"decay_fraction": float(value.get("decay_fraction", 0.0)),
			}
		else:
			result[resource_name] = {"quantity": int(value), "decay_fraction": 0.0}
	return result
