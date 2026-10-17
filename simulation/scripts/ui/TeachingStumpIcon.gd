class_name TeachingStumpIcon
extends Control

# Icona dell'edificio "teaching_stump" (2026-10-16, richiesta utente): lo stesso disegno della mappa
# (PlaceholderBuildingShapes), scalato al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	PlaceholderBuildingShapes.draw(self, "teaching_stump", size * 0.5, false, minf(size.x, size.y) / 10.0)
