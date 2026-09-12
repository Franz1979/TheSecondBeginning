class_name TaskDebugRegistry
extends RefCounted

# Registro STATIC "usa e getta" (2026-09-12, richiesta utente — tab di debug 🐞 nell'info panel:
# "elencami tutte le task con id, nome task, l'assegnatario, lo stato... in ordine dalla più
# recente sopra") — nessuna Task/HumanIndividual VIVA referenziata negli ingressi (solo id/nome
# copiati al momento della registrazione, stesso principio "dati già risolti" di ogni pannello UI
# del progetto): un individuo morto o una Task già scartata restano consultabili qui anche dopo che
# l'oggetto vero non esiste più. SOLO in-memoria per questa sessione di gioco — NON persistito in
# save/load (stesso principio "diagnostico, non simulazione" di DebugLogging stessa): un reload
# parte con la lista vuota, un salvataggio non la include.
#
# Hook: HumanIndividual.assign_task()/stop() chiamano rispettivamente on_task_assigned/
# on_task_closed sotto — QUESTI DUE sono gli UNICI punti che scrivono HumanIndividual.current_task
# nell'intero progetto (verificato: HumanIndividual.set_target passa anch'esso da assign_task),
# quindi coprono per costruzione OGNI Task mai assegnata a un HumanIndividual in questa sessione,
# indipendentemente da quale trigger l'abbia creata (Rest/Wander/Build/haul_resource/Daydream/
# debug hooks). GameLoadService.gd registra SEPARATAMENTE una Task ricostruita da un reload (non
# passa da assign_task, scrive current_task direttamente — vedi lì) con lo stesso on_task_assigned.
#
# GAP NOTO (non risolto, fuori scope per un primo giro di un pannello diagnostico): un individuo
# che MUORE con una Task ancora "in corso" non la chiude mai esplicitamente (GameTimeService.
# _kill_individual non chiama stop()) — quella entry resta "in corso" per sempre nella lista, un
# falso "mai concluso" per un individuo che nel frattempo non esiste più. Accettabile per una prima
# versione, segnalato qui per quando servirà davvero risolverlo.

const STATUS_IN_PROGRESS := "in corso"
const STATUS_COMPLETED := "completata"
const STATUS_INTERRUPTED := "interrotta"

# Tetto al numero di entry mantenute (2026-09-12) — una sessione lunga potrebbe accumulare
# centinaia di Task usa-e-getta (Rest/Wander premute ripetutamente); FIFO semplice quando il tetto
# viene superato, la più VECCHIA (in fondo, vedi ordine "più recente sopra" sotto) viene scartata —
# nessuna Task "importante" da preservare per forza, è un log diagnostico, non un archivio.
const MAX_ENTRIES: int = 200

# Un Dictionary per entry: {"id","task_name","individual_id","individual_name","status"} — Array
# semplice, non Dictionary[id]->entry: l'ordine di inserimento (più recente in testa, vedi
# on_task_assigned sotto) è il dato che serve al pannello, un Dictionary lo perderebbe senza un
# campo ordine separato.
static var _entries: Array[Dictionary] = []


# Chiamato da HumanIndividual.assign_task() (nuovo Task) e da GameLoadService (Task ricostruita da
# reload) — registra SEMPRE una entry "in corso" in testa alla lista (più recente sopra). task
# null è un no-op silenzioso (guardia difensiva, nessun chiamante oggi lo passa mai null in
# pratica).
static func on_task_assigned(individual: HumanIndividual, task: Task) -> void:
	if task == null:
		return
	_entries.push_front({
		"id": task.id,
		"task_name": task.task_name,
		"individual_id": individual.id,
		"individual_name": individual.name,
		"status": STATUS_IN_PROGRESS,
	})
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)


# Chiamato da HumanIndividual.assign_task() (PRIMA di sovrascrivere current_task con la nuova Task)
# e da stop() (prima di azzerare current_task) — chiude l'entry corrispondente, se esiste:
# STATUS_COMPLETED se task.is_finished() era già vero a quel momento (arrivo naturale, vedi
# HumanIndividualActionService.apply_action, che chiama stop() SOLO dopo aver verificato is_
# finished()), STATUS_INTERRUPTED altrimenti (sostituita da una nuova Task prima di finire, o
# fermata manualmente — tasto H). task null (nessuna Task da chiudere, es. individuo appena creato,
# mai assegnato) o entry non trovata è un no-op silenzioso.
static func on_task_closed(task: Task) -> void:
	if task == null:
		return
	for entry in _entries:
		if entry["id"] == task.id:
			if entry["status"] == STATUS_IN_PROGRESS:
				entry["status"] = STATUS_COMPLETED if task.is_finished() else STATUS_INTERRUPTED
			return


# Copia difensiva (2026-09-12) — il chiamante (TaskDebugPanel) non deve poter mutare lo stato
# interno di questo registro semplicemente leggendo la lista per popolare la UI.
static func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


static func clear() -> void:
	_entries.clear()
