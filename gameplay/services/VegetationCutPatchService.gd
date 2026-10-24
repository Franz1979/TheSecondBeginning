class_name VegetationCutPatchService
extends RefCounted

# Taglio di una pianta senza rileggere tutta la vegetazione (2026-10-24, progetto B fase 2a —
# docs/progetto_B_vegetazione_individui.md). Dopo un taglio cambia una sola voce dell'elenco delle piante della cella
# (LiveMacroCell.cached_vegetation_positions): la si toglie da lì invece di rifare VegetationLayoutService.read (~50 ms),
# e si tengono allineati il bosco per il traino (LiveMacroCell.forest_cells) e la vegetazione sfocata della nebbia, che
# cambiano solo se il lotto resta senza piante. La versione delle posizioni (vegetation_layout_version) non sale: le
# disponibilità sparse in memoria restano valide (il chiamante aggiorna solo il lotto degli stick).
# Solo con la disposizione già pronta e nessun ricalcolo in sospeso; altrimenti il chiamante fa il ricalcolo di sempre.
# Stateless.


# true = voce tolta, il chiamante ridisegna senza ricalcolo; false = ricalcolo completo come prima.
static func remove_individual(cell: LiveMacroCell, object_type: GameTypes.WorldObjectType, individual_key: Vector3i, current_year: int) -> bool:
	if cell.macro_state == null or cell.needs_full_vegetation_recompute or cell.needs_vegetation_layout_rebuild \
			or not cell.macro_state.vegetation_layout_ready:
		return false
	var individuals: Array = cell.cached_vegetation_positions.get(object_type, [])
	var index: int = individuals.find(individual_key)
	if index < 0:
		return false
	# Copie: il renderer e l'ultimo elenco filtrato possono tenere gli stessi oggetti (senza nebbia il filtro li passa
	# così come sono), e il confronto del salto del rimontaggio deve vederli diversi.
	var updated_individuals: Array = individuals.duplicate()
	updated_individuals.remove_at(index)
	var updated_positions: Dictionary = cell.cached_vegetation_positions.duplicate()
	updated_positions[object_type] = updated_individuals
	cell.cached_vegetation_positions = updated_positions
	var lot := Vector2i(individual_key.x, individual_key.y)
	if not _lot_has_listed_plant(cell.macro_state, lot, current_year):
		if cell.forest_cells_version == cell.vegetation_layout_version:
			cell.forest_cells.erase(lot)
		if cell.fog_of_war_renderer != null:
			cell.fog_of_war_renderer.remove_vegetation_presence(lot)
	return true


# Controllo di debug (DebugLogging.CHECK_VEGETATION_CUT_PATCH): rifà la lettura completa e i pesi dei frutti e avvisa se
# il risultato aggiornato a mano è diverso. `occupied` viene modificato (come VegetationLayoutService.read).
static func verify(cell: LiveMacroCell, occupied: Dictionary, building_positions: Dictionary, current_year: int) -> void:
	var expected: Dictionary = VegetationLayoutService.read(cell.macro_state, occupied, current_year, building_positions)
	for object_type in [GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB, GameTypes.WorldObjectType.GRASS]:
		var patched: Array = cell.cached_vegetation_positions.get(object_type, [])
		var full: Array = expected.get(object_type, [])
		var patched_set: Dictionary = {}
		for key in patched:
			patched_set[key] = true
		var missing := 0
		for key in full:
			if not patched_set.has(key):
				missing += 1
		var extra: int = patched.size() - (full.size() - missing)
		if missing > 0 or extra > 0:
			push_warning("[CUT PATCH] macrocella (%d,%d) %s: elenco aggiornato %d, lettura completa %d (mancanti %d, in più %d)" % [
				cell.macro_x, cell.macro_y, GameTypes.WorldObjectType.keys()[object_type], patched.size(), full.size(), missing, extra
			])
	for mismatch in TerrainScatteredResourceService.fruit_weight_cache_mismatches(cell.macro_state):
		push_warning("[CUT PATCH] macrocella (%d,%d) %s" % [cell.macro_x, cell.macro_y, mismatch])


# Il lotto ha ancora un albero o un arbusto nell'elenco: stessa regola di VegetationLayoutService.read (posto della
# disposizione con un individuo vivo, né morto né col ceppo attivo). Edifici non controllati: la pianta tagliata era
# nell'elenco, quindi il lotto non ne ha.
static func _lot_has_listed_plant(macro_state: MacroCellState, lot: Vector2i, current_year: int) -> bool:
	for object_type in VegetationLayoutService.LAYOUT_TYPES:
		var slots: int = int(VegetationLayoutService._lot_slots_store(macro_state, object_type).get(lot, 0))
		var subtype_store := VegetationLayoutService._subtype_store(macro_state, object_type)
		for index in range(slots):
			var key := Vector3i(lot.x, lot.y, index)
			if not subtype_store.has(key) or macro_state.vegetation_death_exceptions.has(key):
				continue
			if macro_state.vegetation_cut_exceptions.has(key) \
					and IndividualVegetationService._is_cut_entry_active(macro_state.vegetation_cut_exceptions[key], current_year):
				continue
			return true
	return false
