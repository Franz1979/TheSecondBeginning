extends Control

# Icona dell'edificio "domestication_pen" (Recinto di addomesticazione, 2026-11-18, segnaposto): lo stesso disegno della
# mappa (PlaceholderBuildingShapes), scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# 3x2: il disegno è largo tre caselle e alto due.
	PlaceholderBuildingShapes.draw(self, "domestication_pen", size * 0.5, false, minf(size.x / 30.0, size.y / 20.0))
