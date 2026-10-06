class_name HaulZoneService
extends RefCounted

# Zona di raccolta della Task haul_resource (2026-09-27, richiesta utente — work areas, passo 2). La raccolta lavora
# sempre su una zona scritta nel context della Task (chiave CONTEXT_KEY), NON su una WorkArea: un Dictionary
# JSON-nativo (sopravvive al salvataggio insieme al context, Rect2i spezzato come in WorkArea.to_save_data):
#   macro_x/macro_y        macrocella della zona;
#   rect_x/rect_y/rect_w/rect_h  rettangolo in microcelle locali alla macrocella;
#   criterion_kind/criterion_category/resource_name/quantity_requested  filtro (PickUpAction.CriterionKind ecc.);
#   source_kind            PickUpAction.SourceKind;
#   max_repeats            ripetizioni massime della raccolta (TaskRepeatRules resta la fonte di "attiva" e contatore).
# Il clic del giocatore crea al volo una zona 1×1 sulla cella cliccata (CLICK_MAX_REPEATS). Le WorkArea vere (passo 3a)
# usano la stessa chiave con work_area_id al posto di macrocella e rettangolo (vedi in fondo). Stateless, funzioni statiche. Letture sempre con .get e default: dopo un reload i numeri
# tornano float da JSON.

const CONTEXT_KEY := "haul_zone"
# Ripetizioni massime della zona 1×1 del clic: TaskRepeatRules.MAX_REPEATS (MAX_TRIPS viaggi in tutto).
const CLICK_MAX_REPEATS: int = TaskRepeatRules.MAX_REPEATS
# Consegna "fino a mucchio vuoto" (taglio, 2026-10-04): ripetizioni pari alle unità del mucchio, nessun numero fisso di
# viaggi da mostrare (Task.get_activity_description salta il contatore). Assente nelle altre zone.
const UNTIL_EMPTY_KEY := "until_empty"
# Etichetta della consegna fino a mucchio vuoto (2026-10-05): nome della task del lavoro che ha lasciato il mucchio
# ("task_cut_name", "task_quarry_name"); Task.get_activity_description la mostra al posto di "Raccolta". Assente nelle
# altre zone (raccolta, anche da un mucchio ordinata a mano).
const LABEL_TASK_KEY := "label_task_name"


static func get_label_task_name(zone: Dictionary) -> String:
	return String(zone.get(LABEL_TASK_KEY, ""))


static func make_zone(
	macro_coords: Vector2i, rect: Rect2i, criterion_kind: int, criterion_category: int, resource_name: String,
	quantity_requested: int, source_kind: int, max_repeats: int
) -> Dictionary:
	return {
		"macro_x": macro_coords.x,
		"macro_y": macro_coords.y,
		"rect_x": rect.position.x,
		"rect_y": rect.position.y,
		"rect_w": rect.size.x,
		"rect_h": rect.size.y,
		"criterion_kind": criterion_kind,
		"criterion_category": criterion_category,
		"resource_name": resource_name,
		"quantity_requested": quantity_requested,
		"source_kind": source_kind,
		"max_repeats": max_repeats,
	}


# Zona 1×1 equivalente a una PickUpAction già costruita: per le Task salvate prima delle zone (nessuna CONTEXT_KEY nel
# context), con le ripetizioni del clic.
static func from_pickup(step: PickUpAction) -> Dictionary:
	var macro_coords := Vector2i(step.macro_state.x, step.macro_state.y) if step.macro_state != null else Vector2i.ZERO
	return make_zone(
		macro_coords, Rect2i(step.target_position, Vector2i.ONE), int(step.criterion_kind), step.criterion_category,
		step.resource_name, step.quantity_requested, int(step.source_kind), CLICK_MAX_REPEATS
	)


# Zona scritta nel context, {} se assente.
static func get_zone(context: Dictionary) -> Dictionary:
	var zone: Variant = context.get(CONTEXT_KEY, {})
	return zone if zone is Dictionary else {}


static func get_macro_coords(zone: Dictionary) -> Vector2i:
	return Vector2i(int(zone.get("macro_x", 0)), int(zone.get("macro_y", 0)))


static func get_rect(zone: Dictionary) -> Rect2i:
	return Rect2i(int(zone.get("rect_x", 0)), int(zone.get("rect_y", 0)), int(zone.get("rect_w", 1)), int(zone.get("rect_h", 1)))


static func get_criterion_kind(zone: Dictionary) -> int:
	return int(zone.get("criterion_kind", PickUpAction.CriterionKind.NAME))


static func get_criterion_category(zone: Dictionary) -> int:
	return int(zone.get("criterion_category", -1))


static func get_resource_name(zone: Dictionary) -> String:
	return String(zone.get("resource_name", "pebble"))


static func get_quantity_requested(zone: Dictionary) -> int:
	return int(zone.get("quantity_requested", -1))


static func get_source_kind(zone: Dictionary) -> int:
	return int(zone.get("source_kind", PickUpAction.SourceKind.TERRAIN))


static func get_max_repeats(zone: Dictionary) -> int:
	return int(zone.get("max_repeats", CLICK_MAX_REPEATS))


static func is_until_empty(zone: Dictionary) -> bool:
	return bool(zone.get(UNTIL_EMPTY_KEY, false))


# Cella bersaglio della raccolta dentro la zona, null se nessuna cella ha qualcosa per il filtro. Una zona 1×1 dà
# sempre la sua cella, anche vuota (il comportamento del clic di sempre: si va comunque e la raccolta a vuoto chiude
# la Task). Altrimenti la cella con qualcosa da raccogliere più vicina a `from_position` (coordinate locali
# dell'individuo, lo stesso sistema di PickUpAction.target_position). Disponibilità = PickUpAction.has_candidates_at,
# la stessa del PickUp; l'elenco delle risorse del catalogo è letto una volta sola per tutta la zona.
static func find_target_cell(zone: Dictionary, macro_state: MacroCellState, from_position: Vector2) -> Variant:
	var rect := get_rect(zone)
	if rect.size == Vector2i.ONE:
		return rect.position
	if macro_state == null:
		return null
	var criterion_kind := get_criterion_kind(zone)
	var names := PickUpAction.list_candidate_names(criterion_kind, get_resource_name(zone))
	var best: Variant = null
	var best_distance := INF
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not PickUpAction.has_candidates_at(macro_state, cell, get_source_kind(zone), criterion_kind, get_criterion_category(zone), names):
				continue
			var distance := from_position.distance_squared_to(Vector2(cell) + Vector2(0.5, 0.5))
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


# true se almeno una cella della zona ha ancora qualcosa per il filtro (controllo della ripetizione).
static func has_available(zone: Dictionary, macro_state: MacroCellState) -> bool:
	if macro_state == null:
		return false
	var rect := get_rect(zone)
	var criterion_kind := get_criterion_kind(zone)
	var names := PickUpAction.list_candidate_names(criterion_kind, get_resource_name(zone))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if PickUpAction.has_candidates_at(macro_state, Vector2i(x, y), get_source_kind(zone), criterion_kind, get_criterion_category(zone), names):
				return true
	return false


# --- Zone vere (WorkArea) — 2026-09-27, richiesta utente, work areas passo 3a ---
# Per una WorkArea la zona del context contiene solo work_area_id e il filtro dell'ordine (criterion_kind,
# criterion_category, resource_name) più source_kind (sempre TERRAIN) e max_repeats: rettangolo, macrocella e filtro
# della zona si rileggono dalla WorkArea (GameData.work_areas) a ogni ricerca, così le modifiche del giocatore valgono
# subito e una zona eliminata risulta assente (resolve_work_area -> null). Si raccolgono solo le risorse che passano
# sia il filtro dell'ordine sia quello della zona (allowed_names).

# Ripetizioni massime di una raccolta in una WorkArea (una ripetizione = un viaggio completo fino allo scarico).
const WORK_AREA_MAX_REPEATS: int = 5
# Viaggi della raccolta in zona (2026-10-01, selettore "viaggi" del dialog di Raccogli, UserOptions.work_area_gather_trips):
# da 1 a WORK_AREA_MAX_TRIPS. N viaggi = il primo + (N - 1) ripetizioni (max_repeats della zona); 1 = nessuna ripetizione.
const WORK_AREA_MAX_TRIPS: int = 5
# Scelta della cella: una cella verso cui sta già andando un altro pipottino che raccoglie nella stessa zona conta
# come più lontana di tante microcelle (per ogni pipottino diretto lì).
const HEADING_CELL_DISTANCE_PENALTY: float = 6.0
# Scelta della cella: a caso tra le migliori N.
const CELL_CHOICE_TOP_COUNT: int = 3
# Scelta della zona: punteggio = disponibile / (distanza + ZONE_DISTANCE_OFFSET) × ZONE_CROWDING_FACTOR^(pipottini che
# già raccolgono lì).
const ZONE_DISTANCE_OFFSET: float = 10.0
const ZONE_CROWDING_FACTOR: float = 0.7
# Risorse raccolte nel viaggio in corso (context, solo WorkArea): cercate al magazzino a fine viaggio.
const CONTEXT_TRIP_RESOURCES := "haul_trip_resources"
const HAUL_JOB := "haul"


static func make_work_area_zone(
	area_id: int, criterion_kind: int, criterion_category: int, resource_name: String, max_repeats: int = WORK_AREA_MAX_REPEATS
) -> Dictionary:
	return {
		"work_area_id": area_id,
		"criterion_kind": criterion_kind,
		"criterion_category": criterion_category,
		"resource_name": resource_name,
		"quantity_requested": -1,
		"source_kind": PickUpAction.SourceKind.TERRAIN,
		"max_repeats": max_repeats,
	}


static func get_work_area_id(zone: Dictionary) -> int:
	return int(zone.get("work_area_id", -1))


static func is_work_area_zone(zone: Dictionary) -> bool:
	return get_work_area_id(zone) >= 0


# WorkArea della zona, null se eliminata (o se la zona non è di una WorkArea).
static func resolve_work_area(zone: Dictionary) -> WorkArea:
	if not is_work_area_zone(zone):
		return null
	return WorkAreaService.find_by_id(GameSettings.active_game_data, get_work_area_id(zone))


# Limite "solo cibo" delle zone (2026-10-01, richiesta utente): attivo finché il Folk del giocatore non ha completato
# WorkAreaTypes.ADVANCED_REQUIRED_IDEA_ID. Le idee si leggono da GameSettings.active_human_folk (stesso canale di
# TerrainScatteredResourceService.is_resource_locked e di active_game_data/active_human_individuals già usati qui),
# così nessuna firma cambia. Senza un Folk attivo il limite resta acceso. Letto ad ogni chiamata, mai memorizzato:
# completata l'idea, le zone esistenti accettano subito tutto.
static func is_food_only_limit_active() -> bool:
	var folk := GameSettings.active_human_folk
	return folk == null or not folk.completed_ideas.has(WorkAreaTypes.ADVANCED_REQUIRED_IDEA_ID)


# true se la zona raccoglie questa risorsa: raccolta abilitata e filtro della zona ("all", oppure categoria o risorsa
# spuntate — vedi WorkAreaInfoPanel). Col limite "solo cibo" ogni risorsa non FOOD è rifiutata e "all" vale come
# "tutto il cibo" (anche per le zone salvate prima). Unico punto del vincolo: allowed_names_for, choose_work_area,
# list_work_area_resources e has_haul_work_area passano tutti da qui.
static func work_area_accepts(area: WorkArea, resource_name: String) -> bool:
	if area == null or not area.enabled_jobs.has(HAUL_JOB):
		return false
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if is_food_only_limit_active() and (rules == null or int(rules.category) != int(SecondaryResourceTypes.Category.FOOD)):
		return false
	var filters: Variant = area.filters.get(HAUL_JOB, null)
	if not (filters is Dictionary):
		filters = WorkAreaTypes.get_default_filters(HAUL_JOB)
	if bool(filters.get("all", true)):
		return true
	var categories: Array = filters.get("categories", [])
	if rules != null and categories.has(int(rules.category)):
		return true
	var resources: Array = filters.get("resources", [])
	return resources.has(resource_name)


# Risorse dell'ordine accettate anche dalla zona (catalogo letto una volta sola).
static func allowed_names(zone: Dictionary, area: WorkArea) -> Array[String]:
	return allowed_names_for(area, get_criterion_kind(zone), get_criterion_category(zone), get_resource_name(zone))


static func allowed_names_for(area: WorkArea, criterion_kind: int, criterion_category: int, resource_name: String) -> Array[String]:
	var result: Array[String] = []
	for candidate_name in PickUpAction.list_candidate_names(criterion_kind, resource_name):
		if criterion_kind == PickUpAction.CriterionKind.CATEGORY:
			var rules := CaloricCalculator.get_caloric_source_rules(candidate_name)
			if rules == null or int(rules.category) != criterion_category:
				continue
		if work_area_accepts(area, candidate_name):
			result.append(candidate_name)
	return result


# Risorse tra `names` di cui almeno un'unità entra ancora nello zaino: spazio libero sufficiente e, per una varietà
# non ancora trasportata, varietà sotto HumanIndividual.MAX_CARRIED_VARIETIES. Vuoto = zaino "pieno" per l'ordine.
static func fitting_names(individual: HumanIndividual, names: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var free_space: float = individual.max_carry_capacity - individual.get_carried_space()
	var at_variety_cap: bool = individual.carried_resources.size() >= HumanIndividual.MAX_CARRIED_VARIETIES
	for candidate_name in names:
		var rules := CaloricCalculator.get_caloric_source_rules(candidate_name)
		if rules == null or rules.space_per_unit <= 0.0:
			continue
		if at_variety_cap and not individual.carried_resources.has(candidate_name):
			continue
		if int(floor(free_space / rules.space_per_unit + FoodSelectionService.UNIT_FIT_EPSILON)) <= 0:
			continue
		result.append(candidate_name)
	return result


# Offset (in microcelle) della macrocella `macro_coords` rispetto alla home dell'individuo: le posizioni
# dell'individuo sono locali alla home.
static func macro_offset_for(individual: HumanIndividual, macro_coords: Vector2i) -> Vector2:
	return Vector2(macro_coords - individual.home_macro_coords) * World.WIDTH


# Stessa regola di PathfindingService.reachability_for: regioni della sola macrocella home; fuori di lì true.
static func is_cell_reachable(individual: HumanIndividual, macro_coords: Vector2i, cell: Vector2i) -> bool:
	if macro_coords != individual.home_macro_coords:
		return true
	var live_cell := PathfindingService.get_live_cell(macro_coords)
	var from := Vector2i(floori(individual.position.x), floori(individual.position.y))
	return PathfindingService.is_reachable(live_cell, from, cell)


# true se l'individuo sta raccogliendo (Task in corso) nella WorkArea `area_id`.
static func is_gathering_in(individual: HumanIndividual, area_id: int) -> bool:
	if individual == null or individual.current_task == null or individual.current_task.is_finished():
		return false
	return get_work_area_id(get_zone(individual.current_task.context)) == area_id


# Cella verso cui l'individuo sta andando a raccogliere nella WorkArea `area_id` (primo PickUp dal passo corrente in
# poi), null se nessuna.
static func heading_cell(individual: HumanIndividual, area_id: int) -> Variant:
	if not is_gathering_in(individual, area_id):
		return null
	var task: Task = individual.current_task
	for i in range(task.current_step_index, task.steps.size()):
		if task.steps[i] is PickUpAction:
			return (task.steps[i] as PickUpAction).target_position
	return null


# Cella di raccolta nella WorkArea per `individual`: celle raggiungibili con qualcosa tra `names`; distanza dalla
# posizione attuale, + HEADING_CELL_DISTANCE_PENALTY per ogni altro pipottino della stessa zona diretto lì; a caso tra
# le migliori CELL_CHOICE_TOP_COUNT. null se nessuna.
static func find_work_area_target_cell(area: WorkArea, macro_state: MacroCellState, names: Array[String], individual: HumanIndividual) -> Variant:
	if area == null or macro_state == null or names.is_empty():
		return null
	var headed: Dictionary = {}
	for other in GameSettings.active_human_individuals:
		if other == individual:
			continue
		var other_cell: Variant = heading_cell(other, area.id)
		if other_cell != null:
			headed[other_cell] = int(headed.get(other_cell, 0)) + 1
	var offset := macro_offset_for(individual, area.macro_coords)
	var scored: Array = []
	for y in range(area.rect.position.y, area.rect.end.y):
		for x in range(area.rect.position.x, area.rect.end.x):
			var cell := Vector2i(x, y)
			if not PickUpAction.has_candidates_at(macro_state, cell, PickUpAction.SourceKind.TERRAIN, PickUpAction.CriterionKind.ALL, -1, names):
				continue
			if not is_cell_reachable(individual, area.macro_coords, cell):
				continue
			var distance := individual.position.distance_to(Vector2(cell) + Vector2(0.5, 0.5) + offset)
			distance += HEADING_CELL_DISTANCE_PENALTY * float(headed.get(cell, 0))
			scored.append({"cell": cell, "distance": distance})
	if scored.is_empty():
		return null
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	return scored[randi() % mini(CELL_CHOICE_TOP_COUNT, scored.size())]["cell"]


# Unità disponibili di `names` nelle celle della WorkArea (solo quelle raggiungibili da `individual`, se passato).
static func count_available(area: WorkArea, macro_state: MacroCellState, names: Array[String], individual: HumanIndividual = null) -> int:
	if area == null or macro_state == null or names.is_empty():
		return 0
	var total := 0
	for y in range(area.rect.position.y, area.rect.end.y):
		for x in range(area.rect.position.x, area.rect.end.x):
			var cell := Vector2i(x, y)
			var cell_total := 0
			for candidate_name in names:
				cell_total += maxi(PickUpAction.get_source_available_at(macro_state, cell, PickUpAction.SourceKind.TERRAIN, candidate_name), 0)
			if cell_total > 0 and (individual == null or is_cell_reachable(individual, area.macro_coords, cell)):
				total += cell_total
	return total


# true se nella WorkArea c'è ancora qualcosa tra `names` (controllo della ripetizione).
static func work_area_has_available(area: WorkArea, macro_state: MacroCellState, names: Array[String]) -> bool:
	if area == null or macro_state == null or names.is_empty():
		return false
	for y in range(area.rect.position.y, area.rect.end.y):
		for x in range(area.rect.position.x, area.rect.end.x):
			if PickUpAction.has_candidates_at(macro_state, Vector2i(x, y), PickUpAction.SourceKind.TERRAIN, PickUpAction.CriterionKind.ALL, -1, names):
				return true
	return false


# Scelta automatica della zona per un ordine di raccolta: valide le WorkArea con raccolta abilitata, intersezione dei
# filtri non vuota e qualcosa di raggiungibile da raccogliere; punteggio = disponibile / (distanza pipottino–centro
# zona + ZONE_DISTANCE_OFFSET) × ZONE_CROWDING_FACTOR per ogni altro pipottino che già raccoglie lì. null se nessuna.
static func choose_work_area(
	game_data: GameData, world: World, individual: HumanIndividual, criterion_kind: int, criterion_category: int, resource_name: String
) -> WorkArea:
	if game_data == null or world == null or individual == null:
		return null
	var best: WorkArea = null
	var best_score := -1.0
	for area in game_data.work_areas:
		var names := allowed_names_for(area, criterion_kind, criterion_category, resource_name)
		if names.is_empty():
			continue
		var macro_state := world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		var available := count_available(area, macro_state, names, individual)
		if available <= 0:
			continue
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + macro_offset_for(individual, area.macro_coords)
		var score := float(available) / (individual.position.distance_to(center) + ZONE_DISTANCE_OFFSET)
		for other in GameSettings.active_human_individuals:
			if other != individual and is_gathering_in(other, area.id):
				score *= ZONE_CROWDING_FACTOR
		if score > best_score:
			best_score = score
			best = area
	return best


# true se esiste almeno una WorkArea con la raccolta abilitata che accetta almeno una risorsa raccoglibile da terra
# (bottone "Raccogli" della barra comandi): col limite "solo cibo" una zona che filtra solo non-cibo non conta.
static func has_haul_work_area(game_data: GameData) -> bool:
	if game_data == null:
		return false
	for area in game_data.work_areas:
		if not area.enabled_jobs.has(HAUL_JOB):
			continue
		for resource_name in _list_pickable_names():
			if work_area_accepts(area, resource_name):
				return true
	return false


# Risorse raccoglibili da terra (TerrainScatteredResourceService.is_pickable), lette una volta per sessione: il catalogo
# delle .tres non cambia e has_haul_work_area gira ad ogni frame (GameScene._sync_command_bar), mentre
# list_secondary_resource_names scansiona la cartella.
static var _pickable_names_cache: Array[String] = []
static var _pickable_names_loaded: bool = false


static func _list_pickable_names() -> Array[String]:
	if not _pickable_names_loaded:
		_pickable_names_loaded = true
		for resource_name in CaloricCalculator.list_secondary_resource_names():
			if TerrainScatteredResourceService.is_pickable(resource_name):
				_pickable_names_cache.append(resource_name)
	return _pickable_names_cache


# Risorse raccoglibili nelle WorkArea con la raccolta abilitata, per il dialog di scelta: una voce per risorsa con la
# quantità totale nelle zone che la accettano ({"resource_name", "category", "quantity", "source_kind"}).
static func list_work_area_resources(game_data: GameData, world: World) -> Array:
	var entries: Array = []
	if game_data == null or world == null:
		return entries
	var totals: Dictionary = {}
	var catalog := CaloricCalculator.list_secondary_resource_names()
	for area in game_data.work_areas:
		if not area.enabled_jobs.has(HAUL_JOB):
			continue
		var macro_state := world.get_cell_state_at(area.macro_coords.x, area.macro_coords.y)
		for candidate_name in catalog:
			if not work_area_accepts(area, candidate_name):
				continue
			var single: Array[String] = [candidate_name]
			var quantity := count_available(area, macro_state, single)
			if quantity > 0:
				totals[candidate_name] = int(totals.get(candidate_name, 0)) + quantity
	for candidate_name in totals.keys():
		var rules := CaloricCalculator.get_caloric_source_rules(candidate_name)
		entries.append({
			"resource_name": candidate_name,
			"category": int(rules.category) if rules != null else int(SecondaryResourceTypes.Category.FOOD),
			"quantity": int(totals[candidate_name]),
			"source_kind": PickUpAction.SourceKind.TERRAIN,
		})
	return entries
