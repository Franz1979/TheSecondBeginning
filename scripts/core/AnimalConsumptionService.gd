class_name AnimalConsumptionService
extends RefCounted

# Consumo calorico giornaliero (non stagionale) per ogni specie animale presente in ciascuna
# cella: per ora tutte le specie mangiano solo FORAGE (vedi AnimalRules.diet_compatibility —
# la logica multi-risorsa non è ancora implementata). Il fabbisogno non soddisfatto non ha
# ancora conseguenze (nessuna mortalità per fame): la popolazione consuma quello che trova e
# basta. Ritorna true solo se il consumo ha DAVVERO decrementato dedicated_space[GRASS] in
# almeno una cella questo giorno (non semplicemente se esiste popolazione): il debito
# frazionario (pending_grass_space_debt) fa sì che la maggior parte dei giorni non tolga
# spazio reale, e il chiamante (MacroCellScene) usa questo valore per decidere se vale la pena
# ricostruire le MultiMesh di vegetazione — un rebuild costoso a ogni giorno, a prescindere da
# un cambiamento visibile, sarebbe sprecato.
func apply_daily_consumption(world: World, current_season: GameTypes.Season) -> bool:
	var forage_rules := CaloricCalculator.get_caloric_source_rules("forage")
	if forage_rules == null or forage_rules.calories_per_unit <= 0.0:
		return false

	var any_grass_removed := false

	for state in world.cell_states:
		if state.animal_population.is_empty():
			continue
		var cell := world.get_cell_at(state.x, state.y)
		if cell == null:
			continue

		for species_name in state.animal_population.keys():
			var population := state.get_animal_population(species_name)
			if population <= 0:
				continue

			var rules := AnimalCalculator.get_animal_rules(species_name)
			if rules == null:
				continue

			var total_requirement := float(population) * rules.daily_caloric_requirement
			var available_calories := CaloricCalculator.get_forage_available_calories(cell, state, current_season)
			var consumed_calories: float = min(total_requirement, available_calories)
			var units_consumed := consumed_calories / forage_rules.calories_per_unit

			# Stesso schema di conversione spazio<->quantità usato da growth/mortality: la
			# risorsa primaria (consuming_depletes_primary = true) viene decrementata tramite
			# dedicated_space, con resource_quantity sempre RICALCOLATO da esso — mai un
			# contatore indipendente, altrimenti il prossimo checkpoint di crescita lo
			# sovrascriverebbe cancellando l'effetto del consumo.
			#
			# Il consumo giornaliero convertito in spazio (unità/densità) è quasi sempre < 1
			# unità intera: arrotondare ogni giorno lo azzererebbe sistematicamente, perdendo
			# il consumo per sempre. Si accumula invece in pending_grass_space_debt finché non
			# supera 1.0, momento in cui dedicated_space viene davvero decrementato — nessuna
			# quantità va mai persa, solo posticipata.
			var max_density := ResourceCalculator.get_max_density(
				GameTypes.WorldObjectType.GRASS, cell.terrain_base, cell.biome, cell.coast_type
			)
			if max_density > 0.0:
				var space_debt := state.get_pending_grass_space_debt() + (units_consumed / max_density)
				var space_to_remove: int = int(floor(space_debt))
				if space_to_remove > 0:
					var current_space := state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
					# Se lo spazio fisico disponibile è meno del debito maturato (es. grass
					# ridotta nel frattempo da mortalità), si rimuove solo quello che c'è
					# davvero e il resto del debito resta in sospeso, invece di essere scartato.
					var actually_removed: int = min(space_to_remove, current_space)
					if actually_removed > 0:
						any_grass_removed = true
					var new_space := current_space - actually_removed
					state.set_dedicated_space(GameTypes.WorldObjectType.GRASS, new_space)
					state.set_resource_quantity(
						GameTypes.WorldObjectType.GRASS, int(round(new_space * max_density))
					)
					space_debt -= actually_removed
				state.set_pending_grass_space_debt(space_debt)

			if DebugLogging.ENABLED and state.x == 50 and state.y == 50:
				print("[ANIMAL CONSUME %s] population=%d fabbisogno=%.1f calorie_consumate=%.1f unità_forage=%.2f pending_debt=%.2f" % [
					species_name, population, total_requirement, consumed_calories, units_consumed,
					state.get_pending_grass_space_debt()
				])

	return any_grass_removed
