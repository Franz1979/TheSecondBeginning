class_name RiverMicrocellService
extends RefCounted

# Stessa geometria di MicroCellRenderer._draw_river/_draw_river_arc (pivot/from/to identici),
# ma qui in unità di microcelle (grid_size = World.WIDTH) invece che pixel: scala-invariante,
# dato che thickness_ratio è già normalizzato su TOTAL_SPACE. Nessuna duplicazione concettuale
# nuova — è la stessa forma già disegnata dal renderer, solo campionata a griglia intera per
# rispondere a "la microcella (x,y) è river?" invece di produrre un poligono da disegnare.
const CORNER_ARC_DATA := {
	GameTypes.RiverShape.CORNER_TOP_RIGHT: {"pivot": Vector2(1, 0), "from": PI, "to": PI / 2.0},
	GameTypes.RiverShape.CORNER_RIGHT_BOTTOM: {"pivot": Vector2(1, 1), "from": -PI / 2.0, "to": -PI},
	GameTypes.RiverShape.CORNER_BOTTOM_LEFT: {"pivot": Vector2(0, 1), "from": 0.0, "to": -PI / 2.0},
	GameTypes.RiverShape.CORNER_LEFT_TOP: {"pivot": Vector2(0, 0), "from": PI / 2.0, "to": 0.0},
}


# Restituisce tutte le posizioni microcella (Array[Vector2i]) coperte dalla fascia di fiume di
# forma `river_shape`, spessore `thickness_ratio` (0..1, frazione di TOTAL_SPACE). Funzione pura
# — nessun random, nessuno stato esterno — così il risultato è identico ogni volta che viene
# richiamata con gli stessi argomenti.
static func get_river_positions(river_shape: GameTypes.RiverShape, thickness_ratio: float) -> Array:
	var positions: Array = []
	var grid_size: float = float(World.WIDTH)
	var thickness: float = max(grid_size * clamp(thickness_ratio, 0.0, 1.0), 1.0)
	var half: float = grid_size / 2.0
	var center: float = half

	var arc_data: Dictionary = CORNER_ARC_DATA.get(river_shape, {})

	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var point := Vector2(x + 0.5, y + 0.5)
			var is_river: bool
			if not arc_data.is_empty():
				is_river = _is_in_arc_band(point, arc_data, half, thickness)
			else:
				is_river = _is_in_straight_band(point, river_shape, grid_size, center, thickness)
			if is_river:
				positions.append(Vector2i(x, y))

	return positions


static func _is_in_straight_band(
	point: Vector2, river_shape: GameTypes.RiverShape, grid_size: float, center: float, thickness: float
) -> bool:
	match river_shape:
		GameTypes.RiverShape.HORIZONTAL:
			return absf(point.y - center) <= thickness / 2.0
		GameTypes.RiverShape.FULL:
			return true
		# VERTICAL e qualunque altro valore inatteso: stesso fallback a banda verticale usato
		# da MicroCellRenderer._draw_river per restare geometricamente coerenti col disegno.
		_:
			return absf(point.x - center) <= thickness / 2.0


static func _is_in_arc_band(point: Vector2, arc_data: Dictionary, half: float, thickness: float) -> bool:
	var pivot: Vector2 = arc_data["pivot"] * (half * 2.0)
	var offset: Vector2 = point - pivot
	var radius: float = offset.length()
	if radius < half - thickness / 2.0 or radius > half + thickness / 2.0:
		return false

	var angle: float = atan2(offset.y, offset.x)
	var lo: float = min(arc_data["from"], arc_data["to"])
	var hi: float = max(arc_data["from"], arc_data["to"])
	return angle >= lo and angle <= hi
