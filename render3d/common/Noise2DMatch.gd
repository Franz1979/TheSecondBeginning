class_name Noise2DMatch
extends RefCounted

# Lo stesso rumore deterministico che usa il disegno 2D (MicroCellRenderer._stream_noise): stesso punto e stesso
# canale = stesso valore 0..1. Serve agli oggetti 3D che devono avere la stessa forma del 2D (ruscello, argilla).

static func value(key: Vector2i, channel: int) -> float:
	var h: int = (key.x * 73856093) ^ (key.y * 19349663) ^ (channel * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
