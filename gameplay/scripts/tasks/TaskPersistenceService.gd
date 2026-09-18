class_name TaskPersistenceService
extends RefCounted

# Serializzazione/deserializzazione di HumanIndividual.current_task per il salvataggio
# (2026-09-08, richiesta utente) — separato da TaskFactory (che costruisce una Task da una
# TaskDefinition ASTRATTA + contesto, un concetto diverso: qui si ricostruisce ESATTAMENTE lo
# stato RUNTIME di una Task già in corso, non si "confeziona" una ricetta). Nessuno stato proprio
# (RefCounted, .new() mai chiamato — solo funzioni statiche, stesso pattern di TaskFactory).
#
# task_name/current_step_index/context/step_descriptions/step_stamina_cost/step_days_elapsed/
# step_happiness_cost (2026-09-13, richiesta utente) sono tutti Dictionary/Array/String/int/float
# già JSON-safe, copiati diretti. Ogni step invece richiede
# di sapere QUALE sottoclasse concreta di Action ricostruire — TaskTypes.ActionType (esteso con
# THINK/UNLOAD apposta per questo, vedi task_types.gd — UNLOAD rinominato da DEPOSIT il 2026-09-09,
# stesso valore intero: nessun save esistente rotto, vedi _action_type_for_step/_build_step) fa da
# chiave, stesso principio già usato da TaskFactory.build_task ma in entrambe le direzioni (qui
# serve anche class->enum, non solo enum->class).
#
# `target` (Action.target, Variant) è coperto GENERICAMENTE: se è un Vector2 (solo WalkAction oggi)
# viene salvato come target_x/target_y (JSON non supporta Vector2 nativamente, stesso trattamento
# già in uso altrove nel progetto — vedi GameSaveService.facing_direction_x/y); se è null (Rest/
# Think/Unload/PickUp) non viene salvato nulla. Qualunque stato interno AGGIUNTIVO di una
# sottoclasse (es. ThinkAction.duration/_elapsed, PickUpAction.target_position/resource_name/
# quantity_to_collect/duration/elapsed) passa da Action.get_save_data()/load_save_data(), non da
# questo file — così una futura Action con un proprio stato non richiede di toccare
# TaskPersistenceService, solo di implementare quei due metodi.
#
# `macro_state` (2026-09-09, richiesta utente, persistenza PickUpAction) — DEVIAZIONE rispetto alla
# firma precedente di deserialize_task/_build_step (prendevano solo `data`/`step_data`): necessaria
# perché PickUpAction.target_position (Vector2i) da solo non identifica una macrocella — serve il
# MacroCellState della cella HOME dell'individuo (stesso riferimento che GameScene._debug_test_two_
# walk_task inietta al momento della costruzione originale, vedi PickUpAction.gd). Non è
# recuperabile da `data` stesso (JSON non trasporta riferimenti a oggetti vivi), quindi il chiamante
# (GameLoadService, che ha già `world` e `individual.home_macro_coords` risolti a questo punto) lo
# risolve e lo inietta — stesso identico principio "chi crea/ricostruisce inietta i riferimenti
# esterni già risolti" già seguito ovunque in questo sistema. null è un valore legittimo (nessun
# MacroCellState risolvibile, es. home_macro_coords invalido) — PickUpAction lo tratta in modo
# difensivo (vedi lì), mai un crash qui.
#
# `world` (2026-09-09, richiesta utente, persistenza UnloadAction ramo fisico) — stesso identico
# principio di `macro_state` sopra: UnloadAction.target_building (Building) non è serializzabile
# per riferimento (JSON non trasporta oggetti vivi), quindi get_save_data() salva solo
# `target_building_id` (vedi unload_action.gd) e qui lo si risolve contro World.buildings, che
# GameLoadService ha già in scope. null è un valore legittimo (building_id non più esistente, es.
# distrutto nel frattempo — non dovrebbe succedere in pratica ma resta una guardia difensiva) — un
# building_id salvato ma non risolvibile è un caso limite accettato, non un errore da segnalare.
# DEVIAZIONE (2026-09-10, richiesta utente — scollegare il ramo di UnloadAction dalla nullità di
# target_building): un target_building_id non risolvibile NON implica più automaticamente il ramo
# pensiero come prima di questo passo — il ramo è deciso da `deposit_kind` (salvato/ricostruito a
# parte, vedi _build_step sotto), un target_building_id sopravvissuto ma non risolvibile con
# deposit_kind RESOURCE lascia semplicemente target_building null nel ramo fisico (guardia difensiva
# in UnloadAction.on_complete, mai un crash — vedi lì).


static func serialize_task(task: Task) -> Dictionary:
	var steps_data: Array = []
	for i in range(task.steps.size()):
		var step := task.steps[i]
		var step_data := {
			"action_type": _action_type_for_step(step),
			"step_description": task.step_descriptions[i] if i < task.step_descriptions.size() else "",
			"stamina_cost": task.step_stamina_cost[i] if i < task.step_stamina_cost.size() else 0.0,
			"days_elapsed": task.step_days_elapsed[i] if i < task.step_days_elapsed.size() else 0.0,
			# happiness_cost (2026-09-13, richiesta utente) — STESSO trattamento di stamina_cost
			# sopra: senza persisterlo, un reload a metà Task azzererebbe silenziosamente il
			# contributo happiness già maturato dagli step precedenti nel futuro log [TASK COST].
			"happiness_cost": task.step_happiness_cost[i] if i < task.step_happiness_cost.size() else 0.0,
		}
		if step.target is Vector2:
			step_data["target_x"] = step.target.x
			step_data["target_y"] = step.target.y
		step_data.merge(step.get_save_data())
		steps_data.append(step_data)
	return {
		"task_name": task.task_name,
		"current_step_index": task.current_step_index,
		"context": task.context,
		"steps": steps_data,
		# interrupt_priority/is_suspendable (2026-09-13, richiesta utente — struttura dati coda
		# personale, in preparazione al sistema di interrupt da stamina critica) — a DIFFERENZA di
		# allowed_age_bands (mai persistito: consultato SOLO al momento di assign_task(), vedi
		# Task.gd), questi due vanno riconsultati CONTINUAMENTE durante l'esecuzione (un interrupt
		# può scattare in qualunque istante, anche dopo un reload) — persistiti qui per non perdere
		# silenziosamente "questa Task di lavoro è sospendibile"/"questa è una Task-bisogno di
		# priorità X" ad ogni salvataggio.
		"interrupt_priority": task.interrupt_priority,
		"is_suspendable": task.is_suspendable,
		# is_idle_activity (2026-09-16, richiesta utente, fix bordo macrocella) — STESSO motivo/
		# STESSO trattamento di interrupt_priority/is_suspendable sopra: un attraversamento di
		# bordo può scattare in qualunque istante futuro, anche dopo un reload, quindi va
		# ricontrollato continuamente, non solo al momento di assign_task().
		"is_idle_activity": task.is_idle_activity,
	}


# .get() con default per OGNI campo (2026-09-08) — questo intero sistema di persistenza è nuovo,
# nessun save precedente lo contiene mai: stesso principio già richiesto da CLAUDE.md per campi
# nuovi/opzionali, qui applicato fin dal primo giorno invece che aggiunto in un secondo passo.
# Ritorna una Task vuota (nessuno step) se `data` è vuoto/malformato invece di null — il chiamante
# (GameLoadService) decide se assegnarla o meno a individual.current_task in base a "esisteva un
# current_task nel salvataggio" (vedi lì), questa funzione resta pura rispetto a quella decisione.
# `macro_state`/`world` — vedi i commenti in testa al file: propagati a _build_step, `macro_state`
# consultato per il solo caso PICKUP e `world` per il solo caso UNLOAD, ignorati per ogni altro
# action_type.
#
# BUGFIX (2026-09-10, richiesta utente — una Task salvata a metà del PRIMO step si "ferma"
# silenziosamente quando raggiunge il secondo, es. Walk→PickUp salvata durante il Walk): PRIMA di
# questo passo, load_save_data() veniva chiamato incondizionatamente su OGNI step ricostruito
# (dentro _build_step, vedi lì), inclusi gli step con indice DIVERSO da current_step_index — sia
# quelli già completati (innocuo, mai più riattivati) sia, soprattutto, quelli FUTURI mai ancora
# attivati nella sessione originale. Per Action con un guard `_restored_from_save` (PickUpAction/
# UnloadAction: activate() ricalcola quantità/durata dinamicamente e salta il ricalcolo se "già
# ripristinato da un save"), questo marcava incorrettamente uno step mai eseguito come "già in
# corso con progresso reale a zero" — quando la Task lo raggiungeva naturalmente più tardi, il suo
# PRIMO vero activate() veniva silenziosamente saltato, lasciandolo bloccato a durata/quantità zero
# (si "completa" istantaneamente senza fare nulla). Ora load_save_data() è chiamato SOLO per lo
# step all'indice current_step_index (l'unico per cui può esistere un progresso reale da
# preservare) — gli step precedenti e successivi restano nel loro stato di default appena
# costruito (_restored_from_save resta false su PickUpAction/UnloadAction), così il loro primo vero
# activate() — quando/se la Task li raggiunge — calcola tutto da zero come dovrebbe. Nessuna
# modifica a PickUpAction/UnloadAction/_build_step: il fix è interamente qui.
static func deserialize_task(data: Dictionary, macro_state: MacroCellState, world: World) -> Task:
	var steps: Array[Action] = []
	var step_descriptions: Array[String] = []
	var step_stamina_cost: Array[float] = []
	var step_days_elapsed: Array[float] = []
	var step_happiness_cost: Array[float] = []
	var current_step_index := int(data.get("current_step_index", 0))
	var raw_steps_data: Array = data.get("steps", [])
	for i in range(raw_steps_data.size()):
		var step_data: Dictionary = raw_steps_data[i]
		var step := _build_step(int(step_data.get("action_type", -1)), step_data, macro_state, world)
		if step == null:
			continue
		# Solo lo step CORRENTE riceve load_save_data() — vedi BUGFIX sopra. `i` è l'indice
		# nell'array grezzo salvato (data["steps"]), che coincide con l'indice in task.steps al
		# momento del salvataggio (serialize_task itera task.steps con lo stesso indice) — lo skip
		# di uno step null qui sotto non altera questa corrispondenza, dato che action_type
		# sconosciuto/-1 non è un caso reale (push_error in _build_step, non un ramo normale).
		if i == current_step_index:
			step.load_save_data(step_data)
		steps.append(step)
		step_descriptions.append(String(step_data.get("step_description", "")))
		step_stamina_cost.append(float(step_data.get("stamina_cost", 0.0)))
		step_days_elapsed.append(float(step_data.get("days_elapsed", 0.0)))
		step_happiness_cost.append(float(step_data.get("happiness_cost", 0.0)))

	var task := Task.new(steps)
	task.task_name = String(data.get("task_name", ""))
	task.current_step_index = current_step_index
	task.context = data.get("context", {})
	task.step_descriptions = step_descriptions
	task.step_stamina_cost = step_stamina_cost
	task.step_days_elapsed = step_days_elapsed
	task.step_happiness_cost = step_happiness_cost
	# interrupt_priority/is_suspendable — .get() con i default di classe (-1/false, "non è una
	# Task-bisogno"/"non sospendibile"), stesso trattamento di ogni altro campo opzionale in questo
	# file: un save precedente a questi due campi non li conteneva mai, il default resta corretto.
	task.interrupt_priority = int(data.get("interrupt_priority", -1))
	task.is_suspendable = bool(data.get("is_suspendable", false))
	# is_idle_activity — STESSO trattamento .get() con default (false, "non è una task perditempo")
	# di interrupt_priority/is_suspendable sopra.
	task.is_idle_activity = bool(data.get("is_idle_activity", false))
	return task


# class->enum, verso opposto di TaskFactory.build_task (che fa enum->class) — necessario qui perché
# si parte da un'istanza Action già viva (quella corrente della Task in corso), non da una
# TaskDefinition dichiarativa. push_error + ActionType impossibile (-1, mai un valore enum valido,
# vedi _build_step sotto che lo scarta) invece di far fallire l'intero salvataggio per un solo step
# di tipo sconosciuto.
static func _action_type_for_step(step: Action) -> int:
	if step is WalkAction:
		return TaskTypes.ActionType.WALK
	if step is RestAction:
		return TaskTypes.ActionType.REST
	if step is ThinkAction:
		return TaskTypes.ActionType.THINK
	if step is UnloadAction:
		return TaskTypes.ActionType.UNLOAD
	if step is PickUpAction:
		return TaskTypes.ActionType.PICKUP
	# SETUP_SITE/CLEAR (2026-09-11, richiesta utente — chiude un gap mai colmato: SETUP_SITE fu
	# aggiunta a TaskTypes.ActionType il 2026-09-10 insieme a SetupSiteAction, ma questa funzione
	# non fu MAI estesa per riconoscerla — un salvataggio a metà SetupSiteAction cadeva nel
	# push_error/-1 sotto, quindi serialize_task scriveva action_type=-1 per quello step e
	# _build_step lo scartava silenziosamente al reload (nessun crash, nessun log visibile — lo
	# step spariva e basta). Aggiunte insieme, stesso schema, ora che CLEAR (ClearAction) arriva a
	# introdurre lo stesso identico bisogno per un secondo tipo.
	if step is SetupSiteAction:
		return TaskTypes.ActionType.SETUP_SITE
	if step is ClearAction:
		return TaskTypes.ActionType.CLEAR
	# BUILD (2026-09-11, richiesta utente — quarto e ultimo step della Build Task, aggiunta insieme
	# al proprio case in _build_step sotto, stesso schema di SETUP_SITE/CLEAR: mai lasciata
	# "temporaneamente" scoperta come accadde per SETUP_SITE al suo debutto).
	if step is BuildAction:
		return TaskTypes.ActionType.BUILD
	# LOOK_AROUND (2026-09-12, richiesta utente — Wander Task, aggiunta insieme al proprio case in
	# _build_step sotto, stesso schema di BUILD sopra: mai lasciata "temporaneamente" scoperta).
	if step is LookAroundAction:
		return TaskTypes.ActionType.LOOK_AROUND
	# RETRIEVE (2026-09-12, richiesta utente — RetrieveAction, aggiunta insieme al proprio case in
	# _build_step sotto, stesso schema di LOOK_AROUND sopra: mai lasciata "temporaneamente" scoperta
	# come accadde storicamente per SETUP_SITE al suo debutto).
	if step is RetrieveAction:
		return TaskTypes.ActionType.RETRIEVE
	# RUN/JUMP (2026-09-13, richiesta utente, aggiunte insieme ai propri case in _build_step sotto,
	# stesso schema di RETRIEVE sopra: mai lasciate "temporaneamente" scoperte come accadde
	# storicamente per SETUP_SITE al suo debutto).
	if step is RunAction:
		return TaskTypes.ActionType.RUN
	if step is JumpAction:
		return TaskTypes.ActionType.JUMP
	push_error("TaskPersistenceService._action_type_for_step: tipo Action sconosciuto (%s)." % step.get_script().get_global_name())
	return -1


# enum->class, stesso principio di TaskFactory.build_task ma senza context_keys (qui il target
# arriva già risolto dentro step_data, non da un Dictionary di contesto esterno). load_save_data()
# NON è più chiamato qui (2026-09-10, BUGFIX — vedi il commento su deserialize_task, l'unico
# chiamante): questa funzione ora si limita a COSTRUIRE lo step con i dati che servono al
# costruttore (target_position/macro_state/resource_name per PICKUP, target_building/deposit_kind
# per UNLOAD, ecc. — questi restano risolti QUI, invariato, perché servono comunque a costruire uno
# step "identico" indipendentemente dal suo indice), mentre load_save_data() — che ripristina
# SOLO il progresso runtime (_elapsed/_duration/...) — è ora responsabilità del chiamante,
# condizionata all'indice dello step.
static func _build_step(action_type: int, step_data: Dictionary, macro_state: MacroCellState, world: World) -> Action:
	var step: Action = null
	match action_type:
		TaskTypes.ActionType.WALK:
			step = WalkAction.new(Vector2(float(step_data.get("target_x", 0.0)), float(step_data.get("target_y", 0.0))))
		TaskTypes.ActionType.REST:
			# rest_multiplier/max_duration_days/ignore_stamina_cap (2026-09-12, esteso 2026-09-16,
			# richiesta utente, Rest Task esplicita) — letti da RestAction.get_save_data (vedi lì),
			# default -1.0/false per compatibilità con save precedenti a questi due campi (nessun
			# tetto/nessuna modalità "per piacere" per una Task salvata prima di questa estensione),
			# stesso trattamento di skill_multiplier/tool_multiplier per BUILD sotto.
			step = RestAction.new(
				float(step_data.get("rest_multiplier", 1.0)),
				float(step_data.get("max_duration_days", -1.0)),
				bool(step_data.get("ignore_stamina_cap", false))
			)
		TaskTypes.ActionType.THINK:
			step = ThinkAction.new(float(step_data.get("duration", 0.0)))
		TaskTypes.ActionType.UNLOAD:
			var target_building: Building = null
			if step_data.has("target_building_id"):
				target_building = _find_building_by_id(world, int(step_data["target_building_id"]))
			# deposit_kind letto qui PRIMA della costruzione, stesso trattamento di
			# target_building_id sopra (2026-09-10, richiesta utente — scollegare il ramo di
			# UnloadAction dalla nullità di target_building: il discriminatore va ora persistito e
			# ricostruito esplicitamente, non più deducibile dalla presenza di target_building_id —
			# vedi UnloadAction.get_save_data). Default THOUGHT per compatibilità con save più vecchi
			# salvati prima di questo campo.
			var deposit_kind: UnloadAction.DepositKind = int(step_data.get("deposit_kind", UnloadAction.DepositKind.THOUGHT))
			step = UnloadAction.new(target_building, deposit_kind)
		TaskTypes.ActionType.PICKUP:
			var pickup_target := Vector2i(
				int(step_data.get("target_position_x", 0)), int(step_data.get("target_position_y", 0))
			)
			# quantity_requested (2026-09-18, richiesta utente) — .get() con default -1 per
			# compatibilità coi save precedenti a questo campo (nessuno di quei save può aver mai
			# avuto un tetto scelto dal player, quindi -1 "nessun tetto" è sempre il valore corretto).
			step = PickUpAction.new(
				pickup_target, macro_state, String(step_data.get("resource_name", "pebble")),
				int(step_data.get("quantity_requested", -1))
			)
		TaskTypes.ActionType.SETUP_SITE:
			# 1 argomento (target_building: Building), stesso schema di UNLOAD sopra per risolvere il
			# riferimento — GAP CHIUSO (2026-09-11, vedi nota su _action_type_for_step): prima d'ora
			# questo case non esisteva affatto, quindi SETUP_SITE non arrivava mai qui (scartato prima,
			# in _action_type_for_step). SetupSiteAction.get_save_data() scrive già "target_building_id"
			# da quando fu introdotta (2026-09-10) — era pronta per questo, semplicemente mai collegata.
			var setup_site_building: Building = null
			if step_data.has("target_building_id"):
				setup_site_building = _find_building_by_id(world, int(step_data["target_building_id"]))
			step = SetupSiteAction.new(setup_site_building)
		TaskTypes.ActionType.CLEAR:
			# 3 argomenti, stesso ordine di ClearAction._init(target_building, macro_state,
			# is_currently_grass) — DEVIAZIONE rispetto a PICKUP sopra: qui NON si riusa il parametro
			# `macro_state` di questa funzione (quello è la macrocella HOME dell'individuo, risolto da
			# GameLoadService — vedi commento in testa al file), perché la macrocella rilevante per
			# ClearAction è quella OSPITANTE il cantiere (target_building.macro_x/macro_y), che
			# potrebbe in teoria non coincidere (stesso limite architetturale noto di
			# GameScene._start_building_task_at — oggi coincidono sempre in pratica, ma questa
			# ricostruzione resta corretta anche se smettessero di farlo). Risolta contro World.
			# get_cell_state_at, `world` già disponibile qui (stesso `world` usato da UNLOAD sopra per
			# _find_building_by_id).
			var clear_target_building: Building = null
			if step_data.has("target_building_id"):
				clear_target_building = _find_building_by_id(world, int(step_data["target_building_id"]))
			var clear_macro_state: MacroCellState = null
			if clear_target_building != null and world != null:
				clear_macro_state = world.get_cell_state_at(clear_target_building.macro_x, clear_target_building.macro_y)
			step = ClearAction.new(
				clear_target_building, clear_macro_state, bool(step_data.get("is_currently_grass", false))
			)
		TaskTypes.ActionType.BUILD:
			# 3 argomenti (target_building, skill_multiplier, tool_multiplier), stesso schema di
			# SETUP_SITE sopra per il riferimento + BuildAction.get_save_data per i due moltiplicatori
			# (2026-09-11, quarto e ultimo step della Build Task). Nessun progresso da ripristinare
			# qui (labor_accumulated vive su Building.construction_progress, già ricostruito per
			# intero da GameLoadService — vedi BuildAction.gd, non richiede load_save_data()).
			var build_target_building: Building = null
			if step_data.has("target_building_id"):
				build_target_building = _find_building_by_id(world, int(step_data["target_building_id"]))
			step = BuildAction.new(
				build_target_building,
				float(step_data.get("skill_multiplier", 1.0)),
				float(step_data.get("tool_multiplier", 1.0))
			)
		TaskTypes.ActionType.LOOK_AROUND:
			# Nessun argomento — LookAroundAction._init non prende parametri (2026-09-12, richiesta
			# utente, Wander Task). elapsed/i due flag di cambio direzione arrivano da load_save_data
			# (chiamato dal chiamante SOLO se questo è lo step corrente, vedi deserialize_task sopra),
			# non da qui.
			step = LookAroundAction.new()
		TaskTypes.ActionType.RETRIEVE:
			# 3 argomenti (target_building, resource_name, quantity_requested), stesso schema di
			# UNLOAD/SETUP_SITE sopra per risolvere il riferimento all'edificio (2026-09-12, richiesta
			# utente, RetrieveAction). Nessun progresso da ripristinare qui oltre quantity_to_retrieve/
			# duration/elapsed/total_stamina_cost (arrivano da load_save_data, chiamato dal chiamante
			# SOLO se questo è lo step corrente, vedi deserialize_task sopra).
			var retrieve_target_building: Building = null
			if step_data.has("target_building_id"):
				retrieve_target_building = _find_building_by_id(world, int(step_data["target_building_id"]))
			step = RetrieveAction.new(
				retrieve_target_building,
				String(step_data.get("resource_name", "")),
				int(step_data.get("quantity_requested", 0))
			)
		TaskTypes.ActionType.RUN:
			# 1 argomento (target: Vector2), stesso schema di WALK sopra (target_x/target_y già
			# coperti genericamente da serialize_task, vedi la nota in testa al file).
			step = RunAction.new(Vector2(float(step_data.get("target_x", 0.0)), float(step_data.get("target_y", 0.0))))
		TaskTypes.ActionType.JUMP:
			# Nessun argomento — JumpAction._init non prende parametri (2026-09-13, richiesta
			# utente). _duration/_jump_count/elapsed/jumps_triggered arrivano da load_save_data
			# (chiamato dal chiamante SOLO se questo è lo step corrente, vedi deserialize_task sopra) —
			# senza quella chiamata l'istanza fresca qui tiene i valori appena tirati a caso dal
			# proprio _init, corretto per uno step non ancora raggiunto.
			step = JumpAction.new()
		_:
			push_error("TaskPersistenceService._build_step: action_type %d non supportato." % action_type)
			return null
	return step


# Scansione lineare di World.buildings (stesso pattern già in uso in GameScene._debug_test_daydream_
# task per trovare lo Pebble Circle) — nessun indice per id costruito apposta: il numero di edifici
# resta piccolo per ora, non vale la complessità di un Dictionary id->Building mantenuto a parte.
# null se non trovato (world null, o building_id di un edificio non più esistente) — UnloadAction
# tratta target_building null come ramo pensiero, mai un crash qui.
static func _find_building_by_id(world: World, building_id: int) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null
