class_name HideTentIcon
extends Control

# Icona della tenda di pelli nella barra di costruzione (2026-10-03, richiesta utente — prima l'emoji ⛺, la stessa della
# tenda di rami): lo stesso disegno della mappa (TentShapes.draw_hide_tent), porta verso il basso, scalato al rettangolo.
# Registrata in IconRegistry.BUILDING_ICON_NODES.

# Lato del disegno in unità della mappa (raggio + segno della porta, con un po' di margine).
const DRAWING_SPAN: float = 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var drawing_scale: float = minf(size.x, size.y) / DRAWING_SPAN
	TentShapes.draw_hide_tent(self, size * 0.5 - Vector2(0.0, 0.5 * drawing_scale), GameTypes.Direction.SOUTH,
		TentShapes.HIDE_TENT_COLOR, TentShapes.HIDE_TENT_OUTLINE_COLOR, drawing_scale)
