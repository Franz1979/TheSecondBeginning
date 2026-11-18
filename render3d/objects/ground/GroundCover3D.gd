class_name GroundCover3D
extends RefCounted

# Oggetto 3D: i suoli di UNA macrocella, come "maschera" letta dallo shader del terreno (terrain.gdshader). Un pixel per
# microcella: R = la microcella ha la risorsa erba (prato), G = ha un albero (sottobosco), B = ha una roccia (ghiaia),
# A = ha un cespuglio (sottocespuglio). Tutto a zero = terra. Lo shader la legge sfumata e ne frastaglia i confini.

const CHANNELS := 4


static func build_image(snapshot: GroundCoverSnapshot3D) -> Image:
	var size := World.WIDTH
	var bytes := PackedByteArray()
	bytes.resize(size * size * CHANNELS)
	_mark(bytes, size, snapshot.grass, 0)
	_mark(bytes, size, snapshot.trees, 1)
	_mark(bytes, size, snapshot.rocks, 2)
	_mark(bytes, size, snapshot.shrubs, 3)
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)


# positions: microcelle (Vector2i o Vector3i, di cui contano x e y).
static func _mark(bytes: PackedByteArray, size: int, positions: Array, channel: int) -> void:
	for pos in positions:
		if pos.x < 0 or pos.y < 0 or pos.x >= size or pos.y >= size:
			continue
		bytes[(pos.y * size + pos.x) * CHANNELS + channel] = 255
