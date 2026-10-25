class_name LinearShapes
extends RefCounted

# Unico punto di disegno degli edifici LINEARI per tipo (2026-10-16, richiesta utente — con il sentiero di ciottoli il
# vallo smette di avere rami propri): mappa (MicroCellRenderer), anteprima di piazzamento (BuildingGhost) e icone chiamano
# qui con il nome del tipo; ogni tipo ha la sua classe di forma (EarthworkShape, PebblePathShape) sopra LinearShape. Un
# nuovo edificio lineare si aggiunge solo qui. Stateless.

const STRAIGHT_MASK: int = LinearShape.STRAIGHT_MASK


# true se il disegno lineare di `type_name` ha un lato scelto col tasto di rotazione (2026-10-23: la palizzata).
static func has_side(type_name: String) -> bool:
	return type_name == "palisade" or type_name == "gate"


# Come si disegna il lato di `type_name` (has_side) per `outward` sul pezzo `neighbor_mask`: due direzioni con la stessa
# firma danno lo stesso disegno (2026-10-25: il tasto di rotazione le salta, BuildingGhost.rotate_clockwise).
static func side_signature(type_name: String, neighbor_mask: int, outward: Vector2) -> Array[Vector2]:
	if type_name == "gate":
		return [GateShape.open_side(neighbor_mask, outward)]
	return PalisadeShape.lean_signature(neighbor_mask, outward)


# true se `type_name` ha un disegno lineare.
static func has_shape(type_name: String) -> bool:
	return type_name in ["earthwork", "palisade", "gate", "pebble_path"]


# `with_details` false sulla mappa: i dettagli che il renderer disegna in MultiMesh (i ciottoli del sentiero) si saltano.
# `outward` (2026-10-23, solo la palizzata): verso cui si inclinano i pali (PalisadeShape.side_vector della direzione
# dell'edificio); nullo = zig-zag.
static func draw(
	canvas: CanvasItem, type_name: String, center: Vector2, neighbor_mask: int, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0, clip_mask: int = 0, with_details: bool = true, outward: Vector2 = Vector2.ZERO, gate_open: bool = true
) -> void:
	match type_name:
		"earthwork":
			EarthworkShape.draw(canvas, center, neighbor_mask, invalid, alpha, scale, clip_mask)
		"palisade":
			PalisadeShape.draw(canvas, center, neighbor_mask, invalid, alpha, scale, clip_mask, outward)
		"gate":
			GateShape.draw(canvas, center, neighbor_mask, invalid, alpha, scale, outward, gate_open)
		"pebble_path":
			PebblePathShape.draw(canvas, center, neighbor_mask, invalid, alpha, scale, clip_mask, with_details)


# Fondo sotto il tracciato (oggi il vallo; il sentiero usa il tile della terra battuta, MicroCellRenderer).
static func draw_ground(
	canvas: CanvasItem, type_name: String, center: Vector2, neighbor_mask: int, clip_mask: int, fill_mask: int, color: Color
) -> void:
	match type_name:
		"earthwork":
			EarthworkShape.draw_ground(canvas, center, neighbor_mask, clip_mask, fill_mask, color)
		"palisade":
			PalisadeShape.draw_ground(canvas, center, neighbor_mask, clip_mask, fill_mask, color)
		"gate":
			GateShape.draw_ground(canvas, center, neighbor_mask, clip_mask, fill_mask, color)
