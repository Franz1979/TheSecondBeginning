class_name IdeaCalculator
extends RefCounted

# Caricamento per-id di Idea (.tres) — stesso identico pattern/stessa convenzione di
# BuildingCalculator (get_building_rules/list_building_type_names) e AnimalCalculator/
# ResourceCalculator: un file per id in IDEAS_DIR, nome file == Idea.id (stessa convenzione già
# in uso per BuildingRules.building_type_name/nome file .tres).
#
# Spostata insieme a Idea.gd (2026-09-07, richiesta utente) da simulation/ a human/ — Idea
# rappresenta progresso tecnologico del Folk (dominio umano/player), non simulazione di mondo:
# IdeaProgressService (stesso dominio, stessa cartella) era già qui, questo file e i suoi dati
# erano rimasti indietro per inerzia. IDEAS_DIR aggiornata di conseguenza, stessa convenzione di
# human/data/era_rules/ e human/data/human_rules/ per i dati di dominio umano.
const IDEAS_DIR := "res://human/data/ideas/"


static func get_idea(idea_id: String) -> Idea:
	var path := IDEAS_DIR + idea_id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Idea


# Elenco per convenzione (un id per ogni {id}.tres in IDEAS_DIR) — stesso principio già usato da
# BuildingCalculator.list_building_type_names: una nuova Idea compare qui da sola appena il suo
# .tres viene aggiunto, senza toccare questo file.
static func list_idea_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(IDEAS_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			ids.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids
