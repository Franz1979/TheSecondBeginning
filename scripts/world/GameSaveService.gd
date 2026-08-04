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
			"current_day": game_data.current_day
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
			"active_growth_bonuses": state.active_growth_bonuses,
			"pending_migration_surplus": state.pending_migration_surplus,
			"secondary_resource_stock": state.secondary_resource_stock,
			"pending_grass_space_debt": state.pending_grass_space_debt
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
		var occupied_cells_data: Array = []
		for coords in group.territory.occupied_macrocells:
			occupied_cells_data.append({"x": coords.x, "y": coords.y})
		# hunger_buckets (giorni consecutivi di digiuno -> individui, vedi
		# AnimalHungerService/PopulationGroup): a differenza di territory_distribution_weights è
		# storia accumulata reale e va salvata — perderla al caricamento azzererebbe una crisi di
		# fame già vicina alla soglia di morte. birth_mitigation_multiplier va salvato per lo
		# stesso motivo di fondo (bug corretto: viene calcolato a inizio birth_season ma consumato
		# solo a fine — un salvataggio/caricamento nel mezzo lo perdeva, tornando al default 1.0 e
		# applicando nascite senza alcuna mitigazione).
		data["world"]["population_groups"].append({
			"id": group.id,
			"species_name": group.species_name,
			"population": group.population,
			"age_composition": group.age_composition,
			"occupied_macrocells": occupied_cells_data,
			"hunger_buckets": group.hunger_buckets,
			"birth_mitigation_multiplier": group.birth_mitigation_multiplier
		})
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()
	print("Game saved to JSON: ", file_path)
