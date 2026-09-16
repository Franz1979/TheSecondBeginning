class_name TaskQueueService
extends RefCounted

# Coda personale di Task SOSPESE — service RefCounted stateless (2026-09-13, richiesta utente,
# refactoring di posizione in preparazione alla logica di interrupt/coda) — stesso identico
# principio "individuo come stato puro, la logica vive nei service" già seguito altrove nel
# progetto (HumanCalculator/HumanStaminaIndividualService/WarehouseSelectionService): il dato
# (HumanIndividual.task_queue, un Array[Task]) resta sull'individuo, solo le due funzioni
# meccaniche che lo manipolano si spostano qui.
#
# Semantica LIFO (nessun timestamp: non serve per una coda LIFO semplice) — push in fondo, pop
# dalla fine: l'ultima Task sospesa è la prima a riprendere.

# Tetto massimo alla coda (2026-09-13, richiesta utente) — una coda illimitata permetterebbe a un
# individuo di accumulare Task sospese all'infinito (ogni comando manuale su un lavoro già
# sospendibile ne aggiunge una), la maggior parte destinate a non essere mai riprese in pratica.
const MAX_QUEUE_SIZE: int = 3


# Push in fondo — se la coda è già al tetto MAX_QUEUE_SIZE, la Task PIÙ VECCHIA (indice 0, la più
# lontana/dimenticata — non l'ultima appena entrata) viene rimossa PRIMA di aggiungere la nuova,
# per farle spazio (2026-09-13, richiesta utente).
#
# PLACEHOLDER TEMPORANEO (2026-09-13, richiesta utente) — l'elemento rimosso per limite di coda
# oggi sparisce semplicemente (stesso trattamento di un vero abbandono: discard_carried_resource()
# se l'individuo aveva inventario, log dedicato sotto). Quando esisterà il pool di villaggio (Step
# 5), questo elemento andrà invece depositato nel contenitore condiviso (raccoglibile da chiunque
# sia libero, incluso lo stesso individuo in futuro) invece di sparire per sempre — NON
# implementato qui, solo questo commento per chi tornerà su questo codice.
#
# discard_carried_resource() sull'INDIVIDUO (non un campo per-Task: l'inventario vive su
# HumanIndividual, un solo slot condiviso indipendentemente da quale Task in coda l'abbia
# eventualmente riempito) — no-op silenzioso se lo zaino è già vuoto, stesso guard interno già
# esistente in quella funzione.
static func push_suspended_task(individual: HumanIndividual, task: Task) -> void:
	# ZOMBIE GUARD (2026-09-16, richiesta utente, fix "task zombie") — ultima linea di difesa,
	# indipendente dal chiamante: una task già conclusa (current_step_index >= steps.size()) non
	# deve MAI entrare in coda, qualunque sia il percorso che ha portato fin qui — difesa in
	# profondità rispetto alle guardie già in HumanIndividual.assign_task (che oggi non dovrebbero
	# più chiamare questa funzione con una task finita, ma un futuro secondo chiamante potrebbe).
	# Log gated dalla categoria SAFETY (2026-09-16, richiesta utente — riordino log di debug: prima
	# stampava sempre, indipendentemente da DebugLogging.ENABLED; SHOW_SAFETY_LOGS default true
	# mantiene la stessa visibilità a impostazioni invariate), stesso motivo del guard gemello in
	# assign_task/resolve_idle_individual: segnala un'anomalia, non un evento di routine.
	if task.is_finished():
		if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
			print("[ZOMBIE GUARD] Individuo #%d %s: tentativo di sospendere in coda la task '%s' (step %d/%d) già conclusa — rifiutata, TaskQueueService.push_suspended_task." % [
				individual.id, individual.name, task.task_name, task.current_step_index, task.steps.size()
			])
		return
	if individual.task_queue.size() >= MAX_QUEUE_SIZE:
		var discarded_task: Task = individual.task_queue.pop_front()
		individual.discard_carried_resource()
		if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
			print("[QUEUE OVERFLOW] Individuo #%d %s: coda già a %d/%d — Task '%s' (la più vecchia) scartata per fare spazio a '%s'." % [
				individual.id, individual.name, MAX_QUEUE_SIZE, MAX_QUEUE_SIZE, discarded_task.task_name, task.task_name
			])
	individual.task_queue.append(task)


static func pop_suspended_task(individual: HumanIndividual) -> Task:
	if individual.task_queue.is_empty():
		return null
	return individual.task_queue.pop_back()


# ZOMBIE GUARD — recupero da salvataggio (2026-09-16, richiesta utente, fix "task zombie") —
# chiamata da GameScene._ready() PRIMA di valutare se un individuo caricato è libero: un
# salvataggio fatto PRIMA di questo fix può ancora contenere in coda task già concluse (prodotte
# dal bug ora corretto alla radice in HumanIndividualActionService._handle_task_completion_need_
# and_queue). Rimuove ogni voce già conclusa, PRESERVANDO l'ordine relativo delle altre (mai un
# semplice filter che stravolgerebbe il LIFO) — ritorna quante ne ha rimosse, solo per il log/i
# test, nessuna logica di simulazione lo consulta. Log gated dalla categoria SAFETY (2026-09-16,
# richiesta utente — riordino log di debug: prima stampava sempre indipendentemente da
# DebugLogging.ENABLED, stesso motivo del guard gemello in push_suspended_task).
static func purge_finished_tasks(individual: HumanIndividual) -> int:
	var kept: Array[Task] = []
	var removed := 0
	for queued_task in individual.task_queue:
		if queued_task.is_finished():
			removed += 1
			if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
				print("[ZOMBIE GUARD] Individuo #%d %s: task '%s' (step %d/%d) rimossa dalla coda perché già conclusa — TaskQueueService.purge_finished_tasks." % [
					individual.id, individual.name, queued_task.task_name, queued_task.current_step_index, queued_task.steps.size()
				])
		else:
			kept.append(queued_task)
	individual.task_queue = kept
	return removed
