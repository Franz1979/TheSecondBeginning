class_name WoodshedIcon
extends Control

# Icona della Legnaia "woodshed" (2026-10-18, 2x1): lo stesso disegno della mappa (WoodshedShape), con la porta in basso,
# scalato perché il rettangolo 2x1 (20 × 10 unità) stia nel proprio. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var fit: float = minf(size.x / (WoodshedShape.HALF_WIDTH * 2.0), size.y / (WoodshedShape.HALF_DEPTH * 2.0))
	WoodshedShape.draw(self, size * 0.5, GameTypes.Direction.SOUTH, false, 1.0, fit * 0.95)
