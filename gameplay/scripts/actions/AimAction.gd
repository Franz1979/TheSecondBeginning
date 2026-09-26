class_name AimAction
extends Action

# Prendere la mira su un bersaglio (2026-09-26, richiesta utente — caccia: mira e tiro separati, prima
# accorpati in HuntAction). Parametrizzata dal BERSAGLIO (CombatTarget), non dalla preda: servirà anche
# per il combattimento contro bersagli umani; oggi il bersaglio è sempre un animale.
#
# Dura AIM_DURATION_DAYS con il consumo di stamina abituale delle azioni stazionarie. A ogni tick:
#   - bersaglio sparito o perso di vista -> la mira termina; lo step successivo (ThrowAction, stesso
#     bersaglio) non è più valido e la Task si chiude (HumanIndividualActionService.finish_current_step);
#   - nessuna arma della categoria in cintura (rotta o riposta) -> la caccia si chiude;
#   - bersaglio uscito dalla gittata -> "tiro non partito": nessun uso dell'arma, nessuna fuga; la Task
#     torna ad avvicinarsi (Task.context[HuntService.CONTEXT_PENDING_REAPPROACH], vedi
#     HumanIndividualActionService._handle_pending_hunt_reapproach), con il tetto di HuntService.MAX_REAPPROACHES;
#   - altrimenti, allo scadere della durata, la mira è completa e si passa al lancio (ThrowAction).

# Durata della mira in giorni di gioco: 0.04 = 0.32 s reali a 1x.
const AIM_DURATION_DAYS: float = 0.04
# Stamina per giorno di gioco durante la mira: 200 × 0.04 = 8 punti (stesso ordine di Build/Produce).
const STAMINA_DRAIN_PER_DAY: float = 200.0

var combat_target: CombatTarget = null
# Categoria dell'arma richiesta: HUNTING per la caccia (in futuro COMBAT per il combattimento).
var weapon_category: TaskTypes.ToolCategory = TaskTypes.ToolCategory.HUNTING

# Progresso della mira (salvato: un load a metà mira riprende da dove era) e flag "mira terminata" (non
# salvato: quando è vero lo step si completa nello stesso frame).
var _elapsed: float = 0.0
var _done: bool = false


func _init(p_combat_target: CombatTarget = null, p_weapon_category: TaskTypes.ToolCategory = TaskTypes.ToolCategory.HUNTING) -> void:
	target = null
	combat_target = p_combat_target if p_combat_target != null else CombatTarget.new()
	weapon_category = p_weapon_category
	required_tool_categories = [weapon_category]
	disallowed_age_bands = attack_disallowed_age_bands(weapon_category)


# Fasce d'età escluse da un attacco con armi della categoria: la caccia è vietata a neonati, bambini e
# adolescenti (stesse fasce di ApproachPreyAction); ogni altra categoria a neonati e bambini. Condivisa con
# ThrowAction.
static func attack_disallowed_age_bands(category: TaskTypes.ToolCategory) -> Array[HumanTypes.AgeBand]:
	var bands: Array[HumanTypes.AgeBand] = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	if category == TaskTypes.ToolCategory.HUNTING:
		bands.append(HumanTypes.AgeBand.TEENAGER)
	return bands


func is_target_valid() -> bool:
	return combat_target.is_valid()


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_done = false
	HuntService.log_event(individual, "mira su %s iniziata (durata %.2f giorni, distanza %.2f, gittata %.2f)." % [
		combat_target.describe(), AIM_DURATION_DAYS, combat_target.distance_from(individual),
		HuntService.compute_reach(individual, weapon_category)
	])


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done:
		return 0.0
	var status := combat_target.get_status()
	if status != CombatTarget.Status.OK:
		_done = true
		HuntService.log_event(individual, "mira interrotta su %s: %s — la caccia verrà chiusa." % [
			combat_target.describe(), CombatTarget.describe_status(status)
		])
		return 0.0
	if HuntService.pick_weapon(individual, weapon_category) == "":
		_done = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "nessuna arma in cintura durante la mira"
		return 0.0
	var distance := combat_target.distance_from(individual)
	var reach := HuntService.compute_reach(individual, weapon_category)
	if distance > reach:
		# Tiro non partito: nessun uso dell'arma, nessuna fuga — si torna ad avvicinarsi.
		_done = true
		context[HuntService.CONTEXT_PENDING_REAPPROACH] = HuntService.REAPPROACH_AFTER_AIM
		HuntService.log_event(individual, "tiro NON PARTITO: %s uscito dalla gittata durante la mira (distanza %.2f > gittata %.2f)." % [
			combat_target.describe(), distance, reach
		])
		return 0.0
	_elapsed += delta
	if _elapsed >= AIM_DURATION_DAYS:
		_done = true
		HuntService.log_event(individual, "mira su %s completata (distanza %.2f <= gittata %.2f): si scaglia." % [
			combat_target.describe(), distance, reach
		])
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


func get_save_data() -> Dictionary:
	var data := combat_target.to_save_data()
	data["weapon_category"] = weapon_category
	data["elapsed"] = _elapsed
	return data


# Solo lo step corrente riceve questa chiamata (TaskPersistenceService): riprende la mira in corso.
func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
