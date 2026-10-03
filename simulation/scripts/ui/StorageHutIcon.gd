class_name StorageHutIcon
extends Control

# Icona della capanna di stoccaggio nella barra di costruzione (2026-10-03, richiesta utente): lo stesso disegno della
# mappa (StorageHutShape), porta verso il basso, scalato al rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.

# Lato del disegno in unità della mappa (pianta più la porta che sporge, con un po' di margine).
const DRAWING_SPAN: float = 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var drawing_scale: float = minf(size.x, size.y) / DRAWING_SPAN
	StorageHutShape.draw(self, size * 0.5 - Vector2(0.0, 0.2 * drawing_scale), GameTypes.Direction.SOUTH, false, 1.0, drawing_scale)
