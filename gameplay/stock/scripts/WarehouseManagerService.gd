class_name WarehouseManagerService
extends RefCounted

# Gestore delle scorte del magazzino (2026-10-11; spostato da GameScene il 2026-10-17, refactoring GameScene blocco 4 — regole
# invariate). Statico; lo stato che vive solo in partita sta in GameData.stock_runtime (StockRuntimeState), gli ordini in
# GameData.drawer_orders (DrawerOrderService). Il magazzino GENERA soltanto: gli ordini li assegna la coda dei lavori.
#
# Magazzino acceso: idea WarehousePanel.REQUIRED_IDEA_ID, coda dei lavori attiva (punto di assegnazione) e almeno un deposito
# (edificio di categoria Stoccaggio completo). Inventario: ogni GameData.inventory_interval_hours ore di gioco dalla fine
# dell'ultimo entra in coda il lavoro "Inventario" (InventoryJobProvider); chi lo prende va al deposito più vicino
# (InventoryAction): all'arrivo il magazzino conta (foto delle scorte in GameData.stock_snapshot) e decide gli ordini
# (on_inventory_started -> request_stock: gli annullamenti subito, i nuovi nascosti con StockRequestService.
# INVENTORY_PENDING_KEY); alla fine del conteggio gli ordini escono in coda (on_inventory_finished).
#
# Ordini decisi: ogni risorsa con un livello minimo (GameData.stock_min_levels) che si procura con raccolta, taglio o
# estrazione (StockRequestService.source_kind_for) e sta sotto il livello genera ordini di zona del cassetto in zona
# automatica, marcati StockRequestService.ORDER_KEY; più caccia, produzione, essiccatoio, combustibile e giorni di cibo,
# ciascuno con la sua regola sotto. Ordini non presi diventati di troppo si tolgono; quelli presi finiscono la loro serie.

const INVENTORY_TASK_NAME := "task_inventory_name"
# Ordini del magazzino appena nati (2026-10-11, contro l'oscillazione): un ordine non preso si toglie come "di troppo" solo
# dopo STOCK_ORDER_MIN_AGE_DAYS di gioco dalla nascita (StockRequestService.CREATED_AT_KEY, salvato con l'ordine); con il
# livello tolto si toglie subito. Chi mangia dal deposito e chi consegna fanno salire e scendere la scorta di continuo.
const STOCK_ORDER_MIN_AGE_DAYS: float = 1.0
# Interruttore delle difese contro l'oscillazione (2026-10-11, prova): con gli ordini decisi solo all'inventario non c'è
# più il ricalcolo continuo che le rendeva necessarie, quindi spente — età minima (_order_too_young) e margine di
# un'unità nel giudizio "di troppo" (_margin). true = comportamento di prima.
const STOCK_ANTI_OSCILLATION: bool = false
# Trasporti del magazzino verso l'essiccatoio: ricetta nel context della Transport Task (pezzi in viaggio, _dry_traveling).
const STOCK_DRY_KEY := "stock_dry_recipe"


# --- Magazzino e inventario ---

static func is_enabled(ctx: GameContext) -> bool:
	if ctx.game_data == null or ctx.world == null or ctx.folk == null:
		return false
	if not ctx.folk.completed_ideas.has(WarehousePanel.REQUIRED_IDEA_ID) or not JobBoardService.is_enabled(ctx.folk):
		return false
	return first_storage_building(ctx.world) != null


static func is_storage_building(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.category == BuildingTypes.Category.STORAGE \
		and building.is_complete and not building.is_demolished and not building.is_out_of_service()


static func first_storage_building(world: World) -> Building:
	for building in world.buildings:
		if is_storage_building(building):
			return building
	return null


static func nearest_storage_building(world: World, worker: HumanIndividual) -> Building:
	return SpatialSelectionService.find_nearest(
		world.buildings, worker.position, worker.home_macro_coords, is_storage_building, [],
		PathfindingService.reachability_for(worker)
	) as Building


# Inventario scaduto: mai fatto, o passate inventory_interval_hours ore dalla fine dell'ultimo.
static func is_inventory_due(game_data: GameData, now: float) -> bool:
	if game_data.last_inventory_end < 0.0:
		return true
	return now >= next_inventory_time(game_data)


static func next_inventory_time(game_data: GameData) -> float:
	return game_data.last_inventory_end + float(game_data.inventory_interval_hours) / 24.0


# Ore di ritardo oltre le quali l'inventario è "in ritardo": un intero intervallo (GameData.inventory_interval_hours).
static func inventory_overdue_hours(game_data: GameData) -> float:
	return float(game_data.inventory_interval_hours)


static func inventory_workers(individuals: Array[HumanIndividual]) -> Array[HumanIndividual]:
	var workers: Array[HumanIndividual] = []
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			if task.task_name == INVENTORY_TASK_NAME:
				workers.append(member)
				break
	return workers


# Ordine del magazzino deciso durante un inventario: nascosto finché il conteggio non finisce.
static func mark_inventory_pending(game_data: GameData, order: Dictionary) -> void:
	var runtime := game_data.stock_runtime
	if runtime.inventory_pending:
		order[StockRequestService.INVENTORY_PENDING_KEY] = true
		runtime.inventory_new_orders += 1


# Inizio del conteggio (InventoryAction.on_started): foto delle scorte e ordini decisi (i nuovi nascosti). Ritorna quanti
# ordini nuovi usciranno alla fine.
static func on_inventory_started(ctx: GameContext, now: float, worker: HumanIndividual, effects: GameEffects) -> int:
	if ctx.game_data == null or ctx.world == null:
		return 0
	var game_data := ctx.game_data
	game_data.stock_snapshot = VillageStockService.get_village_stock(ctx.world)
	game_data.stock_snapshot_fill = VillageStockService.get_storage_fill(ctx.world)
	game_data.stock_snapshot_time = now
	game_data.stock_runtime.inventory_pending = true
	game_data.stock_runtime.inventory_new_orders = 0
	request_stock(ctx, now, effects)
	game_data.stock_runtime.inventory_pending = false
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] Inventario iniziato da %s: %d ordini nuovi da emettere." % [
			worker.name if worker != null else "?", game_data.stock_runtime.inventory_new_orders
		])
	return game_data.stock_runtime.inventory_new_orders


# Fine del conteggio (InventoryAction.on_finished): gli ordini decisi escono in coda, parte l'intervallo per il prossimo.
static func on_inventory_finished(game_data: GameData, now: float, worker: HumanIndividual, effects: GameEffects) -> void:
	if game_data == null:
		return
	var released := 0
	for order in game_data.drawer_orders:
		if order.has(StockRequestService.INVENTORY_PENDING_KEY):
			order.erase(StockRequestService.INVENTORY_PENDING_KEY)
			released += 1
	game_data.last_inventory_end = now
	game_data.last_inventory_by = worker.name if worker != null else ""
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] Inventario finito da %s: %d ordini in coda; prossimo inventario a giorno %.2f." % [
			game_data.last_inventory_by, released, next_inventory_time(game_data)
		])
	effects.refresh_pending()


# --- Creazione degli ordini del magazzino ---

static func _create_zone_order(ctx: GameContext, now: float, kind: String, count: int, zone_id: int, extra: Dictionary) -> void:
	_mark_new_order(ctx.game_data, now, DrawerOrderService.add_zone_order(ctx.game_data, kind, count, zone_id, extra))


static func _create_produce_order(ctx: GameContext, now: float, recipe: String, quantity: int, extra: Dictionary) -> void:
	_mark_new_order(ctx.game_data, now, DrawerOrderService.add_produce_order(ctx.game_data, recipe, quantity, true, extra))


# Ordine appena creato dal magazzino: momento di nascita e, durante un inventario, nascosto finché il conteggio non finisce.
static func _mark_new_order(game_data: GameData, now: float, order: Dictionary) -> void:
	if order.has(StockRequestService.ORDER_KEY):
		order[StockRequestService.CREATED_AT_KEY] = now
		mark_inventory_pending(game_data, order)


# Margine di un'unità contro l'oscillazione: il valore se STOCK_ANTI_OSCILLATION, altrimenti 0.
static func _margin(value: float) -> float:
	return value if STOCK_ANTI_OSCILLATION else 0.0


static func _order_too_young(order: Dictionary, level: float, now: float) -> bool:
	if not STOCK_ANTI_OSCILLATION or level <= 0 or not order.has(StockRequestService.CREATED_AT_KEY):
		return false
	return now - float(order[StockRequestService.CREATED_AT_KEY]) < STOCK_ORDER_MIN_AGE_DAYS


# --- Giro del magazzino ---

# Decide gli ordini (solo all'inizio di un inventario, on_inventory_started): raccolta, taglio ed estrazione per livello,
# poi caccia, produzione, essiccatoio, combustibile e giorni di cibo; aggiorna i nomi da riempire. Con un cambiamento,
# "In sospeso" va ricalcolato (effetto).
static func request_stock(ctx: GameContext, now: float, effects: GameEffects) -> void:
	if ctx.game_data == null or ctx.world == null or ctx.folk == null:
		return
	if not is_enabled(ctx):
		return
	var game_data := ctx.game_data
	var stock := VillageStockService.get_village_stock(ctx.world)
	var claims := DrawerOrderService.collect_zone_claims(ctx.individuals)
	var carry_capacity := average_carry_capacity(ctx)
	# Ordini del magazzino ancora aperti, per risorsa.
	var open_by_resource: Dictionary = {}
	for order in game_data.drawer_orders:
		if order.has(StockRequestService.ORDER_KEY):
			var resource_name := String(order[StockRequestService.ORDER_KEY])
			if not open_by_resource.has(resource_name):
				open_by_resource[resource_name] = []
			(open_by_resource[resource_name] as Array).append(order)
	var names: Array = game_data.stock_min_levels.keys()
	for resource_name in open_by_resource.keys():
		if not names.has(resource_name):
			names.append(resource_name)
	var changed := false
	for resource_name in names:
		var source_kind := StockRequestService.source_kind_for(String(resource_name))
		# Caccia: una domanda sola per carne, pelle, tendini e ossa (_request_hunt); produzione ed essiccatoio a parte.
		if source_kind == "" or source_kind == StockRequestService.SOURCE_HUNT or source_kind == StockRequestService.SOURCE_PRODUCE \
				or source_kind == StockRequestService.SOURCE_DRY:
			continue
		var unit_yield := _unit_yield(String(resource_name), source_kind, carry_capacity)
		var level := int(game_data.stock_min_levels.get(resource_name, 0))
		var quantity := int(stock.get(resource_name, 0))
		var orders: Array = open_by_resource.get(resource_name, [])
		var coverages: Dictionary = {}
		var total_coverage := 0
		var any_taken := false
		for order in orders:
			var coverage := _order_coverage(order, claims, String(resource_name), unit_yield)
			coverages[int(order["id"])] = coverage
			total_coverage += coverage
			any_taken = any_taken or bool(order.get("taken", false))
		# Taglio ed estrazione: la resa cade in un mucchio a terra e arriva al magazzino dopo (consegna della serie). Con un
		# ordine in corso i mucchi della risorsa contano come coperti, altrimenti in quell'attesa nascerebbe un ordine doppio.
		if any_taken and source_kind != StockRequestService.SOURCE_GATHER:
			for pile in game_data.ground_piles:
				total_coverage += pile.get_quantity(String(resource_name))
		# Di troppo: i non presi, dal più nuovo, finché senza di loro il livello resta coperto.
		for index in range(orders.size() - 1, -1, -1):
			var order: Dictionary = orders[index]
			if bool(order.get("taken", false)):
				continue
			var coverage := int(coverages[int(order["id"])])
			if StockRequestService.is_order_surplus(level, quantity, total_coverage, coverage, int(_margin(unit_yield))) \
					and not _order_too_young(order, level, now):
				total_coverage -= coverage
				DrawerOrderService.remove(game_data, int(order["id"]))
				orders.remove_at(index)
				changed = true
				if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
					print("[JOB BOARD] Magazzino: ordine #%d per %s tolto (livello %d coperto)." % [int(order["id"]), resource_name, level])
		var counts := StockRequestService.compute_new_order_counts(
			level, quantity, total_coverage, orders.size(), unit_yield, StockRequestService.get_series_max(source_kind)
		)
		var extra := {StockRequestService.ORDER_KEY: String(resource_name)}
		if source_kind == StockRequestService.SOURCE_GATHER:
			extra["criterion_kind"] = PickUpAction.CriterionKind.NAME
			extra["criterion_category"] = -1
			extra["resource_name"] = String(resource_name)
		# Cibo raccolto (2026-10-11): se adesso non si trova in nessuna zona, nessun ordine né avviso (lo coprono i giorni di
		# autonomia, _request_food_days); gli ordini non presi rimasti fermi si tolgono.
		if is_food(String(resource_name)) and order_blocked_reason(ctx, source_kind, extra) != "":
			for order in orders:
				if not bool(order.get("taken", false)):
					DrawerOrderService.remove(game_data, int(order["id"]))
					changed = true
			continue
		counts = _limit_if_blocked(ctx, counts, orders.size(), source_kind, extra)
		for count in counts:
			_create_zone_order(ctx, now, source_kind, count, -1, extra.duplicate())
			changed = true
	if _request_hunt(ctx, now, stock, claims, open_by_resource.get(StockRequestService.HUNT_GROUP_KEY, [])):
		changed = true
	if _request_produce(ctx, now, stock):
		changed = true
	if _request_dry(ctx, now, stock):
		changed = true
	if _request_fuel(ctx, now):
		changed = true
	if _request_food_days(ctx, now, stock):
		changed = true
	_update_fill_names(ctx, stock)
	if changed:
		effects.refresh_pending()


# Ordine che nascerebbe già bloccato (2026-10-11 — nessuno ha l'attrezzo addosso, nessuna zona valida): un solo ordine per
# risorsa, che fa da avviso in coda e in campanella; nessuno se ce n'è già uno aperto. Sbloccato, al giro dopo il magazzino
# aggiunge quelli che mancano.
static func _limit_if_blocked(ctx: GameContext, counts: Array[int], open_orders: int, order_type: String, extra: Dictionary) -> Array[int]:
	if counts.is_empty() or order_blocked_reason(ctx, order_type, extra) == "":
		return counts
	var limited: Array[int] = []
	if open_orders == 0:
		limited.append(counts[0])
	return limited


# Motivo per cui un ordine del magazzino di tipo `order_type` sarebbe bloccato adesso ("" = prendibile): lo stesso della
# riga del cassetto (DrawerOrderJobProvider.zone_blocked_reason), su un ordine di prova in zona automatica.
static func order_blocked_reason(ctx: GameContext, order_type: String, extra: Dictionary) -> String:
	if order_type == DrawerOrderService.TYPE_PRODUCE:
		return produce_static_reason(ctx, String(extra.get("recipe", "")))
	var probe := {"type": order_type, "zone_id": -1}
	probe.merge(extra)
	return DrawerOrderJobProvider.zone_blocked_reason(ctx, order_type, -1, null, probe)


# --- Caccia ---

# Caccia del magazzino (2026-10-11). Per ogni prodotto della caccia con un livello: scoperto = livello − scorta − in arrivo
# (mucchi e carcasse a terra, con una caccia del magazzino in corso), tradotto in carne (StockRequestService.
# get_meat_per_unit); la domanda è il MASSIMO, perché la stessa preda li dà tutti. Ordini "hunt" in zona automatica da 5 a
# STOCK_HUNT_MAX_MEAT carne, chiave HUNT_GROUP_KEY. Destinazione: carne o pelle che servono = il magazzino (solo lì entrano
# nelle scorte); altrimenti la regola "Carne e pelli in eccesso" (excess_meat_destination). Dopo un ordine finito senza
# prede, pausa fino a StockRuntimeState.hunt_pause_until. true se ha creato o tolto ordini.
static func _request_hunt(ctx: GameContext, now: float, stock: Dictionary, claims: Dictionary, orders: Array) -> bool:
	var game_data := ctx.game_data
	if not ButcherDestinationService.is_available(ButcherDestinationService.WAREHOUSE, ctx.world, ctx.folk):
		return false
	var any_taken := false
	var coverages: Dictionary = {}
	var total_coverage := 0
	for order in orders:
		var coverage := _order_coverage(order, claims, HuntZoneService.MEAT_RESOURCE, 1)
		coverages[int(order["id"])] = coverage
		total_coverage += coverage
		any_taken = any_taken or bool(order.get("taken", false))
	var arriving := _hunt_arriving(game_data) if any_taken else {}
	var demand := 0
	var demand_by_resource: Dictionary = {}
	# Livelli della caccia: quelli del giocatore; la carne cruda = il suo livello (la riserva, 2026-10-16) + quello che nasce
	# dai prodotti che la usano (StockRequestService.DERIVED_LEVEL_RESOURCES, _derived_meat_breakdown).
	var levels := game_data.stock_min_levels.duplicate()
	var own_meat_level := int(levels.get(HuntZoneService.MEAT_RESOURCE, 0))
	var meat_level := own_meat_level + int(_derived_meat_breakdown(ctx, stock)["total"])
	levels.erase(HuntZoneService.MEAT_RESOURCE)
	if meat_level > 0:
		levels[HuntZoneService.MEAT_RESOURCE] = meat_level
	for resource_name in levels.keys():
		if StockRequestService.source_kind_for(String(resource_name)) != StockRequestService.SOURCE_HUNT:
			continue
		var uncovered := int(levels[resource_name]) - int(stock.get(resource_name, 0)) - int(arriving.get(resource_name, 0))
		if uncovered <= 0:
			continue
		var meat := ceili(float(uncovered) * StockRequestService.get_meat_per_unit(String(resource_name)))
		demand_by_resource[resource_name] = meat
		demand = maxi(demand, meat)
	var changed := false
	for index in range(orders.size() - 1, -1, -1):
		var order: Dictionary = orders[index]
		if bool(order.get("taken", false)):
			continue
		var coverage := int(coverages[int(order["id"])])
		if StockRequestService.is_order_surplus(demand, 0, total_coverage, coverage, int(_margin(StockRequestService.HUNT_MEAT_STEP))) \
				and not _order_too_young(order, demand, now):
			total_coverage -= coverage
			DrawerOrderService.remove(game_data, int(order["id"]))
			orders.remove_at(index)
			changed = true
			if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
				print("[JOB BOARD] Magazzino: ordine di caccia #%d tolto (domanda %d carne coperta)." % [int(order["id"]), demand])
	if now < game_data.stock_runtime.hunt_pause_until:
		return changed
	var counts := StockRequestService.compute_new_order_counts(
		demand, 0, total_coverage, orders.size(), 1, StockRequestService.STOCK_HUNT_MAX_MEAT
	)
	counts = _limit_if_blocked(
		ctx, counts, orders.size(), DrawerOrderService.TYPE_HUNT, {StockRequestService.ORDER_KEY: StockRequestService.HUNT_GROUP_KEY}
	)
	if counts.is_empty():
		return changed
	# Carne o pelle ancora scoperte dopo gli ordini già aperti: tutto al magazzino. Eccezione (2026-10-11): carne che serve
	# solo per la carne essiccata = direttamente all'essiccatoio, senza il trasporto successivo dal deposito. Dal 2026-10-13
	# con "Essiccatoio – solo carne": le pelli vanno al magazzino, anche quando servono anche loro. Essiccatoio pieno
	# all'arrivo = ripiego sul deposito (ButcherDestinationService.find_preferred_building), poi il trasporto del magazzino.
	var needs_meat := int(demand_by_resource.get(HuntZoneService.MEAT_RESOURCE, 0)) > total_coverage
	var needs_hide := int(demand_by_resource.get("hide", 0)) > total_coverage
	var destination := excess_meat_destination(ctx)
	if needs_meat or needs_hide:
		destination = ButcherDestinationService.WAREHOUSE
		var breakdown := _derived_meat_breakdown(ctx, stock)
		# Con la riserva di carne cruda ancora scoperta la carne serve anche al magazzino (2026-10-16): niente scorciatoia.
		var reserve_covered := int(stock.get(HuntZoneService.MEAT_RESOURCE, 0)) >= own_meat_level
		if needs_meat and reserve_covered and int(breakdown["dry"]) > 0 and int(breakdown["other"]) <= 0 \
				and ButcherDestinationService.is_available(ButcherDestinationService.DRYING_RACK_MEAT, ctx.world, ctx.folk):
			destination = ButcherDestinationService.DRYING_RACK_MEAT
	for count in counts:
		_create_zone_order(ctx, now, DrawerOrderService.TYPE_HUNT, StockRequestService.snap_hunt_count(count), -1, {
			StockRequestService.ORDER_KEY: StockRequestService.HUNT_GROUP_KEY, "butcher_destination": destination,
		})
		changed = true
	return changed


# Destinazione di carne e pelli in eccesso per gli ordini di caccia del magazzino: la regola, se disponibile; altrimenti
# il magazzino.
static func excess_meat_destination(ctx: GameContext) -> String:
	var destination := ctx.game_data.stock_excess_meat_destination
	if ButcherDestinationService.ORDER.has(destination) and ButcherDestinationService.is_available(destination, ctx.world, ctx.folk):
		return destination
	return ButcherDestinationService.WAREHOUSE


# Prodotti della caccia già a terra: risorse dei mucchi e resa delle carcasse non ancora macellate (ButcherAction.
# compute_yields). Nome -> quantità.
static func _hunt_arriving(game_data: GameData) -> Dictionary:
	var arriving: Dictionary = {}
	for pile in game_data.ground_piles:
		for resource_name in pile.resources.keys():
			arriving[resource_name] = int(arriving.get(resource_name, 0)) + pile.get_quantity(String(resource_name))
		for carcass in pile.carcasses:
			var yields := ButcherAction.compute_yields(String(carcass.get("species", "")), int(carcass.get("age_band", -1)))
			for resource_name in yields.keys():
				arriving[resource_name] = int(arriving.get(resource_name, 0)) + int(yields[resource_name])
	return arriving


# Livello effettivo della carne cruda per la caccia (2026-10-11, eccezione di StockRequestService.DERIVED_LEVEL_RESOURCES):
# per ogni prodotto con un livello che ha la carne tra gli ingredienti (carne cotta, affumicata, essiccata), i pezzi che
# mancano (livello − scorta − in produzione fattibile − in essiccazione o in viaggio verso l'essiccatoio) × carne per pezzo,
# più la carne già impegnata (ordini sulle postazioni, ordini "Produci" fattibili, trasporti verso l'essiccatoio), così che
# "livello − carne in deposito" dia la carne da cacciare. {"total": livello effettivo della carne, "dry": carne mancante
# per l'essiccatoio, "other": carne mancante per le ricette con lavoro (carne cotta, affumicata)}.
static func _derived_meat_breakdown(ctx: GameContext, stock: Dictionary) -> Dictionary:
	var game_data := ctx.game_data
	var meat := HuntZoneService.MEAT_RESOURCE
	var in_production := _units_in_production(ctx, true)
	var needed := 0
	var needed_dry := 0
	for resource_name in game_data.stock_min_levels.keys():
		var rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if rules == null or not rules.recipe_inputs.has(meat):
			continue
		var have := int(stock.get(resource_name, 0)) + int(in_production.get(resource_name, 0))
		if rules.recipe_auto_progress_days > 0:
			have += _dry_in_racks(ctx.world, String(resource_name), meat) + _dry_traveling(ctx.individuals, String(resource_name))
			for order in game_data.drawer_orders:
				if String(order.get("type", "")) == DrawerOrderService.TYPE_TRANSPORT and String(order.get("recipe", "")) == String(resource_name):
					have += int(order.get("quantity", 0))
		var missing := int(game_data.stock_min_levels[resource_name]) - have
		if missing > 0:
			needed += missing * int(rules.recipe_inputs[meat])
			if rules.recipe_auto_progress_days > 0:
				needed_dry += missing * int(rules.recipe_inputs[meat])
	if needed <= 0:
		return {"total": 0, "dry": 0, "other": 0}
	var free := int(_production_available(ctx, stock).get(meat, 0))
	for order in game_data.drawer_orders:
		if String(order.get("type", "")) == DrawerOrderService.TYPE_TRANSPORT and not order.has(FuelStockService.FUEL_TARGET_KEY) \
				and String(order.get("resource", "")) == meat:
			free -= int(order.get("quantity", 0))
	free = maxi(free, 0)
	return {"total": needed + maxi(int(stock.get(meat, 0)) - free, 0), "dry": needed_dry, "other": needed - needed_dry}


# --- Produzione ---

# Produzione del magazzino (2026-10-11). Per ogni prodotto con ricetta (StockRequestService.SOURCE_PRODUCE) con un livello:
# scoperto = livello − scorta − già in produzione (unità ancora da fare degli ordini sulle postazioni per quella ricetta +
# quantità degli ordini "Produci" del cassetto non presi, di chiunque). Ordini "Produci" del cassetto con ORDER_KEY e
# "Porta al deposito". Gli ingredienti NON si procurano mai. Esempio (corda: 3 fibre ciascuna, livello 5, 8 fibre): "Corda
# ×2" parte subito; per le altre 3 un solo ordine fermo "Corda ×3 · Mancano: 7 Fibre vegetali". Regole:
#   - prenotazione: gli ingredienti vanno prima agli ordini sulle postazioni (quello che manca loro), poi agli ordini non
#     presi dal più vecchio (quelli a mano prenotano tutto; quelli del magazzino la parte fattibile);
#   - riduzione: un ordine fermo del magazzino che può fare almeno 1 pezzo si riduce a quella quantità e parte; il resto
#     torna, al giro dopo, un solo ordine fermo;
#   - mai più di un ordine fermo per prodotto (anche per postazione o attrezzo mancanti). Gli ordini a mano non si toccano.
# Il motivo "Mancano: …" dell'ordine fermo (calcolato con le prenotazioni) resta nell'ordine (StockRequestService.MISSING_KEY),
# letto dalla riga della coda e dalla campanella. true se ha creato, ridotto o tolto ordini.
static func _request_produce(ctx: GameContext, now: float, stock: Dictionary) -> bool:
	var game_data := ctx.game_data
	var changed := false
	var available := _workstation_free_stock(ctx.world, stock)
	for order in game_data.drawer_orders:
		if String(order.get("type", "")) != DrawerOrderService.TYPE_PRODUCE:
			continue
		var order_recipe := String(order.get("recipe", ""))
		var order_quantity := maxi(int(order.get("quantity", 1)), 1)
		var order_fuel := _recipe_fuel_per_cycle(ctx.world, order_recipe)
		if not order.has(StockRequestService.ORDER_KEY):
			_reserve_recipe(available, order_recipe, order_quantity, order_fuel)
			continue
		var makeable := _makeable_units(order_recipe, order_quantity, available, order_fuel)
		if makeable > 0:
			if makeable < order_quantity:
				order["quantity"] = makeable
				changed = true
				if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
					print("[JOB BOARD] Magazzino: ordine #%d %s ridotto a ×%d (la parte fattibile)." % [int(order["id"]), order_recipe, makeable])
			_reserve_recipe(available, order_recipe, makeable, order_fuel)
			order[StockRequestService.MISSING_KEY] = ""
		else:
			order[StockRequestService.MISSING_KEY] = _produce_missing_text(order_recipe, order_quantity, available, order_fuel)
	var in_production := _units_in_production(ctx)
	for resource_name in game_data.stock_min_levels.keys():
		var recipe := String(resource_name)
		if StockRequestService.source_kind_for(recipe) != StockRequestService.SOURCE_PRODUCE:
			continue
		var level := int(game_data.stock_min_levels[resource_name])
		var quantity := int(stock.get(recipe, 0))
		var wm_orders: Array = []
		for order in game_data.drawer_orders:
			if String(order.get("type", "")) == DrawerOrderService.TYPE_PRODUCE and String(order.get("recipe", "")) == recipe \
					and order.has(StockRequestService.ORDER_KEY):
				wm_orders.append(order)
		var coverage := int(in_production.get(recipe, 0))
		for index in range(wm_orders.size() - 1, -1, -1):
			var order: Dictionary = wm_orders[index]
			var order_quantity := maxi(int(order.get("quantity", 1)), 1)
			if StockRequestService.is_order_surplus(level, quantity, coverage, order_quantity, int(_margin(1))) \
					and not _order_too_young(order, level, now):
				coverage -= order_quantity
				DrawerOrderService.remove(game_data, int(order["id"]))
				wm_orders.remove_at(index)
				changed = true
		var uncovered := level - quantity - coverage
		if uncovered <= 0:
			continue
		var max_quantity := maxi(_best_produce_quantity(ctx.world, recipe), 1)
		var has_waiting := false
		for order in wm_orders:
			if String(order.get(StockRequestService.MISSING_KEY, "")) != "":
				has_waiting = true
		# Postazione o attrezzo che mancano: un solo ordine fermo, nessuno se ce n'è già uno.
		if produce_static_reason(ctx, recipe) != "":
			if wm_orders.is_empty():
				_create_produce_order(ctx, now, recipe, mini(uncovered, max_quantity), {StockRequestService.ORDER_KEY: recipe})
				changed = true
			continue
		var fuel_per_cycle := _recipe_fuel_per_cycle(ctx.world, recipe)
		var order_count := wm_orders.size()
		while uncovered > 0 and order_count < StockRequestService.MAX_ORDERS_PER_RESOURCE:
			var makeable := _makeable_units(recipe, mini(uncovered, max_quantity), available, fuel_per_cycle)
			if makeable <= 0:
				break
			_reserve_recipe(available, recipe, makeable, fuel_per_cycle)
			_create_produce_order(ctx, now, recipe, makeable, {StockRequestService.ORDER_KEY: recipe, StockRequestService.MISSING_KEY: ""})
			uncovered -= makeable
			order_count += 1
			changed = true
		if uncovered > 0 and not has_waiting and order_count < StockRequestService.MAX_ORDERS_PER_RESOURCE:
			var waiting_quantity := mini(uncovered, max_quantity)
			_create_produce_order(ctx, now, recipe, waiting_quantity, {
				StockRequestService.ORDER_KEY: recipe,
				StockRequestService.MISSING_KEY: _produce_missing_text(recipe, waiting_quantity, available, fuel_per_cycle),
			})
			changed = true
	return changed


# Scorte meno quello che manca agli ordini già sulle postazioni (lo preleverà chi li fa).
static func _workstation_free_stock(world: World, stock: Dictionary) -> Dictionary:
	var available := stock.duplicate()
	for building in world.buildings:
		if building.is_demolished or building.rules == null or not building.rules.is_workstation or not building.is_complete:
			continue
		var asked := ProductionService.get_missing_inputs(building)
		for name in asked.keys():
			available[name] = maxi(int(available.get(name, 0)) - int(asked[name]), 0)
	return available


# Scorte libere per nuovi ordini "Produci": quelle delle postazioni (_workstation_free_stock) meno gli ingredienti
# prenotati dagli ordini "Produci" del cassetto non presi e fattibili.
static func _production_available(ctx: GameContext, stock: Dictionary) -> Dictionary:
	var available := _workstation_free_stock(ctx.world, stock)
	for order in ctx.game_data.drawer_orders:
		if String(order.get("type", "")) != DrawerOrderService.TYPE_PRODUCE:
			continue
		if order.has(StockRequestService.ORDER_KEY) and String(order.get(StockRequestService.MISSING_KEY, "")) != "":
			continue
		var recipe := String(order.get("recipe", ""))
		_reserve_recipe(available, recipe, maxi(int(order.get("quantity", 1)), 1), _recipe_fuel_per_cycle(ctx.world, recipe))
	return available


# Combustibile per ciclo di `recipe` sulla postazione che la farebbe adesso (0 se nessuna o se non ne serve).
static func _recipe_fuel_per_cycle(world: World, recipe: String) -> float:
	var building := DrawerOrderService.choose_produce_building(world, recipe, 1, {})
	return ProductionService.get_required_fuel(building, recipe) if building != null else 0.0


# Pezzi di `recipe` (fino a `max_units`) che le scorte `available` coprono per intero, combustibile compreso.
static func _makeable_units(recipe: String, max_units: int, available: Dictionary, fuel_per_cycle: float) -> int:
	for units in range(max_units, 0, -1):
		if StockRequestService.missing_for_recipe(recipe, units, available, fuel_per_cycle).is_empty():
			return units
	return 0


# Toglie da `available` gli ingredienti e il combustibile di `units` pezzi di `recipe` (combustibile: prima le risorse che
# bruciano di più, mai gli ingredienti della ricetta).
static func _reserve_recipe(available: Dictionary, recipe: String, units: int, fuel_per_cycle: float) -> void:
	var rules := CaloricCalculator.get_caloric_source_rules(recipe)
	if rules == null or units <= 0:
		return
	for input_name in rules.recipe_inputs.keys():
		var name := String(input_name)
		available[name] = maxi(int(available.get(name, 0)) - int(rules.recipe_inputs[input_name]) * units, 0)
	var fuel_needed := fuel_per_cycle * float(units)
	if fuel_needed <= 0.0:
		return
	var fuels: Array = []
	for name in available.keys():
		var fuel_rules := CaloricCalculator.get_caloric_source_rules(String(name))
		if fuel_rules != null and fuel_rules.fuel_value > 0.0 and not rules.recipe_inputs.has(name):
			fuels.append(name)
	fuels.sort_custom(func(a, b) -> bool:
		return CaloricCalculator.get_caloric_source_rules(String(a)).fuel_value > CaloricCalculator.get_caloric_source_rules(String(b)).fuel_value
	)
	for name in fuels:
		if fuel_needed <= 0.0:
			break
		var value := CaloricCalculator.get_caloric_source_rules(String(name)).fuel_value
		var take := mini(int(available[name]), ceili(fuel_needed / value))
		available[name] = int(available[name]) - take
		fuel_needed -= float(take) * value


# Unità ancora da produrre per ricetta: ordini sulle postazioni (con o senza lavoratore) + ordini "Produci" del cassetto
# non ancora presi. `ready_only`: senza gli ordini del magazzino fermi per i materiali (non produrranno finché non arrivano).
static func _units_in_production(ctx: GameContext, ready_only: bool = false) -> Dictionary:
	var units: Dictionary = {}
	for building in ctx.world.buildings:
		if building.is_demolished or building.rules == null or not building.rules.is_workstation:
			continue
		for order_key in ProductionService.get_order_keys(building):
			var recipe := ProductionService.get_order_recipe(building, order_key)
			units[recipe] = int(units.get(recipe, 0)) + ProductionService.get_order_units(building, order_key)
	for order in ctx.game_data.drawer_orders:
		if String(order.get("type", "")) == DrawerOrderService.TYPE_PRODUCE:
			if ready_only and String(order.get(StockRequestService.MISSING_KEY, "")) != "":
				continue
			var recipe := String(order.get("recipe", ""))
			units[recipe] = int(units.get(recipe, 0)) + maxi(int(order.get("quantity", 1)), 1)
	return units


# Quantità massima di un ordine di `recipe` sulla postazione migliore che la fa (0 = nessuna postazione).
static func _best_produce_quantity(world: World, recipe: String) -> int:
	var best := 0
	for building in world.buildings:
		if ProductionService.can_produce_at(building, recipe):
			best = maxi(best, ProductionService.get_max_order_quantity(building))
	return best


# Motivo per cui un ordine "Produci" del magazzino di `recipe` sarebbe fermo per la postazione o l'attrezzo ("" = no).
static func produce_static_reason(ctx: GameContext, recipe: String) -> String:
	var building := DrawerOrderService.choose_produce_building(ctx.world, recipe, 1, {})
	if building == null:
		return GameContext.tr_text("drawer_order_no_free_building")
	var tool_reason := ToolFetchService.blocked_reason(
		ctx, BuildingToolkitService.filter_uncovered(building, ToolFetchService.recipe_tool_categories(recipe)), DrawerOrderService.TYPE_PRODUCE
	)
	if tool_reason != "" and DrawerOrderService.choose_produce_building(ctx.world, recipe, 1, {}, true) == null:
		return tool_reason
	return ""


# Motivo per cui l'ordine "Produci" del magazzino `order` è fermo ("" = no): postazione o attrezzo, altrimenti i materiali
# calcolati dall'ultimo giro del magazzino con le prenotazioni (StockRequestService.MISSING_KEY).
static func produce_order_reason(ctx: GameContext, order: Dictionary) -> String:
	var static_reason := produce_static_reason(ctx, String(order.get("recipe", "")))
	if static_reason != "":
		return static_reason
	return String(order.get(StockRequestService.MISSING_KEY, ""))


# "Mancano: 6 Fibre vegetali, combustibile 3" per `recipe` × `quantity` con le scorte `available`; "" se c'è tutto.
static func _produce_missing_text(recipe: String, quantity: int, available: Dictionary, fuel_per_cycle: float) -> String:
	var missing := StockRequestService.missing_for_recipe(recipe, quantity, available, fuel_per_cycle)
	if missing.is_empty():
		return ""
	var parts: Array[String] = []
	for name in missing.keys():
		if String(name) == StockRequestService.FUEL_KEY:
			parts.append("%s %s" % [GameContext.tr_text("pending_material_fuel"), str(snappedf(float(missing[name]), 0.1))])
		else:
			parts.append("%d %s" % [int(missing[name]), IconRegistry.get_resource_display_name(String(name))])
	return GameContext.tr_text("drawer_order_missing_materials").format({"materials": ", ".join(parts)})


# --- Essiccatoio e combustibile (ordini "transport") ---

# Essiccatoio del magazzino (2026-10-11). Prodotti ad avanzamento automatico (StockRequestService.SOURCE_DRY: carne e pelle
# essiccate): sotto livello, con l'ingrediente crudo in deposito e un essiccatoio con posto, il magazzino crea un ordine
# "transport" del cassetto: trasporto deposito → essiccatoio (la Transport Task esistente, con ripetizione fino alla
# quantità), che la coda assegna come gli altri. Calcolo: scoperto = livello − scorta − in essiccazione (ingrediente nel
# magazzino degli essiccatoi) − in viaggio (trasporti del magazzino, STOCK_DRY_KEY) − ordini "transport" aperti; un solo
# ordine aperto per prodotto. Ingrediente mancante, essiccatoio pieno o assente: nessun ordine, una voce in campanella
# (StockRuntimeState.dry_warnings, ricalcolata a ogni giro). I prodotti pronti restano nell'essiccatoio (contano nelle
# scorte, VillageStockService). La presa toglie l'ordine dal cassetto, come la produzione.
static func _request_dry(ctx: GameContext, now: float, stock: Dictionary) -> bool:
	var game_data := ctx.game_data
	var warnings := game_data.stock_runtime.dry_warnings
	var changed := false
	warnings.clear()
	for resource_name in game_data.stock_min_levels.keys():
		var recipe := String(resource_name)
		if StockRequestService.source_kind_for(recipe) != StockRequestService.SOURCE_DRY:
			continue
		var ingredient := dry_ingredient(recipe)
		if ingredient == "":
			continue
		var level := int(game_data.stock_min_levels[resource_name])
		var open_orders: Array = []
		var pending := 0
		for order in game_data.drawer_orders:
			if String(order.get("type", "")) == DrawerOrderService.TYPE_TRANSPORT and String(order.get("recipe", "")) == recipe:
				open_orders.append(order)
				pending += int(order.get("quantity", 0))
		# Coperto senza gli ordini aperti (la loro quantità non deve far sembrare il livello raggiunto e farli togliere).
		var covered_without := int(stock.get(recipe, 0)) + _dry_in_racks(ctx.world, recipe, ingredient) + _dry_traveling(ctx.individuals, recipe)
		var covered := covered_without + pending
		# Ordini non presi da togliere: di troppo anche senza di loro (con il margine di un pezzo e non appena nati), o che
		# non possono più partire (essiccatoio senza posto, niente da portare: diventano l'avviso in campanella).
		for order in open_orders.duplicate():
			if not order.has(StockRequestService.ORDER_KEY):
				continue
			var surplus := covered_without >= level + _margin(1) and not _order_too_young(order, level, now)
			if surplus or transport_order_pick(ctx.world, null, order).is_empty():
				DrawerOrderService.remove(game_data, int(order["id"]))
				open_orders.erase(order)
				covered -= int(order.get("quantity", 0))
				changed = true
		if covered >= level or not open_orders.is_empty():
			continue
		var racks := _dry_racks(ctx.world, recipe)
		if racks.is_empty():
			warnings[recipe] = GameContext.tr_text("pending_stock_dry_no_rack")
			continue
		var room := 0
		for rack in racks:
			room = maxi(room, BuildingStorageService.get_max_depositable(rack, ingredient))
		if room <= 0:
			warnings[recipe] = GameContext.tr_text("pending_stock_dry_rack_full")
			continue
		var available := int(stock.get(ingredient, 0))
		if available <= 0:
			warnings[recipe] = GameContext.tr_text("pending_stock_dry_missing").format({"resource": IconRegistry.get_resource_display_name(ingredient)})
			continue
		var quantity := mini(level - covered, mini(available, room))
		var order_id := game_data.next_drawer_order_id
		game_data.next_drawer_order_id += 1
		var dry_order := {
			"id": order_id, "type": DrawerOrderService.TYPE_TRANSPORT, "recipe": recipe, "resource": ingredient, "quantity": quantity,
			StockRequestService.ORDER_KEY: recipe, StockRequestService.CREATED_AT_KEY: now,
		}
		mark_inventory_pending(game_data, dry_order)
		game_data.drawer_orders.append(dry_order)
		changed = true
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] Ordine del cassetto #%d: porta %d %s all'essiccatoio, dal magazzino per %s." % [order_id, quantity, ingredient, recipe])
	return changed


# Regola "Combustibile negli edifici che lo usano" (2026-10-16): decide FuelStockService; qui solo il cassetto. Gli ordini
# sono "transport" con FuelStockService.FUEL_TARGET_KEY (edificio da rifornire) e FUEL_AMOUNT_KEY (combustibile da
# portare), senza ORDER_KEY: non hanno un livello di scorta. true se ha creato o tolto ordini.
static func _request_fuel(ctx: GameContext, now: float) -> bool:
	var game_data := ctx.game_data
	var open_orders: Array = game_data.drawer_orders.filter(func(order: Dictionary) -> bool: return order.has(FuelStockService.FUEL_TARGET_KEY))
	var plan := FuelStockService.plan_orders(ctx.world, game_data, open_orders, FuelStockService.traveling_fuel(ctx.individuals))
	for order_id in plan["remove"]:
		DrawerOrderService.remove(game_data, int(order_id))
	for need in plan["create"]:
		var order_id := game_data.next_drawer_order_id
		game_data.next_drawer_order_id += 1
		var fuel_order := {
			"id": order_id, "type": DrawerOrderService.TYPE_TRANSPORT, FuelStockService.FUEL_TARGET_KEY: int(need[FuelStockService.FUEL_TARGET_KEY]),
			FuelStockService.FUEL_AMOUNT_KEY: float(need[FuelStockService.FUEL_AMOUNT_KEY]), StockRequestService.CREATED_AT_KEY: now,
		}
		mark_inventory_pending(game_data, fuel_order)
		game_data.drawer_orders.append(fuel_order)
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] Ordine del cassetto #%d: porta %.1f di combustibile a %s #%d." % [
				order_id, float(need[FuelStockService.FUEL_AMOUNT_KEY]), (need["building"] as Building).building_type_name,
				int(need[FuelStockService.FUEL_TARGET_KEY]),
			])
	return not (plan["remove"] as Array).is_empty() or not (plan["create"] as Array).is_empty()


# Ingrediente della ricetta ad avanzamento automatico (il primo; oggi ce n'è uno solo per ricetta), "" se nessuno.
static func dry_ingredient(recipe: String) -> String:
	var rules := CaloricCalculator.get_caloric_source_rules(recipe)
	if rules == null or rules.recipe_inputs.is_empty():
		return ""
	return String(rules.recipe_inputs.keys()[0])


# Essiccatoi completi e non demoliti che fanno `recipe`.
static func _dry_racks(world: World, recipe: String) -> Array[Building]:
	var racks: Array[Building] = []
	var rules := CaloricCalculator.get_caloric_source_rules(recipe)
	if rules == null:
		return racks
	for building in world.buildings:
		if building.is_demolished or not building.is_complete or building.is_out_of_service():
			continue
		if rules.recipe_workstation_types.has(building.building_type_name):
			racks.append(building)
	return racks


# Pezzi in essiccazione: l'ingrediente nel magazzino degli essiccatoi di `recipe` (una unità di ingrediente = un pezzo).
static func _dry_in_racks(world: World, recipe: String, ingredient: String) -> int:
	var total := 0
	for rack in _dry_racks(world, recipe):
		var entry: Variant = rack.stored_resources.get(ingredient, null)
		if entry is Dictionary:
			total += int((entry as Dictionary).get("quantity", 0))
	return total


# Pezzi in viaggio verso l'essiccatoio: il residuo da consegnare dei trasporti del magazzino per `recipe` (il più alto per
# individuo: i viaggi ripetuti portano lo stesso residuo).
static func _dry_traveling(individuals: Array[HumanIndividual], recipe: String) -> int:
	var total := 0
	for member in individuals:
		var best := 0
		for task in JobWorkScanService.open_tasks(member):
			if String(task.context.get(STOCK_DRY_KEY, "")) == recipe:
				best = maxi(best, int(task.context.get("transport_requested_remaining", 0)))
		total += best
	return total


# Destinazione, sorgente, risorsa e pezzi di un ordine "transport" per `worker` (o per chiunque, con `worker` null):
# {"target", "source", "resource", "quantity"}, {} se non può partire.
# - essiccatoio: l'essiccatoio di `recipe` con più posto per la risorsa dell'ordine, deposito più vicino che la ha;
# - combustibile (FuelStockService.FUEL_TARGET_KEY, 2026-10-16): l'edificio dell'ordine; quale combustibile, quanti pezzi
#   e da dove li sceglie FuelStockService.pick_fuel adesso, non alla creazione dell'ordine.
static func transport_order_pick(world: World, worker: HumanIndividual, order: Dictionary) -> Dictionary:
	if order.has(FuelStockService.FUEL_TARGET_KEY):
		var target := find_building(world, int(order[FuelStockService.FUEL_TARGET_KEY]))
		if target == null or target.is_demolished or not target.is_complete or target.is_out_of_service():
			return {}
		var fuel := FuelStockService.pick_fuel(world, target, float(order.get(FuelStockService.FUEL_AMOUNT_KEY, 0.0)), worker)
		if fuel.is_empty():
			return {}
		return {"target": target, "source": fuel["source"], "resource": fuel["resource"], "quantity": int(fuel["quantity"])}
	var ingredient := String(order.get("resource", ""))
	var best_rack: Building = null
	var best_room := 0
	for rack in _dry_racks(world, String(order.get("recipe", ""))):
		var room := BuildingStorageService.get_max_depositable(rack, ingredient)
		if room > best_room:
			best_room = room
			best_rack = rack
	if best_rack == null:
		return {}
	var origin := worker.position if worker != null else Vector2.ZERO
	var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
	var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
	var source := WarehouseSelectionService.find_source_for_retrieval(world, origin, origin_macro, ingredient, [best_rack.id], 1, -1, reachability)
	if source == null:
		return {}
	return {"target": best_rack, "source": source, "resource": ingredient, "quantity": int(order.get("quantity", 1))}


# Transport Task di un ordine "transport" (deposito → destinazione, con la ripetizione dei viaggi fino alla quantità); null
# se la destinazione non ha bisogno di niente adesso.
static func transport_order_task(worker: HumanIndividual, order: Dictionary, pick: Dictionary) -> Task:
	var resource_name := String(pick["resource"])
	var quantity := int(pick["quantity"])
	var target: Building = pick["target"]
	var trip_target := TaskBuilderService.transport_trip_target(target, resource_name, quantity)
	if trip_target <= 0:
		return null
	var task := TaskBuilderService.build_transport_task(worker, pick["source"], target, resource_name, trip_target, quantity, true, 0)
	if task != null and order.has(FuelStockService.FUEL_TARGET_KEY):
		task.context[FuelStockService.FUEL_TARGET_KEY] = int(order[FuelStockService.FUEL_TARGET_KEY])
	elif task != null:
		task.context[STOCK_DRY_KEY] = String(order.get("recipe", ""))
	return task


static func find_building(world: World, building_id: int) -> Building:
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null


# --- Giorni di autonomia del cibo ---

# Giorni di autonomia del cibo (2026-10-11). Obiettivo = giorni × consumo giornaliero del villaggio; mancano = obiettivo −
# calorie in deposito − calorie in arrivo (ordini del magazzino aperti per il cibo: singoli cibi, carne da cuocere, "tutto
# il cibo"). Se mancano, in quest'ordine:
#   a. la carne cruda in deposito si cucina: ordini "Produci" della ricetta di cibo più calorica fattibile adesso (con
#      prenotazioni, postazione e attrezzo), marcati FOOD_DAYS_KEY; mai fermi;
#   b. per il resto "Raccogli tutto il cibo" in zona automatica (ORDER_KEY = FOOD_DAYS_ORDER_KEY), a serie di viaggi; le
#      calorie di un viaggio si stimano con lo zaino medio × la densità calorica più bassa tra i cibi che si trovano adesso.
#      Nessun cibo in nessuna zona: un solo ordine fermo, con la voce in campanella "Magazzino · Cibo" (rischio fame).
# Gli ordini non presi diventati di troppo (giorni coperti anche senza di loro) si tolgono.
static func _request_food_days(ctx: GameContext, now: float, stock: Dictionary) -> bool:
	var game_data := ctx.game_data
	var changed := false
	var days := game_data.stock_min_food_days
	var claims := DrawerOrderService.collect_zone_claims(ctx.individuals)
	var kcal_per_trip := _food_calories_per_trip(ctx, average_carry_capacity(ctx))
	var days_orders: Array = []
	var meat_orders: Array = []
	for order in game_data.drawer_orders:
		if String(order.get(StockRequestService.ORDER_KEY, "")) == StockRequestService.FOOD_DAYS_ORDER_KEY:
			days_orders.append(order)
		elif order.has(StockRequestService.FOOD_DAYS_KEY):
			meat_orders.append(order)
	if days <= 0:
		for order in days_orders + meat_orders:
			if not bool(order.get("taken", false)):
				DrawerOrderService.remove(game_data, int(order["id"]))
				changed = true
		return changed
	var target := food_days_target_calories(ctx, days)
	var covered := VillageStockService.get_food_calories(stock) + _food_orders_arriving(ctx, claims, kcal_per_trip) \
		+ _food_processing_calories(ctx)
	# Di troppo: i non presi, dal più nuovo, finché senza di loro i giorni restano coperti.
	var candidates: Array = days_orders + meat_orders
	for index in range(candidates.size() - 1, -1, -1):
		var order: Dictionary = candidates[index]
		if bool(order.get("taken", false)):
			continue
		var order_calories := _food_order_calories(ctx, order, claims, kcal_per_trip)
		# Margine contro l'oscillazione: le calorie di un'unità dell'ordine (un viaggio, un pezzo da cuocere).
		var unit_calories := kcal_per_trip
		if String(order.get("type", "")) == DrawerOrderService.TYPE_PRODUCE:
			var unit_rules := CaloricCalculator.get_caloric_source_rules(String(order.get("recipe", "")))
			unit_calories = unit_rules.calories_per_unit if unit_rules != null else 0.0
		if covered - order_calories >= target + _margin(unit_calories) and not _order_too_young(order, days, now):
			covered -= order_calories
			DrawerOrderService.remove(game_data, int(order["id"]))
			days_orders.erase(order)
			changed = true
	var missing := target - covered
	if missing <= 0.0:
		return changed
	# a. Carne (o altro ingrediente) da cuocere: ricette di cibo fattibili adesso, la più calorica per prima. Solo la carne
	# cruda libera (2026-10-16): non la riserva né quella avviata all'essiccatoio.
	var available := _production_available(ctx, stock)
	_food_days_free_meat_cut(game_data, available)
	for recipe in _food_recipes_by_calories():
		if missing <= 0.0:
			break
		if produce_static_reason(ctx, recipe) != "":
			continue
		var calories := CaloricCalculator.get_caloric_source_rules(recipe).calories_per_unit
		if calories <= 0.0:
			continue
		var wanted := mini(ceili(missing / calories), maxi(_best_produce_quantity(ctx.world, recipe), 1))
		var fuel_per_cycle := _recipe_fuel_per_cycle(ctx.world, recipe)
		var makeable := _makeable_units(recipe, wanted, available, fuel_per_cycle)
		if makeable <= 0:
			continue
		_reserve_recipe(available, recipe, makeable, fuel_per_cycle)
		_create_produce_order(ctx, now, recipe, makeable, {
			StockRequestService.ORDER_KEY: recipe, StockRequestService.FOOD_DAYS_KEY: true, StockRequestService.MISSING_KEY: "",
		})
		missing -= float(makeable) * calories
		changed = true
	if missing <= 0.0:
		return changed
	# b. Raccogli tutto il cibo.
	var extra := {
		StockRequestService.ORDER_KEY: StockRequestService.FOOD_DAYS_ORDER_KEY,
		"criterion_kind": PickUpAction.CriterionKind.CATEGORY,
		"criterion_category": SecondaryResourceTypes.Category.FOOD, "resource_name": "",
	}
	if kcal_per_trip <= 0.0:
		if days_orders.is_empty():
			_create_zone_order(ctx, now, DrawerOrderService.TYPE_GATHER, 1, -1, extra.duplicate())
			changed = true
		return changed
	var trips_needed := ceili(missing / kcal_per_trip)
	var counts := StockRequestService.compute_new_order_counts(
		trips_needed, 0, 0, days_orders.size(), 1, HaulZoneService.WORK_AREA_MAX_TRIPS, StockRequestService.MAX_FOOD_DAYS_ORDERS
	)
	counts = _limit_if_blocked(ctx, counts, days_orders.size(), DrawerOrderService.TYPE_GATHER, extra)
	for count in counts:
		_create_zone_order(ctx, now, DrawerOrderService.TYPE_GATHER, count, -1, extra.duplicate())
		changed = true
	return changed


# Carne cruda che i giorni di autonomia non cuociono (2026-10-16 — priorità: lavorazioni, poi la riserva, poi i giorni): la
# riserva (livello proprio della carne cruda) e la carne degli ordini "transport" dell'essiccatoio non ancora presi. Quella
# degli ordini "Produci" è già tolta da _production_available. Modifica `available` sul posto.
static func _food_days_free_meat_cut(game_data: GameData, available: Dictionary) -> void:
	var meat := HuntZoneService.MEAT_RESOURCE
	var kept := int(game_data.stock_min_levels.get(meat, 0))
	for order in game_data.drawer_orders:
		if String(order.get("type", "")) == DrawerOrderService.TYPE_TRANSPORT and not order.has(FuelStockService.FUEL_TARGET_KEY) \
				and String(order.get("resource", "")) == meat:
			kept += int(order.get("quantity", 0))
	available[meat] = maxi(int(available.get(meat, 0)) - kept, 0)


# Calorie del cibo già avviato alla lavorazione (2026-10-16): per i giorni di autonomia è cibo in arrivo. Essiccata
# (avanzamento automatico): pezzi nell'essiccatoio, in viaggio e negli ordini "transport" aperti; ricette con lavoro: pezzi
# ancora da fare negli ordini già sulle postazioni (quelli del cassetto li conta _food_orders_arriving), tranne quelli
# riservati (il banchetto: va ai presenti, non nelle scorte).
static func _food_processing_calories(ctx: GameContext) -> float:
	var total := 0.0
	for building in ctx.world.buildings:
		if building.is_demolished or building.rules == null or not building.rules.is_workstation:
			continue
		for order_key in ProductionService.get_order_keys(building):
			if ProductionService.is_order_reserved(building, order_key):
				continue
			var rules := CaloricCalculator.get_caloric_source_rules(ProductionService.get_order_recipe(building, order_key))
			if rules != null and rules.category == SecondaryResourceTypes.Category.FOOD:
				total += float(ProductionService.get_order_units(building, order_key)) * rules.calories_per_unit
	for recipe in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(recipe)
		if rules == null or rules.category != SecondaryResourceTypes.Category.FOOD or rules.recipe_auto_progress_days <= 0:
			continue
		var ingredient := dry_ingredient(recipe)
		if ingredient == "":
			continue
		var pieces := _dry_in_racks(ctx.world, recipe, ingredient) + _dry_traveling(ctx.individuals, recipe)
		for order in ctx.game_data.drawer_orders:
			if String(order.get("type", "")) == DrawerOrderService.TYPE_TRANSPORT and String(order.get("recipe", "")) == recipe:
				pieces += int(order.get("quantity", 0))
		total += float(pieces) * rules.calories_per_unit
	return total


# Calorie da avere per i giorni di autonomia (2026-10-11): giorni minimi più il consumo fino al prossimo inventario (la
# frequenza), così a fine giro si è ancora al minimo e non sotto.
static func food_days_target_calories(ctx: GameContext, days: int) -> float:
	if days <= 0:
		return 0.0
	return (float(days) + float(ctx.game_data.inventory_interval_hours) / 24.0) * village_daily_calorie_need(ctx)


# Consumo giornaliero di calorie di tutti gli individui, con la stessa formula del consumo reale
# (HumanCalculator.get_daily_calorie_consumption: regole umane, fascia d'età, sesso, allattamento, era). Usato dal cassetto
# Scorte e dai giorni di autonomia.
static func village_daily_calorie_need(ctx: GameContext) -> float:
	var daily_need := 0.0
	if ctx.folk != null and ctx.folk.human_rules_ref != null and ctx.game_data != null:
		var era_rules := EraCalculator.get_era_rules(ctx.game_data.current_era_name)
		for member in ctx.individuals:
			daily_need += HumanCalculator.get_daily_calorie_consumption(
				ctx.folk.human_rules_ref, ctx.age_band_of(member), member.sex, member.dependent_child_id != -1, era_rules
			)
	return daily_need


# Calorie stimate di un viaggio "tutto il cibo": zaino × la densità calorica (calorie per spazio) più bassa tra i cibi
# raccoglibili che adesso si trovano in almeno una zona di raccolta; 0 se nessuno.
static func _food_calories_per_trip(ctx: GameContext, carry_capacity: float) -> float:
	var lowest := INF
	var areas := DrawerOrderService.zone_areas(ctx.game_data, DrawerOrderService.TYPE_GATHER)
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if not is_food(resource_name) or not TerrainScatteredResourceService.is_pickable(resource_name):
			continue
		if TerrainScatteredResourceService.is_resource_locked(resource_name):
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules.calories_per_unit <= 0.0 or rules.space_per_unit <= 0.0:
			continue
		var probe := {"criterion_kind": PickUpAction.CriterionKind.NAME, "criterion_category": -1, "resource_name": resource_name}
		var found := false
		for area in areas:
			if DrawerOrderService.area_has_targets(ctx, DrawerOrderService.TYPE_GATHER, area, null, {}, probe):
				found = true
				break
		if found:
			lowest = minf(lowest, rules.calories_per_unit / rules.space_per_unit)
	if lowest == INF or carry_capacity <= 0.0:
		return 0.0
	return lowest * carry_capacity


# Calorie in arrivo dagli ordini del magazzino per il cibo: raccolte di singoli cibi, "tutto il cibo", cibo da cuocere.
static func _food_orders_arriving(ctx: GameContext, claims: Dictionary, kcal_per_trip: float) -> float:
	var total := 0.0
	for order in ctx.game_data.drawer_orders:
		total += _food_order_calories(ctx, order, claims, kcal_per_trip)
	return total


# Calorie che un ordine del magazzino porterà ancora (0 se non è un ordine di cibo del magazzino).
static func _food_order_calories(ctx: GameContext, order: Dictionary, claims: Dictionary, kcal_per_trip: float) -> float:
	if not order.has(StockRequestService.ORDER_KEY):
		return 0.0
	var key := String(order[StockRequestService.ORDER_KEY])
	var order_type := String(order.get("type", ""))
	if order_type == DrawerOrderService.TYPE_PRODUCE:
		var rules := CaloricCalculator.get_caloric_source_rules(key)
		if rules == null or rules.category != SecondaryResourceTypes.Category.FOOD:
			return 0.0
		return float(maxi(int(order.get("quantity", 1)), 1)) * rules.calories_per_unit
	if order_type != DrawerOrderService.TYPE_GATHER:
		return 0.0
	var claim: Dictionary = claims.get(int(order["id"]), {})
	var taken := bool(order.get("taken", false)) and not claim.is_empty()
	var remaining := maxi(int(order.get("count", 1)) - (int(claim.get("done", 0)) if taken else 0), 0)
	if key == StockRequestService.FOOD_DAYS_ORDER_KEY:
		return float(remaining) * kcal_per_trip
	if not is_food(key):
		return 0.0
	var food_rules := CaloricCalculator.get_caloric_source_rules(key)
	return float(remaining * StockRequestService.get_gather_units_per_trip(key, average_carry_capacity(ctx))) * food_rules.calories_per_unit


# Ricette di cibo con lavoro (non ad avanzamento automatico), dalla più calorica.
static func _food_recipes_by_calories() -> Array[String]:
	var recipes: Array[String] = []
	for name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(name)
		if rules != null and rules.category == SecondaryResourceTypes.Category.FOOD and not rules.recipe_inputs.is_empty() \
				and rules.recipe_auto_progress_days <= 0:
			recipes.append(name)
	recipes.sort_custom(func(a: String, b: String) -> bool:
		return CaloricCalculator.get_caloric_source_rules(a).calories_per_unit > CaloricCalculator.get_caloric_source_rules(b).calories_per_unit
	)
	return recipes


# --- Helper comuni ---

static func is_food(resource_name: String) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules != null and rules.category == SecondaryResourceTypes.Category.FOOD


# Nomi che il magazzino sta chiedendo: risorse raccoglibili sotto il loro livello e, se mancano giorni di autonomia, tutto
# il cibo raccoglibile (StockRuntimeState.fill_names, letti da HaulZoneService per riempire lo zaino).
static func _update_fill_names(ctx: GameContext, stock: Dictionary) -> void:
	var game_data := ctx.game_data
	var fill: Array[String] = []
	for resource_name in game_data.stock_min_levels.keys():
		var name := String(resource_name)
		if StockRequestService.source_kind_for(name) != StockRequestService.SOURCE_GATHER:
			continue
		if int(stock.get(name, 0)) < int(game_data.stock_min_levels[resource_name]):
			fill.append(name)
	if game_data.stock_min_food_days > 0:
		if VillageStockService.get_food_calories(stock) < food_days_target_calories(ctx, game_data.stock_min_food_days):
			for name in CaloricCalculator.list_secondary_resource_names():
				if is_food(name) and TerrainScatteredResourceService.is_pickable(name) and not fill.has(name):
					fill.append(name)
	game_data.stock_runtime.fill_names = fill


# Nome mostrato di un ordine del magazzino: la risorsa, o "Cibo" per i giorni di autonomia.
static func order_display_name(order: Dictionary) -> String:
	var key := String(order.get(StockRequestService.ORDER_KEY, ""))
	if key == StockRequestService.FOOD_DAYS_ORDER_KEY:
		return GameContext.tr_text("warehouse_food_days_name")
	return IconRegistry.get_resource_display_name(key)


# Unità coperte da un ordine del magazzino: quello che resta della serie × resa, più quanto della risorsa portano già nello
# zaino i suoi lavoratori (raccolto ma non ancora scaricato: altrimenti nel viaggio verso il magazzino il deficit
# sembrerebbe scoperto e nascerebbe un ordine doppio).
static func _order_coverage(order: Dictionary, claims: Dictionary, resource_name: String, unit_yield: int) -> int:
	var claim: Dictionary = claims.get(int(order["id"]), {})
	var taken := bool(order.get("taken", false)) and not claim.is_empty()
	var remaining := maxi(int(order.get("count", 1)) - (int(claim.get("done", 0)) if taken else 0), 0)
	var coverage := remaining * unit_yield
	if taken:
		for member in claim.get("members", []):
			coverage += (member as HumanIndividual).get_carried_quantity(resource_name)
	return coverage


# Resa di un'unità dell'ordine: viaggio (zaino medio), pianta tagliata o estrazione.
static func _unit_yield(resource_name: String, source_kind: String, carry_capacity: float) -> int:
	match source_kind:
		StockRequestService.SOURCE_GATHER:
			return StockRequestService.get_gather_units_per_trip(resource_name, carry_capacity)
		StockRequestService.SOURCE_CUT:
			return StockRequestService.get_cut_yield_per_plant(resource_name)
		StockRequestService.SOURCE_QUARRY:
			return StockRequestService.get_quarry_yield_per_extraction()
	return 0


# Zaino medio di chi può raccogliere (non neonati né bambini), per stimare un viaggio; 0 se nessuno.
static func average_carry_capacity(ctx: GameContext) -> float:
	var total := 0.0
	var count := 0
	for member in ctx.individuals:
		var age_band := ctx.age_band_of(member)
		if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD or member.max_carry_capacity <= 0.0:
			continue
		total += member.max_carry_capacity
		count += 1
	return total / float(count) if count > 0 else 0.0


# --- Voci della campanella ("In sospeso") ---

# Inventario in coda da almeno un intervallo (inventory_overdue_hours) e nessuno che lo fa.
static func collect_inventory_entries(ctx: GameContext, now: float) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not is_enabled(ctx) or not is_inventory_due(ctx.game_data, now) or not inventory_workers(ctx.individuals).is_empty():
		return entries
	if ctx.game_data.last_inventory_end >= 0.0:
		var overdue_hours := (now - next_inventory_time(ctx.game_data)) * 24.0
		if overdue_hours < inventory_overdue_hours(ctx.game_data):
			return entries
		var text := GameContext.tr_text("pending_inventory_overdue").format({"hours": int(floor(overdue_hours))})
		var entry := PendingEntryService.make_entry("inventory_overdue", text, {"kind": "none", "id": -1, "macro": Vector2i(-1, -1), "sort": 0.0, "name": text}, false)
		entry["disabled_reason"] = GameContext.tr_text("pending_stock_blocked_detail")
		entries.append(entry)
	return entries


# Una voce per ogni ordine del magazzino non preso e bloccato, "Magazzino · <risorsa>" con il motivo sotto; nessun posto da
# centrare (l'ordine sta nella coda delle task). L'essiccatoio ha i suoi avvisi (collect_dry_entries); gli ordini
# dell'inventario in corso non sono ancora usciti.
static func collect_blocked_entries(ctx: GameContext) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if ctx.game_data == null or not JobBoardService.is_enabled(ctx.folk):
		return entries
	for order in ctx.game_data.drawer_orders:
		if not order.has(StockRequestService.ORDER_KEY) or bool(order.get("taken", false)):
			continue
		var order_type := String(order.get("type", ""))
		if order_type == DrawerOrderService.TYPE_TRANSPORT or bool(order.get(StockRequestService.INVENTORY_PENDING_KEY, false)):
			continue
		var reason := ""
		if order_type == DrawerOrderService.TYPE_PRODUCE:
			reason = produce_order_reason(ctx, order)
		else:
			reason = DrawerOrderJobProvider.zone_blocked_reason(ctx, order_type, int(order.get("zone_id", -1)), null, order)
		if reason == "":
			continue
		var row_name := GameContext.tr_text("pending_stock_blocked").format({"resource": order_display_name(order)})
		var entry := PendingEntryService.make_entry("stock_blocked:%d" % int(order["id"]), "%s\n%s" % [row_name, reason], {
			"kind": "none", "id": -1, "macro": Vector2i(-1, -1), "sort": float(order["id"]),
			"name": row_name, "detail": reason,
		}, false)
		entry["disabled_reason"] = GameContext.tr_text("pending_stock_blocked_detail")
		entries.append(entry)
	return entries


# Una voce per prodotto dell'essiccatoio con un motivo nell'ultimo giro del magazzino ("Magazzino · Carne essiccata", motivo
# sotto; StockRuntimeState.dry_warnings).
static func collect_dry_entries(game_data: GameData) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for recipe in game_data.stock_runtime.dry_warnings.keys():
		var row_name := GameContext.tr_text("pending_stock_blocked").format({"resource": IconRegistry.get_resource_display_name(String(recipe))})
		var reason := String(game_data.stock_runtime.dry_warnings[recipe])
		var entry := PendingEntryService.make_entry("stock_dry:%s" % String(recipe), "%s\n%s" % [row_name, reason], {
			"kind": "none", "id": -1, "macro": Vector2i(-1, -1), "sort": 0.0, "name": row_name, "detail": reason,
		}, false)
		entry["disabled_reason"] = GameContext.tr_text("pending_stock_blocked_detail")
		entries.append(entry)
	return entries
