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

# Rest è lo stato IMPLICITO di un individuo senza current_task attiva (2026-09-07, richiesta
# utente — "senza current_action" nel commento originale, aggiornato per Task) — istanza condivisa
# unica, creata una sola volta qui come costante statica del servizio, non una nuova istanza per
# frame per ogni individuo idle: RestAction non ha bisogno di stato proprio (nessun target, nessun
# _last_position come in WalkAction), quindi una sola istanza può servire tutti gli individui idle
# contemporaneamente senza rischio di stato incrociato.
static var _idle_rest_action := RestAction.new()


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
	if individual.current_task == null or individual.current_task.is_finished():
		# Rest implicito: non scrive individual.current_task (resta null/conclusa) — non "occupa"
		# lo slot della task corrente, che resta libero per essere sovrascritto immediatamente da
		# un comando esplicito come Walk.
		individual.current_stamina += _idle_rest_action.get_stamina_delta(individual, {}, delta)
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
# discard_on_failure (dentro il Dictionary) distingue i DUE esiti "nessun candidato" richiesti
# esplicitamente dall'utente per i due casi: true (scritto solo da UnloadAction.activate, re-routing
# — un edificio già raggiunto è risultato pieno) fa perdere la merce "per strada", TEMPORANEO, nessun
# sistema di scarico a terra esiste ancora; false/assente (PickUpAction.on_complete, ricerca
# iniziale — nessun edificio "vicino da abbandonare" in questo caso) lascia semplicemente l'individuo
# con la merce in spalla, nessuna perdita — non un fallimento distruttivo.
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
		var new_steps: Array[Action] = [WalkAction.new(candidate_position), UnloadAction.new(candidate)]
		task.append_steps(new_steps)
		if DebugLogging.ENABLED:
			print("[WAREHOUSE SEARCH] magazzino trovato: id=%d — Walk+Unload accodati alla Task corrente (esclusi finora: %s)." % [
				candidate.id, str(excluded_building_ids)
			])
		return

	if bool(search.get("discard_on_failure", false)):
		# TEMPORANEO (2026-09-09, richiesta utente, nota esplicita in fase di indagine — "nota di
		# contesto per l'implementazione successiva"): nessun magazzino alternativo trovato dopo un
		# re-routing. Non esiste ANCORA un vero sistema di scarico a terra (drop pile/lotto
		# persistente sulla mappa) — la merce viene quindi semplicemente PERSA qui ("scaricata per
		# strada"), invece di restare bloccata nello zaino dell'individuo all'infinito. DA SOSTITUIRE
		# quando quel sistema esisterà: questo ramo dovrà allora creare davvero un lotto a terra
		# invece di azzerare lo zaino.
		if DebugLogging.ENABLED:
			print("[WAREHOUSE SEARCH] nessun magazzino alternativo trovato per resource_name='%s' quantity=%d — merce persa 'per strada' (comportamento TEMPORANEO, nessun sistema di scarico a terra esiste ancora)." % [
				resource_name, quantity
			])
		individual.carried_quantity = 0
		individual.carried_resource_name = ""
		individual.carried_decay_fraction = 0.0
		return

	# Ricerca INIZIALE (PickUpAction) senza candidato — nessun edificio "vicino da abbandonare" in
	# questo caso: l'individuo resta semplicemente con la merce in spalla, la Task prosegue/termina
	# su quello che ha. Nessuna perdita, non un fallimento distruttivo (richiesta esplicita utente).
	if DebugLogging.ENABLED:
		print("[WAREHOUSE SEARCH] nessun magazzino trovato per resource_name='%s' quantity=%d — l'individuo resta con la merce in spalla (nessun edificio da abbandonare in questo caso)." % [
			resource_name, quantity
		])


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
