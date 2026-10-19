class_name WasteDisposalService
extends RefCounted

# Fossa dei rifiuti (2026-10-18, richiesta utente — passo "trasporto manuale verso la fossa"): quanto ci sta e il
# getto vero e proprio. Quello che entra nella fossa è distrutto: occupa solo spazio (Building.waste_stored), mai
# stoccato né riprendibile. Spazio di una merce = quantità × SecondaryResourceRules.space_per_unit, arrotondato per
# eccesso. Volutamente FUORI da BuildingStorageService.can_accept/get_max_depositable: la fossa riceve solo da chi la
# sceglie esplicitamente (Transport manuale), mai dalle ricerche automatiche di un magazzino (reinstradamenti, ritorno
# del carico), che altrimenti ci butterebbero merce buona.
# Prenotazione dello spazio (Building.waste_reserved): non ancora usata. Se due portatori arrivano insieme e il secondo
# non trova posto, il residuo segue il reinstradamento già esistente di UnloadAction; i rifiuti (waste_only, es. i
# detriti) non entrano in nessun magazzino e finiscono a terra.
#
# Macerie (2026-10-18, richiesta utente — sgombero con viaggi veri): al crollo le macerie ricevono DEBRIS_RESOURCE nel
# proprio deposito (rubble_debris_quantity: spazio dei materiali di costruzione dell'edificio crollato, senza i legnetti
# dell'allestimento, / RUBBLE_DEBRIS_SPACE_DIVISOR,
# minimo RUBBLE_MIN_DEBRIS); "Sgombera" è una Transport ripetuta dalle macerie alla Fossa più vicina con posto
# (build_debris_clearing_task); a detriti finiti le macerie spariscono (BuildingMaintenanceService.emptied_rubble).
#
# Svuota la Fossa (2026-10-18, richiesta utente): i rifiuti passano nel deposito della Fossa come detriti (1 di spazio = 1
# detrito) e si portano a viaggi in un'altra Fossa con lo stesso sgombero; la Fossa resta "chiusa ai rifiuti"
# (Building.waste_closed) anche a fine svuotamento, così il lavoro finisce davvero e la si può demolire. Macerie da
# sgomberare e Fosse in svuotamento sono le "sorgenti di detriti" (is_debris_source).
const DEBRIS_RESOURCE := "debris"
const RUBBLE_DEBRIS_SPACE_DIVISOR: float = 10.0
const RUBBLE_MIN_DEBRIS: int = 10
# Ceppi (2026-10-18, richiesta utente): detriti di base per ogni ceppo tolto dalla pulizia di un cantiere (ClearAction),
# moltiplicati per la taglia del ceppo (BuildingSiteClearingService.stump_debris). Erba e piante morte non ne producono.
const DEBRIS_PER_TREE_STUMP: int = 10
const DEBRIS_PER_SHRUB_STUMP: int = 3


# true per una fossa che riceve rifiuti: completa (BuildingRules.waste_capacity > 0), non demolita, non chiusa ai rifiuti
# e non in svuotamento. Un cantiere di fossa riceve i legnetti dell'allestimento come ogni altro cantiere.
static func is_waste_pit(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.waste_capacity > 0 \
		and building.is_complete and not building.is_demolished and not building.waste_closed and not building.waste_emptying


# Unità di `resource_name` che entrano ancora nella fossa (0 se non è una fossa o è piena).
static func get_max_disposable(building: Building, resource_name: String) -> int:
	if not is_waste_pit(building):
		return 0
	var free_space: int = building.get_waste_free_space()
	if free_space <= 0:
		return 0
	var space_per_unit: float = _space_per_unit(resource_name)
	if space_per_unit <= 0.0:
		return 1 << 30
	return floori(float(free_space) / space_per_unit + 0.000001)


# Getta fino a `quantity` unità di `resource_name` nella fossa; ritorna quante ne sono entrate. Lo zaino lo svuota chi
# chiama (UnloadAction).
static func dispose(building: Building, resource_name: String, quantity: int) -> int:
	var units: int = mini(quantity, get_max_disposable(building, resource_name))
	if units <= 0:
		return 0
	var space: int = ceili(float(units) * _space_per_unit(resource_name) - 0.000001)
	building.waste_stored = mini(building.waste_stored + space, building.rules.waste_capacity)
	return units


static func _space_per_unit(resource_name: String) -> float:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return resource_rules.space_per_unit if resource_rules != null else 0.0


# true per una risorsa che si può solo buttare (SecondaryResourceRules.waste_only, es. i detriti).
static func is_waste_only(resource_name: String) -> bool:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return resource_rules != null and resource_rules.waste_only


# Detriti che nascono dal crollo di un edificio di tipo `source_type`: spazio dei suoi materiali di costruzione /
# divisore, per eccesso.
static func rubble_debris_quantity(source_type: String) -> int:
	var space: float = 0.0
	var source_rules: BuildingRules = BuildingCalculator.get_building_rules(source_type) if source_type != "" else null
	if source_rules != null:
		for material_name in source_rules.required_materials.keys():
			space += float(source_rules.required_materials[material_name]) * _space_per_unit(String(material_name))
	return maxi(ceili(space / RUBBLE_DEBRIS_SPACE_DIVISOR - 0.000001), RUBBLE_MIN_DEBRIS)


# Detriti della demolizione di un edificio con regole `rules` (2026-10-18, richiesta utente): la metà dei materiali che
# non si recupera (required − floor(required/2), come BuildingLifecycleService.complete_demolition) × space_per_unit /
# divisore, per eccesso. Nessun minimo: 0 = nessuna maceria (edificio senza materiali).
static func demolition_debris_quantity(rules: BuildingRules) -> int:
	if rules == null:
		return 0
	var space: float = 0.0
	for material_name in rules.required_materials.keys():
		var required: int = int(rules.required_materials[material_name])
		var lost: int = required - floori(float(required) / 2.0)
		space += float(lost) * _space_per_unit(String(material_name))
	return maxi(ceili(space / RUBBLE_DEBRIS_SPACE_DIVISOR - 0.000001), 0)


# Detriti rimasti in una sorgente di detriti (macerie, Fossa in svuotamento).
static func get_debris(building: Building) -> int:
	return int((building.stored_resources.get(DEBRIS_RESOURCE, {}) as Dictionary).get("quantity", 0))


# true per una Fossa (completa, non demolita), qualunque sia il suo stato.
static func is_pit(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.waste_capacity > 0 and building.is_complete \
		and not building.is_demolished


# Sorgente di detriti da portare in una Fossa: macerie, una Fossa in svuotamento, o un cantiere con i detriti dei suoi
# ceppi rimasti dentro (2026-10-18: nessuna cella libera vicina per una maceria, la costruzione aspetta lo sgombero).
static func is_debris_source(building: Building) -> bool:
	return building != null and (building.is_rubble() or (is_pit(building) and building.waste_emptying) or has_site_debris(building))


# Sorgente di detriti con un lavoro aperto: macerie da sgomberare, Fossa in svuotamento, cantiere con detriti.
static func has_debris_job(building: Building) -> bool:
	return building != null and ((building.is_rubble() and building.is_marked_for_demolition) or (is_pit(building) and building.waste_emptying) \
		or has_site_debris(building))


# Cantiere (non completo, non demolito) con detriti dei ceppi da portare alla Fossa prima di costruire.
static func has_site_debris(building: Building) -> bool:
	return building != null and not building.is_complete and not building.is_demolished and not building.is_rubble() \
		and get_debris(building) > 0


# Spazio occupato mostrato nel pannello della Fossa: rifiuti più i detriti ancora da portare via (in svuotamento).
static func get_pit_fill(pit: Building) -> int:
	return pit.waste_stored + get_debris(pit)


# Mette i detriti nelle macerie (crollo: la parte di questa maceria; salvataggi precedenti senza detriti: -1 = il calcolo
# intero, erano tutte macerie di edifici 1x1). Scritti direttamente: le macerie non hanno slot di magazzino,
# BuildingStorageService.store li rifiuterebbe.
static func seed_rubble_debris(rubble: Building, quantity: int = -1) -> void:
	var debris: int = quantity if quantity >= 0 else rubble_debris_quantity(rubble.rubble_source_name)
	rubble.stored_resources[DEBRIS_RESOURCE] = {"quantity": debris, "decay_fraction": 0.0}


# Fossa con almeno `space` di spazio libero più vicina a `near`; null se nessuna.
static func find_pit_for(world: World, space: int, near: Building) -> Building:
	if world == null:
		return null
	var best: Building = null
	var best_distance: float = INF
	var origin: Vector2 = InfluenceService.building_absolute_center(near) if near != null else Vector2.ZERO
	for building in world.buildings:
		if not is_waste_pit(building) or building.get_waste_free_space() < space:
			continue
		var distance: float = InfluenceService.building_absolute_center(building).distance_to(origin)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


# Fossa di destinazione per i detriti di `source`: la più vicina dove entra almeno un detrito. La sorgente stessa non è mai
# candidata (una Fossa in svuotamento non riceve, is_waste_pit).
static func find_pit_for_debris(world: World, source: Building) -> Building:
	return find_pit_for(world, maxi(ceili(_space_per_unit(DEBRIS_RESOURCE)), 1), source)


# Transport dei detriti (2026-10-18): dalla sorgente (macerie, Fossa in svuotamento) alla Fossa più vicina con posto, tutti
# i detriti rimasti, con ripetizione. null se mancano detriti o una Fossa con posto. Il contesto porta
# CONTEXT_DEBRIS_CLEARING (nome del compito e bacheca lavori; valore "rubble_clearing" invariato per i salvataggi).
const CONTEXT_DEBRIS_CLEARING := "rubble_clearing"


static func build_debris_clearing_task(world: World, worker: HumanIndividual, source: Building) -> Task:
	var debris: int = get_debris(source)
	if debris <= 0:
		return null
	var pit := find_pit_for_debris(world, source)
	if pit == null:
		return null
	var trip_target: int = TaskBuilderService.transport_trip_target(pit, DEBRIS_RESOURCE, debris)
	if trip_target <= 0:
		return null
	var task := TaskBuilderService.build_transport_task(worker, source, pit, DEBRIS_RESOURCE, trip_target, debris, true, 0)
	if task != null:
		task.context[CONTEXT_DEBRIS_CLEARING] = true
		# Posizione della sorgente (2026-10-18): la catena passa alle macerie vicine anche dopo che questa è sparita.
		task.context[CONTEXT_DEBRIS_SOURCE_CELL] = {"macro_x": source.macro_x, "macro_y": source.macro_y, "micro_x": source.micro_x, "micro_y": source.micro_y}
	return task


const CONTEXT_DEBRIS_SOURCE_CELL := "debris_source_cell"
# Distanza massima (microcelle, Chebyshev) delle macerie su cui prosegue chi ha finito di sgomberarne una.
const NEXT_RUBBLE_RADIUS: int = 2


# Macerie da sgomberare (con detriti) più vicine alla cella `cell` (Dictionary di CONTEXT_DEBRIS_SOURCE_CELL), nella stessa
# macrocella ed entro NEXT_RUBBLE_RADIUS; null se nessuna. Per finire di fila un edificio grande crollato o demolito.
static func find_next_rubble(world: World, cell: Dictionary) -> Building:
	if world == null or cell.is_empty():
		return null
	var macro := Vector2i(int(cell.get("macro_x", -1)), int(cell.get("macro_y", -1)))
	var micro := Vector2i(int(cell.get("micro_x", 0)), int(cell.get("micro_y", 0)))
	var best: Building = null
	var best_distance: float = INF
	for building in world.buildings:
		if not building.is_rubble() or building.is_demolished or not building.is_marked_for_demolition:
			continue
		if building.macro_x != macro.x or building.macro_y != macro.y or get_debris(building) <= 0:
			continue
		var offset := Vector2i(building.micro_x, building.micro_y) - micro
		if maxi(absi(offset.x), absi(offset.y)) > NEXT_RUBBLE_RADIUS:
			continue
		var distance := Vector2(offset).length()
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


# true se `task` porta via detriti (dalla sorgente `source_id`, o da qualunque sorgente con -1).
static func is_debris_clearing_task(task: Task, source_id: int = -1) -> bool:
	if task == null or not bool(task.context.get(CONTEXT_DEBRIS_CLEARING, false)):
		return false
	return source_id < 0 or int(task.context.get("transport_source_id", -1)) == source_id


# Fossa con dei rifiuti (2026-10-18, richiesta utente): non si demolisce finché ne contiene (una discarica resta dov'è),
# né durante lo svuotamento.
static func blocks_demolition(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.waste_capacity > 0 \
		and (building.waste_stored > 0 or building.waste_emptying)


# --- Svuota la Fossa ---

# "Svuota" possibile: Fossa con rifiuti, non già in svuotamento, e un'altra Fossa che riceve con posto.
static func can_start_emptying(world: World, pit: Building) -> bool:
	if not is_pit(pit) or pit.waste_emptying or pit.waste_stored <= 0:
		return false
	# La Fossa stessa conta come destinazione solo se è aperta: va esclusa a mano.
	for building in (world.buildings if world != null else []):
		if building != pit and is_waste_pit(building) and building.get_waste_free_space() >= 1:
			return true
	return false


# Avvia lo svuotamento: i rifiuti diventano detriti nel deposito della Fossa, che si chiude ai rifiuti.
static func start_emptying(pit: Building) -> void:
	if not is_pit(pit) or pit.waste_emptying or pit.waste_stored <= 0:
		return
	pit.waste_closed = true
	pit.waste_emptying = true
	pit.stored_resources[DEBRIS_RESOURCE] = {"quantity": get_debris(pit) + pit.waste_stored, "decay_fraction": 0.0}
	pit.waste_stored = 0


# Svuotamento annullato: i detriti rimasti tornano rifiuti; la Fossa resta chiusa. I lavori sulla Fossa li chiude chi
# chiama (serve il GameContext).
static func cancel_emptying(pit: Building) -> void:
	if pit == null or not pit.waste_emptying:
		return
	pit.waste_stored = mini(pit.waste_stored + get_debris(pit), pit.rules.waste_capacity)
	pit.stored_resources.erase(DEBRIS_RESOURCE)
	pit.waste_emptying = false


# Svuotamento finito (nessun detrito rimasto): la Fossa è vuota e resta chiusa ai rifiuti.
static func finish_emptying(pit: Building) -> void:
	pit.stored_resources.erase(DEBRIS_RESOURCE)
	pit.waste_emptying = false


# --- Detriti posati a terra (2026-10-18, richiesta utente) ---
# Chi non trova posto per i detriti in spalla li posa a terra (mucchio). Ogni secondo BuildingLifecycleService.
# settle_ground_debris li toglie dai mucchi e li mette in una maceria (vicina o nuova): i detriti a terra sono sempre macerie.

# Distanza massima (microcelle, Chebyshev) di una maceria da sgomberare a cui si aggiungono i detriti di un mucchio.
const GROUND_DEBRIS_MERGE_RADIUS: int = 1


# Mucchi con dei rifiuti (waste_only): ritorna [{pile, quantity}] con la quantità di detriti di ognuno (le voci restano nel
# mucchio finché chi chiama non trova dove metterle, take_ground_debris).
static func find_ground_debris(game_data: GameData) -> Array:
	var result: Array = []
	if game_data == null:
		return result
	for pile in game_data.ground_piles:
		var quantity: int = 0
		for resource_name in pile.resources.keys():
			if is_waste_only(String(resource_name)):
				quantity += int((pile.resources[resource_name] as Dictionary).get("quantity", 0))
		if quantity > 0:
			result.append({"pile": pile, "quantity": quantity})
	return result


# Toglie i rifiuti dal mucchio; il mucchio rimasto vuoto sparisce.
static func take_ground_debris(game_data: GameData, pile: GroundPile) -> void:
	for resource_name in pile.resources.keys():
		if is_waste_only(String(resource_name)):
			pile.resources.erase(resource_name)
	pile.revision += 1
	if pile.is_empty():
		GroundPileService.remove_pile(game_data, pile)


# Tetto di detriti per maceria (2026-10-18, richiesta utente): oltre, i detriti vanno in una maceria nuova vicina
# (BuildingLifecycleService.put_debris_near), così non conviene mai tenere un'unica maceria enorme invece della Fossa.
const MAX_DEBRIS_PER_RUBBLE: int = 300


# Posto rimasto in una maceria prima del tetto.
static func rubble_room(rubble: Building) -> int:
	return maxi(MAX_DEBRIS_PER_RUBBLE - get_debris(rubble), 0)


# Macerie da sgomberare con posto (sotto MAX_DEBRIS_PER_RUBBLE) più vicine a `micro` (stessa macrocella) entro `radius`;
# null se nessuna.
static func find_rubble_near(world: World, macro: Vector2i, micro: Vector2i, radius: int) -> Building:
	if world == null:
		return null
	var best: Building = null
	var best_distance: float = INF
	for building in world.buildings:
		if not building.is_rubble() or building.is_demolished or not building.is_marked_for_demolition:
			continue
		if building.macro_x != macro.x or building.macro_y != macro.y or rubble_room(building) <= 0:
			continue
		var offset := Vector2i(building.micro_x, building.micro_y) - micro
		if maxi(absi(offset.x), absi(offset.y)) > radius:
			continue
		var distance := Vector2(offset).length()
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


# Aggiunge `quantity` detriti a una maceria.
static func add_debris(rubble: Building, quantity: int) -> void:
	rubble.stored_resources[DEBRIS_RESOURCE] = {"quantity": get_debris(rubble) + quantity, "decay_fraction": 0.0}


# --- Disagio (2026-10-18, richiesta utente) ---
# Raggio dell'influenza InfluenceService.InfluenceType.DISCOMFORT, in microcelle: Fossa dei rifiuti (completa) 3 già da
# vuota, che cresce col riempimento (rifiuti + detriti ancora da portare via) fino a 6; macerie sempre 3. 0 per tutto il
# resto (mucchi a terra, cantieri, edifici demoliti).
const DISCOMFORT_RUBBLE_RADIUS: int = 3
# Fossa: [quota massima di riempimento, raggio], dalla più bassa.
const DISCOMFORT_PIT_STEPS: Array[Vector2] = [Vector2(0.25, 3), Vector2(0.50, 4), Vector2(0.75, 5), Vector2(1.0, 6)]

# Ultimo raggio di disagio visto per Fossa (id -> raggio), solo in memoria: sync_discomfort_radii alza
# GameData.buildings_revision quando cambia, così copertura delle case e layer si aggiornano.
static var _last_discomfort_radius: Dictionary = {}


static func discomfort_radius(building: Building) -> int:
	if building == null or building.rules == null or building.is_demolished or not building.is_complete:
		return 0
	if building.is_rubble():
		return DISCOMFORT_RUBBLE_RADIUS
	if not is_pit(building):
		return 0
	var fill_ratio: float = float(get_pit_fill(building)) / float(maxi(building.rules.waste_capacity, 1))
	for step in DISCOMFORT_PIT_STEPS:
		if fill_ratio <= step.x + 0.000001:
			return int(step.y)
	return int(DISCOMFORT_PIT_STEPS[DISCOMFORT_PIT_STEPS.size() - 1].y)


# Una volta al secondo (GameSimulation.tick_second): se il raggio di disagio di una Fossa è cambiato (riempimento), alza
# GameData.buildings_revision. Nascita e fine delle macerie la alzano già come ogni edificio aggiunto o tolto.
static func sync_discomfort_radii(world: World, game_data: GameData) -> void:
	if world == null or game_data == null:
		return
	var changed := false
	for building in world.buildings:
		if not is_pit(building):
			continue
		var radius := discomfort_radius(building)
		if int(_last_discomfort_radius.get(building.id, -1)) != radius:
			_last_discomfort_radius[building.id] = radius
			changed = true
	if changed:
		game_data.buildings_revision += 1


# Motivo (chiave tr) di un lavoro di detriti fermo — sgombero delle macerie o svuotamento di una Fossa (2026-10-18):
# nessuna Fossa aperta con posto, altrimenti `missing_worker_key` (manca chi lo fa).
static func debris_job_reason_key(world: World, source: Building, missing_worker_key: String) -> String:
	if find_pit_for_debris(world, source) == null:
		return "pending_reason_no_waste_pit"
	return missing_worker_key


# --- Rifiuti del villaggio (2026-10-18, richiesta utente) ---
# Ogni VILLAGE_WASTE_PERIOD_DAYS giorni ogni villaggio con centro produce VILLAGE_WASTE_PER_INHABITANT_PER_MONTH detriti per
# abitante, senza azioni: entrano nelle Fosse aperte (dump_into_pits), il resto diventa "Rifiuti del villaggio" accanto al
# centro (BuildingLifecycleService.produce_village_waste). Senza centro (gruppo nomade) niente.
const VILLAGE_WASTE_PER_INHABITANT_PER_MONTH: int = 5
const VILLAGE_WASTE_PERIOD_DAYS: int = 30


# Abitanti del villaggio: chi ha la casa in un suo edificio; i senza casa contano nel primo villaggio con centro
# (`first_village_id`).
static func village_inhabitants(village: Village, individuals: Array[HumanIndividual], world: World, first_village_id: int) -> int:
	var count := 0
	for member in individuals:
		var house := _find_building(world, member.house_id)
		var member_village: int = house.village_id if house != null else first_village_id
		if member_village == village.id:
			count += 1
	return count


# Butta `amount` detriti nelle Fosse aperte, dalla più vicina a `near` in poi, fino a riempirle; ritorna quanti ne sono entrati.
static func dump_into_pits(world: World, near: Building, amount: int) -> int:
	var dumped := 0
	while dumped < amount:
		var pit := find_pit_for(world, 1, near)
		if pit == null:
			break
		var units := mini(amount - dumped, pit.get_waste_free_space())
		if units <= 0:
			break
		pit.waste_stored += units
		dumped += units
	return dumped


static func _find_building(world: World, building_id: int) -> Building:
	if world == null or building_id < 0:
		return null
	for building in world.buildings:
		if building.id == building_id and not building.is_demolished:
			return building
	return null


# Motivo (chiave tr) per cui un costruttore con detriti sul cantiere aspetta: nessuna Fossa aperta con posto.
static func site_debris_waiting(world: World, site: Building) -> bool:
	return has_site_debris(site) and find_pit_for_debris(world, site) == null
