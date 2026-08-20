class_name PopulationSplitService
extends RefCounted

# Scissione di un PopulationGroup (Step 9 del refactoring fauna): quando un tentativo di
# espansione territorio fallisce (TerritoryBuilderService.expand_by_one_cell -> false, per
# qualunque motivo — territorio già a max_territory_cells o BFS satura, i due chiamanti non
# distinguono il motivo, vedi TerritoryDynamicsService/AnimalHungerService), prova a staccare
# una porzione della popolazione in un nuovo PopulationGroup indipendente altrove, PRIMA di
# lasciare che la sola pressione calorica/fame gestisca la situazione. Nessuna soglia minima di
# frequenza per ora (nessun cooldown tra scissioni): si osserva empiricamente il comportamento
# prima di introdurre eventuali freni.
#
# Erbivori: il nuovo gruppo nasce SEMPRE con territorio a UNA SOLA CELLA, indipendentemente da
# min_territory_cells della specie (anche per deer, min_territory_cells=3): si espanderà nel
# tempo secondo le normali regole di TerritoryDynamicsService/AnimalHungerService se/quando la
# sua popolazione lo giustificherà, stesso percorso di qualunque altro gruppo esistente — nessuna
# eccezione hardcoded per la provenienza "da scissione".
#
# Predatori: eccezione a quanto sopra (vedi il blocco `if rules is PredatorRules` dentro
# attempt_split) — nascono già dimensionati al fabbisogno reale di chi si stacca (stessa formula
# di TerritoryDynamicsService per l'espansione), mai a 1 cella: senza AnimalHungerService per loro,
# un branco a 1 cella non avrebbe alcuna occasione quotidiana di rimediare prima di morire di fame.
# Se non si trova abbastanza spazio, l'intero split fallisce (nessun branco nato già condannato).
const MIN_DISPERSAL_SHARE_FRACTION := 0.05


# `requested_amount` è già calcolato dal chiamante (formula diversa per trigger di densità/
# calorico stagionale vs fame giornaliera, vedi TerritoryDynamicsService/AnimalHungerService) —
# qui si clampa solo a [1, population - 1], mai ricalcolato. `trigger_reason` è solo per il log
# (vedi sotto) — non influenza in alcun modo la logica di split, puramente descrittivo di COSA ha
# fatto fallire l'espansione a monte (densità/calorico stagionale/fame giornaliera), così il log
# resta leggibile senza dover incrociare a mano il checkpoint di origine. Ritorna true se lo split
# è riuscito (nuovo gruppo creato e aggiunto a world.population_groups), false se non c'è
# popolazione sufficiente o nessuna cella libera raggiungibile (silenzioso, non un errore — il
# gruppo di origine resta invariato, stesso trattamento del fallimento di expand_by_one_cell).
func attempt_split(
	world: World, group: PopulationGroup, rules: AnimalRules, requested_amount: int, trigger_reason: String
) -> bool:
	if group.population <= 1:
		return false

	var amount: int = clamp(requested_amount, 1, group.population - 1)

	var found_cell = TerritoryBuilderService.new().find_nearest_free_cell(world, group.territory, group.species_name)
	if found_cell == null:
		# SHOW_HERBIVORE_LIFECYCLE_LOGS: stesso flag usato altrove per silenziare i log di ciclo
		# vita degli erbivori mentre si valida la sola natalità/mortalità dei lupi — qui filtra i
		# tre print di attempt_split (questo, quello sotto per territorio insufficiente — già
		# implicitamente solo predatori, dentro `if rules is PredatorRules` — e quello finale di
		# successo), mai i predatori.
		if DebugLogging.ENABLED and (rules is PredatorRules or DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS):
			print(
				"[POPULATION SPLIT] #%d %s pop=%d trigger=%s tentativo fallito: nessuna cella libera raggiungibile" % [
					group.id, group.species_name, group.population, trigger_reason
				]
			)
		return false

	# Predatori: il nuovo branco NON nasce a 1 sola cella come gli erbivori — senza
	# AnimalHungerService (che per i predatori è escluso, vedi AnimalHungerService.apply_daily_hunger)
	# l'unica occasione annuale di TerritoryDynamicsService per aggiustare il territorio sarebbe
	# troppo rada: un branco a 1 cella morirebbe di fame ben prima del prossimo checkpoint, senza
	# alcuna leva quotidiana per rimediare. target_cells riusa la STESSA formula di
	# TerritoryDynamicsService._update_group_territory (clamp del fabbisogno di densità tra min/max
	# etologici), calcolata su `amount` (gli individui che si staccano davvero), non sulla
	# popolazione del branco d'origine — così il nuovo territorio è sempre corretto per chi ci
	# abiterà, anche quando supera min_territory_cells (es. uno split del 50% di un branco numeroso).
	# build_territory di per sé non fallisce mai (restituisce il meglio trovato anche se incompleto),
	# quindi il controllo esplicito sotto: se non trova abbastanza spazio, lo split fallisce DEL
	# TUTTO (stesso trattamento di "nessuna cella libera" sopra) invece di far nascere un branco già
	# condannato — nessuna mutazione del gruppo d'origine avvenuta finora, niente da annullare.
	var new_territory: Territory
	if rules is PredatorRules:
		var target_cells: int = clamp(
			int(ceil(float(amount) / rules.max_density_per_cell)), rules.min_territory_cells, rules.max_territory_cells
		)
		new_territory = TerritoryBuilderService.new().build_territory(world, found_cell, target_cells, group.species_name)
		if new_territory.get_cell_count() < target_cells:
			if DebugLogging.ENABLED:
				print(
					(
						"[POPULATION SPLIT] #%d %s pop=%d trigger=%s tentativo fallito: territorio "
						+ "insufficiente per un nuovo branco vitale (%d/%d celle trovate)"
					) % [
						group.id, group.species_name, group.population, trigger_reason,
						new_territory.get_cell_count(), target_cells
					]
				)
			return false
	else:
		new_territory = Territory.from_single_cell(found_cell)

	var departing_age := _compute_departing_age(group, rules, amount)
	var departing_hunger: Dictionary = MacroCellState._split_by_weight_capped(
		group.hunger_buckets, group.hunger_buckets, amount
	)
	# Predatori: il ledger calorico (PredationService.predation_calorie_debt/
	# predation_surplus_carryover) è un debito/surplus COLLETTIVO del branco, non riconducibile a
	# singoli individui — va diviso proporzionalmente alla quota che si stacca (amount/population
	# PRIMA dello split, non un fisso 50%: split_amount può superare la metà nei casi di
	# sovraffollamento severo, vedi TerritoryDynamicsService), così il debito/surplus PRO CAPITE
	# resta identico per entrambi i gruppi dopo lo split — mai concentrato sul solo gruppo d'origine
	# (che altrimenti si ritroverebbe lo stesso debito totale con metà degli individui a ripianarlo)
	# né azzerato gratuitamente sul nuovo (un "colpo di spugna" che premierebbe lo split invece di
	# limitarsi a ridistribuirne le conseguenze). Stesso principio già usato per hunger_buckets
	# sopra, qui su due scalari invece che su un dizionario pesato. Calcolato PRIMA di
	# group.set_population sotto: serve il population di PRIMA dello split come denominatore.
	var departing_calorie_debt := 0.0
	var departing_surplus_carryover := 0.0
	if rules is PredatorRules:
		var departing_share: float = float(amount) / float(group.population)
		departing_calorie_debt = group.predation_calorie_debt * departing_share
		departing_surplus_carryover = group.predation_surplus_carryover * departing_share
		group.predation_calorie_debt -= departing_calorie_debt
		group.predation_surplus_carryover -= departing_surplus_carryover

	for age_band in departing_age.keys():
		group.set_age_count(age_band, group.get_age_count(age_band) - int(departing_age[age_band]))
	for day in departing_hunger.keys():
		group.set_hunger_bucket_count(day, group.get_hunger_bucket_count(day) - int(departing_hunger[day]))
	group.set_population(group.population - amount)
	# Countdown di recovery post-scissione (Step 10, vedi TerritoryDynamicsService.
	# _get_post_split_multiplier): riazzerato sul gruppo di ORIGINE ad ogni split, mai sul nuovo
	# gruppo sotto (che resta al proprio default -1, "mai scisso").
	group.years_since_last_split = 0

	var new_group := PopulationGroup.new(group.species_name, new_territory, world.allocate_population_group_id())
	for age_band in departing_age.keys():
		new_group.set_age_count(age_band, int(departing_age[age_band]))
	for day in departing_hunger.keys():
		new_group.set_hunger_bucket_count(day, int(departing_hunger[day]))
	if rules is PredatorRules:
		new_group.predation_calorie_debt = departing_calorie_debt
		new_group.predation_surplus_carryover = departing_surplus_carryover
		# Territorio del tutto nuovo (mai pattugliato prima) -> reset_progress=true di default resta
		# corretto qui, nessuna posizione precedente da preservare (Step 7, a differenza del caso
		# espansione/contrazione in TerritoryDynamicsService, che usa invece
		# recompute_route_preserving_position).
		PredatorPatrolService.new().recompute_route(new_group, rules as PredatorRules)
	new_group.set_population(amount)
	world.population_groups.append(new_group)

	if DebugLogging.ENABLED and (rules is PredatorRules or DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS):
		print(
			(
				"[POPULATION SPLIT] #%d %s pop=%d->%d trigger=%s scissione di %d individui "
				+ "age(Y=%d,A=%d,O=%d) -> nuovo gruppo #%d in (%d,%d)"
			) % [
				group.id, group.species_name, group.population + amount, group.population, trigger_reason, amount,
				int(departing_age.get(GameTypes.AgeBand.YOUNG, 0)),
				int(departing_age.get(GameTypes.AgeBand.ADULT, 0)),
				int(departing_age.get(GameTypes.AgeBand.OLD, 0)),
				new_group.id, found_cell.x, found_cell.y,
			]
		)

	return true


# Ripartisce `amount` tra le fasce d'età secondo AnimalRules.dispersal_share_by_age, riproporzionando
# sulle fasce con capienza residua quando una non ne ha abbastanza (stesso "water-filling" capped
# già usato da PopulationGroup.apply_old_age_mortality/apply_hunger_mortality per lo stesso
# problema). Specie senza track_age_bands (o gruppo con age_composition non ancora popolata)
# restano un contatore piatto, stesso fallback usato altrove: dizionario vuoto, population
# spostata senza age_composition da aggiornare né nel gruppo di origine né in quello nuovo.
func _compute_departing_age(group: PopulationGroup, rules: AnimalRules, amount: int) -> Dictionary:
	if not rules.track_age_bands or group.get_age_total() <= 0:
		return {}

	var weights: Dictionary = {
		GameTypes.AgeBand.YOUNG: rules.dispersal_share_by_age[0],
		GameTypes.AgeBand.ADULT: rules.dispersal_share_by_age[1],
		GameTypes.AgeBand.OLD: rules.dispersal_share_by_age[2],
	}
	var caps: Dictionary = {
		GameTypes.AgeBand.YOUNG: group.get_age_count(GameTypes.AgeBand.YOUNG),
		GameTypes.AgeBand.ADULT: group.get_age_count(GameTypes.AgeBand.ADULT),
		GameTypes.AgeBand.OLD: group.get_age_count(GameTypes.AgeBand.OLD),
	}
	return MacroCellState._split_by_weight_capped(weights, caps, amount)
