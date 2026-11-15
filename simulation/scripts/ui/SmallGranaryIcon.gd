extends Control

# Icona dell'edificio "small_granary" (Casa delle granaglie, 2026-11-15): lo stesso disegno della mappa (PlaceholderBuildingShapes),
# scalato al proprio rettangolo; il disegno è largo due microcelle (20 unità), alto una.
# Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	PlaceholderBuildingShapes.draw(self, "small_granary", size * 0.5, false, minf(size.x / 20.0, size.y / 10.0))
