class_name StoneFordIcon
extends Control

# Icona dell'edificio "stone_ford" (2026-10-31, richiesta utente — Guado di pietre): lo stesso disegno della mappa
# (PlaceholderBuildingShapes) su una striscia d'acqua, scalato al proprio rettangolo. Registrata in
# IconRegistry.BUILDING_ICON_NODES.

const WATER_COLOR := Color(0.33, 0.55, 0.78, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var unit := minf(size.x, size.y) / 10.0
	var center := size * 0.5
	draw_rect(Rect2(Vector2(0.0, center.y - 2.2 * unit), Vector2(size.x, 4.4 * unit)), WATER_COLOR)
	PlaceholderBuildingShapes.draw(self, "stone_ford", center, false, unit)
