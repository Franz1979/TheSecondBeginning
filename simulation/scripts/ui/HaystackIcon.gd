extends Control

# Icona del pagliaio (2026-11-15): lo stesso disegno della mappa (HaystackShape) con i quattro trespoli pieni, scalato al
# proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	HaystackShape.draw(self, size * 0.5, HaystackShape.RACK_COUNT, false, 1.0, minf(size.x, size.y) / 10.0)
