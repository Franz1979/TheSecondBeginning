class_name VegetationLayoutService
extends RefCounted

# Disposizione salvata della vegetazione (2026-10-24, progetto B fase 1 — docs/progetto_B_vegetazione_individui.md).
# Prima ogni taglio, cantiere ripulito o edificio piazzato rifaceva da capo VegetationPositionService su tutta la
# macrocella (~120 ms): rumore, ordinamento dei lotti, distribuzione degli individui, erba. Ora:
#   - rebuild: chiama lo STESSO generatore di sempre (risultato identico) e ne tiene la disposizione in MacroCellState
#     (tree_lot_slots/shrub_lot_slots: lotto -> numero di posti; grass_lots). Solo alla prima vista, ai checkpoint di
#     stagione/anno e dopo gli eventi che cambiano i numeri della vegetazione.
#   - read: ricostruisce lo stesso elenco dalla disposizione tenuta, senza generatore. Salta i posti bloccati come
#     IndividualVegetationService._is_blocked (edificio sul lotto, ceppo ancora attivo, pianta morta) e quelli senza più
#     un individuo (tagliato, ripulito): non ne crea di nuovi, lo fa solo rebuild. L'erba salta i lotti con un edificio o
#     un blocco attivo (come VegetationPositionService._exclude_blocked_lots), senza rimpiazzarli altrove.
# Stessa forma di risultato di VegetationPositionService.generate_positions: TREE/SHRUB Array di Vector3i, GRASS Array di
# Vector2i. TREE/SHRUB ordinati per zona del renderer (dal 2026-10-24, _ordered_by_zone), sia in rebuild sia in read.
# Stateless.

# Lotto nel salvataggio: y * LOT_CODE_WIDTH + x (microcelle 0..99).
const LOT_CODE_WIDTH := 100
const LAYOUT_TYPES: Array[GameTypes.WorldObjectType] = [GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB]
# Vegetazione a richiesta, passo 4 (docs/progetto_vegetazione_a_richiesta.md): true = la disposizione nasce da
# VegetationAtLotService e non dipende più dai numeri di cella; false = dal generatore di sempre.
const USE_LOT_FUNCTION := false


# Generatore di sempre + disposizione tenuta. `occupied` e `building_positions` come VegetationPositionService.
static func rebuild(macro_state: MacroCellState, occupied: Dictionary, current_year: int, current_day: int, building_positions: Dictionary) -> Dictionary:
	var positions: Dictionary = VegetationPositionService.new().generate_positions(macro_state, occupied, current_year, current_day, building_positions)
	for object_type in LAYOUT_TYPES:
		positions[object_type] = _ordered_by_zone(positions.get(object_type, []))
		var slots := _lot_slots_store(macro_state, object_type)
		slots.clear()
		for key in positions.get(object_type, []):
			var lot := Vector2i(key.x, key.y)
			slots[lot] = maxi(int(slots.get(lot, 0)), key.z + 1)
		# Posti bloccati (ceppi, piante morte) di questo tipo: il generatore non li restituisce ma il lotto li ha.
		var claimed := _claimed_lots_store(macro_state, object_type)
		for exceptions in [macro_state.vegetation_cut_exceptions, macro_state.vegetation_death_exceptions]:
			for key in exceptions.keys():
				if int(exceptions[key]["origin_type"]) != object_type:
					continue
				var lot := Vector2i(key.x, key.y)
				if claimed.has(lot):
					slots[lot] = maxi(int(slots.get(lot, 0)), key.z + 1)
	macro_state.grass_lots.clear()
	for lot in positions.get(GameTypes.WorldObjectType.GRASS, []):
		macro_state.grass_lots[lot] = true
	macro_state.vegetation_layout_ready = true
	return positions


# Disposizione calcolata da VegetationAtLotService: riempie gli stessi dati del generatore (lotti, posti, sottotipi, anni
# di nascita, erba), così chi li legge non cambia, poi costruisce l'elenco con read. Un lotto in `occupied` resta vuoto.
# Ceppi e piante morte restano al loro posto e il loro posto non riceve una pianta.
static func rebuild_from_function(
	macro_state: MacroCellState, macro_cell: MacroCellData, occupied: Dictionary, current_year: int,
	world_age: GameTypes.WorldAge, building_positions: Dictionary
) -> Dictionary:
	var profile := VegetationAtLotService.get_profile(macro_cell.terrain_base, macro_cell.biome, macro_cell.coast_type, world_age)
	var lot_codes := PackedInt32Array()
	for y in range(VegetationAtLotService.LOTS_PER_CELL):
		for x in range(VegetationAtLotService.LOTS_PER_CELL):
			if not occupied.has(Vector2i(x, y)):
				lot_codes.append(y * LOT_CODE_WIDTH + x)
	var lots: Dictionary = VegetationAtLotService.vegetation_for_lots(profile, macro_cell.x, macro_cell.y, current_year, lot_codes)
	for object_type in LAYOUT_TYPES:
		IndividualVegetationService._prune_expired_cut_exceptions(macro_state.vegetation_cut_exceptions, object_type, current_year)
	_store_plants(macro_state, GameTypes.WorldObjectType.TREE, lots["trees"], current_year)
	_store_plants(macro_state, GameTypes.WorldObjectType.SHRUB, lots["shrubs"], current_year)
	macro_state.grass_lots.clear()
	for code in lots["grass"]:
		macro_state.grass_lots[_decode(code)] = true
	macro_state.vegetation_revision += 1
	macro_state.vegetation_layout_ready = true
	return read(macro_state, occupied, current_year, building_positions)


# `plants`: [codice lotto, indice posto, età, indice sottotipo, ...] (VegetationAtLotService.vegetation_for_lots).
static func _store_plants(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, plants: PackedInt32Array, current_year: int) -> void:
	var rules: Array = ResourceCalculator.get_subtype_rules(object_type)
	var claimed := _claimed_lots_store(macro_state, object_type)
	var slots := _lot_slots_store(macro_state, object_type)
	var subtype_store := _subtype_store(macro_state, object_type)
	var birth_year_store := IndividualVegetationService._birth_year_store(macro_state, object_type)
	var cut_exceptions: Dictionary = macro_state.vegetation_cut_exceptions
	var death_exceptions: Dictionary = macro_state.vegetation_death_exceptions
	claimed.clear()
	slots.clear()
	subtype_store.clear()
	birth_year_store.clear()
	for i in range(0, plants.size(), 4):
		var lot := _decode(plants[i])
		var index: int = plants[i + 1]
		claimed[lot] = true
		slots[lot] = maxi(int(slots.get(lot, 0)), index + 1)
		var key := Vector3i(lot.x, lot.y, index)
		if cut_exceptions.has(key) or death_exceptions.has(key):
			continue
		var rule = rules[plants[i + 3]]
		subtype_store[key] = rule.subtype_name
		if rule.track_age_bands:
			birth_year_store[key] = current_year - plants[i + 2]
	for exceptions in [cut_exceptions, death_exceptions]:
		for key in exceptions.keys():
			if int(exceptions[key]["origin_type"]) != object_type:
				continue
			var lot := Vector2i(key.x, key.y)
			claimed[lot] = true
			slots[lot] = maxi(int(slots.get(lot, 0)), key.z + 1)


# Elenco dalla disposizione tenuta. Richiede vegetation_layout_ready (altrimenti rebuild).
static func read(macro_state: MacroCellState, occupied: Dictionary, current_year: int, building_positions: Dictionary) -> Dictionary:
	var cut_exceptions: Dictionary = macro_state.vegetation_cut_exceptions
	var death_exceptions: Dictionary = macro_state.vegetation_death_exceptions
	var result: Dictionary = {}
	for object_type in LAYOUT_TYPES:
		var subtype_store := _subtype_store(macro_state, object_type)
		var individuals: Array = []
		if USE_LOT_FUNCTION or macro_state.get_dedicated_space(object_type) > 0:
			var slots := _lot_slots_store(macro_state, object_type)
			for lot in slots.keys():
				if building_positions.has(lot):
					continue
				for index in range(int(slots[lot])):
					var key := Vector3i(lot.x, lot.y, index)
					if death_exceptions.has(key):
						continue
					if cut_exceptions.has(key) and IndividualVegetationService._is_cut_entry_active(cut_exceptions[key], current_year):
						continue
					if not subtype_store.has(key):
						continue
					individuals.append(key)
			# Come il generatore: i lotti rivendicati restano occupati per chi viene dopo.
			for lot in _claimed_lots_store(macro_state, object_type).keys():
				occupied[lot] = true
		result[object_type] = _ordered_by_zone(individuals)
	var blocked_lots: Dictionary = {}
	for key in death_exceptions.keys():
		blocked_lots[Vector2i(key.x, key.y)] = true
	for key in cut_exceptions.keys():
		if IndividualVegetationService._is_cut_entry_active(cut_exceptions[key], current_year):
			blocked_lots[Vector2i(key.x, key.y)] = true
	var grass: Array = []
	for lot in macro_state.grass_lots.keys():
		if building_positions.has(lot) or blocked_lots.has(lot):
			continue
		grass.append(lot)
		occupied[lot] = true
	result[GameTypes.WorldObjectType.GRASS] = grass
	return result


# --- Salvataggio (GameSaveService/GameLoadService) ---

# {"tree": [codice, posti, ...], "shrub": [...], "grass": [codice, ...]}.
static func to_save_data(macro_state: MacroCellState) -> Dictionary:
	var data: Dictionary = {}
	for object_type in LAYOUT_TYPES:
		var flat: Array = []
		var slots := _lot_slots_store(macro_state, object_type)
		for lot in slots.keys():
			flat.append(_encode(lot))
			flat.append(int(slots[lot]))
		data[_save_key(object_type)] = flat
	var grass: Array = []
	for lot in macro_state.grass_lots.keys():
		grass.append(_encode(lot))
	data["grass"] = grass
	data["checkpoint"] = macro_state.vegetation_layout_checkpoint
	return data


static func load_save_data(macro_state: MacroCellState, data: Dictionary) -> void:
	macro_state.vegetation_layout_ready = not data.is_empty()
	macro_state.vegetation_layout_checkpoint = int(data.get("checkpoint", -1))
	if data.is_empty():
		return
	for object_type in LAYOUT_TYPES:
		var slots := _lot_slots_store(macro_state, object_type)
		slots.clear()
		var flat: Array = data.get(_save_key(object_type), [])
		for i in range(0, flat.size() - 1, 2):
			slots[_decode(int(flat[i]))] = int(flat[i + 1])
	macro_state.grass_lots.clear()
	for code in data.get("grass", []):
		macro_state.grass_lots[_decode(int(code))] = true


# --- Interni ---

# Alberi/arbusti ordinati per zona del renderer (2026-10-24, progetto B fase 2b — MicroCellRenderer.vegetation_zone_of),
# nell'ordine di prima dentro ogni zona: i gruppi del rimontaggio sono le zone, quindi un taglio ne cambia uno solo.
static func _ordered_by_zone(individuals: Array) -> Array:
	var buckets: Array = []
	buckets.resize(MicroCellRenderer.VEGETATION_ZONE_COUNT)
	for i in range(buckets.size()):
		buckets[i] = []
	for key in individuals:
		(buckets[MicroCellRenderer.vegetation_zone_of(key.x, key.y)] as Array).append(key)
	var ordered: Array = []
	for bucket in buckets:
		ordered.append_array(bucket)
	return ordered


static func _save_key(object_type: GameTypes.WorldObjectType) -> String:
	return "tree" if object_type == GameTypes.WorldObjectType.TREE else "shrub"


static func _encode(lot: Vector2i) -> int:
	return lot.y * LOT_CODE_WIDTH + lot.x


static func _decode(code: int) -> Vector2i:
	return Vector2i(code % LOT_CODE_WIDTH, code / LOT_CODE_WIDTH)


static func _lot_slots_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_lot_slots if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_lot_slots


static func _subtype_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype


static func _claimed_lots_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_claimed_lots if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_claimed_lots
