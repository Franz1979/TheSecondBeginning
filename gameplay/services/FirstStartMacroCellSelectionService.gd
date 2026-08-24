class_name FirstStartMacroCellSelectionService
extends RefCounted

# Sceglie SOLO la macrocella di partenza del player — non legge ne' scrive GameData
# (player_macro_cell_x/y) ne' GameSettings.selected_exclude_hostile_start/
# selected_exclude_predator_territories/selected_resource_richness_preference/
# selected_guarantee_animal_presence, quello e' responsabilita' del chiamante (GameScene, alla
# primissima apertura). Vedi World.gd/MacroCellData.gd/PopulationGroup.gd/Territory.gd per le
# strutture ispezionate.

# Numero di celle per fascia (povera/media/ricca) quando il pool di candidate e' abbastanza
# grande — "le dieci piu' povere/mediane/piu' ricche", non un terzo dell'intero pool: anche su
# una mappa enorme restano tre gruppi ristretti, non larghe porzioni della mappa. Sotto
# TIER_MIN_CANDIDATES_FOR_FIXED_SIZE candidate, _pick_cell_by_richness_tier ripiega su tre
# terzi proporzionali (vedi li') cosi' le tre fasce restano sempre disgiunte e non vuote.
const TIER_SAMPLE_SIZE := 10
const TIER_MIN_CANDIDATES_FOR_FIXED_SIZE := TIER_SAMPLE_SIZE * 3


# Criterio base (minimale, da migliorare in futuro): a caso tra le macrocelle che non sono
# corpi d'acqua. Stessa convenzione gia' stabilita nel resto del codebase (vedi
# TerritoryBuilderService): "questa macrocella E' acqua" == terrain_base == WATER, e basta —
# una cella di terra attraversata da un fiume (water_type == RIVER e/o river_shape != NONE,
# terrain_base resta PLAIN/HILL) NON viene esclusa, e' un candidato valido come qualunque
# altra cella di terra.
#
# exclude_hostile_zones/exclude_predator_territories/guarantee_animal_presence (opzioni
# "Escludi partenza in zone ostili"/"Escludi partenza vicino ai predatori"/"Presenza sicura
# animali" di NewGameOptionsMenu, vedi GameSettings/DifficultyCalculator per i moltiplicatori di
# difficolta' collegati): quando attivi, scartano ANCHE le celle "ostili" (vedi _is_hostile), e/o
# quelle occupate dal territorio (TUTTE le celle, non solo il centro della BFS — vedi
# _collect_predator_territory_cells) di un branco predatore gia' seminato, e/o quelle SENZA
# presenza erbivora reale (population>0, non solo territorio — vedi
# _collect_animal_present_cells), dai candidati primari. Con guarantee_animal_presence=false
# nessun filtro viene applicato su questo asse: gli animali possono comunque esserci per puro
# caso, semplicemente non e' garantito (confermato con l'utente). Se l'insieme dei filtri attivi
# non lascia candidati, la cascata di fallback sotto ripiega direttamente su "qualunque cella di
# terra" (ignora TUTTI i filtri insieme, non uno alla volta — semplificazione confermata con
# l'utente: il caso e' comunque raro/limite), poi su una cella qualunque — confermato con
# l'utente: meglio una partenza non ideale che nessuna partenza.
func select_starting_cell(
	world: World,
	exclude_hostile_zones: bool = false,
	exclude_predator_territories: bool = false,
	resource_richness_preference: String = "NORMAL",
	guarantee_animal_presence: bool = false
) -> Vector2i:
	var predator_cells := (
		_collect_predator_territory_cells(world) if exclude_predator_territories else {}
	)
	var animal_present_cells := (
		_collect_animal_present_cells(world) if guarantee_animal_presence else {}
	)

	var land_candidates: Array[Vector2i] = []
	var filtered_candidates: Array[Vector2i] = []
	for cell in world.cells:
		if cell.terrain_base == GameTypes.TerrainBase.WATER:
			continue
		var pos := Vector2i(cell.x, cell.y)
		land_candidates.append(pos)

		if exclude_hostile_zones and _is_hostile(cell):
			continue
		if exclude_predator_territories and predator_cells.has(pos):
			continue
		if guarantee_animal_presence and not animal_present_cells.has(pos):
			continue
		filtered_candidates.append(pos)

	var chosen: Vector2i
	var any_filter_active := exclude_hostile_zones or exclude_predator_territories or guarantee_animal_presence
	var candidates := filtered_candidates if any_filter_active else land_candidates
	if not candidates.is_empty():
		chosen = _pick_cell_by_richness_tier(world, candidates, resource_richness_preference)
		print(
			(
				"FirstStartMacroCellSelectionService: cella di partenza scelta (%d, %d) — "
				+ "exclude_hostile_zones=%s exclude_predator_territories=%s "
				+ "resource_richness_preference=%s guarantee_animal_presence=%s"
			) % [
				chosen.x, chosen.y, exclude_hostile_zones, exclude_predator_territories,
				resource_richness_preference, guarantee_animal_presence
			]
		)
		return chosen

	if any_filter_active and not land_candidates.is_empty():
		chosen = land_candidates[randi_range(0, land_candidates.size() - 1)]
		push_warning(
			"FirstStartMacroCellSelectionService: nessuna macrocella soddisfa i filtri attivi "
			+ "(zone ostili/territori predatori/presenza animali), fallback su una cella di terra "
			+ "qualunque: (%d, %d)" % [chosen.x, chosen.y]
		)
		return chosen

	var fallback_cell: MacroCellData = world.cells[randi_range(0, world.cells.size() - 1)]
	chosen = Vector2i(fallback_cell.x, fallback_cell.y)
	push_warning(
		"FirstStartMacroCellSelectionService: nessuna macrocella di terra trovata "
		+ "(mondo interamente acqua?), fallback su una cella d'acqua qualunque: (%d, %d)" % [chosen.x, chosen.y]
	)
	return chosen


# "Ostile" per l'esclusione opzionale (confermato con l'utente): montagna, deserto, palude,
# roccioso, o qualunque costa (anche BEACH — una cella costiera e' comunque a rischio, es.
# sea flood, non solo le coste scoscese). Non e' la stessa nozione di "acqua" usata sopra:
# una cella ostile resta terra a tutti gli effetti, solo scartata quando l'utente lo chiede.
func _is_hostile(cell: MacroCellData) -> bool:
	if cell.terrain_base == GameTypes.TerrainBase.MOUNTAIN:
		return true
	if cell.biome == GameTypes.Biome.DESERT or cell.biome == GameTypes.Biome.SWAMP or cell.biome == GameTypes.Biome.ROCKY:
		return true
	if cell.coast_type != GameTypes.CoastType.NONE:
		return true
	return false


# Tutte le celle occupate da un branco predatore gia' seminato (world.population_groups e'
# gia' popolato quando questo servizio viene chiamato: la creazione del mondo/la semina animali
# in WorldScene._populate_new_world avviene sempre prima che il player possa raggiungere
# GameScene). "Predatore" = stesso downcast polimorfico usato ovunque nel resto del codebase
# (PredationService, WorldInfoPanel._is_predator_species, ecc.): rules is PredatorRules, nessuna
# lista di nomi hardcoded. group.territory.occupied_macrocells e' l'INTERO territorio, non solo
# la cella seed della BFS — esattamente quanto richiesto.
func _collect_predator_territory_cells(world: World) -> Dictionary:
	var cells: Dictionary = {}
	for group in world.population_groups:
		if group.territory == null:
			continue
		if not (AnimalCalculator.get_animal_rules(group.species_name) is PredatorRules):
			continue
		for pos in group.territory.occupied_macrocells:
			cells[pos] = true
	return cells


# Tutte le celle con presenza REALE di almeno un individuo erbivoro (population>0 in QUELLA
# cella, via get_population_by_cell — non l'intero territorio come sopra: un territorio
# multi-cella puo' avere quote diverse per cella, alcune a zero, e "presenza animali" per il
# giocatore deve significare "ci sono davvero individui qui", non "questa cella fa parte di un
# territorio"). Predatori esclusi (stesso downcast di _collect_predator_territory_cells): un
# branco predatore non e' "presenza animali rassicurante" per il player, e' gia' gestito a parte
# dal toggle "escludi predatori".
func _collect_animal_present_cells(world: World) -> Dictionary:
	var cells: Dictionary = {}
	for group in world.population_groups:
		if group.territory == null or group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or rules is PredatorRules:
			continue

		var population_by_cell := group.get_population_by_cell()
		for coords in population_by_cell.keys():
			if int(population_by_cell[coords]) > 0:
				cells[coords] = true
	return cells


# Ordina "candidates" per ricchezza (CellRichnessCalculator.evaluate_richness_batch, piu' alto =
# piu' ricca — vedi li' per la formula, normalizzata per asse prima dei pesi 0.4/0.4/0.2) e tira
# a caso nella fascia richiesta ("RICH"/"NORMAL"/"POOR" — default NORMAL per preferenze
# sconosciute, stesso principio dei Dictionary.get(key, neutro) usati altrove).
#
# Shuffle PRIMA di ordinare per punteggio: senza, a parita' di punteggio (es. due celle
# ugualmente prive di risorse) le candidate a pari merito resterebbero nell'ordine di iterazione
# di world.cells — che e' spaziale (riga per riga) — facendo si' che una fascia finisca per
# coincidere sistematicamente con una porzione geografica della mappa invece che con un
# sottoinsieme neutro tra i pari merito. Mescolare prima rende quel tie-break innocuo, e non
# altera l'ordinamento quando i punteggi differiscono davvero.
#
# Le tre fasce sono TAGLI FISSI di TIER_SAMPLE_SIZE celle ciascuno (le piu' ricche, le mediane
# centrate, le piu' povere) — non terzi dell'intero pool: su una mappa con migliaia di candidate
# restano comunque tre gruppi ristretti. Sotto TIER_MIN_CANDIDATES_FOR_FIXED_SIZE candidate si
# ripiega su tre terzi proporzionali (tier_size = candidates.size() / 3, minimo 1) cosi' le tre
# fasce restano sempre disgiunte e non vuote anche su pool piccoli.
func _pick_cell_by_richness_tier(world: World, candidates: Array[Vector2i], preference: String) -> Vector2i:
	var richness_scores := CellRichnessCalculator.new().evaluate_richness_batch(world, candidates)

	var scored: Array = []
	for pos in candidates:
		scored.append({"pos": pos, "score": float(richness_scores.get(pos, 0.0))})

	scored.shuffle()
	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	var total := scored.size()
	var tier_size := TIER_SAMPLE_SIZE
	if total < TIER_MIN_CANDIDATES_FOR_FIXED_SIZE:
		tier_size = maxi(1, total / 3)

	var mid_start: int = (total - tier_size) / 2
	var tier_slice: Array
	match preference:
		"RICH":
			tier_slice = scored.slice(0, tier_size)
		"POOR":
			tier_slice = scored.slice(total - tier_size, total)
		_:
			tier_slice = scored.slice(mid_start, mid_start + tier_size)

	var picked: Dictionary = tier_slice[randi_range(0, tier_slice.size() - 1)]
	return picked["pos"]
