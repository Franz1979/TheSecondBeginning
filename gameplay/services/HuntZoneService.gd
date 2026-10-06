class_name HuntZoneService
extends RefCounted

# Caccia nelle zone di lavoro (2026-10-01, richiesta utente — primo passo: solo servizio e interfaccia, nessuna Task o
# Action ancora). Stateless, funzioni statiche, stesso schema di HaulZoneService. Regole decise per i passi successivi:
# pattuglia nella zona (attesa massima 1 giorno senza avvistamenti), una ripetizione = una preda portata a casa,
# inseguimento libero di uscire dalla zona, filtro per specie in WorkArea.filters["hunt"] ({"all": bool,
# "species": [String]}, vedi WorkAreaInfoPanel), comando diretto sull'animale sempre disponibile e invariato.
#
# Avvistamento = la preda è entro il raggio di vista del cacciatore STESSO (FogOfWarRenderer.visibility_radius), mai la
# visibilità della tribù (FogOfWarRenderer.is_animal_visible_at vale anche per 20 giorni dopo il passaggio di chiunque).

const HUNT_JOB := "hunt"
# Context della futura Task di caccia in zona: id della WorkArea in cui il cacciatore sta cacciando (choose_prey lo usa
# per non far puntare a due cacciatori della stessa zona la stessa preda). La preda puntata è "hunt_prey_id", la stessa
# chiave della caccia diretta (GameScene._try_assign_hunt_command_on_right_click).
const CONTEXT_WORK_AREA_ID := "hunt_work_area_id"
const CONTEXT_PREY_ID := "hunt_prey_id"
# Resto della preda puntata (passo 2a), JSON-nativo perché il context si salva così com'è.
const CONTEXT_PREY_SPECIES := "hunt_prey_species"
const CONTEXT_PREY_MACRO_X := "hunt_prey_macro_x"
const CONTEXT_PREY_MACRO_Y := "hunt_prey_macro_y"
# Richiesta di PatrolAreaAction: preda avvistata, inserire gli step di caccia (HumanIndividualActionService).
const CONTEXT_PENDING_PREY := "pending_hunt_zone_prey"
# Giorni di gioco passati dentro la zona senza avvistamenti (PatrolAreaAction), azzerati a ogni avvistamento.
const CONTEXT_UNSIGHTED_DAYS := "hunt_zone_unsighted_days"
# Task della caccia in zona (hunt_zone.tres) e chiave consumata da TaskFactory per lo step di pattuglia.
const TASK_NAME := "task_hunt_zone_name"
const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/hunt_zone.tres"
const FACTORY_WORK_AREA_KEY := "patrol_work_area_id"
# Scelta automatica della zona: punteggio = 1 / (distanza + ZONE_DISTANCE_OFFSET) × ZONE_CROWDING_FACTOR per ogni
# altro cacciatore già in quella zona (stessi valori di HaulZoneService).
const ZONE_DISTANCE_OFFSET: float = 10.0
const ZONE_CROWDING_FACTOR: float = 0.7
# Serie di cacce fino a un limite di carne (2026-10-01, passo 2b — dal selettore "carne" del dialog di Caccia,
# PickupChoiceDialog in modalità caccia, valore ricordato in UserOptions.hunt_zone_meat_target). La serie viaggia nel context ({"work_area_id", "target",
# "delivered"}, JSON-nativo, salvato con la Task): nella Task di caccia in zona e, dopo un'uccisione, nella Task di
# macellazione nata da lei, dove UnloadAction somma la carne consegnata (focolare o magazzino). A fine macellazione,
# sotto il limite e con la zona ancora attiva, si accoda una nuova caccia nella stessa zona
# (HumanIndividualActionService._continue_hunt_zone_series -> GameScene). Senza la chiave: una sola caccia.
# Valori del selettore (nessuno oltre 20) e valore iniziale.
const MEAT_TARGET_OPTIONS: Array[int] = [5, 10, 15, 20]
const MEAT_TARGET_DEFAULT: int = 10
const CONTEXT_MEAT_SERIES := "hunt_zone_meat_series"
const MEAT_RESOURCE := "meat"
# Raggio di vista se nessun FogOfWarRenderer vivo è disponibile (stesso default di FogOfWarRenderer.visibility_radius).
const FALLBACK_VISIBILITY_RADIUS: float = 6.0


# Log [HUNT ZONE] (DebugLogging.SHOW_HUNT_ZONE_LOGS). `individual` null = riga senza pipottino.
static func log_event(individual: Variant, text: String) -> void:
	if not DebugLogging.SHOW_HUNT_ZONE_LOGS:
		return
	if individual == null:
		print("[HUNT ZONE] %s" % text)
	else:
		print("[HUNT ZONE] #%d %s: %s" % [individual.id, individual.name, text])


# La caccia nelle zone richiede l'idea "Aree di lavoro" (WorkAreaTypes.ADVANCED_REQUIRED_IDEA_ID). Folk letto da
# GameSettings.active_human_folk, come HaulZoneService.is_food_only_limit_active.
# Sblocco della caccia nelle zone (2026-10-05: dal controllo unico dei lavori, WorkAreaTypes.is_job_unlocked — stessa
# idea work_areas_advanced di prima).
static func is_hunt_job_unlocked() -> bool:
	return WorkAreaTypes.is_job_unlocked(HUNT_JOB)


# true se la zona caccia questa specie: idea completata, caccia abilitata e filtro della zona ("all" o specie spuntata).
static func work_area_accepts_species(area: WorkArea, species: String) -> bool:
	if area == null or not is_hunt_job_unlocked() or not area.enabled_jobs.has(HUNT_JOB):
		return false
	var filters: Variant = area.filters.get(HUNT_JOB, null)
	if not (filters is Dictionary):
		filters = WorkAreaTypes.get_default_filters(HUNT_JOB)
	if bool(filters.get("all", true)):
		return true
	return (filters.get("species", []) as Array).has(species)


# true se esiste almeno una zona con la caccia attiva (bottone Caccia del pannello comandi).
static func has_hunt_work_area(game_data: GameData) -> bool:
	if game_data == null or not is_hunt_job_unlocked():
		return false
	for area in game_data.work_areas:
		if area.enabled_jobs.has(HUNT_JOB):
			return true
	return false


# Prede vive dentro la zona e ammesse dal filtro, senza controllo di visibilità: individui dei renderer della macrocella
# della zona (viva) con salute > 0 e microcella dentro il rettangolo. Array[AnimalVisualGroup].
static func list_prey_in_area(area: WorkArea, live_cells: Dictionary) -> Array:
	var prey: Array = []
	if area == null:
		return prey
	var cell: LiveMacroCell = live_cells.get(area.macro_coords)
	if cell == null:
		return prey
	for species in cell.animal_renderers:
		if not work_area_accepts_species(area, String(species)):
			continue
		var renderer: AnimalGroupRenderer = cell.animal_renderers[species]
		if not is_instance_valid(renderer):
			continue
		for animal in renderer.get_individuals():
			if animal.health <= 0.0:
				continue
			var microcell := Vector2i(floori(animal.position.x), floori(animal.position.y))
			if area.contains(area.macro_coords, microcell):
				prey.append(animal)
	return prey


# Prede della zona (list_prey_in_area) entro il raggio di vista del cacciatore stesso.
static func find_sighted_prey(area: WorkArea, hunter: HumanIndividual, live_cells: Dictionary) -> Array:
	var sighted: Array = []
	if hunter == null:
		return sighted
	var radius := get_hunter_visibility_radius(hunter, live_cells, area.macro_coords if area != null else hunter.home_macro_coords)
	var radius_sq := radius * radius
	for animal in list_prey_in_area(area, live_cells):
		if hunter.position.distance_squared_to(ApproachPreyAction.prey_position_for(hunter, animal)) <= radius_sq:
			sighted.append(animal)
	return sighted


# Preda da puntare: tra le avvistate, la più vicina non già puntata da un altro cacciatore della stessa zona (Task di
# caccia in corso con CONTEXT_WORK_AREA_ID == area.id). null se nessuna.
static func choose_prey(area: WorkArea, hunter: HumanIndividual, live_cells: Dictionary) -> AnimalVisualGroup:
	if area == null or hunter == null:
		return null
	var targeted: Dictionary = {}
	for other in GameSettings.active_human_individuals:
		if other == hunter or not HuntService.is_hunt_task(other.current_task) or other.current_task.is_finished():
			continue
		var context: Dictionary = other.current_task.context
		if int(context.get(CONTEXT_WORK_AREA_ID, -1)) == area.id:
			targeted[int(context.get(CONTEXT_PREY_ID, -1))] = true
	var best: AnimalVisualGroup = null
	var best_distance_sq := INF
	for animal in find_sighted_prey(area, hunter, live_cells):
		if targeted.has(animal.id):
			continue
		var distance_sq := hunter.position.distance_squared_to(ApproachPreyAction.prey_position_for(hunter, animal))
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = animal
	return best


# Raggio di vista del cacciatore: lo stesso FogOfWarRenderer.visibility_radius con cui la nebbia rivela le celle attorno
# a ogni pipottino, letto dal renderer della macrocella `macro_coords` (o di quella del cacciatore) se viva.
static func get_hunter_visibility_radius(hunter: HumanIndividual, live_cells: Dictionary, macro_coords: Vector2i) -> float:
	for coords in [macro_coords, hunter.home_macro_coords]:
		var cell: LiveMacroCell = live_cells.get(coords)
		if cell != null and cell.fog_of_war_renderer != null:
			return cell.fog_of_war_renderer.visibility_radius
	return FALLBACK_VISIBILITY_RADIUS


# Requisito della caccia in zona: un attrezzo BUTCHERING in cintura (il coltello, che vale anche come arma da caccia),
# così la preda si può macellare sul posto senza tornare a prenderlo. "" se va bene, altrimenti il messaggio di rifiuto
# già tradotto. La caccia diretta non lo richiede (resta il gate HUNTING di sempre, ToolGateService).
static func get_hunt_rejection(hunter: HumanIndividual) -> String:
	if hunter == null:
		return ""
	if ToolGateService.find_belt_slot_for(hunter, TaskTypes.ToolCategory.BUTCHERING) == -1:
		return TranslationServer.translate("work_area_hunt_needs_knife").format({"name": hunter.name})
	return ""


# --- Passo 2b (2026-10-01): serie fino a un limite di carne ---

# `butcher_destination` (2026-10-03): destinazione dei prodotti della macellazione scelta nel dialog
# (ButcherDestinationService), copiata nel context di ogni caccia della serie (GameScene._build_hunt_zone_task).
static func make_meat_series(area_id: int, target: int, butcher_destination: String = "") -> Dictionary:
	var series := {"work_area_id": area_id, "target": target, "delivered": 0}
	if butcher_destination != "":
		series["butcher_destination"] = butcher_destination
	return series


# Serie del context ({} se la Task non ne fa parte).
static func get_meat_series(context: Dictionary) -> Dictionary:
	var series: Variant = context.get(CONTEXT_MEAT_SERIES, {})
	return series if series is Dictionary else {}


# Carne appena consegnata da uno scarico (UnloadAction) di una Task della serie.
static func add_delivered_meat(context: Dictionary, quantity: int) -> void:
	var series := get_meat_series(context)
	if series.is_empty() or quantity <= 0:
		return
	series["delivered"] = int(series.get("delivered", 0)) + quantity
	context[CONTEXT_MEAT_SERIES] = series


static func is_meat_series_complete(series: Dictionary) -> bool:
	return int(series.get("delivered", 0)) >= int(series.get("target", MEAT_TARGET_DEFAULT))


# --- Passo 2a (2026-10-01): Task di caccia in zona ---

static func is_zone_hunt_task(task: Task) -> bool:
	return task != null and task.task_name == TASK_NAME


# Zone con la caccia attiva (ordine di GameData.work_areas). Vuoto senza l'idea.
static func list_hunt_work_areas(game_data: GameData) -> Array[WorkArea]:
	var areas: Array[WorkArea] = []
	if game_data == null or not is_hunt_job_unlocked():
		return areas
	for area in game_data.work_areas:
		if area.enabled_jobs.has(HUNT_JOB):
			areas.append(area)
	return areas


# Scelta automatica della zona di caccia per `hunter`: la più vicina, penalizzata per ogni altro cacciatore che caccia
# già lì. null se nessuna zona con la caccia attiva.
static func choose_work_area(game_data: GameData, hunter: HumanIndividual) -> WorkArea:
	if hunter == null:
		return null
	var best: WorkArea = null
	var best_score := -1.0
	for area in list_hunt_work_areas(game_data):
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + Vector2(area.macro_coords - hunter.home_macro_coords) * World.WIDTH
		var score := 1.0 / (hunter.position.distance_to(center) + ZONE_DISTANCE_OFFSET)
		for other in GameSettings.active_human_individuals:
			if other != hunter and is_zone_hunt_task(other.current_task) and int(other.current_task.context.get(CONTEXT_WORK_AREA_ID, -1)) == area.id:
				score *= ZONE_CROWDING_FACTOR
		if score > best_score:
			best_score = score
			best = area
	return best


# WorkArea della Task di caccia in zona (null se eliminata o se la Task non lo è).
static func resolve_task_area(task: Task) -> WorkArea:
	if not is_zone_hunt_task(task):
		return null
	return WorkAreaService.find_by_id(GameSettings.active_game_data, int(task.context.get(CONTEXT_WORK_AREA_ID, -1)))


static func write_prey_context(context: Dictionary, prey: AnimalVisualGroup) -> void:
	context[CONTEXT_PREY_ID] = prey.id
	context[CONTEXT_PREY_SPECIES] = prey.species_name
	context[CONTEXT_PREY_MACRO_X] = prey.macro_coords.x
	context[CONTEXT_PREY_MACRO_Y] = prey.macro_coords.y


# Dimentica la preda e lo stato dell'inseguimento (si torna alla pattuglia). Il punto di caduta dell'arma
# (HuntService.CONTEXT_WEAPON_DROP) resta: lo usa un recupero ancora in corso.
static func clear_prey_context(context: Dictionary) -> void:
	for key in [
		CONTEXT_PREY_ID, CONTEXT_PREY_SPECIES, CONTEXT_PREY_MACRO_X, CONTEXT_PREY_MACRO_Y, CONTEXT_PENDING_PREY,
		HuntService.CONTEXT_REAPPROACH_COUNT, HuntService.CONTEXT_PENDING_REAPPROACH, HuntService.CONTEXT_HUNT_WEAPON,
	]:
		context.erase(key)


# Step di caccia di sempre sulla preda del context: [ApproachPrey, Aim, Throw] con le loro descrizioni.
static func build_chase_steps(context: Dictionary) -> Array[Action]:
	var prey_id := int(context.get(CONTEXT_PREY_ID, 0))
	var species := String(context.get(CONTEXT_PREY_SPECIES, ""))
	var macro := Vector2i(int(context.get(CONTEXT_PREY_MACRO_X, 0)), int(context.get(CONTEXT_PREY_MACRO_Y, 0)))
	var combat_target := CombatTarget.for_animal(prey_id, species, macro)
	return HuntService.build_reapproach_steps(combat_target, true)


const CHASE_STEP_DESCRIPTIONS: Array[String] = ["task_hunt_step_approach", "task_hunt_step_aim", "task_hunt_step_throw"]


# Sospensione (bisogno, ordine del giocatore — TaskQueueService.push_suspended_task): una caccia in zona interrotta
# durante l'inseguimento perde la preda e alla ripresa riparte dalla pattuglia. Gli step dal corrente in poi vengono
# sostituiti da una PatrolAreaAction nuova. Eccezione: un recupero dell'arma in corso resta (l'arma è a terra) —
# con la preda uccisa resta com'è (poi la macellazione, l'uscita è conclusa); altrimenti punta un bersaglio vuoto,
# così al termine non insegue più e la Task torna alla pattuglia (HumanIndividualActionService).
static func reset_to_patrol_on_suspend(task: Task) -> void:
	if not is_zone_hunt_task(task) or task.is_finished():
		return
	var current := task.get_current_action()
	if current is PatrolAreaAction:
		return
	var area_id := int(task.context.get(CONTEXT_WORK_AREA_ID, -1))
	clear_prey_context(task.context)
	if current is RecoverWeaponAction:
		var recover := current as RecoverWeaponAction
		task.remove_steps(task.current_step_index + 1, task.steps.size())
		if recover.prey_killed:
			return
		task.remove_steps(task.current_step_index, 1)
		var detached: Array[Action] = [RecoverWeaponAction.new(recover.weapon_name, recover.weapon_uses, CombatTarget.new(), false)]
		var detached_descriptions: Array[String] = ["task_hunt_step_recover_weapon"]
		task.insert_steps_before_current(detached, detached_descriptions)
		var patrol_after: Array[Action] = [PatrolAreaAction.new(area_id)]
		task.append_steps(patrol_after)
		task.step_descriptions[task.step_descriptions.size() - 1] = "task_hunt_zone_step_patrol"
		return
	task.remove_steps(task.current_step_index, task.steps.size())
	var patrol: Array[Action] = [PatrolAreaAction.new(area_id)]
	task.append_steps(patrol)
	task.step_descriptions[task.step_descriptions.size() - 1] = "task_hunt_zone_step_patrol"
