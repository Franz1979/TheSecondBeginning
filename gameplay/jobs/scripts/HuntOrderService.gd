class_name HuntOrderService
extends RefCounted

# Fine delle serie di caccia degli ordini del cassetto (2026-10-09; spostata da GameScene il 2026-10-17, refactoring GameScene
# blocco 4 — regole invariate): cambio di zona dopo un'uscita a vuoto, ordine tolto o tornato in coda, avvisi "nessuna
# preda" nella campanella, pausa delle cacce automatiche del magazzino. Statico; gli avvisi degli ordini già finiti vivono in
# GameData.job_board_runtime.hunt_no_prey_alerts (mai salvati), quello di un ordine tornato in coda sull'ordine stesso.

# Avviso "Caccia: nessuna preda in <zona>": sull'ordine tornato in coda (zona automatica: {"zone", "macro_x", "macro_y",
# "area_id"}, salvato con l'ordine) finché non riprende o viene tolto; per l'ordine finito (zona scelta) in memoria per
# NO_PREY_ALERT_DAYS di gioco.
const NO_PREY_KEY := "no_prey_alert"
const NO_PREY_ALERT_DAYS: float = 1.0
# Avviso dell'ordine a zona automatica finito senza più zone da provare (2026-10-10): {"done", "total"} carne dell'ordine
# intero, nell'avviso in memoria; testo "Caccia finita: nessuna preda catturata (N/M carne portate)".
const ENDED_KEY := "hunt_ended"


# HumanIndividualActionService.hunt_zone_series_ended: carne consegnata fino all'obiettivo = ordine tolto; un'uscita senza
# prede = zona automatica: si prova un'altra zona; senza più zone da provare (2026-10-10) l'ordine finisce con l'avviso
# "Caccia finita"; solo se il cambio non avviene per altri motivi torna in coda con la carne che manca (chi cacciava salta
# una volta la lista) e l'avviso "nessuna preda"; zona scelta: l'ordine finisce, con l'avviso "nessuna preda".
static func on_series_ended(ctx: GameContext, now: float, hunter: HumanIndividual, series: Dictionary, reason: String, effects: GameEffects) -> void:
	# Zona automatica (2026-10-09): dopo un'uscita a vuoto si prova un'altra zona con prede, prima di arrendersi.
	if reason == HuntZoneService.SERIES_END_NO_PREY and _try_switch_zone(ctx, hunter, series, effects):
		return
	var game_data := ctx.game_data
	if not series.has(DrawerOrderService.SERIES_KEY) or game_data == null:
		return
	var order := DrawerOrderService.find(game_data, int(series[DrawerOrderService.SERIES_KEY]))
	if order.is_empty() or not bool(order.get("taken", false)):
		return
	order["done_seen"] = maxi(int(order.get("done_seen", 0)), int(series.get("delivered", 0)))
	if reason == HuntZoneService.SERIES_END_COMPLETE:
		DrawerOrderService.remove(game_data, int(order["id"]))
		return
	var area := WorkAreaService.find_by_id(game_data, int(series.get("work_area_id", -1)))
	var alert := {
		"zone": area.name if area != null else GameContext.tr_text("drawer_cut_zone_gone"),
		"area_id": area.id if area != null else -1,
		"macro_x": area.macro_coords.x if area != null else -1, "macro_y": area.macro_coords.y if area != null else -1,
	}
	var alerts := game_data.job_board_runtime.hunt_no_prey_alerts
	if int(order.get("zone_id", -1)) >= 0:
		alert["order_id"] = int(order["id"])
		alert["until"] = now + NO_PREY_ALERT_DAYS
		alerts.append(alert)
		DrawerOrderService.remove(game_data, int(order["id"]))
		return
	# Zona automatica senza più zone da provare (2026-10-10, contro il loop: prima tornava in coda e veniva ripreso con le
	# zone provate azzerate, all'infinito): l'ordine finisce come quello a zona fissata, con l'avviso "Caccia finita". Già
	# all'obiettivo: tolto come completato, senza avviso.
	if hunter != null and ctx.individuals.has(hunter) and _zones_exhausted(ctx, hunter, series):
		var done := int(order.get("done_before", 0)) + int(order.get("done_seen", 0))
		var total := DrawerOrderService.order_total(order)
		if done < total:
			alert["order_id"] = int(order["id"])
			alert["until"] = now + NO_PREY_ALERT_DAYS
			alert[ENDED_KEY] = {"done": done, "total": total}
			alerts.append(alert)
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] Ordine del cassetto #%d finito: nessuna preda in nessuna zona (%d/%d carne)." % [int(order["id"]), done, total])
		# Ordine del magazzino (2026-10-11): niente nuove cacce automatiche per un giorno, invece di ricrearne una al secondo.
		if order.has(StockRequestService.ORDER_KEY):
			game_data.stock_runtime.hunt_pause_until = now + NO_PREY_ALERT_DAYS
		DrawerOrderService.remove(game_data, int(order["id"]))
		return
	order[NO_PREY_KEY] = alert
	DrawerOrderService.return_order(ctx, order)
	if hunter != null:
		hunter.skip_job_board_once = true


# Cambio di zona dopo un'uscita a vuoto (2026-10-09, solo serie con la zona automatica — comando o ordine del cassetto senza
# zona fissata): la zona appena pattugliata si segna come provata e la caccia riparte, in coda (subito dopo la chiusura di
# questa uscita), nella zona migliore tra quelle non ancora provate in questo giro e con prede adesso
# (HuntZoneService.choose_work_area con require_prey). false = nessuna zona così, o ordine non più di chi caccia, o coltello
# non preparabile (in cintura, o dallo zaino in cintura — ToolGateService.try_satisfy): la serie finisce come prima.
static func _try_switch_zone(ctx: GameContext, hunter: HumanIndividual, series: Dictionary, effects: GameEffects) -> bool:
	var game_data := ctx.game_data
	if game_data == null or hunter == null or not ctx.individuals.has(hunter):
		return false
	if not bool(series.get(HuntZoneService.SERIES_AUTO_ZONE_KEY, false)):
		return false
	if series.has(DrawerOrderService.SERIES_KEY):
		var order := DrawerOrderService.find(game_data, int(series[DrawerOrderService.SERIES_KEY]))
		if order.is_empty() or not bool(order.get("taken", false)) or int(order.get("zone_id", -1)) >= 0:
			return false
	var tried := _tried_zones(series)
	var next_area := HuntZoneService.choose_work_area(game_data, hunter, ctx.live_cells, tried, true)
	if next_area == null:
		HuntZoneService.log_event(hunter, "nessuna altra zona con prede (provate %s): la serie finisce." % str(tried))
		return false
	var next_series := series.duplicate(true)
	next_series["work_area_id"] = next_area.id
	next_series[HuntZoneService.SERIES_TRIED_ZONES_KEY] = tried
	var task := TaskBuilderService.build_hunt_zone_task(next_area.id, next_series)
	if task == null:
		return false
	var required_knife: Array[TaskTypes.ToolCategory] = [TaskTypes.ToolCategory.BUTCHERING]
	if ToolGateService.try_satisfy(hunter, required_knife, game_data)["result"] != ToolGateService.Result.OK:
		return false
	# Nuova uscita della serie (2026-10-10): seguito della catena, fuori dal tetto della coda.
	TaskQueueService.push_follow_up_task(hunter, task)
	HuntZoneService.log_event(hunter, "nessuna preda dopo %.1f giorni: si passa alla zona %s #%d (provate %s)." % [
		PatrolAreaAction.PATROL_DAYS_WITHOUT_PREY_LIMIT, next_area.name, next_area.id, str(tried)
	])
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	return true


# Zona automatica (2026-10-10): nessuna zona con la caccia attiva e con prede, tra quelle non ancora provate in questo giro
# (stessa scelta di _try_switch_zone). Distingue "zone esaurite" dagli altri motivi per cui il cambio di zona non avviene
# (ordine non più di chi caccia, coltello).
static func _zones_exhausted(ctx: GameContext, hunter: HumanIndividual, series: Dictionary) -> bool:
	if not bool(series.get(HuntZoneService.SERIES_AUTO_ZONE_KEY, false)):
		return false
	return HuntZoneService.choose_work_area(ctx.game_data, hunter, ctx.live_cells, _tried_zones(series), true) == null


# Zone già provate in questo giro, con quella appena pattugliata.
static func _tried_zones(series: Dictionary) -> Array[int]:
	var tried := HuntZoneService.get_tried_zone_ids(series)
	var current_area_id := int(series.get("work_area_id", -1))
	if current_area_id >= 0 and not tried.has(current_area_id):
		tried.append(current_area_id)
	return tried


# Voci della campanella: avviso sugli ordini di caccia tornati in coda e avvisi in memoria degli ordini finiti (scaduti:
# tolti). Clic = la zona selezionata e centrata.
static func collect_no_prey_entries(ctx: GameContext, now: float) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if ctx.game_data == null:
		return entries
	for order in ctx.game_data.drawer_orders:
		if String(order.get("type", "")) != DrawerOrderService.TYPE_HUNT or bool(order.get("taken", false)):
			continue
		var alert: Variant = order.get(NO_PREY_KEY, null)
		if alert is Dictionary:
			entries.append(_no_prey_entry(ctx, int(order["id"]), alert as Dictionary))
	var alerts := ctx.game_data.job_board_runtime.hunt_no_prey_alerts
	for alert in alerts.duplicate():
		if now >= float(alert["until"]):
			alerts.erase(alert)
			continue
		entries.append(_no_prey_entry(ctx, int(alert["order_id"]), alert))
	return entries


static func _no_prey_entry(ctx: GameContext, order_id: int, alert: Dictionary) -> Dictionary:
	var text := GameContext.tr_text("pending_hunt_no_prey").format({"zone": String(alert.get("zone", ""))})
	var ended: Variant = alert.get(ENDED_KEY, null)
	if ended is Dictionary:
		text = GameContext.tr_text("pending_hunt_order_ended").format({"done": int(ended.get("done", 0)), "total": int(ended.get("total", 0))})
	var macro := Vector2i(int(alert.get("macro_x", -1)), int(alert.get("macro_y", -1)))
	return PendingEntryService.make_entry("hunt_no_prey:%d" % order_id, text, {
		"kind": "work_area", "id": int(alert.get("area_id", -1)), "macro": macro, "sort": float(order_id), "name": text,
	}, ctx.live_cells.has(macro))
