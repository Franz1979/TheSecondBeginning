class_name Task
extends RefCounted

# Sequenza ordinata di Action (2026-09-07, richiesta utente) — SOSTITUISCE del tutto
# HumanIndividual.current_action: un individuo ha ora current_task: Task (un solo campo, mai
# affiancato al vecchio). RefCounted come ogni Action (vedi gameplay/scripts/actions/Action.gd) —
# nessuna dipendenza da HumanIndividual/stamina qui dentro: questa classe resta pura struttura dati
# (lista di step + indice), l'avanzamento (QUANDO passare allo step successivo) è deciso dal
# chiamante (HumanIndividualActionService.apply_action), che sa valutare is_complete() sullo step
# attivo — Task offre solo il meccanismo (get_current_action/advance_to_next_step/is_finished), non
# la policy.
#
# Spostata qui, in gameplay/scripts/tasks/ (2026-09-07, richiesta utente — RIORGANIZZAZIONE, prima
# viveva in gameplay/scripts/actions/ insieme alle Action): separa "Action" (verbi atomici —
# WalkAction/RestAction, cosa un individuo SA fare) da "Task" (orchestrazione + ricette — questa
# classe è la sequenza RUNTIME; TaskDefinition/TaskStepDefinition/TaskFactory, stessa cartella,
# sono la descrizione ASTRATTA/riusabile da cui una Task runtime viene costruita, vedi
# task_definition.gd/task_factory.gd). Nessun impatto sui riferimenti esistenti: `class_name Task`
# resta globale in GDScript, nessun preload/percorso hardcoded referenziava questo file altrove.

# Step ordinati — assegnati una volta al costruttore, mai mutati dopo (nessun metodo per
# aggiungere/rimuovere step a runtime in questo passo: "un solo current_task alla volta", nessuna
# coda di più Task, richiesta esplicita).
var steps: Array[Action] = []

# Indice dello step attualmente attivo — 0-based, parte dal primo step. Un valore >= steps.size()
# significa Task conclusa (vedi is_finished sotto); nessun valore negativo previsto in pratica
# (mai decrementato da nessun metodo qui), il controllo `< 0` in get_current_action sotto è solo
# una guardia difensiva simmetrica, non un caso d'uso reale.
var current_step_index: int = 0

# Contesto condiviso tra gli step (2026-09-07, richiesta utente) — Dictionary libero, non campi
# dedicati: forma più semplice possibile finché non esiste un consumatore reale che dica quali
# chiavi servono davvero (item/quantità/source/destination, citati come esempi nella richiesta, ma
# NESSUNA Action li legge o scrive ancora in questo passo). Deliberatamente non tipizzato oltre
# Dictionary generico — una Task futura per un mestiere composito (es. "vai alla pianta, raccogli,
# torna, deposita") potrebbe scrivere qui la risorsa raccolta tra uno step e il successivo, ma
# quella logica non esiste ancora: il campo è pronto, vuoto, non consumato.
var context: Dictionary = {}

# Nome identificativo leggibile, SOLO per debug/log (es. print_cost_summary sotto) — "" se non
# valorizzato (ogni Task costruita a mano, es. dai test di debug in GameScene, lo lascia vuoto).
# TaskFactory.build_task lo copia da TaskDefinition.task_name quando una Task nasce da una vera
# ricetta (vedi task_factory.gd) — mai letto da nessuna logica di simulazione, solo dal log.
var task_name: String = ""

# Costo in stamina e giorni di gioco accumulati PER STEP (2026-09-07, richiesta utente) — array
# paralleli a `steps` (stesso indice), aggiornati da record_step_cost sotto ad ogni
# HumanIndividualActionService.apply_action mentre quello step è quello attivo. Vive qui (non su
# HumanIndividualActionService) perché il costo appartiene alla Task, non al service stateless che
# la applica — stesso principio "chi possiede il dato lo tiene" già seguito per current_step_index.
var step_stamina_cost: Array[float] = []
var step_days_elapsed: Array[float] = []

# Descrizione di ogni step per l'info panel individuo (2026-09-07, richiesta utente) — array
# PARALLELO a `steps` (stesso indice), chiavi tr() (mai testo già tradotto, vedi TaskStepDefinition.
# step_description) o "" se quello step non ne ha una propria (get_activity_description sotto
# ripiega sul nome grezzo della classe Action). TaskFactory.build_task lo valorizza da
# TaskStepDefinition quando una Task nasce da una vera ricetta; una Task costruita a mano (es. i
# test di debug in GameScene) può valorizzarlo direttamente, stesso principio di task_name sopra.
var step_descriptions: Array[String] = []


func _init(p_steps: Array[Action] = []) -> void:
	steps = p_steps
	step_stamina_cost.resize(steps.size())
	step_stamina_cost.fill(0.0)
	step_days_elapsed.resize(steps.size())
	step_days_elapsed.fill(0.0)
	step_descriptions.resize(steps.size())
	step_descriptions.fill("")


# Aggiunge nuovi step in coda a una Task GIÀ in corso (richiesta utente, 2026-09-09, re-routing
# UnloadAction su magazzino pieno) — a differenza di _init() sopra, qui steps/current_step_index
# possono già contenere progresso accumulato: NON si può usare .fill() sugli array paralleli
# esistenti (cancellerebbe i costi già registrati degli step passati). Le tre array temporanee
# sotto sono invece fresche/vuote, quindi resize()+fill() su di LORO è sicuro, poi si accodano
# agli array reali con append_array — stesso effetto di _init() ma solo sulla porzione nuova.
func append_steps(new_steps: Array[Action]) -> void:
	steps.append_array(new_steps)
	var added_count := new_steps.size()

	var new_stamina_costs: Array[float] = []
	new_stamina_costs.resize(added_count)
	new_stamina_costs.fill(0.0)
	step_stamina_cost.append_array(new_stamina_costs)

	var new_days_elapsed: Array[float] = []
	new_days_elapsed.resize(added_count)
	new_days_elapsed.fill(0.0)
	step_days_elapsed.append_array(new_days_elapsed)

	var new_descriptions: Array[String] = []
	new_descriptions.resize(added_count)
	new_descriptions.fill("")
	step_descriptions.append_array(new_descriptions)


# Azione attiva (quella all'indice corrente) — null se la lista è vuota o l'indice è già oltre
# l'ultimo step (Task conclusa). Il chiamante NON deve mai assumere un'Action non-null senza aver
# controllato prima is_finished()/il valore di ritorno qui (stesso pattern già in uso da
# HumanIndividualActionService per il vecchio current_action nullable).
func get_current_action() -> Action:
	if current_step_index < 0 or current_step_index >= steps.size():
		return null
	return steps[current_step_index]


# Fa avanzare l'indice di UNO step. Nessun controllo sul completamento dello step corrente qui
# dentro (responsabilità del chiamante, che decide QUANDO chiamare in base a is_complete() —
# questa classe non conosce HumanIndividual/stamina, quindi non può valutarlo da sé). Chiamabile
# anche quando la Task è già conclusa: current_step_index cresce oltre steps.size() senza errori,
# is_finished() resta semplicemente vero (nessun clamp necessario).
func advance_to_next_step() -> void:
	current_step_index += 1


func is_finished() -> bool:
	return current_step_index >= steps.size()


# Accumula il costo di QUESTO istante nello step attualmente attivo (2026-09-07, richiesta utente)
# — chiamata da HumanIndividualActionService.apply_action subito dopo get_stamina_delta, con lo
# stesso valore già sommato a individual.current_stamina e lo stesso `delta` (giorni di gioco)
# ricevuto quel frame. No-op se l'indice è fuori range (Task già conclusa) — non dovrebbe succedere
# nell'ordine in cui apply_action la chiama oggi, ma resta una guardia difensiva coerente con
# get_current_action sopra.
func record_step_cost(stamina_delta: float, days_delta: float) -> void:
	if current_step_index < 0 or current_step_index >= steps.size():
		return
	step_stamina_cost[current_step_index] += stamina_delta
	step_days_elapsed[current_step_index] += days_delta


# Log una tantum del costo totale della Task, scomposto per step (2026-09-07, richiesta utente) —
# chiamato da HumanIndividualActionService.apply_action SOLO quando is_finished() diventa vero
# (tutti gli step completati), mai una volta per step. Nome dello step risolto via reflection
# (get_script().get_global_name(), Godot 4.3+) invece di un campo dedicato su Action: evita di dover
# aggiungere un override "display_name"-simile a OGNI sottoclasse solo per un log di debug.
# `individual` generico (Variant, stesso principio di Action.get_stamina_delta) — usato solo per
# comporre l'etichetta quando task_name è vuoto (nessuna Task costruita a mano nei test di debug lo
# valorizza ancora).
func print_cost_summary(individual: Variant) -> void:
	var label: String = task_name if task_name != "" else "Task di %s" % individual.name
	print("[TASK COST] %s:" % label)
	var total_stamina := 0.0
	var total_days := 0.0
	for i in range(steps.size()):
		var step_name: String = steps[i].get_script().get_global_name()
		print("  - %s: %.1f stamina (%.1f giorni)" % [step_name, step_stamina_cost[i], step_days_elapsed[i]])
		total_stamina += step_stamina_cost[i]
		total_days += step_days_elapsed[i]
	print("  TOTALE: %.1f stamina, %.1f giorni" % [total_stamina, total_days])


# Testo per l'info panel individuo — "cosa sta facendo ORA" (2026-09-07, richiesta utente): es.
# "Sognare a occhi aperti (Vagando nei dintorni)" mentre il primo WalkAction di Daydream è attivo,
# "Sognare a occhi aperti (Tornando al centro del villaggio)" durante il secondo — stesso
# ActionType (WALK) in entrambi, significato diverso perché lo step_description cambia, mai
# l'Action stessa (vedi TaskStepDefinition.step_description per il perché vive lì e non su Action).
# tr() applicato QUI (non a monte, né su task_name/step_descriptions che restano chiavi grezze —
# stesso principio di BuildingRules.building_name/Idea.display_name): la lingua corrente conta solo
# al momento di mostrare il testo, mai quando i dati vengono assegnati. "" se la Task non ha
# un'azione attiva (già conclusa/vuota — il chiamante non dovrebbe arrivare fin qui in quel caso,
# dato che HumanIndividual.current_task diventa null non appena una Task finisce, ma resta una
# guardia difensiva coerente con get_current_action).
func get_activity_description() -> String:
	if get_current_action() == null:
		return ""
	var step_description_key: String = step_descriptions[current_step_index] if current_step_index < step_descriptions.size() else ""
	# Ripiego sul nome grezzo della classe Action (stesso trattamento di print_cost_summary sopra)
	# quando lo step non ha una propria descrizione — copre le Task costruite a mano che non
	# valorizzano step_descriptions (es. _debug_test_two_walk_task), mostrando comunque qualcosa
	# invece di un pannello vuoto.
	var step_text: String = tr(step_description_key) if step_description_key != "" else get_current_action().get_script().get_global_name()
	if task_name == "":
		return step_text
	return "%s (%s)" % [tr(task_name), step_text]
