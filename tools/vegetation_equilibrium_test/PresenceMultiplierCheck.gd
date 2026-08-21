extends Node

# Verifica numerica una tantum (non un tool permanente): ricalcola get_presence_chance/
# get_water_presence_chance per i casi gia' documentati come problematici, prima e dopo
# l'introduzione dell'asse presence_*, per confermare che ora la presenza non scali piu' con
# terrain/biome/coast/water. Non genera un mondo, chiama solo l'API statica di
# ResourceCalculator/GameTypes.

func _ready() -> void:
	print("=== Verifica asse presence_* ===")

	print("\n-- GRASS --")
	print("  MOUNTAIN|ROCKY|NONE coast: presence_chance = %.4f (atteso: 0.8000, la sola base)" % [
		ResourceCalculator.get_presence_chance(GameTypes.WorldObjectType.GRASS, GameTypes.TerrainBase.MOUNTAIN, GameTypes.Biome.ROCKY, GameTypes.CoastType.NONE)
	])
	print("  PLAIN|GRASSLAND|CLIFF coast: presence_chance = %.4f (atteso: 0.8000, prima era 0.0 per coast_multiplier_cliff=0.0)" % [
		ResourceCalculator.get_presence_chance(GameTypes.WorldObjectType.GRASS, GameTypes.TerrainBase.PLAIN, GameTypes.Biome.GRASSLAND, GameTypes.CoastType.CLIFF)
	])
	print("  max_density MOUNTAIN|ROCKY (deve restare invariato, basso): %.4f" % [
		ResourceCalculator.get_max_density(GameTypes.WorldObjectType.GRASS, GameTypes.TerrainBase.MOUNTAIN, GameTypes.Biome.ROCKY, GameTypes.CoastType.NONE)
	])

	print("\n-- SHRUB --")
	print("  MOUNTAIN|DESERT|NONE coast: presence_chance = %.4f (atteso: 0.5500, la sola base)" % [
		ResourceCalculator.get_presence_chance(GameTypes.WorldObjectType.SHRUB, GameTypes.TerrainBase.MOUNTAIN, GameTypes.Biome.DESERT, GameTypes.CoastType.NONE)
	])

	print("\n-- BIRDS --")
	print("  MOUNTAIN|ROCKY|NONE coast: presence_chance = %.4f (atteso: 0.4000, la sola base)" % [
		ResourceCalculator.get_presence_chance(GameTypes.WorldObjectType.BIRDS, GameTypes.TerrainBase.MOUNTAIN, GameTypes.Biome.ROCKY, GameTypes.CoastType.NONE)
	])

	print("\n-- FISH --")
	print("  RIVER: presence_chance = %.4f (atteso: 0.5000, la sola base — prima era 0.15)" % [
		ResourceCalculator.get_water_presence_chance(GameTypes.WorldObjectType.FISH, GameTypes.WaterType.RIVER)
	])
	print("  LAKE: presence_chance = %.4f (atteso: 0.5000, la sola base — prima era 0.30)" % [
		ResourceCalculator.get_water_presence_chance(GameTypes.WorldObjectType.FISH, GameTypes.WaterType.LAKE)
	])
	print("  water_max_density RIVER (deve restare invariato, basso): %.4f" % [
		ResourceCalculator.get_water_max_density(GameTypes.WorldObjectType.FISH, GameTypes.WaterType.RIVER)
	])

	print("\n-- STONE (non toccato, deve restare accoppiato come prima) --")
	print("  MOUNTAIN|ROCKY|NONE coast: presence_chance = %.4f (invariato: 0.4 * 1.1 * 1.5 = 0.66)" % [
		ResourceCalculator.get_presence_chance(GameTypes.WorldObjectType.ROCK, GameTypes.TerrainBase.MOUNTAIN, GameTypes.Biome.ROCKY, GameTypes.CoastType.NONE)
	])

	print("\n-- TREE (non toccato, deve restare accoppiato come prima) --")
	print("  PLAIN|DESERT|NONE coast: presence_chance = %.4f (invariato: 0.0, biome_multiplier_desert=0.0)" % [
		ResourceCalculator.get_presence_chance(GameTypes.WorldObjectType.TREE, GameTypes.TerrainBase.PLAIN, GameTypes.Biome.DESERT, GameTypes.CoastType.NONE)
	])

	print("\n=== Fine verifica ===")
	get_tree().quit()
