class_name BuildingCalculator
extends RefCounted

const BUILDINGS_DIR := "res://simulation/data/buildings/"


static func get_building_rules(building_type_name: String) -> BuildingRules:
	var path := BUILDINGS_DIR + building_type_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as BuildingRules


# Elenco per convenzione (un nome per ogni {building_type_name}.tres in BUILDINGS_DIR) — stesso
# principio già usato da AnimalCalculator.list_species_names/ResourceCalculator: un nuovo tipo di
# edificio compare qui da solo appena il suo .tres viene aggiunto, senza toccare questo file.
static func list_building_type_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(BUILDINGS_DIR)
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
