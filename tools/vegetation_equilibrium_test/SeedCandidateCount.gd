extends Node

# Harness diagnostico standalone (stessa convenzione di VegetationEquilibriumTest/
# ParametricSeedCheck in questa stessa cartella): NON crea alcun PopulationGroup, NON chiama
# TerritoryBuilderService — misura solo QUANTI punti di semina candidati esistono per specie su
# una mappa reale. Serve come dato di calibrazione per un parametro di densità di popolazione
# ("Pochi/Medi/Tanti"), non è il seminatore automatico.
#
# La scansione a griglia con jitter (passo derivato da max_territory_cells, ricerca di recupero a
# raggio crescente) vive ora in AnimalSeedingService.find_candidate_start_cells — l'unica
# implementazione, condivisa col seminatore automatico vero e proprio: questo file non ne tiene
# più una copia propria, si limita a chiamarla e a formattare l'output per la diagnosi.
#
# Esecuzione (headless, dalla cartella del progetto):
#   godot4 --headless --path . res://tools/vegetation_equilibrium_test/SeedCandidateCount.tscn

const MAP_FILE_PATH := "user://maps/marealtodx.json"
const OUTPUT_JSON_PATH := "res://tools/vegetation_equilibrium_test/seed_candidate_counts.json"


func _ready() -> void:
	print("=== Seed Candidate Count (griglia con jitter, mappa reale) ===")
	print("Mappa: %s" % MAP_FILE_PATH)

	var load_service := WorldLoadService.new()
	var world := load_service.load_world_from_json(MAP_FILE_PATH)
	if world == null:
		push_error("Impossibile caricare la mappa %s." % MAP_FILE_PATH)
		get_tree().quit(1)
		return
	world.ensure_cell_states()
	print("Mappa caricata: %d celle.\n" % world.cells.size())

	var seeding_service := AnimalSeedingService.new()
	var results: Dictionary = {}
	var low_candidate_species: Array = []

	print("%-14s %-20s %-6s %-8s %-12s" % ["specie", "max_territory_cells", "step", "jitter", "candidati_unici"])
	for species in AnimalCalculator.list_species_names():
		var rules := AnimalCalculator.get_animal_rules(species)
		if rules == null:
			push_error("Nessun AnimalRules trovato per '%s' — .tres mancante o nome errato." % species)
			continue

		var max_cells: int = rules.max_territory_cells
		var step: int = maxi(ceili(sqrt(float(max_cells))), 1)
		var jitter: int = mini(2, step / 2)

		var candidates := seeding_service.find_candidate_start_cells(world, rules)
		var candidate_coords: Array = []
		for coords in candidates:
			candidate_coords.append([coords.x, coords.y])

		results[species] = {
			"max_territory_cells": max_cells,
			"step": step,
			"jitter": jitter,
			"candidate_count": candidates.size(),
			"candidate_coords": candidate_coords,
		}

		print("%-14s %-20d %-6d %-8d %-12d" % [species, max_cells, step, jitter, candidates.size()])

		if candidates.size() < 5:
			low_candidate_species.append({"species": species, "count": candidates.size()})

	print("")
	print("=== Note sul jitter e sul tetto di tentativi (vedi AnimalSeedingService.gd) ===")
	print("Jitter per-punto: +/- min(2, step/2) celle, sia in x che in y. Stesso range")
	print("riapplicato indipendentemente all'avanzamento riga-su-riga. Raggio massimo di")
	print("recupero attorno a un punto non idoneo: %d celle (anello di Chebyshev, ordine" % AnimalSeedingService.MAX_SEARCH_RADIUS)
	print("casuale ad ogni raggio) prima di scartare il punto di griglia.")

	print("")
	print("=== SPECIE CON POCHI CANDIDATI (<5) ===")
	if low_candidate_species.is_empty():
		print("Nessuna. Tutte le specie hanno almeno 5 punti di semina candidati su questa mappa.")
	else:
		for entry in low_candidate_species:
			print("  %s: %d candidati" % [entry["species"], entry["count"]])

	_write_json(results)

	print("\n=== Fine ===")
	get_tree().quit()


func _write_json(results: Dictionary) -> void:
	var file := FileAccess.open(OUTPUT_JSON_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Impossibile scrivere %s (errore %d)" % [OUTPUT_JSON_PATH, FileAccess.get_open_error()])
		return
	var payload := {
		"map_file": MAP_FILE_PATH,
		"max_search_radius": AnimalSeedingService.MAX_SEARCH_RADIUS,
		"species": results,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("\nConteggio candidati esportato in: %s" % OUTPUT_JSON_PATH)
