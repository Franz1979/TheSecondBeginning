class_name SetTrapAction
extends Action

# Montaggio della trappola sul posto (2026-11-07, capanna del trappoliere — lavoro "Piazza trappola", place_trap.tres): il
# Walk prima porta alla microcella scelta (TrapService.choose_site, nel context). Lavoro di trap_setup_days giorni, più
# svelto con la Caccia (SkillEffectService "trap"). Alla fine la trappola esce dallo zaino con i suoi usi e diventa una
# PlacedTrap (TrapService.place). Senza trappola nello zaino la Task si chiude con il motivo.

# Fatica del montaggio, come le altre azioni da fermo (ButcherAction).
const STAMINA_DRAIN_PER_DAY: float = 150.0

var _elapsed: float = 0.0


func _init() -> void:
	target = null
	skill_effect_key = TrapService.SKILL_EFFECT_KEY
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Skill della trappola che si monta (2026-11-08: pesca per la nassa).
func get_skill_effect_key(_individual: Variant, context: Dictionary) -> String:
	var rules := TrapService.get_rules(String(context.get(TrapService.CONTEXT_TRAP_NAME, "")))
	return rules.trap_skill_effect_key if rules != null else skill_effect_key


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta * SkillEffectService.get_factor_for_action(self, individual, context)
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(_individual: Variant, context: Dictionary) -> bool:
	var rules := TrapService.get_rules(String(context.get(TrapService.CONTEXT_TRAP_NAME, "")))
	return _elapsed >= (rules.trap_setup_days if rules != null else 0.0)


func on_complete(individual: Variant, context: Dictionary) -> void:
	var trap_name := String(context.get(TrapService.CONTEXT_TRAP_NAME, ""))
	var units: Array = individual.take_carried_tool_units(trap_name, 1) if trap_name != "" else []
	var game_data: GameData = GameSettings.active_game_data
	if units.is_empty() or game_data == null:
		var message := GameContext.tr_text("trap_fail_not_carried").format({"name": individual.name})
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = message
		context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = message
		return
	var macro_coords := Vector2i(int(context.get(TrapService.CONTEXT_MACRO_X, 0)), int(context.get(TrapService.CONTEXT_MACRO_Y, 0)))
	var lot := Vector2i(int(context.get(TrapService.CONTEXT_LOT_X, 0)), int(context.get(TrapService.CONTEXT_LOT_Y, 0)))
	var trap := TrapService.place(game_data, GameSettings.active_world, trap_name, units[0], macro_coords, lot, int(context.get(TrapService.CONTEXT_AREA_ID, 0)))
	TrapService.log_line("#%d %s monta %s #%d in macrocella %s microcella %s (zona #%d), usi %d, indice del posto %.2f" % [
		individual.id, individual.name, trap_name, trap.id, macro_coords, lot, trap.work_area_id, trap.get_remaining_uses(), trap.site_index
	])


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
