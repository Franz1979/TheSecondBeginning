class_name RiteAction
extends Action

# Step "celebra il rito" della Task Rite (2026-10-02, richiesta utente — rite.tres: Walk → Rite). Presso un edificio
# che ammette il rito (RiteService), dura RiteRules.duration_days giorni di gioco consumando STAMINA_DRAIN_PER_DAY; al
# completamento applica gli effetti (RiteEffectService). La Task non è sospendibile: interrotta o annullata si chiude
# senza effetti. Se l'edificio non è più utilizzabile (demolito, da demolire) o il rito non esiste più, la Task si
# chiude (pending_task_abort).
#
# Funerale (2026-10-04, cumulo sepolcrale passo 3b — ultimo step di bury.tres, `body_id` != -1): il rito si celebra
# presso il cumulo sulla cui lastra giace il corpo (target_building risolto dal record, "mound_id"; finché il corpo non è
# sulla lastra lo step resta valido e in attesa del trasporto). Il celebrante sta nella microcella accanto
# (BodyBurialService.get_put_down_point). Al completamento: effetti con i parenti del defunto (RiteEffectService,
# relative_ids) e il corpo consumato, cioè sepolto nel cumulo (BodyBurialService.bury_body).
#
# Regola generale (2026-10-04): dentro una Task SOSPENDIBILE il rito obbedisce alla Task — interrotto, la Task va in
# coda e riprende, e il rito riparte da capo (activate azzera il tempo trascorso). La Task Rito, non sospendibile, resta
# com'è: interrotta si chiude senza effetti.

# Emesso al completamento del rito (on_complete, dopo gli effetti), ordinato o spontaneo, con l'edificio in cui si è
# celebrato (2026-10-03, richiesta utente — effetto visivo e campana). Collegato da GameScene._track_rite_tasks.
# rite_id (2026-10-04): il rito celebrato, per il suono scelto dalla ricetta (RiteRules.completion_sound_id).
signal rite_completed(building: Building, rite_id: String)

const STAMINA_DRAIN_PER_DAY: float = 100.0
# Chiave di SkillEffectService (skill_action_effects.tres): fattore della skill di chi celebra sulla fede dei presenti.
const SKILL_EFFECT_KEY := "rite"

var target_building: Building = null
var rite_id: String = ""
# Funerale: individual_id del corpo (record DEAD_BODY) da seppellire; -1 = rito senza defunto.
var body_id: int = -1
var _elapsed: float = 0.0
# true subito dopo load_save_data: la prima activate dopo un caricamento non azzera il tempo già trascorso.
var _restored_from_save: bool = false
# true se il bersaglio non è più valido: lo step si dichiara completo per far chiudere la Task (pending_task_abort,
# gestito da HumanIndividualActionService.finish_current_step) senza effetti.
var _aborted: bool = false
# true dopo l'applicazione degli effetti (rito concluso davvero): GameScene._track_rite_tasks lo legge per distinguere
# un rito finito da uno interrotto. Non salvato: un rito concluso non sopravvive alla propria Task.
var completed: bool = false


func _init(p_target_building: Building = null, p_rite_id: String = "", p_body_id: int = -1) -> void:
	target = null
	target_building = p_target_building
	rite_id = p_rite_id
	body_id = p_body_id
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	skill_effect_key = SKILL_EFFECT_KEY


func get_rules() -> RiteRules:
	return RiteService.get_rules(rite_id)


func is_target_valid() -> bool:
	if body_id != -1:
		# Funerale: corpo ancora esistente; finché non è sulla lastra resta valido (il trasporto lo porterà), poi vale il
		# cumulo su cui giace.
		var record := BodyBurialService.find_body_record(body_id)
		if record.is_empty() or BodyBurialService.is_expired(record):
			return false
		if not BodyBurialService.is_on_slab(record):
			return true
		target_building = BodyBurialService.find_building(int(record.get("mound_id", -1)))
	var rules := get_rules()
	return rules != null and RiteService.is_building_usable(target_building) \
		and rules.building_types.has(target_building.building_type_name)


# Il rito parte (o riparte, dopo una ripresa dalla coda) da capo; non dopo un caricamento, che riprende da dove era.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if _restored_from_save:
		_restored_from_save = false
	else:
		_elapsed = 0.0
	_aborted = false


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _aborted:
		return 0.0
	if not is_target_valid():
		_aborted = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "edificio o rito non più validi"
		return 0.0
	if body_id != -1 and not BodyBurialService.is_on_slab(BodyBurialService.find_body_record(body_id)):
		_aborted = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "corpo non sulla lastra del cumulo"
		return 0.0
	_elapsed += delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if _aborted:
		return true
	var rules := get_rules()
	return rules != null and is_target_valid() and _elapsed >= rules.duration_days


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _aborted or not is_target_valid():
		return
	var relative_ids: Dictionary = {}
	var body_record: Dictionary = {}
	if body_id != -1:
		body_record = BodyBurialService.find_body_record(body_id)
		relative_ids = BodyBurialService.get_relative_ids(body_record, GameSettings.active_human_individuals)
	elif get_rules() != null and get_rules().faith_relatives > 0.0:
		# Rito senza defunto con fede ai parenti (2026-10-04, ricordo dei defunti): i parenti dei sepolti nell'edificio.
		relative_ids = BodyBurialService.get_buried_relative_ids(target_building, GameSettings.active_human_individuals)
	RiteEffectService.apply_completion(
		individual as HumanIndividual, target_building, get_rules(), GameSettings.active_human_individuals, relative_ids,
		BodyBurialService.get_body_name(body_record)
	)
	if body_id != -1:
		BodyBurialService.bury_body(body_record, target_building)
	completed = true
	rite_completed.emit(target_building, rite_id)


# Punto nella microcella dell'edificio (stessa formula di DemolishAction). Funerale: la microcella accanto al cumulo,
# come chi ha posato il corpo (il corpo è sulla lastra, dentro la microcella del cumulo).
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	if body_id != -1:
		return BodyBurialService.get_put_down_point(target_building, individual)
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + macro_offset)


func get_save_data() -> Dictionary:
	var data := {"rite_id": rite_id, "elapsed": _elapsed, "body_id": body_id}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	_restored_from_save = true
