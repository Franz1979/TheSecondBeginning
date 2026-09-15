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
	if individual.task_queue.size() >= MAX_QUEUE_SIZE:
		var discarded_task: Task = individual.task_queue.pop_front()
		individual.discard_carried_resource()
		if DebugLogging.ENABLED:
			print("[QUEUE OVERFLOW] Individuo #%d %s: coda già a %d/%d — Task '%s' (la più vecchia) scartata per fare spazio a '%s'." % [
				individual.id, individual.name, MAX_QUEUE_SIZE, MAX_QUEUE_SIZE, discarded_task.task_name, task.task_name
			])
	individual.task_queue.append(task)


static func pop_suspended_task(individual: HumanIndividual) -> Task:
	if individual.task_queue.is_empty():
		return null
	return individual.task_queue.pop_back()
