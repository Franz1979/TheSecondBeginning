class_name GateIcon
extends Control

# Icona del cancello "gate" (2026-10-23): il disegno della mappa (GateShape) aperto, su un tratto dritto, con le ante verso
# l'alto dell'icona. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	LinearShapes.draw(
		self, "gate", size * 0.5, LinearShapes.STRAIGHT_MASK, false, 1.0, minf(size.x, size.y) / 10.0, 0, true, Vector2.UP
	)
