class_name TaskFactory

# Fabbrica statica (2026-09-07, richiesta utente, riorganizzazione Action/Task) — nessuno stato,
# un solo metodo statico: non serve nemmeno un'istanza (a differenza dei *Service stateless del
# progetto, che restano RefCounted con .new() per uniformità con gli altri — qui non c'è nulla da
# uniformare, è una pura funzione). Costruisce una Task RUNTIME (Task.gd) a partire da una
# TaskDefinition ASTRATTA (task_definition.gd) + un Dictionary di contesto concreto: per ogni
# TaskStepDefinition (task_step_definition.gd) istanzia l'Action concreta giusta secondo
# action_type, passandole gli argomenti letti da context tramite context_keys, nell'ordine
# dichiarato lì (vedi task_step_definition.gd).

# Supporta WALK, REST, THINK, PICKUP, SETUP_SITE, CLEAR, BUILD, LOOK_AROUND, RETRIEVE, UNLOAD in
# questo passo (2026-09-10, richiesta utente — estensione per haul_resource: aggiunti THINK/PICKUP
# allo schema WALK/REST preesistente, poi SETUP_SITE per la prima porzione della Build Task, poi
# CLEAR (2026-09-11) per il terzo step, poi BUILD (2026-09-11, stesso giorno) per il quarto e
# ultimo, poi RETRIEVE/UNLOAD (2026-09-12, Transport Task) — stesso principio di dispatch
# eterogeneo per-tipo già usato da TaskPersistenceService._build_step, sorgente diversa — lì un
# Dictionary a chiavi fisse per tipo, qui context_keys+context). haul_resource costruita da questa
# factory produce solo i primi due step [Walk, PickUp] — il resto della catena (ricerca magazzino/
# Unload/cammina-via) continua a crescere a runtime via Task.append_steps, invariato (vedi
# HumanIndividualActionService); build.tres invece produce oggi la Build Task COMPLETA [Walk,
# SetupSite, Clear, Build], transport.tres la Transport Task COMPLETA [Walk, Retrieve, Walk,
# Unload] — nessuno step residuo fuori scope per queste due Task.
#
# UNLOAD GAP CHIUSO (2026-09-12, richiesta utente, Transport Task) — PRIMA di questo passo il case
# UNLOAD non esisteva affatto qui ("UNLOAD resta FUORI SCOPE", commento storico): ogni UnloadAction
# nasceva SOLO a runtime (accodata dinamicamente via Task.append_steps, vedi
# HumanIndividualActionService._handle_pending_warehouse_search/_handle_pending_thought_target_
# search) o costruita a mano nei debug hook/comandi diretti di GameScene, mai tramite una vera
# TaskDefinition. Il case sotto fissa SEMPRE deposit_kind a RESOURCE (mai letto da un secondo
# context_keys): l'unico caso in cui una TaskDefinition.tres ha senso di dichiarare esplicitamente
# uno step UNLOAD è il deposito FISICO di una risorsa già in spalla (es. Transport Task) — il ramo
# PENSIERO (THOUGHT) resta sempre e solo costruito dinamicamente a runtime, nessuna TaskDefinition
# ne ha bisogno oggi (daydreaming.tres si ferma a [Walk, Think], il resto cresce a runtime).
#
# REST non richiede un target (RestAction non ne ha uno, vedi RestAction.gd)
# ma accetta un rest_multiplier OPZIONALE da context_keys[0] (2026-09-12, richiesta utente — Rest
# Task esplicita, rest.tres: [Walk, Rest con moltiplicatore] — vedi il case REST sotto). Aggiungere qui un nuovo case
# per ogni futuro ActionType quando arriverà la sua Action concreta — non prima, per non gestire
# azioni che non esistono ancora.
static func build_task(definition: TaskDefinition, context: Dictionary) -> Task:
	var steps: Array[Action] = []
	# step_descriptions (2026-09-07) — array PARALLELO a steps (stesso indice), copiato da
	# TaskStepDefinition.step_description: vedi Task.get_activity_description, il consumatore.
	# Un "" per ogni step SALTATO (context_keys insufficienti/ActionType non supportato, vedi i
	# push_error sotto) manterrebbe l'allineamento indice-per-indice con `steps` rotto altrimenti —
	# ma quei casi sono già errori di configurazione segnalati a parte, non un caso normale da
	# gestire con eleganza qui.
	var step_descriptions: Array[String] = []
	# consumed_context_keys (2026-09-10, richiesta utente — pulizia automatica del context, prima
	# delegata al chiamante via un context.erase() manuale in GameScene._assign_pickup_task) —
	# accumula, per OGNI TaskStepDefinition di questa definition (costruita con successo o scartata
	# per errore di configurazione: vedi sotto), le chiavi dichiarate nel suo context_keys. A fine
	# funzione queste chiavi vengono rimosse da `context` PRIMA di assegnarlo a task.context, così i
	# valori usati SOLO per costruire gli step (es. MacroCellState, Vector2/Vector2i — mai JSON-safe,
	# vedi TaskPersistenceService per la stessa nota su Action.target) non restano appesi a
	# task.context per tutta la vita della Task, a rischio di corrompere un salvataggio a metà Task.
	# Include ANCHE le chiavi di uno step scartato (context mancante/ActionType non supportato): quelle
	# chiavi non sono comunque mai finite in `context` con successo in quel caso (altrimenti lo step
	# non sarebbe stato scartato), quindi un erase() su una chiave assente più sotto è un no-op
	# innocuo — più semplice che distinguere "step riuscito" da "step scartato" qui.
	#
	# Nessuna whitelist/eccezione oggi: nessuna chiave nota serve ad altro scopo nel context oltre a
	# costruire l'Action che la dichiara in context_keys (vedi il report della sessione che ha
	# introdotto questo meccanismo per la verifica fatta). Se in futuro un'Action dovesse rileggere
	# una propria chiave di costruzione anche DOPO essere stata istanziata (via il canale generico
	# Action.get_stamina_delta/is_complete/activate context, vedi Action.gd), quella chiave andrebbe
	# esclusa qui esplicitamente — nessun meccanismo del genere esiste ancora, non costruito in
	# anticipo.
	var consumed_context_keys: Array[String] = []
	for step_definition: TaskStepDefinition in definition.steps:
		consumed_context_keys.append_array(step_definition.context_keys)
		match step_definition.action_type:
			TaskTypes.ActionType.WALK:
				if step_definition.context_keys.is_empty() or not context.has(step_definition.context_keys[0]):
					push_error("TaskFactory.build_task: context_keys[0] mancante/non risolvibile per step WALK di TaskDefinition '%s'." % definition.task_name)
					continue
				# LOG DEBUG TEMPORANEO (2026-09-10, richiesta utente — indagine bug "il pipottino
				# cammina sempre verso lo stesso punto in basso a destra" su build.tres) — DA
				# RIMUOVERE una volta chiuso il bug, non è un log permanente del progetto.
				if DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
					print("[TASKFACTORY DEBUG] step WALK di '%s': context_keys[0]='%s' -> target_position=%s" % [
						definition.task_name, step_definition.context_keys[0], str(context[step_definition.context_keys[0]])
					])
				steps.append(WalkAction.new(context[step_definition.context_keys[0]]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.REST:
				# rest_multiplier/max_duration_days/ignore_stamina_cap TUTTI OPZIONALI (2026-09-12,
				# esteso 2026-09-16, richiesta utente — Rest Task esplicita: Walk verso target_position
				# + Rest con questi tre parametri) — a differenza di WALK/THINK sopra (context_keys[0]
				# obbligatorio), qui un context_keys vuoto/non risolvibile per ciascuna posizione
				# ripiega sul default di RestAction._init (1.0/-1.0/false), comportamento INVARIATO per
				# qualunque TaskDefinition che dichiari REST senza queste chiavi. Vedi step_rest.tres
				# (rest_multiplier, max_duration_days, ignore_stamina_cap in quest'ordine) per l'unico
				# consumatore oggi, riusato sia da rest.tres sia da leisure_rest.tres con valori diversi
				# di contesto.
				var rest_multiplier: float = 1.0
				if step_definition.context_keys.size() > 0 and context.has(step_definition.context_keys[0]):
					rest_multiplier = float(context[step_definition.context_keys[0]])
				var rest_max_duration_days: float = -1.0
				if step_definition.context_keys.size() > 1 and context.has(step_definition.context_keys[1]):
					rest_max_duration_days = float(context[step_definition.context_keys[1]])
				var rest_ignore_stamina_cap: bool = false
				if step_definition.context_keys.size() > 2 and context.has(step_definition.context_keys[2]):
					rest_ignore_stamina_cap = bool(context[step_definition.context_keys[2]])
				steps.append(RestAction.new(rest_multiplier, rest_max_duration_days, rest_ignore_stamina_cap))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.THINK:
				# 1 argomento scalare (duration: float) — stesso schema di WALK sopra, solo il
				# tipo del target cambia (Vector2 -> float): ThinkAction._init(p_duration: float).
				if step_definition.context_keys.is_empty() or not context.has(step_definition.context_keys[0]):
					push_error("TaskFactory.build_task: context_keys[0] mancante/non risolvibile per step THINK di TaskDefinition '%s'." % definition.task_name)
					continue
				steps.append(ThinkAction.new(context[step_definition.context_keys[0]]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.PICKUP:
				# 3 argomenti eterogenei, nell'ordine atteso da PickUpAction._init(target_position,
				# macro_state, resource_name) — stesso ordine con cui context_keys va compilato in
				# una TaskStepDefinition PICKUP (vedi step_pickup_from_position.tres — nome generico,
				# riusabile da qualunque TaskDefinition, non solo haul_resource: vedi
				# gameplay/scripts/tasks/definitions/haul_resource.tres per l'unico consumatore oggi).
				if step_definition.context_keys.size() < 3:
					push_error("TaskFactory.build_task: context_keys insufficienti (servono 3: target_position, macro_state, resource_name) per step PICKUP di TaskDefinition '%s'." % definition.task_name)
					continue
				var target_position_key: String = step_definition.context_keys[0]
				var macro_state_key: String = step_definition.context_keys[1]
				var resource_name_key: String = step_definition.context_keys[2]
				if not context.has(target_position_key) or not context.has(macro_state_key) or not context.has(resource_name_key):
					push_error("TaskFactory.build_task: una o più chiavi di contesto mancanti ('%s'/'%s'/'%s') per step PICKUP di TaskDefinition '%s'." % [
						target_position_key, macro_state_key, resource_name_key, definition.task_name
					])
					continue
				steps.append(PickUpAction.new(context[target_position_key], context[macro_state_key], context[resource_name_key]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.SETUP_SITE:
				# 1 argomento (target_building: Building) — stesso schema di WALK/THINK sopra, solo il
				# tipo del target cambia (Building invece di Vector2/float): SetupSiteAction._init(
				# target_building). Vedi step_setup_site.tres/gameplay/scripts/tasks/definitions/build.
				# tres per l'unico consumatore oggi.
				if step_definition.context_keys.is_empty() or not context.has(step_definition.context_keys[0]):
					push_error("TaskFactory.build_task: context_keys[0] mancante/non risolvibile per step SETUP_SITE di TaskDefinition '%s'." % definition.task_name)
					continue
				steps.append(SetupSiteAction.new(context[step_definition.context_keys[0]]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.CLEAR:
				# 3 argomenti eterogenei, nell'ordine atteso da ClearAction._init(target_building,
				# macro_state, is_currently_grass) — stesso schema di PICKUP sopra. Vedi
				# step_clear_site.tres/gameplay/scripts/tasks/definitions/build.tres per l'unico
				# consumatore oggi (2026-09-11, terzo step della Build Task).
				if step_definition.context_keys.size() < 3:
					push_error("TaskFactory.build_task: context_keys insufficienti (servono 3: target_building, macro_state, is_currently_grass) per step CLEAR di TaskDefinition '%s'." % definition.task_name)
					continue
				var clear_building_key: String = step_definition.context_keys[0]
				var clear_macro_state_key: String = step_definition.context_keys[1]
				var clear_is_grass_key: String = step_definition.context_keys[2]
				if not context.has(clear_building_key) or not context.has(clear_macro_state_key) or not context.has(clear_is_grass_key):
					push_error("TaskFactory.build_task: una o più chiavi di contesto mancanti ('%s'/'%s'/'%s') per step CLEAR di TaskDefinition '%s'." % [
						clear_building_key, clear_macro_state_key, clear_is_grass_key, definition.task_name
					])
					continue
				steps.append(ClearAction.new(context[clear_building_key], context[clear_macro_state_key], context[clear_is_grass_key]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.BUILD:
				# 1 argomento (target_building: Building) — stesso schema di SETUP_SITE sopra.
				# skill_multiplier/tool_multiplier NON letti da context: restano al default 1.0 di
				# BuildAction._init (nessun sistema skill/tool esiste ancora da cui pescare un valore
				# diverso, vedi BuildAction.gd) — nessuna TaskStepDefinition dichiara quelle chiavi
				# oggi. Vedi step_build.tres/gameplay/scripts/tasks/definitions/build.tres per l'unico
				# consumatore oggi (2026-09-11, quarto e ultimo step della Build Task).
				if step_definition.context_keys.is_empty() or not context.has(step_definition.context_keys[0]):
					push_error("TaskFactory.build_task: context_keys[0] mancante/non risolvibile per step BUILD di TaskDefinition '%s'." % definition.task_name)
					continue
				steps.append(BuildAction.new(context[step_definition.context_keys[0]]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.LOOK_AROUND:
				# Nessun argomento — LookAroundAction._init non prende parametri (durata/drain fissi,
				# nessun target). Vedi step_look_around.tres/wander.tres per l'unico consumatore oggi
				# (2026-09-12, richiesta utente, Wander Task).
				steps.append(LookAroundAction.new())
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.RETRIEVE:
				# 3 argomenti eterogenei, nell'ordine atteso da RetrieveAction._init(target_building,
				# resource_name, quantity_requested) — stesso schema di PICKUP/CLEAR sopra. Nessuna
				# TaskDefinition la usa ancora oggi (2026-09-12, richiesta utente — solo l'Action e il
				# collegamento a TaskFactory/persistenza in questo giro, nessuna Task di trasporto
				# materiale completa ancora costruita).
				if step_definition.context_keys.size() < 3:
					push_error("TaskFactory.build_task: context_keys insufficienti (servono 3: target_building, resource_name, quantity_requested) per step RETRIEVE di TaskDefinition '%s'." % definition.task_name)
					continue
				var retrieve_building_key: String = step_definition.context_keys[0]
				var retrieve_resource_name_key: String = step_definition.context_keys[1]
				var retrieve_quantity_key: String = step_definition.context_keys[2]
				if not context.has(retrieve_building_key) or not context.has(retrieve_resource_name_key) or not context.has(retrieve_quantity_key):
					push_error("TaskFactory.build_task: una o più chiavi di contesto mancanti ('%s'/'%s'/'%s') per step RETRIEVE di TaskDefinition '%s'." % [
						retrieve_building_key, retrieve_resource_name_key, retrieve_quantity_key, definition.task_name
					])
					continue
				steps.append(RetrieveAction.new(
					context[retrieve_building_key], context[retrieve_resource_name_key], int(context[retrieve_quantity_key])
				))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.UNLOAD:
				# 1 argomento (target_building: Building) — stesso schema di SETUP_SITE/BUILD sopra.
				# deposit_kind SEMPRE RESOURCE (vedi nota in testa al file per il perché) — mai letto da
				# un secondo context_keys, UnloadAction.new(target_building, DepositKind.RESOURCE)
				# esplicito. Vedi step_unload_transport.tres/transport.tres per l'unico consumatore oggi.
				if step_definition.context_keys.is_empty() or not context.has(step_definition.context_keys[0]):
					push_error("TaskFactory.build_task: context_keys[0] mancante/non risolvibile per step UNLOAD di TaskDefinition '%s'." % definition.task_name)
					continue
				steps.append(UnloadAction.new(context[step_definition.context_keys[0]], UnloadAction.DepositKind.RESOURCE))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.RUN:
				# 1 argomento (target: Vector2) — stesso schema di WALK sopra, RunAction.new(target).
				# Nessuna TaskDefinition la usa ancora oggi (2026-09-13, richiesta utente — solo l'Action
				# e il collegamento a TaskFactory/persistenza in questo giro, in preparazione della
				# futura Task Play).
				if step_definition.context_keys.is_empty() or not context.has(step_definition.context_keys[0]):
					push_error("TaskFactory.build_task: context_keys[0] mancante/non risolvibile per step RUN di TaskDefinition '%s'." % definition.task_name)
					continue
				steps.append(RunAction.new(context[step_definition.context_keys[0]]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.JUMP:
				# Nessun argomento — JumpAction._init non prende parametri (durata/numero di salti
				# tirati a caso internamente, nessun target). Vedi JumpAction.gd. Nessuna TaskDefinition
				# la usa ancora oggi (2026-09-13, richiesta utente — stesso discorso di RUN sopra).
				steps.append(JumpAction.new())
				step_descriptions.append(step_definition.step_description)
			_:
				push_error("TaskFactory.build_task: ActionType %d non supportato (TaskDefinition '%s')." % [
					step_definition.action_type, definition.task_name
				])
	# Pulizia STRUTTURALE (2026-09-10) — vedi il commento su consumed_context_keys sopra: rimuove da
	# `context` (lo STESSO Dictionary che diventa task.context subito sotto, per riferimento — non
	# una copia) tutte le chiavi appena raccolte, PRIMA dell'assegnazione. `context.erase(key)` su
	# una chiave già assente non solleva errori (ritorna semplicemente false), quindi duplicati in
	# consumed_context_keys (es. due step diversi che dichiarassero la stessa chiave) sono innocui.
	for key in consumed_context_keys:
		context.erase(key)
	var task := Task.new(steps)
	task.context = context
	# task_name/step_descriptions (2026-09-07) — copiati da TaskDefinition, mai lasciati vuoti per
	# una Task nata da una vera ricetta: vedi Task.print_cost_summary/get_activity_description, i
	# consumatori.
	task.task_name = definition.task_name
	task.step_descriptions = step_descriptions
	# allowed_age_bands (2026-09-13, richiesta utente, Play Task CHILD-only) — copiato da
	# TaskDefinition, stesso schema di task_name/step_descriptions sopra. Vedi Task.allowed_
	# age_bands/HumanIndividual.assign_task per il consumatore.
	task.allowed_age_bands = definition.allowed_age_bands
	# interrupt_priority/is_suspendable (2026-09-13, richiesta utente, in preparazione al sistema di
	# interrupt da stamina critica) — copiati da TaskDefinition, stesso schema di allowed_age_bands
	# sopra. Nessun collegamento a logica di interrupt ancora: solo il dato copiato.
	task.interrupt_priority = definition.interrupt_priority
	task.is_suspendable = definition.is_suspendable
	# is_idle_activity (2026-09-16, richiesta utente, fix bordo macrocella) — copiato da
	# TaskDefinition, stesso schema di interrupt_priority/is_suspendable sopra.
	task.is_idle_activity = definition.is_idle_activity
	return task
