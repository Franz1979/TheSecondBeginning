class_name FeastGroundIcon
extends Control

# Icona dello Spiazzo delle feste "feast_ground" (2026-10-17): lo stesso disegno della mappa (FeastGroundShape), scalato al
# proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	FeastGroundShape.draw(self, size * 0.5, Vector2(side, side), false)
