class_name EarthworkIcon
extends Control

# Icona del vallo difensivo "earthwork" (2026-09-26, richiesta utente; dal 2026-10-04 il disegno a pezzi della mappa,
# EarthworkShape, come tratto dritto di argine), scalata al proprio rettangolo. Registrata in
# IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	EarthworkShape.draw(self, size * 0.5, EarthworkShape.STRAIGHT_MASK, false, 1.0, minf(size.x, size.y) / 10.0)
