class_name WorldTimeService
extends RefCounted

# Advances the calendar by exactly one day, then runs whichever seasonal simulation
# checkpoint(s) fall on the resulting day (see _run_seasonal_checkpoints), plus the animal
# consumption pass (see _run_daily_animal_consumption), che a differenza dei checkpoint
# stagionali gira OGNI giorno, non solo ai confini di stagione. Ritorna le due cause di
# cambiamento separate (non fuse in un solo bool) così i chiamanti che vogliono trattarle
# diversamente — vedi MacroCellScene, che ridisegna sempre ai checkpoint stagionali ma
# l'aggiornamento guidato dal solo consumo animale lo rende opzionale — possono farlo senza
# dover indovinare quale delle due è effettivamente scattata.
func advance_day(world: World, game_data: GameData) -> Dictionary:
	var year_rolled_over := game_data.advance_day()
	var animals_changed := _run_daily_animal_consumption(world, game_data)
	# Caccia dei predatori (Step 3 del piano predatori) — gira OGNI giorno come il consumo
	# erbivoro sopra, indipendente dai checkpoint stagionali, e PRIMA di questi ultimi: una preda
	# catturata oggi deve già risultare decrementata quando gli eventuali checkpoint di oggi
	# (nascite/maturazione/territorio) leggono la sua popolazione, mai lo stato di ieri. Anche
	# PRIMA di _run_daily_animal_hunger sotto (che gira comunque dopo i checkpoint stagionali,
	# vedi ordine esistente): PopulationGroup.apply_predation_loss non tocca hunger_buckets della
	# preda, la riconciliazione con population se ne occupa la prossima volta che
	# AnimalHungerService gira su quel gruppo — stesso giorno, con questo ordine.
	_run_daily_predation(world, game_data)
	var checkpoint_ran := _run_seasonal_checkpoints(world, game_data, year_rolled_over)
	# DOPO i checkpoint stagionali (mai prima): se oggi capita anche un checkpoint di fine
	# birth_season (nascite/morte per vecchiaia), hunger_buckets viene già mantenuto coerente con
	# population da PopulationGroup.apply_births/apply_old_age_mortality PRIMA che questo servizio
	# legga population — vedi AnimalHungerService.
	_run_daily_animal_hunger(world)
	# ULTIMO passo della giornata, dopo ogni checkpoint che può azzerare population (morte per
	# vecchiaia sopra, fame prolungata appena sopra) — mai prima, altrimenti un gruppo morto oggi
	# stesso resterebbe nell'array (e quindi "occupante" la propria cella) fino a domani. Vedi
	# World.remove_extinct_population_groups per il perché.
	world.remove_extinct_population_groups()
	return {"checkpoint_ran": checkpoint_ran, "animals_changed": animals_changed}


# Gira ogni giorno (non solo ai checkpoint stagionali): il fabbisogno calorico degli animali
# non aspetta il cambio di stagione. Vedi AnimalConsumptionService per la formula.
func _run_daily_animal_consumption(world: World, game_data: GameData) -> bool:
	var current_season := SeasonCalculator.get_season_for_day(game_data.current_day)
	return AnimalConsumptionService.new().apply_daily_consumption(world, current_season)


# Gira ogni giorno, indipendente da birth_season, esattamente come _run_daily_animal_consumption
# sopra — ma per i predatori (vedi PredationService), non per gli erbivori. year/current_day
# passati per popolare PopulationGroup.recent_hunt_log/yearly_prey_totals (tab Fauna 3, UI) —
# letti DOPO game_data.advance_day() già chiamato sopra in questo stesso metodo, quindi riflettono
# già la data di OGGI, non quella di ieri.
func _run_daily_predation(world: World, game_data: GameData) -> void:
	PredationService.new().apply_daily_predation(world, game_data.year, game_data.current_day)


# Gira ogni giorno, indipendente da birth_season (vedi AnimalHungerService): legge
# group.daily_caloric_ratio già calcolato sopra da _run_daily_animal_consumption, non lo
# ricalcola.
func _run_daily_animal_hunger(world: World) -> void:
	AnimalHungerService.new().apply_daily_hunger(world)

# Debug/emergency fast-forward (the "+1" button): advances a full 365 days one at a time (via
# advance_day) so every seasonal checkpoint crossed along the way still runs, in chronological
# order, exactly once — instead of jumping straight to day 0 and running everything at once.
func force_advance_to_year_end(world: World, game_data: GameData) -> void:
	for i in range(GameData.DAYS_PER_YEAR):
		advance_day(world, game_data)

# Dispatches to the seasonal pipeline steps whose checkpoint day matches game_data.current_day:
#   - start of spring: apply last autumn's pending migration surplus (compute + apply transfers)
#   - end of each season: animal lifecycle (age-band maturation, then births) for whichever
#     species have that AnimalRules.birth_season (see AnimalAgeBandService/AnimalBirthService)
#     — always before that day's other sibling checkpoint, and maturation always before births
#     within the lifecycle checkpoint itself, so this year's newborns never mature the same
#     cycle they're born in — same principle as vegetation's age-band maturation before growth
#   - end of spring: growth + encroachment, leftover surplus stored as this year's pending surplus
#   - start of each season: evaluate natural event types whose reference_season matches
#   - start of each season: for every multi-cell animal territory (any species, not gated by
#     birth_season), reshuffle the random per-cell population weights (visual only — see
#     PopulationTerritoryShuffleService)
#   - end of autumn (year rollover): mortality
# Order within a shared day matters only for SPRING's start (migration before any future
# spring-referenced event type), chosen to mirror the original pipeline's resource-then-events
# ordering.
func _run_seasonal_checkpoints(world: World, game_data: GameData, year_rolled_over: bool) -> bool:
	var day := game_data.current_day
	var checkpoint_ran := false

	if day == SeasonCalculator.get_season_day_range(GameTypes.Season.SPRING).x:
		_run_timed("migration_checkpoint", func(): _run_migration_checkpoint(world, game_data))
		checkpoint_ran = true

	# Nessun'altra logica gira ancora a fine inverno: blocco dedicato solo alle specie animali
	# con birth_season == WINTER (nessuna oggi, ma il checkpoint deve esistere comunque).
	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.WINTER):
		_run_timed("animal_lifecycle_checkpoint(WINTER)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.WINTER))
		checkpoint_ran = true

	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.SPRING):
		_run_timed("animal_lifecycle_checkpoint(SPRING)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.SPRING))
		_run_timed("growth_checkpoint", func(): _run_growth_checkpoint(world, game_data))
		checkpoint_ran = true

	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.SUMMER):
		_run_timed("animal_lifecycle_checkpoint(SUMMER)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.SUMMER))
		_run_timed("fauna_migration_checkpoint", func(): _run_fauna_migration_checkpoint(world))
		checkpoint_ran = true

	for season in [GameTypes.Season.WINTER, GameTypes.Season.SPRING, GameTypes.Season.SUMMER, GameTypes.Season.AUTUMN]:
		if day == SeasonCalculator.get_season_day_range(season).x:
			_run_timed(
				"secondary_resource_stock_checkpoint",
				func(): _run_secondary_resource_stock_checkpoint(world, SeasonCalculator.get_previous_season(season), season)
			)
			_run_timed("natural_events_checkpoint", func(): _run_natural_events_checkpoint(world, game_data, season))
			# Step 8 del refactoring fauna: territorio ed espansione/contrazione girano nello
			# STESSO checkpoint di inizio birth_season in cui girava già (da solo) il calcolo del
			# ratio calorico per la mitigazione natalità — i due condividono la stessa identica
			# definizione di scarsità (vedi TerritoryDynamicsService), quindi la mitigazione non è
			# più un checkpoint a sé: è orchestrata da TerritoryDynamicsService stesso, DOPO
			# l'eventuale aggiustamento del territorio, mai prima.
			_run_timed("territory_dynamics_checkpoint", func(): _run_territory_dynamics_checkpoint(world, season))
			_run_timed("animal_territory_shuffle_checkpoint", func(): _run_animal_territory_shuffle_checkpoint(world, season))
			checkpoint_ran = true

	if year_rolled_over:
		# AUTUMN "end of season" non può essere un confronto sul giorno (current_day è già
		# tornato a 0 quando year_rolled_over è true, vedi GameData.advance_day) — year_rolled_over
		# stesso è il segnale di fine autunno, stesso schema già usato da _run_mortality_checkpoint.
		_run_timed("animal_lifecycle_checkpoint(AUTUMN)", func(): _run_animal_lifecycle_checkpoint(world, GameTypes.Season.AUTUMN))
		_run_timed("mortality_checkpoint", func(): _run_mortality_checkpoint(world))
		checkpoint_ran = true

	return checkpoint_ran


# TEMPORANEO — diagnostica per isolare quale funzione del checkpoint stagionale è responsabile
# del rallentamento segnalato tra giorno 181 e 182 (Step 11): misura e stampa il tempo di ogni
# passo (Time.get_ticks_usec, non affetto da eventuale vsync/frame limiting). Gated da
# DebugLogging.ENABLED come il resto della diagnostica — va rimossa una volta individuata la
# causa. `action` viene sempre eseguita (il gate riguarda solo la stampa del tempo, mai il
# lavoro reale).
func _run_timed(label: String, action: Callable) -> void:
	var start_usec := Time.get_ticks_usec()
	action.call()
	if DebugLogging.ENABLED:
		pass
		#print("[TIMING] %s: %.2f ms" % [label, (Time.get_ticks_usec() - start_usec) / 1000.0])


func _run_animal_lifecycle_checkpoint(world: World, season: GameTypes.Season) -> void:
	# Ordine fisso: maturazione -> nascite -> morte per vecchiaia. Maturazione PRIMA, nascite
	# DOPO — così i nuovi nati (sempre aggiunti in YOUNG da AnimalBirthService) non maturano mai
	# nello stesso ciclo in cui compaiono, garantito strutturalmente dall'ordine di chiamata qui,
	# non da un controllo a parte. Morte per vecchiaia PER ULTIMA: include anche gli individui
	# appena entrati in OLD in questo stesso checkpoint (la maturazione adult->old gira prima,
	# sopra) — nessuno stato "appena arrivato" viene tracciato da nessuna transizione di fascia,
	# quindi non lo tracciamo neanche per la mortalità (vedi AnimalOldAgeMortalityService).
	_run_timed("  mature_age_bands (animali)", func(): AnimalAgeBandService.new().mature_age_bands(world, season))
	_run_timed("  apply_births", func(): AnimalBirthService.new().apply_births(world, season))
	_run_timed("  apply_old_age_mortality", func(): AnimalOldAgeMortalityService.new().apply_old_age_mortality(world, season))


func _run_growth_checkpoint(world: World, game_data: GameData) -> void:
	# Maturazione PRIMA di growth/encroachment: opera sulla composizione young/adult/old
	# ereditata dagli anni precedenti, cosicché le nascite di growth in questo stesso ciclo
	# (età 0) non vengano mai incluse nella maturazione dello stesso anno in cui compaiono —
	# vedi ResourceAgeBandService.
	_run_timed("  mature_age_bands (vegetazione)", func(): ResourceAgeBandService.new().mature_age_bands(world))

	_run_timed("  grow_resources", func(): ResourceGrowthService.new().grow_resources(world, game_data))

	# Step 11 Step 4: mitigazione dell'encroachment da presenza fisica di fauna brucante (densità
	# di riempimento per cella rispetto ad AnimalRules.max_density_per_cell) — vedi
	# BrowsingMitigationService. Il risultato è ora un INPUT REALE per encroach_resources sotto
	# (non più solo calcolo/log): gira quindi SEMPRE, non gated da DebugLogging.ENABLED. Il
	# prototipo calorico precedente (GrazingPressureService, scartato: la scarsità calorica è già
	# coperta altrove da fame/mortalità) è stato rimosso in una sessione precedente.
	# Non passata tramite _run_timed: serve il valore di ritorno, misurata quindi a mano — stesso
	# schema di encroach_resources sotto.
	var browsing_start_usec := Time.get_ticks_usec()
	var browsing_mitigation := BrowsingMitigationService.new().compute_browsing_mitigation(world)
	if DebugLogging.ENABLED:
		pass
		#print("[TIMING]   compute_browsing_mitigation: %.2f ms" % [(Time.get_ticks_usec() - browsing_start_usec) / 1000.0])

	var encroach_start_usec := Time.get_ticks_usec()
	var encroachment_service := ResourceEncroachmentService.new()
	var leftover_surplus := encroachment_service.encroach_resources(world, browsing_mitigation)
	if DebugLogging.ENABLED:
		pass
		#print("[TIMING]   encroach_resources: %.2f ms" % [(Time.get_ticks_usec() - encroach_start_usec) / 1000.0])
	_store_pending_migration_surplus(world, leftover_surplus)

	# FISH cresce sullo stesso checkpoint di fine primavera della vegetazione, ma su un budget
	# separato (water_dedicated_space): nessuna interazione con
	# encroachment/pending_migration_surplus terrestri. Migration e mortality per FISH sono
	# invece in checkpoint propri (fine estate/fine autunno, vedi sotto) — a differenza della
	# vegetazione, growth->migration->mortality per FISH restano tre momenti separati dell'anno
	# invece che un'unica pipeline diretta, per poter osservare l'evoluzione di ciascuna fase.
	_run_timed("  grow_fauna", func(): FaunaGrowthService.new().grow_fauna(world))


# Fine estate: unico checkpoint per la migrazione FISH, nessuno sfasamento all'anno successivo
# come lo schema "seed bank" della vegetazione (_run_migration_checkpoint sotto).
func _run_fauna_migration_checkpoint(world: World) -> void:
	FaunaMigrationService.new().migrate_fauna(world)


func _run_mortality_checkpoint(world: World) -> void:
	var mortality_service := ResourceMortalityService.new()
	mortality_service.apply_mortality(world)

	# Stesso checkpoint di fine autunno (year_rolled_over) della mortalità vegetale, su
	# water_dedicated_space invece che dedicated_space.
	FaunaMortalityService.new().apply_fauna_mortality(world)


# A inizio di ogni stagione (stesso giorno degli altri checkpoint "start of season" sopra): per
# le specie con birth_season == season, valuta espansione/contrazione del territorio e poi
# calcola il moltiplicatore di mitigazione della natalità legato alla disponibilità calorica —
# in quest'ordine, sullo stesso ratio calorico condiviso (vedi TerritoryDynamicsService). Il
# moltiplicatore risultante resta memorizzato sul gruppo fino al checkpoint di nascita già
# esistente, a fine birth_season.
func _run_territory_dynamics_checkpoint(world: World, season: GameTypes.Season) -> void:
	TerritoryDynamicsService.new().update_territories_and_mitigation(world, season)


func _run_migration_checkpoint(world: World, game_data: GameData) -> void:
	var migration_service := ResourceMigrationService.new()
	var leftover_surplus := _collect_pending_migration_surplus(world)
	var transfers := migration_service.compute_transfers(world, leftover_surplus)
	migration_service.apply_transfers(world, transfers)
	_clear_pending_migration_surplus(world)


func _run_natural_events_checkpoint(world: World, game_data: GameData, season: GameTypes.Season) -> void:
	var natural_event_service := NaturalEventService.new()
	natural_event_service.trigger_events(world, game_data, season)


# Stesso giorno "inizio stagione" del checkpoint sopra, ma NON filtrato per AnimalRules.
# birth_season: si applica a ogni gruppo con territorio multi-cella a ogni cambio stagione (4
# volte/anno), non solo alla propria stagione di nascita — qui la stagione è solo il ritmo del
# rimescolamento visivo, non legata al ciclo riproduttivo di una specie (vedi
# PopulationTerritoryShuffleService, Step 6 del refactoring fauna).
func _run_animal_territory_shuffle_checkpoint(world: World, season: GameTypes.Season) -> void:
	PopulationTerritoryShuffleService.new().shuffle_distribution(world, season)


# Nessun vero registro di fonti a stock persistente esiste ancora (nessuna scansione automatica
# dei .tres in data/caloric_sources/) — solo questo elenco hardcoded delle fonti oggi
# implementate con la rispettiva risorsa primaria. Aggiungere una nuova fonte a stock persistente
# richiede una riga qui, a mano.
const _SECONDARY_SOURCES := [
	{"resource_name": "berry", "primary_resource_type": GameTypes.WorldObjectType.SHRUB},
	{"resource_name": "acorn", "primary_resource_type": GameTypes.WorldObjectType.TREE},
	{"resource_name": "fruit", "primary_resource_type": GameTypes.WorldObjectType.TREE},
	{"resource_name": "eggs", "primary_resource_type": GameTypes.WorldObjectType.BIRDS},
]

func _run_secondary_resource_stock_checkpoint(
	world: World, previous_season: GameTypes.Season, new_season: GameTypes.Season
) -> void:
	for source in _SECONDARY_SOURCES:
		var rules := CaloricCalculator.get_caloric_source_rules(source["resource_name"])
		if rules == null:
			continue
		for state in world.cell_states:
			var cell := world.get_cell_at(state.x, state.y)
			if cell == null:
				continue
			CaloricCalculator.update_secondary_resource_stock(
				rules, cell, state, source["primary_resource_type"], previous_season, new_season
			)


func _store_pending_migration_surplus(world: World, leftover_surplus: Dictionary) -> void:
	for cell_key in leftover_surplus.keys():
		var state := world.get_cell_state_at(cell_key.x, cell_key.y)
		if state == null:
			continue
		for resource_type in leftover_surplus[cell_key].keys():
			var surplus_quantity = leftover_surplus[cell_key][resource_type]
			state.pending_migration_surplus[resource_type] = surplus_quantity
			#if DebugLogging.ENABLED and cell_key.x == 50 and cell_key.y == 50:
			#	print("[SURPLUS SAVED 50,50] %s: %.3f accantonato" % [
			#		GameTypes.WorldObjectType.keys()[resource_type], surplus_quantity
			#	])


func _collect_pending_migration_surplus(world: World) -> Dictionary:
	var leftover_surplus: Dictionary = {}
	for state in world.cell_states:
		if state.pending_migration_surplus.is_empty():
			continue
		#if DebugLogging.ENABLED and state.x == 50 and state.y == 50:
		#	for resource_type in state.pending_migration_surplus.keys():
		#		print("[SURPLUS APPLIED 50,50] %s: %.3f applicato" % [
		#			GameTypes.WorldObjectType.keys()[resource_type], state.pending_migration_surplus[resource_type]
		#		])
		leftover_surplus[Vector2i(state.x, state.y)] = state.pending_migration_surplus.duplicate()
	return leftover_surplus


func _clear_pending_migration_surplus(world: World) -> void:
	for state in world.cell_states:
		state.pending_migration_surplus.clear()
