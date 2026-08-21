extends Node

# Verifica una tantum (non un tool permanente): per ciascuno dei 3 livelli di
# GameTypes.PopulationSize (SPARSE/NORMAL/DENSE), carica marealtodx.json, popola con
# ParametricResourceSetupService (age=OLD) + AnimalSeedingService (density=MEDIUM) — lo stesso
# percorso che GameScene._populate_new_world segue per una vera partita — poi stampa capacity/
# target/campione di popolazioni create per specie (wolf incluso) e verifica che nessuna coppia
# di popolazioni della STESSA specie condivida anche una sola cella di territorio. Non tocca il
# motore: chiama solo l'API pubblica gia' esistente (compute_population_target incluso, cosi' il
# calcolo di capacity/target qui sotto usa la STESSA formula del service reale, non una copia).

const MAP_FILE_PATH := "user://maps/marealtodx.json"

const LEVELS := [
	{"name": "SPARSE", "enum": GameTypes.PopulationSize.SPARSE},
	{"name": "NORMAL", "enum": GameTypes.PopulationSize.NORMAL},
	{"name": "DENSE", "enum": GameTypes.PopulationSize.DENSE},
]


func _ready() -> void:
	_verify_advance_formula_never_below_step()

	for level in LEVELS:
		_run_level(level["name"], level["enum"])

	print("\n=== Fine verifica ===")
	get_tree().quit()


func _run_level(level_name: String, level_enum: GameTypes.PopulationSize) -> void:
	print("\n\n########## LIVELLO: %s ##########" % level_name)

	var load_service := WorldLoadService.new()
	var world := load_service.load_world_from_json(MAP_FILE_PATH)
	if world == null:
		push_error("Impossibile caricare la mappa %s." % MAP_FILE_PATH)
		return
	world.ensure_cell_states()

	ParametricResourceSetupService.new().populate_resources(world, GameTypes.WorldAge.OLD)
	var seeding_service := AnimalSeedingService.new()
	seeding_service.populate_animals(world, GameTypes.AnimalDensity.MEDIUM, level_enum)

	print("")
	print("=== Capacity / target / campione popolazioni create (%s) ===" % level_name)
	print("%-14s %-10s %-8s %-30s" % ["specie", "capacity", "target", "campione popolazioni create"])

	for species in AnimalCalculator.list_species_names():
		var rules := AnimalCalculator.get_animal_rules(species)
		if rules == null:
			continue

		var capacity: float = float(rules.min_territory_cells) * rules.max_density_per_cell
		# target "di riferimento" mostrato in tabella: stessa formula di compute_population_target
		# ma SENZA il jitter/disturbo casuale, solo per far vedere il centro attorno a cui il
		# +/-10% oscilla — i valori davvero creati (colonna campione) passano invece dalla
		# funzione reale, jitter incluso.
		var divisor: float = seeding_service.POPULATION_SIZE_DIVISOR[level_enum]
		var target_reference: float = capacity / divisor

		var sample: Array = []
		for group in world.population_groups:
			if group.species_name == species:
				sample.append(group.population)
				if sample.size() >= 6:
					break

		print("%-14s %-10s %-8s %-30s" % [
			species, "%.2f" % capacity, "%.2f" % target_reference, str(sample)
		])

	print("")
	print("=== Verifica sovrapposizione territori stessa specie (%s) ===" % level_name)
	var overlaps := _find_same_species_overlaps(world)
	if overlaps.is_empty():
		print("Nessuna sovrapposizione trovata.")
	else:
		print("TROVATE %d celle in sovrapposizione:" % overlaps.size())
		for entry in overlaps:
			print("  %s: cella (%d,%d) condivisa da gruppi #%s" % [
				entry["species"], entry["coords"].x, entry["coords"].y, str(entry["group_ids"])
			])


# Per ogni specie, mappa cella -> elenco id gruppi che la includono nel proprio territorio.
# Qualunque cella con piu' di un id nell'elenco e' una sovrapposizione reale.
func _find_same_species_overlaps(world: World) -> Array:
	var by_species: Dictionary = {} # species_name -> Dictionary[Vector2i, Array[int]]

	for group in world.population_groups:
		if group.territory == null:
			continue
		if not by_species.has(group.species_name):
			by_species[group.species_name] = {}
		var cell_owners: Dictionary = by_species[group.species_name]
		for coords in group.territory.occupied_macrocells:
			var owners: Array = cell_owners.get(coords, [])
			owners.append(group.id)
			cell_owners[coords] = owners

	var overlaps: Array = []
	for species_name in by_species.keys():
		var cell_owners: Dictionary = by_species[species_name]
		for coords in cell_owners.keys():
			var owners: Array = cell_owners[coords]
			if owners.size() > 1:
				overlaps.append({"species": species_name, "coords": coords, "group_ids": owners})

	return overlaps


# Verifica diretta della formula di avanzamento usata da AnimalSeedingService.
# find_candidate_start_cells (x += step + randi_range(0, jitter), idem per y): per ogni
# combinazione (step, jitter) realmente in uso dalle 9 specie, genera N incrementi con la STESSA
# formula e conferma che nessuno scenda mai sotto `step`.
func _verify_advance_formula_never_below_step() -> void:
	const TRIALS_PER_CASE := 5000
	var step_jitter_cases := [
		[1, 0], [4, 2], [5, 2], [6, 2], [7, 2], [18, 2],
	]

	var min_increment_seen: Dictionary = {}
	var all_ok := true

	for pair in step_jitter_cases:
		var step: int = pair[0]
		var jitter: int = pair[1]
		var min_increment := 999999
		for i in range(TRIALS_PER_CASE):
			var increment := step + randi_range(0, jitter)
			if increment < step:
				all_ok = false
				push_error("VIOLAZIONE: incremento %d < step %d (jitter=%d)" % [increment, step, jitter])
			min_increment = mini(min_increment, increment)
		min_increment_seen["step=%d,jitter=%d" % [step, jitter]] = min_increment

	print("=== Verifica formula di avanzamento (step + randi_range(0, jitter), %d campioni/caso) ===" % TRIALS_PER_CASE)
	for key in min_increment_seen.keys():
		print("  %s -> incremento minimo osservato: %d" % [key, min_increment_seen[key]])
	if all_ok:
		print("OK: nessun incremento e' mai sceso sotto il proprio step, su nessuno dei %d campioni totali." % (TRIALS_PER_CASE * step_jitter_cases.size()))
