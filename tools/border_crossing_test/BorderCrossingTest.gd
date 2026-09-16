extends Node

# TEST AUTOMATIZZATO — bug di bordo macrocella per le task perditempo (2026-09-16, richiesta
# utente) — stesso stile di tools/zombie_task_test/ZombieTaskTest.gd/tools/first_start_cell_check/
# FirstStartCellCheck.gd: Node standalone, print("OK: ...")/push_error("MISMATCH: ...") come
# esito, eseguito headless via:
#   Godot.exe --headless --path <project> res://tools/border_crossing_test/BorderCrossingTest.tscn
#
# CAUSA A: resolve_wander_targets/resolve_play_targets/NeedTaskAssignmentService.
# resolve_rest_target calcolano TUTTI i target assoluti in un colpo solo all'assegnazione. Al
# cambio di macrocella, GameScene._attempt_macro_cell_transition ribasava SOLO il target dello
# step ATTIVO — le gambe FUTURE (e le Task sospese in coda) restavano nel vecchio sistema di
# riferimento. Fix: Task.rebase_positional_targets(offset), che ribasa OGNI step non ancora
# completato la cui Action.target sia un Vector2 (WalkAction/RunAction — ogni altra Action lascia
# target null e usa proprie posizioni derivate da home_macro_coords, già corrette da sole).
#
# CAUSA B: GameScene._block_border_crossing clampava la posizione sul bordo e metteva
# is_moving=false SENZA toccare la Task; WalkAction/RunAction.is_complete() confrontava
# position==target in modo esatto, quindi lo step non si completava mai. Fix: (1) tolleranza di
# distanza in is_complete() (robustezza generica); (2) SOLO per le task perditempo
# (Task.is_idle_activity, marcatore esplicito su TaskDefinition — wander.tres/play.tres/
# leisure_rest.tres) una gamba bloccata al bordo viene considerata conclusa, tramite
# HumanIndividualActionService.finish_current_step (estratta dal corpo di apply_action, SECONDO
# chiamante oltre ad apply_action stesso). Per ogni altra Task il comportamento sul bordo bloccato
# resta quello di sempre (nessuna chiamata a finish_current_step da lì).
#
# LIMITE DICHIARATO DI QUESTO TEST: GameScene._attempt_macro_cell_transition/_block_border_
# crossing sono metodi privati di GameScene (un Node con camera/UI/live_cells/ecc., non
# testabile in isolamento senza istanziare l'intera scena) — questo file testa quindi il
# MECCANISMO che quei due metodi usano (Task.rebase_positional_targets, Task.is_idle_activity,
# HumanIndividualActionService.finish_current_step, WalkAction/RunAction.is_complete), non il
# collegamento vero e proprio dentro GameScene. Quel collegamento va verificato in gioco (vedi
# riepilogo finale).

const HUMAN_RULES_PATH := "res://human/data/human_rules/player_human_rules.tres"
const ERA_NAME := "paleolithic"
const WANDER_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/wander.tres"
const LEISURE_REST_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/leisure_rest.tres"
const HAUL_RESOURCE_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/haul_resource.tres"
const NON_IDLE_DEFINITION_PATHS := [
	"res://gameplay/scripts/tasks/definitions/rest.tres",
	"res://gameplay/scripts/tasks/definitions/emergency_rest.tres",
	"res://gameplay/scripts/tasks/definitions/build.tres",
	"res://gameplay/scripts/tasks/definitions/transport.tres",
	"res://gameplay/scripts/tasks/definitions/haul_resource.tres",
]

var _next_individual_id := 1
var _pass_count := 0
var _fail_count := 0


func _ready() -> void:
	_test_a_wander_rebase_future_legs()
	_test_b_wander_blocked_leg_skips_to_end()
	_test_c_leisure_rest_rebase_walk_away()
	_test_d_haul_resource_rebase_generic()
	_test_e_regression_walk_and_non_idle_tasks()

	print("\n=== RIEPILOGO: %d passati, %d falliti ===" % [_pass_count, _fail_count])
	print("NOTA: il test f) (regressione tools/zombie_task_test) va eseguito separatamente, stessa convenzione one-tool-per-scene.")
	get_tree().quit()


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("OK: %s" % label)
	else:
		_fail_count += 1
		push_error("MISMATCH: %s" % label)


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


# ---------------------------------------------------------------------------
# a) — Wander: un attraversamento durante la 1a gamba deve ribasare anche le gambe FUTURE (indici
# 2 e 4, i due Walk successivi in wander.tres: [Walk,LookAround,Walk,LookAround,Walk]).
# ---------------------------------------------------------------------------

func _test_a_wander_rebase_future_legs() -> void:
	print("\n=== TEST a) Wander: bordo attraversato durante la 1a gamba -> le gambe successive vengono ribasate ===")
	var individual := _make_individual(Vector2(50, 50))
	var target_data := IdleTaskAssignmentService.resolve_wander_targets(individual)
	var wander_definition := load(WANDER_DEFINITION_PATH) as TaskDefinition
	var context := {
		"wander_target_1": target_data["target_1"],
		"wander_target_2": target_data["target_2"],
		"wander_target_3": target_data["target_3"],
	}
	var task := TaskFactory.build_task(wander_definition, context)
	_check(task.is_idle_activity, "a) wander.tres produce una Task con is_idle_activity=true")
	_check(task.steps.size() == 5, "a) wander.tres ha 5 step [Walk,LookAround,Walk,LookAround,Walk] (trovati %d)" % task.steps.size())

	# current_step_index resta 0 (la 1a gamba è quella attiva) — STESSO offset che
	# GameScene._attempt_macro_cell_transition applicherebbe per un attraversamento verso ovest.
	var offset := Vector2(-float(World.WIDTH), 0.0)
	var target_1_before: Vector2 = (task.steps[0] as WalkAction).target
	var target_2_before: Vector2 = (task.steps[2] as WalkAction).target
	var target_3_before: Vector2 = (task.steps[4] as WalkAction).target

	var rebased := task.rebase_positional_targets(offset)

	_check(rebased == 3, "a) tutti e 3 i Walk (indici 0,2,4) sono stati ribasati (rebased=%d)" % rebased)
	_check((task.steps[0] as WalkAction).target == target_1_before + offset, "a) gamba 1 (attiva) ribasata correttamente")
	_check((task.steps[2] as WalkAction).target == target_2_before + offset, "a) gamba 2 (futura) ribasata correttamente")
	_check((task.steps[4] as WalkAction).target == target_3_before + offset, "a) gamba 3 (futura) ribasata correttamente")


# ---------------------------------------------------------------------------
# b) — Wander verso un bordo bloccato: ogni gamba bloccata viene considerata conclusa (via
# HumanIndividualActionService.finish_current_step, lo stesso metodo che GameScene.
# _block_border_crossing chiamerebbe per una task perditempo) — la Task deve arrivare comunque
# alla fine, mai restare bloccata a metà.
# ---------------------------------------------------------------------------

func _test_b_wander_blocked_leg_skips_to_end() -> void:
	print("\n=== TEST b) Wander verso un bordo bloccato: la gamba viene saltata, la task prosegue fino alla fine ===")
	var game_data := _make_game_data()
	var world := _make_world()
	var action_service := HumanIndividualActionService.new()
	var individual := _make_individual(Vector2(50, 50))
	individual.current_stamina = 900.0

	var target_data := IdleTaskAssignmentService.resolve_wander_targets(individual)
	var wander_definition := load(WANDER_DEFINITION_PATH) as TaskDefinition
	var context := {
		"wander_target_1": target_data["target_1"],
		"wander_target_2": target_data["target_2"],
		"wander_target_3": target_data["target_3"],
	}
	var task := TaskFactory.build_task(wander_definition, context)
	individual.assign_task(task, HumanTypes.AgeBand.FERTILE_ADULT)
	_check(individual.current_task == task, "b) Wander assegnata")

	# Interruttore GLOBALE spento (2026-09-16, richiesta utente) — questo test verifica che la
	# Wander arrivi alla fine quando le sue gambe vengono bloccate al bordo, non l'idle-fallback:
	# con WANDER_ENABLED/LEISURE_REST_ENABLED ora true di default in produzione, senza spegnere
	# fallback_enabled la conclusione della Wander farebbe scattare un NUOVO idle-fallback (esito
	# corretto in produzione, ma estraneo a quello che questo test misura).
	var previous_fallback_enabled := IdleTaskAssignmentService.fallback_enabled
	IdleTaskAssignmentService.fallback_enabled = false

	# Simula un bordo bloccato su OGNI gamba (5 step in wander.tres) — chiamata diretta a
	# finish_current_step, esattamente cosa farebbe GameScene._block_border_crossing per una task
	# is_idle_activity=true bloccata al bordo. Se una gamba anticipa la conclusione della Task,
	# individual.current_task cambia da sé (idle-fallback/stop) — il ciclo si ferma.
	for i in range(5):
		if individual.current_task != task:
			break
		action_service.finish_current_step(individual, task, world, game_data)

	IdleTaskAssignmentService.fallback_enabled = previous_fallback_enabled

	_check(task.is_finished(), "b) dopo un blocco per ciascuna gamba la Wander risulta conclusa (step %d/%d)" % [task.current_step_index, task.steps.size()])
	_check(individual.current_task != task, "b) l'individuo non è più bloccato sulla Wander conclusa")
	_check(individual.current_task == null, "b) fallback globale spento durante il test -> nessun idle-fallback -> individuo libero")


# ---------------------------------------------------------------------------
# c) — Leisure Rest: un attraversamento durante il Rest (step stazionario) deve ribasare il walk
# away (ultimo step, ancora futuro) — stesso controllo di a).
# ---------------------------------------------------------------------------

func _test_c_leisure_rest_rebase_walk_away() -> void:
	print("\n=== TEST c) Leisure Rest: bordo attraversato durante il Rest -> il walk away (futuro) viene ribasato ===")
	var world := _make_world()
	var individual := _make_individual(Vector2(50, 50))
	var target_data := NeedTaskAssignmentService.resolve_rest_target(individual, world)
	var leisure_definition := load(LEISURE_REST_DEFINITION_PATH) as TaskDefinition
	var context := {
		"target_position": target_data["target_position"],
		"rest_multiplier": target_data["rest_multiplier"],
		"walk_away_target_position": target_data["walk_away_target_position"],
		"rest_max_duration_days": 4.0,
		"rest_ignore_stamina_cap": true,
	}
	var task := TaskFactory.build_task(leisure_definition, context)
	_check(task.is_idle_activity, "c) leisure_rest.tres produce una Task con is_idle_activity=true")
	_check(task.steps.size() == 3, "c) leisure_rest.tres ha 3 step [Walk,Rest,WalkAway] (trovati %d)" % task.steps.size())

	# Simula: il Walk iniziale è già concluso, ora è attivo il Rest (stazionario, target=null) —
	# un attraversamento in questo momento (l'individuo può muoversi anche durante un Rest se un
	# bisogno lo interrompe e lo sposta altrove, o più semplicemente per qualunque causa esterna
	# futura) deve comunque ribasare il walk away, l'UNICO step futuro con un target posizionale.
	task.current_step_index = 1
	var offset := Vector2(0.0, float(World.HEIGHT))
	var walk_away_target_before: Vector2 = (task.steps[2] as WalkAction).target

	var rebased := task.rebase_positional_targets(offset)

	_check(rebased == 1, "c) solo il walk away (unico step futuro con target posizionale) è stato ribasato (rebased=%d)" % rebased)
	_check((task.steps[2] as WalkAction).target == walk_away_target_before + offset, "c) il target del walk away è stato ribasato correttamente")


# ---------------------------------------------------------------------------
# d) — haul_resource (task di LAVORO, non perditempo): il fix generico (CAUSA A) deve ribasare
# anche il suo Walk, a dimostrazione che non è specifico a Wander/Play/Leisure Rest.
# ---------------------------------------------------------------------------

func _test_d_haul_resource_rebase_generic() -> void:
	print("\n=== TEST d) haul_resource: il fix generico ribasa anche il Walk di una task di lavoro ===")
	var macro_state := MacroCellState.new(0, 0)
	var haul_definition := load(HAUL_RESOURCE_DEFINITION_PATH) as TaskDefinition
	var context := {
		"target_position": Vector2(80, 80),
		"pickup_position": Vector2(80, 80),
		"macro_state": macro_state,
		"resource_name": "stick",
	}
	var task := TaskFactory.build_task(haul_definition, context)
	_check(not task.is_idle_activity, "d) haul_resource.tres NON è una task perditempo (is_idle_activity=false)")
	_check(task.steps.size() == 2, "d) haul_resource.tres ha 2 step [Walk,PickUp] (trovati %d)" % task.steps.size())

	var offset := Vector2(float(World.WIDTH), 0.0)
	var walk_target_before: Vector2 = (task.steps[0] as WalkAction).target
	var rebased := task.rebase_positional_targets(offset)

	# rebased atteso 1, non 2: PickUpAction tiene la propria posizione in un campo suo
	# (target_position), MAI in Action.target (resta null) — si ri-deriva da sola, nessun
	# ribasamento esplicito necessario per lei (vedi nota di testa al file).
	_check(rebased == 1, "d) solo il Walk (indice 0) ha un target posizionale generico — PickUp non lo usa (rebased=%d)" % rebased)
	_check((task.steps[0] as WalkAction).target == walk_target_before + offset, "d) il target del Walk verso la risorsa è stato ribasato correttamente")


# ---------------------------------------------------------------------------
# e) — Regressione: WalkAction senza attraversamenti si completa come prima (arrivo esatto);
# nessuna task di lavoro è marcata is_idle_activity (il fix sul bordo bloccato non le riguarda).
# ---------------------------------------------------------------------------

func _test_e_regression_walk_and_non_idle_tasks() -> void:
	print("\n=== TEST e) regressione: WalkAction invariato; nessuna task di lavoro è is_idle_activity ===")
	var individual := _make_individual(Vector2(55, 50))
	var walk := WalkAction.new(Vector2(55, 50))
	_check(walk.is_complete(individual, {}), "e) WalkAction si completa ancora con un arrivo ESATTO (nessuna regressione)")
	individual.position = Vector2(50, 50)
	_check(not walk.is_complete(individual, {}), "e) WalkAction NON si completa se la posizione è lontana dal target")

	for path in NON_IDLE_DEFINITION_PATHS:
		var definition := load(path) as TaskDefinition
		_check(not definition.is_idle_activity, "e) %s NON è una task perditempo (is_idle_activity=false)" % path.get_file())
