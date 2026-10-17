class_name LinearShapes
extends RefCounted

# Unico punto di disegno degli edifici LINEARI per tipo (2026-10-16, richiesta utente — con il sentiero di ciottoli il
# vallo smette di avere rami propri): mappa (MicroCellRenderer), anteprima di piazzamento (BuildingGhost) e icone chiamano
# qui con il nome del tipo; ogni tipo ha la sua classe di forma (EarthworkShape, PebblePathShape) sopra LinearShape. Un
# nuovo edificio lineare si aggiunge solo qui. Stateless.

const STRAIGHT_MASK: int = LinearShape.STRAIGHT_MASK


# true se `type_name` ha un disegno lineare.
static func has_shape(type_name: String) -> bool:
	return type_name in ["earthwork", "pebble_path"]


# `with_details` false sulla mappa: i dettagli che il renderer disegna in MultiMesh (i ciottoli del sentiero) si saltano.
static func draw(
	canvas: CanvasItem, type_name: String, center: Vector2, neighbor_mask: int, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0, clip_mask: int = 0, with_details: bool = true
) -> void:
	match type_name:
		"earthwork":
			EarthworkShape.draw(canvas, center, neighbor_mask, invalid, alpha, scale, clip_mask)
		"pebble_path":
			PebblePathShape.draw(canvas, center, neighbor_mask, invalid, alpha, scale, clip_mask, with_details)


# Fondo sotto il tracciato (oggi il vallo; il sentiero usa il tile della terra battuta, MicroCellRenderer).
static func draw_ground(
	canvas: CanvasItem, type_name: String, center: Vector2, neighbor_mask: int, clip_mask: int, fill_mask: int, color: Color
) -> void:
	match type_name:
		"earthwork":
			EarthworkShape.draw_ground(canvas, center, neighbor_mask, clip_mask, fill_mask, color)
