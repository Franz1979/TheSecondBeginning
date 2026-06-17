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

	var generator := MapGenerator.new()
	generator.generate(self)

	print("World generated. Cells: ", cells.size())
