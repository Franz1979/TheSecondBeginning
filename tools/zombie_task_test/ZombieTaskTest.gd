extends Node

# TEST AUTOMATIZZATO — bug "task zombie" (2026-09-16, richiesta utente) — stesso stile di
# tools/first_start_cell_check/FirstStartCellCheck.gd: Node standalone, nessun framework di test
# (il progetto non ne ha uno, vedi CLAUDE.md), print("OK: ...")/push_error("MISMATCH: ...") come
# esito, eseguito headless via:
#   Godot.exe --headless --path <project> res://tools/zombie_task_test/ZombieTaskTest.tscn
#
# CAUSA (ricognizione precedente): quando una Task sospendibile (transport/build/haul_resource,
# tutte interrupt_priority=-1) finisce naturalmente (HumanIndividualActionService.apply_action,
# righe 178-197), individual.current_task NON viene azzerato prima di chiamare
# resolve_idle_individual. Se resolve_idle_individual arriva al ramo idle-fallback (stamina OK,
# coda vuota) e questo riesce ad assegnare qualcosa, passa da HumanIndividual.assign_task, che
# trova ancora la Task appena conclusa come current_task e — se is_suspendable, vero per tutte e
# tre — la sospende in coda COSÌ COM'È (current_step_index == steps.size()). Alla ripresa,
# activate_resumed_task la trova già "finita" e non fa nulla: individuo bloccato per sempre.
#
# Task SINTETICHE per i test a/b/c/e/f/g — NON le vere transport.tres/build.tres/
# haul_resource.tres (che richiederebbero Building/World completi solo per il CONTENUTO degli
# step, irrilevante al bug): sono Task con un solo WalkAction, ma con task_name/is_suspendable/
# interrupt_priority COPIATI dai valori reali dei tre .tres — il meccanismo del bug dipende SOLO
# da questi tre campi (verificato in ricognizione: ogni Action chiude tramite lo stesso ciclo
# generico di apply_action, nessuna scorciatoia specifica al contenuto degli step). Il test h)
# usa invece le vere transport.tres/Building/BuildingStorageService per riprodurre alla lettera
# lo scenario reale di #10 (deposito parziale + residuo re-instradato).
#
# INFRASTRUTTURA DI TEST aggiunta insieme a questo file (2026-09-16), NON logica del fix:
#   - IdleTaskAssignmentService.WANDER_ENABLED/LEISURE_REST_ENABLED: da const a static var,
#     STESSO valore di default (false) — permette al test c)/a)/b) di forzarle temporaneamente a
#     true per esercitare il ramo idle-fallback riuscito, poi ripristinarle. Comportamento di
#     produzione INVARIATO (default identico).
#   - TaskQueueService.purge_finished_tasks / HumanIndividualActionService.
#     recover_zombie_current_task: SCHELETRI no-op (return 0 / return false) aggiunti SOLO perché
#     il test g) deve poter chiamarli per compilare — la logica vera arriva nel punto B. Nessun
#     altro codice di produzione esistente è stato toccato in questo passo A.

const HUMAN_RULES_PATH := "res://human/data/human_rules/player_human_rules.tres"
const ERA_NAME := "paleolithic"
const REST_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/rest.tres"
const TRANSPORT_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/transport.tres"

var _next_individual_id := 1
var _pass_count := 0
var _fail_count := 0


func _ready() -> void:
	_test_a_transport_idle_fallback()
	_test_b_build_and_haul_idle_fallback()
	_test_c_assign_task_guard_direct()
	_test_e_push_suspended_task_rejects_finished()
	_test_f_queue_skips_finished_resumes_valid()
	_test_g_load_recovery()
	_test_h1_regression_partial_deposit()
	_test_h2_regression_suspend_resume_not_finished()

	print("\n=== RIEPILOGO: %d passati, %d falliti ===" % [_pass_count, _fail_count])
	get_tree().quit()


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("OK: %s" % label)
	else:
		_fail_count += 1
		push_error("MISMATCH: %s" % label)


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

func _make_game_data() -> GameData:
	var game_data := GameData.new()
	var human_rules := load(HUMAN_RULES_PATH) as HumanRules
	game_data.set_current_era(ERA_NAME, human_rules)
	game_data.year = 40
	return game_data


func _make_individual(position: Vector2) -> HumanIndividual:
	var individual := HumanIndividual.new()
	individual.id = _next_individual_id
	_next_individual_id += 1
	individual.name = "Test%d" % individual.id
	individual.sex = HumanTypes.Sex.MALE
	individual.birth_year_virtual = 15 # con game_data.year=40 -> età 25 -> FERTILE_ADULT
	individual.position = position
	individual.home_macro_coords = Vector2i(0, 0)
	individual.max_stamina = 1000.0
	individual.current_stamina = 1000.0
	individual.max_carry_capacity = 200.0
	individual.house_id = -1
	return individual


func _make_world() -> World:
	return World.new()


# Task sintetica con un solo WalkAction verso `position` — se `position` coincide con quella
# GIÀ attuale dell'individuo, is_complete() risulta vero al primissimo apply_action (nessun
# movimento necessario). is_suspendable/interrupt_priority copiati dai valori reali di
# transport.tres/build.tres/haul_resource.tres (tutti true/-1) — vedi nota di testa al file.
func _make_about_to_finish_task(task_name: String, position: Vector2) -> Task:
	var task := Task.new([WalkAction.new(position)])
	task.task_name = task_name
	task.is_suspendable = true
	task.interrupt_priority = -1
	return task


# Task sintetica GIÀ conclusa (current_step_index forzato a steps.size()) — per i test che
# vogliono partire direttamente da "una task finita esiste già", senza doverla far completare
# tramite apply_action.
func _make_finished_task(task_name: String) -> Task:
	var task := _make_about_to_finish_task(task_name, Vector2.ZERO)
	task.current_step_index = task.steps.size()
	return task


# Task sintetica MAI completabile in questo test (target lontanissimo, mai raggiunto): serve solo
# a rappresentare "una task valida, non finita" senza doverla eseguire.
func _make_unfinished_task(task_name: String) -> Task:
	var task := Task.new([WalkAction.new(Vector2(9999, 9999))])
	task.task_name = task_name
	task.is_suspendable = true
	task.interrupt_priority = -1
	return task


func _assert_no_zombie(individual: HumanIndividual, label: String) -> void:
	var current_ok := individual.current_task == null or not individual.current_task.is_finished()
	_check(current_ok, "%s — current_task non è una task già conclusa" % label)
	var queue_ok := true
	for queued in individual.task_queue:
		if queued.is_finished():
			queue_ok = false
	_check(queue_ok, "%s — task_queue non contiene task già concluse" % label)


func _drive(individual: HumanIndividual, world: World, game_data: GameData, action_service: HumanIndividualActionService, movement_service: HumanIndividualMovementService, iterations: int, delta: float = 1.0) -> void:
	for i in range(iterations):
		movement_service.advance_movement(individual, delta)
		action_service.apply_action(individual, delta, world, game_data)


# ---------------------------------------------------------------------------
# a)/b) — transport/build/haul_resource completano naturalmente con stamina OK, coda vuota,
# fallback idle FORZATO attivo per la durata della sola chiamata che assegna il fallback.
# ---------------------------------------------------------------------------

func _run_idle_fallback_zombie_case(task_name: String, label: String) -> void:
	var previous_wander := IdleTaskAssignmentService.WANDER_ENABLED
	var previous_leisure := IdleTaskAssignmentService.LEISURE_REST_ENABLED

	var game_data := _make_game_data()
	var world := _make_world()
	var action_service := HumanIndividualActionService.new()
	var movement_service := HumanIndividualMovementService.new()

	var individual := _make_individual(Vector2(50, 50))
	individual.current_stamina = 900.0 # 90%, ben sopra STAMINA_REST_THRESHOLD (0.20)

	var task := _make_about_to_finish_task(task_name, individual.position)
	individual.assign_task(task, HumanTypes.AgeBand.FERTILE_ADULT)

	IdleTaskAssignmentService.WANDER_ENABLED = true
	IdleTaskAssignmentService.LEISURE_REST_ENABLED = true
	movement_service.advance_movement(individual, 1.0)
	action_service.apply_action(individual, 1.0, world, game_data)
	# Ripristino SUBITO dopo l'unica chiamata che ne ha bisogno (2026-09-16, richiesta utente:
	# "ripristinandoli alla fine anche in caso di errore") — finestra di alterazione minima;
	# _ready() sotto ripristina comunque di nuovo, difensivamente, dopo ogni funzione di test.
	IdleTaskAssignmentService.WANDER_ENABLED = previous_wander
	IdleTaskAssignmentService.LEISURE_REST_ENABLED = previous_leisure

	_check(individual.current_task != null, "%s: dopo il completamento naturale, current_task non è null (idle-fallback assegnato)" % label)
	if individual.current_task != null:
		_check(
			individual.current_task.task_name in ["task_wander_name", "task_leisure_rest_name"],
			"%s: la nuova task è Wander o Leisure Rest (idle-fallback), non un residuo di '%s'" % [label, task_name]
		)
	_assert_no_zombie(individual, "%s: subito dopo l'idle-fallback forzato" % label)

	# Interruttore GLOBALE spento per la fase finale (2026-09-16, richiesta utente — WANDER_ENABLED/
	# LEISURE_REST_ENABLED sono ora true DI DEFAULT in produzione: senza spegnere fallback_enabled
	# qui, l'idle-fallback continuerebbe a riassegnarsi da solo all'infinito, e l'individuo non
	# tornerebbe mai "libero" — non un bug, il comportamento voluto, solo incompatibile con questa
	# parte del test). Usare l'interruttore globale invece di ri-forzare i due flag granulari a
	# false isola questa fase dal loro default ambientale, ED esercita fallback_enabled come
	# regressione.
	var previous_fallback_enabled := IdleTaskAssignmentService.fallback_enabled
	IdleTaskAssignmentService.fallback_enabled = false
	_drive(individual, world, game_data, action_service, movement_service, 20)
	IdleTaskAssignmentService.fallback_enabled = previous_fallback_enabled

	_assert_no_zombie(individual, "%s: dopo il ciclo Wander/Leisure Rest" % label)
	_check(individual.current_task == null, "%s: al termine (fallback globale spento) l'individuo è libero" % label)
	_check(individual.task_queue.is_empty(), "%s: task_queue vuota al termine" % label)


func _test_a_transport_idle_fallback() -> void:
	print("\n=== TEST a) transport completa con stamina OK, coda vuota, fallback idle FORZATO -> nessuno zombie ===")
	_run_idle_fallback_zombie_case("task_transport_name", "a)")


func _test_b_build_and_haul_idle_fallback() -> void:
	print("\n=== TEST b) stesso scenario di a) con build e haul_resource ===")
	_run_idle_fallback_zombie_case("task_build_name", "b) [build]")
	_run_idle_fallback_zombie_case("task_haul_resource_name", "b) [haul_resource]")


# ---------------------------------------------------------------------------
# c) — guardia a livello di assign_task, indipendente da come ci si arriva: current_task già
# finita + chiamata diretta ad assign_rest_task/assign_emergency_rest_task (is_interrupt_
# transition=true, stesso identico percorso che HumanIndividualActionService._handle_stamina_
# interrupt userebbe per un bisogno reale).
# ---------------------------------------------------------------------------

func _test_c_assign_task_guard_direct() -> void:
	print("\n=== TEST c) assign_task scarta una current_task già finita (chiamata diretta, Rest ed Emergency Rest) ===")
	var world := _make_world()

	var individual_rest := _make_individual(Vector2(50, 50))
	individual_rest.current_task = _make_finished_task("task_transport_name")
	var assigned_rest := NeedTaskAssignmentService.assign_rest_task(individual_rest, world, HumanTypes.AgeBand.FERTILE_ADULT, true)
	_check(assigned_rest, "c) [Rest] assign_rest_task riesce anche con una current_task già finita")
	_check(individual_rest.current_task != null and individual_rest.current_task.task_name == "task_rest_name", "c) [Rest] current_task è ora la Rest")
	_check(individual_rest.task_queue.is_empty(), "c) [Rest] la task finita NON è stata messa in coda")

	var individual_emergency := _make_individual(Vector2(50, 50))
	individual_emergency.current_task = _make_finished_task("task_build_name")
	var assigned_emergency := NeedTaskAssignmentService.assign_emergency_rest_task(individual_emergency, HumanTypes.AgeBand.FERTILE_ADULT, true)
	_check(assigned_emergency, "c) [Emergency Rest] assign_emergency_rest_task riesce anche con una current_task già finita")
	_check(individual_emergency.current_task != null and individual_emergency.current_task.task_name == "task_emergency_rest_name", "c) [Emergency Rest] current_task è ora la Emergency Rest")
	_check(individual_emergency.task_queue.is_empty(), "c) [Emergency Rest] la task finita NON è stata messa in coda")


# ---------------------------------------------------------------------------
# e) — TaskQueueService.push_suspended_task rifiuta una task già conclusa.
# ---------------------------------------------------------------------------

func _test_e_push_suspended_task_rejects_finished() -> void:
	print("\n=== TEST e) TaskQueueService.push_suspended_task rifiuta una task già conclusa ===")
	var individual := _make_individual(Vector2(50, 50))
	var finished := _make_finished_task("task_transport_name")
	TaskQueueService.push_suspended_task(individual, finished)
	_check(individual.task_queue.is_empty(), "e) la task già conclusa non è stata accodata")


# ---------------------------------------------------------------------------
# f) — coda con [task finita, task valida] (finita in cima, popped per prima): la ripresa deve
# saltarla e riprendere la valida.
# ---------------------------------------------------------------------------

func _test_f_queue_skips_finished_resumes_valid() -> void:
	print("\n=== TEST f) coda [task finita, task valida]: la ripresa salta la prima e riprende la seconda ===")
	var world := _make_world()
	var individual := _make_individual(Vector2(50, 50))
	individual.current_stamina = individual.max_stamina # nessun bisogno attivo

	var valid := _make_unfinished_task("task_build_name")
	var finished := _make_finished_task("task_transport_name")
	# LIFO: pop_suspended_task estrae dal FONDO — accodo "valid" per primo (resterà sul fondo,
	# estratta per SECONDA) e "finished" per ultimo (in cima, estratta per PRIMA).
	individual.task_queue.append(valid)
	individual.task_queue.append(finished)

	HumanIndividualActionService.resolve_idle_individual(individual, HumanTypes.AgeBand.FERTILE_ADULT, world)

	_check(individual.current_task == valid, "f) current_task è la task valida, non quella finita")
	_check(individual.task_queue.is_empty(), "f) la coda è vuota dopo la ripresa (entrambe estratte)")


# ---------------------------------------------------------------------------
# g) — recupero da salvataggio: current_task già finita + coda con task finite -> individuo
# libero, code pulite. Usa le due funzioni introdotte per il fix (TaskQueueService.
# purge_finished_tasks / HumanIndividualActionService.recover_zombie_current_task), oggi ancora
# SCHELETRI no-op — la logica vera arriva nel punto B.
# ---------------------------------------------------------------------------

func _test_g_load_recovery() -> void:
	print("\n=== TEST g) recupero da salvataggio: current_task finita + coda con task finite -> individuo libero, code pulite ===")
	var individual := _make_individual(Vector2(50, 50))
	individual.current_task = _make_finished_task("task_transport_name")
	individual.task_queue.append(_make_finished_task("task_build_name"))
	individual.task_queue.append(_make_finished_task("task_haul_resource_name"))

	# STESSA sequenza prevista per GameScene._ready() (punto 3 del fix): purge coda, poi rilascia
	# current_task se già conclusa, PRIMA di valutare "è libero?".
	var purged := TaskQueueService.purge_finished_tasks(individual)
	var recovered := HumanIndividualActionService.recover_zombie_current_task(individual)

	_check(purged == 2, "g) entrambe le task finite in coda sono state rimosse (rimosse=%d)" % purged)
	_check(individual.task_queue.is_empty(), "g) task_queue vuota dopo il recupero")
	_check(recovered, "g) current_task già finita è stata rilasciata")
	_check(individual.current_task == null, "g) current_task è null dopo il recupero (individuo trattato come libero)")


# ---------------------------------------------------------------------------
# h1) — regressione: transport REALE (transport.tres) con deposito parziale al cantiere +
# residuo re-instradato al magazzino (scenario reale di #10) completa correttamente.
# ---------------------------------------------------------------------------

func _test_h1_regression_partial_deposit() -> void:
	print("\n=== TEST h) regressione: transport con deposito parziale + residuo al magazzino (#10) ===")
	var game_data := _make_game_data()
	var world := _make_world()
	var action_service := HumanIndividualActionService.new()
	var movement_service := HumanIndividualMovementService.new()

	var source_rules := BuildingRules.new()
	source_rules.category = BuildingTypes.Category.RESIDENTIAL
	source_rules.storage_slot_count = 10
	source_rules.storage_space_per_slot = 100
	var source := Building.new(source_rules, 0, 0, "hut")
	source.id = 1
	source.is_complete = true
	source.micro_x = 10
	source.micro_y = 10
	source.stored_resources["stick"] = {"quantity": 20, "decay_fraction": 0.0}

	# Cantiere/destinazione con capacità per UNA sola unità di stick (space_per_unit=10.0,
	# storage_space_per_slot=10 -> esattamente 1 unità) — stessa forma del deposito parziale "1
	# su 4" osservato per #10.
	var destination_rules := BuildingRules.new()
	destination_rules.category = BuildingTypes.Category.POLITICAL
	destination_rules.storage_slot_count = 1
	destination_rules.storage_space_per_slot = 10
	var destination := Building.new(destination_rules, 0, 0, "stick_tent")
	destination.id = 2
	destination.is_complete = true
	destination.micro_x = 20
	destination.micro_y = 20

	var warehouse_rules := BuildingRules.new()
	warehouse_rules.category = BuildingTypes.Category.STORAGE
	warehouse_rules.storage_slot_count = 10
	warehouse_rules.storage_space_per_slot = 100
	var warehouse := Building.new(warehouse_rules, 0, 0, "deposit_site")
	warehouse.id = 3
	warehouse.is_complete = true
	warehouse.micro_x = 30
	warehouse.micro_y = 30

	world.buildings = [source, destination, warehouse]

	var individual := _make_individual(Vector2(source.micro_x, source.micro_y))
	# Stamina ENORMEMENTE sovradimensionata (2026-09-16) — a differenza di a)/b)/c) (WalkAction
	# sintetico a costo zero, target==posizione attuale), qui le Action sono REALI: con
	# delta=1.0/iterazione (vedi _drive) un singolo Walk di ~14 microcelle a zaino pieno costa
	# centinaia di stamina. Senza questo margine l'individuo scenderebbe sotto soglia REST/
	# EMERGENCY a metà tragitto, innescando un'interruzione che non ha nulla a che fare con quello
	# che questo test vuole verificare (deposito parziale + residuo re-instradato).
	individual.max_stamina = 1000000.0
	individual.current_stamina = 1000000.0

	var transport_definition := load(TRANSPORT_DEFINITION_PATH) as TaskDefinition
	var context := {
		"transport_source_position": Vector2(source.micro_x, source.micro_y),
		"transport_source_building": source,
		"transport_resource_name": "stick",
		"transport_quantity": 4,
		"transport_destination_position": Vector2(destination.micro_x, destination.micro_y),
		"transport_destination_building": destination,
	}
	var task := TaskFactory.build_task(transport_definition, context)
	individual.assign_task(task, HumanTypes.AgeBand.FERTILE_ADULT)

	# Interruttore GLOBALE spento (2026-09-16, richiesta utente) — questo test verifica il deposito
	# parziale/residuo re-instradato, non l'idle-fallback: con WANDER_ENABLED/LEISURE_REST_ENABLED
	# ora true di default in produzione, senza spegnere fallback_enabled l'individuo riceverebbe
	# Wander/Leisure Rest invece di tornare libero al termine, un esito corretto ma estraneo a
	# quello che questo test misura.
	var previous_fallback_enabled := IdleTaskAssignmentService.fallback_enabled
	IdleTaskAssignmentService.fallback_enabled = false
	_drive(individual, world, game_data, action_service, movement_service, 25)
	IdleTaskAssignmentService.fallback_enabled = previous_fallback_enabled

	var destination_stick: int = int(destination.stored_resources.get("stick", {}).get("quantity", 0))
	var warehouse_stick: int = int(warehouse.stored_resources.get("stick", {}).get("quantity", 0))
	_check(destination_stick == 1, "h) 1 stick depositato al cantiere originale (deposito parziale) — trovato %d" % destination_stick)
	_check(warehouse_stick == 3, "h) 3 stick residui re-instradati e depositati nel magazzino — trovato %d" % warehouse_stick)
	_check(individual.carried_resources.is_empty(), "h) zaino vuoto al termine")
	_check(individual.current_task == null, "h) la transport termina regolarmente, individuo libero")
	_check(individual.task_queue.is_empty(), "h) nessuna task in coda dopo la conclusione regolare")


# ---------------------------------------------------------------------------
# h2) — regressione: sospensione/ripresa di una task NON finita funziona come prima (il fix non
# deve toccare questo percorso).
# ---------------------------------------------------------------------------

func _test_h2_regression_suspend_resume_not_finished() -> void:
	print("\n=== TEST h) regressione: sospensione/ripresa di una task NON finita invariata ===")
	var game_data := _make_game_data()
	var world := _make_world()
	var action_service := HumanIndividualActionService.new()
	var movement_service := HumanIndividualMovementService.new()

	var individual := _make_individual(Vector2(50, 50))
	individual.current_stamina = 250.0 # 25%, sopra STAMINA_REST_THRESHOLD (0.20)

	var far_target := Vector2(58, 50) # 8 microcelle — con move_speed=10/gg non si arriva in 0.5gg
	var task := Task.new([WalkAction.new(far_target), WalkAction.new(Vector2(50, 50))])
	task.task_name = "task_transport_name"
	task.is_suspendable = true
	task.interrupt_priority = -1
	individual.assign_task(task, HumanTypes.AgeBand.FERTILE_ADULT)

	movement_service.advance_movement(individual, 0.5)
	action_service.apply_action(individual, 0.5, world, game_data)
	_check(individual.current_task == task and task.current_step_index == 0, "h) la task sintetica è ancora al primo step, non completa")

	# Stamina sotto soglia (simula un lavoro lungo): il prossimo apply_action deve interromperla e
	# sospenderla in coda INTATTA (non finita) — comportamento preesistente, invariato dal fix.
	individual.current_stamina = 150.0
	movement_service.advance_movement(individual, 0.1)
	action_service.apply_action(individual, 0.1, world, game_data)

	_check(individual.current_task != null and individual.current_task.task_name == "task_rest_name", "h) interrotta da un bisogno di Rest (comportamento esistente)")
	_check(individual.task_queue.size() == 1, "h) la task originale è stata sospesa in coda (non scartata)")
	if individual.task_queue.size() == 1:
		_check(individual.task_queue[0] == task, "h) è esattamente la stessa istanza, non ricostruita")
		_check(not task.is_finished(), "h) la task sospesa NON è finita")

	# Drive ITERAZIONE PER ITERAZIONE (non un _drive fisso, 2026-09-16 — bugfix del test stesso:
	# la task originale, una volta ripresa, ha solo due WalkAction brevi e finisce anch'essa in
	# 1-2 iterazioni — un _drive fisso a N iterazioni la lascerebbe già CONCLUSA/sostituita
	# dall'idle-fallback al momento del controllo, mascherando l'esito della ripresa stessa che
	# questo test vuole verificare). Fermarsi al PRIMO istante in cui current_task torna ad essere
	# esattamente `task` cattura il momento della ripresa, indipendentemente da quanto dura dopo.
	var resumed := false
	for i in range(15):
		movement_service.advance_movement(individual, 1.0)
		action_service.apply_action(individual, 1.0, world, game_data)
		if individual.current_task == task:
			resumed = true
			break
	_check(resumed, "h) dopo la Rest, la task originale è ripresa dalla coda (stessa istanza)")
	_check(individual.task_queue.is_empty(), "h) la coda è di nuovo vuota dopo la ripresa")
