class_name World

const WIDTH: int = 100
const HEIGHT: int = 100

var cells: Array[MacroCellData] = []
var cell_states: Array[MacroCellState] = []


func generate_empty_world() -> void:
	cells.clear()
	cell_states.clear()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := MacroCellData.new(x, y)
			cells.append(cell)
			cell_states.append(MacroCellState.new(x, y))

	print("Tipo mappa selezionato: ", GameSettings.selected_map_type)
	if GameSettings.selected_map_type == "random":
		var generator := RandomMapGenerator.new()
		generator.generate(self)
	elif GameSettings.selected_map_type == "island":
		var generator := PresetMapGenerator.new()
		generator.generate_island(self)
	elif GameSettings.selected_map_type == "valley":
		print("Mappa valle non ancora disponibile")
	elif GameSettings.selected_map_type == "mountain":
		print("Mappa montagna non ancora disponibile")
	elif GameSettings.selected_map_type == "empty":
		print("Mappa vuota creata")
	print("World generated. Cells: ", cells.size())

func generate_uniform_terrain(
	terrain_base: GameTypes.TerrainBase,
	water_type: GameTypes.WaterType,
	coast_type: GameTypes.CoastType = GameTypes.CoastType.NONE
) -> void:
	cells.clear()
	cell_states.clear()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := MacroCellData.new(x, y)
			cell.terrain_base = terrain_base
			cell.water_type = water_type
			cell.coast_type = coast_type
			cells.append(cell)
			cell_states.append(MacroCellState.new(x, y))

func get_cell_at(x: int, y: int) -> MacroCellData:
	var index := y * WIDTH + x
	if index < 0 or index >= cells.size():
		return null
	var cell := cells[index]
	if cell.x != x or cell.y != y:
		return null
	return cell


func get_cell_state_at(x: int, y: int) -> MacroCellState:
	var index := y * WIDTH + x
	if index < 0 or index >= cell_states.size():
		return null
	var state := cell_states[index]
	if state.x != x or state.y != y:
		return null
	return state

func ensure_cell_states() -> void:
	if cell_states.size() == cells.size():
		return
	cell_states.clear()
	for cell in cells:
		cell_states.append(MacroCellState.new(cell.x, cell.y))
	print("cell_states dopo il fix: ", cell_states.size())
