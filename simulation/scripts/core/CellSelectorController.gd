class_name CellSelectorController
extends RefCounted

signal cell_selected(cell: MacroCellData, state: MacroCellState)

var world: World
var renderer: WorldRenderer


func setup(p_world: World, p_renderer: WorldRenderer) -> void:
	world = p_world
	renderer = p_renderer


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_cell_at_mouse_position()


func _get_cell_under_mouse() -> MacroCellData:
	var mouse_pos: Vector2 = renderer.get_local_mouse_position()
	var cell_x: int = int(mouse_pos.x / WorldRenderer.CELL_SIZE)
	var cell_y: int = int(mouse_pos.y / WorldRenderer.CELL_SIZE)
	return world.get_cell_at(cell_x, cell_y)


func _select_cell_at_mouse_position() -> void:
	var cell := _get_cell_under_mouse()
	if cell == null:
		return
	var state := world.get_cell_state_at(cell.x, cell.y)
	cell_selected.emit(cell, state)
