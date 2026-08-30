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


# Classifica ogni PopulationGroup di world in LEVEL_2 (il suo Territory tocca almeno una delle
# coordinate in `live_cell_coords`) o LEVEL_1 (nessuna cella del territorio è viva). Territory non
# espone oggi un metodo di intersezione dedicato (solo get_cell_count/contains/get_primary_cell/
# get_centroid, vedi Territory.gd) — il controllo minimo qui sotto (_territory_intersects_live_
# cells) itera occupied_macrocells e testa live_cell_coords.has(coords), senza aggiungere nulla a
# Territory stesso (lettura pura dall'esterno, nessuna modifica a un file esistente).
#
# live_cell_coords è un Dictionary[Vector2i, bool] delle SINGOLE celle vive, non un Rect2i che ne
# faccia il bounding box — deliberato (fix 2026-08-30): con celle vive potenzialmente molto
# distanti tra loro (edifici lontani dal player, vedi GameScene._activate_all_building_cells), un
# bounding box tratterebbe come "a fuoco" anche tutto lo spazio vuoto in mezzo, promuovendo a
# torto popolazioni che non toccano nessuna cella viva reale.
#
# Puramente di lettura/calcolo: non tocca alcuno stato di PopulationGroup/Territory/World, non
# chiama né altera nessun checkpoint di WorldTimeService. Ritorna un Dictionary sia per il log
# leggibile (vedi print_classification_log sotto) sia per un futuro consumo programmatico
# (quando il Livello 1 diventerà un calcolo annuale reale):
#   "level_2_groups": Array[PopulationGroup]
#   "level_1_groups": Array[PopulationGroup]
#   "level_2_count_by_species": Dictionary[String, int]
#   "level_1_count_by_species": Dictionary[String, int]
func set_focus_region(world: World, live_cell_coords: Dictionary) -> Dictionary:
	var level_2_groups: Array = []
	var level_1_groups: Array = []
	var level_2_count_by_species: Dictionary = {}
	var level_1_count_by_species: Dictionary = {}

	for group in world.population_groups:
		if _territory_intersects_live_cells(group.territory, live_cell_coords):
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


static func _territory_intersects_live_cells(territory: Territory, live_cell_coords: Dictionary) -> bool:
	if territory == null:
		return false
	for coords in territory.occupied_macrocells:
		if live_cell_coords.has(coords):
			return true
	return false


# Registra UN SINGOLO gruppo appena creato (es. da uno split dentro TerritoryDynamicsService.
# process_daily_stagger, il percorso GIORNALIERO che _run_lod_focus_refresh_checkpoint non copre
# finché non arriva il prossimo checkpoint stagionale — vedi la discussione sul perché i nuovi
# gruppi da spalmamento finivano trattati come Livello 2 per tutta la stagione) dentro
# world.lod_focus_state, SENZA riclassificare tutto il mondo da zero (quello resta il compito di
# set_focus_region, deliberatamente più raro/costoso). No-op se nessun focus è attivo
# (world.lod_focus_state vuoto = vista mondo). Riusa la STESSA identica regola geografica di
# set_focus_region (_territory_intersects_live_cells) — mai una seconda definizione di cosa
# significhi "Livello 2", verificata per davvero (territorio del nuovo gruppo contro le celle vive
# reali), mai un default assunto solo perché il genitore era Livello 1 (un genitore al bordo di
# una cella viva potrebbe generare un figlio che ricade appena dentro).
static func register_new_group(world: World, group: PopulationGroup) -> void:
	if world.lod_focus_state.is_empty():
		return
	if _territory_intersects_live_cells(group.territory, world.lod_focus_live_cells):
		world.lod_focus_state["level_2_groups"].append(group)
		var counts: Dictionary = world.lod_focus_state["level_2_count_by_species"]
		counts[group.species_name] = int(counts.get(group.species_name, 0)) + 1
	else:
		world.lod_focus_state["level_1_groups"].append(group)
		var counts: Dictionary = world.lod_focus_state["level_1_count_by_species"]
		counts[group.species_name] = int(counts.get(group.species_name, 0)) + 1


# Log leggibile del risultato di set_focus_region, riusabile da ogni futuro punto di invocazione
# (oggi solo MacroCellScene._ready) senza duplicare il formato di stampa. Statica: non ha bisogno
# di stato dell'istanza, solo del Dictionary già calcolato.
static func print_classification_log(result: Dictionary) -> void:
	if not DebugLogging.SHOW_LOD_CLASSIFICATION_LOGS:
		return
	var level_2_groups: Array = result["level_2_groups"]
	var level_1_groups: Array = result["level_1_groups"]
	var total: int = level_2_groups.size() + level_1_groups.size()

	print("[LOD] Popolazioni totali: %d" % total)
	# "N" qui è un conteggio di GRUPPI (PopulationGroup), non di individui — un gruppo "rabbit: 1"
	# può comunque contenere decine di conigli (group.population), vedi il dettaglio per-gruppo
	# sotto. level_2_count_by_species è già una SOMMA per specie (set_focus_region incrementa lo
	# stesso contatore per ogni gruppo classificato LEVEL_2, mai un overwrite) — se compare più di
	# un gruppo della stessa specie a fuoco, il numero qui cresce di conseguenza, non resta fermo a
	# 1: NON è quindi possibile che questo conteggio nasconda gruppi "ripetuti ma non sommati". Se
	# vedi lo stesso blocco identico due volte di fila nel log, è perché print_classification_log è
	# stata richiamata due volte per due eventi distinti nello stesso frame (es. sia da _ready() sia
	# da un cambio di vicino attivo, vedi GameScene._refresh_lod_focus_region) — non un doppio conteggio.
	print("[LOD] LEVEL_2 (a fuoco, calcolo giornaliero invariato): %d gruppi" % level_2_groups.size())
	var level_2_by_species: Dictionary = result["level_2_count_by_species"]
	var level_2_species_names: Array = level_2_by_species.keys()
	level_2_species_names.sort()
	for species_name in level_2_species_names:
		print("  - %s: %d gruppi" % [species_name, level_2_by_species[species_name]])

	# Dettaglio per-gruppo (solo LEVEL_2, mai LEVEL_1: lì i gruppi sono migliaia, elencarli
	# singolarmente sommergerebbe il log) — INTERO territorio (tutte le occupied_macrocells), non
	# solo la cella primaria: un gruppo multi-cella (es. deer, min_territory_cells=3) può finire
	# LEVEL_2 perché una QUALSIASI delle sue celle tocca il set vivo (_territory_intersects_live_
	# cells, vedi sopra — non solo se la cella primaria coincide), quindi mostrare solo get_primary_
	# cell() qui potrebbe far sembrare "lontano" un gruppo che in realtà è a fuoco per via di
	# un'altra sua cella. Con l'intero elenco si vede sempre DAVVERO perché è stato classificato così.
	if not level_2_groups.is_empty():
		print("[LOD] Dettaglio gruppi LEVEL_2 (id specie: intero territorio, popolazione):")
		for group in level_2_groups:
			var cells: Array = []
			for coords in group.territory.occupied_macrocells:
				cells.append(str(coords))
			print("  - #%d %s: [%s], pop=%d" % [
				group.id, group.species_name, ", ".join(cells), group.population
			])

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
