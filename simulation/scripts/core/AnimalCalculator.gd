class_name AnimalCalculator
extends RefCounted

const ANIMALS_DIR := "res://simulation/data/animals/"


static func get_animal_rules(species_name: String) -> AnimalRules:
	var path := ANIMALS_DIR + species_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AnimalRules


# Elenco per convenzione (un nome per ogni {species_name}.tres in ANIMALS_DIR), stesso principio
# già usato da ResourceCalculator per le risorse: una specie futura (es. birds) compare qui da
# sola appena il suo .tres viene aggiunto, senza toccare questo file — usato dal menu a tendina
# di specie in GameScene (debug "imposta popolazione").
static func list_species_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(ANIMALS_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			names.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names
