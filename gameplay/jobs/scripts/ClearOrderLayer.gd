class_name ClearOrderLayer
extends Node2D

# Segno delle microcelle da sgomberare di una macrocella (2026-11-15, ClearOrderService): un riquadro tratteggiato color
# ambra attorno alla microcella, finché l'ordine resta. Figlio del container della cella, sopra gli oggetti del renderer e
# sotto la nebbia. Si ridisegna quando cambia l'elenco (GameData.clear_orders_revision).

const CELL_SIZE: float = MicroCellRenderer.CELL_SIZE
const MARK_COLOR := Color(1.0, 0.72, 0.18, 0.95)
const MARK_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const LINE_WIDTH: float = 1.2
const DASH: float = 2.0
const INSET: float = 0.8

var _macro_coords: Vector2i = Vector2i.ZERO
var _drawn_revision: int = -1


func setup(macro_coords: Vector2i) -> void:
	_macro_coords = macro_coords
	_drawn_revision = -1
	queue_redraw()


func _process(_delta: float) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null and game_data.clear_orders_revision != _drawn_revision:
		queue_redraw()


func _draw() -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	_drawn_revision = game_data.clear_orders_revision
	for lot in ClearOrderService.lots_in_cell(game_data, _macro_coords):
		var rect := Rect2(Vector2(lot) * CELL_SIZE + Vector2(INSET, INSET), Vector2(CELL_SIZE, CELL_SIZE) - Vector2(INSET, INSET) * 2.0)
		_draw_dashed_rect(rect.position + Vector2(0.5, 0.5), rect.size, MARK_SHADOW_COLOR)
		_draw_dashed_rect(rect.position, rect.size, MARK_COLOR)


func _draw_dashed_rect(top_left: Vector2, size: Vector2, color: Color) -> void:
	var corners := [top_left, top_left + Vector2(size.x, 0.0), top_left + size, top_left + Vector2(0.0, size.y)]
	for i in range(4):
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, LINE_WIDTH, DASH)
