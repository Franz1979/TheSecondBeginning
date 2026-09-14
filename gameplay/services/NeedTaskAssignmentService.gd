class_name NeedTaskAssignmentService
extends RefCounted

# Costruzione/assegnazione delle due Task-bisogno (Rest/Emergency Rest) — service RefCounted
# stateless (2026-09-13, richiesta utente: sistema di interrupt/coda da stamina critica). ESTRATTO
# da GameScene._resolve_rest_target/_resolve_emergency_rest_target/_assign_rest_task/
# _assign_emergency_rest_task (i trigger manuali tasti R/E — invariati nel comportamento esterno,
# vedi GameScene.gd: ora entrambi delegano qui) — necessario perché HumanIndividualActionService
# (il nuovo chiamante automatico, dentro apply_action) è un service stateless senza accesso a un
# nodo GameScene: la risoluzione target/costruzione Task non poteva restare un metodo privato su
# quel Node. Building lookup tramite un piccolo _find_building_by_id locale (stessa identica
# scansione lineare già duplicata altrove nel progetto per lo stesso scopo, es. GameScene/
# TaskPersistenceService — nessun indice per id mantenuto a parte, stesso principio "costo
# accettato" già in uso ovunque).
const REST_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/rest.tres"
const EMERGENCY_REST_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/emergency_rest.tres"

# Raggio massimo del walk-around casuale quando l'individuo NON ha una casa assegnata — STESSO
# valore/STESSO principio già in uso prima di questo spostamento (vedi GameScene, ora rimosso da
# lì): 4.0 scelto come via di mezzo, distanza REALE randf_range(1.0, questo raggio).
const REST_TASK_NO_HOUSE_WANDER_RADIUS: float = 4.0

# Lunghezza FISSA (non un range) del piccolo passo della Emergency Rest Task — 1.0 microcella
# esatta: basta lo scatto minimo per il segnale visivo "individuo appena interrotto".
const EMERGENCY_REST_STEP_LENGTH: float = 1.0


# Risoluzione del target/rest_multiplier/walk_away_target della Rest Task — STESSA identica
# logica di GameScene._resolve_rest_target (spostata qui tale e quale, nessun cambio di
# comportamento): ramo "ha casa" (house_id != -1, rest_multiplier da BuildingRules.rest_multiplier)
# o ramo "nessuna casa"/Building non più risolvibile (walk-around casuale, rest_multiplier 1.0).
# `world` sostituisce l'accesso diretto a GameScene.macro_world del codice originale.
static func resolve_rest_target(individual: HumanIndividual, world: World) -> Dictionary:
	var walk_away_distance: float = randf_range(1.0, REST_TASK_NO_HOUSE_WANDER_RADIUS)
	var walk_away_position: Vector2 = individual.position + Vector2.from_angle(randf() * TAU) * walk_away_distance
	if individual.house_id != -1:
		var house := _find_building_by_id(world, individual.house_id)
		if house != null:
			var macro_offset: Vector2 = Vector2(
				Vector2i(house.macro_x, house.macro_y) - individual.home_macro_coords
			) * World.WIDTH
			var house_position: Vector2 = Vector2(house.micro_x, house.micro_y) + macro_offset
			var house_rest_multiplier: float = 1.0
			if house.rules != null:
				house_rest_multiplier = house.rules.rest_multiplier
			return {
				"target_position": house_position,
				"rest_multiplier": house_rest_multiplier,
				"walk_away_target_position": walk_away_position,
			}
		# house_id valorizzato ma Building non più risolvibile — ripiega sul walk-around sotto,
		# stesso comportamento di house_id == -1.
	var wander_distance: float = randf_range(1.0, REST_TASK_NO_HOUSE_WANDER_RADIUS)
	var wander_position: Vector2 = individual.position + Vector2.from_angle(randf() * TAU) * wander_distance
	return {
		"target_position": wander_position,
		"rest_multiplier": 1.0,
		"walk_away_target_position": walk_away_position,
	}


# Risoluzione del target Walk della Emergency Rest Task — STESSA identica logica di GameScene.
# _resolve_emergency_rest_target (spostata qui tale e quale): angolo casuale, lunghezza FISSA
# (EMERGENCY_REST_STEP_LENGTH), nessun house_id/BuildingRules consultato mai (nessun bonus casa,
# richiesta esplicita del prompt che ha introdotto questa Task).
static func resolve_emergency_rest_target(individual: HumanIndividual) -> Dictionary:
	var target_position: Vector2 = individual.position + Vector2.from_angle(randf() * TAU) * EMERGENCY_REST_STEP_LENGTH
	return {"target_position": target_position}


# Costruisce e assegna la Rest Task completa [Walk, Rest, Walk away] — STESSO meccanismo già
# usato dal trigger manuale tasto R (GameScene._assign_rest_task, ora un thin wrapper su questa
# funzione). Ritorna l'esito di individual.assign_task (false = rifiutata dal guard age_band,
# current_task lasciato intatto dal guard stesso — vedi HumanIndividual.assign_task).
#
# is_interrupt_transition (2026-09-13, richiesta utente, bugfix inventario) — default false,
# inoltrato TALE E QUALE a individual.assign_task: il trigger manuale tasto R (GameScene, nessun
# argomento passato) resta invariato (discard sempre); HumanIndividualActionService passa true
# SOLO quando assegna questa Task-bisogno a seguito di un interrupt automatico rilevato — vedi
# HumanIndividual.assign_task per il perché.
static func assign_rest_task(individual: HumanIndividual, world: World, age_band: HumanTypes.AgeBand, is_interrupt_transition: bool = false) -> bool:
	var target_data := resolve_rest_target(individual, world)
	var rest_definition := load(REST_TASK_DEFINITION_PATH) as TaskDefinition
	var context: Dictionary = {
		"target_position": target_data["target_position"],
		"rest_multiplier": target_data["rest_multiplier"],
		"walk_away_target_position": target_data["walk_away_target_position"],
	}
	var task := TaskFactory.build_task(rest_definition, context)
	# Guard PRIMA di stop() (2026-09-13, richiesta utente, bugfix — vedi HumanIndividual.
	# can_assign_task) — se la Task venisse rifiutata (oggi solo un INFANT selezionato, disallowed
	# su Walk/Rest), individual.stop() non deve MAI scattare: scarterebbe l'inventario/azzererebbe
	# la Task PRECEDENTE di un individuo per una sostituzione che non avverrà mai.
	if not individual.can_assign_task(task, age_band):
		return false
	# stop() SOLO se non è un interrupt automatico (2026-09-13, richiesta utente) — STESSO
	# principio/STESSO parametro di is_interrupt_transition passato ad assign_task sotto: un
	# interrupt automatico non deve azzerare is_moving/path della Task appena sospesa (comunque
	# innocuo qui, il primo step è sempre un WalkAction che sovrascrive is_moving/target_position
	# da sé in activate() — ma resta comunque un side-effect non necessario per quel percorso,
	# stesso principio "tocca solo quello che serve" già seguito per il discard).
	if not is_interrupt_transition:
		individual.stop()
	var assigned := individual.assign_task(task, age_band, is_interrupt_transition)
	if assigned and DebugLogging.ENABLED:
		print("[REST] Task Walk+Rest assegnata a #%d %s: target=%s, rest_multiplier=%.2f" % [
			individual.id, individual.name, target_data["target_position"], target_data["rest_multiplier"]
		])
	return assigned


# Costruisce e assegna la Emergency Rest Task completa [Walk, Rest] — STESSO meccanismo già usato
# dal trigger manuale tasto E (GameScene._assign_emergency_rest_task, ora un thin wrapper su
# questa funzione). rest_multiplier SEMPRE 1.0 letterale (nessun bonus casa, mai un lookup
# house_id/BuildingRules).
#
# is_interrupt_transition — STESSO trattamento/STESSO default di assign_rest_task sopra: false
# per il trigger manuale tasto E (invariato), true SOLO quando HumanIndividualActionService
# assegna questa Task-bisogno a seguito di un interrupt automatico rilevato.
static func assign_emergency_rest_task(individual: HumanIndividual, age_band: HumanTypes.AgeBand, is_interrupt_transition: bool = false) -> bool:
	var target_data := resolve_emergency_rest_target(individual)
	var emergency_rest_definition := load(EMERGENCY_REST_TASK_DEFINITION_PATH) as TaskDefinition
	var context: Dictionary = {
		"target_position": target_data["target_position"],
		"rest_multiplier": 1.0,
	}
	var task := TaskFactory.build_task(emergency_rest_definition, context)
	# Guard PRIMA di stop() — STESSO principio di assign_rest_task sopra.
	if not individual.can_assign_task(task, age_band):
		return false
	if not is_interrupt_transition:
		individual.stop()
	var assigned := individual.assign_task(task, age_band, is_interrupt_transition)
	if assigned and DebugLogging.ENABLED:
		print("[EMERGENCY REST] Task Walk+Rest assegnata a #%d %s: target=%s, rest_multiplier=1.0 (fisso)" % [
			individual.id, individual.name, target_data["target_position"]
		])
	return assigned


# Scansione lineare di World.buildings — stesso identico pattern/stesso costo accettato già in uso
# altrove nel progetto per liste di questa dimensione (GameScene._find_building_by_id/
# TaskPersistenceService._find_building_by_id, entrambe copie indipendenti dello stesso principio).
static func _find_building_by_id(world: World, building_id: int) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null
