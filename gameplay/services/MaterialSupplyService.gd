class_name MaterialSupplyService
extends RefCounted

# Rifornimento automatico di materiale a un cantiere (2026-09-29, richiesta utente) — service stateless, stesso
# pattern degli altri *Service. Diviso in due parti INDIPENDENTI:
#   (a) FABBISOGNO — funzioni pure, nessun effetto collaterale: dato il bersaglio, quale risorsa manca, quanta e da
#       quale sorgente prelevarla. Non conosce Task/Action/individui: in futuro lo stesso fabbisogno potrà essere
#       soddisfatto in altro modo (Task assegnate ad altri pipottini) riusando solo questa parte.
#   (b) SODDISFAZIONE "livello 0" — il pipottino bloccato va da sé: inserisce nella SUA Task, prima dello step
#       corrente, Walk → Retrieve → Walk → Unload verso il bersaglio. Usa (a), mai il contrario.
#
# Fasi coperte (gli "step riforniti" di is_supplied_step): setup site (BuildingRules.setup_site_material_name,
# SetupSiteAction), costruzione (BuildingRules.required_materials, BuildAction) e, dal 2026-09-29, produzione presso
# una workstation (input delle ricette per l'ordine intero, poi combustibile — ProduceAction). Il resto è generico sul
# nome della risorsa; il combustibile passa dalla voce speciale FUEL_KEY, risolta in una risorsa vera solo quando si
# sceglie la sorgente (get_supply_need). L'aggancio vive in HumanIndividualActionService
# (_handle_pending_material_shortage, retry_blocked_material_shortages, activate_resumed_task).
#
# Ripetizione "a giri": nessun contatore. Finito l'Unload, lo step bloccato torna corrente, la sua activate() riscrive
# pending_material_shortage se manca ancora qualcosa e il giro successivo parte da lì.

# Protezione dai loop: scritto da RetrieveAction.on_complete (modalità material_supply) quando il prelievo di
# rifornimento non ha portato nulla nello zaino. Consumato dal tentativo successivo (try_supply_at_level_zero), che
# allora rinuncia e lascia ricadere nell'attesa; il retry giornaliero ritenta da capo.
const CONTEXT_SUPPLY_FAILED := "material_supply_failed"

# Ordine del giocatore arrivato a metà di un giro con lo zaino carico (2026-09-29, richiesta utente): scritto da
# HumanIndividual.assign_task (l'ordine va in coda), consumato da HumanIndividualActionService.finish_current_step al
# primo Unload del giro completato — la Build va in coda e parte l'ordine. Salvato con il context.
const CONTEXT_YIELD_AFTER_DELIVERY := "material_supply_yield_after_delivery"

# Voce di get_missing_materials per il combustibile mancante di una workstation (2026-09-29): il valore è il
# combustibile mancante (float, in unità di fuel_value), non una quantità di risorsa — quale risorsa portare lo decide
# get_supply_need in base al magazzino sorgente. Sempre l'ultima voce: prima gli input delle ricette.
const FUEL_KEY := "__fuel__"


# ============================================================================================
# (a) FABBISOGNO — nessun effetto collaterale
# ============================================================================================

# {resource_name: quantità mancante} del bersaglio, vuoto se nulla manca, per la fase in corso del cantiere:
#   - setup site (site_setup_complete false): stessa formula di SetupSiteAction.get_missing_material_quantity;
#   - costruzione (site_setup_complete true): required_materials meno lo stoccato, stessa formula di
#     BuildAction.get_missing_materials, nell'ordine in cui required_materials le elenca (un giro per risorsa);
#   - workstation completa (produzione): input mancanti per l'ORDINE INTERO delle produzioni in corso
#     (ProductionService.get_missing_inputs, la stessa base di get_production_demand/get_max_depositable), poi il
#     combustibile mancante come voce FUEL_KEY (ProductionService.get_missing_fuel).
static func get_missing_materials(target_building: Building) -> Dictionary:
	var missing: Dictionary = {}
	if target_building == null or target_building.rules == null:
		return missing
	if target_building.is_demolished or target_building.is_out_of_service():
		return missing
	# In finitura (2026-10-17, giorni minimi): materiali già consumati, nessun fabbisogno.
	if BuildingLifecycleService.is_finishing(target_building):
		return missing
	# Rito sociale in preparazione (2026-10-16, banchetto): prima il combustibile, poi la carne (SocialRiteService).
	if SocialRiteService.is_preparing(target_building):
		return SocialRiteService.get_preparation_missing(target_building)
	if target_building.is_complete:
		if not target_building.rules.is_workstation:
			return missing
		var missing_inputs := ProductionService.get_missing_inputs(target_building)
		for input_name in missing_inputs.keys():
			missing[String(input_name)] = int(missing_inputs[input_name])
		var missing_fuel := ProductionService.get_missing_fuel(target_building)
		if missing_fuel > 0.0:
			missing[FUEL_KEY] = missing_fuel
		return missing
	if not target_building.site_setup_complete:
		var material_name: String = target_building.rules.setup_site_material_name
		var required: int = target_building.rules.setup_site_material_per_cell * target_building.rules.required_space
		if material_name == "" or required <= 0:
			return missing
		var stored_entry: Dictionary = target_building.stored_resources.get(material_name, {})
		var missing_quantity: int = maxi(required - int(stored_entry.get("quantity", 0)), 0)
		if missing_quantity > 0:
			missing[material_name] = missing_quantity
		return missing
	for resource_name in target_building.rules.required_materials.keys():
		var required_build: int = int(target_building.rules.required_materials[resource_name])
		if required_build <= 0:
			continue
		var stored_build_entry: Dictionary = target_building.stored_resources.get(resource_name, {})
		var missing_build: int = maxi(required_build - int(stored_build_entry.get("quantity", 0)), 0)
		if missing_build > 0:
			missing[String(resource_name)] = missing_build
	return missing


# Fabbisogno da soddisfare adesso per `target_building`, visto da `origin_position` (chi andrà a prelevare):
#   {} se non manca nulla (o nulla è depositabile);
#   altrimenti {"resource_name", "quantity", "source"} — quantity = min(mancante, BuildingStorageService.
#   get_max_depositable), che il Retrieve limiterà poi allo zaino; source = magazzino più vicino con almeno un'unità
#   (WarehouseSelectionService.find_source_for_retrieval), escludendo il bersaglio; da una workstation solo i suoi
#   Prodotti finiti, mai il suo magazzino (2026-10-08, BuildingStorageService.withdraw_auto). source null
#   = la risorsa manca ma nessuna sorgente la ha. Con più risorse mancanti vince la prima che ha una sorgente.
# Combustibile (FUEL_KEY): per resa (2026-10-22, find_fuel_source: fuel_value / spazio, la legna da ardere prima dei
# rametti) la sorgente più vicina che ha il combustibile migliore, il successivo solo se quello non c'è da nessuna parte;
# quantità =
# combustibile mancante / fuel_value arrotondato per eccesso, limitata da get_max_depositable.
# `carrier` (2026-10-16, materiali troppo pesanti): se c'è, le risorse di cui non porta nemmeno un'unità a zaino vuoto
# (get_uncarryable_materials) sono saltate, così porta prima quelle che può.
# `for_repair` (2026-10-10, materiali della riparazione): fabbisogno = RepairAction.get_supply_missing (piano meno
# consumato meno contenitore), nessuna sorgente esclusa (chi ripara un deposito può prendere dalle sue stesse scorte) e
# quantità non limitata dal magazzino del bersaglio (si scarica nel contenitore della riparazione).
static func get_supply_need(
	world: World, target_building: Building, origin_position: Vector2, origin_macro_coords: Vector2i,
	reachable: Callable = Callable(), for_repair: bool = false, carrier: HumanIndividual = null
) -> Dictionary:
	var missing := RepairAction.get_supply_missing(target_building) if for_repair else get_missing_materials(target_building)
	if missing.is_empty() or world == null:
		return {}
	# Più costruttori (2026-10-17): via quello che altri stanno già portando a questo cantiere (niente viaggi doppi).
	if not for_repair:
		missing = subtract_in_transit(target_building, missing, carrier)
		if missing.is_empty():
			return {}
	# Mai un'espressione ternaria con [] qui: il letterale non è tipizzato e l'assegnazione a Array[int] fallisce a runtime.
	var excluded: Array[int] = []
	if not for_repair:
		excluded = _get_excluded_source_ids(world, target_building)
	var first_need: Dictionary = {}
	for resource_name in missing.keys():
		if carrier != null and resource_name != FUEL_KEY and not carrier.can_carry_one_unit_when_empty(String(resource_name)):
			continue
		var need: Dictionary
		if resource_name == FUEL_KEY:
			need = _get_fuel_need(world, target_building, float(missing[resource_name]), origin_position, origin_macro_coords, excluded, reachable)
			if need.is_empty():
				continue
		else:
			var quantity: int = int(missing[resource_name]) if for_repair \
				else mini(int(missing[resource_name]), BuildingStorageService.get_max_depositable(target_building, String(resource_name)))
			if quantity <= 0:
				continue
			var source := WarehouseSelectionService.find_source_for_retrieval(
				world, origin_position, origin_macro_coords, String(resource_name), excluded, 1, -1, reachable, true
			)
			need = {"resource_name": String(resource_name), "quantity": quantity, "source": source}
		if need["source"] != null:
			return need
		if first_need.is_empty():
			first_need = need
	return first_need


# Materiale in viaggio verso `building` (2026-10-17, più costruttori): `resource_name` che gli altri pipottini (non
# `excluded`) stanno portando con un rifornimento — Retrieve di rifornimento non ancora fatto (quantità chiesta) oppure
# carico nello zaino con lo scarico al cantiere ancora da fare.
static func get_in_transit(building: Building, resource_name: String, excluded: HumanIndividual = null) -> int:
	var total := 0
	for member in GameSettings.active_human_individuals:
		if member == excluded:
			continue
		for task in JobWorkScanService.open_tasks(member):
			var unload_pending := false
			var retrieve_pending := 0
			for step_index in range(task.current_step_index, task.steps.size()):
				var step: Action = task.steps[step_index]
				if step is RetrieveAction:
					var retrieve := step as RetrieveAction
					if retrieve.material_supply and retrieve.supply_target_building == building and retrieve.resource_name == resource_name:
						retrieve_pending += retrieve.quantity_requested
				elif step is UnloadAction and (step as UnloadAction).target_building == building:
					unload_pending = true
			if retrieve_pending > 0:
				total += retrieve_pending
			elif unload_pending and task == member.current_task:
				total += member.get_carried_quantity(resource_name)
	return total


# `missing` meno il materiale in viaggio verso `building` (get_in_transit), per nome; le voci coperte spariscono. Il
# combustibile (FUEL_KEY) resta com'è (lo porta un solo lavoratore per volta).
static func subtract_in_transit(building: Building, missing: Dictionary, excluded: HumanIndividual = null) -> Dictionary:
	var result: Dictionary = {}
	for resource_name in missing.keys():
		if String(resource_name) == FUEL_KEY:
			result[resource_name] = missing[resource_name]
			continue
		var left := int(missing[resource_name]) - get_in_transit(building, String(resource_name), excluded)
		if left > 0:
			result[resource_name] = left
	return result


# true se tutto quello che manca a `building` sta già arrivando con altri pipottini: chi è fermo aspetta sul posto.
static func is_fully_in_transit(building: Building, excluded: HumanIndividual = null) -> bool:
	var missing := get_missing_materials(building)
	return not missing.is_empty() and subtract_in_transit(building, missing, excluded).is_empty()


# Materiali troppo pesanti (2026-10-16, richiesta utente — pietra da 50 con capacità 49): risorse ancora mancanti a
# `target_building` di cui `individual` non porta nemmeno un'unità a zaino vuoto, con la cintura attuale
# (HumanIndividual.can_carry_one_unit_when_empty). Il combustibile è escluso: sceglie da sé la risorsa al prelievo.
static func get_uncarryable_materials(individual: HumanIndividual, target_building: Building, for_repair: bool = false) -> Array[String]:
	var names: Array[String] = []
	if individual == null or target_building == null:
		return names
	var missing := RepairAction.get_supply_missing(target_building) if for_repair else get_missing_materials(target_building)
	for resource_name in missing.keys():
		if resource_name != FUEL_KEY and not individual.can_carry_one_unit_when_empty(String(resource_name)):
			names.append(String(resource_name))
	return names


# Risorse mancanti a `target_building` che nessuno di `individuals` porta (stesso controllo di get_uncarryable_materials):
# l'avviso "nessuno può trasportare" della campanella. Vuoto se nessuno è nel gruppo.
static func get_materials_nobody_can_carry(individuals: Array[HumanIndividual], target_building: Building, for_repair: bool = false) -> Array[String]:
	var names: Array[String] = []
	if individuals.is_empty():
		return names
	for resource_name in get_uncarryable_materials(individuals[0], target_building, for_repair):
		var someone_can := false
		for member in individuals:
			if member.can_carry_one_unit_when_empty(resource_name):
				someone_can = true
				break
		if not someone_can:
			names.append(resource_name)
	return names


# Fabbisogno di combustibile (vedi get_supply_need). {} se nulla è depositabile; source null se nessun magazzino ha
# combustibile.
static func _get_fuel_need(
	world: World, target_building: Building, missing_fuel: float, origin_position: Vector2, origin_macro_coords: Vector2i,
	excluded: Array[int], reachable: Callable
) -> Dictionary:
	var found := find_fuel_source(world, origin_position, origin_macro_coords, excluded, reachable)
	if found.is_empty():
		return {"resource_name": FUEL_KEY, "quantity": 0, "source": null}
	var source: Building = found["source"]
	var fuel_name := String(found["resource"])
	var fuel_value := ProductionService.get_fuel_value(fuel_name)
	if fuel_name == "" or fuel_value <= 0.0:
		return {}
	var units: int = int(ceil(missing_fuel / fuel_value - ProductionService.FUEL_EPSILON))
	var quantity: int = mini(units, BuildingStorageService.get_max_depositable(target_building, fuel_name))
	if quantity <= 0:
		return {}
	return {"resource_name": fuel_name, "quantity": quantity, "source": source}


# Risorsa con fuel_value più alto tra quelle disponibili in `building` (a parità, in ordine di nome — stesso ordine
# di ProductionService._consume_fuel); "" se nessuna.
# Combustibile migliore presente in `building`, per resa (fuels_by_yield). "" se nessuno.
static func best_fuel_in(building: Building) -> String:
	var present := WarehouseSelectionService.get_matching_stock(building, WarehouseSelectionService.FUEL_CRITERION, 1, true)
	for fuel_name in fuels_by_yield():
		if present.has(fuel_name):
			return fuel_name
	return ""


# Combustibili ordinati per RESA (2026-10-22, richiesta utente): fuel_value / space_per_unit decrescente, a parità per nome
# (legna da ardere 1/3 prima dei rametti 1/10: a parità di calore pesano un terzo e i rametti servono per costruire).
static var _fuels_by_yield_cache: Array[String] = []


static func fuels_by_yield() -> Array[String]:
	if not _fuels_by_yield_cache.is_empty():
		return _fuels_by_yield_cache
	var fuels: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if ProductionService.get_fuel_value(String(resource_name)) > 0.0:
			fuels.append(String(resource_name))
	fuels.sort_custom(func(a: String, b: String) -> bool:
		var yield_a := _fuel_yield(a)
		var yield_b := _fuel_yield(b)
		return yield_a > yield_b if not is_equal_approx(yield_a, yield_b) else a < b
	)
	_fuels_by_yield_cache = fuels
	return fuels


static func _fuel_yield(resource_name: String) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null or rules.space_per_unit <= 0.0:
		return ProductionService.get_fuel_value(resource_name)
	return rules.fuel_value / rules.space_per_unit


# Sorgente di combustibile (2026-10-22): per ogni combustibile in ordine di resa, la sorgente raggiungibile più vicina che
# lo ha (Prodotti finiti delle postazioni compresi, combustibile delle case escluso); vince il primo combustibile trovato.
# {"source": Building, "resource": String} o {} se nessuna sorgente ha combustibile.
static func find_fuel_source(
	world: World, origin_position: Vector2, origin_macro_coords: Vector2i, excluded: Array[int], reachable: Callable
) -> Dictionary:
	for fuel_name in fuels_by_yield():
		var source := WarehouseSelectionService.find_source_for_retrieval(
			world, origin_position, origin_macro_coords, fuel_name, excluded, 1, -1, reachable, true
		)
		if source != null:
			return {"source": source, "resource": fuel_name}
	return {}


# Id esclusi come sorgente: il solo bersaglio. Le workstation non sono più escluse in blocco (2026-10-03, essiccazione
# passo 3): sono sorgenti solo per i loro Prodotti finiti, filtro applicato dalla ricerca (find_source_for_retrieval
# con workstation_products_only) e dal prelievo (RetrieveAction material_supply -> BuildingStorageService.withdraw_auto).
static func _get_excluded_source_ids(_world: World, target_building: Building) -> Array[int]:
	return [target_building.id]


# ============================================================================================
# (b) SODDISFAZIONE "livello 0" — il pipottino bloccato si rifornisce da solo
# ============================================================================================

# Prova a far rifornire `target_building` all'individuo che lavora `task` (la sua current_task, ferma sullo step
# bloccato). true = step inseriti prima dello step corrente e il nuovo step corrente già attivato; false = nessun
# rifornimento possibile, il chiamante ricade nell'attesa di oggi (_resolve_material_shortage). Casi:
#   - l'ultimo Retrieve di rifornimento non ha portato nulla (CONTEXT_SUPPLY_FAILED) → false, niente nuovo giro;
#   - lo zaino contiene già una risorsa mancante → Walk → Unload al bersaglio (anche senza sorgente);
#   - nessuna sorgente → false (le risorse che l'individuo non porta sono saltate: vedi get_supply_need `carrier`);
#   - zaino con altro → prima Walk → Unload al magazzino più vicino che lo accetta (nessuno → false), poi il giro;
#   - zaino vuoto → Walk → Retrieve → Walk → Unload.
static func try_supply_at_level_zero(individual: HumanIndividual, task: Task, world: World, target_building: Building) -> bool:
	if individual == null or task == null or world == null or target_building == null:
		return false
	if task.context.has(CONTEXT_SUPPLY_FAILED):
		task.context.erase(CONTEXT_SUPPLY_FAILED)
		_log(individual, target_building, "l'ultimo prelievo di rifornimento non ha portato nulla — nessun nuovo giro, attesa.")
		return false
	# Riparazione (2026-10-10, passo 3): fabbisogno del piano, scarico dedicato nel contenitore della riparazione.
	var for_repair: bool = task.get_current_action() is RepairAction
	var deposit_kind := UnloadAction.DepositKind.REPAIR if for_repair else UnloadAction.DepositKind.RESOURCE
	var missing := RepairAction.get_supply_missing(target_building) if for_repair else get_missing_materials(target_building)
	if missing.is_empty():
		return false

	var new_steps: Array[Action] = []
	var descriptions: Array[String] = []

	for resource_name in missing.keys():
		if _is_carrying_for(individual, target_building, String(resource_name)):
			_append_walk_and_unload(individual, target_building, new_steps, descriptions, deposit_kind)
			_insert_and_activate(individual, task, new_steps, descriptions)
			_log(individual, target_building, "ha già '%s' nello zaino — lo scarica al cantiere." % resource_name)
			return true

	var reachable := PathfindingService.reachability_for(individual)
	var need := get_supply_need(world, target_building, individual.position, individual.home_macro_coords, reachable, for_repair, individual)
	if need.is_empty() or need["source"] == null:
		_log(individual, target_building, "nessun magazzino ha %s — attesa." % str(missing))
		return false
	var source: Building = need["source"]
	var need_resource_name: String = need["resource_name"]
	var quantity: int = int(need["quantity"])

	if not individual.carried_resources.is_empty():
		var carried_name := String(individual.carried_resources.keys()[0])
		var excluded: Array[int] = [target_building.id]
		var warehouse := WarehouseSelectionService.find_best(
			world, individual.position, individual.home_macro_coords, carried_name,
			individual.get_carried_quantity(carried_name), excluded, reachable
		)
		if warehouse == null:
			_log(individual, target_building, "zaino occupato (%s) e nessun magazzino lo accetta — attesa." % str(individual.carried_resources.keys()))
			return false
		_append_walk_and_unload(individual, warehouse, new_steps, descriptions)

	new_steps.append(WalkAction.new(_building_point(individual, source)))
	descriptions.append("task_transport_step_walk_to_source")
	new_steps.append(RetrieveAction.new(source, need_resource_name, quantity, -1, false, true, target_building))
	descriptions.append("task_transport_step_retrieve")
	_append_walk_and_unload(individual, target_building, new_steps, descriptions, deposit_kind)
	_insert_and_activate(individual, task, new_steps, descriptions)
	_log(individual, target_building, "va a prendere %d '%s' da %s #%d (%d step inseriti)." % [
		quantity, need_resource_name, source.building_type_name, source.id, new_steps.size()
	])
	return true


# true se lo zaino contiene già qualcosa che copre la voce `key` del fabbisogno: la risorsa stessa, oppure — per
# FUEL_KEY — una qualunque risorsa con fuel_value > 0 che il bersaglio accetta ancora.
static func _is_carrying_for(individual: HumanIndividual, target_building: Building, key: String) -> bool:
	if key != FUEL_KEY:
		return individual.get_carried_quantity(key) > 0
	for raw_name in individual.carried_resources.keys():
		var carried_name := String(raw_name)
		if individual.get_carried_quantity(carried_name) > 0 and ProductionService.get_fuel_value(carried_name) > 0.0 \
				and BuildingStorageService.get_max_depositable(target_building, carried_name) > 0:
			return true
	return false


# --- Giro di rifornimento in corso: riconoscimento, annullo, ripresa ---
# Un giro finisce sempre con l'Unload al cantiere bersaglio dello step bloccato (SetupSiteAction o BuildAction della
# Build Task), che nessun altro percorso inserisce: i re-routing dei residui puntano a magazzini, mai a un cantiere
# incompleto.

# true se `action` è uno step che il rifornimento sa sbloccare (2026-09-29: setup site e costruzione). Unico punto da
# allargare per nuove fasi — i controlli in HumanIndividualActionService passano da qui.
# Riparazione (2026-10-10, materiali della riparazione — passo 3): RepairAction, con lo scarico dedicato.
# Rito sociale (2026-10-16): SocialRiteAttendAction dell'organizzatore in preparazione.
static func is_supplied_step(action: Action) -> bool:
	return action is SetupSiteAction or action is BuildAction or action is ProduceAction or action is RepairAction \
		or action is SocialRiteAttendAction


# Step di lavoro sul cantiere (setup, sgombero, costruzione): un giro di rifornimento sta sempre prima di uno di questi,
# mai a cavallo — _find_round_end_index si ferma al primo che incontra.
static func _is_site_work_step(action: Action) -> bool:
	return action is SetupSiteAction or action is ClearAction or action is BuildAction or action is ProduceAction or action is RepairAction \
		or action is SocialRiteAttendAction

# Accessi pubblici per HumanIndividualActionService (avanzo di fine giro: Walk di ritorno al cantiere).
static func get_supply_target(task: Task) -> Building:
	return _get_supply_target(task)


static func building_point(individual: HumanIndividual, building: Building) -> Vector2:
	return _building_point(individual, building)


# Cantiere del giro di rifornimento: il bersaglio del primo step di lavoro sul cantiere della Task (SetupSite/Clear/
# Build, tutti sullo stesso edificio nella Build Task); null se non ce n'è.
static func _get_supply_target(task: Task) -> Building:
	if task == null:
		return null
	for step in task.steps:
		if _is_site_work_step(step):
			var site: Building = step.get("target_building")
			if site != null:
				return site
	return null


# Indice dell'Unload al cantiere che chiude il giro in corso (da current_step_index in poi), -1 se nessun giro in corso.
static func _find_round_end_index(task: Task) -> int:
	var site := _get_supply_target(task)
	if site == null or task.is_finished():
		return -1
	for i in range(task.current_step_index, task.steps.size()):
		var step: Action = task.steps[i]
		# Scarico al bersaglio: nel magazzino del cantiere o, per la riparazione, nel suo contenitore (2026-10-10).
		if step is UnloadAction and ((step as UnloadAction).deposit_kind == UnloadAction.DepositKind.RESOURCE \
				or (step as UnloadAction).deposit_kind == UnloadAction.DepositKind.REPAIR) \
				and (step as UnloadAction).target_building == site:
			return i
		if _is_site_work_step(step):
			return -1
	return -1


# true se `task` è a metà di un giro di rifornimento (ordine del giocatore a metà giro, avanzo, ripresa dalla coda).
static func is_in_supply_round(task: Task) -> bool:
	return _find_round_end_index(task) >= 0


# Ripresa dalla coda (2026-09-29): un giro il cui prelievo non è ancora avvenuto va ripianificato — nel frattempo la
# sorgente può essersi svuotata o il cantiere essere stato rifornito da altri. Toglie gli step del giro (dallo step
# corrente all'Unload al cantiere compreso), così lo step bloccato torna corrente e la sua activate() riscrive il
# fabbisogno. Un giro già caricato (Retrieve eseguito) resta: il carico va consegnato. true = step rimossi.
static func drop_pending_supply_round(task: Task) -> bool:
	var end_index := _find_round_end_index(task)
	if end_index < 0:
		return false
	var has_pending_retrieve := false
	for i in range(task.current_step_index, end_index):
		if task.steps[i] is RetrieveAction and (task.steps[i] as RetrieveAction).material_supply:
			has_pending_retrieve = true
			break
	if not has_pending_retrieve:
		return false
	task.remove_steps(task.current_step_index, end_index - task.current_step_index + 1)
	return true


static func _append_walk_and_unload(
	individual: HumanIndividual, building: Building, steps: Array[Action], descriptions: Array[String],
	deposit_kind: UnloadAction.DepositKind = UnloadAction.DepositKind.RESOURCE
) -> void:
	steps.append(WalkAction.new(_building_point(individual, building)))
	descriptions.append("task_transport_step_walk_to_destination")
	steps.append(UnloadAction.new(building, deposit_kind))
	descriptions.append("task_transport_step_unload")


# Punto casuale nella microcella dell'edificio, nel sistema di coordinate dell'individuo (stessa formula di
# get_required_position di SetupSiteAction/RetrieveAction).
static func _building_point(individual: HumanIndividual, building: Building) -> Vector2:
	var macro_offset: Vector2 = Vector2(Vector2i(building.macro_x, building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(building.micro_x, building.micro_y) + macro_offset)


# Lo step bloccato scivola dopo i nuovi step e verrà riattivato (activate) quando la catena finisce.
static func _insert_and_activate(individual: HumanIndividual, task: Task, steps: Array[Action], descriptions: Array[String]) -> void:
	task.insert_steps_before_current(steps, descriptions)
	task.get_current_action().activate(individual, task.context)


static func _log(individual: HumanIndividual, target_building: Building, message: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[MATERIAL SUPPLY] #%d %s, cantiere #%d: %s" % [individual.id, individual.name, target_building.id, message])
