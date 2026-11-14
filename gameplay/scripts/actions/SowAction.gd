class_name SowAction
extends Action

# Semina di un lotto (2026-11-15, orto delle prove e campi — sow.tres): il Walk prima porta sulla microcella del lotto
# (CultivationService.CONTEXT_LOT_CELL nel context). All'arrivo i semi dello zaino passano sul lotto (CropLot.seeds); poi
# lavoro col bastone da scavo (categoria Semina, un uso per lotto) fino a CultivationService.sowing_labor,
# più svelto con l'Agricoltura (SkillEffectService "sow"). Il lavoro sta sul lotto (CropLot.labor). Finito: once seminate e punti (1 per oncia). Fuori stagione o
# terreno non più da seminare: la tappa si chiude (la parte fatta la chiude CultivationService.advance_daily).

const STAMINA_DRAIN_PER_DAY: float = 150.0

var garden: Building = null
var lot: CropLot = null
# Attrezzi del capanno (2026-11-15, passo 2c — CultivationService.CONTEXT_SHED_TOOLS): letto dal context col lotto.
var uses_shed_tools: bool = false
# Questo lavoratore ha lavorato il lotto (paga l'uso dell'attrezzo quando il lotto si chiude, _wear_tools_for_lot).
var _worked: bool = false


func _init(p_garden: Building) -> void:
	target = null
	garden = p_garden
	skill_effect_key = CultivationService.SKILL_EFFECT_KEY
	required_tool_categories = CultivationService.SOWING_TOOLS.duplicate()
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, _context: Dictionary, delta: float) -> float:
	_resolve_lot(_context)
	if not _can_work():
		return 0.0
	_drop_seeds(individual)
	if lot.seeds <= 0:
		return 0.0
	if not ensure_required_tools(individual):
		return 0.0
	_worked = true
	# Lavoro come la produzione (150 al giorno × Agricoltura); il moltiplicatore dell'orto sta nel lavoro richiesto.
	lot.labor += STAMINA_DRAIN_PER_DAY * delta * SkillEffectService.get_factor_for_action(self, individual, _context)
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(_individual: Variant, _context: Dictionary) -> bool:
	_resolve_lot(_context)
	return not _can_work() or lot.seeds <= 0 or lot.labor >= CultivationService.sowing_labor(garden)


func on_complete(individual: Variant, context: Dictionary) -> void:
	_resolve_lot(context)
	_drop_seeds(individual)
	if _can_work() and lot.seeds > 0 and lot.labor >= CultivationService.sowing_labor(garden):
		var points := CultivationService.finish_sowing(garden, lot, 1.0)
		if not points.is_empty():
			DomesticPlantCalculator.add_pending_points(context, points)
	# Lotto chiuso (finito qui o dalla fine della stagione): un uso dell'attrezzo.
	if not _can_work():
		_wear_tools_for_lot(individual)


func _resolve_lot(context: Dictionary) -> void:
	if lot == null:
		lot = CultivationService.lot_from_context(garden, context)
		uses_shed_tools = bool(context.get(CultivationService.CONTEXT_SHED_TOOLS, false))


# Con gli attrezzi del capanno il pipottino deve coprire solo ciò che il capanno non copre (come ProduceAction).
func get_tool_categories_for_individual() -> Array[TaskTypes.ToolCategory]:
	return CultivationService.worker_tool_categories(garden, ToolGateService.get_action_required_categories(self), uses_shed_tools)


func _can_work() -> bool:
	return garden != null and lot != null and not garden.is_demolished \
		and CultivationService.needs_sowing(GameSettings.active_game_data, garden, lot)


# I semi della specie nello zaino passano sul terreno (fino a quanti ne vuole); poi, nel campo, il resto dal capanno senza
# viaggio (2026-11-15, passo 3c — FieldSeedStoreService.take_for_lot).
func _drop_seeds(individual: Variant) -> void:
	if garden == null or lot == null or not (individual is HumanIndividual):
		return
	var seed_name := CultivationService.seed_resource(garden)
	var wanted := CultivationService.seeds_wanted(garden, lot)
	if seed_name == "" or wanted <= 0:
		return
	if individual.get_carried_quantity(seed_name) > 0:
		lot.seeds += individual.remove_carried_resource(seed_name, wanted)
	FieldSeedStoreService.take_for_lot(garden, lot)


# Un uso dell'attrezzo per lotto (2026-11-15, richiesta utente — come accetta e piccone, che pagano un uso per pianta
# tagliata o pezzo estratto, non per tempo): lo paga chi sta lavorando il lotto quando il lotto si chiude, finito da lui
# o chiuso dalla fine della stagione, sul pezzo del capanno se lavora con quello. Chi ha lasciato il lotto a metà non
# paga; un lotto chiuso dalla stagione senza nessuno al lavoro non lo paga nessuno.
func _wear_tools_for_lot(individual: Variant) -> void:
	if not _worked or not (individual is HumanIndividual):
		return
	_worked = false
	var broken := CultivationService.wear_tools(individual, garden, required_tool_categories, uses_shed_tools, GameSettings.active_game_data)
	report_broken_tools(individual, broken)


func get_save_data() -> Dictionary:
	return {"sow_garden_id": garden.id if garden != null else -1, "worked": _worked}


func load_save_data(data: Dictionary) -> void:
	_worked = bool(data.get("worked", float(data.get("tool_wear_days", 0.0)) > 0.0))
