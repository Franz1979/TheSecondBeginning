class_name HumanIndividualActionService
extends RefCounted

# Servizio single-responsibility (stesso pattern di HumanIndividualMovementService, stesso
# livello/cartella): applica lo step ATTIVO della Task corrente di un HumanIndividual
# (individual.current_task), se presente — costo/recupero di stamina per questo istante, poi
# verifica se quello step è concluso e fa avanzare la Task di conseguenza. Girato ogni frame da
# GameScene._process, DOPO individual_movement_service.advance_movement (vedi lì per il perché
# dell'ordine: WalkAction.get_stamina_delta calcola la distanza percorsa confrontando
# individual.position con l'ultima nota, quindi deve leggere la position già aggiornata di questo
# frame — e advance_movement NON chiama più individual.stop() all'arrivo, vedi lì: è QUESTO
# servizio, non quello, a decidere quando una Task è davvero conclusa).
#
# Nessun clamp su current_stamina in questo passo (richiesta esplicita utente, 2026-09-06): può
# scendere sotto zero senza conseguenze — l'auto-interrupt quando la stamina si esaurisce arriverà
# in uno step successivo.

# `world` (2026-09-09, richiesta utente — nato per il re-routing UnloadAction su magazzino pieno,
# poi GENERALIZZATO alla ricerca magazzino post-PickUp, vedi _handle_pending_warehouse_search
# sotto) — DEVIAZIONE rispetto alla firma precedente (solo individual/delta): necessario per passare
# a WarehouseSelectionService.find_best, che deve conoscere World.buildings per scegliere un
# magazzino. Default null (non `world: World` obbligatorio) così qualunque futuro chiamante che non
# ha ancora un World a portata di mano non rompe la compilazione — _handle_pending_warehouse_search
# tratta world null come "nessun candidato disponibile" (stesso comportamento del ramo "nessun
# magazzino trovato", vedi lì), mai un crash. UNICO call site oggi: GameScene._process, che passa
# macro_world.
func apply_action(individual: HumanIndividual, delta: float, world: World = null) -> void:
	# Fallback di rest implicito RIMOSSO (2026-09-12, richiesta utente — "un individuo senza
	# current_task valida deve semplicemente non fare nulla qui: nessun recupero automatico, nessun
	# consumo automatico"). Un individuo con current_task null/conclusa resta a stamina invariata
	# indefinitamente finché non gli viene assegnata manualmente una nuova Task — il vero recupero
	# stamina tornerà a breve dentro una Rest Task esplicita (Walk verso casa + RestAction), non
	# più come fallback implicito di questa funzione. Verificato (indagine dedicata, giro
	# precedente): ogni lettore di current_task/current_action nel codebase è già null-safe, e
	# questo era l'UNICO punto dell'intero progetto che rigenerava current_stamina — rimuoverlo
	# senza sostituto è quindi una regressione di gameplay attesa/temporanea, non un bug.
	if individual.current_task == null or individual.current_task.is_finished():
		return
	# Avanzamento automatico Task (2026-09-07, richiesta utente, introdotto insieme a Task) —
	# applica lo step ATTIVO (mai la Task intera: Task non sa nulla di stamina, vedi Task.gd), poi
	# se quello step è concluso fa avanzare l'indice: se la Task risulta conclusa DOPO l'avanzamento
	# ferma per davvero l'individuo (stop(), che azzera is_moving/current_task — vedi HumanIndividual.
	# gd), altrimenti attiva subito il nuovo step attivo (activate(), vedi Action.gd/WalkAction.gd)
	# così il movimento prosegue senza soluzione di continuità verso la destinazione successiva,
	# nello stesso frame in cui il precedente è arrivato — nessun frame "fermo" in mezzo.
	# `task` tenuto in una variabile locale (2026-09-07, necessario per il log di costo sotto):
	# individual.stop() azzera individual.current_task, quindi senza questo riferimento la Task non
	# sarebbe più raggiungibile nel momento in cui va stampato il suo riepilogo costi.
	var task := individual.current_task
	var action := task.get_current_action()
	var stamina_delta := action.get_stamina_delta(individual, task.context, delta)
	individual.current_stamina += stamina_delta
	# Accumulo costo per-step (2026-09-07, richiesta utente) — stesso stamina_delta/delta appena
	# applicati sopra, nessun ricalcolo: vedi Task.record_step_cost/print_cost_summary.
	task.record_step_cost(stamina_delta, delta)
	if action.is_complete(individual, task.context):
		# on_complete() (2026-09-07, richiesta utente, introdotta con ThinkAction) — SEMPRE PRIMA di
		# advance_to_next_step()/stop(): quello che uno step lascia sull'individuo al proprio termine
		# (es. ThinkAction -> individual.pending_thought = true) deve essere scritto mentre quello
		# step è ancora "il current" per costruzione, non dopo che la Task è già passata oltre.
		action.on_complete(individual, task.context)
		# Ricerca magazzino (2026-09-09, richiesta utente — nata come re-routing UnloadAction su
		# magazzino pieno, poi GENERALIZZATA per servire anche la ricerca iniziale post-PickUp di
		# haul_resource, stesso canale/stesso Dictionary per entrambe, vedi _handle_pending_
		# warehouse_search sotto) e "cammina via" dopo un deposito riuscito (vedi _handle_pending_
		# walk_away sotto) — ENTRAMBE DOPO on_complete(), PRIMA di advance_to_next_step(): quello che
		# uno step ha appena scritto in context va consumato mentre è ancora "il current" per
		# costruzione, accodando eventuali nuovi step alla Task corrente PRIMA che l'indice avanzi,
		# così is_finished()/il nuovo current_action sotto vedono già i nuovi step come parte della
		# stessa Task, mai una Task separata. Ordine fra le due chiamate irrilevante in pratica: sono
		# mutuamente esclusive per costruzione (pending_warehouse_search lo scrive solo un deposito
		# NON riuscito/ricerca iniziale, pending_walk_away_position solo un deposito RIUSCITO — mai
		# entrambe nello stesso passaggio, vedi unload_action.gd).
		_handle_pending_warehouse_search(individual, task, world)
		_handle_pending_thought_target_search(individual, task, world)
		_handle_pending_walk_away(task)
		task.advance_to_next_step()
		if task.is_finished():
			if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_TOTAL_COST_LOGS:
				task.print_cost_summary(individual)
			individual.stop()
		else:
			task.get_current_action().activate(individual, task.context)


# Consuma task.context["pending_warehouse_search"] (2026-09-09, richiesta utente — GENERALIZZATO da
# _handle_pending_reroute: un unico canale/Dictionary riusato sia dal re-routing UnloadAction su
# magazzino pieno — UnloadAction.activate, vedi lì — sia dalla ricerca magazzino INIZIALE dopo un
# PickUp riuscito — PickUpAction.on_complete, vedi lì). No-op immediato se la chiave non è presente
# (il caso comune, nessuno step ha appena richiesto una ricerca) — questa funzione è chiamata ad OGNI
# step completato di OGNI Task, non solo dopo un PickUp/Unload, quindi deve restare economica quando
# non c'è nulla da fare.
#
# pending_warehouse_search viene SEMPRE rimosso qui (in ENTRAMBI i casi sotto, trovato o non trovato
# un candidato) — mai lasciato oltre questa chiamata, altrimenti lo step successivo (che potrebbe non
# essere affatto un Unload) lo rileggerebbe per errore.
#
# warehouse_search_excluded_building_ids (la lista persistente, NON il campo excluded_building_ids
# dentro il Dictionary appena letto/rimosso — vedi commento su quella chiave in unload_action.gd)
# invece non viene mai toccato qui: è UnloadAction.activate, non questa funzione, a farlo crescere
# quando scopre un nuovo magazzino pieno.
#
# discard_on_failure (dentro il Dictionary) distingueva in origine DUE esiti diversi per "nessun
# candidato" (true = re-routing, perdita; false/assente = ricerca iniziale, nessuna perdita) — dal
# fix unificato "scarico a terra" (2026-09-12, richiesta utente) i DUE esiti ora CONVERGONO sullo
# stesso risultato pratico (HumanIndividual.discard_carried_resource, vedi lì per il log/il TODO sul
# futuro sistema di scarico a terra): true = re-routing fallito (Scenario B2, un edificio già
# raggiunto è risultato pieno), false/assente = ricerca iniziale fallita (Scenario B1, nessun
# edificio da abbandonare, ma comunque nessuna destinazione disponibile). Il campo resta comunque
# utile per distinguere i due CONTESTI nel log stampato subito prima di ciascuna chiamata, anche se
# l'esito finale (scarto) è oggi identico.
func _handle_pending_warehouse_search(individual: HumanIndividual, task: Task, world: World) -> void:
	if not task.context.has("pending_warehouse_search"):
		return
	var search: Dictionary = task.context["pending_warehouse_search"]
	task.context.erase("pending_warehouse_search")

	var resource_name := String(search.get("resource_name", ""))
	var quantity := int(search.get("quantity", 0))
	if resource_name == "" or quantity <= 0:
		return

	# Costruita manualmente (int(id) per elemento), non Array[int](search.get(...)) — stesso motivo
	# di UnloadAction.activate (vedi lì): gestisce anche un context deserializzato da JSON (numeri
	# sempre float, mai int).
	var excluded_building_ids: Array[int] = []
	for raw_id in search.get("excluded_building_ids", []):
		excluded_building_ids.append(int(raw_id))

	var candidate := WarehouseSelectionService.find_best(
		world, individual.position, individual.home_macro_coords, resource_name, quantity, excluded_building_ids
	)
	if candidate != null:
		var macro_offset: Vector2 = Vector2(Vector2i(candidate.macro_x, candidate.macro_y) - individual.home_macro_coords) * World.WIDTH
		var candidate_position: Vector2 = Vector2(candidate.micro_x, candidate.micro_y) + macro_offset
		# DepositKind.RESOURCE passato esplicitamente (2026-09-10, richiesta utente — scollegare il
		# ramo di UnloadAction dalla nullità di target_building): `candidate` qui è sempre un Building
		# risolto (vedi guardia `if candidate != null` sopra), stesso comportamento di ramo fisico di
		# prima di questo passo, ora reso esplicito invece che dedotto dalla non-nullità dell'argomento.
		var new_steps: Array[Action] = [WalkAction.new(candidate_position), UnloadAction.new(candidate, UnloadAction.DepositKind.RESOURCE)]
		task.append_steps(new_steps)
		if DebugLogging.ENABLED:
			print("[WAREHOUSE SEARCH] magazzino trovato: id=%d — Walk+Unload accodati alla Task corrente (esclusi finora: %s)." % [
				candidate.id, str(excluded_building_ids)
			])
		return

	if bool(search.get("discard_on_failure", false)):
		# Scenario B2 — re-routing fallito (2026-09-09, richiesta utente iniziale — nota di
		# contesto in fase di indagine; UNIFICATO 2026-09-12 sotto discard_carried_resource, che
		# prima duplicava qui lo stesso azzeramento inline senza log/commento dedicato): nessun
		# magazzino alternativo trovato dopo che il target originale è risultato pieno all'arrivo.
		# Vedi HumanIndividual.discard_carried_resource per il log/il TODO sul futuro sistema di
		# scarico a terra — questo print resta qui SOLO per il contesto SPECIFICO del re-routing
		# (perché la ricerca è scattata: magazzino pieno), non duplicato dal log generico della
		# funzione condivisa.
		if DebugLogging.ENABLED:
			print("[WAREHOUSE SEARCH] nessun magazzino alternativo trovato per resource_name='%s' quantity=%d dopo re-routing (magazzino originale pieno all'arrivo)." % [
				resource_name, quantity
			])
		individual.discard_carried_resource()
		return

	# Scenario B1 — ricerca INIZIALE (PickUpAction) senza candidato (2026-09-12, richiesta utente
	# — fix unificato "scarico a terra": DECISIONE CAMBIATA rispetto al comportamento precedente,
	# che qui lasciava l'individuo "con la merce in spalla, nessuna perdita" — ora invece scarta
	# anche questo caso, stessa funzione condivisa di B2/Scenario A) — nessun edificio "vicino da
	# abbandonare" in questo caso (a differenza di B2, qui non c'è mai stato un target da cui
	# ripartire), ma il risultato pratico è lo stesso: la Task (solo [Walk, PickUp] per
	# haul_resource) termina qui SENZA aver mai raggiunto un Unload — individual.stop() poco dopo,
	# in apply_action, chiuderebbe comunque lo zaino via il proprio hook di sicurezza (vedi
	# HumanIndividual.stop()), ma scartare QUI, PRIMA della terminazione, è più diretto e
	# corrisponde esattamente al punto richiesto ("prima o durante la terminazione della Task").
	if DebugLogging.ENABLED:
		print("[WAREHOUSE SEARCH] nessun magazzino trovato per resource_name='%s' quantity=%d — nessun edificio da abbandonare in questo caso, ma nessuna destinazione disponibile." % [
			resource_name, quantity
		])
	individual.discard_carried_resource()


# Consuma task.context["pending_thought_target_search"] (2026-09-10, richiesta utente — handler di
# ricerca per i pensieri, PARALLELO a _handle_pending_warehouse_search sopra ma per il ramo PENSIERO
# di UnloadAction: stesso canale generico/stesso momento di consumo — DOPO on_complete(), PRIMA di
# advance_to_next_step(), vedi apply_action) — usa ThoughtTargetSelectionService invece di
# WarehouseSelectionService come unica differenza di dominio. No-op immediato se la chiave non è
# presente, stesso motivo/stessa economicità di _handle_pending_warehouse_search: questa funzione è
# chiamata ad OGNI step completato di OGNI Task.
#
# Struttura del Dictionary DELIBERATAMENTE più piccola di pending_warehouse_search — SOLO
# excluded_building_ids (nessun resource_name/quantity, che non hanno senso per un pensiero: nessuna
# categoria/capacità residua da verificare, vedi ThoughtTargetSelectionService.find_best) e nessun
# discard_on_failure: quel campo esiste sull'altro canale per distinguere re-routing (perdita
# TEMPORANEA della merce) da ricerca iniziale (nessuna perdita) — qui non esiste ancora uno scenario
# di re-routing (nessun chiamante reale scrive ancora questa chiave, vedi nota in testa al file), e
# comunque non c'è alcun side-effect distruttivo equivalente a carried_* da poter scartare: un
# pensiero non depositato semplicemente resta pending sull'individuo (vedi ramo "nessun candidato"
# sotto), stesso trattamento "nessuna perdita" già riservato alla ricerca INIZIALE del magazzino.
# `excluded_building_ids` viene comunque letto/passato per permettere a un futuro chiamante di
# escludere edifici già provati (es. un secondo tentativo dopo un fallimento), stesso principio
# dell'omonimo campo sull'altro canale — semplicemente non c'è ancora nessuno che lo faccia crescere.
func _handle_pending_thought_target_search(individual: HumanIndividual, task: Task, world: World) -> void:
	if not task.context.has("pending_thought_target_search"):
		return
	var search: Dictionary = task.context["pending_thought_target_search"]
	task.context.erase("pending_thought_target_search")

	# Costruita manualmente (int(id) per elemento), non Array[int](search.get(...)) — stesso motivo
	# di _handle_pending_warehouse_search sopra: gestisce anche un context deserializzato da JSON
	# (numeri sempre float, mai int).
	var excluded_building_ids: Array[int] = []
	for raw_id in search.get("excluded_building_ids", []):
		excluded_building_ids.append(int(raw_id))

	var candidate := ThoughtTargetSelectionService.find_best(
		world, individual.position, individual.home_macro_coords, excluded_building_ids
	)
	if candidate != null:
		var macro_offset: Vector2 = Vector2(Vector2i(candidate.macro_x, candidate.macro_y) - individual.home_macro_coords) * World.WIDTH
		var candidate_position: Vector2 = Vector2(candidate.micro_x, candidate.micro_y) + macro_offset
		# DepositKind.THOUGHT passato esplicitamente (stesso principio di DepositKind.RESOURCE in
		# _handle_pending_warehouse_search sopra) — `candidate` qui è sempre un Building risolto
		# (vedi guardia `if candidate != null`), coerente con target_building ora indipendente da
		# deposit_kind (vedi nota in testa a unload_action.gd).
		var new_steps: Array[Action] = [WalkAction.new(candidate_position), UnloadAction.new(candidate, UnloadAction.DepositKind.THOUGHT)]
		task.append_steps(new_steps)
		if DebugLogging.ENABLED:
			print("[THOUGHT TARGET SEARCH] edificio trovato: id=%d — Walk+Unload(THOUGHT) accodati alla Task corrente (esclusi finora: %s)." % [
				candidate.id, str(excluded_building_ids)
			])
		return

	# Nessun edificio con accepts_thoughts trovato — nessun side-effect equivalente a carried_* da
	# ripulire (vedi nota in testa alla funzione): il pensiero resta semplicemente pending
	# sull'individuo (individual.pending_thought, se già true, non viene toccato qui), la Task
	# prosegue/termina senza aver depositato. Nessuna perdita, non un fallimento distruttivo —
	# stesso trattamento "nessun candidato" già riservato alla ricerca INIZIALE del magazzino sopra.
	if DebugLogging.ENABLED:
		print("[THOUGHT TARGET SEARCH] nessun edificio con accepts_thoughts trovato — nessun deposito, la Task prosegue/termina senza aver depositato il pensiero.")


# Consuma task.context["pending_walk_away_position"] scritto da UnloadAction.on_complete() (vedi lì)
# subito dopo un deposito FISICO riuscito (2026-09-09, richiesta utente — haul_resource, ultimo
# step "cammina via" — stesso schema di walk_away in Daydream). No-op se la chiave non è presente
# (il caso comune). A differenza di _handle_pending_warehouse_search sopra, non ha bisogno di
# `individual`/`world`: la posizione è già completamente risolta da chi ha scritto la chiave.
func _handle_pending_walk_away(task: Task) -> void:
	if not task.context.has("pending_walk_away_position"):
		return
	var walk_away_position: Vector2 = task.context["pending_walk_away_position"]
	task.context.erase("pending_walk_away_position")
	var new_steps: Array[Action] = [WalkAction.new(walk_away_position)]
	task.append_steps(new_steps)
	if DebugLogging.ENABLED:
		print("[WALK AWAY] WalkAction accodato verso %s dopo un deposito riuscito." % str(walk_away_position))
