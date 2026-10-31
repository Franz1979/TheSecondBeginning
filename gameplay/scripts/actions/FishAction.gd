class_name FishAction
extends Action

# Pesca con la lenza nel ruscello (2026-10-31, richiesta utente — task Fish, secondo step di fish.tres dopo il Walk alla
# riva). Richiede FISHING (la lenza passa da sola dallo zaino alla cintura — ensure_required_tools).
# Sessione (2026-10-31, richiesta utente): si pesca per SESSION_DAYS (circa 6 ore), un tentativo ogni ATTEMPT_DAYS: un uso
# della lenza e CATCH_CHANCE di prendere un pesce; preso, un pesce in meno nella microcella del ruscello
# (StreamFishService.take_fish) e un pesce crudo (fish_meat) nello zaino, e si continua. La sessione finisce allo scadere
# del tempo, o prima se la microcella resta senza pesci, se la lenza si rompe o se lo zaino non ha posto; si può tornare a
# mani vuote. La skill di pesca alza la probabilità di presa (chiave "fish", come "hunt_throw" per la caccia). Le stesse sessioni saranno il mattone delle serie (area di lavoro, gestore scorte).
# Consegna come la carne della caccia (2026-10-31, richiesta utente — il pesce si comporta sempre come la carne): a fine
# sessione, se ha preso qualcosa, tutto il pescato in un solo viaggio con la stessa richiesta della raccolta della
# macellazione (context "pending_warehouse_search", consumata da HumanIndividualActionService._handle_pending_warehouse_
# search a fine step): la Task si allunga con Walk + Unload, prima i bisogni (HuntProductAllocationService) poi la
# destinazione della carne scritta nel context dal comando (ButcherDestinationService.CONTEXT_KEY). Senza pescato nessuna
# consegna; un fermo anticipato senza pescato chiude la Task con il motivo per il giocatore.
# Tempo della sessione, del tentativo in corso e pesci presi si salvano (get_save_data/load_save_data).
# Serie nelle zone (2026-10-31, richiesta utente — pesca nelle aree di lavoro, passo 3; serie nel context,
# FishZoneService.CONTEXT_SERIES): niente tempo della sessione, si pesca di fila. Il viaggio di consegna parte quando i pesci
# in mano (quelli portati dai punti di prima, "in_hand", più quelli presi qui) arrivano a quelli che mancano, quando lo
# zaino è pieno, quando la zona resta senza pesci o quando la lenza si rompe senza un ricambio addosso (questi ultimi due
# fermano anche la serie, "stop_reason"). Punto vuoto con altri punti liberi nella zona: la Task finisce senza consegna e
# la serie riparte dal punto nuovo con i pesci in mano. Lenza rotta con un ricambio addosso: si continua (ensure_required_
# tools lo passa in cintura).

const SESSION_DAYS: float = 0.25
const ATTEMPT_DAYS: float = 0.04
const CATCH_CHANCE: float = 0.3
const STAMINA_DRAIN_PER_DAY: float = 100.0
const CAUGHT_RESOURCE_NAME := "fish_meat"

# Emesso a pesce preso: GameScene ridisegna i pesciolini della cella (_on_stream_fish_caught).
signal stream_fish_caught(macro_coords: Vector2i, fish_position: Vector2i)

var macro_coords: Vector2i = Vector2i.ZERO
var fish_position: Vector2i = Vector2i.ZERO
var _elapsed: float = 0.0
var _session_elapsed: float = 0.0
var _caught_count: int = 0
var _finished: bool = false


func _init(p_macro_coords: Vector2i = Vector2i.ZERO, p_fish_position: Vector2i = Vector2i.ZERO) -> void:
	target = null
	macro_coords = p_macro_coords
	fish_position = p_fish_position
	required_tool_categories = [TaskTypes.ToolCategory.FISHING]
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	skill_effect_key = "fish"


func is_same_spot(p_macro_coords: Vector2i, p_fish_position: Vector2i) -> bool:
	return macro_coords == p_macro_coords and fish_position == p_fish_position


func _current_fish() -> int:
	var cell := PathfindingService.get_live_cell(macro_coords)
	var game_data: GameData = GameSettings.active_game_data
	if cell == null or game_data == null:
		return 0
	return StreamFishService.get_fish(cell.macro_state, cell.stream_positions, macro_coords.x, macro_coords.y, fish_position, game_data.get_absolute_day())


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _finished:
		return 0.0
	if not ensure_required_tools(individual):
		return 0.0
	_elapsed += delta
	_session_elapsed += delta
	while _elapsed >= ATTEMPT_DAYS and not _finished:
		_elapsed -= ATTEMPT_DAYS
		_attempt(individual, context)
	if not _finished and _session_elapsed >= SESSION_DAYS and not _in_series(context):
		_end_session(individual, context, "tempo scaduto", "")
	return -STAMINA_DRAIN_PER_DAY * delta


func _attempt(individual: Variant, context: Dictionary) -> void:
	var timing_start := Time.get_ticks_usec()
	_attempt_inner(individual, context)
	_log_timing(individual, "tentativo", timing_start)


# Misura temporanea (DebugLogging.SHOW_FISH_TIMING_LOGS): una riga solo sopra FISH_TIMING_SLOW_MSEC.
func _log_timing(individual: Variant, what: String, since: int) -> void:
	if not (DebugLogging.ENABLED and DebugLogging.SHOW_FISH_TIMING_LOGS):
		return
	var msec := float(Time.get_ticks_usec() - since) / 1000.0
	if msec >= DebugLogging.FISH_TIMING_SLOW_MSEC:
		print("[FISH TIMING] #%d %s: %s %.2f ms." % [individual.id, individual.name, what, msec])


func _attempt_inner(individual: Variant, context: Dictionary) -> void:
	var in_series := _in_series(context)
	if _current_fish() <= 0:
		if in_series:
			_series_spot_empty(individual, context)
		else:
			_end_session(individual, context, "punto senza pesci", GameContext.tr_text("fish_reject_empty"))
		return
	if not _has_room(individual):
		var no_room := HumanIndividualActionService.no_room_message(individual, [CAUGHT_RESOURCE_NAME])
		if in_series:
			# Con pesci in mano si consegna e si riprende; a mani vuote la serie si ferma.
			_end_series_trip(individual, context, "zaino pieno", no_room if _in_hand(context) <= 0 else "")
		else:
			_end_session(individual, context, "zaino pieno", no_room)
		return
	var game_data: GameData = GameSettings.active_game_data
	var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, game_data)
	# Skill di pesca (2026-10-31): alza la probabilità di presa, da CATCH_CHANCE a skill 0 fino a ×1,5 alla massima.
	var caught := randf() < CATCH_CHANCE * SkillEffectService.get_factor_for_action(self, individual, context)
	if caught:
		var cell := PathfindingService.get_live_cell(macro_coords)
		caught = StreamFishService.take_fish(
			cell.macro_state, cell.stream_positions, macro_coords.x, macro_coords.y, fish_position, game_data.get_absolute_day()
		)
		if caught:
			individual.add_carried_resource(CAUGHT_RESOURCE_NAME, 1)
			_caught_count += 1
	if DebugLogging.ENABLED and DebugLogging.SHOW_FISH_LOGS:
		print("[FISH] #%d %s: tentativo in %s %s -> %s (presi %d)%s." % [
			individual.id, individual.name, str(macro_coords), str(fish_position), "preso" if caught else "niente",
			_caught_count, "" if broken.is_empty() else ", lenza rotta: %s" % str(broken)
		])
	if caught:
		stream_fish_caught.emit(macro_coords, fish_position)
	if not broken.is_empty():
		report_broken_tools(individual, broken)
		if not in_series:
			_end_session(individual, context, "lenza rotta", "")
		elif not ToolGateService.has_tool_for(individual, TaskTypes.ToolCategory.FISHING):
			_end_series_trip(individual, context, "lenza rotta", GameContext.tr_text("series_stop_no_tool").format({
				"tools": ToolFetchService.describe_missing_categories([TaskTypes.ToolCategory.FISHING]),
			}))
			return
	if in_series and not _finished and _in_hand(context) >= FishZoneService.remaining(FishZoneService.get_series(context)):
		_end_series_trip(individual, context, "pesci che mancano presi", "")


# Fine della sessione: con pescato, la consegna di tutto in un viaggio (la Task prosegue); senza, un fermo anticipato
# chiude la Task con `reason` (e `player_message` per il giocatore), lo scadere del tempo la chiude normalmente.
func _end_session(individual: Variant, context: Dictionary, reason: String, player_message: String) -> void:
	_finished = true
	if DebugLogging.ENABLED and DebugLogging.SHOW_FISH_LOGS:
		print("[FISH] #%d %s: fine sessione (%s), presi %d." % [individual.id, individual.name, reason, _caught_count])
	if _caught_count > 0:
		context["pending_warehouse_search"] = {
			"searches": [{"resource_name": CAUGHT_RESOURCE_NAME, "quantity": _caught_count}],
			"excluded_building_ids": [],
		}
		return
	if reason == "tempo scaduto":
		return
	context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = reason
	if player_message != "":
		context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = player_message


func _in_series(context: Dictionary) -> bool:
	return not FishZoneService.get_series(context).is_empty()


# Pesci in mano nella serie: quelli portati dai punti di prima più quelli presi in questa sessione.
func _in_hand(context: Dictionary) -> int:
	return int(FishZoneService.get_series(context).get("in_hand", 0)) + _caught_count


# Punto vuoto nella serie: un altro punto libero nella zona = la Task finisce senza consegna (la serie riparte da lì con
# i pesci in mano); nessuno = consegna di quello che c'è e serie ferma.
func _series_spot_empty(individual: Variant, context: Dictionary) -> void:
	var series := FishZoneService.get_series(context)
	var area := WorkAreaService.find_by_id(GameSettings.active_game_data, int(series.get("work_area_id", -1)))
	var next_spot: Variant = null
	if area != null:
		var timing_start := Time.get_ticks_usec()
		next_spot = FishZoneService.choose_spot(area, individual, FishZoneService.collect_reserved_spots(GameSettings.active_human_individuals))
		_log_timing(individual, "scelta di un altro punto", timing_start)
	if next_spot == null:
		_end_series_trip(individual, context, "zona senza pesci", GameContext.tr_text("fish_series_stop_no_fish"))
		return
	_finished = true
	series["in_hand"] = _in_hand(context)
	context[FishZoneService.CONTEXT_SERIES] = series
	if DebugLogging.ENABLED and DebugLogging.SHOW_FISH_LOGS:
		print("[FISH] #%d %s: punto vuoto, si passa a %s con %d pesci in mano." % [individual.id, individual.name, str(next_spot), int(series["in_hand"])])


# Fine del viaggio di pesca nella serie: consegna di tutti i pesci in mano in un solo viaggio (stessa richiesta della
# pesca col clic destro); `stop_reason` (tradotto, "" = nessuno) ferma la serie dopo la consegna.
func _end_series_trip(individual: Variant, context: Dictionary, reason: String, stop_reason: String) -> void:
	_finished = true
	var series := FishZoneService.get_series(context)
	var in_hand := _in_hand(context)
	if DebugLogging.ENABLED and DebugLogging.SHOW_FISH_LOGS:
		print("[FISH] #%d %s: fine del viaggio (%s), %d pesci da consegnare." % [individual.id, individual.name, reason, in_hand])
	if in_hand > 0:
		context["pending_warehouse_search"] = {
			"searches": [{"resource_name": CAUGHT_RESOURCE_NAME, "quantity": in_hand}],
			"excluded_building_ids": [],
		}
	series["in_hand"] = 0
	if stop_reason != "":
		series["stop_reason"] = stop_reason
	context[FishZoneService.CONTEXT_SERIES] = series


func _has_room(individual: Variant) -> bool:
	if not individual.can_carry_variety(CAUGHT_RESOURCE_NAME):
		return false
	var rules := CaloricCalculator.get_caloric_source_rules(CAUGHT_RESOURCE_NAME)
	if rules == null or rules.space_per_unit <= 0.0:
		return true
	var free_space: float = individual.max_carry_capacity - individual.get_carried_space()
	return int(floor(free_space / rules.space_per_unit + FoodSelectionService.UNIT_FIT_EPSILON)) >= 1


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _finished


func get_save_data() -> Dictionary:
	return {
		"fish_macro_x": macro_coords.x,
		"fish_macro_y": macro_coords.y,
		"fish_x": fish_position.x,
		"fish_y": fish_position.y,
		"elapsed": _elapsed,
		"session_elapsed": _session_elapsed,
		"caught_count": _caught_count,
	}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	_session_elapsed = float(data.get("session_elapsed", 0.0))
	_caught_count = int(data.get("caught_count", 0))
