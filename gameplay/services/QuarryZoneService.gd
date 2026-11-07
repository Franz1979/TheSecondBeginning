class_name QuarryZoneService
extends RefCounted

# Estrazione della pietra nelle zone di lavoro (2026-10-05, richiesta utente — Quarry in zona, passo 1): lavoro
# "quarry" della zona (WorkAreaTypes.JOBS, sbloccato da work_areas_advanced come la caccia), zone valide, scelta della
# zona e della roccia. Separato da HaulZoneService/HuntZoneService: stesso schema di punteggio della raccolta, ma le
# rocce prenotate da un pipottino (una QuarryAction in corso o in coda) sono ESCLUSE, non penalizzate. Stateless,
# funzioni statiche. L'estrazione vera passa dalle stesse funzioni del clic destro (GameScene._assign_quarry_task).

const QUARRY_JOB := "quarry"
# Zona della task (etichetta "Estrazione (Zona 1)"), scritta nel context da GameScene._assign_quarry_task.
const CONTEXT_WORK_AREA_ID := "quarry_work_area_id"
# Stesso punteggio della raccolta (HaulZoneService): disponibile / (distanza + offset) × fattore per ogni altro pipottino
# che estrae già nella zona.
const ZONE_DISTANCE_OFFSET: float = 10.0
const ZONE_CROWDING_FACTOR: float = 0.7
# Scelta della roccia: distanza + penalità per ogni roccia prenotata da altri a una microcella di distanza (affollamento).
const NEIGHBOR_RESERVED_PENALTY: float = 6.0

# Serie di estrazioni (2026-10-05, passo 2): "Pietre da estrarre" del comando Estrai, da COUNT_MIN a COUNT_MAX (ricordato
# in UserOptions.work_area_quarry_count, la prima volta COUNT_DEFAULT). La serie viaggia con l'estrazione (context
# CONTEXT_SERIES), il mucchio (pile_ref "quarry_series") e la consegna fino a mucchio vuoto (zona della consegna,
# SERIES_ZONE_KEY): {"id": String, "work_area_id": int, "done": int (estrazioni concluse), "target": int, "rock_x",
# "rock_y" (ultima roccia, -1 = nessuna)}. Alla chiusura dell'ultima consegna HumanIndividualActionService chiede
# l'estrazione successiva (GameScene._on_quarry_zone_series_continue_requested); qualunque intoppo chiude la serie.
const COUNT_MIN: int = 1
const COUNT_MAX: int = 5
const COUNT_DEFAULT: int = 3
const CONTEXT_SERIES := "quarry_zone_series"
const SERIES_ZONE_KEY := "quarry_series"


static func make_series(area_id: int, target: int, source: String = ExtractionSourceService.SOURCE_ROCK) -> Dictionary:
	return {
		"id": "%d-%d" % [Time.get_ticks_usec(), randi()], "work_area_id": area_id,
		"done": 0, "target": clampi(target, COUNT_MIN, COUNT_MAX), "rock_x": -1, "rock_y": -1, "source": source,
	}


# Fonte della serie (2026-11-04); senza, una serie di un salvataggio precedente: la roccia.
static func get_series_source(series: Dictionary) -> String:
	return String(series.get("source", ExtractionSourceService.SOURCE_ROCK))


# Motivo tradotto quando nella zona manca il bersaglio della fonte.
static func no_target_text(source: String) -> String:
	return GameContext.tr_text("work_area_clay_no_target" if source == ExtractionSourceService.SOURCE_CLAY else "work_area_quarry_no_rock")


# true se sulla microcella c'è una costruzione: sull'argilla può passare una strada, e va tolta prima di scavare.
static func is_under_building(macro_coords: Vector2i, position: Vector2i) -> bool:
	var world: World = GameSettings.active_world
	if world == null:
		return false
	for building in world.buildings:
		if BuildingFootprint.covers(building, macro_coords, position):
			return true
	return false


# Serie del context di un'estrazione ({} se non ne fa parte).
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


# Messaggio di serie interrotta (chiave tr() di HumanIndividualActionService.series_stopped_message).
const SERIES_STOPPED_KEY := "quarry_series_stopped"


static func is_series_complete(series: Dictionary) -> bool:
	return int(series.get("done", 0)) >= int(series.get("target", 0))


static func is_quarry_job_unlocked() -> bool:
	return WorkAreaTypes.is_job_unlocked(QUARRY_JOB)


# Zone con l'estrazione attiva (ordine di GameData.work_areas). Vuoto senza l'idea.
static func list_quarry_work_areas(game_data: GameData) -> Array[WorkArea]:
	var areas: Array[WorkArea] = []
	if game_data == null or not is_quarry_job_unlocked():
		return areas
	for area in game_data.work_areas:
		if area.enabled_jobs.has(QUARRY_JOB):
			areas.append(area)
	return areas


# true se esiste almeno una zona con l'estrazione attiva (stato del bottone: nessun giro sulle rocce).
static func has_quarry_work_area(game_data: GameData) -> bool:
	return not list_quarry_work_areas(game_data).is_empty()


# Rocce prenotate: chiave "macro_x|macro_y|x|y" di ogni QuarryAction in corso o in coda di qualunque pipottino.
static func collect_reserved_rocks(individuals: Array) -> Dictionary:
	var reserved: Dictionary = {}
	for member in individuals:
		var tasks: Array = member.task_queue.duplicate()
		if member.current_task != null and not member.current_task.is_finished():
			tasks.append(member.current_task)
		for task in tasks:
			for step in task.steps:
				if step is QuarryAction:
					reserved[_rock_key((step as QuarryAction).macro_coords, (step as QuarryAction).rock_position)] = true
	return reserved


# true se il filtro della zona (WorkArea.filters["quarry"], {"all": bool, "sources": [String]}, 2026-11-04) ammette la fonte.
static func area_accepts_source(area: WorkArea, source: String) -> bool:
	var filters: Variant = area.filters.get(QUARRY_JOB, null)
	if not (filters is Dictionary):
		filters = WorkAreaTypes.get_default_filters(QUARRY_JOB)
	return bool(filters.get("all", true)) or (filters.get("sources", []) as Array).has(source)


# Bersagli della zona estraibili da `individual`: fonte ammessa dal filtro, con qualcosa di rimasto, raggiungibili e non
# prenotati. Array[Vector2i] di microcelle locali alla macrocella della zona.
# `first_only` (2026-10-22, come CutZoneService.list_available_plants): si ferma al primo bersaglio trovato.
static func list_available_rocks(
	area: WorkArea, macro_state: MacroCellState, individual: HumanIndividual, reserved: Dictionary, first_only: bool = false,
	source: String = ExtractionSourceService.SOURCE_ROCK
) -> Array[Vector2i]:
	var rocks: Array[Vector2i] = []
	if area == null or macro_state == null or not area_accepts_source(area, source):
		return rocks
	var is_clay := source == ExtractionSourceService.SOURCE_CLAY
	if not (macro_state.clay_positions_generated if is_clay else macro_state.stone_positions_generated):
		return rocks
	for position in macro_state.clay_positions if is_clay else macro_state.stone_positions:
		var rock: Vector2i = position
		if not area.rect.has_point(rock):
			continue
		if reserved.has(_rock_key(area.macro_coords, rock)):
			continue
		if ExtractionSourceService.get_remaining(source, macro_state, rock) <= 0:
			continue
		if is_clay and is_under_building(area.macro_coords, rock):
			continue
		if individual != null and not HaulZoneService.is_cell_reachable(individual, area.macro_coords, rock):
			continue
		rocks.append(rock)
		if first_only:
			return rocks
	return rocks


# Roccia per `individual` nella zona: tra quelle disponibili, la più vicina con la penalità di affollamento; null se
# nessuna.
static func choose_rock(
	area: WorkArea, macro_state: MacroCellState, individual: HumanIndividual, reserved: Dictionary,
	source: String = ExtractionSourceService.SOURCE_ROCK
) -> Variant:
	return choose_rock_from(area, macro_state, individual.home_macro_coords, individual.position, individual, reserved, source)


# Come choose_rock, ma la distanza si misura da `origin_pos` (locale a `origin_macro`) invece che dal pipottino
# (2026-10-23, bersaglio scelto dall'ordine: DrawerOrderTargetService). `individual` solo per la raggiungibilità (null =
# nessun controllo).
static func choose_rock_from(
	area: WorkArea, macro_state: MacroCellState, origin_macro: Vector2i, origin_pos: Vector2, individual: HumanIndividual, reserved: Dictionary,
	source: String = ExtractionSourceService.SOURCE_ROCK
) -> Variant:
	var best: Variant = null
	var best_score := INF
	var offset := Vector2(area.macro_coords - origin_macro) * World.WIDTH
	for rock in list_available_rocks(area, macro_state, individual, reserved, false, source):
		var score := origin_pos.distance_to(Vector2(rock) + Vector2(0.5, 0.5) + offset)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if (dx != 0 or dy != 0) and reserved.has(_rock_key(area.macro_coords, rock + Vector2i(dx, dy))):
					score += NEIGHBOR_RESERVED_PENALTY
		if score < best_score:
			best_score = score
			best = rock
	return best


# Scelta automatica della zona: valide le zone con l'estrazione attiva e almeno una roccia disponibile per `individual`;
# punteggio come la raccolta (rocce disponibili / (distanza dal centro + offset) × fattore per ogni altro pipottino che
# estrae già lì). null se nessuna.
# Tenuta per il fotogramma in corso, per pipottino e prenotazioni (2026-10-22, come CutZoneService.choose_work_area).
static var _chosen_area_cache: Dictionary = {}
static var _chosen_area_frame: int = -1


static func choose_work_area(
	game_data: GameData, world: World, individual: HumanIndividual, reserved: Dictionary,
	source: String = ExtractionSourceService.SOURCE_ROCK
) -> WorkArea:
	if game_data == null or world == null or individual == null:
		return null
	var frame := Engine.get_process_frames()
	if frame != _chosen_area_frame:
		_chosen_area_cache.clear()
		_chosen_area_frame = frame
	var cache_key := [individual.get_instance_id(), reserved.hash(), source]
	if not _chosen_area_cache.has(cache_key):
		_chosen_area_cache[cache_key] = choose_work_area_from(
			game_data, world, individual.home_macro_coords, individual.position, individual, reserved, source
		)
	return _chosen_area_cache[cache_key]


# Come choose_work_area, ma la distanza si misura da `origin_pos` (locale a `origin_macro`) e senza memoria (2026-10-23,
# bersaglio scelto dall'ordine). `individual` solo per raggiungibilità e affollamento (null = nessun controllo).
static func choose_work_area_from(
	game_data: GameData, world: World, origin_macro: Vector2i, origin_pos: Vector2, individual: HumanIndividual, reserved: Dictionary,
	source: String = ExtractionSourceService.SOURCE_ROCK
) -> WorkArea:
	var best: WorkArea = null
	var best_score := -1.0
	for area in list_quarry_work_areas(game_data):
		var macro_state := world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		var available := list_available_rocks(area, macro_state, individual, reserved, false, source).size()
		if available <= 0:
			continue
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + Vector2(area.macro_coords - origin_macro) * World.WIDTH
		var score := float(available) / (origin_pos.distance_to(center) + ZONE_DISTANCE_OFFSET)
		for other in GameSettings.active_human_individuals:
			if other != individual and is_quarrying_in(other, area.id):
				score *= ZONE_CROWDING_FACTOR
		if score > best_score:
			best_score = score
			best = area
	return best


# true se l'individuo ha un'estrazione in corso nella zona `area_id`.
static func is_quarrying_in(individual: HumanIndividual, area_id: int) -> bool:
	if individual == null or individual.current_task == null or individual.current_task.is_finished():
		return false
	return int(individual.current_task.context.get(CONTEXT_WORK_AREA_ID, -1)) == area_id


# Chiave di prenotazione di una roccia, come in collect_reserved_rocks (2026-10-23, DrawerOrderTargetService).
static func rock_reservation_key(macro_coords: Vector2i, rock: Vector2i) -> String:
	return _rock_key(macro_coords, rock)


static func _rock_key(macro_coords: Vector2i, rock: Vector2i) -> String:
	return "%d|%d|%d|%d" % [macro_coords.x, macro_coords.y, rock.x, rock.y]
