class_name QuarryAction
extends Action

# Estrazione della pietra da una roccia (2026-10-05, richiesta utente — task Quarry, secondo step di quarry.tres dopo il
# Walk). Gemella di CutAction: richiede DIGGING (l'attrezzo passa da solo dallo zaino alla cintura e, se manca, lo step
# resta in attesa con l'avviso nel pannello — ensure_required_tools); durata di base BASE_DURATION_DAYS divisa per
# l'efficienza dell'attrezzo e per il fattore della skill (chiave "quarry").
#
# Il lavoro già fatto vive su MacroCellState.cut_work_progress (chiave CutAction.progress_key con tipo ROCK), non
# sull'istanza: una task interrotta e ridata riparte da dove era, e si salva con la macrocella come per il taglio. Al
# completamento: un uso dell'attrezzo, l'estrazione (RockStoneService.extract: roccia tolta, resource_quantity[ROCK]
# più basso, sassi di scarto sulla roccia), la pietra in un mucchio a terra accanto alla roccia e la consegna al
# magazzino accodata allo stesso pipottino "fino a mucchio vuoto" (Action.drop_yield_and_queue_haul). Se la roccia si
# esaurisce durante il lavoro la task si chiude.

const BASE_DURATION_DAYS: float = 1.0
const STAMINA_DRAIN_PER_DAY: float = 300.0

# Emesso a estrazione avvenuta: GameScene ridisegna i sassi della roccia e aggiorna il pannello (_on_rock_quarried).
signal rock_quarried(macro_coords: Vector2i, rock_position: Vector2i)

var macro_coords: Vector2i = Vector2i.ZERO
var rock_position: Vector2i = Vector2i.ZERO
var _aborted: bool = false


func _init(p_macro_coords: Vector2i = Vector2i.ZERO, p_rock_position: Vector2i = Vector2i.ZERO) -> void:
	target = null
	macro_coords = p_macro_coords
	rock_position = p_rock_position
	required_tool_categories = [TaskTypes.ToolCategory.DIGGING]
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	skill_effect_key = "quarry"


func _progress_key() -> String:
	return CutAction.progress_key(GameTypes.WorldObjectType.ROCK, Vector3i(rock_position.x, rock_position.y, 0))


func is_same_rock(p_macro_coords: Vector2i, p_rock_position: Vector2i) -> bool:
	return macro_coords == p_macro_coords and rock_position == p_rock_position


func _get_macro_state() -> MacroCellState:
	var world: World = GameSettings.active_world
	if world == null:
		return null
	return world.get_cell_state_at(macro_coords.x, macro_coords.y)


# Valida finché la roccia ha ancora pietra (0 anche se in quella posizione non c'è una roccia).
func is_target_valid() -> bool:
	return RockStoneService.get_remaining_stone(_get_macro_state(), rock_position) > 0


func _get_work_done() -> float:
	var macro_state := _get_macro_state()
	if macro_state == null:
		return 0.0
	return float(macro_state.cut_work_progress.get(_progress_key(), 0.0))


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _aborted:
		return 0.0
	if not is_target_valid():
		_aborted = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "roccia esaurita"
		return 0.0
	if _get_work_done() >= BASE_DURATION_DAYS:
		return 0.0
	if not ensure_required_tools(individual):
		return 0.0
	var rate := get_tool_efficiency(individual, TaskTypes.ToolCategory.DIGGING) * SkillEffectService.get_factor_for_action(self, individual, context)
	_get_macro_state().cut_work_progress[_progress_key()] = _get_work_done() + delta * rate
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if _aborted:
		return true
	return is_target_valid() and _get_work_done() >= BASE_DURATION_DAYS


# Un punto dentro la microcella della roccia (stessa conversione di CutAction; la microcella è un ostacolo, ma il
# percorso tratta sempre la destinazione come attraversabile, come per la raccolta dei sassi).
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	var macro_offset: Vector2 = Vector2(macro_coords - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(rock_position) + macro_offset)


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _aborted or not is_target_valid():
		return
	var macro_state := _get_macro_state()
	var game_data: GameData = GameSettings.active_game_data
	var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, game_data)
	if not broken.is_empty():
		report_broken_tools(individual, broken)
	var yield_data := RockStoneService.extract(macro_state, rock_position)
	macro_state.cut_work_progress.erase(_progress_key())
	drop_yield_and_queue_haul(context, game_data, macro_coords, Vector2(rock_position) + Vector2(0.5, 0.5), yield_data, "task_quarry_name")
	# Serie in zona (2026-10-05): un'estrazione in più, ultima roccia; passa al mucchio e da lì alla consegna, alla cui
	# chiusura nasce l'estrazione successiva. Senza mucchio (nessuna consegna) la serie si chiude qui.
	var series := QuarryZoneService.get_series(context)
	if not series.is_empty():
		series = series.duplicate()
		series["done"] = int(series.get("done", 0)) + 1
		series["rock_x"] = rock_position.x
		series["rock_y"] = rock_position.y
		context[QuarryZoneService.CONTEXT_SERIES] = series
		if context.has(HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL):
			context[HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL][QuarryZoneService.SERIES_ZONE_KEY] = series
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[QUARRY] #%d %s: estratta la roccia %s in %s -> %s%s." % [
			individual.id, individual.name, str(rock_position), str(macro_coords),
			str(yield_data), "" if broken.is_empty() else ", attrezzi rotti: %s" % str(broken)
		])
	rock_quarried.emit(macro_coords, rock_position)


# Identità della roccia: il lavoro già fatto è su MacroCellState, nessun progresso da salvare qui.
func get_save_data() -> Dictionary:
	return {
		"quarry_macro_x": macro_coords.x,
		"quarry_macro_y": macro_coords.y,
		"quarry_x": rock_position.x,
		"quarry_y": rock_position.y,
	}
