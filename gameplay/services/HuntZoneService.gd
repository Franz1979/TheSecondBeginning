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
# Prede lasciate dopo HuntService.MAX_MISSED_THROWS_PER_PREY tiri a vuoto (2026-10-10): Array di id nel context
# dell'uscita (salvato con la Task, non passa alla caccia successiva della serie), saltate da choose_prey.
const CONTEXT_IGNORED_PREY_IDS := "hunt_zone_ignored_prey_ids"
# Richiesta di PatrolAreaAction: preda avvistata, inserire gli step di caccia (HumanIndividualActionService).
const CONTEXT_PENDING_PREY := "pending_hunt_zone_prey"
# Giorni di gioco dell'uscita senza catture (2026-10-10, contro il loop della preda visibile ma imprendibile — prima:
# giorni di pattuglia dentro la zona senza avvistamenti, azzerati a ogni avvistamento). Conta tutto il tempo in cui la
# Task è quella corrente (pattuglia, tragitto, avvicinamento, mira, tiri, recuperi: HumanIndividualActionService.
# apply_action), non il tempo dei bisogni (Task in coda); lo azzera solo un'uccisione (ThrowAction). Raggiunto
# PatrolAreaAction.PATROL_DAYS_WITHOUT_PREY_LIMIT l'uscita finisce come "nessuna preda" (CONTEXT_NO_PREY). Stessa chiave
# di prima: i salvataggi la leggono così com'è.
const CONTEXT_UNSIGHTED_DAYS := "hunt_zone_unsighted_days"
# Il contatore qui sopra parte (2026-10-10) solo quando il cacciatore arriva nella zona durante la pattuglia (o avvista
# una preda, se la vede prima di entrarci): il tragitto verso la zona non conta. Da lì conta tutto, anche fuori zona.
const CONTEXT_CAPTURE_CLOCK_STARTED := "hunt_zone_capture_clock_started"
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
# Uscita della caccia in zona finita senza prede (PatrolAreaAction.PATROL_DAYS_WITHOUT_PREY_LIMIT giorni) (2026-10-09, PatrolAreaAction): letto alla chiusura della
# Task per avvisare chi segue la serie (HumanIndividualActionService.hunt_zone_series_ended, ordini del cassetto).
const CONTEXT_NO_PREY := "hunt_zone_no_prey"
# Motivi di hunt_zone_series_ended.
const SERIES_END_COMPLETE := "complete"
const SERIES_END_NO_PREY := "no_prey"
# Zona automatica (2026-10-09): la serie nata con la zona scelta in automatico (comando con l'interruttore acceso, ordine
# del cassetto senza zona fissata) può cambiare zona dopo un'uscita a vuoto (HuntOrderService._try_switch_zone). Zone già
# provate a vuoto in questo giro (Array di id, salvato con la serie): ognuna al massimo una volta; si azzera alla cattura
# di una preda (la serie passa alla macellazione senza) e quando l'ordine torna in coda (la serie nuova nasce senza).
const SERIES_AUTO_ZONE_KEY := "auto_zone"
const SERIES_TRIED_ZONES_KEY := "tried_zone_ids"
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
		# Non tipizzata: subito dopo un caricamento il dizionario può ancora avere un renderer già liberato, e assegnarlo a
		# una variabile tipizzata dà errore prima del controllo.
		var renderer = cell.animal_renderers[species]
		if not is_instance_valid(renderer):
			continue
		for animal in renderer.get_individuals():
			if animal.health <= 0.0:
				continue
			var microcell := Vector2i(floori(animal.position.x), floori(animal.position.y))
			if area.contains(area.macro_coords, microcell):
				prey.append(animal)
	return prey


# Prede della zona (list_prey_in_area) entro il raggio di vista del cacciatore stesso, o entro il fiuto del cane che lo
# accompagna (2026-11-07, caccia col cane passo 2: DomesticAnimalHuntService.scenting_animal_for, hunt_scent_radius; il
# cane sta nella macrocella del cacciatore, quindi stesse coordinate).
static func find_sighted_prey(area: WorkArea, hunter: HumanIndividual, live_cells: Dictionary) -> Array:
	var sighted: Array = []
	if hunter == null:
		return sighted
	var radius := get_hunter_visibility_radius(hunter, live_cells, area.macro_coords if area != null else hunter.home_macro_coords)
	var radius_sq := radius * radius
	var dog := DomesticAnimalHuntService.scenting_animal_for(hunter)
	var scent_sq := 0.0
	if dog != null:
		var scent := DomesticAnimalCalculator.get_rules(dog.species).hunt_scent_radius
		scent_sq = scent * scent
	for animal in list_prey_in_area(area, live_cells):
		var prey_position := ApproachPreyAction.prey_position_for(hunter, animal)
		if hunter.position.distance_squared_to(prey_position) <= radius_sq \
				or (dog != null and dog.position.distance_squared_to(prey_position) <= scent_sq):
			sighted.append(animal)
	return sighted


# --- Caccia di gruppo (2026-11-11, richiesta utente — passo 1: zona e prede) ---
# Preda grossa = AnimalRules.max_hunters > 1: la cacciano fino a max_hunters persone insieme; le piccole (coniglio,
# pernice) una sola, come prima. Nessun raduno né attesa: la cooperazione nasce da come si scelgono zona e preda.

static func max_hunters_for(species: String) -> int:
	var rules := AnimalCalculator.get_animal_rules(species)
	return maxi(rules.max_hunters, 1) if rules != null else 1


static func is_big_prey(species: String) -> bool:
	return max_hunters_for(species) > 1


# Cacciatori che inseguono ora ogni preda (Task di caccia corrente, diretta o in zona, con CONTEXT_PREY_ID), escluso
# `except`: {id preda -> numero}.
static func hunters_per_prey(except: HumanIndividual = null) -> Dictionary:
	var counts: Dictionary = {}
	for other in GameSettings.active_human_individuals:
		if other == except or not HuntService.is_hunt_task(other.current_task) or other.current_task.is_finished():
			continue
		var prey_id := int(other.current_task.context.get(CONTEXT_PREY_ID, -1))
		if prey_id >= 0:
			counts[prey_id] = int(counts.get(prey_id, 0)) + 1
	return counts


# Chi sta cacciando la preda `prey_id` (Task di caccia in corso con quella preda puntata), tranne `except`: id degli
# individui. Caccia di gruppo (2026-11-11): all'uccisione sono i compagni che aiutano a portare la carne.
static func hunter_ids_on_prey(prey_id: int, except: HumanIndividual = null) -> Array[int]:
	var ids: Array[int] = []
	for other in GameSettings.active_human_individuals:
		if other == except or not HuntService.is_hunt_task(other.current_task) or other.current_task.is_finished():
			continue
		if int(other.current_task.context.get(CONTEXT_PREY_ID, -1)) == prey_id:
			ids.append(other.id)
	return ids


# Posti ancora liberi sulla preda `animal` con `count` cacciatori già sopra.
static func _has_free_slot(animal: AnimalVisualGroup, count: int) -> bool:
	return count < max_hunters_for(animal.species_name)


# Altri cacciatori della zona `area`, già lì o in arrivo (Task di caccia in zona corrente o in coda, per esempio
# mentre prendono l'arma in deposito).
static func _has_zone_companions(area: WorkArea, hunter: HumanIndividual) -> bool:
	for other in GameSettings.active_human_individuals:
		if other == hunter:
			continue
		for task in JobWorkScanService.open_tasks(other):
			if is_zone_hunt_task(task) and int(task.context.get(CONTEXT_WORK_AREA_ID, -1)) == area.id:
				return true
	return false


# Salute massima di `animal` per la sua fascia d'età (AnimalRules.max_health × size_multiplier_by_age).
static func max_health_of(animal: AnimalVisualGroup) -> float:
	var rules := AnimalCalculator.get_animal_rules(animal.species_name)
	if rules == null:
		return 0.0
	var age_scale := 1.0
	if animal.age_band >= 0 and animal.age_band < rules.size_multiplier_by_age.size():
		age_scale = float(rules.size_multiplier_by_age[animal.age_band])
	return rules.max_health * age_scale


# Preda da puntare tra le avvistate e non lasciate in questa uscita (`ignored_ids`, CONTEXT_IGNORED_PREY_IDS), con un
# posto libero (piccola: nessun altro cacciatore sopra; grossa: meno di max_hunters). Per livelli (2026-11-11):
#   1. preda grossa già cacciata da un compagno o già ferita (2026-11-11: anche se chi l'ha ferita ha chiuso la caccia,
#      per esempio senza più armi) — la più ferita, a pari ferita la più vicina ("vado ad aiutare" / "la finisco");
#   2. preda grossa libera, se nella zona ci sono altri cacciatori (o in arrivo) oppure se le armi di `hunter` bastano a
#      ucciderla da solo (HuntService.damage_budget >= salute attuale) — la più vicina;
#   3. tutte le altre (piccole, e grosse che da solo non riuscirebbe ad abbattere) — la più vicina, come prima.
# Richiamo (2026-11-11, passo 2 — HuntCallService): la preda di un fischio sentito in pattuglia è candidata anche se non
# si vede e anche fuori dalla zona; puntata, il richiamo è consumato.
# null se nessuna.
static func choose_prey(area: WorkArea, hunter: HumanIndividual, live_cells: Dictionary, ignored_ids: Array[int] = []) -> AnimalVisualGroup:
	if area == null or hunter == null:
		return null
	var counts := hunters_per_prey(hunter)
	var companions := _has_zone_companions(area, hunter)
	var budget := HuntService.damage_budget(hunter)
	var best: AnimalVisualGroup = null
	var best_tier := 99
	var best_health_ratio := INF
	var best_distance_sq := INF
	var candidates := find_sighted_prey(area, hunter, live_cells)
	var heard := HuntCallService.heard_prey_for(hunter)
	if heard != null and not candidates.has(heard):
		candidates.append(heard)
	for animal in candidates:
		if ignored_ids.has(animal.id):
			continue
		var count := int(counts.get(animal.id, 0))
		if not _has_free_slot(animal, count):
			continue
		var big := is_big_prey(animal.species_name)
		var tier := 3
		var health_ratio := 1.0
		var max_health := max_health_of(animal)
		var wounded: bool = max_health > 0.0 and animal.health < max_health - 0.001
		if big and (count > 0 or wounded):
			tier = 1
			health_ratio = animal.health / max_health if max_health > 0.0 else 1.0
		elif big and (companions or budget >= animal.health):
			tier = 2
		var distance_sq := hunter.position.distance_squared_to(ApproachPreyAction.prey_position_for(hunter, animal))
		var better := tier < best_tier
		if tier == best_tier:
			if tier == 1 and not is_equal_approx(health_ratio, best_health_ratio):
				better = health_ratio < best_health_ratio
			else:
				better = distance_sq < best_distance_sq
		if better:
			best = animal
			best_tier = tier
			best_health_ratio = health_ratio
			best_distance_sq = distance_sq
	if best != null and best == heard:
		HuntCallService.forget(hunter)
		HuntService.log_event(hunter, "scelta della preda: %s #%d — ha sentito il fischio di un compagno." % [best.species_name, best.id])
	elif best != null:
		var reasons := {1: ("preda grossa già cacciata da %d compagni" % int(counts.get(best.id, 0))) if int(counts.get(best.id, 0)) > 0
				else "preda grossa già ferita (salute %.1f), nessuno la insegue" % best.health,
			2: "preda grossa libera (%s)" % ("compagni nella zona" if companions else "armi %.0f >= salute %.1f" % [budget, best.health]),
			3: "la più vicina"}
		HuntService.log_event(hunter, "scelta della preda in %s: %s #%d — %s." % [area.name, best.species_name, best.id, reasons[best_tier]])
	# Fuori dalla vista del cacciatore: l'ha trovata il fiuto del cane (passo 2).
	if best != null:
		var radius := get_hunter_visibility_radius(hunter, live_cells, area.macro_coords)
		if best_distance_sq > radius * radius:
			var dog := DomesticAnimalHuntService.scenting_animal_for(hunter)
			DomesticAnimalHuntService.log_line("[DOMESTIC HUNT] %s #%d fiuta %s a %.1f microcelle da #%d %s (vista %.1f)" % [
				dog.species if dog != null else "?", dog.id if dog != null else -1, best.species_name,
				sqrt(best_distance_sq), hunter.id, hunter.name, radius])
	return best


# Raggio di vista del cacciatore: lo stesso FogOfWarRenderer.visibility_radius con cui la nebbia rivela le celle attorno
# a ogni pipottino, letto dal renderer della macrocella `macro_coords` (o di quella del cacciatore) se viva.
static func get_hunter_visibility_radius(hunter: HumanIndividual, live_cells: Dictionary, macro_coords: Vector2i) -> float:
	for coords in [macro_coords, hunter.home_macro_coords]:
		var cell: LiveMacroCell = live_cells.get(coords)
		if cell != null and cell.fog_of_war_renderer != null:
			return cell.fog_of_war_renderer.visibility_radius
	return FALLBACK_VISIBILITY_RADIUS


# Requisito della caccia in zona: un attrezzo BUTCHERING (il coltello), così la preda si può macellare sul posto senza
# tornare a prenderlo, e dal 2026-10-11 un'arma da caccia (HUNTING, HuntService.has_hunting_weapon_available: in cintura,
# o nello zaino con le munizioni se servono): il coltello non è più un'arma da caccia. Dal 2026-10-09 la regola generale
# degli attrezzi (ToolGateService): in cintura va bene; nello zaino va bene se la cintura ha posto (lo sposta in cintura chi
# assegna la caccia, GameScene._prepare_hunt_knife); nello zaino con la cintura piena, o da nessuna parte, no. Sola
# lettura: "" se va bene, altrimenti il messaggio di rifiuto già tradotto.
static func get_hunt_rejection(hunter: HumanIndividual) -> String:
	if hunter == null:
		return ""
	if not HuntService.has_hunting_weapon_available(hunter):
		return TranslationServer.translate("work_area_hunt_needs_weapon").format({"name": hunter.name})
	if ToolGateService.find_belt_slot_for(hunter, TaskTypes.ToolCategory.BUTCHERING) != -1:
		return ""
	var backpack_knife := ToolGateService._find_backpack_tool_for(hunter, TaskTypes.ToolCategory.BUTCHERING, [])
	if backpack_knife == "":
		return TranslationServer.translate("work_area_hunt_needs_knife").format({"name": hunter.name})
	if hunter.equipped_tool_count >= hunter.get_tool_slot_count():
		return TranslationServer.translate("tool_gate_belt_full").format({
			"name": hunter.name, "tool": IconRegistry.get_resource_display_name(backpack_knife),
		})
	return ""


# --- Passo 2b (2026-10-01): serie fino a un limite di carne ---

# `butcher_destination` (2026-10-03): destinazione dei prodotti della macellazione scelta nel dialog
# (ButcherDestinationService), copiata nel context di ogni caccia della serie (TaskBuilderService.build_hunt_zone_task).
# `auto_zone` (2026-10-09): zona scelta in automatico, la serie può cambiare zona (SERIES_AUTO_ZONE_KEY).
static func make_meat_series(area_id: int, target: int, butcher_destination: String = "", auto_zone: bool = false) -> Dictionary:
	var series := {"work_area_id": area_id, "target": target, "delivered": 0}
	if butcher_destination != "":
		series["butcher_destination"] = butcher_destination
	if auto_zone:
		series[SERIES_AUTO_ZONE_KEY] = true
	return series


# Zone già provate a vuoto della serie, come interi (il context passa da JSON: gli id tornano float).
static func get_tried_zone_ids(series: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	var raw: Variant = series.get(SERIES_TRIED_ZONES_KEY, [])
	if raw is Array:
		for value in raw:
			ids.append(int(value))
	return ids


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


# Giorni senza catture dell'uscita (CONTEXT_UNSIGHTED_DAYS, vedi sopra).
static func get_days_without_capture(context: Dictionary) -> float:
	return float(context.get(CONTEXT_UNSIGHTED_DAYS, 0.0))


# Avvio del contatore (CONTEXT_CAPTURE_CLOCK_STARTED). Un contatore già sopra zero (salvataggi precedenti) vale avviato.
static func start_capture_clock(context: Dictionary) -> void:
	context[CONTEXT_CAPTURE_CLOCK_STARTED] = true


static func is_capture_clock_started(context: Dictionary) -> bool:
	return bool(context.get(CONTEXT_CAPTURE_CLOCK_STARTED, false)) or get_days_without_capture(context) > 0.0


static func add_days_without_capture(context: Dictionary, delta: float) -> float:
	var days := get_days_without_capture(context) + delta
	context[CONTEXT_UNSIGHTED_DAYS] = days
	return days


static func is_no_capture_limit_reached(context: Dictionary) -> bool:
	return get_days_without_capture(context) >= PatrolAreaAction.PATROL_DAYS_WITHOUT_PREY_LIMIT


# Riga di log della fine dell'uscita per il limite senza catture (pattuglia o inseguimento).
static func log_no_capture_end(individual: Variant, context: Dictionary, during: String) -> void:
	log_event(individual, "uscita finita: %.2f giorni senza catture (limite %.1f), durante %s." % [
		get_days_without_capture(context), PatrolAreaAction.PATROL_DAYS_WITHOUT_PREY_LIMIT, during
	])


# Zone con la caccia attiva (ordine di GameData.work_areas). Vuoto senza l'idea.
static func list_hunt_work_areas(game_data: GameData) -> Array[WorkArea]:
	var areas: Array[WorkArea] = []
	if game_data == null or not is_hunt_job_unlocked():
		return areas
	for area in game_data.work_areas:
		if area.enabled_jobs.has(HUNT_JOB):
			areas.append(area)
	return areas


# Scelta automatica della zona di caccia per `hunter` (2026-10-09, rivista): prima le prede — la zona con più prede
# ammesse dal suo filtro presenti adesso (list_prey_in_area, solo macrocelle attive in `live_cells`), penalizzate per
# ogni altro cacciatore che caccia già lì (ZONE_CROWDING_FACTOR); la distanza (1 / (distanza + ZONE_DISTANCE_OFFSET),
# con la stessa penalità) decide solo a parità. Se nessuna zona ha prede: come prima, la più vicina con la penalità.
# `excluded_ids`: zone da non considerare (già provate a vuoto); `require_prey`: null se nessuna zona ha prede.
# null se nessuna zona con la caccia attiva.
static func choose_work_area(
	game_data: GameData, hunter: HumanIndividual, live_cells: Dictionary = {}, excluded_ids: Array[int] = [],
	require_prey: bool = false
) -> WorkArea:
	if hunter == null:
		return null
	var join := _zone_to_join(game_data, live_cells, hunter.home_macro_coords, hunter.position, excluded_ids, hunter)
	if join != null:
		HuntService.log_event(hunter, "zona scelta: %s — un compagno caccia lì una preda grossa con posti liberi." % join.name)
		return join
	var best: WorkArea = null
	var best_prey := -1.0
	var best_distance_score := -1.0
	for area in list_hunt_work_areas(game_data):
		if excluded_ids.has(area.id):
			continue
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + Vector2(area.macro_coords - hunter.home_macro_coords) * World.WIDTH
		var crowding := _zone_crowding(area, hunter)
		var prey_count := list_prey_in_area(area, live_cells).size()
		if require_prey and prey_count == 0:
			continue
		var prey_score := float(prey_count) * crowding
		var distance_score := crowding / (hunter.position.distance_to(center) + ZONE_DISTANCE_OFFSET)
		if prey_score > best_prey + 0.000001 or (absf(prey_score - best_prey) <= 0.000001 and distance_score > best_distance_score):
			best_prey = prey_score
			best_distance_score = distance_score
			best = area
	return best


# Zona di caccia scelta dall'ordine del cassetto (2026-10-24, assegnatore fase 3 — DrawerOrderTargetService): come
# choose_work_area ma da un punto (`origin_macro`/`origin_pos`, il punto di assegnazione) invece che dal cacciatore,
# così le prede di ogni zona si contano una volta per ordine e non per ogni pipottino che arriva al punto.
static func choose_work_area_from(game_data: GameData, live_cells: Dictionary, origin_macro: Vector2i, origin_pos: Vector2) -> WorkArea:
	var join := _zone_to_join(game_data, live_cells, origin_macro, origin_pos, [], null)
	if join != null:
		HuntService.log_event(null, "zona dell'ordine: %s — un cacciatore caccia lì una preda grossa con posti liberi." % join.name)
		return join
	var best: WorkArea = null
	var best_prey := -1.0
	var best_distance_score := -1.0
	for area in list_hunt_work_areas(game_data):
		if not live_cells.has(area.macro_coords):
			continue
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + Vector2(area.macro_coords - origin_macro) * World.WIDTH
		var crowding := _zone_crowding(area, null)
		var prey_score := float(list_prey_in_area(area, live_cells).size()) * crowding
		var distance_score := crowding / (origin_pos.distance_to(center) + ZONE_DISTANCE_OFFSET)
		if prey_score > best_prey + 0.000001 or (absf(prey_score - best_prey) <= 0.000001 and distance_score > best_distance_score):
			best_prey = prey_score
			best_distance_score = distance_score
			best = area
	return best


# Zona da raggiungere per aiutare (2026-11-11, caccia di gruppo passo 1): fra le zone di caccia con la macrocella viva
# (non in `excluded_ids`), quelle con dentro una preda grossa ammessa dal filtro che qualcuno sta già cacciando e con
# posti liberi; la più vicina a `origin_pos` (locale a `origin_macro`). null se nessuna. `except`: chi sceglie, non conta
# tra i cacciatori.
static func _zone_to_join(game_data: GameData, live_cells: Dictionary, origin_macro: Vector2i, origin_pos: Vector2,
		excluded_ids: Array[int], except: HumanIndividual) -> WorkArea:
	var counts := hunters_per_prey(except)
	if counts.is_empty():
		return null
	var best: WorkArea = null
	var best_distance := INF
	for area in list_hunt_work_areas(game_data):
		if excluded_ids.has(area.id) or not live_cells.has(area.macro_coords):
			continue
		var wanted := false
		for animal in list_prey_in_area(area, live_cells):
			var count := int(counts.get(animal.id, 0))
			if count > 0 and is_big_prey(animal.species_name) and _has_free_slot(animal, count):
				wanted = true
				break
		if not wanted:
			continue
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + Vector2(area.macro_coords - origin_macro) * World.WIDTH
		var distance := origin_pos.distance_to(center)
		if distance < best_distance:
			best_distance = distance
			best = area
	return best


# Penalità di affollamento della zona: ZONE_CROWDING_FACTOR per ogni altro cacciatore lì (Task di caccia in zona
# corrente), tranne chi insegue una preda grossa (2026-11-11: non allontana gli altri, li chiama).
static func _zone_crowding(area: WorkArea, except: HumanIndividual) -> float:
	var crowding := 1.0
	for other in GameSettings.active_human_individuals:
		if other == except or not is_zone_hunt_task(other.current_task):
			continue
		var context: Dictionary = other.current_task.context
		if int(context.get(CONTEXT_WORK_AREA_ID, -1)) != area.id:
			continue
		if int(context.get(CONTEXT_PREY_ID, -1)) >= 0 and is_big_prey(String(context.get(CONTEXT_PREY_SPECIES, ""))):
			continue
		crowding *= ZONE_CROWDING_FACTOR
	return crowding


# WorkArea della Task di caccia in zona (null se eliminata o se la Task non lo è).
static func resolve_task_area(task: Task) -> WorkArea:
	if not is_zone_hunt_task(task):
		return null
	return WorkAreaService.find_by_id(GameSettings.active_game_data, int(task.context.get(CONTEXT_WORK_AREA_ID, -1)))


# Prede lasciate in questa uscita (CONTEXT_IGNORED_PREY_IDS), come interi (il context passa da JSON).
static func get_ignored_prey_ids(context: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	var raw: Variant = context.get(CONTEXT_IGNORED_PREY_IDS, [])
	if raw is Array:
		for value in raw:
			ids.append(int(value))
	return ids


static func ignore_prey(context: Dictionary, prey_id: int) -> void:
	var ids := get_ignored_prey_ids(context)
	if not ids.has(prey_id):
		ids.append(prey_id)
	context[CONTEXT_IGNORED_PREY_IDS] = ids


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
