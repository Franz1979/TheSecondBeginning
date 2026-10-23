class_name ProductionEvictionService
extends RefCounted

# Ordini in attesa di materiali scalzati (2026-10-23, richiesta utente). Gli ordini "Produci" si assegnano anche senza
# materiali (come i cantieri): chi li prende, senza materiale in nessun magazzino, va in pausa nella coda personale e
# l'ordine resta sulla postazione. Così però un ordine in attesa tiene occupato un posto, e si crea un tappo quando
# l'ingrediente che aspetta si fa nella stessa postazione (la corda di fibre al focolare per la Sacca di pelle). Regola,
# per edificio e sullo stato di adesso: un ordine della coda che non trova posto in nessuna postazione adatta fa tornare
# in coda l'ordine in attesa più vecchio di una di queste, e ne prende il posto. I materiali già consegnati restano nel
# deposito dell'edificio; il lavoro fatto resta come produzione sospesa della ricetta (ProductionService.cancel_order).
# Anti ping-pong: l'ordine tornato in coda porta EVICTED_KEY e può prendere solo posti liberi, mai scalzare.
# Esclusi: ordini riservati a un rito, tenuti per l'edificio e cotture automatiche dei giorni di cibo (hanno regole loro).
# Statico e senza stato, come gli altri servizi.

const EVICTED_KEY := "evicted"
# Postazione da cui è stato scalzato (id), se nel suo deposito c'era già qualcuno dei suoi ingredienti (2026-10-23,
# richiesta utente): l'ordine torna solo lì, appena c'è un posto libero, così materiali e lavoro fatto non restano
# altrove e non servono viaggi in più. Si toglie se la postazione non c'è più o non sa più fare la ricetta.
const EVICTED_FROM_KEY := "evicted_from"


# true se l'ordine `order_key` di `building` è in attesa di materiali adesso: la Task del suo lavoratore è in pausa per
# materiali nella coda personale (HumanIndividualActionService._postpone_for_material, tipo produzione) oppure è quella
# corrente con la ProduceAction ferma per materiali o combustibile.
static func is_order_waiting(individuals: Array[HumanIndividual], building: Building, order_key: String) -> bool:
	for member in individuals:
		var current := member.current_task
		if task_has_order(current, building, order_key):
			var action := current.get_current_action() as ProduceAction
			return action != null and action.is_blocked_by_materials()
		for queued in member.task_queue:
			var queued_task := queued as Task
			if task_has_order(queued_task, building, order_key):
				return String(queued_task.context.get(HumanIndividualActionService.CONTEXT_MATERIAL_POSTPONED_KIND, "")) \
					== HumanIndividualActionService.POSTPONED_KIND_PRODUCE
	return false


# Postazione e ordine da scalzare per un ordine di `quantity` pezzi di `recipe` che non trova posto: tra le postazioni
# che sanno farlo (ricetta, quantità per ordine, posto in uscita) ma piene, l'ordine in attesa più vecchio (contatore più
# basso nella chiave). {"building", "order_key"}, {} se nessuno.
static func find_evictable(world: World, individuals: Array[HumanIndividual], recipe: String, quantity: int) -> Dictionary:
	var best: Dictionary = {}
	var best_index := -1
	if world == null:
		return best
	for building in world.buildings:
		if not ProductionService.can_produce_at(building, recipe) or ProductionService.get_max_order_quantity(building) < quantity:
			continue
		if not ProductionService.has_output_room(building, recipe):
			continue
		for order_key in ProductionService.get_order_keys(building):
			if not _is_evictable_kind(building, order_key) or not is_order_waiting(individuals, building, order_key):
				continue
			var index := _order_index(order_key)
			if best_index == -1 or index < best_index:
				best_index = index
				best = {"building": building, "order_key": order_key}
	return best


# Toglie l'ordine a chi lo fa (Task corrente e copie in coda), con la regola del carico come la X dell'ordine; chi resta
# libero cerca altro da fare. L'ordine resta sull'edificio: lo toglie chi chiama.
static func release_order_workers(ctx: GameContext, building: Building, order_key: String) -> void:
	var freed: Array[HumanIndividual] = []
	for member in ctx.individuals:
		if task_has_order(member.current_task, building, order_key):
			if CargoReturnService.release_cargo(member, member.current_task, ctx.world) != CargoReturnService.Outcome.RETURNING:
				member.stop(false)
				freed.append(member)
		for queued_task in member.task_queue.duplicate():
			if task_has_order(queued_task, building, order_key) \
					and CargoReturnService.release_cargo(member, queued_task, ctx.world) != CargoReturnService.Outcome.RETURNING:
				member.task_queue.erase(queued_task)
	for member in freed:
		HumanIndividualActionService.resolve_idle_individual(member, ctx.age_band_of(member), ctx.world)


# Scalza l'ordine: lo toglie al lavoratore e dalla postazione e lo rimette nella coda del cassetto, con EVICTED_KEY e,
# se veniva dal magazzino, la sua chiave (il magazzino continua a gestirlo).
static func evict(ctx: GameContext, building: Building, order_key: String) -> void:
	if ctx.game_data == null or not ProductionService.has_order(building, order_key):
		return
	var record: Dictionary = building.production_progress[order_key]
	var recipe := String(record.get("resource_name", ""))
	var units := maxi(int(record.get("units_remaining", 1)), 1)
	var deliver := bool(record.get("deliver_to_warehouse", true))
	var extra := {EVICTED_KEY: true}
	var warehouse_order := ProductionService.get_order_warehouse_key(building, order_key)
	if warehouse_order != "":
		extra[StockRequestService.ORDER_KEY] = warehouse_order
	var bound := _holds_any_input(building, recipe)
	if bound:
		extra[EVICTED_FROM_KEY] = building.id
	release_order_workers(ctx, building, order_key)
	ProductionService.cancel_order(building, order_key)
	var order := DrawerOrderService.add_produce_order(ctx.game_data, recipe, units, deliver, extra)
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] Ordine %s ×%d in attesa di materiali scalzato da %s #%d: torna in coda come ordine del cassetto #%d%s." % [
			recipe, units, building.building_type_name, building.id, int(order.get("id", -1)),
			", solo per questa postazione (ha già suoi ingredienti)" if bound else ", libero (nessun suo ingrediente lì)"
		])


# Postazione a cui è legato l'ordine del cassetto `order` (EVICTED_FROM_KEY): l'edificio se esiste ancora e sa fare la
# ricetta; altrimenti toglie il segno e ritorna null (l'ordine torna libero). null anche se l'ordine non è legato.
static func bound_building(world: World, order: Dictionary) -> Building:
	if not order.has(EVICTED_FROM_KEY):
		return null
	var building_id := int(order[EVICTED_FROM_KEY])
	var recipe := String(order.get("recipe", ""))
	if world != null:
		for building in world.buildings:
			if building.id == building_id and not building.is_demolished and building.is_complete \
					and CaloricCalculator.get_caloric_source_rules(recipe) != null \
					and CaloricCalculator.get_caloric_source_rules(recipe).recipe_workstation_types.has(building.building_type_name):
				return building
	order.erase(EVICTED_FROM_KEY)
	return null


# true se nel deposito di `building` c'è almeno uno degli ingredienti di `recipe`.
static func _holds_any_input(building: Building, recipe: String) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(recipe)
	if rules == null:
		return false
	for input_name in rules.recipe_inputs.keys():
		if ProductionService.get_input_available(building, String(input_name)) > 0:
			return true
	return false


static func task_has_order(task: Task, building: Building, order_key: String) -> bool:
	if task == null or task.is_finished():
		return false
	for step in task.steps:
		if step is ProduceAction and (step as ProduceAction).order_key == order_key and (step as ProduceAction).target_building == building:
			return true
	return false


# Riservati a un rito, tenuti per l'edificio e cotture automatiche non si scalzano.
static func _is_evictable_kind(building: Building, order_key: String) -> bool:
	var record: Dictionary = building.production_progress[order_key]
	return String(record.get(ProductionService.RESERVED_FOR_KEY, "")) == "" and not bool(record.get("keep_for_building", false)) \
		and not ProductionService.is_order_auto_cook(building, order_key)


# Numero della chiave d'ordine ("o12" -> 12): più basso = creato prima.
static func _order_index(order_key: String) -> int:
	return int(order_key.trim_prefix(ProductionService.ORDER_KEY_PREFIX))
