class_name World

const WIDTH: int = 100
const HEIGHT: int = 100

var cells: Array[MacroCellData] = []

func generate_empty_world() -> void:
	cells.clear()

	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := MacroCellData.new(x, y)
			cells.append(cell)

	print("Tipo mappa selezionato: ", GameSettings.selected_map_type)

	if GameSettings.selected_map_type == "random":
		var generator := MapGenerator.new()
		generator.generate(self)

	elif GameSettings.selected_map_type == "island":
		var generator := PresetMapGenerator.new()
		generator.generate_island(self)

	elif GameSettings.selected_map_type == "valley":
		print("Mappa valle non ancora disponibile")

	elif GameSettings.selected_map_type == "mountain":
		print("Mappa montagna non ancora disponibile")

	print("World generated. Cells: ", cells.size())
