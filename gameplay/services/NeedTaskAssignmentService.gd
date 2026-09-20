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

# Task perditempo "leisure_restock" (2026-09-19, richiesta utente): Walk verso il magazzino piu' vicino
# con cibo -> RestockPouchAction. interrupt_priority -1 e is_idle_activity come wander/leisure_rest.
const LEISURE_RESTOCK_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/leisure_restock.tres"

# Task-bisogno "emergency_restock" (2026-09-19, richiesta utente): stessi step di leisure_restock ma
# interrupt_priority 20 (interrompe). Vedi assign_emergency_restock_task.
const EMERGENCY_RESTOCK_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/emergency_restock.tres"

# Tetto di sicurezza in giorni per la Rest da BISOGNO (2026-09-16, richiesta utente — bugfix:
# anche con regen percentuale, vedi RestAction.STAMINA_REGEN_PERCENT_PER_DAY, il recupero dalla
# soglia del 20% resta ~16gg fissi, troppo per restare bloccati senza un tetto). Passato come
# max_duration_days a RestAction (vedi assign_rest_task sotto) con ignore_stamina_cap=false — un
# backstop in OR col criterio "stamina piena": chi recupera prima si ferma prima, questo scatta
# solo se il recupero fosse più lento del previsto.
const REST_TASK_MAX_DURATION_DAYS: float = 8.0

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
		# Tetto di sicurezza (2026-09-16) — vedi REST_TASK_MAX_DURATION_DAYS sopra: la Rest da
		# bisogno resta comunque legata alla stamina (ignore_stamina_cap=false), il tetto interviene
		# SOLO se il recupero fosse più lento del previsto.
		"rest_max_duration_days": REST_TASK_MAX_DURATION_DAYS,
		"rest_ignore_stamina_cap": false,
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
	if assigned and DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
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
		# Tetto di sicurezza (2026-09-17, richiesta utente — bugfix: mancava qui, a differenza di
		# assign_rest_task sopra, quindi la Emergency Rest restava senza tetto e recuperava sempre
		# fino a stamina piena, fino a ~16gg fissi nel caso peggiore). STESSA costante/STESSO
		# principio di REST_TASK_MAX_DURATION_DAYS sopra — un backstop in OR col criterio "stamina
		# piena", scatta solo se il recupero fosse più lento del previsto.
		"rest_max_duration_days": REST_TASK_MAX_DURATION_DAYS,
		"rest_ignore_stamina_cap": false,
	}
	var task := TaskFactory.build_task(emergency_rest_definition, context)
	# Guard PRIMA di stop() — STESSO principio di assign_rest_task sopra.
	if not individual.can_assign_task(task, age_band):
		return false
	if not is_interrupt_transition:
		individual.stop()
	var assigned := individual.assign_task(task, age_band, is_interrupt_transition)
	if assigned and DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
		print("[EMERGENCY REST] Task Walk+Rest assegnata a #%d %s: target=%s, rest_multiplier=1.0 (fisso)" % [
			individual.id, individual.name, target_data["target_position"]
		])
	return assigned


# Scansione lineare di World.buildings — stesso identico pattern/stesso costo accettato già in uso
# altrove nel progetto per liste di questa dimensione (GameScene._find_building_by_id/
# TaskPersistenceService._find_building_by_id, entrambe copie indipendenti dello stesso principio).
# Costruisce (senza assegnarla) una Task di rifornimento delle provviste (2026-09-19, richiesta
# utente): trova il magazzino piu' vicino che contiene cibo (WarehouseSelectionService.
# find_source_for_retrieval con la categoria FOOD) e costruisce Walk -> RestockPouchAction dalla
# definizione `definition_path` (leisure_restock.tres oppure emergency_restock.tres: stessi step,
# cambia solo la priorita'). Se nessun magazzino completo ha cibo ritorna null: la Task NON nasce.
# Nessun guard sullo stato delle provviste. Il Walk punta alla microcella dell'edificio con un
# piccolo scarto casuale interno, come le altre Task verso edifici (offset cross-macrocella come in
# resolve_rest_target). Usata da assign_leisure_restock_task, assign_emergency_restock_task e dal
# fallback idle (IdleTaskAssignmentService._build_idle_task).
static func build_restock_task(individual: HumanIndividual, world: World, definition_path: String) -> Task:
	var source := WarehouseSelectionService.find_source_for_retrieval(
		world, individual.position, individual.home_macro_coords, SecondaryResourceTypes.Category.FOOD,
		[], 1, individual.id
	)
	if source == null:
		if DebugLogging.should_log_restock(individual.id):
			print("[RESTOCK] #%d %s: nessun magazzino completo con cibo trovato, Task non creata (%s)." % [
				individual.id, individual.name, definition_path.get_file()
			])
		return null
	var macro_offset: Vector2 = Vector2(
		Vector2i(source.macro_x, source.macro_y) - individual.home_macro_coords
	) * World.WIDTH
	var target_position: Vector2 = Vector2(source.micro_x, source.micro_y) + macro_offset \
		+ Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85))
	var definition := load(definition_path) as TaskDefinition
	var context: Dictionary = {
		"restock_target_position": target_position,
		"restock_target_building": source,
	}
	if DebugLogging.should_log_restock(individual.id):
		print("[RESTOCK] #%d %s: magazzino scelto %s #%d in macro=(%d,%d) micro=(%d,%d), target=%s (%s)" % [
			individual.id, individual.name, source.building_type_name, source.id,
			source.macro_x, source.macro_y, source.micro_x, source.micro_y, str(target_position),
			definition_path.get_file()
		])
	return TaskFactory.build_task(definition, context)


# Assegnazione comune delle Task di rifornimento: build_restock_task + can_assign_task + assign_task,
# con il log [RESTOCK] dell'esito. NON chiama individual.stop() (scarterebbe lo zaino: rifornirsi deve
# poter avvenire anche mentre si trasporta qualcosa).
static func _assign_restock_task(
	individual: HumanIndividual, world: World, age_band: HumanTypes.AgeBand, definition_path: String,
	is_interrupt_transition: bool
) -> bool:
	var task := build_restock_task(individual, world, definition_path)
	if task == null:
		return false
	if not individual.can_assign_task(task, age_band):
		if DebugLogging.should_log_restock(individual.id):
			print("[RESTOCK] #%d %s: Task %s rifiutata da can_assign_task." % [individual.id, individual.name, task.task_name])
		return false
	var assigned := individual.assign_task(task, age_band, is_interrupt_transition)
	if DebugLogging.should_log_restock(individual.id):
		print("[RESTOCK] Task %s %s a #%d %s." % [
			task.task_name, "assegnata" if assigned else "NON assegnata (assign_task ha rifiutato)", individual.id, individual.name
		])
	return assigned


# Assegna la Task leisure_restock (attivazione manuale, tasto F), sullo schema di assign_rest_task.
# Se nessun magazzino ha cibo la Task non nasce (false). Nessun guard sullo stato delle provviste: se il
# giocatore la lancia, si esegue comunque (il guard dello spazio libero vale SOLO per il sorteggio idle,
# vedi IdleTaskAssignmentService.LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO). Priorita' -1: passa dalle
# regole generali di assign_task (zaino occupato compreso).
static func assign_leisure_restock_task(individual: HumanIndividual, world: World, age_band: HumanTypes.AgeBand) -> bool:
	return _assign_restock_task(individual, world, age_band, LEISURE_RESTOCK_TASK_DEFINITION_PATH, false)


# Assegna la Task emergency_restock (2026-09-19, richiesta utente), sullo schema di
# assign_emergency_rest_task: il bisogno di cibo che interrompe (interrupt_priority 20). Nessun guard
# sullo spazio libero. Se nessun magazzino ha cibo la Task non nasce e ritorna false SENZA toccare la
# Task in corso (l'interruzione avviene solo dentro assign_task). `is_interrupt_transition` = true dai
# due agganci automatici (HumanIndividualActionService._handle_food_interrupt/resolve_idle_individual):
# conserva lo zaino e sospende la Task in corso se sospendibile.
static func assign_emergency_restock_task(
	individual: HumanIndividual, world: World, age_band: HumanTypes.AgeBand, is_interrupt_transition: bool = false
) -> bool:
	return _assign_restock_task(individual, world, age_band, EMERGENCY_RESTOCK_TASK_DEFINITION_PATH, is_interrupt_transition)


static func _find_building_by_id(world: World, building_id: int) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null
