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
# Varianti "dallo zaino" (2026-09-26, richiesta utente — rifornirsi dal proprio zaino): stesso task_name/priorità, un
# solo step RestockPouch con sorgente BACKPACK e nessun cammino. Scelte da build_restock_task quando lo zaino contiene
# cibo commestibile; se dopo il travaso il bisogno resta, il viaggio al magazzino viene accodato a fine step
# (HumanIndividualActionService._handle_pending_warehouse_restock).
const BACKPACK_RESTOCK_DEFINITION_PATHS := {
	LEISURE_RESTOCK_TASK_DEFINITION_PATH: "res://gameplay/scripts/tasks/definitions/leisure_restock_backpack.tres",
	EMERGENCY_RESTOCK_TASK_DEFINITION_PATH: "res://gameplay/scripts/tasks/definitions/emergency_restock_backpack.tres",
}

# Tetto di sicurezza in giorni per la Rest da BISOGNO (2026-09-16, richiesta utente — bugfix:
# anche con regen percentuale, vedi RestAction.STAMINA_REGEN_PERCENT_PER_DAY, il recupero dalla
# soglia del 20% resta ~16gg fissi, troppo per restare bloccati senza un tetto). Passato come
# max_duration_days a RestAction (vedi assign_rest_task sotto) con ignore_stamina_cap=false — un
# backstop in OR col criterio "stamina piena": chi recupera prima si ferma prima, questo scatta
# solo se il recupero fosse più lento del previsto.
# Taratura 2026-09-26 (richiesta utente): da 8.0 a 6.0, insieme al recupero portato al 10% al giorno.
# Taratura 2026-09-27 (richiesta utente): da 6.0 a 4.0, insieme al recupero portato al 20% al giorno.
const REST_TASK_MAX_DURATION_DAYS: float = 4.0

# Raggio massimo del walk-around casuale quando l'individuo NON ha una casa assegnata — STESSO
# valore/STESSO principio già in uso prima di questo spostamento (vedi GameScene, ora rimosso da
# lì): 4.0 scelto come via di mezzo, distanza REALE randf_range(1.0, questo raggio).
const REST_TASK_NO_HOUSE_WANDER_RADIUS: float = 4.0

# Lunghezza FISSA (non un range) del piccolo passo della Emergency Rest Task — 1.0 microcella
# esatta: basta lo scatto minimo per il segnale visivo "individuo appena interrotto".
const EMERGENCY_REST_STEP_LENGTH: float = 1.0

# Scelta del luogo di riposo per rest.tres (2026-09-27, richiesta utente — vedi _should_rest_at_home): la casa è ammessa
# solo se dopo la camminata d'andata resta almeno questa frazione della stamina massima (5% dell'emergenza più un
# margine), ...
const REST_HOME_MIN_STAMINA_AFTER_WALK_FRACTION: float = 0.10
# ... e si sceglie se il suo tempo totale non supera quello del riposo sul posto di più di questa frazione.
const REST_HOME_TIME_TOLERANCE_FRACTION: float = 0.10


# Risoluzione del target/rest_multiplier/walk_away_target della Rest Task — STESSA identica
# logica di GameScene._resolve_rest_target (spostata qui tale e quale, nessun cambio di
# comportamento): ramo "ha casa" (house_id != -1, rest_multiplier da BuildingRules.rest_multiplier)
# o ramo "nessuna casa"/Building non più risolvibile (walk-around casuale, rest_multiplier 1.0).
# `world` sostituisce l'accesso diretto a GameScene.macro_world del codice originale.
# choose_by_cost (2026-09-27, richiesta utente — solo la Rest da bisogno, assign_rest_task; leisure_rest lo lascia
# false e va sempre a casa come prima): con una casa si confronta il riposo a casa con quello sul posto
# (_should_rest_at_home) e, se non conviene, si riposa sul posto come chi non ha casa.
static func resolve_rest_target(individual: HumanIndividual, world: World, choose_by_cost: bool = false) -> Dictionary:
	# Destinazioni casuali (2026-09-27, pathfinding): solo su microcelle libere e raggiungibili — vedi
	# _random_free_point_around. Il punto di riposo a casa (vicino al bordo della sua microcella) resta com'era.
	var walk_away_position: Vector2 = _random_free_point_around(individual, 1.0, REST_TASK_NO_HOUSE_WANDER_RADIUS)
	if individual.house_id != -1:
		var house := _find_building_by_id(world, individual.house_id)
		if house != null and (not choose_by_cost or _should_rest_at_home(individual, house)):
			var macro_offset: Vector2 = Vector2(
				Vector2i(house.macro_x, house.macro_y) - individual.home_macro_coords
			) * World.WIDTH
			var house_position: Vector2 = Vector2(house.micro_x, house.micro_y) + macro_offset + _random_point_near_cell_border()
			var house_rest_multiplier: float = 1.0
			if house.rules != null:
				house_rest_multiplier = house.rules.rest_multiplier
			return {
				"target_position": house_position,
				"rest_multiplier": house_rest_multiplier,
				"walk_away_target_position": walk_away_position,
			}
		# house_id valorizzato ma Building non più risolvibile, o riposo a casa non conveniente
		# (_should_rest_at_home) — ripiega sul walk-around sotto, stesso comportamento di house_id == -1.
	var wander_position: Vector2 = _random_free_point_around(individual, 1.0, REST_TASK_NO_HOUSE_WANDER_RADIUS)
	return {
		"target_position": wander_position,
		"rest_multiplier": 1.0,
		"walk_away_target_position": walk_away_position,
	}


# Riposo a casa o sul posto (2026-09-27, richiesta utente — solo rest.tres). Con s = stamina attuale e max = massima:
#   - sul posto: tempo = (max − s) / (regen × max × 1.0);
#   - casa: C = lunghezza della camminata fino a casa × costo per microcella attuale (zaino e attrezzi,
#     WalkAction.get_walk_cost_per_microcell). Con una Task sospesa o in coda che ha una posizione si aggiunge il
#     ritorno (2C e due camminate). Tempo = tempi di camminata + (max − s + costo totale) / (regen × max × rest_multiplier);
#   - la casa è ammessa solo se raggiungibile e s − C ≥ REST_HOME_MIN_STAMINA_AFTER_WALK_FRACTION × max;
#   - si sceglie la casa se ammessa e il suo tempo non supera quello sul posto di più di REST_HOME_TIME_TOLERANCE_FRACTION.
# regen = RestAction.STAMINA_REGEN_PERCENT_PER_DAY. Tempo di camminata = lunghezza / move_speed (microcelle al giorno).
static func _should_rest_at_home(individual: HumanIndividual, house: Building) -> bool:
	var max_stamina: float = individual.max_stamina
	if max_stamina <= 0.0:
		return true
	var stamina: float = individual.current_stamina
	var regen_per_day: float = RestAction.STAMINA_REGEN_PERCENT_PER_DAY * max_stamina
	var house_multiplier: float = house.rules.rest_multiplier if house.rules != null else 1.0
	var site_time: float = (max_stamina - stamina) / regen_per_day

	var walk_length: float = _walk_length_to_house(individual, house)
	var cost_per_microcell: float = WalkAction.get_walk_cost_per_microcell(individual)
	var one_way_cost: float = walk_length * cost_per_microcell if walk_length >= 0.0 else INF
	var trips: int = 2 if _has_positioned_follow_up(individual) else 1
	var walk_time: float = 0.0
	if walk_length >= 0.0 and individual.move_speed > 0.0:
		walk_time = walk_length / individual.move_speed * float(trips)
	var total_walk_cost: float = one_way_cost * float(trips)
	var home_time: float = walk_time + (max_stamina - stamina + total_walk_cost) / (regen_per_day * house_multiplier)
	var admitted: bool = walk_length >= 0.0 and stamina - one_way_cost >= REST_HOME_MIN_STAMINA_AFTER_WALK_FRACTION * max_stamina
	var choose_home: bool = admitted and home_time <= site_time * (1.0 + REST_HOME_TIME_TOLERANCE_FRACTION)

	if DebugLogging.ENABLED and DebugLogging.SHOW_REST_CHOICE_LOGS:
		print("[REST] #%d %s: stamina %.0f/%.0f — casa #%d (x%.2f): C=%s (%s microcelle, %.1f/microcella, viaggi %d), tempo casa %s gg, tempo sul posto %.2f gg%s -> %s." % [
			individual.id, individual.name, stamina, max_stamina, house.id, house_multiplier,
			("%.0f" % one_way_cost) if walk_length >= 0.0 else "-",
			("%.1f" % walk_length) if walk_length >= 0.0 else "irraggiungibile",
			cost_per_microcell, trips,
			("%.2f" % home_time) if walk_length >= 0.0 else "-",
			site_time,
			"" if admitted else " (casa non ammessa: stamina insufficiente o casa irraggiungibile)",
			"CASA" if choose_home else "SUL POSTO",
		])
	return choose_home


# Lunghezza (microcelle) della camminata fino alla casa, -1.0 se irraggiungibile. Stessa macrocella viva: somma dei
# tratti del percorso di PathfindingService.find_path (già lisciato), dalla posizione esatta al primo punto e
# dall'ultimo al centro della microcella della casa; altra macrocella o cella senza griglia: distanza in linea retta.
static func _walk_length_to_house(individual: HumanIndividual, house: Building) -> float:
	var macro_offset: Vector2 = Vector2(Vector2i(house.macro_x, house.macro_y) - individual.home_macro_coords) * World.WIDTH
	var house_center: Vector2 = Vector2(house.micro_x, house.micro_y) + macro_offset + Vector2(0.5, 0.5)
	var cell := PathfindingService.get_live_cell(individual.home_macro_coords)
	if Vector2i(house.macro_x, house.macro_y) != individual.home_macro_coords or cell == null or cell.path_grid == null:
		return individual.position.distance_to(house_center)
	var from := Vector2i(floori(individual.position.x), floori(individual.position.y))
	var to := Vector2i(house.micro_x, house.micro_y)
	if from == to:
		return individual.position.distance_to(house_center)
	var path := PathfindingService.find_path(cell, from, to)
	if path.is_empty():
		return -1.0
	var length: float = individual.position.distance_to(Vector2(path[0]) + Vector2(0.5, 0.5))
	for i in range(1, path.size()):
		length += Vector2(path[i - 1]).distance_to(Vector2(path[i]))
	length += (Vector2(path[path.size() - 1]) + Vector2(0.5, 0.5)).distance_to(house_center)
	return length


# true se dopo il riposo il pipottino ha un lavoro da riprendere in un posto preciso: la Task in corso (che il riposo
# sospenderà, se sospendibile) o una Task in coda con almeno uno step rimanente che ha una posizione (WalkAction o
# Action.get_required_position).
static func _has_positioned_follow_up(individual: HumanIndividual) -> bool:
	var candidates: Array[Task] = []
	if individual.current_task != null and not individual.current_task.is_finished() and individual.current_task.is_suspendable:
		candidates.append(individual.current_task)
	candidates.append_array(individual.task_queue)
	for task in candidates:
		if task == null or task.is_finished():
			continue
		for step_index in range(task.current_step_index, task.steps.size()):
			var step: Action = task.steps[step_index]
			if step is WalkAction or step.get_required_position(individual, task.context) != null:
				return true
	return false


# Scostamento del punto di riposo DENTRO la microcella della casa, sempre vicino al suo bordo
# (2026-09-24, richiesta utente — bugfix: prima tutti i residenti andavano sull'angolo in alto a
# sinistra, micro_x/micro_y interi, uno sopra l'altro). Un lato a caso della microcella, a una
# distanza dal bordo di HOUSE_REST_BORDER_INSET_MIN..MAX e in un punto a caso lungo quel lato:
# i residenti si dispongono attorno alla sagoma della casa (disegnata al centro), non sopra.
const HOUSE_REST_BORDER_INSET_MIN: float = 0.08
const HOUSE_REST_BORDER_INSET_MAX: float = 0.2

static func _random_point_near_cell_border() -> Vector2:
	var inset: float = randf_range(HOUSE_REST_BORDER_INSET_MIN, HOUSE_REST_BORDER_INSET_MAX)
	var along: float = randf_range(inset, 1.0 - inset)
	match randi() % 4:
		0:
			return Vector2(along, inset)
		1:
			return Vector2(1.0 - inset, along)
		2:
			return Vector2(along, 1.0 - inset)
		_:
			return Vector2(inset, along)


# Risoluzione del target Walk della Emergency Rest Task — STESSA identica logica di GameScene.
# _resolve_emergency_rest_target (spostata qui tale e quale): angolo casuale, lunghezza FISSA
# (EMERGENCY_REST_STEP_LENGTH), nessun house_id/BuildingRules consultato mai (nessun bonus casa,
# richiesta esplicita del prompt che ha introdotto questa Task).
static func resolve_emergency_rest_target(individual: HumanIndividual) -> Dictionary:
	var target_position: Vector2 = _random_free_point_around(individual, EMERGENCY_REST_STEP_LENGTH, EMERGENCY_REST_STEP_LENGTH)
	return {"target_position": target_position}


# Punto a distanza min_distance..max_distance dall'individuo in una direzione a caso, su una microcella libera e
# raggiungibile (2026-09-27, PathfindingService.pick_free_destination: fino a 8 sorteggi, distanza e direzione
# ritirate ogni volta); nessuno valido = la posizione attuale (l'individuo resta dov'è).
static func _random_free_point_around(individual: HumanIndividual, min_distance: float, max_distance: float) -> Vector2:
	var origin: Vector2 = individual.position
	var destination: Variant = PathfindingService.pick_free_destination(
		individual, func() -> Vector2: return origin + Vector2.from_angle(randf() * TAU) * randf_range(min_distance, max_distance)
	)
	return destination if destination != null else origin


# Costruisce e assegna la Rest Task completa [Walk, Rest, Walk away] — STESSO meccanismo già
# usato dal trigger manuale tasto R (GameScene._assign_rest_task, ora un thin wrapper su questa
# funzione). Ritorna l'esito di individual.assign_task (false = rifiutata dal guard age_band,
# current_task lasciato intatto dal guard stesso — vedi HumanIndividual.assign_task).
#
# is_interrupt_transition (2026-09-13, richiesta utente, bugfix inventario) — default false,
# inoltrato TALE E QUALE a individual.assign_task: il trigger manuale tasto R (GameScene, nessun
# argomento passato) segue la regola unica del carico (_release_cargo_before_manual_need, dal 2026-09-29 — prima
# scartava sempre lo zaino); HumanIndividualActionService passa true
# SOLO quando assegna questa Task-bisogno a seguito di un interrupt automatico rilevato — vedi
# HumanIndividual.assign_task per il perché.
static func assign_rest_task(individual: HumanIndividual, world: World, age_band: HumanTypes.AgeBand, is_interrupt_transition: bool = false) -> bool:
	# Scelta casa/sul posto in base al costo (2026-09-27, richiesta utente) — solo per la Rest da bisogno.
	var target_data := resolve_rest_target(individual, world, true)
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
	# Ultimo step di rest.tres = "allontanati" dopo il riposo (2026-09-27): saltato se all'attivazione c'è un seguito
	# noto (HumanIndividualActionService.has_known_follow_up).
	if not task.steps.is_empty() and task.steps[-1] is WalkAction:
		(task.steps[-1] as WalkAction).is_walk_away = true
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
	if not is_interrupt_transition and _release_cargo_before_manual_need(individual, world, task):
		return true
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
	if not is_interrupt_transition and _release_cargo_before_manual_need(individual, GameSettings.active_world, task):
		return true
	var assigned := individual.assign_task(task, age_band, is_interrupt_transition)
	if assigned and DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
		print("[EMERGENCY REST] Task Walk+Rest assegnata a #%d %s: target=%s, rest_multiplier=1.0 (fisso)" % [
			individual.id, individual.name, target_data["target_position"]
		])
	return assigned


# Riposo MANUALE (tasti R/E, is_interrupt_transition false — 2026-09-29, regola unica del carico, CargoReturnService):
# sostituisce il vecchio individual.stop(), che scartava lo zaino a terra. Se la Task in corso possiede il carico, al
# suo posto parte il ritorno al magazzino e `need_task` va in coda (parte dopo): true. Altrimenti la Task in corso si
# ferma senza scartare lo zaino (un carico di una Task in coda resta suo; uno rimasto senza proprietario lo gestisce
# assign_task) e il chiamante assegna `need_task` come prima: false. L'interrupt automatico non passa mai di qui.
static func _release_cargo_before_manual_need(individual: HumanIndividual, world: World, need_task: Task) -> bool:
	if CargoReturnService.release_cargo(individual, individual.current_task, world) == CargoReturnService.Outcome.RETURNING:
		TaskQueueService.push_suspended_task(individual, need_task)
		return true
	individual.stop(false)
	return false


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
	# Prima lo zaino (2026-09-26): con cibo commestibile addosso la task parte sul posto, senza cammino e anche se
	# non esiste nessun magazzino con cibo. Anche il carico di un'altra task viene mangiato.
	if BACKPACK_RESTOCK_DEFINITION_PATHS.has(definition_path) and FoodSelectionService.has_edible_food(individual.carried_resources):
		if DebugLogging.should_log_restock(individual.id):
			print("[RESTOCK] #%d %s: cibo nello zaino, rifornimento sul posto (%s)." % [individual.id, individual.name, definition_path.get_file()])
		return TaskFactory.build_task(load(BACKPACK_RESTOCK_DEFINITION_PATHS[definition_path]) as TaskDefinition, {
			"restock_target_building": null,
			"restock_source_kind": RestockPouchAction.SourceKind.BACKPACK,
		})
	var source := find_restock_source(individual, world)
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
# Scelta del magazzino del rifornimento (2026-10-09, richiesta utente — provviste normali e d'emergenza): D = distanza
# del magazzino raggiungibile con cibo prelevabile più vicino; contano solo i magazzini con cibo entro
# max(D × FOOD_SOURCE_MAX_DISTANCE_RATIO, D + FOOD_SOURCE_MIN_EXTRA_CELLS) microcelle (in linea d'aria, la stessa misura
# della ricerca del più vicino, SpatialSelectionService.find_nearest).
const FOOD_SOURCE_MAX_DISTANCE_RATIO: float = 3.0
const FOOD_SOURCE_MIN_EXTRA_CELLS: float = 15.0


# Magazzino da cui rifornirsi (2026-10-09): tra quelli con cibo prelevabile entro il limite di distanza qui sopra, quello
# che contiene il cibo con il miglior rapporto calorie/spazio (lo stesso rapporto di FoodSelectionService); a parità il
# più vicino. Stessi filtri di sempre su cosa si può prelevare (WarehouseSelectionService: edificio completo, non da
# demolire, cibo in stored_resources o nel buffer di uscita) e raggiungibilità. Dentro il magazzino la scelta del cibo
# resta quella di FoodSelectionService. null se nessun magazzino ha cibo.
static func find_restock_source(individual: HumanIndividual, world: World) -> Building:
	var reachable := PathfindingService.reachability_for(individual)
	var nearest := WarehouseSelectionService.find_source_for_retrieval(
		world, individual.position, individual.home_macro_coords, SecondaryResourceTypes.Category.FOOD,
		[], 1, individual.id, reachable
	)
	if nearest == null:
		return null
	var origin := individual.position
	var nearest_distance := origin.distance_to(SpatialSelectionService._position_relative_to(nearest, individual.home_macro_coords))
	var max_distance := maxf(nearest_distance * FOOD_SOURCE_MAX_DISTANCE_RATIO, nearest_distance + FOOD_SOURCE_MIN_EXTRA_CELLS)
	var best: Building = nearest
	var best_ratio := _best_food_ratio(nearest)
	var best_distance := nearest_distance
	for building in world.buildings:
		if building == nearest or not building.is_complete or building.is_demolished or building.is_marked_for_demolition:
			continue
		var stock := WarehouseSelectionService.get_matching_stock(building, SecondaryResourceTypes.Category.FOOD, 1)
		if stock.is_empty():
			continue
		var distance := origin.distance_to(SpatialSelectionService._position_relative_to(building, individual.home_macro_coords))
		if distance > max_distance:
			continue
		var ratio := _best_food_ratio(building)
		var better := ratio > best_ratio + 0.000001 or (absf(ratio - best_ratio) <= 0.000001 and distance < best_distance)
		if not better:
			continue
		if reachable.is_valid() and not reachable.call(building):
			continue
		best = building
		best_ratio = ratio
		best_distance = distance
	if DebugLogging.should_log_restock(individual.id) and best != nearest:
		print("[RESTOCK] #%d %s: magazzino %s #%d (calorie/spazio %.1f, distanza %.1f) al posto del più vicino #%d (%.1f, distanza %.1f)." % [
			individual.id, individual.name, best.building_type_name, best.id, best_ratio, best_distance,
			nearest.id, _best_food_ratio(nearest), nearest_distance
		])
	return best


# Miglior rapporto calorie/spazio tra i cibi prelevabili di `building` (stesse regole di FoodSelectionService: calorie e
# spazio per unità > 0); 0 se nessuno.
static func _best_food_ratio(building: Building) -> float:
	var best := 0.0
	for resource_name in WarehouseSelectionService.get_matching_stock(building, SecondaryResourceTypes.Category.FOOD, 1).keys():
		var rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if rules == null or rules.calories_per_unit <= 0.0 or rules.space_per_unit <= 0.0:
			continue
		best = maxf(best, rules.calories_per_unit / rules.space_per_unit)
	return best


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
