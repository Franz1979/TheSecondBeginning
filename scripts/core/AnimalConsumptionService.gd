class_name AnimalConsumptionService
extends RefCounted

const FORAGE_SOURCE_NAME := "forage"

# Consumo calorico giornaliero (non stagionale) per ogni specie animale presente in ciascuna
# cella, ripartito tra TUTTE le fonti con AnimalRules.diet_compatibility > 0 (FORAGE e le fonti
# a stock come BERRY/ACORN/FRUIT), pesato per calorie disponibili × compatibilità — vedi
# _consume_species_in_cell. Il fabbisogno non soddisfatto non ha ancora conseguenze (nessuna
# mortalità per fame): la popolazione consuma quello che trova e basta. Ritorna true se in
# almeno una cella/specie è stato applicato un consumo da ALMENO UNA fonte (peso totale > 0),
# non solo quando GRASS perde davvero spazio: dedicated_space[GRASS] cambia solo quando il
# debito frazionario (pending_grass_space_debt) supera 1.0, un evento raro rispetto al consumo
# giornaliero di berry/acorn/fruit (che invece intacca subito lo stock, ogni giorno). Il
# chiamante (MacroCellScene/GameScene) usa questo valore per decidere se il pannello info va
# rinfrescato oggi — il rebuild costoso delle MultiMesh di vegetazione resta gated
# separatamente da checkpoint_ran/flora_daily_updates_enabled, indipendente da questo flag.
func apply_daily_consumption(world: World, current_season: GameTypes.Season) -> bool:
	var any_consumption_applied := false

	for group in world.population_groups:
		if group.population <= 0:
			continue

		var home_cell := group.territory.get_primary_cell()
		var cell := world.get_cell_at(home_cell.x, home_cell.y)
		var state := world.get_cell_state_at(home_cell.x, home_cell.y)
		if cell == null or state == null:
			continue

		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null:
			continue

		if _consume_species_in_cell(cell, state, rules, group, current_season):
			any_consumption_applied = true

	return any_consumption_applied


# Fabbisogno calorico totale giornaliero per una specie/cella. Per le specie con
# track_age_bands=true pesa ciascuna fascia con AnimalRules.caloric_multiplier_by_age invece di
# trattare l'intera popolazione come un blocco uniforme (adult=1.0 è il riferimento a cui
# daily_caloric_requirement è tarato); per le altre resta la vecchia formula flat. Nessun
# fallback per una composizione età vuota su una specie track_age_bands=true: se capita, è un
# bug reale (population e age_composition del gruppo non allineati) e deve dare fabbisogno 0,
# visibilmente sbagliato, non essere mascherato.
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


# Costruisce le fonti pesate per una specie/cella e ne ripartisce il fabbisogno. Fonti con
# diet_compatibility <= 0 vengono escluse SENZA interrogare CaloricCalculator (peso comunque
# nullo, calcolo sprecato) — vengono solo loggate come escluse. Ritorna true se è stato
# applicato un consumo da almeno una fonte (weight_sum > 0), qualunque essa sia — vedi
# apply_daily_consumption.
func _consume_species_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	rules: AnimalRules,
	group: PopulationGroup,
	current_season: GameTypes.Season
) -> bool:
	var total_requirement := _get_total_daily_requirement(group, rules)

	var weighted_sources: Array[Dictionary] = []
	var weight_sum := 0.0
	var log_lines: Array[String] = []

	for source_name in rules.diet_compatibility.keys():
		var compatibility := float(rules.diet_compatibility[source_name])
		if compatibility <= 0.0:
			log_lines.append("%s: peso=0.00 (escluso, compatibility=0)" % source_name)
			continue

		var source_rules := CaloricCalculator.get_caloric_source_rules(source_name)
		if source_rules == null or source_rules.calories_per_unit <= 0.0:
			log_lines.append("%s: peso=0.00 (escluso, regole mancanti)" % source_name)
			continue

		var available_calories: float
		if source_name == FORAGE_SOURCE_NAME:
			available_calories = CaloricCalculator.get_forage_available_calories(cell, state, current_season)
		else:
			available_calories = CaloricCalculator.get_secondary_resource_stock_calories(state, source_name)

		var weight := available_calories * compatibility
		if weight <= 0.0:
			log_lines.append("%s: peso=0.00 calorie=%.1f (escluso, nulla disponibile)" % [source_name, available_calories])
			continue

		weighted_sources.append({
			"name": source_name,
			"available_calories": available_calories,
			"weight": weight,
			"rules": source_rules,
		})
		weight_sum += weight

	if weight_sum > 0.0:
		for source in weighted_sources:
			var source_name: String = source["name"]
			var source_weight: float = source["weight"]
			var source_available_calories: float = source["available_calories"]
			var source_rules: CaloricSourceRules = source["rules"]

			var share: float = total_requirement * (source_weight / weight_sum)
			var consumed_calories: float = min(share, source_available_calories)
			var units_consumed: float = consumed_calories / source_rules.calories_per_unit

			if source_name == FORAGE_SOURCE_NAME:
				# Il valore di ritorno (spazio GRASS davvero decrementato) non serve più al
				# chiamante: il segnale "consumo avvenuto" oggi è weight_sum > 0, qualunque sia
				# la fonte — vedi apply_daily_consumption.
				_consume_forage(cell, state, units_consumed)
			else:
				var before := state.get_secondary_resource_stock(source_name)
				state.set_secondary_resource_stock(source_name, before - units_consumed)

			log_lines.append("%s: peso=%.1f calorie=%.1f" % [source_name, source_weight, consumed_calories])

	if DebugLogging.ENABLED and state.x == 50 and state.y == 50:
		print("[ANIMAL CONSUME %s] population=%d fabbisogno=%.1f | %s | pending_debt=%.2f" % [
			group.species_name, group.population, total_requirement, " | ".join(log_lines),
			state.get_pending_grass_space_debt()
		])

	return weight_sum > 0.0


# Stesso schema di conversione spazio<->quantità usato da growth/mortality: la risorsa primaria
# (consuming_depletes_primary = true, solo FORAGE/GRASS) viene decrementata tramite
# dedicated_space, con resource_quantity sempre RICALCOLATO da esso — mai un contatore
# indipendente, altrimenti il prossimo checkpoint di crescita lo sovrascriverebbe cancellando
# l'effetto del consumo.
#
# Il consumo giornaliero convertito in spazio (unità/densità) è quasi sempre < 1 unità intera:
# arrotondare ogni giorno lo azzererebbe sistematicamente, perdendo il consumo per sempre. Si
# accumula invece in pending_grass_space_debt finché non supera 1.0, momento in cui
# dedicated_space viene davvero decrementato — nessuna quantità va mai persa, solo posticipata.
func _consume_forage(cell: MacroCellData, state: MacroCellState, units_consumed: float) -> bool:
	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.GRASS, cell.terrain_base, cell.biome, cell.coast_type
	)
	if max_density <= 0.0:
		return false

	var space_debt := state.get_pending_grass_space_debt() + (units_consumed / max_density)
	var space_to_remove: int = int(floor(space_debt))
	var removed := false
	if space_to_remove > 0:
		var current_space := state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
		# Se lo spazio fisico disponibile è meno del debito maturato (es. grass ridotta nel
		# frattempo da mortalità), si rimuove solo quello che c'è davvero e il resto del debito
		# resta in sospeso, invece di essere scartato.
		var actually_removed: int = min(space_to_remove, current_space)
		if actually_removed > 0:
			removed = true
		var new_space := current_space - actually_removed
		state.set_dedicated_space(GameTypes.WorldObjectType.GRASS, new_space)
		state.set_resource_quantity(
			GameTypes.WorldObjectType.GRASS, int(round(new_space * max_density))
		)
		space_debt -= actually_removed
	state.set_pending_grass_space_debt(space_debt)

	return removed
