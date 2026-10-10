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
# Zaino (2026-09-29, regola unica del carico — sostituisce lo scarto a terra del 2026-09-26): la task proprietaria
# del carico (get_cargo_owner) non viene mai espulsa, vedi il corpo sotto.
# `interrupted_by_need` (2026-10-10): la task in corso sospesa da un bisogno automatico (HumanIndividual.assign_task con
# is_interrupt_transition). Non si espelle niente: rientra in coda anche oltre MAX_QUEUE_SIZE (come i seguiti,
# push_follow_up_task), con una riga [QUEUE]. Gli ordini nuovi del giocatore restano con il tetto e l'espulsione.
static func push_suspended_task(individual: HumanIndividual, task: Task, interrupted_by_need: bool = false) -> void:
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
	# Caccia in zona sospesa durante l'inseguimento (2026-10-01): la preda si perde, alla ripresa si riparte dalla
	# pattuglia. Unico punto da cui passa ogni Task che va in coda.
	HuntZoneService.reset_to_patrol_on_suspend(task)
	if interrupted_by_need and individual.task_queue.size() >= MAX_QUEUE_SIZE:
		if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
			print("[QUEUE] Individuo #%d %s: '%s' interrotta da un bisogno rientra in coda oltre il limite (%d/%d), nessuna task espulsa." % [
				individual.id, individual.name, task.task_name, individual.task_queue.size() + 1, MAX_QUEUE_SIZE
			])
	elif individual.task_queue.size() >= MAX_QUEUE_SIZE:
		# Regola unica del carico (2026-09-29, CargoReturnService — prima veniva espulsa comunque la più vecchia, con lo
		# zaino a terra se era la proprietaria del carico): la proprietaria del carico non viene MAI espulsa, esce la
		# più vecchia tra le altre. Letta PRIMA di toccare la coda.
		var cargo_owner := get_cargo_owner(individual)
		var expel_index := -1
		for i in range(individual.task_queue.size()):
			if individual.task_queue[i] != cargo_owner:
				expel_index = i
				break
		if expel_index >= 0:
			var discarded_task: Task = individual.task_queue.pop_at(expel_index)
			if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
				print("[QUEUE OVERFLOW] Individuo #%d %s: coda già a %d/%d — Task '%s' (la più vecchia non proprietaria del carico) scartata per fare spazio a '%s'." % [
					individual.id, individual.name, MAX_QUEUE_SIZE, MAX_QUEUE_SIZE, discarded_task.task_name, task.task_name
				])
		else:
			# Ultima risorsa: in coda c'è solo la proprietaria del carico (raggiungibile solo con MAX_QUEUE_SIZE 1). Il
			# carico torna al magazzino con la regola unica: il ritorno prende il posto della proprietaria (la coda
			# supera il tetto di uno); senza magazzino il carico va a terra e la proprietaria esce.
			var outcome := CargoReturnService.release_cargo(individual, cargo_owner, GameSettings.active_world)
			if outcome != CargoReturnService.Outcome.RETURNING:
				individual.task_queue.erase(cargo_owner)
			if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
				print("[QUEUE OVERFLOW] Individuo #%d %s: coda piena della sola proprietaria del carico '%s' — %s, per fare spazio a '%s'." % [
					individual.id, individual.name, cargo_owner.task_name,
					"sostituita dal ritorno al magazzino" if outcome == CargoReturnService.Outcome.RETURNING else "scartata", task.task_name
				])
	individual.task_queue.append(task)


# Task proprietaria del carico nello zaino (2026-09-26), secondo la regola già seguita da HumanIndividual.
# assign_task (il "cargo owner"): la current_task se è sospendibile e non conclusa — una task persistente con
# carico addosso non viene mai sostituita, il nuovo comando va in coda — altrimenti l'ultima task sospesa in
# coda (solo una task persistente può aver riempito lo zaino ed essere stata interrotta con il carico ancora
# addosso). null se lo zaino è vuoto o non c'è nessuna candidata.
static func get_cargo_owner(individual: HumanIndividual) -> Task:
	if individual.carried_resources.is_empty():
		return null
	var current := individual.current_task
	if current != null and current.is_suspendable and not current.is_finished():
		return current
	if individual.task_queue.is_empty():
		return null
	return individual.task_queue.back()


# Seguito di una catena di lavoro (2026-10-10, caccia — macellazione dopo l'uccisione, nuova uscita della serie di caccia
# nelle zone): non è un ordine nuovo, quindi entra in coda SENZA il tetto MAX_QUEUE_SIZE e senza espellere nulla. In fondo:
# pop_suspended_task lo riprende per primo appena l'individuo si libera (alla chiusura della Task che lo ha generato, o
# dopo un bisogno già attivo in quel momento); le task già in coda restano dove sono.
static func push_follow_up_task(individual: HumanIndividual, task: Task) -> void:
	if task.is_finished():
		return
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
