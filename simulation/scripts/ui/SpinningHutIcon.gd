extends Control

# Icona dell'edificio "spinning_hut" (Filatoio, 2026-11-15, segnaposto): lo stesso disegno della mappa
# (PlaceholderBuildingShapes), scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	PlaceholderBuildingShapes.draw(self, "spinning_hut", size * 0.5, false, minf(size.x, size.y) / 10.0)
