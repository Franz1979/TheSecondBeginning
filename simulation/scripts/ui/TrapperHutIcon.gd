class_name TrapperHutIcon
extends Control

# Icona della capanna del trappoliere nella barra di costruzione (trapper_hut, 2026-11-07): lo stesso disegno della mappa
# (TrapperHutShape), scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	TrapperHutShape.draw(self, size * 0.5, GameTypes.Direction.SOUTH, false, 1.0, minf(size.x, size.y) / 10.0)
