class_name PlantCutService
extends RefCounted

# Taglio di una singola pianta (2026-10-04, richiesta utente — task Cut): letture sulla pianta senza il renderer (età,
# resa, taglia del ceppo, durata) e l'abbattimento vero, che riusa PlayerHarvestService.cut_individual per ceppo,
# ricrescita e numeri della cella. Tutto dai dati di MacroCellState (anno di nascita e sottotipo congelati alla nascita
# dell'individuo), quindi vale anche per una cella non caricata. Stateless, funzioni statiche.

# Durata di base del taglio in giorni, come ClearAction (1 giorno per albero, mezzo per arbusto). Si divide per
# l'efficienza dell'attrezzo (SecondaryResourceRules.work_efficiency) e per il fattore della skill.
const BASE_DURATION_DAYS_BY_TYPE := {
	GameTypes.WorldObjectType.TREE: 1.0,
	GameTypes.WorldObjectType.SHRUB: 0.5,
}
# Stick raccoglibili in più sul lotto di un albero abbattuto (mai per un arbusto): conto del raccolto, vedi
# LotCapacityService.add_extra_units.
const EXTRA_STICKS_PER_TREE: int = 3
const EXTRA_STICK_RESOURCE_NAME := "stick"


static func is_cuttable_type(object_type: GameTypes.WorldObjectType) -> bool:
	return BASE_DURATION_DAYS_BY_TYPE.has(object_type)


static func get_base_duration_days(object_type: GameTypes.WorldObjectType) -> float:
	return float(BASE_DURATION_DAYS_BY_TYPE.get(object_type, 1.0))


static func _subtype_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype


static func _birth_year_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year


# true se l'individuo esiste ed è vivo (non tagliato, non morto: quelli perdono anno di nascita e sottotipo).
static func is_individual_alive(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> bool:
	if macro_state == null or not is_cuttable_type(object_type):
		return false
	return _subtype_store(macro_state, object_type).has(individual_key) and _birth_year_store(macro_state, object_type).has(individual_key)


static func get_subtype_name(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> String:
	return String(_subtype_store(macro_state, object_type).get(individual_key, ""))


# Fattore d'età del sottotipo (size_multiplier_by_age della fascia), stessa regola del renderer
# (MicroCellRenderer._resolve_age_band_and_size): 1.0 per un sottotipo senza fasce d'età.
static func get_age_size_factor(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, individual_key: Vector3i, current_year: int) -> float:
	var rule := ResourceCalculator.get_subtype_rule(object_type, get_subtype_name(macro_state, object_type, individual_key))
	var birth_year_store := _birth_year_store(macro_state, object_type)
	if rule == null or not rule.track_age_bands or not birth_year_store.has(individual_key):
		return 1.0
	var years_lived: int = current_year - int(birth_year_store[individual_key])
	var age_band: int = AgeBandVisualService.band_for_age(years_lived, rule.youth_duration_years, rule.adult_duration_years)
	if age_band < 0 or age_band >= rule.size_multiplier_by_age.size():
		return 1.0
	return float(rule.size_multiplier_by_age[age_band])


# Resa del taglio: {"resource_name", "quantity"} = base × fattore d'età, arrotondata, minimo 1. L'affollamento del lotto
# non conta. {} se il sottotipo non rende nulla.
static func compute_yield(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, individual_key: Vector3i, current_year: int) -> Dictionary:
	var rule := ResourceCalculator.get_subtype_rule(object_type, get_subtype_name(macro_state, object_type, individual_key))
	if rule == null or rule.cut_yield_resource_name == "" or rule.cut_yield_base <= 0:
		return {}
	var factor := get_age_size_factor(macro_state, object_type, individual_key, current_year)
	return {
		"resource_name": rule.cut_yield_resource_name,
		"quantity": maxi(roundi(float(rule.cut_yield_base) * factor), 1),
	}


# Taglia del ceppo per il disegno (vegetation_cut_exceptions.size_multiplier): fattore d'età × affollamento del lotto,
# la stessa formula che il renderer usa per la pianta viva (MicroCellRenderer._resolve_density_scale_and_offset_range),
# così il ceppo resta proporzionato a com'era la pianta.
static func compute_stump_size(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, individual_key: Vector3i, current_year: int) -> float:
	var lot_count := 0
	for key in _subtype_store(macro_state, object_type).keys():
		if key.x == individual_key.x and key.y == individual_key.y:
			lot_count += 1
	var density_scale: float = clampf(1.0 / sqrt(float(maxi(lot_count, 1))), MicroCellRenderer.MIN_DENSITY_SCALE, 1.0)
	return get_age_size_factor(macro_state, object_type, individual_key, current_year) * density_scale


# Abbatte la pianta: ceppo, ricrescita e numeri della cella (PlayerHarvestService.cut_individual) e, per un albero, gli
# stick in più sul lotto. Ritorna la resa (vedi compute_yield), {} se la pianta non c'è più o non rende nulla.
static func cut(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, individual_key: Vector3i, current_year: int) -> Dictionary:
	if not is_individual_alive(macro_state, object_type, individual_key):
		return {}
	# Resa e taglia lette PRIMA del taglio: cut_individual dimentica anno di nascita e sottotipo.
	var yield_data := compute_yield(macro_state, object_type, individual_key, current_year)
	var stump_size := compute_stump_size(macro_state, object_type, individual_key, current_year)
	var subtype_name := get_subtype_name(macro_state, object_type, individual_key)
	PlayerHarvestService.cut_individual(macro_state, object_type, individual_key, subtype_name, stump_size, current_year)
	if object_type == GameTypes.WorldObjectType.TREE:
		LotCapacityService.add_extra_units(
			macro_state, EXTRA_STICK_RESOURCE_NAME, Vector2i(individual_key.x, individual_key.y), EXTRA_STICKS_PER_TREE
		)
	return yield_data
