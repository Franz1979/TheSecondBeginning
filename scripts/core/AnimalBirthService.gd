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
		var births := int(round(weighted_count * rules.base_birth_rate * group.birth_mitigation_multiplier))
		var population_before := group.population
		group.apply_births(births)

		if DebugLogging.ENABLED:
			print("[ANIMAL BIRTHS] checkpoint=fine %s | %s: Y=%d A=%d O=%d pesato_fertilita=%.2f base_birth_rate=%.2f mitigazione=%.2f -> nascite=%d pop %d->%d" % [
				GameTypes.Season.keys()[season], group.species_name,
				young, adult, old, weighted_count, rules.base_birth_rate, group.birth_mitigation_multiplier,
				births, population_before, group.population
			])
