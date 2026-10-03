class_name InfluenceService
extends RefCounted

# Influenza politica, culturale e religiosa degli edifici (2026-10-02, richiesta utente) — service statico, stesso
# pattern degli altri *Service; l'unico stato è la cache della copertura delle case (vedi sotto). Il raggio è in MICROCELLE, dal centro della microcella dell'edificio (vedi
# BuildingRules.political_radius/cultural_radius/religious_radius).
#
# get_effective_radius è l'UNICO punto da cui leggere il raggio di influenza di un edificio: restituisce la parte intera
# del raggio CORRENTE (vedi sotto, passo 4c), che cresce con i riti e decade verso la base.
#
# COPERTURA DELLE CASE (2026-10-02, richiesta utente): una casa (edificio RESIDENTIAL completo, non demolito) è coperta
# da un tipo se il suo centro dista al massimo get_effective_radius(sorgente, tipo) dal centro di almeno un edificio con
# quel raggio > 0 — stessa misura del cerchio dei layer, in microcelle assolute (macrocelle comprese). Risultato in
# una cache statica NON salvata, ricalcolata pigramente alla prima lettura dopo un cambio di GameData.
# buildings_revision (o di partita): mai a ogni giorno né a ogni frame. Lettura: is_house_covered / get_house_coverage.

enum InfluenceType { POLITICAL, CULTURAL, RELIGIOUS }

# RAGGIO CORRENTE (2026-10-02, passo 4c): ogni edificio ha per tipo un raggio con i decimali (Building.influence_radius),
# sempre tra il raggio base delle regole e base × BuildingRules.influence_max_multiplier. Cresce con add_radius (oggi
# solo i riti, tipo RELIGIOUS) e decade ogni giorno di INFLUENCE_RADIUS_DAILY_DECAY verso la base (advance_daily_decay).
# Raggio base 0 = quel tipo resta a 0 e non cresce mai. Quando la parte intera cambia si alza GameData.
# buildings_revision, così copertura delle case e layer si aggiornano; i soli decimali no.
const INFLUENCE_RADIUS_DAILY_DECAY: float = 0.05


# Raggio effettivo in microcelle dell'influenza `influence_type` di `building`: parte intera del raggio corrente. 0 per
# un edificio senza regole, demolito o non completo (un cantiere non proietta influenza).
static func get_effective_radius(building: Building, influence_type: InfluenceType) -> int:
	if building == null or building.rules == null or building.is_demolished or not building.is_complete:
		return 0
	return floori(get_current_radius(building, influence_type))


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
			return maxi(building.rules.religious_radius, 0)
	return 0


# Raggio massimo: base × BuildingRules.influence_max_multiplier (mai sotto la base).
static func get_max_radius(building: Building, influence_type: InfluenceType) -> float:
	var base := float(get_base_radius(building, influence_type))
	if building == null or building.rules == null:
		return base
	return maxf(base, base * building.rules.influence_max_multiplier)


# Raggio CORRENTE con i decimali, sempre tra base e massimo (voce assente = base). Non controlla completezza o
# demolizione: per quello c'è get_effective_radius.
static func get_current_radius(building: Building, influence_type: InfluenceType) -> float:
	var base := float(get_base_radius(building, influence_type))
	if base <= 0.0:
		return 0.0
	var stored := float(building.influence_radius.get(int(influence_type), base))
	return clampf(stored, base, get_max_radius(building, influence_type))


# Aumenta il raggio corrente di `amount` (limitato al massimo). Nessun effetto se il raggio base è 0. Alza
# GameData.buildings_revision se cambia la parte intera. `game_data` null = quello attivo (GameSettings).
static func add_radius(building: Building, influence_type: InfluenceType, amount: float, game_data: GameData = null) -> void:
	if building == null or amount == 0.0 or get_base_radius(building, influence_type) <= 0:
		return
	var before := get_current_radius(building, influence_type)
	var after := clampf(before + amount, float(get_base_radius(building, influence_type)), get_max_radius(building, influence_type))
	building.influence_radius[int(influence_type)] = after
	if floori(after) != floori(before):
		_bump_buildings_revision(game_data)


# Decadimento giornaliero (GameTimeService._on_day_advanced): ogni edificio del mondo con un raggio corrente sopra la
# base perde INFLUENCE_RADIUS_DAILY_DECAY per tipo, senza scendere sotto la base. Una sola alzata di
# buildings_revision se almeno una parte intera è cambiata.
static func advance_daily_decay(world: World, game_data: GameData) -> void:
	if world == null:
		return
	var integer_changed := false
	for building in world.buildings:
		for influence_type in InfluenceType.values():
			var base := float(get_base_radius(building, influence_type))
			var before := get_current_radius(building, influence_type)
			if before <= base:
				building.influence_radius.erase(int(influence_type))
				continue
			var after := maxf(base, before - INFLUENCE_RADIUS_DAILY_DECAY)
			building.influence_radius[int(influence_type)] = after
			if floori(after) != floori(before):
				integer_changed = true
	if integer_changed:
		_bump_buildings_revision(game_data)


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
