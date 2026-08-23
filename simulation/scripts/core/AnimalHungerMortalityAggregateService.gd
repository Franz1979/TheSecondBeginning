class_name AnimalHungerMortalityAggregateService
extends RefCounted

# Mortalità da fame aggregata (Parte B del LOD) SOLO per popolazioni Livello 1 non predatrici —
# equivalente stagionale di AnimalHungerService (che invece opera giorno per giorno via
# hunger_buckets, un istogramma per-individuo che qui non esiste: a Livello 1 esiste solo UN
# seasonal_ratio per stagione, non uno storico giorno per giorno). Chiamato da
# WorldTimeService._run_animal_consumption_aggregate_checkpoint SUBITO dopo
# AnimalConsumptionAggregateService, riusando il suo Dictionary[group_id -> seasonal_ratio] già
# calcolato lì (consumo REALIZZATO, dopo la contesa population_share tra specie sulla stessa
# cella) — mai il ratio stock-based di AnimalBirthMitigationService.compute_caloric_ratio, usato
# invece da natalità/espansione territoriale con un significato diverso (stima di disponibilità,
# non consuntivo di quanto è stato davvero prelevato).
#
# Formula (design "opzione C", debito accumulato — vedi sessione di design precedente): invece di
# un istogramma per-individuo (troppo granulare per un aggregato stagionale), un unico scalare per
# gruppo (PopulationGroup.hunger_debt_days) accumula "giorni-deficit equivalenti" stagione dopo
# stagione:
#   ratio < 1.0  -> hunger_debt_days += season_days * (1.0 - ratio)           (il debito cresce)
#   ratio >= 1.0 -> hunger_debt_days -= season_days * (ratio - 1.0), min 0.0  (il debito si allevia)
# Una stagione buona non azzera di colpo lo stress accumulato da stagioni cattive precedenti —
# stesso principio di accumulo/decadimento già usato per active_growth_bonuses lato vegetazione.
# Quando il debito supera rules.max_days_without_food (STESSO parametro di specie già usato dal
# meccanismo giornaliero — nessuna soglia nuova scoordinata), muore una frazione della
# popolazione proporzionale all'eccedenza:
#   death_fraction = clamp(eccedenza / max_days_without_food, 0.0, MAX_DEATH_FRACTION_PER_SEASON)
# Il tetto MAX_DEATH_FRACTION_PER_SEASON impedisce un collasso istantaneo in una sola stagione —
# una specie in crisi CRONICA multi-stagione muore comunque nel tempo, stagione dopo stagione,
# invece che tutta insieme alla prima stagione negativa (un ratio singolo enormemente sotto
# soglia, es. 0.1, con questa approssimazione a "deficit costante per l'intera stagione"
# produrrebbe altrimenti un'eccedenza enorme in un colpo solo). Dopo la mortalità il debito si
# "scarica" proporzionalmente ai morti (erano loro a portarne il peso maggiore): mai azzerato del
# tutto, chi sopravvive resta comunque sopra soglia se il ratio era molto basso, pronto a morire
# ancora la prossima stagione se la scarsità persiste.
#
# ENABLED: interruttore DEDICATO (non DebugLogging, che per contratto non deve mai cambiare
# comportamento di simulazione, solo cosa compare nei log) — a false l'intero meccanismo è no-op:
# nessun aggiornamento di hunger_debt_days, nessuna mortalità, nessun log. Riprova/disattiva senza
# toccare nient'altro nella pipeline.
const ENABLED := true

const MAX_DEATH_FRACTION_PER_SEASON := 0.15

const FORAGE_SOURCE_NAME := "forage"


# `season` qui è la stagione a cui il seasonal_ratio si riferisce (la stessa già passata a
# AnimalConsumptionAggregateService.apply_seasonal_consumption dal chiamante — la stagione APPENA
# CONCLUSA, non quella che sta iniziando), usata solo per calcolare season_days e per il log.
# Ritorna Dictionary[String species_name -> int deaths totali questa stagione], per il riepilogo
# per-specie stampato in fondo — nessun altro consumatore oggi, ma riusabile da un futuro
# chiamante che voglia aggregare oltre il solo log.
func apply_seasonal_hunger_mortality(
	world: World, level_1_groups: Array, season: GameTypes.Season, seasonal_ratios: Dictionary
) -> Dictionary:
	if not ENABLED:
		return {}

	var season_days: int = SeasonCalculator.SEASON_LENGTHS[season]
	var deaths_by_species: Dictionary = {}
	# Dettaglio per-gruppo (species_name -> Array[Dictionary]) SOLO per il riepilogo stampato in
	# fondo — non nel valore di ritorno (che resta il solo Dictionary[species_name -> deaths] già
	# documentato sopra, nessun chiamante reale legge ancora oltre il log). Permette di capire SE
	# è sempre lo stesso gruppo a morire (id/territorio) senza dover riattivare
	# SHOW_HERBIVORE_LIFECYCLE_LOGS, che porterebbe con sé anche tutto il resto del rumore
	# erbivoro (BIRTH MITIGATION/TERRITORY DYNAMICS/POPULATION SPLIT/ANIMAL CONSUMPTION AGGREGATE).
	var groups_by_species: Dictionary = {}

	for group in level_1_groups:
		if group.population <= 0 or group.territory == null:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or rules is PredatorRules:
			continue
		if rules.max_days_without_food <= 0:
			continue

		# Ratio assente dal Dictionary (AnimalConsumptionAggregateService salta i gruppi con
		# fabbisogno stagionale 0) -> nessuna pressione, stesso "neutro 1.0" già usato altrove
		# (es. TerritoryDynamicsService.initial_ratio_data) invece di un falso 0.0 "carestia
		# permanente" che farebbe crescere il debito senza motivo.
		var ratio: float = float(seasonal_ratios.get(group.id, 1.0))

		if ratio < 1.0:
			group.hunger_debt_days += float(season_days) * (1.0 - ratio)
		else:
			group.hunger_debt_days = max(0.0, group.hunger_debt_days - float(season_days) * (ratio - 1.0))

		if group.hunger_debt_days <= float(rules.max_days_without_food):
			continue

		var debt_before_decay: float = group.hunger_debt_days
		var excess_days: float = debt_before_decay - float(rules.max_days_without_food)
		var death_fraction: float = clamp(
			excess_days / float(rules.max_days_without_food), 0.0, MAX_DEATH_FRACTION_PER_SEASON
		)
		var deaths := SimulationMath.stochastic_round(float(group.population) * death_fraction)
		if deaths <= 0:
			continue

		var population_before: int = group.population
		group.apply_hunger_mortality(deaths, rules)
		group.hunger_debt_days = debt_before_decay * (1.0 - death_fraction)

		deaths_by_species[group.species_name] = int(deaths_by_species.get(group.species_name, 0)) + deaths

		var species_group_entries: Array = groups_by_species.get(group.species_name, [])
		species_group_entries.append({
			"group_id": group.id,
			"deaths": deaths,
			"population_after": group.population,
			"centroid": group.territory.get_centroid(),
			"cell_count": group.territory.get_cell_count(),
			"debt_after": group.hunger_debt_days,
		})
		groups_by_species[group.species_name] = species_group_entries

		# Diagnostica territorio: SEMPRE visibile quando c'è mortalità reale (evento raro per
		# costruzione — al più pochi gruppi a stagione, mai il volume di ANIMAL CONSUMPTION
		# AGGREGATE), non serve nasconderla dietro SHOW_HERBIVORE_LIFECYCLE_LOGS. Risponde alla
		# domanda "è scarsità reale di vegetazione o contesa con un'altra specie?" senza dover
		# aprire l'editor — vedi _log_territory_diagnostics sotto.
		if DebugLogging.ENABLED and DebugLogging.SHOW_HUNGER_MORTALITY_DIAGNOSTICS_LOGS:
			_log_territory_diagnostics(world, group, rules, season)

		if DebugLogging.ENABLED and DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS:
			print(
				(
					"[HUNGER MORTALITY AGGREGATE] #%d %s stagione=%s ratio=%.3f debito_giorni=%.1f "
					+ "soglia=%d eccedenza=%.1f frazione_morte=%.3f MORTI=%d pop %d->%d"
				) % [
					group.id, group.species_name, GameTypes.Season.keys()[season], ratio,
					debt_before_decay, rules.max_days_without_food, excess_days, death_fraction,
					deaths, population_before, group.population
				]
			)

	# Riepilogo per specie: SEMPRE visibile (solo dietro il master switch DebugLogging.ENABLED,
	# non dietro SHOW_HERBIVORE_LIFECYCLE_LOGS sopra, a differenza del dettaglio per-gruppo) — è
	# il log che conta "quanti animali sono morti di fame quest'anno, per specie", pensato per
	# restare visibile anche con i log giornalieri (predazione, dettaglio erbivoro) silenziati.
	if DebugLogging.ENABLED and not deaths_by_species.is_empty():
		for species_name in deaths_by_species.keys():
			var species_group_entries: Array = groups_by_species[species_name]
			print(
				"[HUNGER MORTALITY AGGREGATE SUMMARY] stagione=%s specie=%s morti=%d gruppi_coinvolti=%d" % [
					GameTypes.Season.keys()[season], species_name, deaths_by_species[species_name],
					species_group_entries.size()
				]
			)
			# Un gruppo alla volta (vedi commento a groups_by_species sopra) — id + territorio, così
			# si può controllare a colpo d'occhio se è sempre lo STESSO gruppo a morire, e dove si
			# trova (centroide + numero celle) per andare a ispezionarne le risorse.
			for entry in species_group_entries:
				var centroid: Vector2i = entry["centroid"]
				print(
					"  #%d morti=%d pop_residua=%d territorio_centro=(%d,%d) celle=%d debito_residuo=%.1f" % [
						entry["group_id"], entry["deaths"], entry["population_after"],
						centroid.x, centroid.y, entry["cell_count"], entry["debt_after"]
					]
				)

	return deaths_by_species


# Stampa, per ogni cella del territorio del gruppo, terreno/bioma + disponibilità calorica per
# fonte (STESSA formula di AnimalBirthMitigationService._get_available_stock, ma per-cella invece
# di sommata sull'intero territorio, per vedere quale cella specifica è debole) + quali ALTRI
# gruppi (qualunque specie, non solo Livello 1) condividono la stessa cella — la contesa
# population_share di AnimalConsumptionAggregateService non è visibile altrove nel log, quindi
# senza questo elenco un debito cronico dovuto a un vicino affamato sulla stessa cella
# sembrerebbe indistinguibile da pura scarsità di vegetazione.
func _log_territory_diagnostics(world: World, group: PopulationGroup, rules: AnimalRules, season: GameTypes.Season) -> void:
	print(
		"[HUNGER MORTALITY DIAGNOSTICS] #%d %s territorio (%d celle):" % [
			group.id, group.species_name, group.territory.get_cell_count()
		]
	)
	for coords in group.territory.occupied_macrocells:
		var cell := world.get_cell_at(coords.x, coords.y)
		var state := world.get_cell_state_at(coords.x, coords.y)
		if cell == null or state == null:
			continue

		print(
			"  cella (%d,%d) terreno=%s bioma=%s" % [
				coords.x, coords.y,
				GameTypes.TerrainBase.keys()[cell.terrain_base],
				GameTypes.Biome.keys()[cell.biome],
			]
		)

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

			print(
				"    fonte=%s disponibile=%.1f calorie compatibilita=%.2f" % [
					source_name, available_calories, compatibility
				]
			)

		var sharing_groups: Array = []
		for other_group in world.population_groups:
			if other_group.id == group.id or other_group.population <= 0 or other_group.territory == null:
				continue
			if other_group.territory.contains(coords):
				sharing_groups.append(
					"#%d %s (pop=%d)" % [other_group.id, other_group.species_name, other_group.population]
				)
		if not sharing_groups.is_empty():
			print("    condivisa con: %s" % ", ".join(sharing_groups))
