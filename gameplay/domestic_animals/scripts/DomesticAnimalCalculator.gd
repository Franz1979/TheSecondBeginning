class_name DomesticAnimalCalculator
extends RefCounted

# Caricatore delle specie domestiche per convenzione nome-file (addomesticazione passo 1, 2026-10-26) — stesso
# schema di AnimalCalculator: una specie nuova compare da sola appena si aggiunge il suo .tres.

const DATA_DIR := "res://gameplay/domestic_animals/data/"

# species_name -> DomesticAnimalRules (o null se il file non esiste, per non ritentare). Sicuro come in
# AnimalCalculator: i .tres non cambiano a runtime.
static var _rules_cache: Dictionary = {}


static func get_rules(species_name: String) -> DomesticAnimalRules:
	if _rules_cache.has(species_name):
		return _rules_cache[species_name]
	var path := DATA_DIR + species_name + ".tres"
	var rules: DomesticAnimalRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as DomesticAnimalRules
	_rules_cache[species_name] = rules
	return rules


static func list_species() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# Build esportate: "*.tres.remap", come AnimalCalculator.list_species_names.
		var resource_file := file_name.trim_suffix(".remap")
		if not dir.current_is_dir() and resource_file.ends_with(".tres") and not names.has(resource_file.get_basename()):
			names.append(resource_file.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


# Regole della specie selvatica d'origine (es. il lupo per il cane); null con warning se non esiste.
static func get_wild_rules(species_name: String) -> AnimalRules:
	var rules := get_rules(species_name)
	if rules == null:
		return null
	var wild := AnimalCalculator.get_animal_rules(rules.wild_species_name)
	if wild == null:
		push_warning("DomesticAnimalCalculator: specie selvatica '%s' di '%s' inesistente" % [rules.wild_species_name, species_name])
	return wild
