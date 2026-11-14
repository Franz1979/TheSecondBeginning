extends Control

# Icona dell'edificio "field" (Campo con capanno, 2026-11-15): lo stesso disegno della mappa (FieldShape), scalato al
# proprio rettangolo (3 microcelle per lato). Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	FieldShape.draw(self, size * 0.5, GameTypes.Direction.SOUTH, false, minf(size.x, size.y) / (FieldShape.CELL * 3.0))
