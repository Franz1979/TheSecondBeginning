class_name WaterShelterIcon
extends Control

# Icona della Tettoia dell'acqua "water_shelter" (2026-11-06, 1x1): lo stesso disegno della mappa (WaterShelterShape), piena,
# scalata al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Il disegno occupa circa una microcella (10 unità): lo si scala al lato minore del rettangolo.
	var full: Array = []
	full.resize(WaterShelterShape.CAPACITY)
	full.fill(1)
	WaterShelterShape.draw(self, size * 0.5, GameTypes.Direction.SOUTH, full, false, 1.0, minf(size.x, size.y) / 10.0)
