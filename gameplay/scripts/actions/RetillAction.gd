class_name RetillAction
extends Action

# Rizollatura di un lotto del campo (2026-11-15, richiesta utente — Cura del campo, passo 2 — retill.tres): il Walk prima
# porta sulla microcella del lotto (CultivationService.CONTEXT_LOT_CELL). Lavoro col piccone (categoria Scavo, un uso per
# lotto) fino a FieldFertilityService.retill_labor, più svelto con l'Agricoltura (come la Semina). Il lavoro sta sul
# lotto (CropLot.labor: il lotto è vuoto e la Semina lo aspetta). Finito: FieldFertilityService.finish_retill (+30% di
# fertilità diviso per i lotti). Finita la finestra della rizollatura: la tappa si chiude.

const STAMINA_DRAIN_PER_DAY: float = 150.0

var garden: Building = null
var lot: CropLot = null
# Questo lavoratore ha lavorato il lotto (paga l'uso dell'attrezzo quando il lotto si chiude).
var _worked: bool = false


func _init(p_garden: Building) -> void:
	target = null
	garden = p_garden
	skill_effect_key = CultivationService.SKILL_EFFECT_KEY
	required_tool_categories = FieldFertilityService.RETILL_TOOLS.duplicate()
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_resolve_lot(context)
	if not _can_work():
		return 0.0
	if not ensure_required_tools(individual):
		return 0.0
	_worked = true
	lot.labor += STAMINA_DRAIN_PER_DAY * delta * SkillEffectService.get_factor_for_action(self, individual, context)
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(_individual: Variant, context: Dictionary) -> bool:
	_resolve_lot(context)
	return not _can_work() or lot.labor >= FieldFertilityService.retill_labor(garden)


func on_complete(individual: Variant, context: Dictionary) -> void:
	_resolve_lot(context)
	if _can_work() and lot.labor >= FieldFertilityService.retill_labor(garden):
		FieldFertilityService.finish_retill(garden, lot)
	# Lotto chiuso (rizollato qui o finita la finestra): un uso del piccone.
	if not _can_work():
		_wear_tools_for_lot(individual)


func _resolve_lot(context: Dictionary) -> void:
	if lot == null:
		lot = CultivationService.lot_from_context(garden, context)


func _can_work() -> bool:
	return garden != null and lot != null and not garden.is_demolished \
		and FieldFertilityService.needs_retill(GameSettings.active_game_data, garden, lot)


func _wear_tools_for_lot(individual: Variant) -> void:
	if not _worked or not (individual is HumanIndividual):
		return
	_worked = false
	var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, GameSettings.active_game_data)
	report_broken_tools(individual, broken)


func get_save_data() -> Dictionary:
	return {"retill_garden_id": garden.id if garden != null else -1, "worked": _worked}


func load_save_data(data: Dictionary) -> void:
	_worked = bool(data.get("worked", false))
