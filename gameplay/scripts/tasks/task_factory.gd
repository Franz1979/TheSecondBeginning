class_name TaskFactory

# Fabbrica statica (2026-09-07, richiesta utente, riorganizzazione Action/Task) — nessuno stato,
# un solo metodo statico: non serve nemmeno un'istanza (a differenza dei *Service stateless del
# progetto, che restano RefCounted con .new() per uniformità con gli altri — qui non c'è nulla da
# uniformare, è una pura funzione). Costruisce una Task RUNTIME (Task.gd) a partire da una
# TaskDefinition ASTRATTA (task_definition.gd) + un Dictionary di contesto concreto: per ogni
# TaskStepDefinition (task_step_definition.gd) istanzia l'Action concreta giusta secondo
# action_type, passandole il target letto da context tramite context_key.

# Supporta WALK e REST in questo passo (le uniche due Action esistenti, vedi TaskTypes.ActionType)
# — REST non richiede una chiave di contesto (RestAction non ha un target, vedi RestAction.gd),
# quindi context_key viene semplicemente ignorata per quello step. Aggiungere qui un nuovo case
# per ogni futuro ActionType quando arriverà la sua Action concreta (HARVEST/PICK_UP/UNLOAD/
# BUILD, ...) — non prima, per non gestire azioni che non esistono ancora.
static func build_task(definition: TaskDefinition, context: Dictionary) -> Task:
	var steps: Array[Action] = []
	# step_descriptions (2026-09-07) — array PARALLELO a steps (stesso indice), copiato da
	# TaskStepDefinition.step_description: vedi Task.get_activity_description, il consumatore.
	# Un "" per ogni step SALTATO (context_key mancante/ActionType non supportato, vedi i due
	# push_error sotto) manterrebbe l'allineamento indice-per-indice con `steps` rotto altrimenti —
	# ma quei due casi sono già errori di configurazione segnalati a parte, non un caso normale da
	# gestire con eleganza qui.
	var step_descriptions: Array[String] = []
	for step_definition: TaskStepDefinition in definition.steps:
		match step_definition.action_type:
			TaskTypes.ActionType.WALK:
				if not context.has(step_definition.context_key):
					push_error("TaskFactory.build_task: chiave di contesto '%s' mancante per TaskDefinition '%s'." % [
						step_definition.context_key, definition.task_name
					])
					continue
				steps.append(WalkAction.new(context[step_definition.context_key]))
				step_descriptions.append(step_definition.step_description)
			TaskTypes.ActionType.REST:
				steps.append(RestAction.new())
				step_descriptions.append(step_definition.step_description)
			_:
				push_error("TaskFactory.build_task: ActionType %d non supportato (TaskDefinition '%s')." % [
					step_definition.action_type, definition.task_name
				])
	var task := Task.new(steps)
	task.context = context
	# task_name/step_descriptions (2026-09-07) — copiati da TaskDefinition, mai lasciati vuoti per
	# una Task nata da una vera ricetta: vedi Task.print_cost_summary/get_activity_description, i
	# consumatori.
	task.task_name = definition.task_name
	task.step_descriptions = step_descriptions
	return task
