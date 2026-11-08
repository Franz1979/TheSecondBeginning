class_name SeasonalResourceService
extends RefCounted

# Cambi di stagione delle risorse derivate dalle piante (scorte di frutti e raccolti segnati), un solo punto per le celle
# accese (WorldTimeService, a ogni inizio stagione) e per una cella che si riaccende (catch_up_frozen_cell).
# Erbe, verdure e funghi non hanno una scorta: la loro disponibilità legge il moltiplicatore della stagione corrente ogni
# volta (LotCapacityService._apply_seasonal_availability_to_capacity), quindi sono già giusti. Da una cella spenta può
# restare indietro solo ciò che si aggiorna qui.


# Scorte di frutti di UNA cella al passaggio di stagione. Una fonte senza piante e senza scorta non ha niente da aggiornare.
static func update_cell_stock(
	cell: MacroCellData, state: MacroCellState, previous_season: GameTypes.Season, new_season: GameTypes.Season
) -> void:
	for source in CaloricCalculator.SECONDARY_SOURCES:
		var resource_name: String = source["resource_name"]
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null:
			continue
		if (
			not CaloricCalculator.has_secondary_resource_potential(rules, state, source["primary_resource_type"])
			and state.get_secondary_resource_stock(resource_name) == 0.0
		):
			continue
		CaloricCalculator.update_secondary_resource_stock(rules, cell, state, source["primary_resource_type"], previous_season, new_season)
		# Il raccolto per lotto si azzera solo quando il moltiplicatore SALE: solo lì compare frutto nuovo. Quando scende, la
		# memoria di quanto già raccolto resta, per non far riapparire il frutto appena preso. `not is_empty`: azzerare un
		# registro già vuoto alzerebbe la revisione e farebbe ricalcolare per niente il disegno dei frutti
		# (TerrainScatteredResourceService.get_fruit_stock_recompute_signature).
		if not TerrainScatteredResourceService.FRUIT_STOCK_SOURCES.has(resource_name):
			continue
		var previous_multiplier: float = float(rules.seasonal_availability_multiplier[previous_season])
		var new_multiplier: float = float(rules.seasonal_availability_multiplier[new_season])
		var per_lot: Dictionary = state.berry_harvested_by_lot.get(resource_name, {})
		if new_multiplier > previous_multiplier and not per_lot.is_empty():
			state.berry_harvested_by_lot.erase(resource_name)
			state.berry_harvested_revision[resource_name] = int(state.berry_harvested_revision.get(resource_name, 0)) + 1


# Alla riaccensione di una cella: rifà i cambi di stagione saltati da spenta, con gli stessi calcoli di una cella accesa,
# così frutti e raccolti sono quelli della stagione in corso. Piante ed età non si toccano: il motore delle piante non
# recupera gli anni. Bastano gli ultimi 12 mesi: dentro c'è sempre il reset pieno di inizio ciclo di ogni fonte.
static func catch_up_frozen_cell(cell: MacroCellData, state: MacroCellState, game_data: GameData) -> void:
	var frozen_since: int = state.frozen_since_absolute_day
	state.frozen_since_absolute_day = -1
	if frozen_since < 0:
		return
	var states: Array = [state]
	# Saltata la fine di una primavera: raccolti annuali azzerati e segni delle piante morte tolti.
	if VegetationPoolService.most_recent_growth_checkpoint_absolute_day(game_data) > frozen_since:
		LotCapacityService.reset_harvests_for_resources_without_seasonal_rise(states)
		state.vegetation_death_exceptions.clear()
	var today: int = game_data.get_absolute_day()
	for absolute_day in range(maxi(frozen_since, today - GameData.DAYS_PER_YEAR) + 1, today + 1):
		var day_of_year: int = absolute_day % GameData.DAYS_PER_YEAR
		if not SeasonCalculator.is_season_start_day(day_of_year):
			continue
		var new_season := SeasonCalculator.get_season_for_day(day_of_year)
		var previous_season := SeasonCalculator.get_previous_season(new_season)
		update_cell_stock(cell, state, previous_season, new_season)
		LotCapacityService.reset_all_lot_harvests_on_season_rise(states, previous_season, new_season)
