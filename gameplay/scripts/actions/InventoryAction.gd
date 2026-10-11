class_name InventoryAction
extends Action

# Inventario del magazzino (2026-10-11, richiesta utente — gestore del magazzino). Lo step di lavoro della task
# inventory.tres (dopo il cammino fino al deposito): all'inizio il magazzino "conta" (GameScene, on_started: foto delle
# scorte e ordini decisi, tenuti nascosti) e restituisce quanti ordini nuovi emetterà; la durata è
# (1 h + 1 h × ordini nuovi) / fattore della skill Gestione (SkillEffectService, chiave SKILL_EFFECT_KEY); alla fine
# (on_finished) gli ordini escono in coda e parte l'intervallo per il prossimo inventario. Le due chiamate a GameScene
# passano da Callable statiche impostate da GameScene, come JobBoardService.job_taker.
# Salvataggio: edificio, durata decisa ed elapsed (load_save_data per lo step corrente); un inventario interrotto e
# ripreso dopo un caricamento continua dal tempo raggiunto, senza ricontare.

const SKILL_EFFECT_KEY := "inventory"
const BASE_HOURS: float = 1.0
const HOURS_PER_NEW_ORDER: float = 1.0
const STAMINA_DRAIN_PER_DAY: float = 60.0

# (individual, building) -> int: ordini nuovi decisi all'inizio dell'inventario.
static var on_started: Callable = Callable()
# (individual, building) -> void: fine dell'inventario.
static var on_finished: Callable = Callable()

var target_building: Building = null
var _started: bool = false
var _duration_days: float = 0.0
var _elapsed: float = 0.0
var _aborted: bool = false


func _init(p_target_building: Building = null) -> void:
	target = null
	target_building = p_target_building
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	skill_effect_key = SKILL_EFFECT_KEY


func is_target_valid() -> bool:
	return target_building != null and not target_building.is_demolished and target_building.is_complete


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _aborted:
		return 0.0
	if not is_target_valid():
		_aborted = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "deposito dell'inventario non più valido"
		return 0.0
	if not _started:
		_started = true
		var new_orders := 0
		if on_started.is_valid():
			new_orders = int(on_started.call(individual, target_building))
		var factor := maxf(SkillEffectService.get_factor_for_action(self, individual, context), 0.01)
		_duration_days = (BASE_HOURS + HOURS_PER_NEW_ORDER * float(new_orders)) / 24.0 / factor
	_elapsed += delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if _aborted:
		return true
	return _started and _elapsed >= _duration_days


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _aborted or not _started:
		return
	if on_finished.is_valid():
		on_finished.call(individual, target_building)


# Ore ancora da contare (per le scritte dei pannelli); -1 se il conteggio non è ancora iniziato.
func get_remaining_hours() -> float:
	if not _started:
		return -1.0
	return maxf(_duration_days - _elapsed, 0.0) * 24.0


func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + macro_offset)


func get_save_data() -> Dictionary:
	var data := {"started": _started, "duration_days": _duration_days, "elapsed": _elapsed}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


func load_save_data(data: Dictionary) -> void:
	_started = bool(data.get("started", false))
	_duration_days = float(data.get("duration_days", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
