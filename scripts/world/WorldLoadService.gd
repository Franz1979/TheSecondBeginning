class_name WorldLoadService
extends RefCounted


func load_world_from_json(file_path: String) -> World:
	if not FileAccess.file_exists(file_path):
		print("File JSON non trovato: ", file_path)
		return null

	var file := FileAccess.open(file_path, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_text)

	if data == null:
		print("Errore nella lettura del JSON: ", file_path)
		return null

	var world := World.new()
	world.cells.clear()

	for cell_data in data["cells"]:
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

	print("World loaded from JSON: ", file_path)
	return world
