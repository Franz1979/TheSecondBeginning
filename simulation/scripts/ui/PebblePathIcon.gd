class_name PebblePathIcon
extends Control

# Icona del sentiero di ciottoli "pebble_path" (2026-10-16, richiesta utente): il disegno a pezzi della mappa
# (LinearShapes) come tratto dritto, scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	LinearShapes.draw(self, "pebble_path", size * 0.5, LinearShapes.STRAIGHT_MASK, false, 1.0, minf(size.x, size.y) / 10.0)
