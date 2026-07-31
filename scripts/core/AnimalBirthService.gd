class_name AnimalBirthService
extends RefCounted

# Chiamata da WorldTimeService._run_animal_lifecycle_checkpoint DOPO
# AnimalAgeBandService.mature_age_bands nello stesso checkpoint: opera sulla composizione
# young/adult/old già maturata quest'anno, quindi i nuovi nati (aggiunti in YOUNG da
# MacroCellState.apply_animal_births) non vengono mai inclusi nella maturazione dello stesso
# ciclo in cui compaiono — stesso principio già usato per ResourceAgeBandService/
# ResourceGrowthService lato vegetazione. Solo le specie con AnimalRules.track_age_bands=true
# E birth_season == season producono nascite; le altre sono no-op per costruzione. Nessuna
# modulazione da disponibilità calorica o altro: solo il coefficiente fisso base_birth_rate per
# ora (prompt futuro).
func apply_births(world: World, season: GameTypes.Season) -> void:
	for state in world.cell_states:
		if state.animal_population.is_empty():
			continue
		for species_name in state.animal_population.keys():
			var rules := AnimalCalculator.get_animal_rules(species_name)
			if rules == null or not rules.track_age_bands:
				continue
			if rules.birth_season != season:
				continue

			var young := state.get_animal_age_count(species_name, GameTypes.AgeBand.YOUNG)
			var adult := state.get_animal_age_count(species_name, GameTypes.AgeBand.ADULT)
			var old := state.get_animal_age_count(species_name, GameTypes.AgeBand.OLD)

			var weighted_count: float = (
				float(young) * rules.fertility_multiplier_by_age[GameTypes.AgeBand.YOUNG]
				+ float(adult) * rules.fertility_multiplier_by_age[GameTypes.AgeBand.ADULT]
				+ float(old) * rules.fertility_multiplier_by_age[GameTypes.AgeBand.OLD]
			)
			var births := int(round(weighted_count * rules.base_birth_rate))
			state.apply_animal_births(species_name, births)
