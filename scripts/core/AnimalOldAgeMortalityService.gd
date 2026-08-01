class_name AnimalOldAgeMortalityService
extends RefCounted

# Chiamata da WorldTimeService._run_animal_lifecycle_checkpoint DOPO AnimalBirthService.apply_births
# nello stesso checkpoint: ultimo passo del ciclo annuale per specie/cella. Stessa logica
# frazionaria già usata per le transizioni young->adult/adult->old (vedi
# PopulationGroup.apply_age_band_maturation) applicata alla fascia OLD verso la morte
# invece che verso un'altra fascia — 1/old_duration_years della popolazione OLD corrente muore
# ogni anno, nessun tracking di coorte per anno di nascita. Include anche gli individui appena
# entrati in OLD in questo stesso checkpoint (la maturazione adult->old gira prima, nello stesso
# ciclo): stesso principio aggregato/statistico già usato in tutto il sistema — nessuno stato
# "appena arrivato" viene tracciato da nessuna transizione, quindi non lo tracciamo neanche qui.
# Solo le specie con AnimalRules.track_age_bands=true E birth_season == season sono soggette; le
# altre sono no-op per costruzione. Nessuna interazione con mortalità da fame o altre cause —
# questo copre solo la morte per vecchiaia.
func apply_old_age_mortality(world: World, season: GameTypes.Season) -> void:
	for group in world.population_groups:
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or not rules.track_age_bands:
			continue
		if rules.birth_season != season:
			continue
		if rules.old_duration_years <= 0:
			continue

		var old_count := group.get_age_count(GameTypes.AgeBand.OLD)
		if old_count <= 0:
			continue

		var deaths_from_age: int = min(
			int(round(float(old_count) / float(rules.old_duration_years))), old_count
		)
		group.apply_old_age_mortality(deaths_from_age)
