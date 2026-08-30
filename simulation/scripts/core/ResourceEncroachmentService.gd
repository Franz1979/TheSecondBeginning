class_name ResourceEncroachmentService
extends RefCounted

const ENCROACHABLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
]


# Step 11 Step 4: browsing_mitigation è l'output di BrowsingMitigationService.compute_browsing_
# mitigation (Vector2i -> {"species":..., "combined_browsing_factor":...}) — celle assenti dal
# dizionario (nessuna specie brucante presente) restano a fattore 1.0, encroachment invariato.
func encroach_resources(world: World, browsing_mitigation: Dictionary) -> Dictionary:
	var leftover_surplus: Dictionary = {}
	# Processing order follows succession_level ascending (grass, then shrub, then trees, ...)
	# so that when two encroachers target the same weaker resource in the same cell/year,
	# the lower succession level always gets first claim on it, regardless of how
	# ENCROACHABLE_TYPES is ordered or extended in the future.
	var ordered_types := ResourceCalculator.get_types_ordered_by_succession(ENCROACHABLE_TYPES)

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue
		# LOD0: macrocella mai scoperta dentro una sessione con focus attivo — congelata, nessun
		# encroachment finché il player non ci arriva (vedi LODOrchestrator.is_vegetation_frozen).
		if LODOrchestrator.is_vegetation_frozen(world, state):
			continue

		var cell_key := Vector2i(cell.x, cell.y)
		var browsing_factor: float = 1.0
		if browsing_mitigation.has(cell_key):
			browsing_factor = browsing_mitigation[cell_key]["combined_browsing_factor"]

		for resource_type in ordered_types:
			var surplus := ResourceCalculator.compute_growth_surplus(resource_type, cell, state)
			if surplus <= 0.0:
				continue

			var leftover := _encroach_resource_in_cell(cell, state, resource_type, surplus, browsing_factor)
			if leftover > 0.0:
				_store_leftover(leftover_surplus, cell, resource_type, leftover)

	return leftover_surplus


func _encroach_resource_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	surplus: float,
	browsing_factor: float = 1.0
) -> float:
	# Rule 1: encroachment only when this resource's desired growth exceeds available
	# space/density (surplus > 0 is guaranteed by the caller) — same trigger migration uses,
	# rather than requiring the whole macro cell to be literally at 0 empty space.
	var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
	if growth_rules == null:
		return surplus

	var weaker_types := _get_weaker_types_present(state, resource_type, growth_rules.succession_level)
	if weaker_types.is_empty():
		# Rule 6: no weaker level available, everything goes to migration.
		return surplus

	var own_max_density := ResourceCalculator.get_max_density(
		resource_type, cell.terrain_base, cell.biome, cell.coast_type
	)
	if own_max_density <= 0.0:
		return surplus

	# Rule 4: encroachment is capped at max_encroachment_per_year regardless of surplus size.
	# The cap applies to the final realized quantity (same as max_migration_per_year does for
	# migration), not to the surplus before efficiency is applied — otherwise a low efficiency
	# would shrink an already-capped small budget twice and round away to nothing.
	var remaining_budget: float = float(growth_rules.max_encroachment_per_year)
	# Step 11 Step 4: remaining_surplus/remaining_budget seguono la catena NON mitigata —
	# l'encroacher "tenta" la crescita piena esattamente come se non ci fosse fauna brucante,
	# usando il proprio budget/surplus di conseguenza. browsing_factor entra in gioco SOLO dopo
	# che budget/potenziale/spazio fisico hanno già determinato quantity_gained (vedi sotto) —
	# stesso principio della mitigazione natalità (AnimalBirthMitigationService: il moltiplicatore
	# scala il risultato finale, mai un valore intermedio che un altro vincolo potrebbe rendere
	# ininfluente). Garantisce una riduzione ≈(1-browsing_factor) uniforme, indipendentemente da
	# quale dei tre vincoli (budget_annuo/potenziale/spazio_fisico_debole) risulti stringente in
	# una data cella — confermato empiricamente su un run reale prima di questa pulizia.
	var remaining_surplus: float = surplus

	# Rule 3: consume the farthest (lowest succession level) target fully before moving closer.
	for weak_type in weaker_types:
		if remaining_budget <= 0.0:
			break

		var weak_space: int = state.get_dedicated_space(weak_type)
		if weak_space <= 0:
			continue

		var weak_growth_rules := ResourceCalculator.get_growth_rules(weak_type)
		if weak_growth_rules == null:
			continue

		var efficiency := ResourceCalculator.get_encroachment_efficiency(
			growth_rules, weak_growth_rules.succession_level
		)
		if efficiency <= 0.0:
			continue

		var weak_max_density := ResourceCalculator.get_max_density(
			weak_type, cell.terrain_base, cell.biome, cell.coast_type
		)

		var potential_quantity: float = remaining_surplus * efficiency
		var max_quantity_from_space: float = float(weak_space) * own_max_density
		var quantity_gained: float = min(potential_quantity, remaining_budget, max_quantity_from_space)

		if quantity_gained <= 0.0:
			continue

		# Budget/surplus si consumano sull'importo NON mitigato, così un weak_type successivo
		# nello stesso loop (es. TREE che tenta SHRUB dopo GRASS) vede lo stesso remaining_budget
		# che vedrebbe la catena non mitigata, non uno "gonfiato" dalla mitigazione di questo
		# passo. Se l'importo pieno arrotonda a zero microcelle, nessun budget consumato — stesso
		# comportamento di sempre.
		var space_taken_unmitigated: int = min(int(round(quantity_gained / own_max_density)), weak_space)
		if space_taken_unmitigated <= 0:
			continue
		var applied_quantity_unmitigated: float = space_taken_unmitigated * own_max_density
		remaining_budget -= applied_quantity_unmitigated
		remaining_surplus -= applied_quantity_unmitigated

		# Step 11 Step 4 — PUNTO DI APPLICAZIONE del moltiplicatore: dopo che budget/potenziale/
		# spazio hanno già determinato quantity_gained sopra. browsing_factor=1.0 (default per
		# celle senza fauna brucante) rende space_taken identico a space_taken_unmitigated,
		# nessun cambiamento rispetto a prima dello Step 4 in quel caso.
		var quantity_gained_mitigated: float = quantity_gained * browsing_factor
		var space_taken: int = min(int(round(quantity_gained_mitigated / own_max_density)), weak_space)
		if space_taken <= 0:
			# La mitigazione ha ridotto l'importo sotto una microcella intera: nessuna scrittura
			# sullo stato, ma budget/surplus sopra sono comunque già stati consumati sull'importo
			# pieno (vedi commento sopra) — coerente con "l'encroacher tenta comunque".
			continue

		# Re-derive the applied quantity from the rounded space so quantity stays
		# consistent with space * density (same invariant used everywhere else).
		var applied_quantity: float = space_taken * own_max_density

		# Lato perdente: proporzione locale pura, invariata. La competizione territoriale
		# (chi prende spazio a chi) non è un giudizio di idoneità climatica del sottotipo —
		# solo growth/mortality usano il moltiplicatore di bioma, l'encroachment no. Stessa
		# filosofia estesa all'età: nessun peso esplicito (mortality_share_by_age è solo per la
		# mortalità da fill_ratio), proporzione locale pura anche per le fasce età.
		var new_weak_space: int = weak_space - space_taken
		var weak_loss_split := state.apply_subtype_space_delta(weak_type, -space_taken)
		_apply_age_band_losses(weak_type, state, weak_loss_split)
		state.set_dedicated_space(weak_type, new_weak_space)
		state.set_resource_quantity(weak_type, int(round(new_weak_space * weak_max_density)))

		var gain_weights := ResourceCalculator.get_biome_weighted_subtype_composition(resource_type, state, cell.biome)
		var gain_split := state.apply_subtype_space_delta(resource_type, space_taken, gain_weights)
		_apply_age_band_gains(resource_type, state, gain_split)
		state.set_dedicated_space(resource_type, state.get_dedicated_space(resource_type) + space_taken)
		state.add_resource_quantity(resource_type, int(round(applied_quantity)))

	return max(remaining_surplus, 0.0)


func _get_weaker_types_present(
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	own_succession_level: GameTypes.SuccessionLevel
) -> Array:
	var candidates: Array = []

	for candidate_type in ENCROACHABLE_TYPES:
		if candidate_type == resource_type:
			continue
		if state.get_dedicated_space(candidate_type) <= 0:
			continue

		var candidate_rules := ResourceCalculator.get_growth_rules(candidate_type)
		if candidate_rules == null:
			continue
		if candidate_rules.succession_level >= own_succession_level:
			continue

		candidates.append({"type": candidate_type, "level": candidate_rules.succession_level})

	candidates.sort_custom(func(a, b): return a["level"] < b["level"])

	var sorted_types: Array = []
	for entry in candidates:
		sorted_types.append(entry["type"])
	return sorted_types


func _store_leftover(
	leftover_surplus: Dictionary,
	cell: MacroCellData,
	resource_type: GameTypes.WorldObjectType,
	leftover: float
) -> void:
	var cell_key := Vector2i(cell.x, cell.y)
	if not leftover_surplus.has(cell_key):
		leftover_surplus[cell_key] = {}
	leftover_surplus[cell_key][resource_type] = leftover


# Lato vincente: le unità guadagnate per encroachment sono "nuova crescita" quanto quelle di
# ResourceGrowthService, finiscono sempre in YOUNG — solo per sottotipi track_age_bands=true.
func _apply_age_band_gains(resource_type: GameTypes.WorldObjectType, state: MacroCellState, split: Dictionary) -> void:
	for subtype_name in split.keys():
		var rule := ResourceCalculator.get_subtype_rule(resource_type, subtype_name)
		if rule == null or not rule.track_age_bands:
			continue
		state.add_age_band_gain(resource_type, subtype_name, int(split[subtype_name]))


# Lato perdente: nessun peso esplicito (proporzione locale pura, vedi commento al call site) —
# solo per sottotipi track_age_bands=true.
func _apply_age_band_losses(resource_type: GameTypes.WorldObjectType, state: MacroCellState, split: Dictionary) -> void:
	for subtype_name in split.keys():
		var rule := ResourceCalculator.get_subtype_rule(resource_type, subtype_name)
		if rule == null or not rule.track_age_bands:
			continue
		state.apply_age_band_loss(resource_type, subtype_name, int(split[subtype_name]))
