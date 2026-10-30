class_name DangerFleeService
extends RefCounted

# Fuga dal pericolo (2026-10-30, richiesta utente — lupi L5a). Stateless. Generica: chi crea il pericolo (oggi la carica
# dei lupi, WildAnimalVisitService; un domani i nemici) chiama start_flee con il nome del profilo (DangerProfile), un id
# del pericolo, da dove arriva e i punti sicuri; quando il pericolo è passato chiama end_danger con lo stesso id.
# La fuga è il compito flee.tres (interrupt_priority HumanIndividualActionService.INTERRUPT_PRIORITY_FLEE: interrompe
# qualunque lavoro e nessun bisogno la interrompe): corsa al riparo (RunAction), poi attesa (WaitForSafetyAction) finché
# il pericolo non è chiuso; finita, resolve_idle_individual riprende il lavoro sospeso.

const FLEE_TASK_DEFINITION_PATH: String = "res://gameplay/scripts/tasks/definitions/flee.tres"
const PROFILE_PATH_FORMAT: String = "res://gameplay/dangers/data/%s.tres"
# Nel context della Task di fuga: id del pericolo e "pericolo passato" (letto da WaitForSafetyAction).
const CONTEXT_DANGER_ID: String = "flee_danger_id"
const CONTEXT_DANGER_OVER: String = "flee_danger_over"
# Tetto dell'attesa se il profilo non lo dà (giorni).
const DEFAULT_MAX_WAIT_DAYS: float = 1.0
# Margine dal bordo della macrocella per il punto di "corri via" (microcelle).
const RUN_AWAY_BORDER_MARGIN: float = 0.5

static var _profiles: Dictionary = {}


static func get_profile(profile_name: String) -> DangerProfile:
	if not _profiles.has(profile_name):
		var path := PROFILE_PATH_FORMAT % profile_name
		_profiles[profile_name] = load(path) as DangerProfile if ResourceLoader.exists(path) else null
		if _profiles[profile_name] == null:
			push_warning("DangerFleeService: profilo di pericolo '%s' inesistente" % profile_name)
	return _profiles[profile_name]


# Fa scappare `member` dal pericolo `danger_id` (che arriva da `danger_position`, microcelle della sua macrocella).
# `safe_points`: punti sicuri di questo pericolo (per i lupi il focolare). true = fuga partita o già in corso.
static func start_flee(member: HumanIndividual, profile_name: String, danger_id: int, danger_position: Vector2,
		safe_points: Array[Vector2], world: World, game_data: GameData) -> bool:
	var profile := get_profile(profile_name)
	if profile == null or member == null:
		return false
	if is_fleeing_from(member, danger_id):
		return true
	var choice := _choose_target(member, profile, danger_position, safe_points, world)
	if choice.is_empty():
		print("[FLEE] #%d %s: nessun riparo, resta dov'è (pericolo: %s)" % [member.id, member.name, profile_name])
		return false
	var task := TaskFactory.build_task(TaskDefinitionCache.get_definition(FLEE_TASK_DEFINITION_PATH), {
		"flee_target": choice["target"],
		"flee_max_wait_days": profile.max_wait_days,
		CONTEXT_DANGER_ID: danger_id,
	})
	var interrupted := member.current_task.task_name if member.current_task != null else "(niente)"
	if not member.assign_task(task, GameContext.age_band_for(member, game_data), true):
		print("[FLEE] #%d %s: non può scappare (compito rifiutato)" % [member.id, member.name])
		return false
	print("[FLEE] #%d %s scappa verso %s (pericolo: %s), interrompe '%s'" % [
		member.id, member.name, choice["label"], profile_name, interrupted])
	return true


# Il pericolo `danger_id` è passato: chi lo sta fuggendo smette di aspettare (o, se corre ancora, smetterà appena
# arrivato) e riprende il lavoro interrotto.
static func end_danger(individuals: Array[HumanIndividual], danger_id: int) -> void:
	for member in individuals:
		if not is_fleeing_from(member, danger_id) or bool(member.current_task.context.get(CONTEXT_DANGER_OVER, false)):
			continue
		member.current_task.context[CONTEXT_DANGER_OVER] = true
		print("[FLEE] #%d %s: pericolo passato, riprende il lavoro" % [member.id, member.name])


static func is_fleeing_from(member: HumanIndividual, danger_id: int) -> bool:
	return member.current_task != null and not member.current_task.is_finished() \
		and int(member.current_task.context.get(CONTEXT_DANGER_ID, -1)) == danger_id


# Riparo più vicino tra quelli ammessi dal profilo, scartando quelli a cui il pericolo è più vicino di chi scappa (non si
# corre incontro ai lupi); senza riparo, se il profilo lo vuole, un punto nella direzione opposta al pericolo.
# {"target": Vector2, "label": String}, vuoto = resta dov'è.
static func _choose_target(member: HumanIndividual, profile: DangerProfile, danger_position: Vector2,
		safe_points: Array[Vector2], world: World) -> Dictionary:
	var candidates: Array[Dictionary] = []
	if profile.flee_to_own_house:
		var house := _own_house(member, world)
		if house != null:
			candidates.append({"target": NeedTaskAssignmentService.resolve_rest_target(member, world)["target_position"],
				"label": "casa #%d" % house.id})
	if profile.flee_to_safe_points:
		for point in safe_points:
			var away := member.position - point
			var direction := away.normalized() if away.length() > 0.001 else Vector2.RIGHT
			candidates.append({"target": point + direction * profile.safe_point_stop_distance, "label": "focolare"})
	var best: Dictionary = {}
	var best_distance := INF
	for candidate in candidates:
		var target: Vector2 = candidate["target"]
		var distance := member.position.distance_to(target)
		if danger_position.distance_to(target) < distance:
			continue
		if distance < best_distance:
			best = candidate
			best_distance = distance
	if not best.is_empty() or not profile.run_away_when_no_shelter:
		return best
	var away_from_danger := member.position - danger_position
	var run_direction := away_from_danger.normalized() if away_from_danger.length() > 0.001 else Vector2.RIGHT.rotated(randf() * TAU)
	var run_target := (member.position + run_direction * profile.run_away_distance).clamp(
		Vector2(RUN_AWAY_BORDER_MARGIN, RUN_AWAY_BORDER_MARGIN),
		Vector2(float(World.WIDTH) - RUN_AWAY_BORDER_MARGIN, float(World.HEIGHT) - RUN_AWAY_BORDER_MARGIN))
	return {"target": run_target, "label": "lontano dal pericolo"}


# Casa del membro, se completata, non demolita e nella macrocella in cui si trova.
static func _own_house(member: HumanIndividual, world: World) -> Building:
	if member.house_id == -1 or world == null:
		return null
	for building in world.buildings:
		if building.id != member.house_id:
			continue
		if not building.is_complete or building.is_demolished \
				or Vector2i(building.macro_x, building.macro_y) != member.home_macro_coords:
			return null
		return building
	return null
