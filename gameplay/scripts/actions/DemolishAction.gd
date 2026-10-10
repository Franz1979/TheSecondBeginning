class_name DemolishAction
extends Action

# Abbattimento di un edificio "da demolire" (2026-09-27, richiesta utente — demolizione come Task, secondo step di
# demolish.tres: Walk → Demolish). Stesso schema di BuildAction: lavoro a cicli giornalieri a STAMINA_DRAIN_PER_DAY,
# accumulato DAL VIVO su Building.construction_progress[LABOR_KEY] (mai su un campo dell'istanza), così interruzione,
# ripresa da un'altra DemolishAction (TaskReassignmentService ricostruisce sempre la Task da zero) e salvataggio
# funzionano gratis come per la costruzione. Chiave propria, non "labor_accumulated": quella resta il lavoro di
# costruzione già svolto sull'edificio completo.
#
# Lavoro richiesto: metà del lavoro di costruzione (rules.required_labor / 2). A fine lavoro questa classe non abbatte
# nulla da sé: segnala demolition_completed e chi l'ha creata (GameScene._on_demolition_completed) esegue la
# demolizione vera, fa cadere le macerie a terra e, se c'è un mucchio, scrive nel context la richiesta di portarlo al
# magazzino (HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL).

signal demolition_completed(building: Building, individual: Variant, context: Dictionary)

const LABOR_KEY := "demolition_labor_accumulated"
# Stesso drain della costruzione (BuildAction.STAMINA_DRAIN_PER_DAY), costante propria come ogni Action.
const STAMINA_DRAIN_PER_DAY: float = 200.0
# Frazione del lavoro di costruzione richiesta per abbattere l'edificio.
const LABOR_FRACTION_OF_BUILD: float = 0.5

var target_building: Building = null


func _init(p_target_building: Building = null) -> void:
	target = null
	target_building = p_target_building
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	# Effetto della skill da costruttore (2026-09-27, SkillEffectService "build", stessa voce di BuildAction).
	skill_effect_key = "build"


# Validità (vedi Action.is_target_valid): l'edificio deve esistere ancora ed essere "da demolire".
func is_target_valid() -> bool:
	return target_building != null and not target_building.is_demolished and target_building.is_marked_for_demolition


# Sempre metà del lavoro di costruzione, per ogni edificio. Sgombero delle macerie (2026-10-10): rubble.tres ha
# required_labor = 600 solo perché lo sgombero costi 300 (le macerie non si costruiscono mai).
func get_required_labor() -> float:
	if target_building == null or target_building.rules == null:
		return 0.0
	return float(target_building.rules.required_labor) * LABOR_FRACTION_OF_BUILD


func _get_labor_accumulated() -> float:
	if target_building == null:
		return 0.0
	return float(target_building.construction_progress.get(LABOR_KEY, 0.0))


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if not is_target_valid():
		return 0.0
	if _get_labor_accumulated() >= get_required_labor():
		return 0.0
	var stamina_spent: float = STAMINA_DRAIN_PER_DAY * delta
	# Lavoro richiesto diviso per il fattore della skill, realizzato moltiplicando il lavoro aggiunto (come BuildAction).
	var skill_factor := SkillEffectService.get_factor_for_action(self, individual, context)
	target_building.construction_progress[LABOR_KEY] = _get_labor_accumulated() + stamina_spent * skill_factor
	return -stamina_spent


# Mai completa con un edificio non più valido (demolito nel frattempo da un altro individuo): la Task si chiude dal
# controllo di validità dello step, non da un completamento che rieseguirebbe la demolizione.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	if not is_target_valid():
		return false
	return _get_labor_accumulated() >= get_required_labor()


# Punto casuale dentro la microcella dell'edificio, come BuildAction.get_required_position.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + macro_offset)


func on_complete(individual: Variant, context: Dictionary) -> void:
	if not is_target_valid():
		return
	demolition_completed.emit(target_building, individual, context)


# Solo l'identità del bersaglio: il progresso vive su Building.construction_progress (salvato da GameSaveService).
func get_save_data() -> Dictionary:
	var data := {}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data
