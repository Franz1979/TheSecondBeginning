class_name StickTentIcon
extends Control

# Icona della tenda di rami nella barra di costruzione (2026-10-03, richiesta utente — prima l'emoji ⛺): lo stesso
# disegno della mappa (TentShapes.draw_stick_tent), porta verso il basso, scalato al rettangolo. Registrata in
# IconRegistry.BUILDING_ICON_NODES.

# Lato del disegno in unità della mappa (raggio con le punte dei rami + segno della porta, con un po' di margine).
const DRAWING_SPAN: float = 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var drawing_scale: float = minf(size.x, size.y) / DRAWING_SPAN
	TentShapes.draw_stick_tent(self, size * 0.5 - Vector2(0.0, 0.5 * drawing_scale), GameTypes.Direction.SOUTH, false, 1.0, drawing_scale)
