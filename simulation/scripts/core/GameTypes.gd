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
	FISH,
	BIRDS,
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

enum AgeBand {
	YOUNG,
	ADULT,
	OLD
}

enum NaturalEventType {
	NONE,
	FIRE,
	DROUGHT,
	SEA_FLOOD,
	# in futuro: RIVER_FLOOD, EARTHQUAKE, ecc.
}

enum Season {
	WINTER,
	SPRING,
	SUMMER,
	AUTUMN,
}

# Livello di maturita' del mondo al momento del seeding iniziale (vedi
# ParametricResourceSetupService) — asse concettualmente distinto da AgeBand sopra (che descrive
# la fascia d'eta' di una singola coorte di individui/vegetazione dentro una cella, non l'eta'
# del mondo intero): stessi nomi di membro per leggibilita' del design approvato, ma sono due
# enum separati (GameTypes.WorldAge.OLD != GameTypes.AgeBand.OLD).
enum WorldAge {
	YOUNG,
	ADULT,
	OLD
}

# Livello di densita' del seeding automatico delle popolazioni animali (vedi
# AnimalSeedingService) — indipendente da WorldAge sopra: controlla quante popolazioni vengono
# create tra le celle candidate idonee per specie, non lo stato di maturita' del mondo.
enum AnimalDensity {
	FEW,
	MEDIUM,
	MANY
}

# Livello di numerosita' di CIASCUNA popolazione creata dal seeding automatico (vedi
# AnimalSeedingService) — indipendente da AnimalDensity sopra: quello controlla QUANTE
# popolazioni vengono create, questo controlla QUANTI individui ciascuna ne contiene.
enum PopulationSize {
	SPARSE,
	NORMAL,
	DENSE
}
