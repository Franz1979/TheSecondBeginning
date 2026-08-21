class_name AnimalSeedingService
extends RefCounted

# Seminatore automatico delle popolazioni animali, parallelo al pannello di debug manuale in
# GameScene.gd (_on_debug_set_animal_pressed) — non lo sostituisce, il debug resta disponibile
# per test/casi puntuali. Chiamato SOLO quando GameSettings.selected_world_age_mode != "CLASSIC"
# (vedi GameScene._populate_new_world), mai per un mondo "classico".
#
# find_candidate_start_cells() e' la stessa identica logica di scansione a griglia con jitter
# gia' validata in tools/vegetation_equilibrium_test/SeedCandidateCount.gd — estratta qui come
# unica implementazione condivisa: quel file (diagnostico, non collegato al gioco) ora la
# richiama da qui invece di tenerne una copia propria.

const MAX_SEARCH_RADIUS := 3

const DENSITY_DIVISOR := {
	GameTypes.AnimalDensity.FEW: 20,
	GameTypes.AnimalDensity.MEDIUM: 10,
	GameTypes.AnimalDensity.MANY: 5,
}

# Divisore applicato a rules.min_territory_cells * rules.max_density_per_cell (la capacita'
# massima a territorio minimo) per ottenere la taglia BASE di ciascuna popolazione — STESSA
# formula per tutte le specie, predatori inclusi (verificato: 150 * 0.05 = 7.5 per wolf, in
# linea con la dimensione di branco attesa, nessuna eccezione necessaria).
const POPULATION_SIZE_DIVISOR := {
	GameTypes.PopulationSize.DENSE: 1.0,
	GameTypes.PopulationSize.NORMAL: 2.0,
	GameTypes.PopulationSize.SPARSE: 3.0,
}

const POPULATION_JITTER_RATIO := 0.10
const POPULATION_MIN_FLOOR := 4


func populate_animals(world: World, density: GameTypes.AnimalDensity, population_size: GameTypes.PopulationSize) -> void:
	var divisor: int = DENSITY_DIVISOR[density]

	for species_name in AnimalCalculator.list_species_names():
		var rules := AnimalCalculator.get_animal_rules(species_name)
		if rules == null:
			continue

		var candidates := find_candidate_start_cells(world, rules)
		if candidates.is_empty():
			print("[ANIMAL SEEDING] %s: nessuna cella candidata idonea, nessuna popolazione creata" % species_name)
			continue

		var target: int = maxi(1, int(round(float(candidates.size()) / float(divisor))))

		var chosen: Array[Vector2i] = candidates
		if target < candidates.size():
			chosen = candidates.duplicate()
			chosen.shuffle()
			chosen = chosen.slice(0, target)

		var created := 0
		var skipped_overlap := 0
		for coords in chosen:
			# Protezione a runtime aggiuntiva, tenuta anche se find_candidate_start_cells ora
			# garantisce distanza di griglia >= step (vedi sotto): un territorio BFS puo' comunque
			# assumere forme irregolari che in rari casi lo estendono oltre lo step teorico (mappa
			# non omogenea, acqua che devia la BFS) — riusa world.find_population_group, la stessa
			# funzione gia' usata dal flusso di debug manuale per rilevare un gruppo esistente
			# della stessa specie su una cella. Se la cella scelta e' gia' dentro il territorio di
			# un gruppo di QUESTA specie creato prima in questa stessa chiamata, la scartiamo
			# invece di lasciare che build_territory la includa comunque come start forzato
			# (comportamento suo, documentato e invariato — vedi TerritoryBuilderService).
			if world.find_population_group(species_name, coords) != null:
				skipped_overlap += 1
				continue
			_create_population(world, rules, species_name, coords, population_size)
			created += 1

		var overlap_note := ""
		if skipped_overlap > 0:
			overlap_note = " (%d scartate per sovrapposizione territorio)" % skipped_overlap
		print("[ANIMAL SEEDING] %s: %d candidati, %d popolazioni create%s" % [species_name, candidates.size(), created, overlap_note])


# Stesso identico pattern di creazione gia' usato dal debug manuale (GameScene.
# _on_debug_set_animal_pressed/_build_initial_territory): territorio a singola cella per specie
# con min_territory_cells<=1, altrimenti BFS di TerritoryBuilderService fino a min_territory_cells
# (mai max — il territorio parte al minimo, invariato rispetto al debug manuale). Eta' distribuita
# secondo rules.initial_age_ratio. Per i predatori, patrol_route calcolato subito dopo la
# creazione del territorio, come nel debug manuale — PredationService non tenta mai una caccia se
# patrol_route e' vuoto.
#
# Non serve verificare qui se species_name+coords esiste gia' un gruppo (a differenza del debug
# manuale, che lo fa per gestire click ripetuti sulla stessa cella): find_candidate_start_cells
# deduplica per coordinata all'interno della stessa specie, quindi due celle scelte per la stessa
# specie in questa stessa chiamata sono sempre distinte per costruzione.
func _create_population(
	world: World, rules: AnimalRules, species_name: String, coords: Vector2i, population_size: GameTypes.PopulationSize
) -> void:
	var territory: Territory
	if rules.min_territory_cells <= 1:
		territory = Territory.from_single_cell(coords)
	else:
		territory = TerritoryBuilderService.new().build_territory(world, coords, rules.min_territory_cells, species_name)

	var group := PopulationGroup.new(species_name, territory, world.allocate_population_group_id())
	world.population_groups.append(group)

	if rules is PredatorRules:
		PredatorPatrolService.new().recompute_route(group, rules as PredatorRules)

	var population: int = compute_population_target(rules, population_size)
	group.set_population(population)
	group.set_age_composition(population, rules.initial_age_ratio)


# capacity = rules.min_territory_cells * rules.max_density_per_cell (valore reale, non
# arrotondato) — STESSA formula per ogni specie, predatori inclusi (vedi nota su
# POPULATION_SIZE_DIVISOR). target = capacity / divisore del livello scelto. Variazione +/-10%
# bidirezionale applicata a `target` (non al target gia' arrotondato), poi arrotondata: se il
# risultato arrotondato coincide con l'arrotondamento di `target` senza jitter (variazione netta
# 0 dopo l'arrotondamento — tipico quando target e' piccolo, es. wolf), si applica comunque un
# disturbo minimo di +1 o -1 al posto del jitter "svanito". Floor assoluto a
# POPULATION_MIN_FLOOR (4) applicato PER ULTIMO, dopo jitter/disturbo — puo' quindi appiattire
# livelli diversi allo stesso valore finale quando target e' vicino o sotto il floor (vedi wolf
# su NORMAL/SPARSE nel report di verifica).
func compute_population_target(rules: AnimalRules, population_size: GameTypes.PopulationSize) -> int:
	var capacity: float = float(rules.min_territory_cells) * rules.max_density_per_cell
	var divisor: float = POPULATION_SIZE_DIVISOR[population_size]
	var target: float = capacity / divisor

	var base_rounded: int = int(round(target))
	var jitter_range: float = target * POPULATION_JITTER_RATIO
	var jittered: int = int(round(target + randf_range(-jitter_range, jitter_range)))

	if jittered == base_rounded:
		jittered = base_rounded + (1 if randf() < 0.5 else -1)

	return maxi(jittered, POPULATION_MIN_FLOOR)


# Griglia a passo step=ceil(sqrt(max_territory_cells)), offset iniziale di meta' passo dal bordo.
# Jitter SEMPRE NON-NEGATIVO (0..jitter incluso), applicato all'AVANZAMENTO (sia lungo la riga
# che da una riga alla successiva) invece che come offset indipendente attorno alla posizione di
# griglia pura di ciascun punto — distinzione cruciale: un offset indipendente per punto (il
# design precedente, +/-jitter) poteva ridurre la distanza REALE tra due punti consecutivi sotto
# `step` (es. punto i jitterato di +2, punto i+1 di -2: distanza effettiva = step-4), che e'
# esattamente la causa della sovrapposizione territoriale osservata tra due popolazioni di bezoar
# nella verifica precedente. Con l'avanzamento x += step + randi_range(0, jitter) (idem per y),
# ogni passo aggiunge SOLO in piu' rispetto a `step`, mai in meno — la distanza tra due punti di
# griglia consecutivi (stessa riga o riga-su-riga) e' quindi garantita sempre >= step per
# costruzione (vedi dimostrazione nel report). Il recupero a raggio crescente (anelli di
# Chebyshev, fino a MAX_SEARCH_RADIUS) quando il punto cade su una cella non idonea puo' comunque
# spostare la cella EFFETTIVAMENTE scelta di un po' rispetto al punto di griglia — per questo il
# controllo a runtime in populate_animals resta attivo come rete di sicurezza aggiuntiva.
# Deduplicata per coordinata (Dictionary come set) — vedi nota storica in SeedCandidateCount.gd.
func find_candidate_start_cells(world: World, rules: AnimalRules) -> Array[Vector2i]:
	var max_cells: int = rules.max_territory_cells
	var step: int = maxi(ceili(sqrt(float(max_cells))), 1)
	var jitter: int = mini(2, step / 2)

	var seen: Dictionary = {}

	var y := float(step) / 2.0
	while y < World.HEIGHT:
		var x := float(step) / 2.0
		while x < World.WIDTH:
			var point := Vector2i(int(round(x)), int(round(y)))

			var found = _find_suitable_near(world, rules, point)
			if found != null:
				seen[found] = true

			x += step + randi_range(0, jitter)

		y += step + randi_range(0, jitter)

	var candidates: Array[Vector2i] = []
	for coords in seen.keys():
		candidates.append(coords)
	return candidates


func _find_suitable_near(world: World, rules: AnimalRules, center: Vector2i) -> Variant:
	if _is_suitable_cell(world, rules, center):
		return center

	for radius in range(1, MAX_SEARCH_RADIUS + 1):
		var ring := _ring_offsets(radius)
		ring.shuffle()
		for offset in ring:
			var candidate := center + offset
			if _is_suitable_cell(world, rules, candidate):
				return candidate

	return null


func _is_suitable_cell(world: World, rules: AnimalRules, coords: Vector2i) -> bool:
	var cell := world.get_cell_at(coords.x, coords.y)
	if cell == null:
		return false
	if cell.terrain_base == GameTypes.TerrainBase.WATER:
		return false
	return rules.is_suitable_for(cell.biome, cell.terrain_base)


func _ring_offsets(radius: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) == radius:
				offsets.append(Vector2i(dx, dy))
	return offsets
