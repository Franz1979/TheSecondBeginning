class_name DrawerOrderTargetService
extends RefCounted

# Bersaglio scelto dall'ordine (2026-10-23, richiesta utente — scatti della coda e del coordinatore): per gli ordini di
# taglio ed estrazione del cassetto, zona e pianta/roccia le sceglie L'ORDINE, una volta, vicino al punto di assegnazione
# (scelta dell'utente), e se le tiene finché valgono. Prima si sceglievano per ogni pipottino a ogni domanda
# (DrawerOrderJobProvider.pick_zone_target), con un giro su tutte le piante della macrocella ogni volta. Il pipottino ora
# controlla solo di arrivarci (reach_target della voce) e alla presa riceve quel bersaglio; dalla presa in poi lo prenota
# la sua CutAction/QuarryAction e l'ordine lo lascia (clear_target). Raccolta e caccia: invariate.
#
# Campi sull'ordine (solo interi, salvati così come sono — GameSaveService/GameLoadService non cambiano):
#   "target_area_id": zona scelta (= zone_id se fissata); "target_macro_x"/"target_macro_y": macrocella; "target_x"/
#   "target_y": microcella; solo taglio: "target_z" (indice dell'individuo) e "target_object_type". Assenti = nessun
#   bersaglio (ordini nuovi, salvataggi precedenti): lo sceglie ensure_target.
# Stateless; solo una memoria non salvata dei tentativi falliti, per non rifare la ricerca a ogni giro della coda.

const TARGET_KEYS: Array[String] = [
	"target_area_id", "target_macro_x", "target_macro_y", "target_x", "target_y", "target_z", "target_object_type",
]
# Senza bersaglio trovato, si riprova al più ogni RETRY_MSEC (ms reali).
const RETRY_MSEC := 2000
static var _retry_after: Dictionary = {}  # id ordine -> Time.get_ticks_msec() oltre il quale riprovare


static func uses_order_target(order_type: String) -> bool:
	return order_type == DrawerOrderService.TYPE_CUT or order_type == DrawerOrderService.TYPE_QUARRY


static func has_target(order: Dictionary) -> bool:
	return order.has("target_area_id")


static func clear_target(order: Dictionary) -> void:
	for key in TARGET_KEYS:
		order.erase(key)


# L'ordine ha un bersaglio valido (tenuto o appena scelto). Solo ordini di taglio/estrazione non presi.
static func ensure_target(ctx: GameContext, order: Dictionary) -> bool:
	var order_type := String(order.get("type", ""))
	if ctx == null or ctx.game_data == null or ctx.world == null or not uses_order_target(order_type):
		return false
	var reserved := _reserved_for(ctx, order, order_type)
	if has_target(order):
		if _is_target_valid(ctx, order, order_type, reserved):
			return true
		clear_target(order)
	var order_id := int(order.get("id", -1))
	if Time.get_ticks_msec() < int(_retry_after.get(order_id, 0)):
		return false
	if _choose_target(ctx, order, order_type, reserved):
		_retry_after.erase(order_id)
		return true
	if _retry_after.size() > 256:
		_retry_after.clear()
	_retry_after[order_id] = Time.get_ticks_msec() + RETRY_MSEC
	return false


# {"area": WorkArea, "plant": {...}} o {"area": WorkArea, "rock": {"macro_coords", "position"}}, la stessa forma di
# DrawerOrderJobProvider.pick_zone_target; {} senza bersaglio.
static func get_pick(ctx: GameContext, order: Dictionary) -> Dictionary:
	if not has_target(order):
		return {}
	var area: WorkArea = WorkAreaService.find_by_id(ctx.game_data, int(order["target_area_id"]))
	if area == null:
		return {}
	var macro := _target_macro(order)
	var cell := Vector2i(int(order.get("target_x", 0)), int(order.get("target_y", 0)))
	if String(order.get("type", "")) == DrawerOrderService.TYPE_QUARRY:
		return {"area": area, "rock": {"macro_coords": macro, "position": cell}}
	var object_type := int(order.get("target_object_type", GameTypes.WorldObjectType.TREE)) as GameTypes.WorldObjectType
	var individual_key := Vector3i(cell.x, cell.y, int(order.get("target_z", 0)))
	var macro_state: MacroCellState = ctx.world.get_cell_state_at(macro.x, macro.y)
	return {"area": area, "plant": {
		"macro_coords": macro, "object_type": object_type, "individual_key": individual_key,
		"subtype": PlantCutService.get_subtype_name(macro_state, object_type, individual_key),
	}}


# Bersaglio per il controllo di raggiungibilità della voce (JobBoardService.find_takeable_jobs, reach_target); senza
# bersaglio quello di sempre (macrocella -1 = sempre raggiungibile).
static func reach_target(order: Dictionary) -> Dictionary:
	if not has_target(order):
		return {"macro_x": -1, "macro_y": -1, "micro_x": 0, "micro_y": 0}
	return {
		"macro_x": int(order["target_macro_x"]), "macro_y": int(order["target_macro_y"]),
		"micro_x": int(order["target_x"]), "micro_y": int(order["target_y"]),
	}


# Parte della chiave di prova (DrawerOrderJobProvider.probe_key): ordini con bersagli diversi non condividono l'idoneità.
static func target_signature(order: Dictionary) -> String:
	if not has_target(order):
		return "-"
	return "%d,%d,%d,%d,%d,%d" % [
		int(order["target_area_id"]), int(order["target_macro_x"]), int(order["target_macro_y"]),
		int(order["target_x"]), int(order["target_y"]), int(order.get("target_z", 0)),
	]


# --- Interni ---

static func _target_macro(order: Dictionary) -> Vector2i:
	return Vector2i(int(order.get("target_macro_x", 0)), int(order.get("target_macro_y", 0)))


static func _target_key(order: Dictionary, order_type: String) -> String:
	var macro := _target_macro(order)
	var cell := Vector2i(int(order.get("target_x", 0)), int(order.get("target_y", 0)))
	if order_type == DrawerOrderService.TYPE_QUARRY:
		return QuarryZoneService.rock_reservation_key(macro, cell)
	return CutZoneService.plant_reservation_key(macro, int(order.get("target_object_type", 0)), Vector3i(cell.x, cell.y, int(order.get("target_z", 0))))


# Prenotati per questo ordine: le piante/rocce nelle task di tutti più i bersagli degli altri ordini dello stesso tipo.
static func _reserved_for(ctx: GameContext, order: Dictionary, order_type: String) -> Dictionary:
	var reserved: Dictionary = DrawerOrderService.zone_reserved(ctx.individuals, order_type).duplicate()
	for other in ctx.game_data.drawer_orders:
		if other == order or String(other.get("type", "")) != order_type or not has_target(other):
			continue
		reserved[_target_key(other, order_type)] = true
	return reserved


static func _is_target_valid(ctx: GameContext, order: Dictionary, order_type: String, reserved: Dictionary) -> bool:
	var area: WorkArea = WorkAreaService.find_by_id(ctx.game_data, int(order["target_area_id"]))
	if area == null or not DrawerOrderService.zone_areas(ctx.game_data, order_type).has(area):
		return false
	var zone_id := int(order.get("zone_id", -1))
	if zone_id >= 0 and zone_id != area.id:
		return false
	var macro := _target_macro(order)
	if macro != area.macro_coords or not ctx.live_cells.has(macro):
		return false
	var cell := Vector2i(int(order.get("target_x", 0)), int(order.get("target_y", 0)))
	if not area.rect.has_point(cell) or reserved.has(_target_key(order, order_type)):
		return false
	var macro_state: MacroCellState = ctx.world.get_cell_state_at(macro.x, macro.y)
	if macro_state == null:
		return false
	if order_type == DrawerOrderService.TYPE_QUARRY:
		return RockStoneService.get_remaining_stone(macro_state, cell) > 0
	var object_type := int(order.get("target_object_type", -1)) as GameTypes.WorldObjectType
	var individual_key := Vector3i(cell.x, cell.y, int(order.get("target_z", 0)))
	if not PlantCutService.is_individual_alive(macro_state, object_type, individual_key):
		return false
	var subtype_name := PlantCutService.get_subtype_name(macro_state, object_type, individual_key)
	if not CutZoneService.work_area_accepts_plant(area, object_type, subtype_name):
		return false
	var yield_resource := DrawerOrderService.order_cut_yield(order)
	return yield_resource == "" or CutZoneService.plant_yields(object_type, subtype_name, yield_resource)


# Origine della scelta: il punto di assegnazione valido più vicino a `near` (locale a `near_macro`); senza punti, `near`.
# {"macro": Vector2i, "position": Vector2}.
static func _origin(ctx: GameContext, near_macro: Vector2i, near: Vector2) -> Dictionary:
	var best: Dictionary = {"macro": near_macro, "position": near}
	var best_distance := INF
	for building in ctx.world.buildings:
		if not CoordinatorService.is_valid_point(building):
			continue
		var position := SpatialSelectionService._position_relative_to(building, near_macro) + Vector2(0.5, 0.5)
		var distance := position.distance_to(near)
		if distance < best_distance:
			best_distance = distance
			best = {"macro": Vector2i(building.macro_x, building.macro_y), "position": Vector2(building.micro_x, building.micro_y) + Vector2(0.5, 0.5)}
	return best


static func _choose_target(ctx: GameContext, order: Dictionary, order_type: String, reserved: Dictionary) -> bool:
	var zone_id := int(order.get("zone_id", -1))
	var area: WorkArea = null
	var origin: Dictionary
	if zone_id >= 0:
		area = WorkAreaService.find_by_id(ctx.game_data, zone_id)
		if area == null or not DrawerOrderService.zone_areas(ctx.game_data, order_type).has(area):
			return false
		origin = _origin(ctx, area.macro_coords, Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5)
	else:
		# Zona automatica: origine = il punto di assegnazione (il primo valido; senza punti nessuna scelta automatica,
		# come la coda, che senza punti non è attiva).
		origin = _first_point_origin(ctx)
		if origin.is_empty():
			return false
		if order_type == DrawerOrderService.TYPE_QUARRY:
			area = QuarryZoneService.choose_work_area_from(ctx.game_data, ctx.world, origin["macro"], origin["position"], null, reserved)
		else:
			area = CutZoneService.choose_work_area_from(
				ctx.game_data, ctx.live_cells, origin["macro"], origin["position"], null, reserved, DrawerOrderService.order_cut_yield(order)
			)
	if area == null or not ctx.live_cells.has(area.macro_coords):
		return false
	if order_type == DrawerOrderService.TYPE_QUARRY:
		var macro_state: MacroCellState = ctx.world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		var rock: Variant = QuarryZoneService.choose_rock_from(area, macro_state, origin["macro"], origin["position"], null, reserved)
		if rock == null:
			return false
		_store(order, area, area.macro_coords, rock, 0, 0)
		return true
	var plant := CutZoneService.choose_plant_from(
		area, ctx.live_cells, origin["macro"], origin["position"], null, reserved, DrawerOrderService.order_cut_yield(order)
	)
	if plant.is_empty():
		return false
	var individual_key: Vector3i = plant["individual_key"]
	_store(order, area, area.macro_coords, Vector2i(individual_key.x, individual_key.y), individual_key.z, int(plant["object_type"]))
	return true


static func _first_point_origin(ctx: GameContext) -> Dictionary:
	var best: Building = null
	for building in ctx.world.buildings:
		if CoordinatorService.is_valid_point(building) and (best == null or building.id < best.id):
			best = building
	if best == null:
		return {}
	return {"macro": Vector2i(best.macro_x, best.macro_y), "position": Vector2(best.micro_x, best.micro_y) + Vector2(0.5, 0.5)}


static func _store(order: Dictionary, area: WorkArea, macro: Vector2i, cell: Vector2i, z: int, object_type: int) -> void:
	order["target_area_id"] = area.id
	order["target_macro_x"] = macro.x
	order["target_macro_y"] = macro.y
	order["target_x"] = cell.x
	order["target_y"] = cell.y
	if String(order.get("type", "")) == DrawerOrderService.TYPE_CUT:
		order["target_z"] = z
		order["target_object_type"] = object_type
