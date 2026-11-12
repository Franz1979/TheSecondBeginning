class_name HuntCallService
extends RefCounted

# Richiamo di caccia (2026-11-11, richiesta utente — caccia di gruppo passo 2). Stateless salvo la memoria non salvata di
# chi ha sentito il richiamo. Quando un cacciatore ferisce per la prima volta (senza ucciderla) una preda grossa (AnimalRules.max_hunters > 1,
# non di un branco in visita) fischia con le dita (finger_whistle) e chiama aiuto entro CALL_RADIUS microcelle da sé:
#   1. i cacciatori in pattuglia nella loro zona, senza una preda puntata: la preda ferita entra fra le loro candidate
#      anche se non la vedono e anche fuori dalla zona, al primo livello (HuntZoneService.choose_prey);
#   2. le persone libere (svago o "Cerca lavoro"), adulte, non malate, con un'arma da caccia addosso: ricevono una caccia
#      diretta su quella preda (GameScene, call_emitter). Niente passaggio dal deposito: la preda ferita si muove.
# I posti sono quelli liberi della preda (max_hunters meno chi la caccia già); prima i cacciatori in pattuglia, il resto
# alle persone libere, prima le più brave a cacciare e a pari bravura le più vicine.

const CALL_RADIUS: float = 20.0
# Età che cacciano (come le task di caccia, allowed_age_bands [3, 4]).
const HUNTER_AGE_BANDS: Array[HumanTypes.AgeBand] = [HumanTypes.AgeBand.FERTILE_ADULT, HumanTypes.AgeBand.MATURE_ADULT]

# GameScene (stabile, come gli altri emitter): (caller, animal, slots) -> int. Suono del fischio e cacce dirette alle
# persone libere (helpers_for); ritorna quante ne ha mandate.
static var call_emitter: Callable = Callable()
# Chi ha sentito il richiamo in pattuglia: id cacciatore -> {"prey_id": int, "task_id": int (istanza della Task di caccia
# in zona: con un'altra Task il richiamo non vale più)}. Non salvato: dopo un caricamento il richiamo è perso.
static var _heard: Dictionary = {}


# Chiamata da ThrowAction dopo un colpo a segno che non uccide. Solo al PRIMO ferimento (2026-11-11, richiesta utente —
# niente fischi a ogni colpo): la preda era a salute piena prima del colpo (`health_before`).
static func call_for_help(caller: HumanIndividual, animal: AnimalVisualGroup, health_before: float) -> void:
	if caller == null or animal == null or animal.health <= 0.0 or animal.wild_group_id != 0:
		return
	if not HuntZoneService.is_big_prey(animal.species_name):
		return
	if health_before < HuntZoneService.max_health_of(animal) - 0.001:
		return
	var counts := HuntZoneService.hunters_per_prey()
	var free := HuntZoneService.max_hunters_for(animal.species_name) - int(counts.get(animal.id, 0))
	var heard: Array[String] = []
	if free > 0:
		for other in GameSettings.active_human_individuals:
			if heard.size() >= free:
				break
			if other == caller or not _hears(caller, other):
				continue
			var task := other.current_task
			if not HuntZoneService.is_zone_hunt_task(task) or task.is_finished():
				continue
			if int(task.context.get(HuntZoneService.CONTEXT_PREY_ID, -1)) >= 0:
				continue
			_heard[other.id] = {"prey_id": animal.id, "task_id": task.get_instance_id()}
			heard.append(other.name)
	var sent := 0
	if call_emitter.is_valid():
		sent = int(call_emitter.call(caller, animal, maxi(free - heard.size(), 0)))
	HuntService.log_event(caller, "fischia per aiuto su %s #%d (salute %.1f, posti liberi %d): %s, %d persone libere mandate." % [
		animal.species_name, animal.id, animal.health, maxi(free, 0),
		"nessun cacciatore in pattuglia vicino" if heard.is_empty() else "sentono in pattuglia " + ", ".join(heard), sent
	])


# Preda del richiamo sentito da `hunter` in pattuglia, se vale ancora (stessa Task, preda viva): null altrimenti.
static func heard_prey_for(hunter: HumanIndividual) -> AnimalVisualGroup:
	if hunter == null or not _heard.has(hunter.id):
		return null
	var entry: Dictionary = _heard[hunter.id]
	var animal := AnimalGroupRenderer.find_live_individual(int(entry["prey_id"]))
	if hunter.current_task == null or hunter.current_task.get_instance_id() != int(entry["task_id"]) \
			or animal == null or animal.health <= 0.0:
		_heard.erase(hunter.id)
		return null
	return animal


# Il richiamo è stato seguito (preda puntata) o non serve più.
static func forget(hunter: HumanIndividual) -> void:
	if hunter != null:
		_heard.erase(hunter.id)


# Persone libere da mandare sulla preda (gruppo 2), al massimo `slots`: in svago o in "Cerca lavoro", non malate, adulte,
# entro CALL_RADIUS da chi fischia, con un'arma da caccia addosso; prima le più brave a cacciare, poi le più vicine.
static func helpers_for(ctx: GameContext, caller: HumanIndividual, slots: int) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	if slots <= 0:
		return result
	var candidates: Array[Dictionary] = []
	for member in ctx.individuals:
		if member == caller:
			continue
		var task := member.current_task
		if task != null and (task.is_finished() or not (task.is_idle_activity or task.task_name == JobBoardService.SEEK_JOB_TASK_NAME)):
			continue
		if member.is_sick() or not HUNTER_AGE_BANDS.has(ctx.age_band_of(member)):
			continue
		var distance := _distance(caller, member)
		if distance > CALL_RADIUS or not HuntService.has_hunting_weapon_available(member):
			continue
		candidates.append({"member": member, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var skill_a: float = a["member"].skill_hunting
		var skill_b: float = b["member"].skill_hunting
		if not is_equal_approx(skill_a, skill_b):
			return skill_a > skill_b
		return float(a["distance"]) < float(b["distance"])
	)
	for candidate in candidates:
		if result.size() >= slots:
			break
		result.append(candidate["member"])
	return result


static func _hears(caller: HumanIndividual, other: HumanIndividual) -> bool:
	return _distance(caller, other) <= CALL_RADIUS


# Distanza in microcelle tra due persone, anche in macrocelle diverse.
static func _distance(caller: HumanIndividual, other: HumanIndividual) -> float:
	return other.position.distance_to(caller.position + TaskBuilderService.macro_offset(other, caller.home_macro_coords))
