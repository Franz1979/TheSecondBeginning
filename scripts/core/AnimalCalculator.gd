class_name AnimalCalculator
extends RefCounted

const ANIMALS_DIR := "res://data/animals/"


static func get_animal_rules(species_name: String) -> AnimalRules:
	var path := ANIMALS_DIR + species_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AnimalRules
