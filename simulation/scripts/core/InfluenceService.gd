class_name InfluenceService
extends RefCounted

# Influenza politica, culturale e religiosa degli edifici (2026-10-02, richiesta utente) — service statico, stesso
# pattern degli altri *Service; l'unico stato è la cache della copertura delle case (vedi sotto). Il raggio è in MICROCELLE, dal centro della microcella dell'edificio (vedi
# BuildingRules.political_radius/cultural_radius/religious_radius).
#
# get_effective_radius è l'UNICO punto da cui leggere il raggio di influenza di un edificio: raggio base + livelli
# raggiunti dai PUNTI di influenza (vedi sotto, sistema a punti e soglie).
#
# COPERTURA DELLE CASE (2026-10-02, richiesta utente): una casa (edificio RESIDENTIAL completo, non demolito) è coperta
# da un tipo se il suo centro dista al massimo get_effective_radius(sorgente, tipo) dal centro di almeno un edificio con
# quel raggio > 0 — stessa misura del cerchio dei layer, in microcelle assolute (macrocelle comprese). Risultato in
# una cache statica NON salvata, ricalcolata pigramente alla prima lettura dopo un cambio di GameData.
# buildings_revision (o di partita): mai a ogni giorno né a ogni frame. Lettura: is_house_covered / get_house_coverage.

enum InfluenceType { POLITICAL, CULTURAL, RELIGIOUS }

# PUNTI E SOGLIE (2026-10-03, richiesta utente — sostituisce il raggio corrente con i decimali del passo 4c): ogni
# edificio accumula per tipo dei punti di influenza (Building.influence_points, oggi solo i riti, tipo RELIGIOUS) e
# ricorda il giorno assoluto dell'ultimo guadagno (Building.influence_last_gain_day). Ogni soglia di
# BuildingRules.influence_level_thresholds raggiunta dai punti vale +1 al raggio base, mai oltre base ×
# BuildingRules.influence_max_multiplier. Raggio base 0 = quel tipo resta a 0 e non accumula punti.
# RITI TRASCURATI: a ogni anno intero (NEGLECTED_RITES_INTERVAL_DAYS) dall'ultimo guadagno l'edificio perde NEGLECTED_RITES_LOSS_FRACTION
# della soglia superiore della fascia in cui stanno i suoi punti (sopra l'ultima soglia: dell'ultima), mai sotto 0
# (advance_daily_neglected_rites, tick giornaliero). Quando il raggio effettivo cambia si alza GameData.buildings_revision
# (copertura delle case e layer si aggiornano) e GameSettings emette influence_level_changed (popup in GameScene).
const NEGLECTED_RITES_INTERVAL_DAYS: int = 365
const NEGLECTED_RITES_LOSS_FRACTION: float = 0.1


# Raggio effettivo in microcelle dell'influenza `influence_type` di `building`: base + soglie raggiunte, tra la base e
# il massimo. 0 per un edificio senza regole, demolito o non completo (un cantiere non proietta influenza) e per un
# raggio base 0.
static func get_effective_radius(building: Building, influence_type: InfluenceType) -> int:
	if building == null or building.rules == null or building.is_demolished or not building.is_complete:
		return 0
	var base := get_base_radius(building, influence_type)
	if base <= 0:
		return 0
	return clampi(base + get_level(building, influence_type), base, maxi(base, floori(get_max_radius(building, influence_type))))


# Raggio BASE delle regole (BuildingRules.political_radius/cultural_radius/religious_radius), mai negativo.
static func get_base_radius(building: Building, influence_type: InfluenceType) -> int:
	if building == null or building.rules == null:
		return 0
	match influence_type:
		InfluenceType.POLITICAL:
			return maxi(building.rules.political_radius, 0)
		InfluenceType.CULTURAL:
			return maxi(building.rules.cultural_radius, 0)
		InfluenceType.RELIGIOUS:
			# Danneggiato (2026-10-10, effetti passo 4): raggio religioso a metà (per difetto, mai sotto 1).
			return building.get_effective_capacity(maxi(building.rules.religious_radius, 0))
	return 0


# Raggio massimo: base × BuildingRules.influence_max_multiplier (mai sotto la base).
static func get_max_radius(building: Building, influence_type: InfluenceType) -> float:
	var base := float(get_base_radius(building, influence_type))
	if building == null or building.rules == null:
		return base
	return maxf(base, base * building.rules.influence_max_multiplier)


# Punti di influenza accumulati (0 se nessuno): i punti SALVATI, mai dimezzati — su di loro lavorano l'aggiunta
# (add_points) e la perdita per riti trascurati.
static func get_points(building: Building, influence_type: InfluenceType) -> float:
	if building == null:
		return 0.0
	return float(building.influence_points.get(int(influence_type), 0.0))


# Punti EFFETTIVI per gli effetti (2026-10-10, effetti dello stato "Danneggiato" — passo 4): sacralità a metà per un
# edificio danneggiato, solo per l'influenza religiosa; i punti salvati restano interi, quindi riparando non si perde
# niente. Letti da get_level (soglie raggiunte, quindi raggio) e dal pannello.
static func get_effective_points(building: Building, influence_type: InfluenceType) -> float:
	var points := get_points(building, influence_type)
	if building != null and influence_type == InfluenceType.RELIGIOUS and building.is_damaged():
		return points * 0.5
	return points


# Soglie dell'edificio (BuildingRules.influence_level_thresholds, in ordine crescente), vuote senza regole.
static func get_thresholds(building: Building) -> Array[float]:
	if building == null or building.rules == null:
		return []
	return building.rules.influence_level_thresholds


# Numero di soglie raggiunte dai punti (senza il tetto del raggio massimo).
static func get_level(building: Building, influence_type: InfluenceType) -> int:
	var points := get_effective_points(building, influence_type)
	var level := 0
	for threshold in get_thresholds(building):
		if points >= threshold:
			level += 1
	return level


# Prima soglia non ancora raggiunta, -1.0 se i punti sono già oltre l'ultima. `points` < 0 = i punti salvati (perdita
# per riti trascurati); il pannello passa quelli effettivi (get_effective_points, 2026-10-10).
static func get_next_threshold(building: Building, influence_type: InfluenceType, points: float = -1.0) -> float:
	if points < 0.0:
		points = get_points(building, influence_type)
	for threshold in get_thresholds(building):
		if points < threshold:
			return threshold
	return -1.0


# Punti persi a ogni anno senza riti: NEGLECTED_RITES_LOSS_FRACTION della soglia superiore della fascia attuale, o
# dell'ultima soglia se i punti la superano. 0 senza soglie.
static func get_neglected_rites_loss(building: Building, influence_type: InfluenceType) -> float:
	var thresholds := get_thresholds(building)
	if thresholds.is_empty():
		return 0.0
	var upper := get_next_threshold(building, influence_type)
	if upper < 0.0:
		upper = thresholds[thresholds.size() - 1]
	return upper * NEGLECTED_RITES_LOSS_FRACTION


# Giorno assoluto dell'ultimo guadagno di punti, -1 se mai.
static func get_last_gain_day(building: Building, influence_type: InfluenceType) -> int:
	if building == null:
		return -1
	return int(building.influence_last_gain_day.get(int(influence_type), -1))


# true se l'edificio ha punti e dall'ultimo guadagno è passato almeno un anno intero (perde punti ogni anno).
static func has_neglected_rites(building: Building, influence_type: InfluenceType, absolute_day: int) -> bool:
	var last_gain := get_last_gain_day(building, influence_type)
	return get_points(building, influence_type) > 0.0 and last_gain >= 0 and absolute_day - last_gain >= NEGLECTED_RITES_INTERVAL_DAYS


# Aggiunge `amount` punti (> 0) all'influenza `influence_type` di `building` e registra il giorno del guadagno. Nessun
# effetto se il raggio base è 0. `game_data` null = quello attivo (GameSettings).
static func add_points(building: Building, influence_type: InfluenceType, amount: float, game_data: GameData = null) -> void:
	if building == null or amount <= 0.0 or get_base_radius(building, influence_type) <= 0:
		return
	var data: GameData = game_data if game_data != null else GameSettings.active_game_data
	var before := get_effective_radius(building, influence_type)
	building.influence_points[int(influence_type)] = get_points(building, influence_type) + amount
	if data != null:
		building.influence_last_gain_day[int(influence_type)] = data.get_absolute_day()
	_on_points_changed(building, influence_type, before, data)


# Riti trascurati (GameTimeService._on_day_advanced): per ogni edificio con punti > 0, nel giorno in cui si compie un anno
# intero (multiplo di NEGLECTED_RITES_INTERVAL_DAYS) dall'ultimo guadagno, toglie get_neglected_rites_loss, mai sotto 0.
static func advance_daily_neglected_rites(world: World, game_data: GameData) -> void:
	if world == null or game_data == null:
		return
	var today := game_data.get_absolute_day()
	for building in world.buildings:
		if building.influence_points.is_empty():
			continue
		for influence_key in building.influence_points.keys():
			var influence_type := int(influence_key) as InfluenceType
			var points := get_points(building, influence_type)
			if points <= 0.0:
				continue
			var last_gain := get_last_gain_day(building, influence_type)
			if last_gain < 0:
				# Punti senza giorno di guadagno (non dovrebbe accadere): il conteggio parte da oggi.
				building.influence_last_gain_day[int(influence_type)] = today
				continue
			var elapsed := today - last_gain
			if elapsed <= 0 or elapsed % NEGLECTED_RITES_INTERVAL_DAYS != 0:
				continue
			var before := get_effective_radius(building, influence_type)
			building.influence_points[int(influence_type)] = maxf(0.0, points - get_neglected_rites_loss(building, influence_type))
			_on_points_changed(building, influence_type, before, game_data)


# Dopo un cambio di punti: se il raggio effettivo è cambiato alza buildings_revision e avvisa (GameSettings).
static func _on_points_changed(building: Building, influence_type: InfluenceType, radius_before: int, game_data: GameData) -> void:
	var radius_after := get_effective_radius(building, influence_type)
	if radius_after == radius_before:
		return
	_bump_buildings_revision(game_data)
	GameSettings.influence_level_changed.emit(building, int(influence_type), radius_before, radius_after)


static func _bump_buildings_revision(game_data: GameData) -> void:
	var data: GameData = game_data if game_data != null else GameSettings.active_game_data
	if data != null:
		data.buildings_revision += 1


# Cache della copertura: id casa -> {tipo (int) -> Array[int] degli id degli edifici che la coprono}; solo i tipi che
# la coprono davvero hanno una voce. Valida per la coppia (partita, revisione). Con lei, id -> Building delle sorgenti
# (stessa revisione: aggiungere o togliere un edificio alza buildings_revision), così chi legge le sorgenti non scorre
# world.buildings né calcola distanze.
static var _coverage_by_house: Dictionary = {}
static var _coverage_sources_by_id: Dictionary = {}
static var _coverage_game_data: GameData = null
static var _coverage_revision: int = -1


# true se la casa `house_id` è coperta dall'influenza `influence_type`. `world`/`game_data` null = quelli attivi
# (GameSettings). false per un id che non è una casa completa.
static func is_house_covered(house_id: int, influence_type: InfluenceType, world: World = null, game_data: GameData = null) -> bool:
	return get_house_coverage(house_id, world, game_data).has(int(influence_type))


# Tipi di influenza (InfluenceType, in ordine) che coprono la casa `house_id`; vuoto se nessuno o se non è una casa.
static func get_house_coverage(house_id: int, world: World = null, game_data: GameData = null) -> Array:
	_ensure_coverage(world if world != null else GameSettings.active_world, game_data if game_data != null else GameSettings.active_game_data)
	var types: Array = []
	var by_type: Dictionary = _coverage_by_house.get(house_id, {})
	for influence_type in InfluenceType.values():
		if by_type.has(int(influence_type)):
			types.append(int(influence_type))
	return types


# Id degli edifici che coprono la casa `house_id` con l'influenza `influence_type` (2026-10-02); vuoto se nessuno.
static func get_covering_building_ids(house_id: int, influence_type: InfluenceType, world: World = null, game_data: GameData = null) -> Array:
	_ensure_coverage(world if world != null else GameSettings.active_world, game_data if game_data != null else GameSettings.active_game_data)
	return (_coverage_by_house.get(house_id, {}) as Dictionary).get(int(influence_type), [])


# Gli stessi edifici di get_covering_building_ids, già risolti dalla cache (nessuna scansione del mondo).
static func get_covering_buildings(house_id: int, influence_type: InfluenceType, world: World = null, game_data: GameData = null) -> Array[Building]:
	var buildings: Array[Building] = []
	for building_id in get_covering_building_ids(house_id, influence_type, world, game_data):
		var building: Building = _coverage_sources_by_id.get(building_id)
		if building != null:
			buildings.append(building)
	return buildings


static func _ensure_coverage(world: World, game_data: GameData) -> void:
	if world == null or game_data == null:
		_coverage_by_house = {}
		_coverage_sources_by_id = {}
		_coverage_game_data = null
		_coverage_revision = -1
		return
	if game_data == _coverage_game_data and game_data.buildings_revision == _coverage_revision:
		return
	_coverage_game_data = game_data
	_coverage_revision = game_data.buildings_revision
	_coverage_by_house = {}
	_coverage_sources_by_id = {}
	for house in world.buildings:
		if house.rules == null or house.rules.category != BuildingTypes.Category.RESIDENTIAL or not house.is_complete or house.is_demolished:
			continue
		var covered: Dictionary = {}
		for influence_type in InfluenceType.values():
			var source_ids: Array[int] = []
			for source in world.buildings:
				var radius := get_effective_radius(source, influence_type)
				if radius > 0 and building_absolute_center(house).distance_to(building_absolute_center(source)) <= float(radius):
					source_ids.append(source.id)
					_coverage_sources_by_id[source.id] = source
			if not source_ids.is_empty():
				covered[int(influence_type)] = source_ids
		_coverage_by_house[house.id] = covered


# Centro della microcella di `building` in microcelle ASSOLUTE del mondo (macrocella × World.WIDTH/HEIGHT + microcella).
static func building_absolute_center(building: Building) -> Vector2:
	return Vector2(
		building.macro_x * World.WIDTH + building.micro_x + 0.5,
		building.macro_y * World.HEIGHT + building.micro_y + 0.5
	)


# true se `building` ha almeno un raggio di influenza effettivo > 0.
static func has_any_influence(building: Building) -> bool:
	for influence_type in InfluenceType.values():
		if get_effective_radius(building, influence_type) > 0:
			return true
	return false
