extends Control

# Icona dell'edificio "clay_oven" (Forno d'argilla, 2026-11-15): lo stesso disegno della mappa (PlaceholderBuildingShapes),
# scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	PlaceholderBuildingShapes.draw(self, "clay_oven", size * 0.5, false, minf(size.x, size.y) / 10.0)
