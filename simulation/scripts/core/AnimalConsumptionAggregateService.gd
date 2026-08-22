class_name AnimalConsumptionAggregateService
extends RefCounted

# Consumo aggregato stagionale (Parte B del LOD) SOLO per popolazioni Livello 1 non predatrici —
# sostituisce, per queste sole popolazioni, i ~90 decrementi giornalieri di
# AnimalConsumptionService (invariato, mai toccato: resta la via per Livello 2/debug/vista mondo)
# con un'unica operazione a inizio di ogni stagione. Chiamato da
# WorldTimeService._run_animal_consumption_aggregate_checkpoint, no-op se World.lod_focus_state è
# vuoto (nessun chiamante passa un elenco vuoto in quel caso — il guard vive nel chiamante).
#
# Formula (design approvato in sessione precedente):
#   1. Raggruppa le popolazioni Livello 1 per cella (una popolazione multi-cella contribuisce a
#      più celle, pesata per la propria quota di popolazione in ciascuna — stessa attribuzione
#      già usata da AnimalConsumptionService per il consumo giornaliero).
#   2. need(g,C) = total_daily_requirement(g) × cell_share(g,C) × season_days — stessa formula
#      age-weighted già usata da AnimalConsumptionService._get_total_daily_requirement,
#      duplicata qui deliberatamente (stesso pattern già presente in
#      AnimalBirthMitigationService._get_seasonal_requirement, non un'eccezione).
#   3. population_share(g,C) = need(g,C) / Σ_h need(h,C) — ripartizione proporzionale tra le
#      popolazioni che condividono la cella: nessun pattern esistente da riusare per questo asse
#      (verificato: la contesa cross-specie di oggi si risolve solo per ordine di iterazione),
#      quindi nuovo, ma minimo.
#   4. Ripartizione per fonte: STESSA formula già in
#      AnimalConsumptionService._consume_requirement_in_cell (peso = disponibilità × compatibilità,
#      quota = fabbisogno × peso/somma_pesi, tetto min(quota, peso)) — l'unica differenza è che la
#      disponibilità di ciascuna fonte viene pre-scalata per population_share(g,C) prima di entrare
#      nella stessa formula, cosicché la somma di quanto ciascuna popolazione può prelevare da una
#      fonte condivisa non superi mai la disponibilità totale della cella.
#   5. Applicazione: decremento diretto (non la logica di accumulo frazionario <1 microcella di
#      _consume_forage, non necessaria per importi stagionali quasi sempre >1 microcella) su
#      dedicated_space(GRASS)/secondary_resource_stock — stessi campi letti/scritti dal consumo
#      giornaliero, mai un dato riassuntivo separato (così AnimalBirthMitigationService, che legge
#      questi stessi campi, continua a funzionare invariato per Livello 1 esattamente come per
#      Livello 2).

const FORAGE_SOURCE_NAME := "forage"


# Punto di ingresso. `level_1_groups` è l'elenco già filtrato da World.lod_focus_state
# ["level_1_groups"] — qui si filtrano ulteriormente i predatori (restano sempre giornalieri,
# indipendenti dal livello, per la decisione presa nel profiling) e i gruppi senza territorio/
# popolazione. `season` è la stagione APPENA CONCLUSA (il chiamante passa
# SeasonCalculator.get_previous_season(...) della stagione che sta iniziando) — stessa convenzione
# già usata da WorldTimeService._run_secondary_resource_stock_checkpoint per lo stesso motivo:
# season_days e disponibilità calorica si riferiscono a cosa la vegetazione ha effettivamente
# offerto durante la stagione trascorsa, non a quella che sta per iniziare.
#
# Ritorna Dictionary[int group_id -> float seasonal_ratio] — SOLO per log/debug in questo passo,
# nessun consumatore reale ancora (vedi nota di scope): non persistito su PopulationGroup/save.
func apply_seasonal_consumption(world: World, level_1_groups: Array, season: GameTypes.Season) -> Dictionary:
	var season_days: int = SeasonCalculator.SEASON_LENGTHS[season]

	var herbivore_groups: Array = []
	for group in level_1_groups:
		if group.population <= 0 or group.territory == null:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or rules is PredatorRules:
			continue
		herbivore_groups.append({"group": group, "rules": rules})

	if herbivore_groups.is_empty():
		return {}

	# Passo 1: raggruppamento per cella. Ogni entry: {"group","rules","need"} — need già scalato
	# per season_days/cell_share, pronto per il passo 3 (ripartizione proporzionale).
	var cell_map: Dictionary = {} # Vector2i -> Array[Dictionary]
	var total_need_by_group: Dictionary = {} # group.id -> float, accumulato su tutte le celle del suo territorio

	for entry in herbivore_groups:
		var group: PopulationGroup = entry["group"]
		var rules: AnimalRules = entry["rules"]
		var total_daily_requirement := _get_total_daily_requirement(group, rules)
		if total_daily_requirement <= 0.0:
			continue

		var population_by_cell := group.get_population_by_cell()
		for coords in group.territory.occupied_macrocells:
			var cell_population: int = int(population_by_cell.get(coords, 0))
			if cell_population <= 0:
				continue
			var cell_share: float = float(cell_population) / float(group.population)
			var need: float = total_daily_requirement * cell_share * float(season_days)
			if need <= 0.0:
				continue

			if not cell_map.has(coords):
				cell_map[coords] = []
			cell_map[coords].append({"group": group, "rules": rules, "need": need})
			total_need_by_group[group.id] = float(total_need_by_group.get(group.id, 0.0)) + need

	var consumed_by_group: Dictionary = {} # group.id -> float, accumulato su tutte le celle

	# Passo 2: per ogni cella, ripartizione proporzionale (passo 3 del design) + consumo per fonte
	# (passo 4) — una cella alla volta, nessuna dipendenza dall'ordine tra celle diverse.
	for coords in cell_map.keys():
		var entries: Array = cell_map[coords]
		var total_need_in_cell := 0.0
		for entry in entries:
			total_need_in_cell += float(entry["need"])
		if total_need_in_cell <= 0.0:
			continue

		var cell := world.get_cell_at(coords.x, coords.y)
		var state := world.get_cell_state_at(coords.x, coords.y)
		if cell == null or state == null:
			continue

		for entry in entries:
			var group: PopulationGroup = entry["group"]
			var rules: AnimalRules = entry["rules"]
			var need: float = entry["need"]
			var population_share: float = need / total_need_in_cell

			var consumed := _consume_in_cell(cell, state, rules, need, population_share, season)
			consumed_by_group[group.id] = float(consumed_by_group.get(group.id, 0.0)) + consumed

	# Passo 5 (design punto 2/f): ratio stagionale per gruppo, solo per log — nessuna persistenza.
	var seasonal_ratios: Dictionary = {}
	for entry in herbivore_groups:
		var group: PopulationGroup = entry["group"]
		var need_total: float = float(total_need_by_group.get(group.id, 0.0))
		var consumed_total: float = float(consumed_by_group.get(group.id, 0.0))
		var ratio: float = 1.0 if need_total <= 0.0 else consumed_total / need_total
		seasonal_ratios[group.id] = ratio

		if DebugLogging.ENABLED:
			print(
				"[ANIMAL CONSUMPTION AGGREGATE] #%d %s stagione=%s pop=%d fabbisogno=%.1f consumato=%.1f ratio=%.3f" % [
					group.id, group.species_name, GameTypes.Season.keys()[season],
					group.population, need_total, consumed_total, ratio
				]
			)

	return seasonal_ratios


# Stessa formula age-weighted di AnimalConsumptionService._get_total_daily_requirement,
# duplicata qui deliberatamente (vedi nota in cima al file) — nessuna specie Livello 1 oggi è
# priva di track_age_bands, ma il ramo flat resta comunque corretto se capitasse.
func _get_total_daily_requirement(group: PopulationGroup, rules: AnimalRules) -> float:
	if not rules.track_age_bands:
		return float(group.population) * rules.daily_caloric_requirement

	var young := group.get_age_count(GameTypes.AgeBand.YOUNG)
	var adult := group.get_age_count(GameTypes.AgeBand.ADULT)
	var old := group.get_age_count(GameTypes.AgeBand.OLD)
	var weighted_count: float = (
		float(young) * rules.caloric_multiplier_by_age[GameTypes.AgeBand.YOUNG]
		+ float(adult) * rules.caloric_multiplier_by_age[GameTypes.AgeBand.ADULT]
		+ float(old) * rules.caloric_multiplier_by_age[GameTypes.AgeBand.OLD]
	)
	return weighted_count * rules.daily_caloric_requirement


# Stessa formula di ripartizione per fonte di AnimalConsumptionService._consume_requirement_in_cell
# (peso = disponibilità × compatibilità, quota = fabbisogno × peso/somma_pesi, tetto
# min(quota, peso)) — l'unica differenza è che la disponibilità di ciascuna fonte è pre-scalata per
# `population_share` PRIMA di entrare nella formula, cosicché il tetto per questa popolazione non
# superi mai la sua quota proporzionale della disponibilità condivisa della cella.
func _consume_in_cell(
	cell: MacroCellData, state: MacroCellState, rules: AnimalRules,
	need: float, population_share: float, season: GameTypes.Season
) -> float:
	var weighted_sources: Array[Dictionary] = []
	var weight_sum := 0.0

	for source_name in rules.diet_compatibility.keys():
		var compatibility := float(rules.diet_compatibility[source_name])
		if compatibility <= 0.0:
			continue

		var source_rules := CaloricCalculator.get_caloric_source_rules(source_name)
		if source_rules == null or source_rules.calories_per_unit <= 0.0:
			continue

		var raw_available_calories: float
		if source_name == FORAGE_SOURCE_NAME:
			raw_available_calories = CaloricCalculator.get_forage_available_calories(cell, state, season)
		else:
			raw_available_calories = CaloricCalculator.get_secondary_resource_stock_calories(state, source_name)

		var scaled_available_calories: float = raw_available_calories * population_share
		var weight := scaled_available_calories * compatibility
		if weight <= 0.0:
			continue

		weighted_sources.append({
			"name": source_name,
			"weight": weight,
			"rules": source_rules,
		})
		weight_sum += weight

	var total_consumed_calories := 0.0
	if weight_sum > 0.0:
		for source in weighted_sources:
			var source_name: String = source["name"]
			var source_weight: float = source["weight"]
			var source_rules: CaloricSourceRules = source["rules"]

			var share: float = need * (source_weight / weight_sum)
			var consumed_calories: float = min(share, source_weight)
			var units_consumed: float = consumed_calories / source_rules.calories_per_unit

			if source_name == FORAGE_SOURCE_NAME:
				_consume_forage_aggregate(cell, state, units_consumed)
			else:
				var before := state.get_secondary_resource_stock(source_name)
				state.set_secondary_resource_stock(source_name, before - units_consumed)

			total_consumed_calories += consumed_calories

	return total_consumed_calories


# Decremento diretto di dedicated_space(GRASS) per una quantità stagionale (quasi sempre >1
# microcella) — a differenza di AnimalConsumptionService._consume_forage (pensata per incrementi
# giornalieri <1 microcella accumulati in pending_grass_space_debt), qui si arrotonda subito
# l'importo pieno. Il debito pregresso (eventuale residuo lasciato da un consumo giornaliero
# Livello 2 sulla stessa cella, o da una stagione aggregata precedente) viene comunque sommato
# PRIMA di arrotondare — mai scartato — e il resto frazionario dopo l'arrotondamento confluisce di
# nuovo in pending_grass_space_debt, stesso campo, per coerenza con qualunque consumo futuro
# (giornaliero o aggregato) sulla stessa cella.
func _consume_forage_aggregate(cell: MacroCellData, state: MacroCellState, units_consumed: float) -> void:
	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.GRASS, cell.terrain_base, cell.biome, cell.coast_type
	)
	if max_density <= 0.0:
		return

	var combined_debt: float = state.get_pending_grass_space_debt() + (units_consumed / max_density)
	var space_to_remove: int = int(round(combined_debt))
	if space_to_remove <= 0:
		state.set_pending_grass_space_debt(combined_debt)
		return

	var current_space := state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
	var actually_removed: int = min(space_to_remove, current_space)
	var new_space := current_space - actually_removed
	state.set_dedicated_space(GameTypes.WorldObjectType.GRASS, new_space)
	state.set_resource_quantity(
		GameTypes.WorldObjectType.GRASS, int(round(new_space * max_density))
	)
	state.set_pending_grass_space_debt(combined_debt - actually_removed)
