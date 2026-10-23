class_name PalisadeIcon
extends Control

# Icona della palizzata "palisade" (2026-10-23): il disegno a pezzi della mappa (PalisadeShape) come tratto dritto, scalato
# al proprio rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Pali tutti inclinati verso l'alto dell'icona (un lato solo, come verso l'esterno del villaggio).
	LinearShapes.draw(
		self, "palisade", size * 0.5, LinearShapes.STRAIGHT_MASK, false, 1.0, minf(size.x, size.y) / 10.0, 0, true, Vector2.UP
	)
