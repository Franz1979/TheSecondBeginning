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

func get_cell_at(x: int, y: int) -> MacroCellData:
	for cell in cells:
		if cell.x == x and cell.y == y:
			return cell
	return null
	
func get_cell_state_at(x: int, y: int) -> MacroCellState:
	for state in cell_states:
		if state.x == x and state.y == y:
			return state
	return null

func ensure_cell_states() -> void:
	if cell_states.size() == cells.size():
		return
	cell_states.clear()
	for cell in cells:
		cell_states.append(MacroCellState.new(cell.x, cell.y))
	print("cell_states dopo il fix: ", cell_states.size())
