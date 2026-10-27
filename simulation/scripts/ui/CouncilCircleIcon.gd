class_name CouncilCircleIcon
extends Control

# Icona del Cerchio del consiglio "council_circle" (2026-10-26): lo stesso disegno della mappa (CouncilCircleShape),
# scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	CouncilCircleShape.draw(self, size * 0.5, Vector2(side, side), false)
