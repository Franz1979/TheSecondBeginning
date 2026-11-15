class_name FieldSeedStoreService
extends RefCounted

# Semi nel capanno del campo (2026-11-15, richiesta utente — campi, passo 3a): l'Attrezzeria del capanno tiene anche i
# vasi da semi (10 pezzi come bastoni e falcetti: 500 once), e il capanno accetta SOLO il seme domestico della specie
# scelta nel campo (CultivationService.seed_resource), fino al livello voluto: il raccolto portato al deposito più
# vicino riempie il capanno fin lì e il resto resta nel mucchio per il granaio. Livello: Building.field_seed_level
# (-1 = regola generale, 0 = nessuno, > 0 = suo), sempre entro la capienza dei vasi montati. La regola generale è quella
# del WM "Semi nei campi" (passo 3b, GameData.stock_field_seeds per seme; assente = la semina di tutti i lotti,
# default_level). Stateless.

const CONTAINER := "seed_jar"


# true se l'edificio è un capanno da semi (il campo: solo semi domestici).
static func is_seed_store(building: Building) -> bool:
	return CultivationService.is_domestic_only(building)


# Capienza dei vasi montati adesso.
static func capacity(building: Building) -> int:
	return StorageContainerService.capacity_of(building, CONTAINER)


# Capienza con l'Attrezzeria piena (tetto del campo del livello nel pannello).
static func max_capacity(building: Building) -> int:
	if building == null or building.rules == null:
		return 0
	return BuildingToolkitService.units_for_rules(building.rules, CONTAINER) * StorageContainerService.unit_capacity(CONTAINER)


# Livello della regola generale per il seme di questo campo (regola del WM "Semi nei campi").
static func rule_level(game_data: GameData, building: Building) -> int:
	return general_level(game_data, CultivationService.seed_resource(building))


# Valore della regola generale per `seed_name`: quello scritto nel WM, altrimenti default_level.
static func general_level(game_data: GameData, seed_name: String) -> int:
	if game_data != null and game_data.stock_field_seeds.has(seed_name):
		return int(game_data.stock_field_seeds[seed_name])
	return default_level()


static var _type_cache_ready := false
static var _default_level := 0
static var _max_type_capacity := 0


# Valore iniziale della regola: la semina di tutti i lotti di un campo, entro i suoi vasi (oggi 8 × 100, 8 vasi da 100 → 800).
static func default_level() -> int:
	_prepare_type_cache()
	return _default_level


# Capienza in vasi del capanno più capiente tra i tipi di campo (massimo del valore nel WM).
static func max_type_capacity() -> int:
	_prepare_type_cache()
	return _max_type_capacity


static func _prepare_type_cache() -> void:
	if _type_cache_ready:
		return
	_type_cache_ready = true
	for type_name in BuildingCalculator.list_building_type_names():
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules == null or not rules.cultivation_domestic_only or not rules.toolkit_extra_tools.has(CONTAINER):
			continue
		var type_capacity := BuildingToolkitService.units_for_rules(rules, CONTAINER) * StorageContainerService.unit_capacity(CONTAINER)
		_max_type_capacity = maxi(_max_type_capacity, type_capacity)
		_default_level = maxi(_default_level, mini(rules.cultivation_lots * rules.cultivation_units_per_lot, type_capacity))


# Once da tenere nel capanno adesso: livello del campo o della regola, entro i vasi montati; 0 senza specie.
static func target_level(game_data: GameData, building: Building) -> int:
	if not is_seed_store(building) or building.crop_species == "":
		return 0
	var level := rule_level(game_data, building) if building.field_seed_level < 0 else building.field_seed_level
	return clampi(level, 0, capacity(building))


# Once del seme del campo nel capanno.
static func stored(building: Building) -> int:
	var seed_name := CultivationService.seed_resource(building)
	if seed_name == "":
		return 0
	return int((building.stored_resources.get(seed_name, {}) as Dictionary).get("quantity", 0))


# Semi riservati al campo (2026-11-15, passo 3d — richiesta utente): tutto ciò che sta nel capanno non è una scorta del
# villaggio (VillageStockService, livelli del WM) né una sorgente di prelievo (WarehouseSelectionService: zuppa,
# mangiatoie, Fossa, trasporti). Lo usano solo la Semina (take_for_lot) e il WM che porta via i semi che il capanno non
# tiene più (FieldSeedStockService, sorgente esplicita).
static func is_seed_reserved(building: Building, _resource_name: String) -> bool:
	return is_seed_store(building)


# true se il capanno accetta `resource_name` (solo il seme della specie del campo).
static func accepts(building: Building, resource_name: String) -> bool:
	return resource_name != "" and resource_name == CultivationService.seed_resource(building)


# Once di `resource_name` che il capanno prende ancora (fino al livello voluto).
static func room(building: Building, resource_name: String) -> int:
	if not accepts(building, resource_name):
		return 0
	return maxi(target_level(GameSettings.active_game_data, building) - stored(building), 0)


# Id dei capanni da semi: esclusi dalla ricerca dei semi in magazzino (la Semina li prende dal suo capanno senza viaggio,
# il WM non li sposta da un campo all'altro).
static func store_ids(world: World) -> Array[int]:
	var ids: Array[int] = []
	if world == null:
		return ids
	for building in world.buildings:
		if building != null and is_seed_store(building):
			ids.append(building.id)
	return ids


# Semina dal capanno (2026-11-15, passo 3c — richiesta utente: niente viaggio): chi semina un lotto del campo passa sul
# lotto i semi del capanno che il lotto vuole ancora, prelevati come da un magazzino (usura dei vasi compresa). Ritorna
# le once passate.
static func take_for_lot(building: Building, lot: CropLot) -> int:
	if lot == null or not is_seed_store(building):
		return 0
	var seed_name := CultivationService.seed_resource(building)
	var wanted := CultivationService.seeds_wanted(building, lot)
	if seed_name == "" or wanted <= 0:
		return 0
	var taken := BuildingStorageService.withdraw(building, seed_name, wanted)
	lot.seeds += taken
	if taken > 0:
		CultivationService.log_line("%s #%d: %d once di %s dal capanno al lotto %s" % [
			building.building_type_name, building.id, taken, seed_name, lot.microcell])
	return taken
