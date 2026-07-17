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
			"year": game_data.year
		},
		"world": {
			"width": World.WIDTH,
			"height": World.HEIGHT,
			"cells": [],
			"cell_states": []
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
			"river_space": state.river_space,
			"active_growth_bonuses": state.active_growth_bonuses
		}
		# Solo le macrocelle già aperte in MacroCellScene hanno posizioni stone generate:
		# la chiave resta assente per tutte le altre, per non appesantire il salvataggio.
		if state.stone_positions_generated:
			var stone_positions_data: Array = []
			for pos in state.stone_positions:
				stone_positions_data.append({"x": pos.x, "y": pos.y})
			state_data["stone_positions"] = stone_positions_data
		data["world"]["cell_states"].append(state_data)
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()
	print("Game saved to JSON: ", file_path)
