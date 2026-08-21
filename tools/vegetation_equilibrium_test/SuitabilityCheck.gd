extends Node

# Verifica numerica una tantum (non un tool permanente): richiama is_suitable_for per ciascuna
# specie con un caso atteso idoneo e uno atteso escluso, secondo la tabella approvata. Non
# genera un mondo, chiama solo AnimalCalculator/AnimalRules.

func _check(species: String, biome: GameTypes.Biome, terrain: GameTypes.TerrainBase, expected: bool, label: String) -> void:
	var rules := AnimalCalculator.get_animal_rules(species)
	var result := rules.is_suitable_for(biome, terrain)
	var status := "OK" if result == expected else "MISMATCH"
	print("  [%s] %s: is_suitable_for(%s,%s)=%s atteso=%s -- %s" % [
		status, species, GameTypes.Biome.keys()[biome], GameTypes.TerrainBase.keys()[terrain],
		result, expected, label
	])


func _ready() -> void:
	print("=== Verifica suitable_biomes/suitable_terrains ===")

	_check("rabbit", GameTypes.Biome.GRASSLAND, GameTypes.TerrainBase.PLAIN, true, "idoneo")
	_check("rabbit", GameTypes.Biome.DESERT, GameTypes.TerrainBase.PLAIN, false, "escluso (bioma)")

	_check("deer", GameTypes.Biome.FOREST, GameTypes.TerrainBase.HILL, true, "idoneo")
	_check("deer", GameTypes.Biome.FOREST, GameTypes.TerrainBase.MOUNTAIN, false, "escluso (terreno)")

	_check("aurochs", GameTypes.Biome.GRASSLAND, GameTypes.TerrainBase.PLAIN, true, "idoneo")
	_check("aurochs", GameTypes.Biome.DESERT, GameTypes.TerrainBase.PLAIN, false, "escluso (bioma)")

	_check("tarpan", GameTypes.Biome.FERTILE, GameTypes.TerrainBase.HILL, true, "idoneo")
	_check("tarpan", GameTypes.Biome.FOREST, GameTypes.TerrainBase.PLAIN, false, "escluso (bioma)")

	_check("wild_donkey", GameTypes.Biome.DESERT, GameTypes.TerrainBase.MOUNTAIN, true, "idoneo")
	_check("wild_donkey", GameTypes.Biome.FOREST, GameTypes.TerrainBase.PLAIN, false, "escluso (bioma)")

	_check("boar", GameTypes.Biome.SWAMP, GameTypes.TerrainBase.MOUNTAIN, true, "idoneo")
	_check("boar", GameTypes.Biome.ROCKY, GameTypes.TerrainBase.HILL, false, "escluso (bioma)")

	_check("mouflon", GameTypes.Biome.ROCKY, GameTypes.TerrainBase.MOUNTAIN, true, "idoneo")
	_check("mouflon", GameTypes.Biome.ROCKY, GameTypes.TerrainBase.WATER, false, "escluso (terreno)")

	_check("bezoar", GameTypes.Biome.DESERT, GameTypes.TerrainBase.HILL, true, "idoneo")
	_check("bezoar", GameTypes.Biome.FOREST, GameTypes.TerrainBase.PLAIN, false, "escluso (bioma)")

	_check("wolf", GameTypes.Biome.DESERT, GameTypes.TerrainBase.MOUNTAIN, true, "idoneo (nessuna restrizione)")
	_check("wolf", GameTypes.Biome.NONE, GameTypes.TerrainBase.WATER, true, "idoneo (nessuna restrizione, anche WATER a livello di suitability)")

	print("=== Fine verifica ===")
	get_tree().quit()
