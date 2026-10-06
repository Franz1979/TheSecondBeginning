class_name CutAction
extends Action

# Taglio di una singola pianta, albero o arbusto (2026-10-04, richiesta utente — task Cut, secondo step di cut.tres dopo
# il Walk). Richiede CHOPPING: l'attrezzo passa da solo dallo zaino alla cintura e, se manca, lo step resta in attesa
# con l'avviso nel pannello (ensure_required_tools, come ClearAction). Durata di base da PlantCutService (1 giorno per
# un albero, mezzo per un arbusto), divisa per l'efficienza dell'attrezzo e per il fattore della skill (chiave "cut").
#
# Il lavoro già fatto vive su MacroCellState.cut_work_progress, non sull'istanza: una task interrotta e ridata riparte
# da dove era (stesso principio di ClearAction con Building.construction_progress). Al completamento: un uso
# dell'attrezzo, l'abbattimento (PlantCutService.cut: ceppo, ricrescita, numeri della cella, stick in più per un
# albero), la resa in un mucchio a terra accanto al ceppo e, se il mucchio c'è, la consegna al magazzino accodata
# allo stesso pipottino (HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL con "until_empty", tutti i
# viaggi finché il mucchio è vuoto). Se la pianta sparisce durante il lavoro la task si chiude.

# Come ClearAction.STAMINA_DRAIN_PER_DAY.
const STAMINA_DRAIN_PER_DAY: float = 200.0

# Emesso a pianta abbattuta: GameScene ridisegna la vegetazione della cella (_on_plant_cut).
signal plant_cut(macro_coords: Vector2i, object_type: GameTypes.WorldObjectType, individual_key: Vector3i)

var macro_coords: Vector2i = Vector2i.ZERO
var object_type: GameTypes.WorldObjectType = GameTypes.WorldObjectType.TREE
var individual_key: Vector3i = Vector3i.ZERO
var _aborted: bool = false


func _init(
	p_macro_coords: Vector2i = Vector2i.ZERO,
	p_object_type: GameTypes.WorldObjectType = GameTypes.WorldObjectType.TREE,
	p_individual_key: Vector3i = Vector3i.ZERO
) -> void:
	target = null
	macro_coords = p_macro_coords
	object_type = p_object_type
	individual_key = p_individual_key
	required_tool_categories = [TaskTypes.ToolCategory.CHOPPING]
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	skill_effect_key = "cut"


# Chiave del bersaglio in MacroCellState.cut_work_progress: "tipo|x|y|indice". Condivisa con QuarryAction (tipo ROCK,
# indice 0), così il lavoro di taglio e quello di estrazione vivono nello stesso registro senza collidere.
static func progress_key(p_object_type: int, p_individual_key: Vector3i) -> String:
	return "%d|%d|%d|%d" % [p_object_type, p_individual_key.x, p_individual_key.y, p_individual_key.z]


func is_same_plant(p_macro_coords: Vector2i, p_object_type: int, p_individual_key: Vector3i) -> bool:
	return macro_coords == p_macro_coords and int(object_type) == p_object_type and individual_key == p_individual_key


func _get_macro_state() -> MacroCellState:
	var world: World = GameSettings.active_world
	if world == null:
		return null
	return world.get_cell_state_at(macro_coords.x, macro_coords.y)


func is_target_valid() -> bool:
	return PlantCutService.is_individual_alive(_get_macro_state(), object_type, individual_key)


func _get_work_done() -> float:
	var macro_state := _get_macro_state()
	if macro_state == null:
		return 0.0
	return float(macro_state.cut_work_progress.get(progress_key(object_type, individual_key), 0.0))


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _aborted:
		return 0.0
	if not is_target_valid():
		_aborted = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "pianta da tagliare sparita"
		return 0.0
	var duration := PlantCutService.get_base_duration_days(object_type)
	if _get_work_done() >= duration:
		return 0.0
	if not ensure_required_tools(individual):
		return 0.0
	var rate := get_tool_efficiency(individual, TaskTypes.ToolCategory.CHOPPING) * SkillEffectService.get_factor_for_action(self, individual, context)
	_get_macro_state().cut_work_progress[progress_key(object_type, individual_key)] = _get_work_done() + delta * rate
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if _aborted:
		return true
	return is_target_valid() and _get_work_done() >= PlantCutService.get_base_duration_days(object_type)


# Un punto dentro la microcella della pianta (coordinate dell'individuo, stessa conversione delle altre Action).
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	var macro_offset: Vector2 = Vector2(macro_coords - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(individual_key.x, individual_key.y) + macro_offset)


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _aborted or not is_target_valid():
		return
	var macro_state := _get_macro_state()
	var game_data: GameData = GameSettings.active_game_data
	var current_year: int = game_data.year if game_data != null else 0
	var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, game_data)
	if not broken.is_empty():
		report_broken_tools(individual, broken)
	var yield_data := PlantCutService.cut(macro_state, object_type, individual_key, current_year)
	macro_state.cut_work_progress.erase(progress_key(object_type, individual_key))
	drop_yield_and_queue_haul(context, game_data, macro_coords, Vector2(individual_key.x, individual_key.y) + Vector2(0.5, 0.5), yield_data, "task_cut_name")
	# Taglio in zona (2026-10-06): la zona passa al mucchio e da lì alla consegna, per l'etichetta "Taglio (Zona 1)".
	if context.has(CutZoneService.CONTEXT_WORK_AREA_ID) and context.has(HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL):
		context[HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL][CutZoneService.CONTEXT_WORK_AREA_ID] = context[CutZoneService.CONTEXT_WORK_AREA_ID]
	# Serie in zona (2026-10-06, passo 3, come QuarryAction): un taglio in più; passa al mucchio e da lì alla consegna,
	# alla cui chiusura nasce il taglio successivo.
	var series := CutZoneService.get_series(context)
	if not series.is_empty():
		series = series.duplicate()
		series["done"] = int(series.get("done", 0)) + 1
		context[CutZoneService.CONTEXT_SERIES] = series
		if context.has(HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL):
			context[HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL][CutZoneService.SERIES_ZONE_KEY] = series
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[CUT] #%d %s: abbattuto %s %s in %s -> %s%s." % [
			individual.id, individual.name, GameTypes.WorldObjectType.keys()[object_type], str(individual_key), str(macro_coords),
			str(yield_data), "" if broken.is_empty() else ", attrezzi rotti: %s" % str(broken)
		])
	plant_cut.emit(macro_coords, object_type, individual_key)


# Identità della pianta: il lavoro già fatto è su MacroCellState, nessun progresso da salvare qui.
func get_save_data() -> Dictionary:
	return {
		"cut_macro_x": macro_coords.x,
		"cut_macro_y": macro_coords.y,
		"cut_object_type": int(object_type),
		"cut_x": individual_key.x,
		"cut_y": individual_key.y,
		"cut_i": individual_key.z,
	}
