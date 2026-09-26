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

# Emesso una volta PER OGNI step aggiunto da append_steps() sotto (2026-09-10, richiesta utente —
# Step 2 del refactor Daydream via TaskFactory, preparazione del meccanismo: serve a un futuro
# chiamante — es. GameScene, per ricollegare i signal idea_completed/thought_deposited a un
# UnloadAction costruito dinamicamente da _handle_pending_thought_target_search, 2c — per sapere
# QUANDO un nuovo step è stato accodato a runtime, dato che append_steps può scattare in un frame
# imprevedibile rispetto a quando la Task originale è stata assegnata). Deliberatamente UN emit per
# step, non un singolo emit con l'intero Array[Action] appena accodato: un listener che vuole
# reagire solo a un tipo concreto (es. `if action is UnloadAction`) filtra su un singolo valore per
# chiamata, senza dover iterare da sé un array ad ogni notifica. Nessun altro cambio di
# comportamento ad append_steps() — il signal è un'aggiunta puramente osservativa.
signal step_appended(action: Action)

# Step ordinati — assegnati una volta al costruttore, mai mutati dopo l'_init (append_steps() sotto
# è l'UNICA eccezione, per Task già in corso — "un solo current_task alla volta", nessuna coda di
# più Task, richiesta esplicita invariata).
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

# Id univoco per-Task (2026-09-12, richiesta utente — "le task hanno un id univoco?": NO prima di
# questo campo, introdotto apposta per la nuova tab di debug 🐞 in TaskDebugPanel/TaskDebugRegistry,
# che elenca tutte le Task assegnate in questa sessione) — contatore STATIC condiviso da OGNI
# istanza (mai per-individuo/per-tipo), incrementato ad ogni _init(), mai riusato nemmeno dopo che
# una Task viene scartata/sostituita. SOLO diagnostico — nessuna logica di simulazione legge mai
# questo campo, stesso principio di task_name sopra. NON persistito (TaskPersistenceService non lo
# scrive/legge): una Task ricostruita da un reload riceve un id NUOVO (il prossimo disponibile),
# mai lo stesso che aveva prima del salvataggio — coerente con TaskDebugRegistry, che è anch'esso
# solo in-memoria per la sessione corrente, mai persistito.
static var _next_id: int = 1
var id: int = 0

# Chiave stabile del target per il tracking di TaskDebugRegistry (2026-09-12, richiesta utente —
# fix righe duplicate/fantasma nel pannello 🐞 quando una Build Task viene ricostruita per lo stesso
# target) — "" (default) = nessun target persistente, il registro traccia questa Task per singola
# ISTANZA come sempre (Walk/Wander/Rest/Daydream/haul_resource: mai ricostruite da un target esterno,
# comportamento invariato). Valorizzata SOLO da TaskReassignmentService.reassign_task subito dopo
# TaskFactory.build_task, PRIMA di individual.assign_task(task), da target.get_debug_target_key()
# (es. "building:%d" % id per una Building — vedi Building.gd) — permette a TaskDebugRegistry.
# on_task_assigned di riconoscere "questa nuova Task riguarda lo STESSO target di una riga già
# aperta" anche quando l'istanza Task precedente (e magari l'individuo assegnato) sono diversi, cosa
# che l'id per-istanza sopra non può esprimere da solo. SOLO diagnostico, stesso trattamento di id/
# task_name sopra — nessuna logica di simulazione lo legge, NON persistito (TaskPersistenceService
# non lo scrive/legge).
var debug_target_key: String = ""

# Numero massimo di individui assegnabili CONTEMPORANEAMENTE a questa Task (2026-09-10, richiesta
# utente — preparazione Build Task, Step 1: SOLO il campo, nessuna logica di condivisione lavoro
# ancora — arriverà con un giro successivo, insieme al vero trigger). Default 1 = comportamento
# invariato per ogni Task esistente (haul_resource/daydreaming, entrambe implicitamente a un solo
# lavoratore, mai più di un individuo alla volta oggi — vedi CLAUDE.md, "un solo current_task alla
# volta"). Stesso trattamento di task_name sopra: TaskFactory.build_task NON lo copia ancora da
# TaskDefinition.max_workers (vedi task_definition.gd) in questo passo — resta al default fisso 1
# per qualunque Task costruita da TaskFactory finché quel collegamento non verrà scritto.
var max_workers: int = 1

# Costo in stamina e giorni di gioco accumulati PER STEP (2026-09-07, richiesta utente) — array
# paralleli a `steps` (stesso indice), aggiornati da record_step_cost sotto ad ogni
# HumanIndividualActionService.apply_action mentre quello step è quello attivo. Vive qui (non su
# HumanIndividualActionService) perché il costo appartiene alla Task, non al service stateless che
# la applica — stesso principio "chi possiede il dato lo tiene" già seguito per current_step_index.
var step_stamina_cost: Array[float] = []
var step_days_elapsed: Array[float] = []
# Costo in happiness accumulato PER STEP (2026-09-13, richiesta utente) — TERZO array parallelo,
# STESSO schema esatto di step_stamina_cost sopra: stesso indice di `steps`, aggiornato da
# record_step_cost nello stesso momento/nella stessa chiamata di apply_action, mai un accumulatore
# separato con un proprio ciclo di vita.
var step_happiness_cost: Array[float] = []

# Descrizione di ogni step per l'info panel individuo (2026-09-07, richiesta utente) — array
# PARALLELO a `steps` (stesso indice), chiavi tr() (mai testo già tradotto, vedi TaskStepDefinition.
# step_description) o "" se quello step non ne ha una propria (get_activity_description sotto
# ripiega sul nome grezzo della classe Action). TaskFactory.build_task lo valorizza da
# TaskStepDefinition quando una Task nasce da una vera ricetta; una Task costruita a mano (es. i
# test di debug in GameScene) può valorizzarlo direttamente, stesso principio di task_name sopra.
var step_descriptions: Array[String] = []

# Fasce d'età (valori ordinali di HumanTypes.AgeBand, Array[int] non Array[HumanTypes.AgeBand] —
# stesso motivo di TaskDefinition.allowed_age_bands, vedi lì) a cui è CONSENTITO eseguire QUESTA
# Task (2026-09-13, richiesta utente, Play Task CHILD-only) — vuoto di default = nessun vincolo
# aggiuntivo (comportamento invariato per ogni Task esistente/costruita a mano: Rest/Wander/
# Daydream/haul_resource/build/transport, nessuna delle quali lo valorizza). A differenza di
# Action.disallowed_age_bands (una fascia in lista = VIETATA, aggregato su TUTTI gli step), qui una
# lista NON vuota significa "SOLO queste fasce ammesse" — le due liste sono indipendenti ed
# ENTRAMBE devono passare in HumanIndividual.assign_task(): un'Action generica può restare ammessa
# a qualunque età mentre la Task che la usa resta comunque riservata a una fascia specifica.
# Copiato da TaskDefinition.allowed_age_bands da TaskFactory.build_task, stesso schema di task_name/
# step_descriptions sopra. NON persistito da TaskPersistenceService (stesso trattamento di id/
# debug_target_key sopra, "SOLO diagnostico/di costruzione"): consultato SOLO al momento di
# assign_task(), mai più dopo — una Task già in corso ricostruita da un reload ha già superato quel
# controllo prima di essere salvata, nessun bisogno di riverificarlo.
var allowed_age_bands: Array[int] = []

# Priorità di interrupt (2026-09-13, richiesta utente, in preparazione al sistema di interrupt da
# stamina critica — SOLO la struttura dati in questo passo, NESSUN collegamento al trigger ancora)
# — numero più BASSO = più urgente. -1 (default) = "non è una Task-bisogno, la priorità non si
# applica a lei" — valore invariato per ogni Task esistente tranne le due Task-bisogno esplicite
# (emergency_rest.tres=1, rest.tres=2, vedi quei file). Copiato da TaskDefinition.interrupt_
# priority da TaskFactory.build_task, stesso schema di allowed_age_bands sopra. PERSISTITO da
# TaskPersistenceService (a differenza di allowed_age_bands sopra): questo campo va ricontrollato
# CONTINUAMENTE durante l'esecuzione (ogni volta che un nuovo interrupt scatta, non solo al momento
# di assign_task()), quindi un current_task/task in coda ricostruiti da un reload devono conservare
# il valore originale, non ripartire dal default -1.
var interrupt_priority: int = -1

# Sospendibilità (2026-09-13, richiesta utente, stesso contesto di interrupt_priority sopra) — vero
# SOLO per le Task di lavoro che possono essere messe in pausa e riprese più tardi (oggi
# haul_resource.tres/transport.tres, vedi quei file) quando un interrupt la interrompe. Default
# false = comportamento invariato per ogni altra Task (incluse le due Task-bisogno sopra, mai
# sospendibili a loro volta). Copiato da TaskDefinition.is_suspendable da TaskFactory.build_task,
# stesso schema di interrupt_priority sopra. PERSISTITO, stesso motivo identico di interrupt_
# priority: va ricontrollato continuamente durante l'esecuzione, non solo al momento di
# assign_task().
var is_suspendable: bool = false

# Marcatore esplicito "task perditempo" (2026-09-16, richiesta utente, fix bordo macrocella) —
# vero SOLO per wander.tres/play.tres/leisure_rest.tres (vedi quei tre file). Criterio ESPLICITO
# per distinguere le task idle-fallback da ogni altra (mai un confronto su task_name, che resta
# solo un'etichetta di debug/UI, vedi Task.task_name sopra) — unico consumatore oggi:
# GameScene._block_border_crossing, che tratta una gamba bloccata al bordo come conclusa SOLO per
# queste task (nessun'altra Task cambia comportamento sul bordo bloccato). Copiato da
# TaskDefinition.is_idle_activity da TaskFactory.build_task, stesso schema di is_suspendable
# sopra. PERSISTITO (TaskPersistenceService, stesso trattamento di interrupt_priority/
# is_suspendable sopra, non di allowed_age_bands): current_task viene sempre serializzato
# indipendentemente da is_suspendable (quel campo decide solo se va in CODA, non se viene
# salvato) — un individuo può quindi salvare a metà una Wander/Play/Leisure Rest, e un
# attraversamento di bordo può scattare in QUALUNQUE momento futuro della sessione ricaricata,
# non solo al momento di assign_task().
var is_idle_activity: bool = false


func _init(p_steps: Array[Action] = []) -> void:
	id = _next_id
	_next_id += 1
	steps = p_steps
	step_stamina_cost.resize(steps.size())
	step_stamina_cost.fill(0.0)
	step_days_elapsed.resize(steps.size())
	step_days_elapsed.fill(0.0)
	step_happiness_cost.resize(steps.size())
	step_happiness_cost.fill(0.0)
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

	var new_happiness_costs: Array[float] = []
	new_happiness_costs.resize(added_count)
	new_happiness_costs.fill(0.0)
	step_happiness_cost.append_array(new_happiness_costs)

	var new_descriptions: Array[String] = []
	new_descriptions.resize(added_count)
	new_descriptions.fill("")
	step_descriptions.append_array(new_descriptions)

	# step_appended (2026-09-10) — DOPO che tutti gli array paralleli sopra sono già coerenti con
	# `steps` (un listener che reagisse leggendo task.steps/step_stamina_cost/ecc. dentro il proprio
	# callback trova quindi sempre uno stato interno già allineato, mai a metà aggiornamento). Un
	# emit per step, nello stesso ordine di new_steps — vedi il commento sul signal per il perché.
	for appended_action in new_steps:
		step_appended.emit(appended_action)


# Inserisce un nuovo step ALL'INDICE current_step_index, non in fondo (2026-09-13, richiesta
# utente — "Walk di ritorno alla ripresa" per una Task sospesa in task_queue il cui step era
# fermo su un'Action stazionaria: vedi HumanIndividualActionService.resolve_idle_individual) —
# DEVIAZIONE deliberata da append_steps() sopra (quella accoda in FONDO, pensata per step
# dinamici di una Task ancora IN CORSO, es. il re-routing di UnloadAction): qui invece un nuovo
# step deve diventare il PROSSIMO da eseguire, con lo step originariamente attivo (quello per cui
# current_step_index puntava già) spostato di una posizione, raggiunto naturalmente al
# completamento di questo nuovo step. Array.insert(idx, v) sposta da sé tutto ciò che sta a idx e
# oltre di una posizione a destra — current_step_index NON va incrementato qui: il suo valore
# resta corretto per costruzione, ora punta al nuovo step appena inserito invece che al vecchio
# (che si è spostato a current_step_index + 1).
#
# Stessi 4 array paralleli di append_steps() sopra, stesso principio (nessun costo/progresso già
# maturato da preservare per un elemento che non esisteva fino a un attimo fa) — un solo elemento
# ciascuno stavolta (append_steps ne accoda N in blocco, qui sempre esattamente 1), quindi niente
# resize()/fill() su array temporanei: un `insert()` diretto per array basta.
func insert_step_before_current(new_action: Action, description: String = "") -> void:
	steps.insert(current_step_index, new_action)
	step_stamina_cost.insert(current_step_index, 0.0)
	step_days_elapsed.insert(current_step_index, 0.0)
	step_happiness_cost.insert(current_step_index, 0.0)
	step_descriptions.insert(current_step_index, description)
	# step_appended (2026-09-10, vedi il commento sul signal in testa al file) — STESSO segnale di
	# append_steps(), stesso principio "un emit per step aggiunto a runtime": un listener non deve
	# distinguere se il nuovo step è arrivato in fondo o nel mezzo, solo che ne è arrivato uno.
	step_appended.emit(new_action)


# Inserisce `new_actions` subito DOPO lo step corrente, nell'ordine dato (2026-09-26, richiesta utente —
# riavvicinamento della caccia: gli step aggiunti devono venire prima di quelli già in coda, non in fondo
# come con append_steps). Stessi array paralleli e stesso segnale step_appended di insert_step_before_
# current/append_steps. `descriptions`: chiavi tr() per gli step, "" se mancanti.
func insert_steps_after_current(new_actions: Array[Action], descriptions: Array[String] = []) -> void:
	var insert_index := current_step_index + 1
	for i in range(new_actions.size()):
		var index := insert_index + i
		steps.insert(index, new_actions[i])
		step_stamina_cost.insert(index, 0.0)
		step_days_elapsed.insert(index, 0.0)
		step_happiness_cost.insert(index, 0.0)
		step_descriptions.insert(index, descriptions[i] if i < descriptions.size() else "")
		step_appended.emit(new_actions[i])


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


# Ribasa di `offset` il target POSIZIONALE (Action.target, quando è un Vector2 — vedi Action.gd:
# solo WalkAction/RunAction lo valorizzano così, ogni altra Action lo lascia null e tiene le
# proprie posizioni altrove, es. target_building, che si ri-derivano da sole da individual.
# home_macro_coords appena aggiornato) di OGNI step NON ANCORA completato, incluso quello attivo
# (da current_step_index in poi) — 2026-09-16, richiesta utente, fix bordo macrocella per le task
# perditempo (CAUSA A). PRIMA di questo fix, GameScene._attempt_macro_cell_transition ribasava
# SOLO lo step ATTIVO: una Task multi-Walk che risolve TUTTI i propri target assoluti in un colpo
# solo all'assegnazione (Wander/Play/Leisure Rest, ma anche una qualunque Task futura con lo
# stesso schema) lasciava le gambe FUTURE nel vecchio sistema di riferimento — quando una di
# quelle diventava attiva, puntava a un target sbagliato rispetto alla macrocella corrente,
# potendo generare un nuovo attraversamento in una direzione sbagliata. Chiamata sia sulla
# current_task sia su ogni Task sospesa in task_queue dello stesso individuo (vedi
# _attempt_macro_cell_transition), perché una Task in coda può restare sospesa per giorni mentre
# l'individuo (impegnato in un'altra Task, es. Wander) attraversa bordi che la sua futura ripresa
# non ha mai visto. Ritorna quanti step sono stati ribasati, solo per il log del chiamante
# ([BORDER]) — nessuna logica di simulazione lo consulta.
func rebase_positional_targets(offset: Vector2) -> int:
	var rebased := 0
	for i in range(current_step_index, steps.size()):
		var step := steps[i]
		if step.target is Vector2:
			step.target += offset
			rebased += 1
	return rebased


# Accumula il costo di QUESTO istante nello step attualmente attivo (2026-09-07, richiesta utente)
# — chiamata da HumanIndividualActionService.apply_action subito dopo get_stamina_delta/get_
# happiness_delta, con gli stessi valori già sommati a individual.current_stamina/current_happiness
# e lo stesso `delta` (giorni di gioco) ricevuto quel frame. No-op se l'indice è fuori range (Task
# già conclusa) — non dovrebbe succedere nell'ordine in cui apply_action la chiama oggi, ma resta
# una guardia difensiva coerente con get_current_action sopra.
#
# happiness_delta (2026-09-13, richiesta utente) — TERZO parametro, stesso schema esatto di
# stamina_delta: un solo punto di scrittura per tutti e tre gli array paralleli, mai una seconda
# funzione dedicata solo a happiness (eviterebbe il rischio dei due accumulatori che si
# disallineano nel tempo, stesso principio già dichiarato per birth_results in
# HumanBirthIndividualService).
func record_step_cost(stamina_delta: float, happiness_delta: float, days_delta: float) -> void:
	if current_step_index < 0 or current_step_index >= steps.size():
		return
	step_stamina_cost[current_step_index] += stamina_delta
	step_happiness_cost[current_step_index] += happiness_delta
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
	var total_happiness := 0.0
	var total_days := 0.0
	for i in range(steps.size()):
		var step_name: String = steps[i].get_script().get_global_name()
		# happiness aggiunta accanto a stamina sulla STESSA riga (2026-09-13, richiesta utente) —
		# stesso formato "%.1f" già in uso per stamina/giorni, nessun nuovo stile.
		print("  - %s: %.1f stamina, %.1f happiness (%.4f giorni)" % [
			step_name, step_stamina_cost[i], step_happiness_cost[i], step_days_elapsed[i]
		])
		total_stamina += step_stamina_cost[i]
		total_happiness += step_happiness_cost[i]
		total_days += step_days_elapsed[i]
	print("  TOTALE: %.1f stamina, %.1f happiness, %.4f giorni" % [total_stamina, total_happiness, total_days])


# Testo per l'info panel individuo — "che Task è" (RIVISTO 2026-09-16, richiesta utente: mostrava
# prima "Nome Task (descrizione dello step attivo)", es. "Trasportare materiale (Prelevando)" — la
# parte tra parentesi cambiava ad ogni step, ed essendo lo stesso identico testo per QUALUNQUE
# risorsa trasportata (nessun riferimento a QUALE risorsa), due Task diverse (es. due Transport di
# risorse diverse) risultavano indistinguibili a colpo d'occhio, e "quale action sta facendo ORA"
# aggiungeva rumore che il player non aveva chiesto di vedere — richiesta esplicita: mostrare SOLO
# il tipo di Task, MAI l'Action/step attivo. haul_resource/transport sono un'eccezione mirata: per
# loro l'informazione utile non è lo step ma QUALE risorsa stanno maneggiando.
#
# Letta dall'ISTANZA dell'Action dentro `steps` (PickUpAction.resource_name/RetrieveAction.
# resource_name), MAI da `context` — TaskFactory.build_task ripulisce da context ogni chiave
# consumata per costruire gli step (vedi task_factory.gd, "consumed_context_keys": "i valori usati
# SOLO per costruire gli step non restano appesi a task.context per tutta la vita della Task"),
# quindi "resource_name"/"transport_resource_name" non esistono più in context subito dopo la
# costruzione — solo l'Action stessa, che vive per tutta la vita della Task dentro `steps`, porta
# ancora il dato. IconRegistry.get_resource_display_name (stessa funzione già usata da
# BuildingInfoPanel per lo stesso scopo) risolve il nome leggibile ("Rametti", non "stick").
#
# Nessuna dipendenza da step_descriptions/current_action/current_step_index qui sotto: funziona
# identica sia per la Task ATTIVA (current_task) sia per una Task SOSPESA in coda (task_queue) —
# gli step restano gli stessi oggetti in entrambi i casi, un solo punto invece di due formule
# diverse (vedi GameScene._update_individual_panel_content, unico chiamante).
func get_activity_description() -> String:
	var base_text: String = tr(task_name) if task_name != "" else tr("task_debug_panel_unnamed_task")
	var resource_name: String = ""
	match task_name:
		"task_haul_resource_name":
			for step in steps:
				if step is PickUpAction:
					# Solo con criterio per NOME la risorsa e' una sola (zaino multi-risorsa, 2026-09-20): con
					# categoria/tutto non ce n'e' una da mostrare, resta il solo nome della Task.
					if (step as PickUpAction).criterion_kind == PickUpAction.CriterionKind.NAME:
						resource_name = (step as PickUpAction).resource_name
					break
		"task_transport_name":
			for step in steps:
				if step is RetrieveAction:
					resource_name = (step as RetrieveAction).resource_name
					break
		# Costruzione (2026-09-24, richiesta utente): "Costruzione (Tenda di rami)", stesso stile della
		# raccolta. Edificio letto dal primo step che ha un target_building (SetupSite/Clear/Build),
		# nome tradotto da BuildingRules.building_name. Nessun edificio risolvibile = solo il nome
		# della Task.
		"task_build_name":
			for step in steps:
				if "target_building" in step and step.target_building != null:
					var building: Building = step.target_building
					var building_display_name: String = tr(building.rules.building_name) if building.rules != null else building.building_type_name
					return "%s (%s)" % [base_text, building_display_name]
			return base_text
		# Produzione (2026-09-23, richiesta utente): "Produzione: Corda di fibre". Letta da context
		# ["production_resource_name"], chiave scritta da GameScene._assign_produce_task e NON
		# consumata da TaskFactory (a differenza di "produce_resource_name", che costruisce lo step e
		# viene quindi ripulita) — resta in context e viene salvata con esso. Assente (save precedente)
		# = solo il nome della Task.
		"task_produce_name":
			var produced_name: String = String(context.get("production_resource_name", ""))
			if produced_name == "":
				return base_text
			# Quantità ordinata (2026-09-24): "Corda di fibre ×3", solo se > 1; assente nei save precedenti.
			var produced_display_name := IconRegistry.get_resource_display_name(produced_name)
			var produced_quantity: int = int(context.get("production_quantity", 1))
			if produced_quantity > 1:
				produced_display_name = "%s ×%d" % [produced_display_name, produced_quantity]
			return tr("task_produce_activity").format({"resource": produced_display_name})
		# Prendi/riponi attrezzo dal pannello individuo (2026-09-25, richiesta utente): "Prendi
		# attrezzo (Coltello di pietra)". Nome da context["tool_resource_name"], scritto da GameScene.
		"task_equip_tool_name", "task_store_tool_name":
			resource_name = String(context.get("tool_resource_name", ""))
		# Caccia (2026-09-26, caccia step 2): "Caccia: Coniglio". Specie da context["hunt_activity_species"],
		# scritta da GameScene._try_assign_hunt_command_on_right_click e non consumata da TaskFactory;
		# nome tradotto con la stessa chiave del pannello animale (animal_species_<specie>).
		"task_hunt_name":
			var prey_species: String = String(context.get("hunt_activity_species", ""))
			if prey_species == "":
				return base_text
			return tr("task_hunt_activity").format({"species": tr("animal_species_" + prey_species)})
		_:
			return base_text
	if resource_name == "":
		return base_text
	# "Prendi tutti i prodotti" (2026-09-24): nessun nome di risorsa singolo da mostrare.
	if resource_name == RetrieveAction.ALL_PRODUCTS:
		return "%s (%s)" % [base_text, tr("transport_all_products_activity")]
	return "%s (%s)" % [base_text, IconRegistry.get_resource_display_name(resource_name)]
