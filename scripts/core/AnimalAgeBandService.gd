class_name AnimalAgeBandService
extends RefCounted

# Chiamata da WorldTimeService._run_animal_age_band_checkpoint, una volta per ciascuna delle
# quattro stagioni (a fine stagione), PRIMA di qualunque logica di nascita che finirà nello
# stesso checkpoint (prompt futuro) — così i nuovi nati non maturano mai nello stesso ciclo in
# cui compaiono, stesso principio di ResourceAgeBandService per la vegetazione. Solo le specie
# con AnimalRules.track_age_bands=true E birth_season == season fanno davvero qualcosa; le
# altre sono no-op per costruzione (get_animal_rules null, track_age_bands false, o
# birth_season di un'altra stagione).
func mature_age_bands(world: World, season: GameTypes.Season) -> void:
	for group in world.population_groups:
		if group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or not rules.track_age_bands:
			continue
		if rules.birth_season != season:
			continue

		var young_before := group.get_age_count(GameTypes.AgeBand.YOUNG)
		var adult_before := group.get_age_count(GameTypes.AgeBand.ADULT)
		var old_before := group.get_age_count(GameTypes.AgeBand.OLD)

		group.apply_age_band_maturation(
			rules.youth_duration_years, rules.adult_duration_years,
			("AGING #%d %s" % [group.id, group.species_name]) if rules is PredatorRules else ""
		)

		# Filtro erbivori/predatori: vedi DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS.
		if DebugLogging.ENABLED and (rules is PredatorRules or DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS):
			print("[ANIMAL AGING] checkpoint=fine %s | #%d %s: Y %d->%d (youth_duration=%d) | A %d->%d (adult_duration=%d) | O %d->%d" % [
				GameTypes.Season.keys()[season], group.id, group.species_name,
				young_before, group.get_age_count(GameTypes.AgeBand.YOUNG), rules.youth_duration_years,
				adult_before, group.get_age_count(GameTypes.AgeBand.ADULT), rules.adult_duration_years,
				old_before, group.get_age_count(GameTypes.AgeBand.OLD)
			])
