class_name CutZoneService
extends RefCounted

# Taglio delle piante nelle zone di lavoro (2026-10-06, richiesta utente — Cut in zona): lavoro "cut" della zona
# (WorkAreaTypes.JOBS, sbloccato da work_areas_advanced come caccia ed estrazione), filtro per tipo di pianta, piante
# disponibili, scelta della zona e della pianta. Separato da HaulZoneService/HuntZoneService/QuarryZoneService, sullo
# schema di QuarryZoneService: le piante prenotate da un pipottino (una CutAction in corso o in coda) sono ESCLUSE. Il
# taglio vero passa dalla stessa funzione del clic destro (GameScene._assign_cut_task). Stateless, funzioni statiche.
#
# Filtro (WorkArea.filters["cut"], vedi WorkAreaInfoPanel): {"all": bool, "groups": [String] (tipi spuntati per intero,
# "tree"/"shrub"), "plants": [String] (piante spuntate nei tipi parziali, plant_key "<tipo>_<sottotipo>")}. Senza filtro
# vale il valore iniziale del lavoro (WorkAreaTypes.get_default_filters).

const CUT_JOB := "cut"
# Zona della task (etichetta "Taglio (Zona 1)"), scritta nel context da GameScene._assign_cut_task e portata nel mucchio e
# nella consegna (CutAction.on_complete, GameScene._on_ground_pile_haul_requested), stessa chiave in tutti e tre.
const CONTEXT_WORK_AREA_ID := "cut_work_area_id"
# Tipi di pianta del filtro, nell'ordine dell'albero del pannello; i sottotipi di ciascuno vengono dai dati
# (ResourceCalculator.get_subtype_rules), i nomi da IconRegistry.get_plant_display_name come nel popup del taglio.
const PLANT_OBJECT_TYPES: Array[GameTypes.WorldObjectType] = [GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB]
# Stesso punteggio dell'estrazione (QuarryZoneService): zona = disponibili / (distanza + offset) × fattore per ogni altro
# pipottino che taglia già lì; pianta = distanza + penalità per ogni pianta prenotata da altri nel suo lotto o in uno a
# una microcella di distanza.
const ZONE_DISTANCE_OFFSET: float = QuarryZoneService.ZONE_DISTANCE_OFFSET
const ZONE_CROWDING_FACTOR: float = QuarryZoneService.ZONE_CROWDING_FACTOR
const NEIGHBOR_RESERVED_PENALTY: float = QuarryZoneService.NEIGHBOR_RESERVED_PENALTY

# Serie di tagli (2026-10-06, passo 3 — copiata dalla serie dell'estrazione, dati propri del taglio): "Piante da
# tagliare" del comando Taglia, da COUNT_MIN a COUNT_MAX (ricordato in UserOptions.work_area_cut_count, la prima volta
# COUNT_DEFAULT). La serie viaggia col taglio (context CONTEXT_SERIES), il mucchio (pile_ref SERIES_ZONE_KEY) e la
# consegna fino a mucchio vuoto (zona della consegna, SERIES_ZONE_KEY): {"id": String, "work_area_id": int, "done": int
# (tagli conclusi), "target": int}. Alla chiusura dell'ultima consegna HumanIndividualActionService chiede il taglio
# successivo (GameScene._on_cut_zone_series_continue_requested); qualunque intoppo chiude la serie con un messaggio.
const COUNT_MIN: int = 1
const COUNT_MAX: int = 5
const COUNT_DEFAULT: int = 2
const CONTEXT_SERIES := "cut_zone_series"
const SERIES_ZONE_KEY := "cut_series"
# Messaggio di serie interrotta (chiave tr() di HumanIndividualActionService.series_stopped_message).
const SERIES_STOPPED_KEY := "cut_series_stopped"


static func make_series(area_id: int, target: int) -> Dictionary:
	return {
		"id": "%d-%d" % [Time.get_ticks_usec(), randi()], "work_area_id": area_id,
		"done": 0, "target": clampi(target, COUNT_MIN, COUNT_MAX),
	}


# Serie del context di un taglio ({} se non ne fa parte).
static func get_series(context: Dictionary) -> Dictionary:
	var series: Variant = context.get(CONTEXT_SERIES, {})
	return series if series is Dictionary else {}


# Serie della zona di una consegna fino a mucchio vuoto ({} se non ne fa parte).
static func get_delivery_series(task: Task) -> Dictionary:
	return get_delivery_series_from_context(task.context)


static func get_delivery_series_from_context(context: Dictionary) -> Dictionary:
	var zone := HaulZoneService.get_zone(context)
	var series: Variant = zone.get(SERIES_ZONE_KEY, {}) if not zone.is_empty() else {}
	return series if series is Dictionary else {}


static func is_series_complete(series: Dictionary) -> bool:
	return int(series.get("done", 0)) >= int(series.get("target", 0))


# Serie su una microcella (2026-10-07, "Tutte le piante" del popup del taglio col clic destro): stessa serie e stesse
# chiavi della serie in zona, con "work_area_id" -1 e la microcella al posto della zona ("cell_macro_x/y", "cell_x/y"),
# nessun filtro per tipo e nessun limite COUNT_MAX (`target` = piante vive e libere della cella all'ordine). Finisce
# senza messaggi quando la cella non ha più piante da tagliare, anche prima di `target`.
static func make_cell_series(macro_coords: Vector2i, lot: Vector2i, target: int) -> Dictionary:
	return {
		"id": "%d-%d" % [Time.get_ticks_usec(), randi()], "work_area_id": -1,
		"done": 0, "target": maxi(target, 1),
		"cell_macro_x": macro_coords.x, "cell_macro_y": macro_coords.y, "cell_x": lot.x, "cell_y": lot.y,
	}


static func is_cell_series(series: Dictionary) -> bool:
	return series.has("cell_x")


static func get_cell_series_macro_coords(series: Dictionary) -> Vector2i:
	return Vector2i(int(series.get("cell_macro_x", 0)), int(series.get("cell_macro_y", 0)))


static func get_cell_series_lot(series: Dictionary) -> Vector2i:
	return Vector2i(int(series.get("cell_x", 0)), int(series.get("cell_y", 0)))


# Piante vive e non prenotate della microcella `lot` di `macro_coords` (quelle disegnate, cached_vegetation_positions
# della cella viva), senza filtro per tipo; con `individual`, solo se la microcella è raggiungibile. Stessa forma di
# list_available_plants.
static func list_available_plants_in_lot(
	live_cells: Dictionary, macro_coords: Vector2i, lot: Vector2i, individual: HumanIndividual, reserved: Dictionary
) -> Array[Dictionary]:
	var plants: Array[Dictionary] = []
	var cell: LiveMacroCell = live_cells.get(macro_coords)
	if cell == null or cell.macro_state == null:
		return plants
	if individual != null and not HaulZoneService.is_cell_reachable(individual, macro_coords, lot):
		return plants
	for object_type in PLANT_OBJECT_TYPES:
		for key in cell.cached_vegetation_positions.get(object_type, []):
			var individual_key: Vector3i = key
			if Vector2i(individual_key.x, individual_key.y) != lot:
				continue
			if reserved.has(_plant_reservation_key(macro_coords, object_type, individual_key)):
				continue
			if not PlantCutService.is_individual_alive(cell.macro_state, object_type, individual_key):
				continue
			plants.append({
				"macro_coords": macro_coords, "object_type": object_type, "individual_key": individual_key,
				"subtype": PlantCutService.get_subtype_name(cell.macro_state, object_type, individual_key),
			})
	return plants


# Pianta successiva di una serie su microcella: la prima delle piante vive e libere della cella (stessa microcella,
# quindi tutte alla stessa distanza dal pipottino); {} se nessuna.
static func choose_plant_in_lot(
	live_cells: Dictionary, macro_coords: Vector2i, lot: Vector2i, individual: HumanIndividual, reserved: Dictionary
) -> Dictionary:
	var plants := list_available_plants_in_lot(live_cells, macro_coords, lot, individual, reserved)
	return plants[0] if not plants.is_empty() else {}


static func is_cut_job_unlocked() -> bool:
	return WorkAreaTypes.is_job_unlocked(CUT_JOB)


# Zone con il taglio attivo (ordine di GameData.work_areas). Vuoto senza l'idea.
static func list_cut_work_areas(game_data: GameData) -> Array[WorkArea]:
	var areas: Array[WorkArea] = []
	if game_data == null or not is_cut_job_unlocked():
		return areas
	for area in game_data.work_areas:
		if area.enabled_jobs.has(CUT_JOB):
			areas.append(area)
	return areas


# true se esiste almeno una zona con il taglio attivo (stato del bottone: nessun giro sulle piante).
static func has_cut_work_area(game_data: GameData) -> bool:
	return not list_cut_work_areas(game_data).is_empty()


# true se la zona taglia questa pianta: idea completata, taglio abilitato e filtro della zona ("all", tipo spuntato per
# intero o pianta spuntata); senza filtro, il valore iniziale del lavoro.
static func work_area_accepts_plant(area: WorkArea, object_type: GameTypes.WorldObjectType, subtype_name: String) -> bool:
	if area == null or not area.enabled_jobs.has(CUT_JOB) or not is_cut_job_unlocked():
		return false
	var filters: Variant = area.filters.get(CUT_JOB, null)
	if not (filters is Dictionary):
		filters = WorkAreaTypes.get_default_filters(CUT_JOB)
	if bool(filters.get("all", false)):
		return true
	if (filters.get("groups", []) as Array).has(group_key(object_type)):
		return true
	return (filters.get("plants", []) as Array).has(plant_key(object_type, subtype_name))


# Piante prenotate: chiave "macro_x|macro_y|tipo|x|y|indice" di ogni CutAction in corso o in coda di qualunque pipottino.
static func collect_reserved_plants(individuals: Array) -> Dictionary:
	var reserved: Dictionary = {}
	for member in individuals:
		var tasks: Array = member.task_queue.duplicate()
		if member.current_task != null and not member.current_task.is_finished():
			tasks.append(member.current_task)
		for task in tasks:
			for step in task.steps:
				if step is CutAction:
					var cut := step as CutAction
					reserved[_plant_reservation_key(cut.macro_coords, cut.object_type, cut.individual_key)] = true
	return reserved


# Piante della zona tagliabili da `individual`: quelle disegnate oggi nella macrocella della zona (cached_vegetation_positions
# della cella viva, lo stesso insieme in cui il clic destro trova la pianta), vive, ammesse dal filtro, raggiungibili e
# non prenotate. Macrocella non viva = nessuna pianta (il taglio richiede la cella viva, come il clic destro).
# Array di {"macro_coords": Vector2i, "object_type": WorldObjectType, "individual_key": Vector3i, "subtype": String}.
static func list_available_plants(area: WorkArea, live_cells: Dictionary, individual: HumanIndividual, reserved: Dictionary) -> Array[Dictionary]:
	var plants: Array[Dictionary] = []
	if area == null:
		return plants
	var cell: LiveMacroCell = live_cells.get(area.macro_coords)
	if cell == null or cell.macro_state == null:
		return plants
	for object_type in PLANT_OBJECT_TYPES:
		for key in cell.cached_vegetation_positions.get(object_type, []):
			var individual_key: Vector3i = key
			var lot := Vector2i(individual_key.x, individual_key.y)
			if not area.rect.has_point(lot):
				continue
			if reserved.has(_plant_reservation_key(area.macro_coords, object_type, individual_key)):
				continue
			if not PlantCutService.is_individual_alive(cell.macro_state, object_type, individual_key):
				continue
			var subtype_name := PlantCutService.get_subtype_name(cell.macro_state, object_type, individual_key)
			if not work_area_accepts_plant(area, object_type, subtype_name):
				continue
			if individual != null and not HaulZoneService.is_cell_reachable(individual, area.macro_coords, lot):
				continue
			plants.append({
				"macro_coords": area.macro_coords, "object_type": object_type,
				"individual_key": individual_key, "subtype": subtype_name,
			})
	return plants


# Pianta per `individual` nella zona: tra quelle disponibili, la più vicina con la penalità di affollamento (piante
# prenotate da altri nello stesso lotto o in quelli accanto, come per le rocce); {} se nessuna.
static func choose_plant(area: WorkArea, live_cells: Dictionary, individual: HumanIndividual, reserved: Dictionary) -> Dictionary:
	var available := list_available_plants(area, live_cells, individual, reserved)
	if available.is_empty():
		return {}
	var reserved_by_lot: Dictionary = {}
	for reservation in reserved.keys():
		var parts := String(reservation).split("|")
		if parts.size() == 6 and int(parts[0]) == area.macro_coords.x and int(parts[1]) == area.macro_coords.y:
			var lot := Vector2i(int(parts[3]), int(parts[4]))
			reserved_by_lot[lot] = int(reserved_by_lot.get(lot, 0)) + 1
	var offset := HaulZoneService.macro_offset_for(individual, area.macro_coords)
	var best: Dictionary = {}
	var best_score := INF
	for plant in available:
		var individual_key: Vector3i = plant["individual_key"]
		var lot := Vector2i(individual_key.x, individual_key.y)
		var score := individual.position.distance_to(Vector2(lot) + Vector2(0.5, 0.5) + offset)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				score += NEIGHBOR_RESERVED_PENALTY * float(reserved_by_lot.get(lot + Vector2i(dx, dy), 0))
		if score < best_score:
			best_score = score
			best = plant
	return best


# Scelta automatica della zona: valide le zone con il taglio attivo e almeno una pianta disponibile per `individual`;
# punteggio come l'estrazione (piante disponibili / (distanza dal centro + offset) × fattore per ogni altro pipottino
# che taglia già lì). null se nessuna.
static func choose_work_area(game_data: GameData, live_cells: Dictionary, individual: HumanIndividual, reserved: Dictionary) -> WorkArea:
	if game_data == null or individual == null:
		return null
	var best: WorkArea = null
	var best_score := -1.0
	for area in list_cut_work_areas(game_data):
		var available := list_available_plants(area, live_cells, individual, reserved).size()
		if available <= 0:
			continue
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + HaulZoneService.macro_offset_for(individual, area.macro_coords)
		var score := float(available) / (individual.position.distance_to(center) + ZONE_DISTANCE_OFFSET)
		for other in GameSettings.active_human_individuals:
			if other != individual and is_cutting_in(other, area.id):
				score *= ZONE_CROWDING_FACTOR
		if score > best_score:
			best_score = score
			best = area
	return best


# true se l'individuo ha un taglio in corso nella zona `area_id`.
static func is_cutting_in(individual: HumanIndividual, area_id: int) -> bool:
	if individual == null or individual.current_task == null or individual.current_task.is_finished():
		return false
	return int(individual.current_task.context.get(CONTEXT_WORK_AREA_ID, -1)) == area_id


# "tree" / "shrub".
static func group_key(object_type: GameTypes.WorldObjectType) -> String:
	return String(GameTypes.WorldObjectType.keys()[object_type]).to_lower()


# "tree_conifer", "shrub_fruit_bearing" — stessa forma delle chiavi plant_name_<tipo>_<sottotipo>.
static func plant_key(object_type: GameTypes.WorldObjectType, subtype_name: String) -> String:
	return "%s_%s" % [group_key(object_type), subtype_name]


# Sottotipi di `object_type` dai dati (ordine dei .tres di crescita).
static func list_subtype_names(object_type: GameTypes.WorldObjectType) -> Array[String]:
	var names: Array[String] = []
	for rule in ResourceCalculator.get_subtype_rules(object_type):
		names.append(String(rule.subtype_name))
	return names


static func _plant_reservation_key(macro_coords: Vector2i, object_type: int, individual_key: Vector3i) -> String:
	return "%d|%d|%d|%d|%d|%d" % [macro_coords.x, macro_coords.y, object_type, individual_key.x, individual_key.y, individual_key.z]
