class_name BrowsingMitigationService
extends RefCounted

# Step 11: mitigazione dell'encroachment (SHRUB/TREE su GRASS) legata alla sola PRESENZA FISICA
# di fauna brucante (AnimalRules.is_browsing_species), non alla disponibilità calorica — quel
# fenomeno (fame/scarsità) è già coperto altrove (AnimalHungerService/AnimalOldAgeMortalityService)
# e non serve più qui. Un prototipo calorico precedente (GrazingPressureService) è stato
# scartato e rimosso a favore di questo approccio, deciso con l'utente. Step 4: il risultato è
# ora un INPUT REALE per ResourceEncroachmentService.encroach_resources (vedi
# WorldTimeService._run_growth_checkpoint), non più solo calcolo/log.
#
# Per ogni specie is_browsing_species presente in una cella:
#   density_ratio_species = count_specie_in_cella / max_density_per_cell_specie   (MAI clampato)
#   browsing_factor_species = 1 - (MAX_BROWSING_EFFECT * density_ratio_species)   (può andare < 0)
# Combinato per cella (prodotto tra tutte le specie presenti, quelle assenti non contribuiscono):
#   combined_browsing_factor = product(browsing_factor_species) clampato a >= 0.0 alla fine.
#
# MAX_BROWSING_EFFECT: parametro globale (non per specie) — nessun Resource di configurazione
# globale esiste ancora nel progetto (ogni "Rules" è per-entità: per specie/risorsa/evento), e
# ogni altro meccanismo di mitigazione qui vicino (TerritoryDynamicsService, AnimalBirthMitigationService)
# tiene le proprie costanti di tuning come `const` locali al servizio che le usa — stesso
# principio riapplicato qui invece di introdurre un nuovo tipo di risorsa condivisa per un solo
# valore. Se in futuro si accumulano più parametri globali di questo tipo, vale la pena
# promuoverli a una Resource condivisa; per ora sarebbe un'astrazione prematura.
const MAX_BROWSING_EFFECT := 0.4


func compute_browsing_mitigation(world: World) -> Dictionary:
	var counts_by_cell := _collect_browsing_counts_by_cell(world)
	var result: Dictionary = {}

	for cell_key in counts_by_cell.keys():
		var species_entries: Dictionary = counts_by_cell[cell_key]
		var combined_factor := 1.0
		for species_name in species_entries.keys():
			combined_factor *= species_entries[species_name]["browsing_factor"]
		combined_factor = max(combined_factor, 0.0)

		result[cell_key] = {
			"species": species_entries,
			"combined_browsing_factor": combined_factor,
		}

	return result


func _collect_browsing_counts_by_cell(world: World) -> Dictionary:
	var raw_counts: Dictionary = {}  # {Vector2i: {species_name: int}}
	var rules_by_species: Dictionary = {}  # cache, evita ricaricare la stessa .tres per ogni gruppo

	for group in world.population_groups:
		if group.population <= 0 or group.territory == null:
			continue

		if not rules_by_species.has(group.species_name):
			rules_by_species[group.species_name] = AnimalCalculator.get_animal_rules(group.species_name)
		var rules: AnimalRules = rules_by_species[group.species_name]
		if rules == null or not rules.is_browsing_species:
			continue

		var population_by_cell := group.get_population_by_cell()
		for coords in group.territory.occupied_macrocells:
			var cell_population: int = int(population_by_cell.get(coords, 0))
			if cell_population <= 0:
				continue
			if not raw_counts.has(coords):
				raw_counts[coords] = {}
			# Somma tra gruppi diversi della STESSA specie che condividono la cella (es. dopo uno
			# split, vedi PopulationSplitService): density_ratio_species deve riflettere la
			# popolazione TOTALE della specie in quella cella, non un singolo gruppo isolato.
			raw_counts[coords][group.species_name] = (
				int(raw_counts[coords].get(group.species_name, 0)) + cell_population
			)

	var counts_by_cell: Dictionary = {}
	for coords in raw_counts.keys():
		counts_by_cell[coords] = {}
		for species_name in raw_counts[coords].keys():
			var rules: AnimalRules = rules_by_species[species_name]
			var count: int = raw_counts[coords][species_name]
			var density_ratio: float = float(count) / float(rules.max_density_per_cell)
			var browsing_factor: float = 1.0 - (MAX_BROWSING_EFFECT * density_ratio)
			counts_by_cell[coords][species_name] = {
				"count": count,
				"max_density_per_cell": rules.max_density_per_cell,
				"density_ratio": density_ratio,
				"browsing_factor": browsing_factor,
			}

	return counts_by_cell
