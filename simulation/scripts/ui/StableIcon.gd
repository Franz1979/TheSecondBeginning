extends Control

# Icona dell'edificio "stable" (Stalla, 2026-11-19): lo stesso disegno della mappa (PlaceholderBuildingShapes), senza il
# segno della specie, scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# 4x3: il disegno è largo quattro caselle e alto tre.
	PlaceholderBuildingShapes.draw(self, "stable", size * 0.5, false, minf(size.x / 40.0, size.y / 30.0))
