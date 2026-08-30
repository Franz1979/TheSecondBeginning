class_name AnimalCalculator
extends RefCounted

const ANIMALS_DIR := "res://simulation/data/animals/"

# Cache in-memory (2026-08-30, diagnosticato in sessione: get_animal_rules era chiamata migliaia
# di volte al giorno/checkpoint per sole ~10 specie distinte, ognuna rifacendo ResourceLoader.
# exists()+load() da disco — misurato come causa concreta di lentezza, poi aggravato da LOD0 che
# la chiama anche in _mark_feeding_ground_if_herbivore). species_name -> AnimalRules (o null se
# irrisolvibile, per non ritentare ResourceLoader.exists ad ogni chiamata con un nome sbagliato).
# static: RefCounted senza istanza persistente, un Dictionary di classe è l'unico modo di cachare
# tra chiamate — sicuro perché i file .tres non cambiano a runtime in una sessione di gioco.
static var _rules_cache: Dictionary = {}


static func get_animal_rules(species_name: String) -> AnimalRules:
	if _rules_cache.has(species_name):
		return _rules_cache[species_name]
	var path := ANIMALS_DIR + species_name + ".tres"
	var rules: AnimalRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as AnimalRules
	_rules_cache[species_name] = rules
	return rules


# Elenco per convenzione (un nome per ogni {species_name}.tres in ANIMALS_DIR), stesso principio
# già usato da ResourceCalculator per le risorse: una specie futura (es. birds) compare qui da
# sola appena il suo .tres viene aggiunto, senza toccare questo file — usato dal menu a tendina
# di specie in WorldScene (debug "imposta popolazione").
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
