class_name PotterHutIcon
extends Control

# Icona della capanna del vasellaio nella barra di costruzione (potter_hut, 2026-11-03): lo stesso disegno della mappa
# (PotterHutShape), scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	PotterHutShape.draw(self, size * 0.5, GameTypes.Direction.SOUTH, false, 1.0, minf(size.x, size.y) / 10.0)
