class_name BuildingCalculator
extends RefCounted

const BUILDINGS_DIR := "res://simulation/data/buildings/"

# Sottocartella -> categoria (2026-10-03, richiesta utente — riorganizzazione per categoria): i .tres stanno in
# BUILDINGS_DIR/<cartella>/, la cartella segue BuildingRules.category. Usata da DataFileIndex solo per avvisare se
# un file è nella cartella sbagliata; la risoluzione resta per nome.
const BUILDING_FOLDER_CATEGORIES := {
	"residential": BuildingTypes.Category.RESIDENTIAL,
	"political": BuildingTypes.Category.POLITICAL,
	"storage": BuildingTypes.Category.STORAGE,
	"movement": BuildingTypes.Category.MOVEMENT,
	"production": BuildingTypes.Category.PRODUCTION,
	"military": BuildingTypes.Category.MILITARY,
	"religious": BuildingTypes.Category.RELIGIOUS,
}

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
	var path := DataFileIndex.resolve_path(BUILDINGS_DIR, building_type_name, BUILDING_FOLDER_CATEGORIES)
	var rules: BuildingRules = null
	if path != "" and ResourceLoader.exists(path):
		rules = load(path) as BuildingRules
	_rules_cache[building_type_name] = rules
	return rules


# Elenco per convenzione (un nome per ogni {building_type_name}.tres in BUILDINGS_DIR o in una sua sottocartella) — stesso
# principio già usato da AnimalCalculator.list_species_names/ResourceCalculator: un nuovo tipo di
# edificio compare qui da solo appena il suo .tres viene aggiunto, senza toccare questo file.
static func list_building_type_names() -> Array[String]:
	# Scansione ricorsiva delle sottocartelle per categoria (2026-10-03), .remap compresi: vedi DataFileIndex.
	return DataFileIndex.list_names(BUILDINGS_DIR, BUILDING_FOLDER_CATEGORIES)
