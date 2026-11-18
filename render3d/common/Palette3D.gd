class_name Palette3D
extends RefCounted

# Colori della vista 3D (stile low-poly caldo). Il terreno parte dal colore del 2D (TerrainColors, che decide per terreno,
# bioma e costa) e lo traduce nella tinta 3D: la logica su quale colore spetta a quale cella resta una sola.

const TERRAIN_BY_2D_COLOR := {
	TerrainColors.PLAIN: Color("7fb556"),
	TerrainColors.PLAIN_FOREST: Color("5f9442"),
	TerrainColors.PLAIN_DESERT: Color("d6c085"),
	TerrainColors.PLAIN_SWAMP: Color("6c7843"),
	TerrainColors.PLAIN_FERTILE: Color("74a849"),
	TerrainColors.PLAIN_ROCKY: Color("9a927f"),
	TerrainColors.HILL: Color("a8975f"),
	TerrainColors.MOUNTAIN: Color("7a6650"),
	TerrainColors.BEACH: Color("dcc98e"),
	TerrainColors.SEMI_CLIFF: Color("a3a29a"),
	TerrainColors.CLIFF: Color("8b8a84"),
}

# Quanto il terreno è terra/roccia invece che prato (0 = prato, 1 = terra), per lo shader del terreno. Non elencati = prato.
const DIRT_BY_2D_COLOR := {
	TerrainColors.PLAIN_DESERT: 1.0,
	TerrainColors.PLAIN_ROCKY: 0.6,
	TerrainColors.HILL: 0.4,
	TerrainColors.MOUNTAIN: 1.0,
	TerrainColors.BEACH: 1.0,
	TerrainColors.SEMI_CLIFF: 1.0,
	TerrainColors.CLIFF: 1.0,
}

# Fondale sotto l'acqua.
const SEABED := Color("5e5a3e")

const WATER_SEA := Color("2f6f9f")
const WATER_LAKE := Color("3b86b4")
const WATER_RIVER := Color("4a96c4")
const WATER_ALPHA := 0.82


static func terrain_color(color_2d: Color) -> Color:
	return TERRAIN_BY_2D_COLOR.get(color_2d, color_2d)


static func dirt_amount(color_2d: Color) -> float:
	return DIRT_BY_2D_COLOR.get(color_2d, 0.0)
