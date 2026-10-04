class_name PathfindingDebugOverlay
extends Node2D

# Overlay di debug del pathfinding (2026-09-27, step 1; tasto N tolto il 2026-10-04 — oggi usato solo dal layer della mappa "Percorribilità"): microcelle bloccate della griglia
# (LiveMacroCell.path_grid) in rosso semitrasparente. Figlio del container della cella, coordinate locali. Si
# ridisegna da sé quando la griglia cambia (path_grid_version). Le microcelle bloccate consecutive di una riga
# diventano un solo rettangolo, così una macrocella d'acqua è 100 rettangoli invece di 10000.

const BLOCKED_COLOR := Color(1.0, 0.0, 0.0, 0.35)

var _cell: LiveMacroCell = null
var _drawn_version: int = -1


func show_cell(cell: LiveMacroCell) -> void:
	_cell = cell
	_drawn_version = -1
	queue_redraw()


func get_cell() -> LiveMacroCell:
	return _cell


func _process(_delta: float) -> void:
	if _cell != null and _cell.path_grid_version != _drawn_version:
		queue_redraw()


func _draw() -> void:
	if _cell == null or _cell.path_grid == null:
		return
	_drawn_version = _cell.path_grid_version
	var cell_size := float(MicroCellRenderer.CELL_SIZE)
	for y in range(World.HEIGHT):
		var run_start := -1
		for x in range(World.WIDTH + 1):
			var blocked := x < World.WIDTH and _cell.path_grid.is_point_solid(Vector2i(x, y))
			if blocked and run_start == -1:
				run_start = x
			elif not blocked and run_start != -1:
				draw_rect(Rect2(run_start * cell_size, y * cell_size, (x - run_start) * cell_size, cell_size), BLOCKED_COLOR)
				run_start = -1
