class_name StatisticsSnapshotService
extends RefCounted

# Serie storiche del pannello statistiche (2026-10-25, raccolte qui da GameTimeService, GameSimulation e
# VillageCohesionService senza cambiarne il comportamento): un punto per anno in GameData, chiavi e formati invariati.
# Stateless.


# Istantanee dell'anno 0 (l'anno di partenza non "rotola" mai, quindi record_year_end non le scriverebbe): popolazione
# dei fondatori ed edifici (sempre 0 a inizio partita). Da GameSimulation.setup_population, solo per una partita nuova.
static func record_year_zero(game_data: GameData, individuals: Array[HumanIndividual]) -> void:
	game_data.population_snapshots[0] = individuals.size()
	game_data.building_snapshots[0] = 0
	var vital_percents := VitalsAverageService.average_percents(individuals)
	for parameter in vital_percents:
		game_data.vital_snapshots[parameter] = {0: vital_percents[parameter]}
	var skill_percents := VitalsAverageService.skill_average_percents(individuals)
	for skill in skill_percents:
		game_data.skill_snapshots[skill] = {0: skill_percents[skill]}


# Tutte le serie di fine anno, da GameTimeService._on_year_rolled_over: dopo il calo annuale della coesione, prima della
# determinazione della mortalità annuale. Influenze ed edifici prima li scriveva GameSimulation.tick_year, che gira
# nello stesso year_rolled_over ma prima di GameTimeService (GameScene si connette al segnale prima di start_time): a
# questo punto la crescita annuale delle influenze è già avvenuta, quindi i valori registrati sono gli stessi.
static func record_year_end(game_data: GameData, human_individuals: Array[HumanIndividual], folk: Folk, world: World) -> void:
	# Step 3 del piano statistiche (2026-09-06) — snapshot annuale della popolazione umana totale,
	# per il futuro grafico popolazione/anno del pannello statistiche: non ricavabile in modo
	# affidabile dai soli death_events/birth_events (dipenderebbe dal numero di fondatori iniziali
	# restare sempre corretto, fragile con un'eventuale futura immigrazione), quindi un log
	# dedicato, un punto per anno. Prima di GameTimeService._run_annual_human_mortality_determination:
	# vogliamo la popolazione COSÌ COM'È all'inizio dell'anno (year già incrementato da
	# GameData.advance_day prima che il segnale scattasse), prima che qualunque logica di
	# quest'anno (determinazione mortalità, coupling, concepimento, parto) la tocchi.
	game_data.population_snapshots[game_data.year] = human_individuals.size()
	# Stessa serie per villaggio (2026-10-12, statistiche filtrabili per villaggio).
	if folk != null:
		for village in folk.villages:
			if not game_data.village_population_snapshots.has(village.id):
				game_data.village_population_snapshots[village.id] = {}
			game_data.village_population_snapshots[village.id][game_data.year] = village.count_inhabitants(human_individuals)
	# Coesione (2026-10-14): il punto di fine anno, dopo il calo annuale.
	_record_cohesion_snapshots(folk, game_data)
	_record_average_snapshots(game_data, human_individuals, folk)
	_record_influence_snapshots(game_data, folk)
	_record_building_snapshots(game_data, folk, world)


# Un punto per villaggio e anno (GameData.village_cohesion_snapshots), dopo il calo: il valore di fine anno.
static func _record_cohesion_snapshots(folk: Folk, game_data: GameData) -> void:
	if folk == null or game_data == null:
		return
	for village in folk.villages:
		if not game_data.village_cohesion_snapshots.has(village.id):
			game_data.village_cohesion_snapshots[village.id] = {}
		game_data.village_cohesion_snapshots[village.id][game_data.year] = village.cohesion


# Medie di fine anno dei parametri e delle skill (2026-10-25, schede Parametri e Skill delle statistiche): del popolo e
# di ogni villaggio.
static func _record_average_snapshots(game_data: GameData, human_individuals: Array[HumanIndividual], folk: Folk) -> void:
	_store_snapshot_point(game_data, game_data.vital_snapshots, VitalsAverageService.average_percents(human_individuals))
	_store_snapshot_point(game_data, game_data.skill_snapshots, VitalsAverageService.skill_average_percents(human_individuals))
	if folk == null:
		return
	var by_village: Dictionary = {}  # Village.id -> Array[HumanIndividual]
	for individual in human_individuals:
		if individual.village_ref != null:
			if not by_village.has(individual.village_ref.id):
				by_village[individual.village_ref.id] = [] as Array[HumanIndividual]
			by_village[individual.village_ref.id].append(individual)
	for village in folk.villages:
		var members: Array[HumanIndividual] = by_village.get(village.id, [] as Array[HumanIndividual])
		if not game_data.village_vital_snapshots.has(village.id):
			game_data.village_vital_snapshots[village.id] = {}
		_store_snapshot_point(game_data, game_data.village_vital_snapshots[village.id], VitalsAverageService.average_percents(members))
		if not game_data.village_skill_snapshots.has(village.id):
			game_data.village_skill_snapshots[village.id] = {}
		_store_snapshot_point(game_data, game_data.village_skill_snapshots[village.id], VitalsAverageService.skill_average_percents(members))


# Scrive in `target` (chiave -> {anno -> valore}) il punto dell'anno in corso.
static func _store_snapshot_point(game_data: GameData, target: Dictionary, percents: Dictionary) -> void:
	for key in percents:
		if not target.has(key):
			target[key] = {}
		target[key][game_data.year] = percents[key]


# Storia dei valori R/C/P per la scheda Influenza delle statistiche: un punto per villaggio, tipo e anno.
static func _record_influence_snapshots(game_data: GameData, folk: Folk) -> void:
	if folk == null:
		return
	for village in folk.villages:
		if not game_data.village_influence_snapshots.has(village.id):
			game_data.village_influence_snapshots[village.id] = {}
		var by_type: Dictionary = game_data.village_influence_snapshots[village.id]
		for influence_type in InfluenceService.InfluenceType.values():
			if not by_type.has(influence_type):
				by_type[influence_type] = {}
			by_type[influence_type][game_data.year] = village.get_influence_value(influence_type)


# Istantanea degli edifici dell'anno (scheda Statistiche/Edifici, GameData.building_snapshots): solo completi, senza
# macerie né edifici di movimento (stesso criterio di "Edifici totali" in StatisticsPanel); la stessa serie per villaggio.
static func _record_building_snapshots(game_data: GameData, folk: Folk, world: World) -> void:
	var building_count := 0
	var village_building_counts: Dictionary = {}
	if folk != null:
		for village in folk.villages:
			village_building_counts[village.id] = 0
	if world != null:
		for building in world.buildings:
			if not building.is_complete or building.is_demolished or building.is_rubble():
				continue
			if building.rules == null or building.rules.category != BuildingTypes.Category.MOVEMENT:
				building_count += 1
				if village_building_counts.has(building.village_id):
					village_building_counts[building.village_id] += 1
	game_data.building_snapshots[game_data.year] = building_count
	for village_id in village_building_counts:
		if not game_data.village_building_snapshots.has(village_id):
			game_data.village_building_snapshots[village_id] = {}
		game_data.village_building_snapshots[village_id][game_data.year] = village_building_counts[village_id]
