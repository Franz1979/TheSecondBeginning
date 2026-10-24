class_name DrawerOrderJobProvider
extends RefCounted

# Fornitore "ordini del cassetto" della lista dei lavori (2026-10-09; spostato da GameScene il 2026-10-17, refactoring
# GameScene blocco 2c): un lavoro per voce di GameData.drawer_orders, chiave "order:<id>". "Produci" (tipo produce,
# edificio scelto al momento: DrawerOrderService.choose_produce_building), ordini di zona (taglio, estrazione, raccolta,
# caccia) e ordini "transport" del gestore scorte. Qui la parte di regola (quali lavori, chi può prenderli, chi ci
# lavora); presa, X e Rimetti in coda restano alla scena.
# Gli ordini "transport" (essiccatoio, combustibile) li crea il gestore delle scorte (WarehouseManagerService): destinazione,
# sorgente e quantità si scelgono al momento (WarehouseManagerService.transport_order_pick).


static func collect(ctx: GameContext, provider: Dictionary, assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data.drawer_orders.is_empty():
		return jobs
	var busy_counts: Dictionary = {}
	for claimed_key in assigned["produce"].keys():
		var building_id := int(String(claimed_key).get_slice(":", 0))
		busy_counts[building_id] = int(busy_counts.get(building_id, 0)) + 1
	var zone_claims := DrawerOrderService.collect_zone_claims(ctx.individuals)
	for order in ctx.game_data.drawer_orders:
		# Ordini decisi da un inventario ancora in corso (2026-10-11): escono alla fine del conteggio.
		if bool(order.get(StockRequestService.INVENTORY_PENDING_KEY, false)):
			continue
		var order_type := String(order.get("type", ""))
		if DrawerOrderService.is_zone_order_type(order_type):
			jobs.append(_zone_job(ctx, provider, order, zone_claims))
			continue
		if order_type == DrawerOrderService.TYPE_TRANSPORT:
			jobs.append(_transport_job(ctx, provider, order))
			continue
		if order_type != DrawerOrderService.TYPE_PRODUCE:
			continue
		jobs.append(_produce_job(ctx, provider, order, busy_counts))
	return jobs


static func _produce_job(ctx: GameContext, provider: Dictionary, order: Dictionary, busy_counts: Dictionary) -> Dictionary:
	var order_id := int(order["id"])
	var recipe := String(order.get("recipe", ""))
	var quantity := maxi(int(order.get("quantity", 1)), 1)
	# Ordine scalzato legato alla sua postazione (2026-10-23, ProductionEvictionService.EVICTED_FROM_KEY): solo lì.
	var bound := ProductionEvictionService.bound_building(ctx.world, order)
	var building := DrawerOrderService.choose_produce_building(ctx.world, recipe, quantity, busy_counts, false, bound)
	# Nessun posto libero (2026-10-23, ProductionEvictionService): si prende il posto di un ordine in attesa di materiali,
	# salvo per un ordine già scalzato (anti ping-pong: solo posti liberi).
	var evict: Dictionary = {}
	if building == null and not order.has(ProductionEvictionService.EVICTED_KEY):
		evict = ProductionEvictionService.find_evictable(ctx.world, ctx.individuals, recipe, quantity)
		if not evict.is_empty():
			building = evict["building"]
	var blocked_reason := ""
	if building == null:
		blocked_reason = GameContext.tr_text("drawer_order_waiting_evicted_building").format({
			"building": "%s #%d" % [bound.get_display_name(), bound.id]
		}) if bound != null else WarehouseManagerService.no_building_reason(ctx, recipe)
	# Attrezzo (2026-10-11, stessa regola degli ordini di zona): addosso a qualcuno, nell'Attrezzeria dell'edificio, o da
	# prendere in deposito; altrimenti un edificio la cui Attrezzeria lo copra; nessuno = "Nessuno ha <attrezzo>".
	if building != null:
		var tool_reason := ToolFetchService.blocked_reason(
			ctx, BuildingToolkitService.filter_uncovered(building, ToolFetchService.recipe_tool_categories(recipe)), DrawerOrderService.TYPE_PRODUCE
		)
		if tool_reason != "":
			var covering := DrawerOrderService.choose_produce_building(ctx.world, recipe, quantity, busy_counts, true, bound)
			if covering != null:
				building = covering
				evict = {}
			else:
				blocked_reason = tool_reason
	# Ordine del magazzino: dal 2026-10-23 (richiesta utente — una regola sola con la costruzione) i materiali mancanti non lo
	# bloccano più. Si assegna come un cantiere: chi lo prende porta i materiali man mano e, se non ce ne sono in nessun
	# magazzino, va in pausa nella coda personale e riparte quando arrivano. "Mancano: …" (MISSING_KEY) resta per la
	# campanella.
	var from_warehouse := order.has(StockRequestService.ORDER_KEY)
	var row_name := GameContext.tr_text("drawer_order_produce_row").format({"recipe": IconRegistry.get_resource_display_name(recipe), "quantity": quantity})
	var building_text := (" @ %s #%d" % [building.building_type_name, building.id]) if building != null else ""
	return {
		"key": JobBoardService.drawer_order_key(order_id), "kind": "produce", "name": row_name, "text": row_name,
		"log_name": "ordine del cassetto #%d %s ×%d%s" % [order_id, recipe, quantity, building_text],
		"icon": {"resource": recipe},
		# Nessun posto sulla mappa: macrocella fuori dal mondo = 🎯 spento e nessuna icona lampeggiante.
		"macro": Vector2i(-1, -1), "microcell": Vector2i(-1, -1), "reach_target": building,
		"entry_kind": "drawer_order", "id": order_id, "sort": float(order_id) + DrawerOrderService.PRODUCE_JOB_SORT_OFFSET,
		"assigned": false, "hidden": false, "warehouse": from_warehouse,
		"blocked_reason": blocked_reason,
		"target": building, "provider": provider, "order": order, "recipe": recipe, "quantity": quantity,
		# Ordine in attesa da scalzare alla presa ({} se c'è un posto libero), vedi ProductionEvictionService.
		"evict": evict,
	}


# Riga di un ordine "transport" del magazzino: "Porta N <risorsa> all'essiccatoio" o "… combustibile a <edificio>", sulla
# destinazione scelta adesso; non prendibile se nessuna destinazione con posto o nessuna sorgente.
static func _transport_job(ctx: GameContext, provider: Dictionary, order: Dictionary) -> Dictionary:
	var order_id := int(order["id"])
	var pick := WarehouseManagerService.transport_order_pick(ctx.world, null, order)
	var target: Building = pick.get("target", null)
	var is_fuel := order.has(FuelStockService.FUEL_TARGET_KEY)
	var resource_name := String(pick.get("resource", order.get("resource", "")))
	var quantity := int(pick.get("quantity", order.get("quantity", 1)))
	var row_name := GameContext.tr_text("drawer_order_dry_row").format({"quantity": quantity, "resource": IconRegistry.get_resource_display_name(resource_name)})
	var is_waste := order.has(WarehouseManagerService.STOCK_WASTE_KEY)
	var is_toolkit := order.has(ToolkitStockService.TOOLKIT_TARGET_KEY)
	# Attrezzeria (2026-10-18): "Legnaia: porta 2 Asce".
	if is_toolkit:
		var toolkit_target := WarehouseManagerService.find_building(ctx.world, int(order[ToolkitStockService.TOOLKIT_TARGET_KEY]))
		row_name = GameContext.tr_text("drawer_order_toolkit_row").format({
			"quantity": quantity, "resource": IconRegistry.get_resource_display_name(resource_name),
			"building": toolkit_target.get_display_name() if toolkit_target != null else "",
		})
	# Eccedenza da buttare (2026-10-18): "Buttare · 70 Rametti".
	if is_waste:
		row_name = GameContext.tr_text("drawer_order_waste_row").format({"quantity": quantity, "resource": IconRegistry.get_resource_display_name(resource_name)})
	var icon: Dictionary = {"resource": resource_name}
	if is_fuel:
		var fuel_target := WarehouseManagerService.find_building(ctx.world, int(order[FuelStockService.FUEL_TARGET_KEY]))
		var fuel_quantity: Variant = quantity
		var fuel_resource := IconRegistry.get_resource_display_name(resource_name)
		# Bloccato (2026-10-19, richiesta utente): nessun combustibile scelto, quindi la quantità vera dell'ordine (in
		# fuel_value) e "combustibile" con il fuoco, invece di una risorsa vuota con quantità 1.
		if pick.is_empty():
			fuel_quantity = String.num(snappedf(float(order.get(FuelStockService.FUEL_AMOUNT_KEY, 0.0)), 0.1))
			fuel_resource = GameContext.tr_text("pending_material_fuel")
			icon = {"text": "🔥"}
		row_name = GameContext.tr_text("drawer_order_fuel_row").format({
			"quantity": fuel_quantity, "resource": fuel_resource,
			"building": fuel_target.get_display_name() if fuel_target != null else "",
		})
	return {
		"key": JobBoardService.drawer_order_key(order_id), "kind": "pile", "name": row_name, "text": row_name,
		"log_name": "ordine del cassetto #%d trasporto: %d %s" % [order_id, quantity, resource_name],
		"icon": icon,
		"macro": Vector2i(target.macro_x, target.macro_y) if target != null else Vector2i(-1, -1),
		"microcell": Vector2i(target.micro_x, target.micro_y) if target != null else Vector2i(-1, -1), "reach_target": target,
		"entry_kind": "drawer_order", "id": order_id, "sort": float(order_id) + DrawerOrderService.PRODUCE_JOB_SORT_OFFSET,
		"assigned": false, "hidden": false, "warehouse": order.has(StockRequestService.ORDER_KEY),
		"blocked_reason": "" if not pick.is_empty() else GameContext.tr_text(
			"pending_stock_waste_blocked" if is_waste else ("pending_stock_toolkit_blocked" if is_toolkit else ("pending_stock_fuel_blocked" if is_fuel else "pending_stock_dry_blocked"))
		),
		"target": target, "provider": provider, "order": order,
	}


# Idoneità di un ordine "transport": la Transport Task di prova (deposito → destinazione) passa il controllo di età/energia.
static func transport_rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var order: Dictionary = job["order"]
	var pick := WarehouseManagerService.transport_order_pick(ctx.world, worker, order)
	if pick.is_empty():
		return "nessuna destinazione con posto o nessuna sorgente raggiungibile"
	var task := WarehouseManagerService.transport_order_task(worker, order, pick)
	if task == null:
		return "nessun posto nella destinazione"
	return worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))


# Riga di un ordine di zona: "Taglia N piante · …" / "Estrai N pietre · …" con "Zona automatica" o il nome della zona,
# icona del lavoro; 🎯 sulla zona fissata.
static func _zone_job(ctx: GameContext, provider: Dictionary, order: Dictionary, claims: Dictionary) -> Dictionary:
	var order_type := String(order.get("type", DrawerOrderService.TYPE_CUT))
	var is_quarry := order_type == DrawerOrderService.TYPE_QUARRY
	var order_id := int(order["id"])
	var zone_id := int(order.get("zone_id", -1))
	var area: WorkArea = WorkAreaService.find_by_id(ctx.game_data, zone_id) if zone_id >= 0 else null
	var claim: Dictionary = claims.get(order_id, {})
	var is_assigned := bool(order.get("taken", false)) and not claim.is_empty()
	var remaining := maxi(int(order.get("count", 1)) - (int(claim.get("done", 0)) if is_assigned else 0), 1)
	# Riga (2026-10-09): appena creato "<quanti>"; una volta preso, l'avanzamento dell'ordine intero "fatti/totale" (anche
	# attraverso interruzioni e riprese da altri). Zona: solo quella scelta dal giocatore.
	var total := DrawerOrderService.order_total(order)
	var done := int(order.get("done_before", 0)) + (int(claim.get("done", 0)) if is_assigned else 0)
	# La carne consegnata può superare l'obiettivo (l'ultima preda porta tutta la sua); gli altri tipi no.
	if order_type != DrawerOrderService.TYPE_HUNT:
		done = mini(done, total)
	var started := bool(order.get("started", false)) or is_assigned or done > 0
	var row_key := "drawer_order_quarry_row" if is_quarry else "drawer_order_cut_row"
	var icon_key := "quarry" if is_quarry else "cut"
	var row_args := {"count": total, "done": done, "total": total}
	if order_type == DrawerOrderService.TYPE_GATHER:
		row_key = "drawer_order_gather_row"
		row_args["target"] = gather_target_text(order)
		icon_key = "pickup"
	elif order_type == DrawerOrderService.TYPE_HUNT:
		row_key = "drawer_order_hunt_row"
		icon_key = "hunt"
	# Avviato (2026-10-11): il nome senza conto, "fatti/totale" va nella seconda riga della voce ("progress").
	var progress := ""
	if started:
		row_key = row_key.replace("_row", "_started_row")
		progress = "%d/%d" % [done, total]
	elif total == 1:
		row_key += "_one"
	var row_name := GameContext.tr_text(row_key).format(row_args)
	if zone_id >= 0:
		row_name = GameContext.tr_text("drawer_order_zone_suffix").format({
			"row": row_name, "zone": area.name if area != null else GameContext.tr_text("drawer_cut_zone_gone"),
		})
	var macro := Vector2i(-1, -1)
	var microcell := Vector2i(-1, -1)
	if area != null:
		macro = area.macro_coords
		microcell = area.rect.position + area.rect.size / 2
	# Ordine creato dal magazzino (2026-10-11): magazzino nell'angolo dell'icona della riga.
	var from_warehouse := order.has(StockRequestService.ORDER_KEY)
	# Prima della voce: per taglio/estrazione sceglie anche il bersaglio dell'ordine, letto da reach_target.
	var blocked_reason := "" if is_assigned else zone_blocked_reason(ctx, order_type, zone_id, area, order)
	return {
		"key": JobBoardService.drawer_order_key(order_id), "kind": order_type, "name": row_name,
		"warehouse": from_warehouse, "progress": progress,
		"text": (row_name + "\n" + GameContext.tr_text("task_assignment_warehouse_tag_tooltip")) if from_warehouse else row_name,
		"log_name": "ordine del cassetto #%d %s ×%d (%s)" % [order_id, order_type, remaining, "zona automatica" if zone_id < 0 else "zona #%d" % zone_id],
		"icon": {"command": icon_key}, "macro": macro, "microcell": microcell,
		# Raggiungibilità vera nel controllo di idoneità (zona e bersaglio per chi lo prende): qui un bersaglio fuori dalla
		# macrocella, che PathfindingService.reachability_for dà sempre per raggiungibile.
		# Taglio/estrazione (2026-10-23): il bersaglio scelto dall'ordine (DrawerOrderTargetService, scelto in
		# zone_blocked_reason qui sotto), così la raggiungibilità la controlla find_takeable_jobs; senza bersaglio, come prima.
		"reach_target": DrawerOrderTargetService.reach_target(order),
		"entry_kind": "work_area" if area != null else "drawer_order", "id": area.id if area != null else order_id,
		"sort": float(order_id) + float(DrawerOrderService.ZONE_JOB_SORT_OFFSET.get(order_type, 4500000.0)),
		"assigned": is_assigned, "hidden": false,
		"blocked_reason": blocked_reason,
		"target": area, "provider": provider, "order": order,
	}


# Cosa raccogliere, per la riga di "Raccogli": la risorsa, "Tutto il cibo" / "Tutti i materiali" o "Tutto" (gli stessi
# testi del popup).
static func gather_target_text(order: Dictionary) -> String:
	match int(order.get("criterion_kind", PickUpAction.CriterionKind.ALL)):
		PickUpAction.CriterionKind.NAME:
			return IconRegistry.get_resource_display_name(String(order.get("resource_name", "")))
		PickUpAction.CriterionKind.CATEGORY:
			# "ogni cibo" (2026-10-11, richiesta utente) nella riga, al posto di "Tutto il cibo" del popup.
			if int(order.get("criterion_category", -1)) == SecondaryResourceTypes.Category.FOOD:
				return GameContext.tr_text("drawer_order_gather_all_food")
			var keys: Array = PickupChoiceMenu.CATEGORY_TEXT_KEYS.get(int(order.get("criterion_category", -1)), ["", ""])
			if String(keys[1]) != "":
				return GameContext.tr_text(String(keys[1]))
	return GameContext.tr_text("pickup_choice_all")


# Motivo per cui nessuno può prendere l'ordine di zona ora ("" = prendibile): nessuno in età da lavoro con l'attrezzo;
# nessuna zona valida (zona fissata sparita, senza il lavoro o senza piante / rocce / risorse da raccogliere; con la zona
# automatica nessuna zona adatta).
static func zone_blocked_reason(ctx: GameContext, order_type: String, zone_id: int, area: WorkArea, order: Dictionary = {}) -> String:
	var tool_reason := ToolFetchService.blocked_reason(ctx, DrawerOrderService.tool_categories(order_type), order_type)
	if tool_reason != "":
		return tool_reason
	# Taglio/estrazione di un ordine non preso (2026-10-23): valido se l'ordine ha (o trova) il suo bersaglio
	# (DrawerOrderTargetService), invece del giro su tutte le zone.
	if DrawerOrderTargetService.uses_order_target(order_type) and order.has("id") and not bool(order.get("taken", false)):
		return "" if DrawerOrderTargetService.ensure_target(ctx, order) else GameContext.tr_text("drawer_cut_no_valid_zone")
	var areas := DrawerOrderService.zone_areas(ctx.game_data, order_type)
	var reserved := DrawerOrderService.zone_reserved(ctx.individuals, order_type)
	if zone_id >= 0:
		if area == null or not areas.has(area) or not DrawerOrderService.area_has_targets(ctx, order_type, area, null, reserved, order):
			return GameContext.tr_text("drawer_cut_no_valid_zone")
		return ""
	for candidate in areas:
		if DrawerOrderService.area_has_targets(ctx, order_type, candidate, null, reserved, order):
			return ""
	return GameContext.tr_text("drawer_cut_no_valid_zone")


# Zona e bersaglio per `worker` ({"area", "plant"} per il taglio, {"area", "rock"} per l'estrazione, {"area"} per raccolta e
# caccia; {} se nessuno): zona fissata (se ha ancora il lavoro) o automatica (choose_work_area per lui), poi il bersaglio
# come il comando (choose_plant / choose_rock). Solo macrocelle vive.
static func pick_zone_target(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> Dictionary:
	var order: Dictionary = job["order"]
	var order_type := String(order.get("type", DrawerOrderService.TYPE_CUT))
	var zone_id := int(order.get("zone_id", -1))
	var reserved := DrawerOrderService.zone_reserved(ctx.individuals, order_type)
	var area: WorkArea = null
	if zone_id >= 0:
		area = WorkAreaService.find_by_id(ctx.game_data, zone_id)
		if area == null or not DrawerOrderService.zone_areas(ctx.game_data, order_type).has(area):
			return {}
	elif order_type == DrawerOrderService.TYPE_HUNT:
		area = HuntZoneService.choose_work_area(ctx.game_data, worker, ctx.live_cells)
	elif order_type == DrawerOrderService.TYPE_QUARRY:
		area = QuarryZoneService.choose_work_area(ctx.game_data, ctx.world, worker, reserved)
	elif order_type == DrawerOrderService.TYPE_GATHER:
		area = HaulZoneService.choose_work_area(
			ctx.game_data, ctx.world, worker, int(order.get("criterion_kind", PickUpAction.CriterionKind.ALL)),
			int(order.get("criterion_category", -1)), String(order.get("resource_name", ""))
		)
	else:
		area = CutZoneService.choose_work_area(ctx.game_data, ctx.live_cells, worker, reserved, DrawerOrderService.order_cut_yield(order))
	if area == null:
		return {}
	# Caccia: la zona, in una macrocella viva.
	if order_type == DrawerOrderService.TYPE_HUNT:
		return {"area": area} if ctx.live_cells.has(area.macro_coords) else {}
	if order_type == DrawerOrderService.TYPE_GATHER:
		# Zona con qualcosa per la scelta, raggiungibile da lui, in una macrocella viva.
		if not DrawerOrderService.area_has_targets(ctx, order_type, area, worker, reserved, order):
			return {}
		return {"area": area}
	if order_type == DrawerOrderService.TYPE_QUARRY:
		if not ctx.live_cells.has(area.macro_coords):
			return {}
		var macro_state := ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		var rock: Variant = QuarryZoneService.choose_rock(area, macro_state, worker, reserved)
		if rock == null:
			return {}
		return {"area": area, "rock": {"macro_coords": area.macro_coords, "position": rock}}
	var plant := CutZoneService.choose_plant(area, ctx.live_cells, worker, reserved, DrawerOrderService.order_cut_yield(order))
	if plant.is_empty():
		return {}
	return {"area": area, "plant": plant}


# Chiave di prova (JobBoardService.find_takeable_jobs: stessa chiave = stessa idoneità per lo stesso pipottino). Ordini di
# zona (2026-10-23, scatti: il coordinatore rifaceva la stessa scelta di zona e bersaglio per ogni ordine uguale): la
# forma dell'ordine, cioè i soli campi letti da zone_rejection — tipo, zona, scelta della raccolta e viaggi, risorsa
# voluta del taglio. Gli altri ordini: la loro chiave, come prima.
static func probe_key(job: Dictionary) -> String:
	var order: Dictionary = job["order"]
	var order_type := String(order.get("type", ""))
	if not DrawerOrderService.is_zone_order_type(order_type):
		return String(job["key"])
	# Taglio/estrazione (2026-10-23): anche il bersaglio scelto dall'ordine, che entra nella task di prova.
	return "zone|%s|%d|%d|%d|%s|%s|%d|%s" % [
		order_type, int(order.get("zone_id", -1)), int(order.get("criterion_kind", PickUpAction.CriterionKind.ALL)),
		int(order.get("criterion_category", -1)), String(order.get("resource_name", "")), DrawerOrderService.order_cut_yield(order),
		maxi(int(order.get("count", 1)), 1), DrawerOrderTargetService.target_signature(order),
	]


# Idoneità: ordine di zona (zone_rejection), "transport" (transport_rejection), "Produci" come gli ordini dei pannelli — la Produce Task di prova sull'edificio scelto passa il
# controllo di età/energia, e ogni attrezzo che l'Attrezzeria di quell'edificio non copre il pipottino ce l'ha o può
# prenderlo in deposito.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var order: Dictionary = job["order"]
	if DrawerOrderService.is_zone_order_type(String(order.get("type", ""))):
		return zone_rejection(ctx, worker, job)
	if String(order.get("type", "")) == DrawerOrderService.TYPE_TRANSPORT:
		return transport_rejection(ctx, worker, job)
	var building: Building = job["target"]
	if building == null:
		return "nessun edificio libero"
	var quantity := int(job["quantity"])
	var task := TaskBuilderService.build_produce_task(worker, building, String(job["recipe"]), quantity, bool(order.get("deliver_to_warehouse", true)))
	if task == null:
		return "definizione mancante"
	var assign_rejection := worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))
	if assign_rejection != HumanIndividual.ASSIGN_OK:
		return assign_rejection
	var tool_rejection := ToolFetchService.rejection(
		ctx, worker, BuildingToolkitService.filter_uncovered(building, ToolGateService.get_required_categories(task)), DrawerOrderService.TYPE_PRODUCE
	)
	return tool_rejection if tool_rejection != "" else HumanIndividual.ASSIGN_OK


# Idoneità per un ordine di zona, come il comando Taglia / Estrai / Raccogli / Caccia: età, attrezzi (addosso, oppure da
# prendere in deposito se nessuno li ha), una zona e un bersaglio per lui, e la task di prova passa il controllo di
# età/energia.
static func zone_rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var order: Dictionary = job["order"]
	var order_type := String(order.get("type", DrawerOrderService.TYPE_CUT))
	var age_band := ctx.age_band_of(worker)
	if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD:
		return HumanIndividual.ASSIGN_REJECT_TOO_YOUNG
	var categories := DrawerOrderService.tool_categories(order_type)
	var tool_rejection := ToolFetchService.rejection(ctx, worker, categories, order_type)
	if tool_rejection != "":
		return tool_rejection
	# Caccia con l'equipaggiamento già addosso: coltello in cintura, o nello zaino con posto in cintura.
	if order_type == DrawerOrderService.TYPE_HUNT and ToolFetchService.member_missing_categories(worker, categories).is_empty() \
			and HuntZoneService.get_hunt_rejection(worker) != "":
		return "coltello o arma mancanti, o cintura piena"
	# Taglio/estrazione (2026-10-23): il bersaglio scelto dall'ordine (DrawerOrderTargetService), uguale per tutti; la
	# raggiungibilità la controlla find_takeable_jobs con reach_target; raccolta uguale dal 2026-10-24 (assegnatore fase 3).
	# Caccia: zona scelta per lui, come prima.
	var pick := DrawerOrderTargetService.get_pick(ctx, order) if DrawerOrderTargetService.uses_order_target(order_type) \
		else pick_zone_target(ctx, worker, job)
	if pick.is_empty():
		return "nessuna zona valida"
	var area: WorkArea = pick["area"]
	var task: Task = null
	if order_type == DrawerOrderService.TYPE_GATHER:
		var trips := maxi(int(order.get("count", 1)), 1)
		var zone := HaulZoneService.make_work_area_zone(
			area.id, int(order.get("criterion_kind", PickUpAction.CriterionKind.ALL)), int(order.get("criterion_category", -1)),
			String(order.get("resource_name", "")), maxi(trips - 1, 0)
		)
		task = TaskBuilderService.build_haul_zone_task(zone, trips > 1, 0)
	elif order_type == DrawerOrderService.TYPE_HUNT:
		task = TaskBuilderService.build_hunt_zone_task(area.id)
	elif order_type == DrawerOrderService.TYPE_QUARRY:
		var rock: Dictionary = pick["rock"]
		task = TaskBuilderService.build_quarry_task(worker, rock["macro_coords"], rock["position"], area.id)
	else:
		task = TaskBuilderService.build_cut_task(worker, pick["plant"], area.id)
	if task == null:
		return "definizione mancante"
	return worker.get_assign_rejection_reason(task, age_band)


# "Produci": mai nessuno (alla presa l'ordine diventa un ordine dell'edificio ed esce dall'elenco). Ordini di zona: chi
# porta la serie dell'ordine (lavoro o consegna, in corso o in coda).
static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	var order: Dictionary = job["order"]
	if DrawerOrderService.is_zone_order_type(String(order.get("type", ""))):
		for member in DrawerOrderService.collect_zone_claims(ctx.individuals).get(int(order["id"]), {}).get("members", []):
			result.append(member as HumanIndividual)
	return result
