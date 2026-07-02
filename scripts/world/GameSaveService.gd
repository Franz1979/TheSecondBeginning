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
		"cells": []
	}
}

	for cell in world.cells:
		data["world"]["cells"].append({
			"x": cell.x,
			"y": cell.y,
			"terrain_base": cell.terrain_base,
			"water_type": cell.water_type,
			"river_shape":cell.river_shape,
			"coast_type": cell.coast_type,
			"biome": cell.biome
		})

	var json_text := JSON.stringify(data, "\t")

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()

	print("Game saved to JSON: ", file_path)
