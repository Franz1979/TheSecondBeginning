class_name GameTypes

enum TerrainBase {
	WATER,
	PLAIN,
	HILL,
	MOUNTAIN
}

enum WaterType {
	NONE,
	SEA,
	LAKE,
	RIVER
}

enum RiverShape {
	NONE,
	VERTICAL,
	HORIZONTAL,
	CORNER_TOP_RIGHT,
	CORNER_RIGHT_BOTTOM,
	CORNER_BOTTOM_LEFT,
	CORNER_LEFT_TOP,
	FULL
}

enum Biome {
	NONE,
	FOREST,
	GRASSLAND,
	DESERT,
	SWAMP,
	FERTILE,
	ROCKY
}

enum CoastType {
	NONE,
	BEACH,
	SEMI_CLIFF,
	CLIFF
}

enum WorldObjectType {
	NONE,
	ROCK,
	TREE,
	GRASS,
	SHRUB,
	# in futuro: WILD_ANIMAL, FORAGE, ecc.
}

enum ResourceType {
	NONE,
	STONE,
	WOOD,
	HAY,
	# in futuro: FOOD, TOOLS, ecc.
}

enum SuccessionLevel {
	FORAGE = 0,
	SHRUB = 1,
	TREE = 2,
	# futuri livelli aggiunti qui, in ordine
}
