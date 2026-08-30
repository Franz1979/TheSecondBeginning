class_name AnimalBirthService
extends RefCounted

# Chiamata da WorldTimeService._run_animal_lifecycle_checkpoint DOPO
# AnimalAgeBandService.mature_age_bands nello stesso checkpoint: opera sulla composizione
# young/adult/old già maturata quest'anno, quindi i nuovi nati (aggiunti in YOUNG da
# PopulationGroup.apply_births) non vengono mai inclusi nella maturazione dello stesso
# ciclo in cui compaiono — stesso principio già usato per ResourceAgeBandService/
# ResourceGrowthService lato vegetazione. Solo le specie con AnimalRules.track_age_bands=true
# E birth_season == season producono nascite; le altre sono no-op per costruzione.
# group.birth_mitigation_multiplier (vedi AnimalBirthMitigationService, calcolato a inizio
# birth_season) modula il coefficiente fisso base_birth_rate in base alla disponibilità calorica
# del territorio — si aggiunge a fertility_multiplier_by_age, non lo sostituisce.
func apply_births(world: World, season: GameTypes.Season) -> void:
	for group in world.population_groups:
		if group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or not rules.track_age_bands:
			continue
		if rules.birth_season != season:
			continue

		var young := group.get_age_count(GameTypes.AgeBand.YOUNG)
		var adult := group.get_age_count(GameTypes.AgeBand.ADULT)
		var old := group.get_age_count(GameTypes.AgeBand.OLD)

		var weighted_count: float = (
			float(young) * rules.fertility_multiplier_by_age[GameTypes.AgeBand.YOUNG]
			+ float(adult) * rules.fertility_multiplier_by_age[GameTypes.AgeBand.ADULT]
			+ float(old) * rules.fertility_multiplier_by_age[GameTypes.AgeBand.OLD]
		)
		# stochastic_round (non round()): stesso bias sistematico di AnimalOldAgeMortalityService a
		# popolazioni/pesi_fertilità piccoli — vedi SimulationMath.
		var births := SimulationMath.stochastic_round(
				weighted_count * rules.base_birth_rate * group.birth_mitigation_multiplier,
				("BIRTHS #%d %s" % [group.id, group.species_name]) if (rules is PredatorRules and DebugLogging.SHOW_PREDATOR_LIFECYCLE_LOGS) else ""
			)
		var population_before := group.population
		group.apply_births(births)

		# Filtro erbivori/predatori: vedi DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS/
		# SHOW_PREDATOR_LIFECYCLE_LOGS — ciascun lato ora ha il proprio interruttore indipendente.
		# ratio_calorico (PopulationGroup.birth_mitigation_caloric_ratio) affiancato a mitigazione:
		# quest'ultima è già il prodotto calorico×densità×post-scissione (vedi
		# AnimalBirthMitigationService.apply_mitigation_multiplier), il ratio grezzo da solo non
		# basta a spiegarla — mostrarli insieme evita di dover risalire al checkpoint TERRITORY
		# DYNAMICS di inizio stagione (fino a ~90 giorni prima) per capire da dove viene il numero.
		if DebugLogging.ENABLED and (
			(rules is PredatorRules and DebugLogging.SHOW_PREDATOR_LIFECYCLE_LOGS)
			or (not (rules is PredatorRules) and DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS)
		):
			# base_birth_rate_effettivo = base_birth_rate × mitigazione (già il prodotto
			# calorico×densità×post-scissione) — nessun campo nuovo necessario, entrambi i fattori
			# sono già disponibili qui: risparmia al lettore il calcolo a mano per capire il tasso
			# di natalità REALMENTE applicato a questo gruppo, non solo il coefficiente di specie.
			var base_birth_rate_effettivo: float = rules.base_birth_rate * group.birth_mitigation_multiplier
			print("[ANIMAL BIRTHS] checkpoint=fine %s | #%d %s: Y=%d A=%d O=%d pesato_fertilita=%.2f base_birth_rate=%.2f ratio_calorico=%.3f mitigazione=%.2f base_birth_rate_effettivo=%.3f -> nascite=%d pop %d->%d" % [
				GameTypes.Season.keys()[season], group.id, group.species_name,
				young, adult, old, weighted_count, rules.base_birth_rate, group.birth_mitigation_caloric_ratio,
				group.birth_mitigation_multiplier, base_birth_rate_effettivo, births, population_before, group.population
			])
