class_name RemedyAction
extends Action

# Prende un rimedio (2026-10-25, richiesta utente — autocura): un'unità di `remedy_name` (nel context della Task,
# CONTEXT_REMEDY_NAME) presa dallo zaino sul posto o prelevata dall'edificio raggiunto (magazzino o Prodotti finiti di una
# postazione, es. la capanna del guaritore), e subito applicata a chi la prende (HealthConditionService.apply_remedy:
# salute + remedy_health_restore, condizioni curate segnate come trattate oggi). Si consuma solo se c'è ancora qualcosa da
# curare: se nel frattempo è già stata trattata o è guarito, non prende nulla. Stessa forma di RestockPouchAction
# (SourceKind BUILDING/BACKPACK, durata fissa breve, edificio salvato per id). Task: take_remedy(_backpack).tres.
#
# Cura somministrata (2026-10-25, lavoro "Cura", heal.tres — HealJobProvider): stessa azione in altri due modi (Mode).
# TAKE: all'edificio preleva un rimedio nello zaino per il malato (CONTEXT_PATIENT_ID); se il malato non ne ha più bisogno
# la task si chiude senza prelevare. GIVE: al letto del malato toglie il rimedio dallo zaino e lo applica a lui, con la
# Medicina di chi cura sulla salute data (SkillEffectService "heal", 500 → 625); se il malato è morto, lontano o non ha più
# nulla da curare non consuma nulla (il rimedio resta nello zaino e torna al magazzino come carico orfano).

const CONTEXT_REMEDY_NAME := "remedy_name"
const CONTEXT_PATIENT_ID := "remedy_patient_id"
const SKILL_EFFECT_KEY := "heal"
# Durata del prendere il rimedio, in giorni (circa mezz'ora).
const DURATION_DAYS: float = 0.02
# Durata fissa della somministrazione al malato (un'ora).
const GIVE_DURATION_DAYS: float = 1.0 / 24.0
# Distanza massima (microcelle) dal malato per somministrare.
const GIVE_MAX_DISTANCE: float = 2.0

# Non riordinare: è persistita.
enum SourceKind { BUILDING, BACKPACK }
# USE = prendere il rimedio per sé (autocura); TAKE/GIVE = prelevarlo per un malato / darglielo. Non riordinare: persistito.
enum Mode { USE, TAKE, GIVE }

var target_building: Building = null
var source_kind: SourceKind = SourceKind.BUILDING
var mode: Mode = Mode.USE
var _elapsed: float = 0.0


func _init(p_target_building: Building = null, p_source_kind: int = SourceKind.BUILDING, p_mode: int = Mode.USE) -> void:
	target = null
	target_building = p_target_building
	source_kind = p_source_kind as SourceKind
	mode = p_mode as Mode
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func get_stamina_delta(_individual: Variant, _context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(_individual: Variant, _context: Dictionary) -> bool:
	return _elapsed >= (GIVE_DURATION_DAYS if mode == Mode.GIVE else DURATION_DAYS)


func on_complete(individual: Variant, context: Dictionary) -> void:
	var remedy_name := String(context.get(CONTEXT_REMEDY_NAME, ""))
	if mode == Mode.TAKE:
		_take_for_patient(individual, context, remedy_name)
		return
	if mode == Mode.GIVE:
		_give_to_patient(individual, context, remedy_name)
		return
	if HealthConditionService.treatable_conditions(individual, remedy_name).is_empty():
		_log(individual, remedy_name, "niente da curare, rimedio non preso")
		return
	var taken := 0
	if source_kind == SourceKind.BACKPACK:
		taken = individual.remove_carried_resource(remedy_name, 1)
	elif target_building != null:
		taken = BuildingStorageService.withdraw_auto(target_building, remedy_name, 1)
	if taken <= 0:
		_log(individual, remedy_name, "nessun rimedio da prendere")
		return
	var health_before: float = individual.current_health
	HealthConditionService.apply_remedy(individual, remedy_name)
	_log(individual, remedy_name, "preso, salute %.1f -> %.1f" % [health_before, individual.current_health])


# Cura somministrata, all'edificio: un rimedio nello zaino per il malato, se ne ha ancora bisogno.
func _take_for_patient(individual: Variant, context: Dictionary, remedy_name: String) -> void:
	var patient := find_patient(context)
	if patient == null or HealthConditionService.treatable_conditions(patient, remedy_name).is_empty():
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "il malato non ha più bisogno del rimedio"
		_log(individual, remedy_name, "malato non più da curare, niente prelievo")
		return
	var taken := BuildingStorageService.withdraw_auto(target_building, remedy_name, 1) if target_building != null else 0
	var carried: int = individual.add_carried_resource(remedy_name, taken) if taken > 0 else 0
	if taken > carried:
		BuildingStorageService.store(target_building, remedy_name, taken - carried)
	if carried <= 0:
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "nessun rimedio da portare al malato"
		_log(individual, remedy_name, "nessun rimedio da portare")
		return
	_log(individual, remedy_name, "prelevato per #%d %s" % [patient.id, patient.name])


# Cura somministrata, al letto del malato: dal proprio zaino al malato, con la Medicina di chi cura sulla salute data.
func _give_to_patient(individual: Variant, context: Dictionary, remedy_name: String) -> void:
	var patient := find_patient(context)
	if patient == null or _patient_point(individual, patient).distance_to(individual.position) > GIVE_MAX_DISTANCE:
		_log(individual, remedy_name, "malato non trovato vicino, rimedio non dato")
		return
	if HealthConditionService.treatable_conditions(patient, remedy_name).is_empty():
		_log(individual, remedy_name, "#%d %s non ha più nulla da curare" % [patient.id, patient.name])
		return
	if individual.remove_carried_resource(remedy_name, 1) <= 0:
		_log(individual, remedy_name, "rimedio non più nello zaino")
		return
	var health_before: float = patient.current_health
	var factor := SkillEffectService.get_factor(SKILL_EFFECT_KEY, individual)
	HealthConditionService.apply_remedy(patient, remedy_name, factor)
	# Contagio (2026-10-25, ContagionService): chi cura tira a ogni somministrazione.
	ContagionService.expose(individual, patient, ContagionService.Channel.CAREGIVER, GameSettings.active_game_data, "letto del malato")
	_log(individual, remedy_name, "dato a #%d %s (fattore %.2f), salute %.1f -> %.1f" % [
		patient.id, patient.name, factor, health_before, patient.current_health
	])


# Posizione del malato nelle coordinate della macrocella HOME di `individual`.
static func _patient_point(individual: HumanIndividual, patient: HumanIndividual) -> Vector2:
	return patient.position + Vector2(patient.home_macro_coords - individual.home_macro_coords) * World.WIDTH


# Il malato della cura somministrata (CONTEXT_PATIENT_ID), null se non c'è più.
static func find_patient(context: Dictionary) -> HumanIndividual:
	var patient_id := int(context.get(CONTEXT_PATIENT_ID, -1))
	for member in GameSettings.active_human_individuals:
		if member != null and member.id == patient_id:
			return member
	return null


func get_required_position(individual: Variant, _context: Dictionary) -> Variant:
	if mode == Mode.GIVE or source_kind == SourceKind.BACKPACK or target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + macro_offset)


func get_save_data() -> Dictionary:
	var data := {"elapsed": _elapsed, "source_kind": int(source_kind), "mode": int(mode)}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))


func _log(individual: Variant, remedy_name: String, text: String) -> void:
	if DebugLogging.ENABLED:
		print("[REMEDY] #%d %s: %s da %s — %s." % [
			individual.id, individual.name, remedy_name,
			"zaino" if source_kind == SourceKind.BACKPACK else ("%s #%d" % [target_building.building_type_name, target_building.id] if target_building != null else "?"),
			text,
		])
