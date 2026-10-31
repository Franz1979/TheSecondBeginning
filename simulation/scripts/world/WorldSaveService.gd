class_name WorldSaveService
extends RefCounted


func save_world_to_json(world: World, file_path: String) -> void:
	var data := {
	"file_type": "world_map",
	"width": World.WIDTH,
	"height": World.HEIGHT,
	"streams_generated": world.streams_generated,
	"cells": []
}

	for cell in world.cells:
		data["cells"].append({
			"x": cell.x,
			"y": cell.y,
			"terrain_base": cell.terrain_base,
			"water_type": cell.water_type,
			"river_shape":cell.river_shape,
			"stream_edges": cell.stream_edges,
			"stream_has_spring": cell.stream_has_spring,
			"coast_type": cell.coast_type,
			"biome": cell.biome
		})

	var json_text := JSON.stringify(data, "\t")

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()

	print("World saved to JSON: ", file_path)
