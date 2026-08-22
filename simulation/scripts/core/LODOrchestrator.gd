class_name LODOrchestrator
extends RefCounted

# Parte A del meccanismo di LOD a due livelli (vedi note di progetto): SOLO classificazione,
# nessun effetto sulla simulazione. Livello 2 = popolazioni il cui territorio interseca la
# "zona a fuoco" (oggi: la macrocella aperta in MacroCellScene) — continuano a girare a cadenza
# giornaliera esattamente come oggi, nessun cambiamento di comportamento. Livello 1 = tutte le
# altre — il calcolo annuale semplificato che le riguarderà è un lavoro futuro separato, non
# ancora costruito: questa classe oggi si limita a CONTARLE, non le tratta diversamente in alcun
# modo. Nessun percorso reale del gioco chiama ancora set_focus_region — è invocato solo dal
# punto di debug in MacroCellScene._ready (vedi lì), per validare la classificazione e misurare
# il beneficio teorico prima di costruire il calcolo annuale vero.
#
# Stateless (RefCounted, .new() per uso), stesso pattern di ogni altro "*Service" in
# scripts/core/ — nessuna sottocartella dedicata: la struttura esistente è piatta, non ci sono
# precedenti di raggruppamento per categoria sotto scripts/core/.

enum Level { LEVEL_1, LEVEL_2 }


# Classifica ogni PopulationGroup di world in LEVEL_2 (il suo Territory interseca `region`,
# qualunque cella del territorio ricade dentro il rettangolo) o LEVEL_1 (nessuna cella dentro).
# Territory non espone oggi un metodo di intersezione dedicato (solo get_cell_count/contains/
# get_primary_cell/get_centroid, vedi Territory.gd) — il controllo minimo qui sotto
# (_territory_intersects_region) itera occupied_macrocells e testa region.has_point(coords),
# senza aggiungere nulla a Territory stesso (lettura pura dall'esterno, nessuna modifica a un
# file esistente).
#
# Puramente di lettura/calcolo: non tocca alcuno stato di PopulationGroup/Territory/World, non
# chiama né altera nessun checkpoint di WorldTimeService. Ritorna un Dictionary sia per il log
# leggibile (vedi print_classification_log sotto) sia per un futuro consumo programmatico
# (quando il Livello 1 diventerà un calcolo annuale reale):
#   "level_2_groups": Array[PopulationGroup]
#   "level_1_groups": Array[PopulationGroup]
#   "level_2_count_by_species": Dictionary[String, int]
#   "level_1_count_by_species": Dictionary[String, int]
func set_focus_region(world: World, region: Rect2i) -> Dictionary:
	var level_2_groups: Array = []
	var level_1_groups: Array = []
	var level_2_count_by_species: Dictionary = {}
	var level_1_count_by_species: Dictionary = {}

	for group in world.population_groups:
		if _territory_intersects_region(group.territory, region):
			level_2_groups.append(group)
			level_2_count_by_species[group.species_name] = int(level_2_count_by_species.get(group.species_name, 0)) + 1
		else:
			level_1_groups.append(group)
			level_1_count_by_species[group.species_name] = int(level_1_count_by_species.get(group.species_name, 0)) + 1

	return {
		"level_2_groups": level_2_groups,
		"level_1_groups": level_1_groups,
		"level_2_count_by_species": level_2_count_by_species,
		"level_1_count_by_species": level_1_count_by_species,
	}


func _territory_intersects_region(territory: Territory, region: Rect2i) -> bool:
	if territory == null:
		return false
	for coords in territory.occupied_macrocells:
		if region.has_point(coords):
			return true
	return false


# Log leggibile del risultato di set_focus_region, riusabile da ogni futuro punto di invocazione
# (oggi solo MacroCellScene._ready) senza duplicare il formato di stampa. Statica: non ha bisogno
# di stato dell'istanza, solo del Dictionary già calcolato.
static func print_classification_log(result: Dictionary) -> void:
	var level_2_groups: Array = result["level_2_groups"]
	var level_1_groups: Array = result["level_1_groups"]
	var total: int = level_2_groups.size() + level_1_groups.size()

	print("[LOD] Popolazioni totali: %d" % total)
	print("[LOD] LEVEL_2 (a fuoco, calcolo giornaliero invariato): %d" % level_2_groups.size())
	var level_2_by_species: Dictionary = result["level_2_count_by_species"]
	var level_2_species_names: Array = level_2_by_species.keys()
	level_2_species_names.sort()
	for species_name in level_2_species_names:
		print("  - %s: %d" % [species_name, level_2_by_species[species_name]])

	print("[LOD] LEVEL_1 (fuori fuoco, calcolo annuale futuro — oggi invariato): %d" % level_1_groups.size())
	var level_1_by_species: Dictionary = result["level_1_count_by_species"]
	var level_1_species_names: Array = level_1_by_species.keys()
	level_1_species_names.sort()
	for species_name in level_1_species_names:
		print("  - %s: %d" % [species_name, level_1_by_species[species_name]])

	# Nota informativa (solo quando pertinente, per non appesantire il log nel caso comune senza
	# predatori fuori fuoco): la classificazione qui sopra è puramente geografica, identica per
	# ogni specie — nessuna eccezione per i predatori (vedi set_focus_region). Ma un predatore
	# elencato in LEVEL_1 continua comunque a essere processato ogni giorno da
	# PredationService.apply_daily_predation, che non consulta mai World.lod_focus_state — la
	# predazione non è filtrata dal LOD per decisione presa nel profiling (branchi troppo pochi/
	# economici da giustificare un'aggregazione). Solo un promemoria di lettura: nessuna delle due
	# logiche cambia comportamento.
	var has_predator_in_level_1 := false
	for group in level_1_groups:
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules is PredatorRules:
			has_predator_in_level_1 = true
			break
	if has_predator_in_level_1:
		print(
			"[LOD] Nota: i predatori elencati sopra in LEVEL_1 restano comunque processati "
			+ "giornalmente da PredationService indipendentemente dal livello mostrato "
			+ "(la predazione non è filtrata dal LOD)."
		)
