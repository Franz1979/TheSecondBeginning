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
#
# BUGFIX righe duplicate/fantasma (2026-09-12, richiesta utente) — id per-istanza (sopra) basta a non
# duplicare mai la Task di un dato individuo NELLA SUA STESSA sequenza (assign_task/stop chiudono
# sempre la riga precedente di QUELLO STESSO individuo prima di aprirne una nuova), ma non basta
# quando una Build Task viene RICOSTRUITA per lo stesso target (es. edificio) da TaskReassignmentService
# — una Task nuova ha sempre un id nuovo, e se il lavoro precedente su quel target apparteneva a un
# individuo diverso (o la riga era rimasta aperta da un'assegnazione precedente mai chiusa
# esplicitamente), nulla la chiudeva: risultato, due righe "in corso" per lo stesso target. Vedi
# Task.debug_target_key (valorizzato solo da TaskReassignmentService.reassign_task, "" per ogni
# altra Task) e on_task_assigned sotto, che chiude per target_key PRIMA di aprire la nuova riga.
# Risolve anche il caso save/reload: GameLoadService.load_game_from_json chiama TaskDebugRegistry.
# clear() a inizio caricamento (questo registro non è persistito — vedi sopra), quindi le righe
# ricostruite da un reload non trovano mai entry residue di sessioni/partite precedenti.

const STATUS_IN_PROGRESS := "in corso"
const STATUS_COMPLETED := "completata"
const STATUS_INTERRUPTED := "interrotta"

# Tetto al numero di entry mantenute (2026-09-12) — una sessione lunga potrebbe accumulare
# centinaia di Task usa-e-getta (Rest/Wander premute ripetutamente); FIFO semplice quando il tetto
# viene superato, la più VECCHIA (in fondo, vedi ordine "più recente sopra" sotto) viene scartata —
# nessuna Task "importante" da preservare per forza, è un log diagnostico, non un archivio.
const MAX_ENTRIES: int = 200

# Un Dictionary per entry: {"id","task_name","individual_id","individual_name","status",
# "target_key"} — Array semplice, non Dictionary[id]->entry: l'ordine di inserimento (più recente in
# testa, vedi on_task_assigned sotto) è il dato che serve al pannello, un Dictionary lo perderebbe
# senza un campo ordine separato.
static var _entries: Array[Dictionary] = []


# Chiamato da HumanIndividual.assign_task() (nuovo Task) e da GameLoadService (Task ricostruita da
# reload) — registra SEMPRE una entry "in corso" in testa alla lista (più recente sopra). task
# null è un no-op silenzioso (guardia difensiva, nessun chiamante oggi lo passa mai null in
# pratica).
#
# Chiusura per target (2026-09-12, richiesta utente — fix righe duplicate/fantasma quando una Build
# Task viene ricostruita per lo stesso target, es. dopo un'interruzione) — task.id da solo identifica
# solo QUESTA istanza Task, mai la "stessa lavorazione" concettuale su un target che sopravvive a
# un'interruzione (TaskReassignmentService.reassign_task ricostruisce sempre una Task NUOVA, mai
# riusa l'istanza precedente, anche quando l'individuo assegnato è lo stesso di prima o uno diverso —
# vedi TaskReassignmentService.gd). Quando task.debug_target_key non è vuoto (oggi solo le Build Task
# lo valorizzano, vedi Task.gd), chiude PRIMA come interrotta ogni riga ancora "in corso" con lo
# stesso target_key: se era la Task precedente di QUESTO STESSO individuo, HumanIndividual.
# assign_task l'ha già chiusa poco sopra (on_task_closed, per id) e questo giro la trova già non-"in
# corso", no-op; se apparteneva invece a un individuo diverso (o a una riga lasciata aperta da una
# ricostruzione precedente), è questo il punto che la chiude. Task senza target persistente
# (debug_target_key == "": Walk/Wander/Rest/Daydream/haul_resource) saltano questo passo, stesso
# comportamento di sempre — non sono mai ricostruite da un target esterno.
static func on_task_assigned(individual: HumanIndividual, task: Task) -> void:
	if task == null:
		return
	if task.debug_target_key != "":
		for entry in _entries:
			if entry["target_key"] == task.debug_target_key and entry["status"] == STATUS_IN_PROGRESS:
				entry["status"] = STATUS_INTERRUPTED
	_entries.push_front({
		"id": task.id,
		"task_name": task.task_name,
		"individual_id": individual.id,
		"individual_name": individual.name,
		"status": STATUS_IN_PROGRESS,
		"target_key": task.debug_target_key,
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
