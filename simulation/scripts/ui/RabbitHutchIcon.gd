extends Control

# Icona dell'edificio "rabbit_hutch" (Conigliera, 2026-11-13, segnaposto): lo stesso disegno della mappa (PlaceholderBuildingShapes),
# scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# 2x1 (2026-11-17): il disegno è largo due caselle, come il piccolo granaio.
	PlaceholderBuildingShapes.draw(self, "rabbit_hutch", size * 0.5, false, minf(size.x / 20.0, size.y / 10.0))
