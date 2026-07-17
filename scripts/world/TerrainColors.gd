class_name TerrainColors
extends RefCounted

const SEA := Color(0.10, 0.30, 0.90)
const LAKE := Color(0.15, 0.50, 0.95)
const RIVER := Color(0.20, 0.60, 1.00)
const PLAIN := Color(0.60, 0.90, 0.60)
const HILL := Color(0.82, 0.68, 0.45)
const MOUNTAIN := Color(0.45, 0.25, 0.10)
const BEACH := Color(0.95, 0.85, 0.55)
const SEMI_CLIFF := Color(0.72, 0.72, 0.72)
const CLIFF := Color(0.55, 0.55, 0.55)
const GRID := Color(0, 0, 0, 0.15)


# Colore "piatto" di una cella in base a terrain/water/coast. Condiviso da WorldRenderer
# (mondo macro) e MicroCellRenderer (vista microcella) così i due restano sempre coerenti:
# aggiornare un colore qui lo aggiorna in entrambe le viste.
static func get_cell_color(cell: MacroCellData) -> Color:
	match cell.water_type:
		GameTypes.WaterType.SEA:
			return SEA
		GameTypes.WaterType.LAKE:
			return LAKE
		GameTypes.WaterType.RIVER:
			return RIVER

	return get_land_color(cell)


# Colore del solo terrain_base/coast, ignorando water_type. Serve a chi disegna il fiume
# come una fascia sopra il terreno (WorldRenderer/MicroCellRenderer) invece che come un
# riempimento piatto: la cella di un fiume è terreno vero (es. PLAIN) attraversato da acqua,
# non una cella "tutta acqua".
static func get_land_color(cell: MacroCellData) -> Color:
	match cell.terrain_base:
		GameTypes.TerrainBase.WATER:
			return SEA
		GameTypes.TerrainBase.PLAIN:
			match cell.coast_type:
				GameTypes.CoastType.BEACH:
					return BEACH
				_:
					return PLAIN
		GameTypes.TerrainBase.HILL:
			match cell.coast_type:
				GameTypes.CoastType.SEMI_CLIFF:
					return SEMI_CLIFF
				_:
					return HILL
		GameTypes.TerrainBase.MOUNTAIN:
			match cell.coast_type:
				GameTypes.CoastType.CLIFF:
					return CLIFF
				_:
					return MOUNTAIN
		_:
			return Color.MAGENTA
