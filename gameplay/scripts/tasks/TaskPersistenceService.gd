class_name TaskPersistenceService
extends RefCounted

# Serializzazione/deserializzazione di HumanIndividual.current_task per il salvataggio
# (2026-09-08, richiesta utente) — separato da TaskFactory (che costruisce una Task da una
# TaskDefinition ASTRATTA + contesto, un concetto diverso: qui si ricostruisce ESATTAMENTE lo
# stato RUNTIME di una Task già in corso, non si "confeziona" una ricetta). Nessuno stato proprio
# (RefCounted, .new() mai chiamato — solo funzioni statiche, stesso pattern di TaskFactory).
#
# task_name/current_step_index/context/step_descriptions/step_stamina_cost/step_days_elapsed sono
# tutti Dictionary/Array/String/int/float già JSON-safe, copiati diretti. Ogni step invece richiede
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

	var task := Task.new(steps)
	task.task_name = String(data.get("task_name", ""))
	task.current_step_index = current_step_index
	task.context = data.get("context", {})
	task.step_descriptions = step_descriptions
	task.step_stamina_cost = step_stamina_cost
	task.step_days_elapsed = step_days_elapsed
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
	push_error("TaskPersistenceService._action_type_for_step: tipo Action sconosciuto (%s)." % step.get_script().get_global_name())
	return -1


# enum->class, stesso principio di TaskFactory.build_task ma senza context_key (qui il target
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
			step = RestAction.new()
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
			step = PickUpAction.new(pickup_target, macro_state, String(step_data.get("resource_name", "pebble")))
		_:
			push_error("TaskPersistenceService._build_step: action_type %d non supportato." % action_type)
			return null
	return step


# Scansione lineare di World.buildings (stesso pattern già in uso in GameScene._debug_test_daydream_
# task per trovare lo Stone Circle) — nessun indice per id costruito apposta: il numero di edifici
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
