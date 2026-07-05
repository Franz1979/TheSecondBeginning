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
			var occupied = state_data.get("resource_quantity", {})
			for key in occupied.keys():
				state.resource_quantity[int(key)] = int(occupied[key])
			var dedicated = state_data.get("dedicated_space", {})
			for key in dedicated.keys():
				state.dedicated_space[int(key)] = int(dedicated[key])
			world.cell_states.append(state)

	var loaded_game := LoadedGame.new()
	loaded_game.world = world
	loaded_game.game_data = game_data
	print("Game loaded from JSON: ", file_path)
	return loaded_game
