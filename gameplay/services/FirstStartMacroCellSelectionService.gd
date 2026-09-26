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
# exclude_hostile_zones/exclude_predator_territories/guarantee_animal_presence/
# guarantee_stone_presence (opzioni "Escludi partenza in zone ostili"/"Escludi partenza vicino ai
# predatori"/"Presenza sicura animali"/"Presenza sicura roccia" di NewGameOptionsMenu, vedi
# GameSettings/DifficultyCalculator per i moltiplicatori di difficolta' collegati): quando attivi,
# scartano ANCHE le celle "ostili" (vedi _is_hostile), e/o quelle occupate dal territorio (TUTTE le
# celle, non solo il centro della BFS — vedi _collect_predator_territory_cells) di un branco
# predatore gia' seminato, e/o quelle NON idonee alle prede piccole (habitat del coniglio, che
# coincide con quello della pernice — vedi _is_small_prey_habitat; sostituisce il vecchio criterio
# "almeno un erbivoro qualunque con quota > 0": la preda viene poi GARANTITA da GameScene con
# AnimalSeedingService.ensure_small_prey_at sulla cella scelta), e/o quelle SENZA roccia gia' seminata
# (MacroCellState.get_dedicated_space(ROCK) > 0 — vedi _collect_stone_present_cells; roccia e'
# generata a livello di macrocella da InitialResourceSetupService/ParametricResourceSetupService
# ben prima che questo servizio giri, quindi il dato e' gia' disponibile qui), dai candidati
# primari. Con un filtro spento nessun vincolo viene applicato su quell'asse: quel dato puo'
# comunque esserci per puro caso, semplicemente non e' garantito (confermato con l'utente per
# guarantee_animal_presence, stesso principio qui). Se l'insieme dei filtri attivi
# non lascia candidati, la cascata di fallback sotto ripiega direttamente su "qualunque cella di
# terra" (ignora TUTTI i filtri insieme, non uno alla volta — semplificazione confermata con
# l'utente: il caso e' comunque raro/limite), poi su una cella qualunque — confermato con
# l'utente: meglio una partenza non ideale che nessuna partenza.
func select_starting_cell(
	world: World,
	exclude_hostile_zones: bool = false,
	exclude_predator_territories: bool = false,
	resource_richness_preference: String = "NORMAL",
	guarantee_animal_presence: bool = false,
	guarantee_stone_presence: bool = false
) -> Vector2i:
	var predator_cells := (
		_collect_predator_territory_cells(world) if exclude_predator_territories else {}
	)
	var small_prey_rules: AnimalRules = (
		AnimalCalculator.get_animal_rules(AnimalSeedingService.SMALL_PREY_HABITAT_SPECIES) if guarantee_animal_presence else null
	)
	var stone_present_cells := (
		_collect_stone_present_cells(world) if guarantee_stone_presence else {}
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
		if guarantee_animal_presence and not _is_small_prey_habitat(small_prey_rules, cell):
			continue
		if guarantee_stone_presence and not stone_present_cells.has(pos):
			continue
		filtered_candidates.append(pos)

	var chosen: Vector2i
	var any_filter_active := (
		exclude_hostile_zones or exclude_predator_territories or guarantee_animal_presence or guarantee_stone_presence
	)
	var candidates := filtered_candidates if any_filter_active else land_candidates
	if not candidates.is_empty():
		chosen = _pick_cell_by_richness_tier(world, candidates, resource_richness_preference)
		print(
			(
				"FirstStartMacroCellSelectionService: cella di partenza scelta (%d, %d) — "
				+ "exclude_hostile_zones=%s exclude_predator_territories=%s "
				+ "resource_richness_preference=%s guarantee_animal_presence=%s "
				+ "guarantee_stone_presence=%s"
			) % [
				chosen.x, chosen.y, exclude_hostile_zones, exclude_predator_territories,
				resource_richness_preference, guarantee_animal_presence, guarantee_stone_presence
			]
		)
		return chosen

	if any_filter_active and not land_candidates.is_empty():
		chosen = land_candidates[randi_range(0, land_candidates.size() - 1)]
		push_warning(
			"FirstStartMacroCellSelectionService: nessuna macrocella soddisfa i filtri attivi "
			+ "(zone ostili/territori predatori/presenza animali/presenza roccia), fallback su una "
			+ "cella di terra qualunque: (%d, %d)" % [chosen.x, chosen.y]
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


# "Presenza sicura animali": cella idonea alle prede piccole — habitat del coniglio
# (AnimalRules.is_suitable_for su bioma e terreno), identico a quello della pernice, cosi' la preda
# che GameScene semina subito dopo sulla cella scelta (AnimalSeedingService.ensure_small_prey_at)
# ci puo' vivere. Nessun controllo sugli animali gia' presenti: la presenza non e' piu' un requisito
# della cella, e' garantita per costruzione dalla semina. rules null (specie coniglio non trovata):
# nessuna cella scartata su quest'asse, stesso trattamento permissivo di un lookup fallito altrove.
func _is_small_prey_habitat(rules: AnimalRules, cell: MacroCellData) -> bool:
	if rules == null:
		return true
	return rules.is_suitable_for(cell.biome, cell.terrain_base)


# Tutte le celle dove ROCK e' gia' stato seminato (2026-09-08, richiesta utente — "Presenza
# sicura roccia": la roccia e' una risorsa preziosa e oggi non c'e' nessun modo di sapere se una
# macrocella l'avra' prima di scoprirla). MacroCellState.get_dedicated_space(ROCK) > 0, non
# resource_quantity: dedicated_space e' il valore scritto direttamente da InitialResourceSetupService.
# populate_stone/ParametricResourceSetupService (vedi li') al momento della semina — resource_quantity
# ne e' solo la conversione derivata via densita', stessa fonte di verita' gia' usata da
# StonePositionService.generate_if_needed per contare quante posizioni generare. Nessuna posizione
# puntuale coinvolta qui (StonePositionService non ha ancora girato per la maggior parte delle
# macrocelle a questo punto, vedi la sua lazy-generation): un aggregato per macrocella basta,
# stesso identico livello di granularita' di _collect_predator_territory_cells sopra.
func _collect_stone_present_cells(world: World) -> Dictionary:
	var cells: Dictionary = {}
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue
		if state.get_dedicated_space(GameTypes.WorldObjectType.ROCK) > 0:
			cells[Vector2i(cell.x, cell.y)] = true
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
