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
# Il nuovo gruppo nasce SEMPRE con territorio a UNA SOLA CELLA, indipendentemente da
# min_territory_cells della specie (anche per deer, min_territory_cells=3): si espanderà nel
# tempo secondo le normali regole di TerritoryDynamicsService/AnimalHungerService se/quando la
# sua popolazione lo giustificherà, stesso percorso di qualunque altro gruppo esistente — nessuna
# eccezione hardcoded per la provenienza "da scissione".
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
		if DebugLogging.ENABLED:
			print(
				"[POPULATION SPLIT] #%d %s pop=%d trigger=%s tentativo fallito: nessuna cella libera raggiungibile" % [
					group.id, group.species_name, group.population, trigger_reason
				]
			)
		return false

	var departing_age := _compute_departing_age(group, rules, amount)
	var departing_hunger: Dictionary = MacroCellState._split_by_weight_capped(
		group.hunger_buckets, group.hunger_buckets, amount
	)

	for age_band in departing_age.keys():
		group.set_age_count(age_band, group.get_age_count(age_band) - int(departing_age[age_band]))
	for day in departing_hunger.keys():
		group.set_hunger_bucket_count(day, group.get_hunger_bucket_count(day) - int(departing_hunger[day]))
	group.set_population(group.population - amount)
	# Countdown di recovery post-scissione (Step 10, vedi TerritoryDynamicsService.
	# _get_post_split_multiplier): riazzerato sul gruppo di ORIGINE ad ogni split, mai sul nuovo
	# gruppo sotto (che resta al proprio default -1, "mai scisso").
	group.years_since_last_split = 0

	var new_territory := Territory.from_single_cell(found_cell)
	var new_group := PopulationGroup.new(group.species_name, new_territory, world.allocate_population_group_id())
	for age_band in departing_age.keys():
		new_group.set_age_count(age_band, int(departing_age[age_band]))
	for day in departing_hunger.keys():
		new_group.set_hunger_bucket_count(day, int(departing_hunger[day]))
	new_group.set_population(amount)
	world.population_groups.append(new_group)

	if DebugLogging.ENABLED:
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
