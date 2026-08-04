class_name AnimalBirthMitigationService
extends RefCounted

const FORAGE_SOURCE_NAME := "forage"

# Approssimazione uniforme della durata di una stagione (91-92 giorni reali, vedi
# SeasonCalculator.SEASON_LENGTHS): qui la precisione non serve.
const APPROX_SEASON_DURATION_DAYS := 100

const RATIO_HIGH_THRESHOLD := 0.8  # sopra: nessuna penalità, moltiplicatore = 1.0 (o più, vedi sotto)
const RATIO_LOW_THRESHOLD := 0.3   # sotto: moltiplicatore ridotto al floor
const MULTIPLIER_FLOOR := 0.05     # "quasi zero", mai natalità del tutto azzerata da un solo anno scarso

# Bonus da abbondanza: sopra RATIO_HIGH_THRESHOLD il moltiplicatore non resta più piatto a 1.0,
# ma sale ulteriormente fino a MULTIPLIER_ABUNDANCE_CAP quando raw_ratio raggiunge
# RATIO_ABUNDANCE_CAP_AT — un territorio con surplus calorico reale (non solo "a sufficienza")
# premia una natalità leggermente più alta del normale, dipendente da un dato reale della
# simulazione (il ratio calorico) invece di rumore casuale non correlato a nulla. Nato da un
# problema osservato nei test: la mitigazione da densità (vedi TerritoryDynamicsService) può
# spingere una specie a crescita lenta (deer) in un pareggio quasi esatto nascite/morti proprio
# a ridosso della soglia che farebbe scattare l'espansione territoriale — un piccolo surplus
# calorico aggiuntivo, quando c'è, aiuta a smuovere quel pareggio senza introdurre casualità.
# Nessun rischio di sfuggire di mano: il moltiplicatore finale resta SEMPRE calorico × densità
# (vedi apply_mitigation_multiplier), e il fattore densità crolla verso 0 non appena
# occupazione_ratio supera 1.5 (vedi TerritoryDynamicsService.DENSITY_RATIO_RAMP_END) —
# qualunque bonus calorico, il freno di densità ha sempre l'ultima parola quando serve davvero.
const RATIO_ABUNDANCE_CAP_AT := 2.0       # raw_ratio da cui in poi il bonus satura
const MULTIPLIER_ABUNDANCE_CAP := 1.2     # moltiplicatore massimo raggiungibile per abbondanza


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
# checkpoint di inizio birth_season, mai su un territorio che sta per essere modificato.
#
# density_multiplier/occupancy_ratio: seconda mitigazione, indipendente da quella calorica sopra
# — legata alla densità ETOLOGICA del territorio (AnimalRules.max_density_per_cell), non alle
# risorse (TerritoryDynamicsService._get_density_multiplier calcola questi due valori, questa
# funzione resta l'unico punto che combina+applica+logga il moltiplicatore finale, così non
# restano sparsi due punti di scrittura su group.birth_mitigation_multiplier). Default 1.0/0.0
# (nessuna penalità aggiuntiva) per restare no-op se un futuro chiamante non li passa. Il
# moltiplicatore FINALE (calorico × densità) resta memorizzato sul gruppo fino al checkpoint di
# nascita già esistente, a fine birth_season. Ritorna un Dictionary (non solo il moltiplicatore
# finale) con tutti i valori intermedi — clamped_ratio/caloric_multiplier inclusi, non solo
# final_multiplier — così il chiamante (TerritoryDynamicsService) può metterli nel proprio log
# invece di ricalcolarli o lasciarli invisibili quando il log di qui sotto è soppresso (vedi
# log_enabled sotto): senza questo, il log [TERRITORY DYNAMICS] mostrava il moltiplicatore finale
# ma non la scomposizione calorico/clampato che invece [BIRTH MITIGATION] mostra sempre.
#
# log_enabled di default true (specie a 1 sola cella, es. rabbit: questo è l'unico log disponibile
# sul loro ratio/moltiplicatore). TerritoryDynamicsService lo passa a false per le specie con
# min_territory_cells > 1 (es. deer), il cui log dedicato mostra già ratio_finale/stock/fabbisogno
# — stampare anche qui sarebbe una riga duplicata con la stessa informazione.
func apply_mitigation_multiplier(
	group: PopulationGroup, raw_ratio: float,
	density_multiplier: float = 1.0, occupancy_ratio: float = 0.0,
	log_enabled: bool = true
) -> Dictionary:
	# Clampato a RATIO_ABUNDANCE_CAP_AT (non più a 1.0): un ratio anche enormemente sopra quel
	# valore (es. deer, spesso 60-100+ in questi test) non deve far salire il moltiplicatore oltre
	# MULTIPLIER_ABUNDANCE_CAP — il tetto sull'INPUT qui rispecchia il tetto sull'OUTPUT che
	# _get_multiplier applica comunque, evitando solo di passargli un numero arbitrariamente grande.
	var clamped_ratio: float = min(raw_ratio, RATIO_ABUNDANCE_CAP_AT)
	var caloric_multiplier := _get_multiplier(clamped_ratio)
	var final_multiplier: float = caloric_multiplier * density_multiplier

	group.set_birth_mitigation_multiplier(final_multiplier)

	if DebugLogging.ENABLED and log_enabled:
		print("[BIRTH MITIGATION] #%d %s pop=%d ratio_grezzo=%.3f ratio_clampato=%.3f moltiplicatore_calorico=%.3f occupazione_ratio=%.3f moltiplicatore_densita=%.3f moltiplicatore_finale=%.3f" % [
			group.id, group.species_name, group.population, raw_ratio, clamped_ratio,
			caloric_multiplier, occupancy_ratio, density_multiplier, final_multiplier
		])

	return {
		"clamped_ratio": clamped_ratio,
		"caloric_multiplier": caloric_multiplier,
		"final_multiplier": final_multiplier,
	}


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


# Sotto RATIO_LOW_THRESHOLD: moltiplicatore al floor (mai esattamente 0, così un anno scarso non
# azzera del tutto la natalità). Tra le due soglie basse, rampa lineare verso 1.0 — nessuna soglia
# a gradini come la mortalità density-dependent (FaunaMortalityService/ResourceMortalityService):
# qui la richiesta è un decremento progressivo. Sopra RATIO_HIGH_THRESHOLD, il moltiplicatore non
# resta più piatto a 1.0: sale ulteriormente verso MULTIPLIER_ABUNDANCE_CAP man mano che
# ratio_clamped si avvicina a RATIO_ABUNDANCE_CAP_AT (vedi costanti sopra per il perché), poi
# resta piatto al cap oltre quel punto.
func _get_multiplier(ratio_clamped: float) -> float:
	if ratio_clamped <= RATIO_LOW_THRESHOLD:
		return MULTIPLIER_FLOOR
	if ratio_clamped < RATIO_HIGH_THRESHOLD:
		var t: float = (ratio_clamped - RATIO_LOW_THRESHOLD) / (RATIO_HIGH_THRESHOLD - RATIO_LOW_THRESHOLD)
		return lerp(MULTIPLIER_FLOOR, 1.0, t)
	if ratio_clamped < RATIO_ABUNDANCE_CAP_AT:
		var t: float = (ratio_clamped - RATIO_HIGH_THRESHOLD) / (RATIO_ABUNDANCE_CAP_AT - RATIO_HIGH_THRESHOLD)
		return lerp(1.0, MULTIPLIER_ABUNDANCE_CAP, t)
	return MULTIPLIER_ABUNDANCE_CAP
