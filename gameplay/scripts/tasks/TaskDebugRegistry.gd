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

# Scadenza temporale (2026-09-13, richiesta utente: "le interrotte o completate cancellale dopo
# 2gg") — un'entry COMPLETED/INTERRUPTED chiusa da almeno questo numero di giorni di gioco viene
# rimossa dal registro alla prossima on_day_advanced sotto. STATUS_IN_PROGRESS non scade MAI qui
# (nessun closed_at_absolute_day valorizzato finché resta in corso, vedi sotto).
const EXPIRY_DAYS: int = 2

# Giorno assoluto corrente NOTO a questo registro (2026-09-13) — aggiornato una volta al giorno da
# on_day_advanced sotto (chiamato da GameTimeService._on_day_advanced/GameLoadService, mai da
# questa classe stessa). Necessario per stampare closed_at_absolute_day quando un'entry si chiude
# (on_task_closed/on_task_assigned sotto) SENZA violare il principio "registro stato puro, nessun
# riferimento a oggetti vivi" (vedi doc di testa al file) — un intero copiato, non un GameData vivo.
static var _current_absolute_day: int = 0

# Un Dictionary per entry: {"id","task_name","individual_id","individual_name","status",
# "target_key","closed_at_absolute_day"} — Array semplice, non Dictionary[id]->entry: l'ordine di
# inserimento (più recente in testa, vedi on_task_assigned sotto) è il dato che serve al pannello,
# un Dictionary lo perderebbe senza un campo ordine separato. closed_at_absolute_day (2026-09-13) =
# -1 finché la entry resta STATUS_IN_PROGRESS (mai scaduta), valorizzato al giorno assoluto corrente
# nel momento esatto in cui la entry passa a COMPLETED/INTERRUPTED (vedi on_task_closed/
# on_task_assigned sotto) — è la data di riferimento per il calcolo di scadenza in on_day_advanced.
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
				# closed_at_absolute_day (2026-09-13) — stessa stampa temporale di on_task_closed
				# sotto: questa chiusura "per target" è concettualmente la stessa chiusura, solo
				# attraverso un percorso diverso (nessun task.id corrispondente da cercare qui).
				entry["closed_at_absolute_day"] = _current_absolute_day
	_entries.push_front({
		"id": task.id,
		"task_name": task.task_name,
		"individual_id": individual.id,
		"individual_name": individual.name,
		"status": STATUS_IN_PROGRESS,
		"target_key": task.debug_target_key,
		"closed_at_absolute_day": -1,
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
				# closed_at_absolute_day (2026-09-13) — timbro temporale usato da on_day_advanced
				# sotto per decidere quando questa entry è "abbastanza vecchia" da essere rimossa.
				entry["closed_at_absolute_day"] = _current_absolute_day
			return


# Copia difensiva (2026-09-12) — il chiamante (TaskDebugPanel) non deve poter mutare lo stato
# interno di questo registro semplicemente leggendo la lista per popolare la UI.
static func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


static func clear() -> void:
	_entries.clear()


# Chiamata UNA VOLTA al giorno (2026-09-13, richiesta utente — filtro pannello + pulizia
# temporale): da GameTimeService._on_day_advanced (partita in corso) e da GameLoadService subito
# dopo il caricamento (per sincronizzare _current_absolute_day al giorno VERO appena caricato,
# evitando che un valore stantio residuo di una sessione precedente faccia scadere per errore
# un'entry chiusa nella finestra tra clear() e il prossimo avanzamento giorno reale).
#
# Aggiorna PRIMA _current_absolute_day (così on_task_closed/on_task_assigned di OGGI stampano il
# giorno giusto), POI rimuove ogni entry STATUS_COMPLETED/STATUS_INTERRUPTED chiusa da almeno
# EXPIRY_DAYS giorni — STATUS_IN_PROGRESS non viene mai considerata (closed_at_absolute_day resta
# -1 finché non si chiude, la condizione sotto la esclude per costruzione). Iterazione ALL'INDIETRO
# con remove_at, stesso idioma già in uso altrove nel progetto per rimozioni in-place da un Array
# scorso linearmente (es. GameTimeService._cleanup_expired_objects).
static func on_day_advanced(current_absolute_day: int) -> void:
	_current_absolute_day = current_absolute_day
	var i := _entries.size() - 1
	while i >= 0:
		var entry: Dictionary = _entries[i]
		var closed_at: int = entry.get("closed_at_absolute_day", -1)
		if closed_at >= 0 and current_absolute_day - closed_at >= EXPIRY_DAYS:
			_entries.remove_at(i)
		i -= 1
