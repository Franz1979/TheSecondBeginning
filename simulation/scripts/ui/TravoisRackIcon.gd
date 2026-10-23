class_name TravoisRackIcon
extends Control

# Icona dell'Appoggio per travois "travois_rack" (2026-10-23, 1x1): lo stesso disegno della mappa (TravoisRackShape), pieno,
# scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	TravoisRackShape.draw(self, size * 0.5, GameTypes.Direction.SOUTH, TravoisRackShape.CAPACITY, false, 1.0, minf(size.x, size.y) / 10.0)
