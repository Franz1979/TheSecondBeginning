class_name VegetationLotIndex
extends RefCounted

# Indice lotto -> individui (TREE/SHRUB) di una macrocella (2026-10-28, scatti da 100–300 ms: ogni domanda su un lotto
# scorreva tutte le ~62.000 piante). Unica lista per tutte le domande "per lotto": BuildingSiteClearingService.
# has_woody_vegetation e CutZoneService.list_available_plants_in_lot. Costruito dall'archivio dei sottotipi
# (tree_individual_subtype/shrub_individual_subtype: un taglio o una morte tolgono l'individuo da lì) con un giro solo
# (~20 ms), rifatto solo quando cambia MacroCellState.vegetation_revision (i cinque punti che aggiungono o tolgono un
# individuo) o, per sicurezza, il numero di individui. Sola lettura.

const _MAX_CACHED := 64

static var _cache: Dictionary = {}  # "id macrocella:tipo" -> {"revision", "size", "lots"}


# Individui (Vector3i) del lotto `lot`, nell'ordine dell'archivio. Array vuoto se nessuno. Da non modificare.
static func keys_in_lot(macro_state: MacroCellState, object_type: int, lot: Vector2i) -> Array:
	return _lots(macro_state, object_type).get(lot, [])


static func has_lot(macro_state: MacroCellState, object_type: int, lot: Vector2i) -> bool:
	return _lots(macro_state, object_type).has(lot)


static func _lots(macro_state: MacroCellState, object_type: int) -> Dictionary:
	if macro_state == null:
		return {}
	var store: Dictionary
	if object_type == GameTypes.WorldObjectType.TREE:
		store = macro_state.tree_individual_subtype
	elif object_type == GameTypes.WorldObjectType.SHRUB:
		store = macro_state.shrub_individual_subtype
	else:
		return {}
	var cache_key := "%d:%d" % [macro_state.get_instance_id(), object_type]
	var cached: Variant = _cache.get(cache_key)
	if cached != null and int(cached["revision"]) == macro_state.vegetation_revision and int(cached["size"]) == store.size():
		return cached["lots"]
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	var lots: Dictionary = {}
	for key in store.keys():
		var lot := Vector2i(key.x, key.y)
		if lots.has(lot):
			(lots[lot] as Array).append(key)
		else:
			lots[lot] = [key]
	if _cache.size() > _MAX_CACHED:
		_cache.clear()
	_cache[cache_key] = {"revision": macro_state.vegetation_revision, "size": store.size(), "lots": lots}
	if timing:
		JobBoardTimingService.add("indice lotti: costruzione", started)
	return lots


# Da chiamare subito dopo aver tolto `keys` dall'archivio e alzato vegetation_revision di 1 (2026-10-28, a ogni taglio
# l'indice si rifaceva da capo, 12–25 ms): toglie solo quelle chiavi dal loro lotto. Se l'indice in memoria non è
# quello di un attimo prima (revisione o numero diversi), non fa niente: si rifarà da capo alla prossima domanda.
static func note_removed(macro_state: MacroCellState, object_type: int, keys: Array) -> void:
	if macro_state == null or keys.is_empty():
		return
	var cache_key := "%d:%d" % [macro_state.get_instance_id(), object_type]
	var cached: Variant = _cache.get(cache_key)
	if cached == null:
		return
	var store: Dictionary = macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype
	if int(cached["revision"]) != macro_state.vegetation_revision - 1 or int(cached["size"]) != store.size() + keys.size():
		return
	var lots: Dictionary = cached["lots"]
	var removed: Dictionary = {}
	for key in keys:
		removed[key] = true
	for key in keys:
		var lot := Vector2i(key.x, key.y)
		if not lots.has(lot):
			continue
		# Lista nuova invece di togliere sul posto: chi sta già scorrendo quella vecchia non se la vede cambiare sotto.
		var kept: Array = []
		for other in lots[lot]:
			if not removed.has(other):
				kept.append(other)
		if kept.is_empty():
			lots.erase(lot)
		else:
			lots[lot] = kept
	cached["revision"] = macro_state.vegetation_revision
	cached["size"] = store.size()
