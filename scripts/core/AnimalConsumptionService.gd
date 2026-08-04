class_name AnimalConsumptionService
extends RefCounted

const FORAGE_SOURCE_NAME := "forage"

# Consumo calorico giornaliero (non stagionale) per ogni gruppo animale, ripartito tra le celle
# del suo territorio (vedi _consume_group) e, dentro ciascuna cella, tra TUTTE le fonti con
# AnimalRules.diet_compatibility > 0 (FORAGE e le fonti a stock come BERRY/ACORN/FRUIT), pesato
# per calorie disponibili × compatibilità — vedi _consume_requirement_in_cell. Il fabbisogno non
# soddisfatto non ha ancora conseguenze (nessuna mortalità per fame): la popolazione consuma
# quello che trova e basta. Ritorna true se in
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

		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null:
			continue

		if _consume_group(world, group, rules, current_season):
			any_consumption_applied = true

	return any_consumption_applied


# Consumo di un intero gruppo sul suo territorio (Step 5: territori multi-cella). Il fabbisogno
# calorico TOTALE del gruppo (invariato, stessa _get_total_daily_requirement di sempre) viene
# ripartito tra le celle occupate in proporzione alla popolazione assegnata a ciascuna
# (PopulationGroup.get_population_by_cell — ripartizione uniforme oggi, vedi Territory), poi
# ritentato su ogni cella tramite _consume_requirement_in_cell. Il residuo NON soddisfatto da una
# cella (risorse locali insufficienti) viene ridistribuito sulle celle che quel turno hanno
# soddisfatto per intero la propria quota (unico segnale disponibile che potrebbero avere margine
# residuo) e ritentato — "water-filling" iterativo, converge in al più N round perché l'insieme
# delle celle candidate a ricevere altro residuo non può che restringersi o azzerare il residuo a
# ogni round. Il fabbisogno ancora scoperto dopo che nessuna cella ha più margine resta scoperto,
# nessuna nuova conseguenza (stesso comportamento di sempre — solo mitigazione natalità).
# Con territorio a una sola cella (sempre il caso di rabbit) degenera esattamente nel vecchio
# comportamento pre-Step 5: un solo round, nessuna redistribuzione possibile.
func _consume_group(
	world: World, group: PopulationGroup, rules: AnimalRules, current_season: GameTypes.Season
) -> bool:
	# coords tenuta dentro ogni entry (non solo l'indice nell'array): occupied_macrocells può
	# contenere coordinate non più valide (caso raro, difensivo), quindi cells_info può avere
	# MENO elementi di occupied_macrocells — l'indice `i` qui sotto indicizza SEMPRE cells_info,
	# mai occupied_macrocells direttamente, altrimenti i due andrebbero fuori sincrono.
	# Calcolato PRIMA di cells_info sotto (non dipende da esso) così è comunque disponibile per
	# group.set_daily_caloric_consumption anche nel ramo "nessuna cella valida" — il chiamante
	# (AnimalHungerService, tramite i log) vede sempre required coerente col vero fabbisogno del
	# gruppo, mai un placeholder.
	var total_requirement := _get_total_daily_requirement(group, rules)

	var cells_info: Array[Dictionary] = []
	for coords in group.territory.occupied_macrocells:
		var cell := world.get_cell_at(coords.x, coords.y)
		var state := world.get_cell_state_at(coords.x, coords.y)
		if cell == null or state == null:
			continue
		cells_info.append({"coords": coords, "cell": cell, "state": state})
	if cells_info.is_empty():
		# Nessuna cella valida su cui consumare: 0% del fabbisogno soddisfatto (a meno che
		# total_requirement stesso sia <= 0, nel qual caso set_daily_caloric_consumption
		# normalizza comunque il ratio a 1.0 — nessun fabbisogno = nessuna fame possibile).
		group.set_daily_caloric_consumption(0.0, total_requirement)
		return false

	if total_requirement <= 0.0:
		# Nessun fabbisogno = nessuna fame possibile: ratio neutro (gestito da
		# set_daily_caloric_consumption), stessa semantica di "nessuna penalità" usata altrove
		# (es. AnimalBirthMitigationService quando seasonal_requirement è 0).
		group.set_daily_caloric_consumption(0.0, 0.0)
		return false

	var population_by_cell := group.get_population_by_cell()
	var any_consumption_applied := false
	# Consumo TOTALE del gruppo su tutto il territorio, sommato attraverso celle e round di
	# ridistribuzione — mai un dato per singola cella isolata (vedi conferma utente). Diviso per
	# total_requirement a fine funzione per ottenere group.daily_caloric_ratio, riusato da
	# AnimalHungerService senza ricalcolare nulla.
	var total_consumed := 0.0

	# indice nell'array cells_info (non le coordinate) per tenere pesi/residui in Dictionary
	# ordinari con chiavi int, evitando ambiguità su Vector2i come chiave in più punti.
	var active_indices: Array = range(cells_info.size())
	var pending_requirement: Dictionary = {}
	for i in active_indices:
		var coords: Vector2i = cells_info[i]["coords"]
		var cell_population: int = int(population_by_cell.get(coords, 0))
		pending_requirement[i] = total_requirement * (float(cell_population) / float(group.population))

	var max_iterations: int = cells_info.size() + 1
	for iteration in range(max_iterations):
		if active_indices.is_empty():
			break

		var unmet_this_round: Dictionary = {}
		var round_total_unmet := 0.0

		for i in active_indices:
			var req: float = pending_requirement.get(i, 0.0)
			if req <= 0.0001:
				continue
			var info: Dictionary = cells_info[i]
			var result := _consume_requirement_in_cell(info["cell"], info["state"], rules, req, current_season)
			if result["applied"]:
				any_consumption_applied = true
			var unmet: float = result["unmet"]
			total_consumed += max(req - unmet, 0.0)
			if unmet > 0.0001:
				unmet_this_round[i] = unmet
				round_total_unmet += unmet

		if round_total_unmet <= 0.0001:
			break

		# Solo le celle che questo round hanno soddisfatto per intero la propria quota sono
		# candidate a ricevere il residuo — unico segnale disponibile che potrebbero avere ancora
		# margine, senza doverlo indovinare in anticipo.
		var recipients: Array = []
		for i in active_indices:
			if not unmet_this_round.has(i):
				recipients.append(i)
		if recipients.is_empty():
			break

		var recipient_weight_sum := 0.0
		var recipient_weights: Dictionary = {}
		for i in recipients:
			var coords: Vector2i = cells_info[i]["coords"]
			var weight: float = float(population_by_cell.get(coords, 0))
			if weight <= 0.0:
				weight = 1.0
			recipient_weights[i] = weight
			recipient_weight_sum += weight

		pending_requirement.clear()
		for i in recipients:
			pending_requirement[i] = round_total_unmet * (recipient_weights[i] / recipient_weight_sum)
		active_indices = recipients

	group.set_daily_caloric_consumption(total_consumed, total_requirement)
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


# Costruisce le fonti pesate per una specie/cella e ripartisce `requirement` (fabbisogno già
# assegnato a QUESTA cella — la quota del gruppo su multi-cella, vedi _consume_group, oppure il
# fabbisogno totale invariato quando il territorio ha una sola cella) tra di esse. Fonti con
# diet_compatibility <= 0 vengono escluse SENZA interrogare CaloricCalculator (peso comunque
# nullo, calcolo sprecato). Ritorna {"applied": bool (almeno una fonte ha fornito qualcosa,
# weight_sum > 0), "unmet": float (quota di requirement non soddisfatta, usata da _consume_group
# per la redistribuzione)}.
func _consume_requirement_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	rules: AnimalRules,
	requirement: float,
	current_season: GameTypes.Season
) -> Dictionary:
	var weighted_sources: Array[Dictionary] = []
	var weight_sum := 0.0

	for source_name in rules.diet_compatibility.keys():
		var compatibility := float(rules.diet_compatibility[source_name])
		if compatibility <= 0.0:
			continue

		var source_rules := CaloricCalculator.get_caloric_source_rules(source_name)
		if source_rules == null or source_rules.calories_per_unit <= 0.0:
			continue

		var available_calories: float
		if source_name == FORAGE_SOURCE_NAME:
			available_calories = CaloricCalculator.get_forage_available_calories(cell, state, current_season)
		else:
			available_calories = CaloricCalculator.get_secondary_resource_stock_calories(state, source_name)

		var weight := available_calories * compatibility
		if weight <= 0.0:
			continue

		weighted_sources.append({
			"name": source_name,
			"weight": weight,
			"rules": source_rules,
		})
		weight_sum += weight

	var total_consumed_calories := 0.0
	if weight_sum > 0.0:
		for source in weighted_sources:
			var source_name: String = source["name"]
			var source_weight: float = source["weight"]
			var source_rules: CaloricSourceRules = source["rules"]

			var share: float = requirement * (source_weight / weight_sum)
			# Tetto = source_weight (= calorie_disponibili × compatibility), NON le calorie
			# disponibili grezze: compatibility non è solo un peso di ripartizione tra più fonti
			# simultanee, è anche un tetto reale a quanto di QUESTA fonte è accessibile in un
			# giorno, indipendentemente da quanto ce n'è fisicamente. Con un'unica fonte disponibile
			# (weight_sum == source_weight), share collassa sempre su tutto il requirement — capparlo
			# alla disponibilità grezza avrebbe fatto consumare (e sottrarre dal mondo) più calorie di
			# quelle davvero accessibili. L'eccedenza non coperta finisce in `unmet`, che alimenta la
			# redistribuzione sulle altre celle del territorio invece di sparire nel nulla.
			var consumed_calories: float = min(share, source_weight)
			var units_consumed: float = consumed_calories / source_rules.calories_per_unit

			if source_name == FORAGE_SOURCE_NAME:
				# Il valore di ritorno (spazio GRASS davvero decrementato) non serve più al
				# chiamante: il segnale "consumo avvenuto" oggi è weight_sum > 0, qualunque sia
				# la fonte — vedi apply_daily_consumption.
				_consume_forage(cell, state, units_consumed)
			else:
				var before := state.get_secondary_resource_stock(source_name)
				state.set_secondary_resource_stock(source_name, before - units_consumed)

			total_consumed_calories += consumed_calories

	var unmet: float = max(requirement - total_consumed_calories, 0.0)
	return {"applied": weight_sum > 0.0, "unmet": unmet}


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
