class_name SmokehouseIcon
extends Control

# Icona provvisoria dell'edificio segnaposto "smokehouse" (2026-09-26, richiesta utente): lo stesso disegno della mappa
# (PlaceholderBuildingShapes), scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	PlaceholderBuildingShapes.draw(self, "smokehouse", size * 0.5, false, minf(size.x, size.y) / 10.0)
