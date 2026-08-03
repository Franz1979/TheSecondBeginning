class_name AnimalBirthMitigationService
extends RefCounted

const FORAGE_SOURCE_NAME := "forage"

# Approssimazione uniforme della durata di una stagione (91-92 giorni reali, vedi
# SeasonCalculator.SEASON_LENGTHS): qui la precisione non serve.
const APPROX_SEASON_DURATION_DAYS := 100

const RATIO_HIGH_THRESHOLD := 0.8  # sopra: nessuna penalità, moltiplicatore = 1.0
const RATIO_LOW_THRESHOLD := 0.3   # sotto: moltiplicatore ridotto al floor
const MULTIPLIER_FLOOR := 0.05     # "quasi zero", mai natalità del tutto azzerata da un solo anno scarso


# Ratio calorico del territorio ATTUALE del gruppo: stock disponibile (snapshot, non una media —
# vedi _get_available_stock) diviso il fabbisogno stagionale age-weighted (vedi
# _get_seasonal_requirement). Formula invariata da quando viveva dentro compute_mitigation (ora
# rimosso): calcolata esattamente all'inizio di birth_season (stesso giorno reale, stato reale —
# nessuna proiezione da un'altra stagione). Pubblica e riusata da due chiamanti che devono
# condividere la STESSA definizione di scarsità — TerritoryDynamicsService (Step 8, che la
# ricalcola due volte: prima e dopo un'eventuale espansione/contrazione annuale del territorio,
# nello stesso checkpoint di inizio birth_season) e apply_mitigation_multiplier sotto (che la
# riceve già calcolata sul territorio DEFINITIVO di quest'anno, non la ricalcola mai da capo).
# Ritorna anche stock/fabbisogno grezzi (non solo il ratio) così il chiamante può loggarli senza
# doverli ricalcolare una seconda volta.
func compute_caloric_ratio(world: World, group: PopulationGroup, rules: AnimalRules, season: GameTypes.Season) -> Dictionary:
	var available_stock := _get_available_stock(world, group, rules, season)
	var seasonal_requirement := _get_seasonal_requirement(group, rules)
	var ratio: float = 0.0
	if seasonal_requirement > 0.0:
		ratio = available_stock / seasonal_requirement
	return {"stock": available_stock, "requirement": seasonal_requirement, "ratio": ratio}


# Mitigazione della natalità legata alla disponibilità calorica del territorio: si SOMMA a
# fertility_multiplier_by_age/base_birth_rate già esistenti (vedi AnimalBirthService), non li
# sostituisce. raw_ratio è già stato calcolato dal chiamante (TerritoryDynamicsService) sul
# territorio DEFINITIVO di quest'anno — dopo l'eventuale espansione/contrazione dello stesso
# checkpoint di inizio birth_season, mai su un territorio che sta per essere modificato. Il
# moltiplicatore risultante resta memorizzato sul gruppo fino al checkpoint di nascita già
# esistente, a fine birth_season. Ritorna il moltiplicatore così il chiamante (TerritoryDynamicsService)
# può includerlo nel proprio log invece di richiederlo di nuovo al gruppo.
#
# log_enabled di default true (specie a 1 sola cella, es. rabbit: questo è l'unico log disponibile
# sul loro ratio/moltiplicatore). TerritoryDynamicsService lo passa a false per le specie con
# min_territory_cells > 1 (es. deer), il cui log dedicato mostra già ratio_finale/stock/fabbisogno
# — stampare anche qui sarebbe una riga duplicata con la stessa informazione.
func apply_mitigation_multiplier(group: PopulationGroup, raw_ratio: float, log_enabled: bool = true) -> float:
	var clamped_ratio: float = min(raw_ratio, 1.0)
	var multiplier := _get_multiplier(clamped_ratio)

	group.set_birth_mitigation_multiplier(multiplier)

	if DebugLogging.ENABLED and log_enabled:
		print("[BIRTH MITIGATION] %s pop=%d ratio_grezzo=%.3f ratio_clampato=%.3f moltiplicatore=%.3f" % [
			group.species_name, group.population, raw_ratio, clamped_ratio, multiplier
		])

	return multiplier


# Somma, su tutte le celle del territorio (una sola per rabbit, min_territory_cells fino a 20 per
# deer da Step 5 in poi — vedi Territory, iterato qui in forma generica fin da prima che il
# multi-cella esistesse, quindi nessuna modifica necessaria in questo step), le calorie ottenibili
# da ogni fonte in diet_compatibility, pesate per compatibilità — stessa formula di peso usata da
# AnimalConsumptionService._consume_requirement_in_cell, ma come somma-snapshot invece che
# distribuita contro un fabbisogno giornaliero. `season` qui è la stagione REALE in cui gira
# questo checkpoint (== rules.birth_season per costruzione, vedi TerritoryDynamicsService, unico
# chiamante di compute_caloric_ratio) — nessuna proiezione: FORAGE usa lo stesso stato/stagione di
# oggi, esattamente come farebbe AnimalConsumptionService se girasse in questo stesso giorno.
func _get_available_stock(world: World, group: PopulationGroup, rules: AnimalRules, season: GameTypes.Season) -> float:
	var total := 0.0
	for coords in group.territory.occupied_macrocells:
		var cell := world.get_cell_at(coords.x, coords.y)
		var state := world.get_cell_state_at(coords.x, coords.y)
		if cell == null or state == null:
			continue

		for source_name in rules.diet_compatibility.keys():
			var compatibility := float(rules.diet_compatibility[source_name])
			if compatibility <= 0.0:
				continue

			var source_rules := CaloricCalculator.get_caloric_source_rules(source_name)
			if source_rules == null or source_rules.calories_per_unit <= 0.0:
				continue

			var available_calories: float
			if source_name == FORAGE_SOURCE_NAME:
				available_calories = CaloricCalculator.get_forage_available_calories(cell, state, season)
			else:
				available_calories = CaloricCalculator.get_secondary_resource_stock_calories(state, source_name)

			total += available_calories * compatibility

	return total


# Stessa formula age-weighted di AnimalConsumptionService._get_total_daily_requirement,
# duplicata qui (non esposta/richiamata da AnimalConsumptionService, che resta intoccato) per
# ottenere il fabbisogno calorico giornaliero totale del gruppo, poi esteso alla durata
# stagionale approssimata.
func _get_seasonal_requirement(group: PopulationGroup, rules: AnimalRules) -> float:
	var young := group.get_age_count(GameTypes.AgeBand.YOUNG)
	var adult := group.get_age_count(GameTypes.AgeBand.ADULT)
	var old := group.get_age_count(GameTypes.AgeBand.OLD)
	var weighted_count: float = (
		float(young) * rules.caloric_multiplier_by_age[GameTypes.AgeBand.YOUNG]
		+ float(adult) * rules.caloric_multiplier_by_age[GameTypes.AgeBand.ADULT]
		+ float(old) * rules.caloric_multiplier_by_age[GameTypes.AgeBand.OLD]
	)
	var daily_requirement := weighted_count * rules.daily_caloric_requirement
	return daily_requirement * APPROX_SEASON_DURATION_DAYS


# Sopra RATIO_HIGH_THRESHOLD: nessuna penalità. Sotto RATIO_LOW_THRESHOLD: moltiplicatore al
# floor (mai esattamente 0, così un anno scarso non azzera del tutto la natalità). In mezzo,
# rampa lineare tra i due — nessuna soglia a gradini come la mortalità density-dependent
# (FaunaMortalityService/ResourceMortalityService): qui la richiesta è un decremento progressivo.
func _get_multiplier(ratio_clamped: float) -> float:
	if ratio_clamped >= RATIO_HIGH_THRESHOLD:
		return 1.0
	if ratio_clamped <= RATIO_LOW_THRESHOLD:
		return MULTIPLIER_FLOOR
	var t: float = (ratio_clamped - RATIO_LOW_THRESHOLD) / (RATIO_HIGH_THRESHOLD - RATIO_LOW_THRESHOLD)
	return lerp(MULTIPLIER_FLOOR, 1.0, t)
