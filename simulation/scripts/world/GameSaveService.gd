class_name GameSaveService
extends RefCounted

func save_game_to_json(
	world: World,
	game_data: GameData,
	file_path: String,
	# Vector2i (coord macro) -> FogOfWarMemory — default {} per i due chiamanti (WorldScene/
	# MacroCellScene) che non tengono mai fog viva propria, solo la propagano se l'hanno ricevuta
	# da un caricamento precedente (vedi WorldScene.fog_of_war_memories). GameScene è l'unico
	# chiamante che ne ha sempre una reale da passare.
	fog_of_war_memories: Dictionary = {}
) -> void:
	var data := {
		"file_type": "game_save",
		"game": {
			"year": game_data.year,
			"current_day": game_data.current_day,
			# Statistica pura (vedi GameData) — mai riletti da nessuna logica di simulazione.
			"starting_world_age_mode": game_data.starting_world_age_mode,
			"starting_animal_density": game_data.starting_animal_density,
			"starting_population_size": game_data.starting_population_size,
			"starting_exclude_hostile_start": game_data.starting_exclude_hostile_start,
			"starting_exclude_predator_territories": game_data.starting_exclude_predator_territories,
			"starting_resource_richness_preference": game_data.starting_resource_richness_preference,
			"starting_group_size_preference": game_data.starting_group_size_preference,
			"starting_guarantee_animal_presence": game_data.starting_guarantee_animal_presence,
			"starting_difficulty_ratio": game_data.starting_difficulty_ratio,
			# Sede macrocella del player per la futura GameScene (vedi GameData) — deve
			# sopravvivere a save/load, a differenza dei campi analoghi di GameSettings.
			"player_macro_cell_x": game_data.player_macro_cell_x,
			"player_macro_cell_y": game_data.player_macro_cell_y,
			# Posizione dell'individuo controllabile dentro quella macrocella (vedi GameData) —
			# deve sopravvivere a save/load esattamente come la macrocella stessa.
			"player_micro_x": game_data.player_micro_x,
			"player_micro_y": game_data.player_micro_y,
			# Zoom camera GameScene (vedi GameData) — deve sopravvivere a save/load come la
			# posizione del player, ma è un solo float (zoom.x == zoom.y sempre).
			"camera_zoom": game_data.camera_zoom,
			# Ultimo giorno di pulizia periodica del fog of war (vedi GameData) — deve
			# sopravvivere a save/load per non sfasare la cadenza reale.
			"fog_of_war_last_prune_absolute_day": game_data.fog_of_war_last_prune_absolute_day
		},
		"world": {
			"width": World.WIDTH,
			"height": World.HEIGHT,
			"cells": [],
			"cell_states": [],
			"population_groups": []
		}
	}
	for cell in world.cells:
		data["world"]["cells"].append({
			"x": cell.x,
			"y": cell.y,
			"terrain_base": cell.terrain_base,
			"water_type": cell.water_type,
			"river_shape": cell.river_shape,
			"coast_type": cell.coast_type,
			"biome": cell.biome
		})
	for state in world.cell_states:
		var state_data := {
			"x": state.x,
			"y": state.y,
			"resource_quantity": state.resource_quantity,
			"dedicated_space": state.dedicated_space,
			"has_ever_grown": state.has_ever_grown,
			"subtype_composition": state.subtype_composition,
			"age_composition": state.age_composition,
			"river_space": state.river_space,
			"water_dedicated_space": state.water_dedicated_space,
			"terrestrial_dedicated_space": state.terrestrial_dedicated_space,
			"active_growth_bonuses": state.active_growth_bonuses,
			"pending_migration_surplus": state.pending_migration_surplus,
			"secondary_resource_stock": state.secondary_resource_stock,
			"pending_grass_space_debt": state.pending_grass_space_debt,
			"pending_fish_space_debt": state.pending_fish_space_debt,
			"pending_bird_space_debt": state.pending_bird_space_debt
		}
		# Solo le macrocelle già aperte in MacroCellScene hanno posizioni stone generate:
		# la chiave resta assente per tutte le altre, per non appesantire il salvataggio.
		if state.stone_positions_generated:
			var stone_positions_data: Array = []
			for pos in state.stone_positions:
				stone_positions_data.append({"x": pos.x, "y": pos.y})
			state_data["stone_positions"] = stone_positions_data
		# Assente se vuoto (nessun meccanismo di taglio esiste ancora, sempre il caso oggi), stesso
		# principio di stone_positions sopra — non appesantire il salvataggio per un campo mai
		# popolato. Chiave Vector3i (x, y lotto + "i" indice individuo): "i" va salvato insieme a
		# x/y, altrimenti due individui nello stesso lotto collasserebbero sulla stessa entry.
		# origin_type/cut_year sono i due campi del valore (vedi MacroCellState.
		# vegetation_cut_exceptions) — origin_type serve solo a scegliere la finestra di rientro
		# al caricamento, il blocco resta comunque unificato per qualunque tipo.
		if not state.vegetation_cut_exceptions.is_empty():
			var cut_exceptions_data: Array = []
			for key in state.vegetation_cut_exceptions.keys():
				var entry: Dictionary = state.vegetation_cut_exceptions[key]
				cut_exceptions_data.append({
					"x": key.x, "y": key.y, "i": key.z,
					"origin_type": int(entry["origin_type"]), "cut_year": int(entry["cut_year"]),
					"size_multiplier": float(entry.get("size_multiplier", 1.0))
				})
			state_data["vegetation_cut_exceptions"] = cut_exceptions_data
		# Stesso principio sopra: assenti se vuote. Popolate solo dopo che MicroCellRenderer ha
		# disegnato la cella almeno una volta (vedi MacroCellState.tree_virtual_birth_year). Chiave
		# Vector3i (x, y lotto + "i" indice individuo locale): "i" va salvato insieme a x/y,
		# altrimenti due individui nello stesso lotto collasserebbero sulla stessa entry salvata e
		# il caricamento ricostruirebbe una chiave Vector2i che non corrisponderebbe mai a nessuna
		# Vector3i cercata a runtime — l'età tornerebbe sempre "non ancora vista" ad ogni reload
		# invece di restare fissa.
		if not state.tree_virtual_birth_year.is_empty():
			var tree_birth_year_data: Array = []
			for key in state.tree_virtual_birth_year.keys():
				tree_birth_year_data.append({"x": key.x, "y": key.y, "i": key.z, "year": state.tree_virtual_birth_year[key]})
			state_data["tree_virtual_birth_year"] = tree_birth_year_data
		if not state.shrub_virtual_birth_year.is_empty():
			var shrub_birth_year_data: Array = []
			for key in state.shrub_virtual_birth_year.keys():
				shrub_birth_year_data.append({"x": key.x, "y": key.y, "i": key.z, "year": state.shrub_virtual_birth_year[key]})
			state_data["shrub_virtual_birth_year"] = shrub_birth_year_data
		# Sottotipo congelato per individuo (vedi MacroCellState.tree_individual_subtype/
		# shrub_individual_subtype) — stessa chiave Vector3i/stesso principio "assente se vuoto" di
		# tree_virtual_birth_year sopra, un campo String in più oltre a "year".
		if not state.tree_individual_subtype.is_empty():
			var tree_subtype_data: Array = []
			for key in state.tree_individual_subtype.keys():
				tree_subtype_data.append({"x": key.x, "y": key.y, "i": key.z, "subtype": state.tree_individual_subtype[key]})
			state_data["tree_individual_subtype"] = tree_subtype_data
		if not state.shrub_individual_subtype.is_empty():
			var shrub_subtype_data: Array = []
			for key in state.shrub_individual_subtype.keys():
				shrub_subtype_data.append({"x": key.x, "y": key.y, "i": key.z, "subtype": state.shrub_individual_subtype[key]})
			state_data["shrub_individual_subtype"] = shrub_subtype_data
		# Lotti rivendicati per sempre da ciascun tipo (vedi MacroCellState.tree_claimed_lots/
		# shrub_claimed_lots) — Vector2i, stesso stile {x,y} già in uso per stone_positions.
		if not state.tree_claimed_lots.is_empty():
			var tree_claimed_lots_data: Array = []
			for pos in state.tree_claimed_lots.keys():
				tree_claimed_lots_data.append({"x": pos.x, "y": pos.y})
			state_data["tree_claimed_lots"] = tree_claimed_lots_data
		if not state.shrub_claimed_lots.is_empty():
			var shrub_claimed_lots_data: Array = []
			for pos in state.shrub_claimed_lots.keys():
				shrub_claimed_lots_data.append({"x": pos.x, "y": pos.y})
			state_data["shrub_claimed_lots"] = shrub_claimed_lots_data
		# Stesso formato/principio di vegetation_cut_exceptions sopra, ma per la mortalità naturale
		# (vedi MacroCellState.vegetation_death_exceptions) — campo "death_year" invece di "cut_year".
		if not state.vegetation_death_exceptions.is_empty():
			var death_exceptions_data: Array = []
			for key in state.vegetation_death_exceptions.keys():
				var entry: Dictionary = state.vegetation_death_exceptions[key]
				death_exceptions_data.append({
					"x": key.x, "y": key.y, "i": key.z,
					"origin_type": int(entry["origin_type"]), "death_year": int(entry["death_year"]),
					"size_multiplier": float(entry.get("size_multiplier", 1.0))
				})
			state_data["vegetation_death_exceptions"] = death_exceptions_data
		data["world"]["cell_states"].append(state_data)
	# Popolazioni animali "vere" (rabbit/deer) — world-level, non più annidate dentro
	# cell_states (vedi PopulationGroup/World.population_groups). occupied_macrocells è un array
	# (1+ elementi da Step 5, vedi Territory) invece di una singola coppia x/y.
	for group in world.population_groups:
		# Garanzia esplicita AL CONFINE del salvataggio (non solo conseguenza indiretta di
		# World.remove_extinct_population_groups, che gira a fine di ogni giorno simulato): un
		# gruppo estinto (population <= 0) non finisce mai nel save, né lui né il suo territorio —
		# quest'ultimo è scritto solo dentro il record del gruppo (occupied_cells_data sotto), mai
		# come lista indipendente, quindi saltare il gruppo esclude automaticamente anche le sue
		# celle occupate.
		if group.population <= 0:
			continue
		var occupied_cells_data: Array = []
		for coords in group.territory.occupied_macrocells:
			occupied_cells_data.append({"x": coords.x, "y": coords.y})
		# hunger_buckets (giorni consecutivi di digiuno -> individui, vedi
		# AnimalHungerService/PopulationGroup): a differenza di territory_distribution_weights è
		# storia accumulata reale e va salvata — perderla al caricamento azzererebbe una crisi di
		# fame già vicina alla soglia di morte. birth_mitigation_multiplier va salvato per lo
		# stesso motivo di fondo (bug corretto: viene calcolato a inizio birth_season ma consumato
		# solo a fine — un salvataggio/caricamento nel mezzo lo perdeva, tornando al default 1.0 e
		# applicando nascite senza alcuna mitigazione). years_since_last_split (Step 10) è storia
		# reale allo stesso modo — non ricalcolabile da un checkpoint, perderla al caricamento
		# resetterebbe silenziosamente la recovery post-scissione in corso a "mai scisso".
		# hunger_split_cooldown_days (Step 11) idem: un countdown a metà perso al caricamento
		# riaprirebbe silenziosamente la porta a un nuovo split da fame prima del previsto.
		# patrol_index/patrol_direction (branchi predatori, PredatorPatrolService) sono storia
		# reale allo stesso modo di hunger_buckets — quanti giorni di percorso il branco ha già
		# camminato e in che verso, non ricostruibile dalla sola forma del territorio: perderli al
		# caricamento farebbe silenziosamente ripartire il pattugliamento da zero (vedi TODO ormai
		# risolto in PopulationGroup.gd). predation_calorie_debt/predation_surplus_carryover
		# (PredationService) sono il bookkeeping calorico del branco, stesso principio — un
		# caricamento a metà debito/surplus non deve azzerarlo silenziosamente. patrol_route NON è
		# salvato (dato derivato da territory + hunting_window_size, sempre ricalcolabile — vedi
		# GameLoadService/PredatorPatrolService.recompute_route). recent_hunt_log/
		# yearly_prey_totals (tab Fauna 3, UI — vedi PopulationGroup) sono contenuto informativo
		# reale mostrato al giocatore, non una cache di ottimizzazione: perderli al caricamento
		# sarebbe una regressione visibile (lista "ultimi 5 giorni" vuota anche dopo anni di
		# caccia), quindi salvati per intero come gli altri campi storici sopra. hunger_debt_days
		# (AnimalHungerMortalityAggregateService) è l'equivalente Livello 1 di hunger_buckets,
		# stesso principio.
		data["world"]["population_groups"].append({
			"id": group.id,
			"species_name": group.species_name,
			"population": group.population,
			"age_composition": group.age_composition,
			"occupied_macrocells": occupied_cells_data,
			"hunger_buckets": group.hunger_buckets,
			"birth_mitigation_multiplier": group.birth_mitigation_multiplier,
			"birth_mitigation_caloric_ratio": group.birth_mitigation_caloric_ratio,
			"years_since_last_split": group.years_since_last_split,
			"hunger_split_cooldown_days": group.hunger_split_cooldown_days,
			"patrol_index": group.patrol_index,
			"patrol_direction": group.patrol_direction,
			"predation_calorie_debt": group.predation_calorie_debt,
			"predation_surplus_carryover": group.predation_surplus_carryover,
			"predation_season_calories_obtained": group.predation_season_calories_obtained,
			"predation_season_calories_required": group.predation_season_calories_required,
			"hunger_debt_days": group.hunger_debt_days,
			"recent_hunt_log": group.recent_hunt_log,
			"yearly_prey_totals": group.yearly_prey_totals,
			"yearly_prey_totals_year": group.yearly_prey_totals_year
		})

	# Fog of war (vedi FogOfWarMemory.gd/GameScene.fog_of_war_memories) — una entry per macrocella
	# con ALMENO una posizione vista (una macrocella entrata nel set vivo come vicino ma mai
	# davvero osservata dal player, es. avvicinamento poi allontanamento senza attraversare, ha
	# last_seen_by_position vuoto: saltata per non appesantire il salvataggio con entry inutili,
	# stesso principio già usato sopra per stone_positions). Vector2i non è mai una chiave JSON
	# diretta (JSON vuole chiavi stringa): sia le coordinate macro sia quelle micro sono array di
	# oggetti {x,y,...}, stesso stile già in uso per stone_positions/occupied_macrocells sopra,
	# mai un Dictionary con chiave Vector2i serializzato direttamente.
	data["fog_of_war"] = []
	for coords in fog_of_war_memories:
		var memory: FogOfWarMemory = fog_of_war_memories[coords]
		if memory.last_seen_by_position.is_empty():
			continue
		var last_seen_data: Array = []
		for pos in memory.last_seen_by_position:
			last_seen_data.append({
				"x": pos.x,
				"y": pos.y,
				"day": memory.last_seen_by_position[pos]
			})
		data["fog_of_war"].append({
			"macro_x": coords.x,
			"macro_y": coords.y,
			"last_seen": last_seen_data
		})

	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()
	print("Game saved to JSON: ", file_path)
