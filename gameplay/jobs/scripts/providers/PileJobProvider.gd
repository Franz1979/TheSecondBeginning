class_name PileJobProvider
extends RefCounted

# Fornitore "mucchi" della lista dei lavori (2026-10-07; spostato da GameScene il 2026-10-17, refactoring GameScene blocco
# 2b): mucchi a terra abbandonati (pile:<id>). Conta lo stato, non l'origine: un mucchio è "di qualcuno" (assegnato) se un
# pipottino ha, come task in corso o in coda, una task che lo porta via (collect_claims). Fuori dalla lista: i mucchi con
# una carcassa (lavoro della macellazione) e quelli senza risorse. Tutta la lista dei mucchi si spegne con la regola
# "Ritira i mucchi abbandonati" (UserOptions.job_board_collect_piles). Mucchio che nessun magazzino accetta (has_storage,
# dalla posizione del mucchio, indipendente dal pipottino): visibile in coda ma non prendibile ("blocked_reason"), senza
# attesa né icona. Assegnazione, X e Rimetti in coda restano alla scena.

# Mucchi dopo corpi ed edifici nelle righe del cassetto.
const SORT_OFFSET: float = 1000000.0
# Risposte dei magazzini per edificio e risorsa (2026-10-28: con i magazzini pieni ~3–4 ms per risorsa, 99 edifici
# guardati a ogni giro): WarehouseSelectionService.any_accepts le riusa finché la firma di quell'edificio non cambia, al
# più WarehouseSelectionService.ANSWER_MSEC. id edificio -> {"signature", "msec", "answers"}.
static var _storage_answers_by_building: Dictionary = {}


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if not UserOptions.job_board_collect_piles:
		return jobs
	# Tempi (2026-10-28): "mucchi: chi li ha", ": consegne", ": righe", ": svuotati".
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	var claims := collect_claims(ctx.individuals, ctx.game_data)
	if timing:
		JobBoardTimingService.add("mucchi: chi li ha", started)
	started = JobBoardTimingService.now() if timing else 0
	var job_delivery_keys := collect_job_delivery_keys(ctx.individuals, ctx.game_data)
	if timing:
		JobBoardTimingService.add("mucchi: consegne", started)
	started = JobBoardTimingService.now() if timing else 0
	var memory := ctx.game_data.job_board_runtime.pile_job_memory
	var listed_keys: Dictionary = {}
	var building_signatures := _building_signatures(ctx.world)
	for building_id in _storage_answers_by_building.keys():
		if not building_signatures.has(building_id):
			_storage_answers_by_building.erase(building_id)
	var storage_by_resource: Dictionary = {}
	for pile in ctx.game_data.ground_piles:
		if pile.resources.is_empty() or not pile.carcasses.is_empty():
			continue
		var key := claim_key(pile.macro_coords, pile.microcell)
		# Mucchio consegnato come parte di un taglio o di un'estrazione in corso, o che una demolizione appena finita deve
		# ancora accodare (2026-10-09): non è un lavoro "Mucchio", resta solo la riga del lavoro vero. Interrotto quel
		# lavoro, torna qui. La consegna dopo una demolizione, una volta accodata, è un lavoro "Mucchio" (la demolizione è
		# finita, non ha più una riga).
		if job_delivery_keys.has(key):
			continue
		var is_assigned := claims.has(key)
		var part_started := JobBoardTimingService.now() if timing else 0
		var pile_name := job_name(pile)
		if timing:
			JobBoardTimingService.add("mucchi: righe, nome", part_started)
			part_started = JobBoardTimingService.now()
		var blocked_reason := "" if is_assigned or has_storage(ctx.world, pile, storage_by_resource, building_signatures) else GameContext.tr_text("task_assignment_pile_no_storage")
		if timing:
			JobBoardTimingService.add("mucchi: righe, magazzino", part_started)
		listed_keys[key] = true
		memory[key] = {"id": pile.id, "name": pile_name, "macro": pile.macro_coords, "microcell": pile.microcell}
		jobs.append({
			"key": "pile:%d" % pile.id, "kind": "pile", "name": pile_name, "text": pile_name, "log_name": "mucchio #%d" % pile.id,
			"icon": {"command": "pickup"}, "macro": pile.macro_coords, "microcell": pile.microcell,
			"reach_target": {
				"macro_x": pile.macro_coords.x, "macro_y": pile.macro_coords.y, "micro_x": pile.microcell.x, "micro_y": pile.microcell.y,
			},
			"entry_kind": "ground_pile", "id": pile.id, "sort": float(pile.id) + SORT_OFFSET,
			"assigned": is_assigned, "hidden": false,
			"blocked_reason": blocked_reason,
			"target": pile, "provider": provider, "claimers": claims.get(key, []),
		})
	if timing:
		JobBoardTimingService.add("mucchi: righe (%d mucchi)" % ctx.game_data.ground_piles.size(), started)
	started = JobBoardTimingService.now() if timing else 0
	jobs.append_array(_emptied_pile_jobs(ctx, provider, listed_keys))
	if timing:
		JobBoardTimingService.add("mucchi: svuotati", started)
	return jobs


# Mucchio svuotato dall'ultima raccolta con la consegna ancora in corso (2026-10-09): la riga "Mucchio" resta in "In corso"
# (stessa chiave e stesso testo di quando era elencato, stesso individuo) finché chi porta il carico non l'ha consegnato;
# poi sparisce. Vale per i mucchi presi dalla coda e per la consegna dopo una demolizione (is_board_pile_task).
static func _emptied_pile_jobs(ctx: GameContext, provider: Dictionary, listed_keys: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	var memory := ctx.game_data.job_board_runtime.pile_job_memory
	var existing: Dictionary = {}
	for pile in ctx.game_data.ground_piles:
		if not pile.resources.is_empty():
			existing[claim_key(pile.macro_coords, pile.microcell)] = true
	var carriers: Dictionary = {}
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if not is_board_pile_task(task):
				continue
			var key := board_pile_task_claim_key(task)
			if key == "" or listed_keys.has(key) or existing.has(key) or not memory.has(key):
				continue
			if not carriers.has(key):
				carriers[key] = []
			if not (carriers[key] as Array).has(member):
				(carriers[key] as Array).append(member)
	for key in memory.keys():
		if not listed_keys.has(key) and not carriers.has(key):
			memory.erase(key)
	for key in carriers:
		var remembered: Dictionary = memory[key]
		var macro: Vector2i = remembered["macro"]
		var microcell: Vector2i = remembered["microcell"]
		var first_carrier := (carriers[key] as Array)[0] as HumanIndividual
		jobs.append({
			"key": "pile:%d" % int(remembered["id"]), "kind": "pile", "name": String(remembered["name"]), "text": String(remembered["name"]),
			"log_name": "mucchio #%d (svuotato, consegna in corso)" % int(remembered["id"]),
			"icon": {"command": "pickup"}, "macro": macro, "microcell": microcell,
			"reach_target": {"macro_x": macro.x, "macro_y": macro.y, "micro_x": microcell.x, "micro_y": microcell.y},
			# Clic sulla riga: il mucchio non c'è più, si seleziona chi porta il carico.
			"entry_kind": "individual", "id": first_carrier.id, "sort": float(int(remembered["id"])) + SORT_OFFSET,
			"assigned": true, "hidden": false, "blocked_reason": "",
			"target": null, "emptied_pile_key": key, "provider": provider, "claimers": carriers[key],
		})
	return jobs


# Idoneità alla presa: la consegna di prova (TaskBuilderService.build_pile_job_task, mai assegnata) passa il controllo di
# idoneità, e dal pipottino un magazzino raggiungibile accetta almeno una risorsa che gli entra a carico vuoto (lo stesso
# controllo della consegna automatica). Mucchio in una macrocella non viva: non raggiungibile.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	if not (job["target"] is GroundPile):
		return "mucchio svuotato"
	var pile: GroundPile = job["target"]
	var macro_state: MacroCellState = null
	if ctx.live_cells.has(pile.macro_coords):
		macro_state = ctx.world.get_cell_state_at(pile.macro_coords.x, pile.macro_coords.y)
	var task := TaskBuilderService.build_pile_job_task(worker, pile, macro_state)
	if task == null:
		return "mucchio non raggiungibile"
	var assign_rejection := worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))
	if assign_rejection != HumanIndividual.ASSIGN_OK:
		return assign_rejection
	var reachable := PathfindingService.reachability_for(worker)
	for resource_name in pile.get_resource_names():
		if pile.get_quantity(resource_name) > 0 and worker.can_carry_one_unit_when_empty(resource_name) \
				and WarehouseSelectionService.find_best(ctx.world, worker.position, worker.home_macro_coords, resource_name, 1, [], reachable) != null:
			return HumanIndividual.ASSIGN_OK
	return "nessun magazzino raggiungibile"


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result


# Ritiro di un mucchio come lavoro della coda: lavoro "Mucchio" preso dalla lista (zona "fino a vuoto" sul mucchio senza
# etichetta di lavoro) o consegna dopo una demolizione (HaulZoneService.JOB_DELIVERY_KEY senza etichetta di lavoro). Le
# consegne di taglio ed estrazione hanno l'etichetta: fanno parte del loro lavoro (ordine del cassetto o comando diretto).
static func is_board_pile_task(task: Task) -> bool:
	var zone := HaulZoneService.get_zone(task.context)
	if not zone.is_empty() and HaulZoneService.get_label_task_name(zone) != "":
		return false
	if bool(task.context.get(HaulZoneService.JOB_DELIVERY_KEY, false)):
		return true
	return not zone.is_empty() and HaulZoneService.get_source_kind(zone) == PickUpAction.SourceKind.GROUND_PILE \
			and HaulZoneService.is_until_empty(zone)


# Chiave del mucchio di un ritiro della coda (is_board_pile_task), anche a mucchio sparito: la zona 1×1 sul mucchio, o
# lo step di raccolta dal mucchio (anche già fatto). "" se nessuna.
static func board_pile_task_claim_key(task: Task) -> String:
	var zone := HaulZoneService.get_zone(task.context)
	if not zone.is_empty():
		return claim_key(
			Vector2i(int(zone.get("macro_x", 0)), int(zone.get("macro_y", 0))), Vector2i(int(zone.get("rect_x", 0)), int(zone.get("rect_y", 0)))
		)
	for step in task.steps:
		if step is PickUpAction and (step as PickUpAction).source_kind == PickUpAction.SourceKind.GROUND_PILE:
			var pickup := step as PickUpAction
			var macro := Vector2i(pickup.macro_state.x, pickup.macro_state.y) if pickup.macro_state != null else Vector2i.ZERO
			return claim_key(macro, pickup.target_position)
	return ""


# "Mucchio · Rametti, Pietre…": le prime due risorse contenute, con i puntini se ce ne sono altre.
static func job_name(pile: GroundPile) -> String:
	var names := pile.get_resource_names()
	var shown: Array[String] = []
	for resource_name in names.slice(0, 2):
		shown.append(IconRegistry.get_resource_display_name(resource_name))
	return GameContext.tr_text("pending_pile").format({"resources": ", ".join(shown) + ("…" if names.size() > 2 else "")})


static func claim_key(macro_coords: Vector2i, microcell: Vector2i) -> String:
	return "%d:%d:%d:%d" % [macro_coords.x, macro_coords.y, microcell.x, microcell.y]


# Chi ha in carico quale mucchio: microcella del mucchio (claim_key) -> Array[HumanIndividual]. Un pipottino ha in carico
# un mucchio se una sua task, in corso o in coda e non conclusa:
#   - ha ancora da fare (dal passo corrente in poi) un raccogli (PickUpAction) con sorgente "mucchio" su quella
#     microcella (clic destro, consegna dopo una demolizione, consegna presa dalla lista);
#   - porta nel context una zona di raccolta con sorgente "mucchio" che la contiene (HaulZoneService.CONTEXT_KEY): è il
#     caso delle consegne "fino a mucchio vuoto" e delle serie di taglio o estrazione — tra uno scarico e il viaggio
#     successivo il viaggio dopo è già in coda con la stessa zona, quindi il mucchio resta suo;
#   - ha nel context la consegna ancora da accodare (HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL),
#     chiesta da un taglio/estrazione/demolizione appena finiti.
static func collect_claims(individuals: Array[HumanIndividual], game_data: GameData) -> Dictionary:
	var claims: Dictionary = {}
	for member in individuals:
		var tasks: Array = []
		if member.current_task != null and not member.current_task.is_finished():
			tasks.append(member.current_task)
		tasks.append_array(member.task_queue)
		for raw_task in tasks:
			var task := raw_task as Task
			if task == null or task.is_finished():
				continue
			for key in task_claim_keys(task, game_data):
				if not claims.has(key):
					claims[key] = []
				if not (claims[key] as Array).has(member):
					(claims[key] as Array).append(member)
	return claims


# Mucchi (chiavi di claim_key) portati via come parte di un lavoro in corso: una task, in corso o in coda, che ha ancora
# da accodare la consegna (taglio, estrazione o demolizione appena finiti, CONTEXT_PENDING_GROUND_PILE_HAUL), oppure è la
# consegna di un taglio o di un'estrazione (zona con l'etichetta del lavoro). La consegna dopo una demolizione
# (HaulZoneService.JOB_DELIVERY_KEY senza etichetta, 2026-10-09) no: la demolizione è già finita e senza riga, il mucchio
# resta un lavoro "Mucchio" con il portatore tra chi lo fa (mai una riga "Diretto").
static func collect_job_delivery_keys(individuals: Array[HumanIndividual], game_data: GameData) -> Dictionary:
	var keys: Dictionary = {}
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			var is_job_delivery := false
			var zone := HaulZoneService.get_zone(task.context)
			if not zone.is_empty() and HaulZoneService.get_label_task_name(zone) != "":
				is_job_delivery = true
			var pending: Variant = task.context.get(HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL, null)
			if pending is Dictionary:
				var pending_ref := pending as Dictionary
				keys[claim_key(
					Vector2i(int(pending_ref.get("macro_x", 0)), int(pending_ref.get("macro_y", 0))),
					Vector2i(int(pending_ref.get("micro_x", 0)), int(pending_ref.get("micro_y", 0)))
				)] = true
			if is_job_delivery:
				for key in task_claim_keys(task, game_data):
					keys[key] = true
	return keys


static func task_claim_keys(task: Task, game_data: GameData) -> Array[String]:
	var keys: Array[String] = []
	for step_index in range(task.current_step_index, task.steps.size()):
		var step: Action = task.steps[step_index]
		if step is PickUpAction and (step as PickUpAction).source_kind == PickUpAction.SourceKind.GROUND_PILE:
			var pickup := step as PickUpAction
			var macro := Vector2i(pickup.macro_state.x, pickup.macro_state.y) if pickup.macro_state != null else Vector2i.ZERO
			keys.append(claim_key(macro, pickup.target_position))
	var zone := HaulZoneService.get_zone(task.context)
	if not zone.is_empty() and int(zone.get("source_kind", -1)) == PickUpAction.SourceKind.GROUND_PILE:
		var zone_macro := Vector2i(int(zone.get("macro_x", 0)), int(zone.get("macro_y", 0)))
		var rect := Rect2i(int(zone.get("rect_x", 0)), int(zone.get("rect_y", 0)), int(zone.get("rect_w", 0)), int(zone.get("rect_h", 0)))
		for pile in game_data.ground_piles:
			if pile.macro_coords == zone_macro and rect.has_point(pile.microcell):
				keys.append(claim_key(pile.macro_coords, pile.microcell))
	var pending: Variant = task.context.get(HumanIndividualActionService.CONTEXT_PENDING_GROUND_PILE_HAUL)
	if pending is Dictionary:
		var pile_ref := pending as Dictionary
		keys.append(claim_key(
			Vector2i(int(pile_ref.get("macro_x", 0)), int(pile_ref.get("macro_y", 0))),
			Vector2i(int(pile_ref.get("micro_x", 0)), int(pile_ref.get("micro_y", 0)))
		))
	return keys


# id edificio -> WarehouseSelectionService.building_signature, una volta per giro dei mucchi.
static func _building_signatures(world: World) -> Dictionary:
	var signatures: Dictionary = {}
	if world == null:
		return signatures
	for building in world.buildings:
		signatures[building.id] = WarehouseSelectionService.building_signature(building)
	return signatures


# Almeno una risorsa del mucchio ha un magazzino che la accetta, cercato dalla posizione del mucchio (nessun pipottino,
# nessun controllo di raggiungibilità: quello si rifà alla presa, rejection).
# by_resource (2026-10-28, 40–70 ms con tanti mucchi): risposte per nome della risorsa, condivise tra i mucchi di un giro.
# Senza raggiungibilità né limite di distanza la risposta non dipende dalla posizione del mucchio: basta
# WarehouseSelectionService.any_accepts (stessa risposta di find_best != null, un giro solo).
# building_signatures (2026-10-28): con le firme degli edifici, le risposte per edificio dalla memoria del fornitore.
static func has_storage(world: World, pile: GroundPile, by_resource: Dictionary = {}, building_signatures: Dictionary = {}) -> bool:
	for resource_name in pile.get_resource_names():
		if pile.get_quantity(resource_name) <= 0:
			continue
		if not by_resource.has(resource_name):
			by_resource[resource_name] = WarehouseSelectionService.any_accepts(
				world, resource_name, building_signatures, _storage_answers_by_building if not building_signatures.is_empty() else null
			)
		if bool(by_resource[resource_name]):
			return true
	return false
