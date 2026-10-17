class_name DrawerOrderService
extends RefCounted

# Ordini del cassetto "Assegnazione compiti" (2026-10-09; spostati da GameScene il 2026-10-17, refactoring GameScene blocco
# 2c — regole invariate): voci di GameData.drawer_orders, lavori in coda senza destinatario (chiave della lista
# "order:<id>", JobBoardService.drawer_order_key). Una voce per ordine, solo tipi JSON-nativi: {"id": int stabile,
# "type": uno dei TYPE_* qui sotto, ...campi del tipo}. Statico e senza stato: creazione, ricerca, rimozione, chi porta
# gli ordini di zona presi, ritorno in coda, zone e bersagli, scelta dell'edificio di "Produci". Il fornitore della lista
# è DrawerOrderJobProvider; i popup di scelta e la presa vera restano alla scena.
#
# Ordini di zona ("Taglia", "Estrai", "Raccogli", "Caccia"): taglio, estrazione, raccolta o caccia nelle zone di lavoro "a
# chiunque". {"count": quanto resta (piante, pietre, viaggi o carne), "zone_id": zona fissata (-1 = zona automatica),
# "taken": preso da qualcuno, "done_seen": fatti della serie in corso, "total": chiesto all'inizio, "done_before": fatto
# nelle prese precedenti, "started": preso almeno una volta}. Presa: il comando di oggi in silenzio, con l'id dell'ordine
# nella serie (SERIES_KEY); riuscita = ordine "preso" (resta nell'elenco, riga "In corso"). La serie viaggia nel lavoro e
# nella consegna come sempre: chi la porta è al lavoro sull'ordine (collect_zone_claims). Serie finita = ordine tolto.
# Nessuno la porta più (H, interruzione senza ripresa, serie fermata) o "Rimetti in coda" = l'ordine torna in coda con
# quello che resta e la stessa zona (settle_zone_orders, return_order). Interruzione da bisogno (2026-10-09): l'ordine
# resta a chi lo porta, nella sua coda personale, e lo riprende dopo il bisogno come gli altri lavori della lista.

# "Produci" senza edificio: "recipe", "quantity", "deliver_to_warehouse"; l'edificio si sceglie alla presa.
const TYPE_PRODUCE := "produce"
const TYPE_CUT := "cut"
const TYPE_QUARRY := "quarry"
# "Raccogli" (2026-10-09, quarto tipo): campi in più nella voce "criterion_kind", "criterion_category", "resource_name"
# (cosa raccogliere, come il popup) e "count" = viaggi. L'id dell'ordine sta nella zona della raccolta (si duplica a ogni
# viaggio); fatti = viaggi conclusi (ripetizioni già fatte, più quello in corso se la raccolta è avvenuta).
const TYPE_GATHER := "gather"
# "Caccia" (2026-10-09, quinto tipo): "count" = carne da portare a casa (quella che manca, se l'ordine è tornato in
# coda), "butcher_destination" = destinazione dei prodotti scelta alla creazione. L'id dell'ordine sta nella serie di
# carne (HuntZoneService.CONTEXT_MEAT_SERIES), che passa da caccia a macellazione a caccia successiva; fatti = carne
# consegnata ("delivered", può superare l'obiettivo). Fine: carne consegnata fino all'obiettivo
# (HumanIndividualActionService.hunt_zone_series_ended). Uscita senza prede (PatrolAreaAction.PATROL_DAYS_WITHOUT_PREY_LIMIT
# giorni): zona automatica = si cambia zona e, senza più zone da provare, l'ordine finisce con l'avviso "Caccia finita:
# nessuna preda catturata (N/M carne portate)" (2026-10-10; prima tornava in coda); zona scelta = l'ordine finisce, con
# l'avviso "Caccia: nessuna preda in <zona>" nella campanella.
const TYPE_HUNT := "hunt"
# Ordine "transport" (2026-10-16, rinominato da "dry"): il gestore delle scorte chiede di portare una risorsa dal magazzino
# a un edificio (essiccatoio, combustibile).
const TYPE_TRANSPORT := "transport"

# Attrezzi che servono per gli ordini di zona e per i comandi corrispondenti della barra (CommandBar.ACTIONS legge questi):
# caccia = coltello per la macellazione e arma da caccia (dal 2026-10-11 il coltello non è più un'arma), taglio = accetta,
# estrazione = piccone; la raccolta nessuno.
const HUNT_TOOL_CATEGORIES: Array = [TaskTypes.ToolCategory.BUTCHERING, TaskTypes.ToolCategory.HUNTING]
const CUT_TOOL_CATEGORIES: Array = [TaskTypes.ToolCategory.CHOPPING]
const QUARRY_TOOL_CATEGORIES: Array = [TaskTypes.ToolCategory.DIGGING]

# Id dell'ordine del cassetto nella serie (salvato con lei) o nella zona della raccolta.
const SERIES_KEY := "drawer_order_id"
# Marca nel context del ritorno del carico nato togliendo un ordine di zona: fuori dalle righe "Diretto" di "In corso".
const CARGO_KEY := "drawer_order_cargo"
# Ordini "Produci" del cassetto dopo tutti gli altri lavori nell'ordine delle righe.
const PRODUCE_JOB_SORT_OFFSET: float = 4000000.0
# Righe dei tagli, delle estrazioni, delle raccolte e delle cacce dopo quelle di "Produci".
const ZONE_JOB_SORT_OFFSET := {TYPE_CUT: 4500000.0, TYPE_QUARRY: 4700000.0, TYPE_GATHER: 4300000.0, TYPE_HUNT: 4900000.0}


# Taglio, estrazione, raccolta e caccia: ordini su una zona di lavoro.
static func is_zone_order_type(order_type: String) -> bool:
	return order_type == TYPE_CUT or order_type == TYPE_QUARRY or order_type == TYPE_GATHER or order_type == TYPE_HUNT


static func tool_categories(order_type: String) -> Array:
	match order_type:
		TYPE_HUNT:
			return HUNT_TOOL_CATEGORIES
		TYPE_CUT:
			return CUT_TOOL_CATEGORIES
		TYPE_QUARRY:
			return QUARRY_TOOL_CATEGORIES
	return []


static func find(game_data: GameData, order_id: int) -> Dictionary:
	if game_data == null:
		return {}
	for order in game_data.drawer_orders:
		if int(order["id"]) == order_id:
			return order
	return {}


static func remove(game_data: GameData, order_id: int) -> void:
	if game_data == null:
		return
	for index in range(game_data.drawer_orders.size()):
		if int(game_data.drawer_orders[index]["id"]) == order_id:
			game_data.drawer_orders.remove_at(index)
			return


# Nuovo ordine "Produci" nell'elenco del cassetto; ritorna la voce (già in elenco).
static func add_produce_order(game_data: GameData, recipe: String, quantity: int, deliver_to_warehouse: bool, extra: Dictionary = {}) -> Dictionary:
	var order_id := game_data.next_drawer_order_id
	game_data.next_drawer_order_id += 1
	var new_order := {
		"id": order_id, "type": TYPE_PRODUCE, "recipe": recipe, "quantity": maxi(quantity, 1),
		"deliver_to_warehouse": deliver_to_warehouse,
	}
	new_order.merge(extra)
	game_data.drawer_orders.append(new_order)
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] Ordine del cassetto #%d: produci '%s' x%d (porta al deposito: %s)." % [order_id, recipe, quantity, str(deliver_to_warehouse)])
	return new_order


# Nuovo ordine di zona in coda (dal cassetto o dal magazzino); `extra` = campi del tipo. Ritorna la voce (già in elenco).
static func add_zone_order(game_data: GameData, kind: String, count: int, zone_id: int, extra: Dictionary = {}) -> Dictionary:
	var order_id := game_data.next_drawer_order_id
	game_data.next_drawer_order_id += 1
	var new_order := {
		"id": order_id, "type": kind, "count": count, "zone_id": zone_id, "taken": false, "done_seen": 0,
		"total": count, "done_before": 0, "started": false,
	}
	new_order.merge(extra)
	game_data.drawer_orders.append(new_order)
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] Ordine del cassetto #%d: %s ×%d (zona %s)%s." % [
			order_id, kind, count, "automatica" if zone_id < 0 else "#%d" % zone_id,
			(" dal magazzino per %s" % String(extra[StockRequestService.ORDER_KEY])) if extra.has(StockRequestService.ORDER_KEY) else "",
		])
	return new_order


# Campi della voce "Raccogli" dalla scelta del menu (PickupChoiceMenu.get_selected()); vuota = "Tutto".
static func gather_order_fields(choice: Dictionary) -> Dictionary:
	return {
		"criterion_kind": int(choice.get("kind", PickUpAction.CriterionKind.ALL)),
		"criterion_category": int(choice.get("category", -1)),
		"resource_name": String(choice.get("resource_name", "")),
	}


# Totale chiesto all'inizio (ordini salvati prima di "total": quello che resta più quello già fatto).
static func order_total(order: Dictionary) -> int:
	return int(order.get("total", int(order.get("count", 1)) + int(order.get("done_before", 0))))


# Serie di taglio o di estrazione portata da `task` (il lavoro o la sua consegna), o serie di carne della caccia (la caccia
# o la macellazione nata da lei, 2026-10-09); {} se nessuna.
static func task_zone_series(task: Task) -> Dictionary:
	if task == null:
		return {}
	var series := CutZoneService.get_series(task.context)
	if series.is_empty():
		series = CutZoneService.get_delivery_series(task)
	if series.is_empty():
		series = QuarryZoneService.get_series(task.context)
	if series.is_empty():
		series = QuarryZoneService.get_delivery_series(task)
	if series.is_empty():
		series = HuntZoneService.get_meat_series(task.context)
	return series


# Ordine di zona del cassetto portato da `task` e lavoro fatto: {"order_id", "done"}; {} se nessuno. Taglio ed
# estrazione: dalla serie (il lavoro o la sua consegna). Raccolta: dalla zona della raccolta (viaggi conclusi =
# ripetizioni già fatte, più questo se la raccolta del viaggio è già avvenuta).
static func task_zone_info(task: Task) -> Dictionary:
	if task == null:
		return {}
	var series := task_zone_series(task)
	if not series.is_empty() and series.has(SERIES_KEY):
		# Caccia: fatti = carne consegnata ("delivered").
		return {
			"order_id": int(series[SERIES_KEY]), "done": int(series.get("done", series.get("delivered", 0))),
			"series_id": String(series.get("id", "")),
		}
	var zone := HaulZoneService.get_zone(task.context)
	if not zone.is_empty() and zone.has(SERIES_KEY):
		var done := TaskRepeatRules.get_count(task.context)
		for step_index in range(mini(task.current_step_index, task.steps.size())):
			if task.steps[step_index] is PickUpAction:
				done += 1
				break
		return {"order_id": int(zone[SERIES_KEY]), "done": done}
	return {}


# Id dell'ordine di zona del cassetto portato da `task`; -1 se nessuno.
static func order_of_task(task: Task) -> int:
	return int(task_zone_info(task).get("order_id", -1))


# Chi porta le serie degli ordini di zona: id ordine -> {"members": [HumanIndividual], "done": fatti (il più alto)}.
static func collect_zone_claims(individuals: Array[HumanIndividual]) -> Dictionary:
	var claims: Dictionary = {}
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			var info := task_zone_info(task)
			if info.is_empty():
				continue
			var order_id := int(info["order_id"])
			if not claims.has(order_id):
				claims[order_id] = {"members": [], "done": 0}
			var claim: Dictionary = claims[order_id]
			if not (claim["members"] as Array).has(member):
				(claim["members"] as Array).append(member)
			claim["done"] = maxi(int(claim["done"]), int(info["done"]))
	return claims


# Fatti di una serie con ordine del cassetto: annotati sull'ordine; serie finita = ordine tolto.
static func note_progress(game_data: GameData, series: Dictionary) -> void:
	if not series.has(SERIES_KEY):
		return
	var order := find(game_data, int(series[SERIES_KEY]))
	if order.is_empty() or not bool(order.get("taken", false)):
		return
	order["done_seen"] = maxi(int(order.get("done_seen", 0)), int(series.get("done", 0)))
	if int(series.get("done", 0)) >= int(series.get("target", 0)):
		remove(game_data, int(order["id"]))


# Ordini di zona presi che nessuno porta più: tornano in coda con quello che resta, o spariscono se finiti.
static func settle_zone_orders(ctx: JobBoardContext) -> void:
	if ctx.game_data == null:
		return
	var claims := collect_zone_claims(ctx.individuals)
	for order in ctx.game_data.drawer_orders.duplicate():
		if not is_zone_order_type(String(order.get("type", ""))) or not bool(order.get("taken", false)):
			continue
		var order_id := int(order["id"])
		if claims.has(order_id):
			order["done_seen"] = maxi(int(order.get("done_seen", 0)), int(claims[order_id]["done"]))
			continue
		return_order(ctx, order, true)


# L'ordine di zona torna in coda con quello che resta (o sparisce se finito). `end_if_zone_exhausted` (serie chiusa da
# sola, 2026-10-09): con la zona scelta dal giocatore senza più risorse (o sparita) l'ordine finisce, come il comando
# diretto; con la zona automatica torna in coda (un'altra zona può averla).
static func return_order(ctx: JobBoardContext, order: Dictionary, end_if_zone_exhausted: bool = false) -> void:
	var remaining := int(order.get("count", 1)) - int(order.get("done_seen", 0))
	if remaining <= 0 or (end_if_zone_exhausted and fixed_zone_exhausted(ctx, order)):
		remove(ctx.game_data, int(order["id"]))
		return
	order["total"] = order_total(order)
	order["done_before"] = int(order.get("done_before", 0)) + int(order.get("done_seen", 0))
	order["count"] = remaining
	order["taken"] = false
	order["done_seen"] = 0


# Zone di lavoro con il lavoro del tipo d'ordine.
static func zone_areas(game_data: GameData, order_type: String) -> Array[WorkArea]:
	if order_type == TYPE_HUNT:
		return HuntZoneService.list_hunt_work_areas(game_data)
	if order_type == TYPE_QUARRY:
		return QuarryZoneService.list_quarry_work_areas(game_data)
	if order_type == TYPE_GATHER:
		var areas: Array[WorkArea] = []
		if game_data != null:
			for area in game_data.work_areas:
				if area.enabled_jobs.has(HaulZoneService.HAUL_JOB):
					areas.append(area)
		return areas
	return CutZoneService.list_cut_work_areas(game_data)


# Bersagli già prenotati da altri lavori (rocce o piante); vuoto per raccolta e caccia.
static func zone_reserved(individuals: Array[HumanIndividual], order_type: String) -> Dictionary:
	if order_type == TYPE_QUARRY:
		return QuarryZoneService.collect_reserved_rocks(individuals)
	if order_type == TYPE_GATHER or order_type == TYPE_HUNT:
		return {}
	return CutZoneService.collect_reserved_plants(individuals)


# La zona ha ancora piante (taglio) o rocce con pietra (estrazione) non prenotate, o risorse da raccogliere per la scelta
# dell'ordine `order` (raccolta: criterion_kind/criterion_category/resource_name; senza, "Tutto"); con `individual`,
# raggiungibili da lui. Solo macrocelle vive.
static func area_has_targets(
	ctx: JobBoardContext, order_type: String, area: WorkArea, individual: HumanIndividual, reserved: Dictionary, order: Dictionary = {}
) -> bool:
	if area == null:
		return false
	# Caccia: basta la macrocella viva (le prede si cercano pattugliando, fino a PatrolAreaAction.PATROL_DAYS_WITHOUT_PREY_LIMIT giorni).
	if order_type == TYPE_HUNT:
		return ctx.live_cells.has(area.macro_coords)
	if order_type == TYPE_GATHER:
		if not ctx.live_cells.has(area.macro_coords):
			return false
		var names := HaulZoneService.allowed_names_for(
			area, int(order.get("criterion_kind", PickUpAction.CriterionKind.ALL)), int(order.get("criterion_category", -1)),
			String(order.get("resource_name", ""))
		)
		var gather_state := ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		return HaulZoneService.count_available(area, gather_state, names, individual) > 0
	if order_type == TYPE_QUARRY:
		if not ctx.live_cells.has(area.macro_coords):
			return false
		var macro_state := ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		return not QuarryZoneService.list_available_rocks(area, macro_state, individual, reserved).is_empty()
	return not CutZoneService.list_available_plants(area, ctx.live_cells, individual, reserved, order_cut_yield(order)).is_empty()


# Risorsa voluta da un ordine di taglio del magazzino (solo le piante che la danno, CutZoneService.SERIES_YIELD_KEY); ""
# per gli ordini del giocatore (qualunque pianta ammessa dalla zona).
static func order_cut_yield(order: Dictionary) -> String:
	if String(order.get("type", "")) != TYPE_CUT:
		return ""
	return String(order.get(StockRequestService.ORDER_KEY, ""))


# Zona fissata dell'ordine sparita, senza più il lavoro o senza più risorse (non prenotate, per la scelta dell'ordine);
# macrocella non viva = non si sa, non esaurita.
static func fixed_zone_exhausted(ctx: JobBoardContext, order: Dictionary) -> bool:
	var zone_id := int(order.get("zone_id", -1))
	if zone_id < 0:
		return false
	var order_type := String(order.get("type", TYPE_CUT))
	var area: WorkArea = WorkAreaService.find_by_id(ctx.game_data, zone_id)
	if area == null or not zone_areas(ctx.game_data, order_type).has(area):
		return true
	if not ctx.live_cells.has(area.macro_coords):
		return false
	return not area_has_targets(ctx, order_type, area, null, zone_reserved(ctx.individuals, order_type), order)


# Edificio per un ordine "Produci" del cassetto (lo stesso per ogni pipottino; la vicinanza non conta): tra quelli dove
# ProductionService.can_produce_at vale, che fanno tutta la `quantity` in un ordine (production_max_quantity, 2026-10-09:
# niente più riduzione), non occupati (ordini in lavorazione < production_concurrent_orders), con la coda non piena
# (production_max_orders) e posto in uscita per un ciclo: 1) il più libero (meno ordini, in corso + in coda); 2) a parità,
# se la ricetta chiede un attrezzo, quello la cui Attrezzeria lo copre; 3) a parità, il primo. `busy_counts`: id edificio
# -> ordini in lavorazione (dalle chiavi "id:ordine" di JobWorkScanService.collect_assignments). null se nessuno.
# `covering_only` (2026-10-09): solo gli edifici la cui Attrezzeria copre tutti gli attrezzi della ricetta (quando nessun
# pipottino adulto li ha: altrimenti nessuno potrebbe prendere l'ordine).
static func choose_produce_building(world: World, recipe: String, quantity: int, busy_counts: Dictionary, covering_only: bool = false) -> Building:
	var categories := ToolFetchService.recipe_tool_categories(recipe)
	var best: Building = null
	var best_orders := 0
	var best_covered := false
	for building in world.buildings:
		if not ProductionService.can_produce_at(building, recipe) or ProductionService.get_max_order_quantity(building) < quantity:
			continue
		if ProductionService.has_max_concurrent_orders(building, int(busy_counts.get(building.id, 0))):
			continue
		if ProductionService.has_max_orders(building) or not ProductionService.has_output_room(building, recipe):
			continue
		var orders := building.production_progress.size()
		var covered := not categories.is_empty() and BuildingToolkitService.filter_uncovered(building, categories).is_empty()
		if covering_only and not covered:
			continue
		if best == null or orders < best_orders or (orders == best_orders and covered and not best_covered):
			best = building
			best_orders = orders
			best_covered = covered
	return best
