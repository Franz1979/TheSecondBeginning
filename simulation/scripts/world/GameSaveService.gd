class_name GameSaveService
extends RefCounted

func save_game_to_json(
	world: World,
	game_data: GameData,
	file_path: String
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
			"player_macro_cell_y": game_data.player_macro_cell_y
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
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()
	print("Game saved to JSON: ", file_path)
