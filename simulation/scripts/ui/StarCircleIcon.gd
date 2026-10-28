class_name StarCircleIcon
extends Control

# Icona del Cerchio delle stelle "star_circle" (2026-10-27): il disegno del Cerchio sacro (CouncilCircleShape) senza le
# sedute, scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	CouncilCircleShape.draw(self, size * 0.5, Vector2(side, side), false, 1.0, true, false)
