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
# DENSE a 1.1 (non 1.0): con divisore esattamente 1.0 il target di partenza coincideva con il
# 100% della capacita' di densita' per cella, e il jitter +/-10% sotto (POPULATION_JITTER_RATIO)
# spingeva quindi circa META' delle popolazioni SOPRA la propria capacita' fin dalla nascita —
# scatenando needs_expansion_density al primissimo checkpoint stagionale per centinaia di gruppi
# in un colpo solo (osservato: ~860 split su rabbit/partridge al giorno 91 di una partita nuova
# con Dense+Many, quasi tutti per densita', vedi TerritoryDynamicsService SPLIT SUMMARY). A 1.1,
# anche nel caso peggiore di jitter (+10%) il target resta sotto il 100% (1.0/1.1 * 1.10 ~= 0.96),
# eliminando la cascata immediata pur restando nettamente piu' pieno di NORMAL.
const POPULATION_SIZE_DIVISOR := {
	GameTypes.PopulationSize.DENSE: 1.1,
	GameTypes.PopulationSize.NORMAL: 2.0,
	GameTypes.PopulationSize.SPARSE: 3.0,
}

const POPULATION_JITTER_RATIO := 0.10
const POPULATION_MIN_FLOOR := 4


func populate_animals(world: World, density: GameTypes.AnimalDensity, population_size: GameTypes.PopulationSize) -> void:
	var divisor: int = DENSITY_DIVISOR[density]

	# Due passate esplicite (erbivori prima, predatori dopo) invece di affidarsi all'ordine
	# alfabetico di list_species_names(): il punteggio di disponibilita' prede sotto (vedi
	# _select_predator_start_cells) assume che TUTTE le popolazioni erbivore esistano gia' quando
	# un predatore viene seminato — vero oggi solo perche' "wolf" ordina alfabeticamente dopo le
	# 8 specie erbivore esistenti, non per garanzia strutturale (una futura specie come
	# "cave_hyena" ordinerebbe PRIMA di "deer"/"mouflon"/"rabbit"/"tarpan"/"wild_donkey",
	# rompendo l'assunzione in silenzio).
	var ordered_species: Array[String] = []
	var predator_species: Array[String] = []
	for species_name in AnimalCalculator.list_species_names():
		if AnimalCalculator.get_animal_rules(species_name) is PredatorRules:
			predator_species.append(species_name)
		else:
			ordered_species.append(species_name)
	ordered_species.append_array(predator_species)

	for species_name in ordered_species:
		var rules := AnimalCalculator.get_animal_rules(species_name)
		if rules == null:
			continue

		var candidates := find_candidate_start_cells(world, rules)
		if candidates.is_empty():
			print("[ANIMAL SEEDING] %s: nessuna cella candidata idonea, nessuna popolazione creata" % species_name)
			continue

		var target: int = maxi(1, int(round(float(candidates.size()) / float(divisor))))

		var chosen: Array[Vector2i] = candidates
		var predator_scores: Dictionary = {}
		if rules is PredatorRules:
			# Ranking deterministico per disponibilita' prede (no soglia, no estrazione pesata —
			# vedi _select_predator_start_cells): sostituisce l'estrazione casuale uniforme usata
			# per tutte le altre specie sotto.
			chosen = _select_predator_start_cells(world, rules as PredatorRules, candidates, target, predator_scores)
		elif target < candidates.size():
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

		if rules is PredatorRules and not chosen.is_empty():
			var min_score: float = INF
			var max_score: float = -INF
			for coords in chosen:
				var score: float = predator_scores.get(coords, 0.0)
				min_score = minf(min_score, score)
				max_score = maxf(max_score, score)
			print("[ANIMAL SEEDING] %s: %d candidati, %d popolazioni create%s, punteggio prede tra le celle scelte [min=%.1f, max=%.1f]" % [
				species_name, candidates.size(), created, overlap_note, min_score, max_score
			])
		else:
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


# Ranking deterministico delle candidate SOLO per specie predatrici (rules is PredatorRules),
# generico per qualunque predatore futuro (nessun riferimento a "wolf": legge solo
# PredatorRules.prey_compatibility e AnimalRules.prey_calories) — sostituisce l'estrazione
# casuale uniforme usata per tutte le altre specie. Nessuna soglia minima e nessuna estrazione
# pesata: una cella a punteggio 0 (nessuna preda compatibile entro prey_radius) resta comunque
# eleggibile se il target lo richiede, stesso principio "meglio una popolazione a rischio che
# nessuna" gia' implicito nel comportamento esistente quando le candidate erbivore scarseggiano.
#
# prey_radius = ceil(sqrt(min_territory_cells)) — deriva dal territorio MINIMO (dimensione reale
# con cui il branco nasce, vedi _create_population), non da max_territory_cells (che resta usato
# solo per lo step di spaziatura griglia in find_candidate_start_cells sopra, scopo diverso: li'
# serve a distanziare le candidate tra loro, qui a delimitare "cosa conta come raggiungibile" per
# un branco appena nato). Peso binario, nessun decadimento graduale con la distanza: una preda
# entro prey_radius dal candidato conta per intero, oltre non conta affatto.
#
# out_scores: popolato per OGNI candidata (non solo le scelte), cosi' il chiamante puo' loggare
# min/max tra le celle EFFETTIVAMENTE scelte senza ricalcolare nulla.
func _select_predator_start_cells(
	world: World, rules: PredatorRules, candidates: Array[Vector2i], target: int, out_scores: Dictionary
) -> Array[Vector2i]:
	var prey_radius: int = ceili(sqrt(float(rules.min_territory_cells)))

	# Snapshot dei gruppi preda compatibili una sola volta (indipendente dalla cella candidata):
	# peso di specie = popolazione del gruppo × calorie-preda-adulta della sua specie ×
	# coefficiente di facilita' di cattura del predatore. group.territory.get_centroid() (funzione
	# gia' esistente e generica) da' il punto di riferimento del gruppo per la distanza.
	var prey_groups: Array[Dictionary] = []
	for group in world.population_groups:
		if group.population <= 0 or group.territory == null:
			continue
		var compatibility: float = float(rules.prey_compatibility.get(group.species_name, 0.0))
		if compatibility <= 0.0:
			continue
		var prey_rules := AnimalCalculator.get_animal_rules(group.species_name)
		if prey_rules == null:
			continue
		prey_groups.append({
			"centroid": group.territory.get_centroid(),
			"weight": float(group.population) * prey_rules.prey_calories * compatibility,
		})

	for coords in candidates:
		var score := 0.0
		for prey in prey_groups:
			if _manhattan_distance(coords, prey["centroid"]) <= prey_radius:
				score += float(prey["weight"])
		out_scores[coords] = score

	var ranked := candidates.duplicate()
	ranked.sort_custom(func(a, b): return out_scores[a] > out_scores[b])

	# Log diagnostico di TUTTE le candidate esaminate (non solo quelle scelte), per poter
	# verificare a occhio che il punteggio vari in modo sensato tra celle vicine/lontane dalle
	# prede prima di fidarsi del solo min/max tra le scelte (che con target piccolo puo'
	# banalmente coincidere se viene scelta una sola cella).
	print("[ANIMAL SEEDING - PREDATOR SCORES] %s: prey_radius=%d, %d candidati totali, target=%d" % [
		rules.species_name, prey_radius, ranked.size(), target
	])
	for i in range(ranked.size()):
		var coords: Vector2i = ranked[i]
		var marker := "SCELTA" if i < target else "scartata"
		print("  #%02d (%d,%d) punteggio=%.1f [%s]" % [i + 1, coords.x, coords.y, out_scores[coords], marker])

	if target < ranked.size():
		return ranked.slice(0, target)
	return ranked


func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
