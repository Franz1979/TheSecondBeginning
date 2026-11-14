class_name TakeSeedsAction
extends Action

# Presa dei semi per la Semina (2026-11-15, orto delle prove — sow.tres): dal magazzino raggiunto (il Walk prima porta lì)
# le once della specie che il lotto vuole ancora (CultivationService.seeds_wanted), quante ne entrano nello zaino. Nessun
# seme preso: la Task si chiude con il motivo.

const DURATION_DAYS: float = 0.005

var source_building: Building = null
var _elapsed: float = 0.0


func _init(p_source_building: Building) -> void:
	target = null
	source_building = p_source_building
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(_individual: Variant, _context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(_individual: Variant, _context: Dictionary) -> bool:
	return _elapsed >= DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	var garden := _garden(context)
	var lot := CultivationService.lot_from_context(garden, context)
	var taken := 0
	if garden != null and lot != null and source_building != null and not source_building.is_demolished:
		var seed_name := CultivationService.seed_resource(garden)
		# Quelle che il capanno del campo darà sul lotto non si prendono (2026-11-15, passo 3c).
		var wanted := maxi(CultivationService.seeds_wanted(garden, lot) - int(context.get(CultivationService.CONTEXT_SHED_SEEDS, 0)), 0)
		var rules := CaloricCalculator.get_caloric_source_rules(seed_name)
		var space := rules.space_per_unit if rules != null else 0.0
		var free: float = individual.max_carry_capacity - individual.get_carried_space() + FoodSelectionService.UNIT_FIT_EPSILON
		var fitting := wanted if space <= 0.0 else mini(wanted, int(floor(free / space)))
		if fitting > 0 and seed_name != "" and individual.can_carry_variety(seed_name):
			var decay := float((source_building.stored_resources.get(seed_name, {}) as Dictionary).get("decay_fraction", 0.0))
			var withdrawn := BuildingStorageService.withdraw_auto(source_building, seed_name, fitting)
			if withdrawn > 0:
				taken = individual.add_carried_resource(seed_name, withdrawn, decay)
				if taken < withdrawn:
					BuildingStorageService.store(source_building, seed_name, withdrawn - taken, decay)
		CultivationService.log_line("#%d %s prende %d once di %s da %s #%d (volute %d)" % [
			individual.id, individual.name, taken, seed_name, source_building.building_type_name, source_building.id, wanted])
	if taken <= 0:
		var message := GameContext.tr_text("sow_fail_no_seeds").format({"name": individual.name})
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = message
		context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = message


func _garden(context: Dictionary) -> Building:
	var world: World = GameSettings.active_world
	if world == null:
		return null
	var garden_id := int(context.get(CultivationService.CONTEXT_BUILDING_ID, -1))
	for building in world.buildings:
		if building.id == garden_id:
			return building
	return null


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "seed_building_id": source_building.id if source_building != null else -1}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
