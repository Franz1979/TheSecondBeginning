class_name BuildingCalculator
extends RefCounted

const BUILDINGS_DIR := "res://simulation/data/buildings/"

# Cache in-memory (2026-09-19, richiesta utente — correzione prestazioni: get_building_rules è
# chiamata OGNI FRAME dentro GameScene._process mentre il fantasma edificio è attivo durante il
# piazzamento, ognuna rifacendo ResourceLoader.exists()+load() da disco) — STESSO identico
# principio/STESSA struttura di AnimalCalculator._rules_cache/CaloricCalculator._rules_cache:
# building_type_name -> BuildingRules (o null se irrisolvibile, per non ritentare ResourceLoader.
# exists ad ogni chiamata con un nome sbagliato). static: RefCounted senza istanza persistente, un
# Dictionary di classe è l'unico modo di cachare tra chiamate — sicuro perché i file .tres non
# cambiano a runtime in una sessione di gioco.
static var _rules_cache: Dictionary = {}


static func get_building_rules(building_type_name: String) -> BuildingRules:
	if _rules_cache.has(building_type_name):
		return _rules_cache[building_type_name]
	var path := BUILDINGS_DIR + building_type_name + ".tres"
	var rules: BuildingRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as BuildingRules
	_rules_cache[building_type_name] = rules
	return rules


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
