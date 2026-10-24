class_name TaskBuilderService
extends RefCounted

# Costruzione delle Task, MAI assegnate qui (2026-10-17, refactoring GameScene blocco 1 — docs/design/
# gamescene_refactoring.md): estratte da GameScene._build_*_task così la futura scena 3D le riusa tali e quali. Ogni
# builder calcola il context (posizioni tradotte nelle coordinate della macrocella HOME dell'individuo, jitter, chiavi
# extra che restano in task.context e nel salvataggio) e chiama TaskFactory.build_task con la TaskDefinition .tres.
# Statico e senza stato; nessun nodo: i segnali degli step li collega chi assegna la Task (GameScene). null se la
# definizione non si carica.

const TRANSPORT_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/transport.tres"
const CUT_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/cut.tres"
const QUARRY_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/quarry.tres"
const REPAIR_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/repair.tres"
const PRODUCE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/produce.tres"
const DELIVER_OUTPUT_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/deliver_output.tres"
# TaskDefinition delle due Task degli attrezzi (2026-09-25 — allineate allo schema .tres + TaskFactory delle altre).
const EQUIP_TOOL_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/equip_tool.tres"
const STORE_TOOL_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/store_tool.tres"
const INVENTORY_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/inventory.tres"
# Rito ordinato (rite.tres [Walk → Rite]); il funerale resta nella task Seppellisci (BodyBurialService.build_bury_task).
const RITE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/rite.tres"
const HAUL_RESOURCE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/haul_resource.tres"
# Raccolta su zona (2026-09-27, work areas passo 2): primo step "cerca nella zona" (HaulZoneService).
const HAUL_RESOURCE_ZONE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/haul_resource_zone.tres"
# Macellazione (2026-09-26): Walk verso la carcassa -> Butcher -> PickUp dal mucchio.
const BUTCHER_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/butcher.tres"
# Scarico di quello che si ha già nello zaino in un magazzino (2026-10-17): Walk -> Unload.
const UNLOAD_RESOURCE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/unload_resource.tres"

# Id dell'edificio della consegna dei Prodotti finiti nel context della task (salvato con lei).
const CONTEXT_OUTPUT_JOB_BUILDING_ID := "output_job_building_id"


# Offset in microcelle dalla macrocella HOME di `worker` a `macro_coords` (stessa formula cross-macrocella in uso ovunque:
# zero se coincidono).
static func macro_offset(worker: HumanIndividual, macro_coords: Vector2i) -> Vector2:
	return Vector2(macro_coords - worker.home_macro_coords) * World.WIDTH


# Punto d'arrivo dentro la microcella di `building`, con jitter interno alla cella (mai l'angolo esatto: lavoratori
# diversi non si fermano nello stesso punto — bugfix "angolo in alto a sinistra", 2026-09-17).
static func building_arrival_point(worker: HumanIndividual, building: Building) -> Vector2:
	var jitter := Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85))
	return Vector2(building.micro_x, building.micro_y) + jitter + macro_offset(worker, Vector2i(building.macro_x, building.macro_y))


# Transport Task [Walk, Retrieve, Walk, Unload]. `trip_target` = quanto RECUPERARE in questo viaggio (transport_quantity
# di RetrieveAction); `requested_remaining` = quanto il player voleva ancora che arrivasse (la quantità chiesta meno il
# già consegnato). Le chiavi transport_source_id/transport_destination_id/transport_delivery_resource/
# transport_requested_remaining NON sono nei context_keys di transport.tres: restano in task.context (salvate) e servono
# a UnloadAction.transport_delivered / GameScene._on_transport_delivered.
static func build_transport_task(
	owner: HumanIndividual, source_building: Building, destination_building: Building, resource_name: String,
	trip_target: int, requested_remaining: int, repeat_enabled: bool, repeat_count: int
) -> Task:
	# Un jitter INDIPENDENTE per sorgente e destinazione, non lo stesso valore riusato per entrambe.
	var context := {
		"transport_source_position": building_arrival_point(owner, source_building),
		"transport_source_building": source_building,
		"transport_resource_name": resource_name,
		"transport_quantity": trip_target,
		"transport_destination_position": building_arrival_point(owner, destination_building),
		"transport_destination_building": destination_building,
	}
	context["transport_source_id"] = source_building.id
	context["transport_destination_id"] = destination_building.id
	# Vero se alla creazione la destinazione è un cantiere: se sarà completata prima dell'Unload,
	# UnloadAction la tratta come destinazione non valida (vedi _is_completed_site_destination).
	context["transport_destination_is_site"] = not destination_building.is_complete
	context["transport_delivery_resource"] = resource_name
	context["transport_requested_remaining"] = requested_remaining
	TaskRepeatRules.write(context, repeat_enabled, repeat_count)
	var definition := TaskDefinitionCache.get_definition(TRANSPORT_TASK_DEFINITION_PATH)
	return TaskFactory.build_task(definition, context)


# Obiettivo di UN viaggio di trasporto (2026-09-20; spostato qui da GameScene il 2026-10-17): min(quantità ancora da
# portare, fabbisogno della destinazione) se la destinazione non è completa o è una produzione in corso (il fabbisogno è
# BuildingStorageService.get_max_depositable: per un cantiere required - stored della fase in corso; per una produzione la
# quantità esatta mancante) — altrimenti (edificio completo, magazzino) min(quantità ancora da portare, posto reale), 0 se
# la categoria non è accettata (2026-09-25, bugfix "Transport verso chi non può ricevere"). Ricalcolato a ogni viaggio,
# perché il fabbisogno può essere cambiato. Il controllo all'arrivo e il reinstradamento di UnloadAction restano per i
# cambiamenti durante il viaggio.
static func transport_trip_target(destination_building: Building, resource_name: String, remaining_quantity: int) -> int:
	if remaining_quantity <= 0 or destination_building == null:
		return 0
	if destination_building.is_demolished:
		return 0
	# Fossa dei rifiuti (2026-10-18): tutto ciò che ci sta ancora, qualunque merce (WasteDisposalService).
	if WasteDisposalService.is_waste_pit(destination_building):
		return mini(remaining_quantity, WasteDisposalService.get_max_disposable(destination_building, resource_name))
	# Attrezzeria (2026-10-18, richiesta utente): un attrezzo che le serve entra prima lì, poi nel magazzino se lo accetta.
	var toolkit_room := BuildingToolkitService.get_max_toolkit_depositable(destination_building, resource_name)
	if toolkit_room > 0:
		var storage_room := BuildingStorageService.get_max_depositable(destination_building, resource_name) 			if BuildingStorageService.can_accept(destination_building, resource_name) else 0
		return mini(remaining_quantity, toolkit_room + storage_room)
	if not destination_building.is_complete or ProductionService.is_production_demand(destination_building, resource_name):
		return mini(remaining_quantity, BuildingStorageService.get_max_depositable(destination_building, resource_name))
	if not BuildingStorageService.can_accept(destination_building, resource_name):
		return 0
	return mini(remaining_quantity, BuildingStorageService.get_max_depositable(destination_building, resource_name))


# Task di caccia in zona (hunt_zone.tres, inizia con PatrolAreaAction) per la WorkArea `area_id`. La zona resta nel
# context (HuntZoneService.CONTEXT_WORK_AREA_ID) per etichetta, scelta della preda e ritorno alla pattuglia.
# `series` (2026-10-01, passo 2b): serie fino a un limite di carne ({} = una sola caccia).
static func build_hunt_zone_task(area_id: int, series: Dictionary = {}) -> Task:
	var definition := TaskDefinitionCache.get_definition(HuntZoneService.TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var task := TaskFactory.build_task(definition, {HuntZoneService.FACTORY_WORK_AREA_KEY: area_id})
	task.context[HuntZoneService.CONTEXT_WORK_AREA_ID] = area_id
	if not series.is_empty():
		task.context[HuntZoneService.CONTEXT_MEAT_SERIES] = series
		# Destinazione della macellazione scelta nel dialog (2026-10-03): vale per ogni caccia della serie.
		if series.has("butcher_destination"):
			task.context[ButcherDestinationService.CONTEXT_KEY] = String(series["butcher_destination"])
	return task


# Task Cut (Walk + Cut) su `plant` ({"macro_coords", "object_type", "individual_key"}). `work_area_id` e `series` nel
# context per etichetta e serie in zona (-1 / {} = comando col clic destro).
static func build_cut_task(worker: HumanIndividual, plant: Dictionary, work_area_id: int = -1, series: Dictionary = {}) -> Task:
	var definition := TaskDefinitionCache.get_definition(CUT_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var macro_coords: Vector2i = plant["macro_coords"]
	var individual_key: Vector3i = plant["individual_key"]
	var lot := Vector2i(individual_key.x, individual_key.y)
	var task := TaskFactory.build_task(definition, {
		"target_position": PathfindingService.random_point_in_microcell(Vector2(lot) + macro_offset(worker, macro_coords)),
		"cut_macro_coords": macro_coords,
		"cut_object_type": plant["object_type"],
		"cut_individual_key": individual_key,
	})
	if work_area_id != -1:
		task.context[CutZoneService.CONTEXT_WORK_AREA_ID] = work_area_id
	if not series.is_empty():
		task.context[CutZoneService.CONTEXT_SERIES] = series.duplicate()
	return task


# Task Quarry (Walk + Quarry) sulla roccia `rock_position` della macrocella `macro_coords`; zona e serie come in
# build_cut_task.
static func build_quarry_task(
	worker: HumanIndividual, macro_coords: Vector2i, rock_position: Vector2i, work_area_id: int = -1, series: Dictionary = {}
) -> Task:
	var definition := TaskDefinitionCache.get_definition(QUARRY_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var task := TaskFactory.build_task(definition, {
		"target_position": PathfindingService.random_point_in_microcell(Vector2(rock_position) + macro_offset(worker, macro_coords)),
		"quarry_macro_coords": macro_coords,
		"quarry_position": rock_position,
	})
	if work_area_id != -1:
		task.context[QuarryZoneService.CONTEXT_WORK_AREA_ID] = work_area_id
	if not series.is_empty():
		task.context[QuarryZoneService.CONTEXT_SERIES] = series.duplicate()
	return task


# Repair Task per `worker` su `building` (Walk fino a un punto della microcella, poi Repair).
static func build_repair_task(worker: HumanIndividual, building: Building) -> Task:
	var definition := TaskDefinitionCache.get_definition(REPAIR_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var task := TaskFactory.build_task(definition, {
		"target_position": building_arrival_point(worker, building),
		"target_building": building,
	})
	if task != null:
		task.debug_target_key = "repair:%d" % building.id
	return task


# Produce Task [Walk → Produce] di `quantity` pezzi di `resource_name` presso `target_building`: la stessa
# dell'assegnazione a mano, usata anche come task di prova dalla lista dei lavori.
static func build_produce_task(
	worker: HumanIndividual, target_building: Building, resource_name: String, quantity: int, deliver_to_warehouse: bool
) -> Task:
	var definition := TaskDefinitionCache.get_definition(PRODUCE_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var task := TaskFactory.build_task(definition, {
		"target_position": building_arrival_point(worker, target_building),
		"target_building": target_building,
		"produce_resource_name": resource_name,
		"produce_quantity": quantity,
	})
	task.debug_target_key = "production:%d" % target_building.id
	# Nome del prodotto per il pannello individuo (Task.get_activity_description): chiave NON consumata
	# da TaskFactory, resta in task.context per tutta la vita della Task (e nel salvataggio).
	task.context["production_resource_name"] = resource_name
	task.context["production_quantity"] = quantity
	# Consegna al magazzino a ordine finito (2026-09-26): letta dallo step di consegna (RetrieveAction), salvata col context.
	task.context[RetrieveAction.CONTEXT_DELIVER_TO_WAREHOUSE] = deliver_to_warehouse
	return task


# Task di consegna dei Prodotti finiti: cammino all'edificio, poi lo step di consegna di "Porta al deposito" per
# `resource_name`, fino a tutti i pezzi che ha nei Prodotti finiti (lo step si limita da sé a zaino e magazzino). Che
# l'edificio sia in una macrocella attiva lo controlla il chiamante (dato della scena, non della regola).
static func build_output_job_task(worker: HumanIndividual, building: Building, resource_name: String) -> Task:
	if resource_name == "":
		return null
	var definition := TaskDefinitionCache.get_definition(DELIVER_OUTPUT_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var offset := macro_offset(worker, Vector2i(building.macro_x, building.macro_y))
	var task := TaskFactory.build_task(definition, {
		"transport_source_position": PathfindingService.random_point_in_microcell(Vector2(building.micro_x, building.micro_y) + offset),
		"target_building": building,
		"produce_resource_name": resource_name,
		"produce_quantity": maxi(
			BuildingStorageService.get_auto_available_quantity(building, resource_name) if ProductionService.get_output_capacity(building) <= 0
			else int(building.production_output.get(resource_name, 0)), 1
		),
		"produce_delivery_step": true,
	})
	task.context[CONTEXT_OUTPUT_JOB_BUILDING_ID] = building.id
	task.debug_target_key = "output:%d" % building.id
	return task


# Task di prelievo o riposizione di un attrezzo (equip_tool.tres/store_tool.tres) verso/da `building`, slot della
# cintura `slot_index`. `is_apparel` (2026-10-11): lo slot da svuotare è del vestiario (store_tool.tres ->
# UnloadAction.unequip_apparel); il prelievo non ne ha bisogno, RetrieveAction riconosce i capi dalla risorsa.
static func build_tool_task(
	target: HumanIndividual, definition_path: String, tool_name: String, building: Building, slot_index: int, is_apparel: bool = false
) -> Task:
	var definition := TaskDefinitionCache.get_definition(definition_path)
	if definition == null:
		return null
	var task := TaskFactory.build_task(definition, {
		"target_position": building_arrival_point(target, building),
		"tool_building": building,
		"tool_resource_name": tool_name,
		"tool_quantity": 1,
		"tool_slot_index": slot_index,
		"tool_is_apparel": is_apparel,
	})
	if task == null:
		return null
	# TaskFactory rimuove dal context le chiavi consumate dagli step (tool_resource_name compresa): la si rimette per
	# Task.get_activity_description ("Prendi attrezzo (Coltello di pietra)"), come production_resource_name.
	task.context["tool_resource_name"] = tool_name
	task.debug_target_key = "tool:%d" % building.id
	return task


# Prelievo in cintura nello slot `slot_index` (equip_tool.tres): per gli ordini di zona che partono senza l'attrezzo.
static func build_equip_tool_task(target: HumanIndividual, building: Building, tool_name: String, slot_index: int) -> Task:
	return build_tool_task(target, EQUIP_TOOL_TASK_DEFINITION_PATH, tool_name, building, slot_index)


# Task Inventario del magazzino `depot` (Walk + inventario).
static func build_inventory_task(worker: HumanIndividual, depot: Building) -> Task:
	var definition := TaskDefinitionCache.get_definition(INVENTORY_TASK_DEFINITION_PATH)
	if definition == null or depot == null:
		return null
	var offset := macro_offset(worker, Vector2i(depot.macro_x, depot.macro_y))
	return TaskFactory.build_task(definition, {
		"target_position": PathfindingService.random_point_in_microcell(Vector2(depot.micro_x, depot.micro_y) + offset),
		"target_building": depot,
	})


# Task di raccolta [Walk, PickUp] su `target_position` della macrocella di `macro_state` (haul_resource.tres). Il resto
# della catena (ricerca del magazzino, cammino, Unload) cresce a runtime via Task.append_steps
# (HumanIndividualActionService._handle_pending_warehouse_search): i segnali di quegli step, e del PickUp, li collega chi
# usa la Task (GameScene._wire_pickup_task).
# Due chiavi per la STESSA posizione: "target_position" (Vector2, con jitter interno alla cella — bugfix "angolo in alto
# a sinistra", 2026-09-17) per il Walk, "pickup_position" (il Vector2i ESATTO della cella, chiave del pool della
# risorsa) per il PickUp — TaskFactory passa context[chiave] così com'è al costruttore, senza conversioni.
# `quantity_requested` < 0 = nessun tetto; criterio scritto solo se diverso dal default NAME; le chiavi di
# TaskRepeatRules non sono nei context_keys del PickUp, quindi restano in task.context (e nel salvataggio).
static func build_pickup_task(
	macro_state: MacroCellState, target_position: Vector2i, resource_name: String, quantity_requested: int,
	criterion_kind: int, criterion_category: int, repeat_enabled: bool, repeat_count: int,
	source_kind: int = PickUpAction.SourceKind.TERRAIN
) -> Task:
	var definition := TaskDefinitionCache.get_definition(HAUL_RESOURCE_TASK_DEFINITION_PATH)
	var context: Dictionary = {
		"target_position": Vector2(target_position) + Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85)),
		"pickup_position": target_position,
		"macro_state": macro_state,
		"resource_name": resource_name,
	}
	if quantity_requested >= 0:
		context["pickup_requested_quantity"] = quantity_requested
	if criterion_kind != PickUpAction.CriterionKind.NAME:
		context["pickup_criterion_kind"] = criterion_kind
		context["pickup_criterion_category"] = criterion_category
	if repeat_enabled:
		TaskRepeatRules.write(context, true, repeat_count)
	var task := TaskFactory.build_task(definition, context)
	# Sorgente (2026-09-26, ground drop): impostata dopo TaskFactory, così haul_resource.tres resta invariata.
	for step in task.steps:
		if step is PickUpAction:
			(step as PickUpAction).source_kind = source_kind as PickUpAction.SourceKind
			break
	return task


# Raccolta su zona (2026-09-27, work areas passo 2): primo step "cerca nella zona", la zona (HaulZoneService) e la
# ripetizione nel context. Walk e PickUp nascono a runtime dalla ricerca: i loro segnali (e quelli dell'Unload che
# seguirà) passano da step_appended (GameScene._connect_haul_zone_step_appended).
static func build_haul_zone_task(zone: Dictionary, repeat_enabled: bool, repeat_count: int) -> Task:
	var definition := TaskDefinitionCache.get_definition(HAUL_RESOURCE_ZONE_TASK_DEFINITION_PATH)
	var context: Dictionary = {HaulZoneService.CONTEXT_KEY: zone}
	if repeat_enabled:
		TaskRepeatRules.write(context, true, repeat_count)
	return TaskFactory.build_task(definition, context)


# Consegna del mucchio `pile` "fino a mucchio vuoto", come quella automatica dopo un taglio o un'estrazione: raccogli di
# tutto dal mucchio, poi la catena di sempre (magazzino, cammino, scarico), ripetuta finché il mucchio ha qualcosa.
# `macro_state` = quello della cella del mucchio; null (cella non viva) o mucchio vuoto -> null.
static func build_pile_job_task(worker: HumanIndividual, pile: GroundPile, macro_state: MacroCellState) -> Task:
	if macro_state == null:
		return null
	var resource_names := pile.get_resource_names()
	if resource_names.is_empty():
		return null
	var task := build_pickup_task(
		macro_state, pile.microcell, resource_names[0], -1, PickUpAction.CriterionKind.ALL, -1, true, 0,
		PickUpAction.SourceKind.GROUND_PILE
	)
	if task == null:
		return null
	var pile_units := 0
	for resource_name in resource_names:
		pile_units += pile.get_quantity(resource_name)
	var zone := HaulZoneService.make_zone(
		pile.macro_coords, Rect2i(pile.microcell, Vector2i.ONE), PickUpAction.CriterionKind.ALL, -1, resource_names[0], -1,
		PickUpAction.SourceKind.GROUND_PILE, maxi(pile_units, 1)
	)
	zone[HaulZoneService.UNTIL_EMPTY_KEY] = true
	# "Ritiro mucchio (<risorsa>)" nella riga dell'individuo (2026-10-09): la risorsa se è una sola.
	zone[HaulZoneService.PILE_RESOURCE_KEY] = resource_names[0] if resource_names.size() == 1 else ""
	task.context[HaulZoneService.CONTEXT_KEY] = zone
	return task


# Macellazione della carcassa `carcass_id` del mucchio `pile` (`macro_state` = quello della sua cella): Walk -> Butcher ->
# PickUp di tutto dal mucchio, poi la catena di sempre. `butcher_destination` (ButcherDestinationService): dove portare
# i prodotti; il comando manuale usa il default, il focolare.
static func build_butcher_task(
	worker: HumanIndividual, pile: GroundPile, carcass_id: int, macro_state: MacroCellState,
	butcher_destination: String = ButcherDestinationService.CAMPFIRE
) -> Task:
	var definition := TaskDefinitionCache.get_definition(BUTCHER_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var task := TaskFactory.build_task(definition, {
		"target_position": pile.get_position() + macro_offset(worker, pile.macro_coords),
		"butcher_macro_coords": pile.macro_coords,
		"butcher_microcell": pile.microcell,
		"butcher_carcass_id": carcass_id,
		"pickup_position": pile.microcell,
		"macro_state": macro_state,
		"resource_name": "meat",
		"pickup_criterion_kind": PickUpAction.CriterionKind.ALL,
		"pickup_criterion_category": -1,
	})
	# Scarico (2026-09-27; dal 2026-10-03 secondo la destinazione scelta, ButcherDestinationService): focolare = la carne
	# al focolare più vicino con posto e il resto al magazzino; essiccatoio = carne e pelli all'essiccatoio; magazzino.
	task.context[ButcherDestinationService.CONTEXT_KEY] = butcher_destination
	# Più viaggi (2026-10-01): consegnato il carico si torna a questo mucchio finché ha prodotti della macellazione
	# (HumanIndividualActionService._continue_butcher_pile_trips). Vale per caccia diretta e comando manuale.
	task.context[ButcherAction.CONTEXT_PILE_TRIPS] = {
		"macro_x": pile.macro_coords.x, "macro_y": pile.macro_coords.y,
		"micro_x": pile.microcell.x, "micro_y": pile.microcell.y,
		"last_total": -1,
	}
	for step in task.steps:
		if step is PickUpAction:
			(step as PickUpAction).source_kind = PickUpAction.SourceKind.GROUND_PILE
	return task


# Scarico nel magazzino `warehouse` di quello che `worker` ha già nello zaino (unload_resource.tres: Walk -> Unload,
# sospendibile come haul/transport). Arrivo in un punto casuale della microcella del magazzino, mai l'angolo esatto
# (2026-09-27). Oggi per la dote dei visitatori (prima costruita a mano in GameScene._give_visitor_dowry).
static func build_unload_resource_task(worker: HumanIndividual, warehouse: Building) -> Task:
	var definition := TaskDefinitionCache.get_definition(UNLOAD_RESOURCE_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var offset := macro_offset(worker, Vector2i(warehouse.macro_x, warehouse.macro_y))
	return TaskFactory.build_task(definition, {
		"target_position": PathfindingService.random_point_in_microcell(Vector2(warehouse.micro_x, warehouse.micro_y) + offset),
		"target_building": warehouse,
	})


# Task Rite ORDINATA dal giocatore (rite.tres [Walk → Rite]) del rito `rite_id` presso `target_building`: al
# completamento evade l'ordine dell'edificio (RiteService.CONTEXT_ORDERED, letto da RiteAction.on_complete). I controlli
# (edificio libero, rito ammesso, chi può celebrarlo) restano a chi la assegna.
static func build_rite_task(worker: HumanIndividual, target_building: Building, rite_id: String) -> Task:
	var definition := TaskDefinitionCache.get_definition(RITE_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var offset := macro_offset(worker, Vector2i(target_building.macro_x, target_building.macro_y))
	var task := TaskFactory.build_task(definition, {
		"target_position": PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + offset),
		"rite_target_building": target_building,
		"rite_id": rite_id,
	})
	task.context[RiteService.CONTEXT_ORDERED] = true
	task.debug_target_key = "rite:%d" % target_building.id
	return task
