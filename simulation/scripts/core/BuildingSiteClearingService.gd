class_name BuildingSiteClearingService
extends RefCounted

# Libera una microcella prima di piazzarci un edificio, rimuovendo esattamente ciò che vi si trova
# davvero — mai una scelta arbitraria tra TREE/SHRUB: con MIX_TREE_AND_SHRUB (vedi
# VegetationPositionService) un lotto può ospitare individui di ENTRAMBI i tipi contemporaneamente,
# quindi qui si controllano indipendentemente. Stessa aritmetica di PlayerHarvestService.
# cut_individual (resource_quantity -1 per individuo rimosso, apply_subtype_space_delta sul
# sottotipo VERO di ciascuno) ma SENZA vegetation_cut_exceptions: un edificio non è un taglio
# temporaneo con finestra di rientro, il blocco è permanente finché l'edificio esiste — vedi
# GameScene._building_positions_for_cell/IndividualVegetationService._is_blocked, che consultano
# direttamente World.buildings, nessuna eccezione da scrivere né da ripulire qui. I lotti restano
# comunque "noti" in tree_claimed_lots/shrub_claimed_lots (mai cancellati, stesso principio del
# taglio) — così, se l'edificio viene demolito in futuro, il lotto torna semplicemente eleggibile
# per un nuovo individuo alla prossima crescita, senza bisogno di alcuna resurrezione esplicita.
static func clear_microcell(macro_state: MacroCellState, pos: Vector2i, is_currently_grass: bool) -> void:
	_clear_type(macro_state, GameTypes.WorldObjectType.TREE, pos)
	_clear_type(macro_state, GameTypes.WorldObjectType.SHRUB, pos)
	if is_currently_grass:
		_clear_grass(macro_state)
	_clear_exceptions_at_lot(macro_state, pos)


# Un ceppo tagliato o una pianta morta lì sotto non hanno più motivo di restare "in attesa di
# ricrescita": building_positions in IndividualVegetationService._is_blocked blocca già per
# sempre questo lotto, l'eccezione qui sarebbe solo un marker visivo residuo (il tronco mozzato/
# la pianta secca disegnati sotto o accanto all'edificio) senza più alcuno scopo — a differenza di
# un taglio/morte "normale", dove l'eccezione serve a impedire la ricrescita SOLO per la sua
# finestra temporanea. BLOCCO UNIFICATO (vedi MacroCellState.vegetation_cut_exceptions): ripulisce
# un'eccezione a QUALUNQUE indice di questo lotto, indipendentemente da origin_type — l'intera
# microcella diventa l'edificio, non importa quale tipo l'avesse occupata prima.
static func _clear_exceptions_at_lot(macro_state: MacroCellState, pos: Vector2i) -> void:
	for exceptions in [macro_state.vegetation_cut_exceptions, macro_state.vegetation_death_exceptions]:
		var keys_to_erase: Array = []
		for key in exceptions.keys():
			if key.x == pos.x and key.y == pos.y:
				keys_to_erase.append(key)
		for key in keys_to_erase:
			exceptions.erase(key)


static func _clear_type(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, pos: Vector2i) -> void:
	var claimed_lots: Dictionary = macro_state.tree_claimed_lots if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_claimed_lots
	if not claimed_lots.has(pos):
		return

	var birth_year_store: Dictionary = macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year
	var subtype_store: Dictionary = macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype

	# subtype_store (non birth_year_store) è la fonte completa di "chi è vivo qui": ogni individuo
	# riceve sempre un sottotipo congelato alla nascita, mentre birth_year_store resta vuoto per i
	# sottotipi con track_age_bands=false (vedi IndividualVegetationService._freeze_new_individual).
	# Un individuo già tagliato/morto non compare più qui (cut_individual/kill_individual cancellano
	# già subtype_store alla rimozione), quindi non viene mai ri-rimosso per errore.
	var removed_by_subtype: Dictionary = {}
	var keys_to_erase: Array = []
	for key in subtype_store.keys():
		if key.x == pos.x and key.y == pos.y:
			var subtype_name: String = subtype_store[key]
			removed_by_subtype[subtype_name] = int(removed_by_subtype.get(subtype_name, 0)) + 1
			keys_to_erase.append(key)

	if keys_to_erase.is_empty():
		return

	for key in keys_to_erase:
		birth_year_store.erase(key)
		subtype_store.erase(key)

	macro_state.add_resource_quantity(object_type, -keys_to_erase.size())

	# UNA sola unità di spazio liberata per lotto cancellato, MAI una per individuo:
	# dedicated_space conta lotti (microcelle), non individui — un lotto può ospitarne più di uno
	# per densità (vedi lot_counts/MicroCellRenderer._lot_extent_counts), ma resta comunque 1 sola
	# unità del budget di quel tipo, esattamente come un singolo taglio giocatore libera sempre e
	# solo 1 unità indipendentemente da quanti individui condividono quel lotto. removed_by_subtype
	# serve solo come PESO per scegliere quale sottotipo perde quell'unica unità (il sottotipo più
	# rappresentato tra gli individui rimossi ha più probabilità di essere quello scalato), mai come
	# quantità letterale da sottrarre.
	var weights: Dictionary = {}
	for subtype_name in removed_by_subtype.keys():
		weights[subtype_name] = float(removed_by_subtype[subtype_name])
	var space_before: int = macro_state.get_dedicated_space(object_type)
	var removed_space: Dictionary = macro_state.apply_subtype_space_delta(object_type, -1, weights)
	var space_removed: int = 0
	for amount in removed_space.values():
		space_removed += int(amount)
	if space_removed > 0:
		macro_state.set_dedicated_space(object_type, space_before - space_removed)

	print("[BUILDING SITE CLEARING] rimossi %d %s in (%d,%d) per far posto a un edificio (spazio liberato: %d)" % [
		keys_to_erase.size(), GameTypes.WorldObjectType.keys()[object_type], pos.x, pos.y, space_removed
	])


# GRASS non ha identità individuale né posizioni persistite (rigenerata da zero ogni volta, vedi
# VegetationPositionService) — non c'è "l'individuo" da cancellare, solo una densità aggregata.
# Libera 1 unità di spazio e la quantità corrispondente alla densità corrente (resource_quantity/
# dedicated_space) — stessa approssimazione già accettata per il taglio giocatore (1 unità di
# spazio è la conversione più semplice difendibile per un evento a granularità microcella).
static func _clear_grass(macro_state: MacroCellState) -> void:
	var object_type := GameTypes.WorldObjectType.GRASS
	var space: int = macro_state.get_dedicated_space(object_type)
	if space <= 0:
		return
	var quantity: int = macro_state.get_resource_quantity(object_type)
	var quantity_removed: int = int(round(float(quantity) / float(space)))
	macro_state.set_dedicated_space(object_type, space - 1)
	if quantity_removed > 0:
		macro_state.add_resource_quantity(object_type, -quantity_removed)
