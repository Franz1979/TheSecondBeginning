class_name IdleTaskAssignmentService
extends RefCounted

# Fallback "perditempo" per individui LIBERI (2026-09-13, richiesta utente) — quando nessuna Task è
# in corso, nessun bisogno stamina è attivo e la coda personale (task_queue) è vuota, invece di
# restare fermo senza current_task l'individuo riceve una Task scelta a caso tra quelle "per
# passare il tempo", filtrate per età. Service RefCounted stateless, stesso pattern di
# NeedTaskAssignmentService/TaskQueueService.
#
# SEPARATO da TaskQueueService (richiesta utente: "a tua scelta motivata") — TaskQueueService resta
# scoped alla sola meccanica della coda LIFO (push/pop, zero conoscenza di TaskDefinition/
# TaskFactory/risoluzione target), stessa separazione di responsabilità già stabilita tra
# NeedTaskAssignmentService (risoluzione/costruzione/assegnazione delle Task-bisogno) e
# TaskQueueService stesso — un servizio, una responsabilità, mai mescolare "gestione coda" con
# "scelta/costruzione di una Task".
#
# resolve_wander_targets/resolve_play_targets ESTRATTE da GameScene._resolve_wander_targets/
# _resolve_play_targets (spostate qui TALI E QUALI, nessun cambio di comportamento) — i trigger
# manuali tasti G/P (GameScene._assign_wander_task/_assign_play_task) ora le richiamano da qui
# invece di tenerne una copia propria, stesso principio già applicato a Rest/Emergency Rest tramite
# NeedTaskAssignmentService: una sola formula, riusata sia dal comando manuale sia da questo
# fallback automatico, mai due copie indipendenti a rischio di disallinearsi in futuro.

# Rito spontaneo (2026-10-02, richiesta utente): stessi step della task rite (Walk → Rite), escluso a monte se non
# esiste un edificio dove celebrarlo (RiteService.find_spontaneous_rite_target), stesso principio di daydreaming con
# l'edificio che accetta pensieri.
const LEISURE_RITE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/leisure_rite.tres"

# Elenco CENTRALIZZATO delle Task "perditempo" (2026-09-13, richiesta utente) — pensato per
# crescere in futuro (nuove Task "per passare il tempo") senza toccare la logica di scelta in
# assign_idle_fallback sotto: aggiungere un path qui basta perché entri nel tiro a sorte, filtrato
# per età con lo stesso identico meccanismo delle altre due. L'UNICA parte che va comunque estesa
# per una nuova voce è _build_idle_task sotto (il "come si risolve il context di QUESTA specifica
# Task" resta necessariamente per-caso, non genericizzabile senza un'astrazione che oggi non serve
# per due sole voci — stesso principio "niente genericità prematura" già seguito ovunque in questo
# progetto, es. TaskFactory.build_task).
const EXPLORE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/explore.tres"
const IDLE_FALLBACK_TASK_PATHS: Array[String] = [
	"res://gameplay/scripts/tasks/definitions/wander.tres",
	EXPLORE_TASK_DEFINITION_PATH,
	"res://gameplay/scripts/tasks/definitions/play.tres",
	"res://gameplay/scripts/tasks/definitions/leisure_rest.tres",
	"res://gameplay/scripts/tasks/definitions/daydreaming.tres",
	"res://gameplay/scripts/tasks/definitions/leisure_restock.tres",
	LEISURE_RITE_TASK_DEFINITION_PATH,
]

# Guard di eleggibilita' di leisure_restock nel sorteggio idle (2026-09-19, richiesta utente): la Task e'
# eleggibile solo se lo spazio libero nelle provviste (food_space_capacity - food_space_used) e' almeno
# questa frazione della capacita' (0.4 = 40%). Con le provviste quasi piene il sorteggio la salta e ne
# pesca un'altra. Vale SOLO per il sorteggio idle: l'attivazione manuale (tasto F) resta senza
# condizioni.
const LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO: float = 0.4

# Range di durata (in giorni) della Rest per SVAGO (2026-09-16, richiesta utente) — RANDOM ad ogni
# assegnazione (a differenza del tetto FISSO di 8gg della Rest da bisogno, vedi
# NeedTaskAssignmentService.REST_TASK_MAX_DURATION_DAYS): qui non c'è un vero bisogno da soddisfare,
# solo un modo di passare il tempo, quindi una durata variabile è più naturale/meno meccanica di un
# singolo numero fisso ripetuto ad ogni occorrenza.
# Taratura 2026-09-26 (richiesta utente): da 4-8 a 2-5 giorni.
# Taratura 2026-09-27 (richiesta utente): da 2-5 a 1-3 giorni.
const LEISURE_REST_MIN_DURATION_DAYS: float = 1.0
const LEISURE_REST_MAX_DURATION_DAYS: float = 3.0

# RIATTIVATA (2026-09-16, richiesta utente) — era stata sospesa per il sintomo "i pipottini che
# ondulano fermi su se stessi"/"ondulando come quando camminano", causa poi isolata e corretta:
# GameScene._attempt_macro_cell_transition ribasava SOLO il target dello step ATTIVO al cambio di
# macrocella, lasciando le gambe FUTURE di Wander/Play/Leisure Rest nel vecchio sistema di
# riferimento (CAUSA A), e uno step bloccato al bordo (macrocella inesistente/acqua) restava
# incompleto per sempre, mai avanzato (CAUSA B) — vedi Task.rebase_positional_targets/
# HumanIndividualActionService.finish_current_step/GameScene._block_border_crossing, verificati da
# tools/border_crossing_test. Storico sospensioni precedenti (git blame per il dettaglio completo):
# prima disattivata per debug, poi il 2026-09-15, poi di nuovo il 2026-09-16 quando il sintomo era
# ricomparso subito dopo una prima riattivazione — sempre lo stesso bug, mai isolato fino ad ora.
#
# static var, non più const (2026-09-16, richiesta utente — infrastruttura per il test
# automatizzato tools/zombie_task_test/ZombieTaskTest.gd, fix "task zombie"): reso var SOLO perché
# quel test deve poterlo forzare temporaneamente, poi ripristinarlo. Nessun punto di produzione lo
# riassegna — il controllo runtime per disattivare il fallback perditempo SENZA toccare questo
# flag è ora `fallback_enabled` sotto (interruttore unico, sessione-only, bottone DebugBar).
static var WANDER_ENABLED := true

# RIATTIVATA insieme a WANDER_ENABLED sopra (2026-09-16, richiesta utente) — era stata sospesa SOLO
# per isolare meglio il problema di Wander (nessun sintomo proprio mai riscontrato su questa Task),
# stessa causa/stesso fix di sopra.
#
# static var, non più const — STESSO motivo/STESSO trattamento di WANDER_ENABLED sopra.
static var LEISURE_REST_ENABLED := true

# Interruttore GLOBALE di sessione per l'intero fallback perditempo (2026-09-16, richiesta utente)
# — DIVERSO da WANDER_ENABLED/LEISURE_REST_ENABLED sopra (che disattivano UNA task specifica,
# lasciando le altre candidate): questo spegne l'INTERO meccanismo (Wander/Play/Leisure Rest
# insieme), controllato da assign_idle_fallback sotto. Pensato per un pulsante di debug (DebugBar,
# vedi GameScene._on_debug_action_pressed), non per un bug da isolare — utile per confrontare
# rapidamente "con/senza perditempo" senza dover toccare i tre flag sopra uno per uno.
#
# Solo stato di SESSIONE (richiesta esplicita) — MAI salvato/letto da GameSettings o da un
# salvataggio: ad ogni avvio del gioco riparte SEMPRE acceso (true), indipendentemente da come è
# stato lasciato nella sessione precedente. Spegnimento: le task perditempo GIÀ in corso non
# vengono toccate (nessun controllo qui dentro apply_action/resolve_idle_individual, solo qui in
# assign_idle_fallback), finiscono normalmente per la loro strada; SOLO la prossima assegnazione
# viene bloccata. Riaccensione: nessun ripescaggio automatico degli individui nel frattempo finiti
# a current_task=null (via stop(), lo stesso ramo che scatterebbe comunque a flag acceso se nessun
# candidato fosse idoneo) — rientrano nel giro da soli alla prossima chiamata naturale di
# resolve_idle_individual (fine della loro prossima Task) o con un comando manuale (tasto H).
static var fallback_enabled := true


# Accende/spegne fallback_enabled sopra, con il log richiesto — unico punto che lo scrive (mai
# un'assegnazione diretta al campo altrove, cosi' il log non puo' disallinearsi dallo stato reale).
# Chiamata dal pulsante di debug in GameScene._on_debug_action_pressed.
static func set_fallback_enabled(enabled: bool) -> void:
	fallback_enabled = enabled
	if DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
		print("[IDLE FALLBACK] service %s." % ("attivato" if enabled else "disattivato"))

# Hook di connessione listener per lo step_appended di una Task Daydream (2026-09-16, richiesta
# utente, "Daydreaming nel fallback perditempo") — IdleTaskAssignmentService è uno stateless
# service senza riferimento alla scena (nessun Node): non può chiamare da sé
# GameScene._reconnect_unload_action_signals (side-effect UI: refresh griglia edifici, popup
# idea). GameScene si registra da sé in _ready() con questo Callable statico, stesso principio già
# seguito da fallback_enabled/set_fallback_enabled sopra ("GameScene configura lo stato del
# servizio dall'esterno, il servizio resta ignaro di chi lo consuma"). Callable() vuoto di default
# (contesti senza GameScene — tools/zombie_task_test, HumanBirthIndividualService — restano no-op
# sicuri via `.is_valid()` sotto: la Daydream funziona comunque, solo senza gli aggiornamenti UI
# collegati all'Unload del ramo pensiero). Chiamata da _build_idle_task sotto, subito dopo aver
# costruito la Task, PRIMA che assign_idle_fallback la assegni — stesso ordine (costruisci, collega
# listener, assegna) già seguito da GameScene._debug_test_daydream_task.
static var daydream_step_appended_connector: Callable = Callable()

# Lunghezza min/max (in microcelle) di ciascun tratto casuale di Wander/Play — STESSO valore/STESSO
# principio già in uso prima di questo spostamento (vedi GameScene.gd, ora rimosso da lì).
const WANDER_LEG_MIN_LENGTH: float = 4.0
const WANDER_LEG_MAX_LENGTH: float = 8.0
# Explore (2026-10-04, richiesta utente — il comportamento della vecchia Wander, con tratti più lunghi).
const EXPLORE_LEG_MIN_LENGTH: float = 5.0
const EXPLORE_LEG_MAX_LENGTH: float = 10.0
# Wander attorno all'àncora (2026-10-04): ogni tratto va verso un punto a questa distanza dall'àncora.
const WANDER_ANCHOR_MIN_DISTANCE: float = 4.0
const WANDER_ANCHOR_MAX_DISTANCE: float = 10.0
# Play attorno all'àncora (2026-10-04): ogni corsa va verso un punto entro questa distanza dall'àncora (minimo 1, per
# non sorteggiare l'àncora stessa).
const PLAY_ANCHOR_MIN_DISTANCE: float = 1.0
const PLAY_ANCHOR_MAX_DISTANCE: float = 8.0


# Àncora delle perditempo (2026-10-04, richiesta utente): il punto attorno a cui girano Wander e Play, nello spazio
# locale del pipottino (stessa traduzione cross-macrocella del rito spontaneo in _build_idle_task: microcella + 0,5 più
# lo scarto di macrocella × World.WIDTH). Ripiego, in ordine: casa del pipottino; centro del villaggio
# (VisitorService.find_village_center); magazzino completo più vecchio (built_year minimo, a parità id minimo); un
# edificio completo qualsiasi non MOVEMENT (id minimo). Nessun edificio: null.
static func resolve_anchor_position(individual: HumanIndividual, world: World) -> Variant:
	var anchor := _resolve_anchor_building(individual, world)
	if anchor == null:
		return null
	var macro_offset := Vector2(Vector2i(anchor.macro_x, anchor.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(float(anchor.micro_x) + 0.5, float(anchor.micro_y) + 0.5) + macro_offset


static func _resolve_anchor_building(individual: HumanIndividual, world: World) -> Building:
	if world == null:
		return null
	if individual.house_id != -1:
		for building in world.buildings:
			if building.id == individual.house_id and not building.is_demolished:
				return building
	var village_center := VisitorService.find_village_center(world)
	if village_center != null:
		return village_center
	var oldest_storage: Building = null
	var any_building: Building = null
	for building in world.buildings:
		if building.is_demolished or not building.is_complete or building.rules == null:
			continue
		if building.rules.category == BuildingTypes.Category.MOVEMENT:
			continue
		if any_building == null or building.id < any_building.id:
			any_building = building
		if building.rules.category == BuildingTypes.Category.STORAGE and (
			oldest_storage == null or building.built_year < oldest_storage.built_year
			or (building.built_year == oldest_storage.built_year and building.id < oldest_storage.id)
		):
			oldest_storage = building
	return oldest_storage if oldest_storage != null else any_building

# Distanza/durata BASE della Daydream del fallback (2026-09-16, richiesta utente) — STESSI valori
# di GameScene._DEBUG_DAYDREAM_AROUND_DISTANCE/_DEBUG_DAYDREAM_THINK_BASE_DURATION (tasto Y), ma
# SENZA il moltiplicatore EraRules.think_duration_multiplier che quel tasto applica: questa
# funzione (chiamata da _resolve_active_stamina_need_priority/resolve_idle_individual a cascata,
# vedi HumanIndividualActionService) non riceve `game_data`, solo `world` — thread-arlo giù da lì
# toccherebbe 5 chiamanti esterni (HumanBirthIndividualService/GameLoadService/ZombieTaskTest/
# GameScene x2) per un affinamento cosmetico. Semplificazione deliberata: durata BASE = "era
# neutra" (moltiplicatore 1.0), coerente con l'uso già arbitrario di questa costante nel tasto Y.
const DAYDREAM_AROUND_DISTANCE: float = 14.1
const DAYDREAM_THINK_BASE_DURATION: float = 2.0

# Risoluzione dei tre target Walk della Wander Task — STESSA identica logica di GameScene.
# _resolve_wander_targets prima di questo spostamento (vedi doc di testa al file).
# Pathfinding (2026-09-27, step 2b): i due punti intermedi solo su microcelle libere e raggiungibili
# (PathfindingService.pick_free_destination, fino a 8 sorteggi ciascuno, lunghezza e direzione ritirate ogni volta);
# nessuno valido = quel tratto resta sul punto precedente. Il secondo è controllato dalla posizione attuale: il primo
# è raggiungibile da lì, quindi sta nella stessa regione e la risposta è la stessa. Il ritorno (target_3) è la
# partenza, com'era.
#
# ATTORNO ALL'ÀNCORA (2026-10-04, richiesta utente): con un'àncora (resolve_anchor_position) i due tratti vanno verso
# punti liberi e raggiungibili a WANDER_ANCHOR_MIN..MAX_DISTANCE dall'àncora in una direzione a caso, e non si torna
# alla partenza: target_3 = target_2 (l'ultimo Walk di wander.tres finisce subito). Il secondo punto, se non si trova,
# resta il primo. Senza àncora, o se nemmeno il primo punto si trova (àncora fuori dalla macrocella del pipottino, zona
# irraggiungibile), il comportamento di prima: tratti dalla posizione attuale e ritorno alla partenza. Le Wander salvate
# prima di questa modifica hanno già i loro bersagli negli step e finiscono come erano.
static func resolve_wander_targets(individual: HumanIndividual, world: World = null) -> Dictionary:
	var anchor: Variant = resolve_anchor_position(individual, world)
	if anchor != null:
		var anchored_1: Variant = _free_point_around(individual, anchor, WANDER_ANCHOR_MIN_DISTANCE, WANDER_ANCHOR_MAX_DISTANCE)
		if anchored_1 != null:
			var anchored_2: Variant = _free_point_around(individual, anchor, WANDER_ANCHOR_MIN_DISTANCE, WANDER_ANCHOR_MAX_DISTANCE)
			var second: Vector2 = anchored_2 if anchored_2 != null else anchored_1
			return {"target_1": anchored_1, "target_2": second, "target_3": second}
	var starting_position: Vector2 = individual.position
	var target_1: Vector2 = _free_leg_end(individual, starting_position)
	var target_2: Vector2 = _free_leg_end(individual, target_1)
	return {"target_1": target_1, "target_2": target_2, "target_3": starting_position}


# Explore (2026-10-04, richiesta utente): EXPLORE_LEG_COUNT tratti dalla posizione attuale, lunghi
# EXPLORE_LEG_MIN..MAX_LENGTH, con "guardarsi intorno" dopo ognuno (explore.tres), poi ritorno alla partenza
# (target_<EXPLORE_LEG_COUNT + 1>). Direzione coerente: il primo tratto va in una direzione a caso, ogni tratto
# successivo prosegue la direzione dell'ultimo tratto riuscito con una deviazione di al massimo
# EXPLORE_MAX_DEVIATION per parte — il pipottino si allontana in linea invece di girare in tondo. Ogni sorteggio di
# pick_free_destination ritira la deviazione dentro lo stesso limite; nessun punto libero e raggiungibile = il tratto
# resta sul punto precedente, e la direzione resta quella di prima. Le esplorazioni salvate con due tratti hanno già i
# loro bersagli negli step e finiscono come erano.
const EXPLORE_LEG_COUNT: int = 3
const EXPLORE_MAX_DEVIATION: float = PI / 4.0

static func resolve_explore_targets(individual: HumanIndividual) -> Dictionary:
	var starting_position: Vector2 = individual.position
	var targets: Dictionary = {}
	var leg_start: Vector2 = starting_position
	var heading: Variant = null # angolo dell'ultimo tratto riuscito; null = nessuno ancora, direzione libera
	for leg in range(EXPLORE_LEG_COUNT):
		var start: Vector2 = leg_start
		var base_heading: Variant = heading
		var destination: Variant = PathfindingService.pick_free_destination(individual, func() -> Vector2:
			var angle: float = randf() * TAU if base_heading == null else float(base_heading) + randf_range(-EXPLORE_MAX_DEVIATION, EXPLORE_MAX_DEVIATION)
			return start + Vector2.from_angle(angle) * randf_range(EXPLORE_LEG_MIN_LENGTH, EXPLORE_LEG_MAX_LENGTH)
		)
		if destination != null and (destination as Vector2) != start:
			heading = ((destination as Vector2) - start).angle()
			leg_start = destination
		targets["target_%d" % (leg + 1)] = leg_start
	targets["target_%d" % (EXPLORE_LEG_COUNT + 1)] = starting_position
	return targets


# Contesto della Explore Task dai punti di resolve_explore_targets (explore_target_1..N, vedi gli step di explore.tres).
static func build_explore_context(targets: Dictionary) -> Dictionary:
	var context: Dictionary = {}
	for i in range(1, EXPLORE_LEG_COUNT + 2):
		context["explore_target_%d" % i] = targets["target_%d" % i]
	return context


# Fine di un tratto da `leg_start`: lunghezza min..max (predefinita: quella della Wander) in una direzione a caso, su
# una microcella libera e raggiungibile; nessun sorteggio valido = `leg_start`.
static func _free_leg_end(
	individual: HumanIndividual, leg_start: Vector2,
	min_length: float = WANDER_LEG_MIN_LENGTH, max_length: float = WANDER_LEG_MAX_LENGTH
) -> Vector2:
	var destination: Variant = PathfindingService.pick_free_destination(
		individual,
		func() -> Vector2: return leg_start + Vector2.from_angle(randf() * TAU) * randf_range(min_length, max_length)
	)
	return destination if destination != null else leg_start


# Punto libero e raggiungibile a min..max da `center`, in una direzione a caso; null se nessun sorteggio è valido.
static func _free_point_around(individual: HumanIndividual, center: Vector2, min_distance: float, max_distance: float) -> Variant:
	return PathfindingService.pick_free_destination(
		individual,
		func() -> Vector2: return center + Vector2.from_angle(randf() * TAU) * randf_range(min_distance, max_distance)
	)


# Risoluzione dei due target Run della Play Task — STESSA identica logica di GameScene.
# _resolve_play_targets prima di questo spostamento (vedi doc di testa al file).
# Pathfinding (2026-09-27, step 3): stessi tratti liberi e raggiungibili di Wander (_free_leg_end).
# Attorno all'àncora (2026-10-04, richiesta utente): con un'àncora le due corse vanno verso punti liberi e raggiungibili
# entro PLAY_ANCHOR_MAX_DISTANCE da lei (secondo punto mancante = il primo); senza àncora, o se nemmeno il primo punto
# si trova, come prima.
static func resolve_play_targets(individual: HumanIndividual, world: World = null) -> Dictionary:
	var anchor: Variant = resolve_anchor_position(individual, world)
	if anchor != null:
		var anchored_1: Variant = _free_point_around(individual, anchor, PLAY_ANCHOR_MIN_DISTANCE, PLAY_ANCHOR_MAX_DISTANCE)
		if anchored_1 != null:
			var anchored_2: Variant = _free_point_around(individual, anchor, PLAY_ANCHOR_MIN_DISTANCE, PLAY_ANCHOR_MAX_DISTANCE)
			return {"target_1": anchored_1, "target_2": anchored_2 if anchored_2 != null else anchored_1}
	var starting_position: Vector2 = individual.position
	var target_1: Vector2 = _free_leg_end(individual, starting_position)
	var target_2: Vector2 = _free_leg_end(individual, target_1)
	return {"target_1": target_1, "target_2": target_2}


# Punto "vicino" del sogno a occhi aperti (2026-09-27, pathfinding step 3 — condiviso con GameScene.
# _debug_test_daydream_task): a `distance` dall'individuo in una direzione a caso, su una microcella libera e
# raggiungibile (PathfindingService.pick_free_destination, fino a 8 sorteggi); nessuno valido = la posizione attuale.
static func resolve_daydream_around_position(individual: HumanIndividual, distance: float = DAYDREAM_AROUND_DISTANCE) -> Vector2:
	var origin: Vector2 = individual.position
	var destination: Variant = PathfindingService.pick_free_destination(
		individual, func() -> Vector2: return origin + Vector2.from_angle(randf() * TAU) * distance
	)
	return destination if destination != null else origin


# Eleggibilita' di leisure_restock nel sorteggio idle: spazio libero nelle provviste >=
# LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO x capacita'. Capacita' <= 0 -> non eleggibile.
static func _is_leisure_restock_eligible(individual: HumanIndividual) -> bool:
	if individual.food_space_capacity <= 0.0:
		return false
	var free_space: float = individual.food_space_capacity - individual.food_space_used
	return free_space >= LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO * individual.food_space_capacity


# Costruisce la Task runtime per UNO dei path di IDLE_FALLBACK_TASK_PATHS — match ESPLICITO per
# path (vedi il commento su IDLE_FALLBACK_TASK_PATHS sopra per il perché non è genericizzato). Il
# case `_` logga un errore invece di un crash silenzioso, per segnalare subito una voce aggiunta a
# IDLE_FALLBACK_TASK_PATHS senza il proprio case qui.
#
# `world` (2026-09-16, richiesta utente, Rest per svago) — DEVIAZIONE rispetto alla firma
# precedente (solo path/individual): necessario per riusare NeedTaskAssignmentService.
# resolve_rest_target, che a sua volta ne ha bisogno per risolvere la Building casa dell'individuo
# (stessa DEVIAZIONE già documentata altrove nel progetto per lo stesso motivo, es.
# HumanIndividualActionService.apply_action). Thread-ato da assign_idle_fallback sotto, che lo
# riceve già come proprio parametro.
# `age_band` (2026-10-02): serve solo al rito spontaneo (riti celebrabili per età); -1 = non noto.
static func _build_idle_task(path: String, individual: HumanIndividual, world: World, age_band: int = -1) -> Task:
	match path:
		LEISURE_RITE_TASK_DEFINITION_PATH:
			# Edificio valido più vicino e un rito spontaneo a caso tra quelli celebrabili lì (RiteService).
			var rite_target := RiteService.find_spontaneous_rite_target(individual, world, age_band, GameSettings.active_human_individuals)
			if rite_target.is_empty():
				return null
			var rite_building: Building = rite_target["building"]
			var rite_rules: RiteRules = rite_target["rite"]
			var rite_macro_offset: Vector2 = Vector2(Vector2i(rite_building.macro_x, rite_building.macro_y) - individual.home_macro_coords) * World.WIDTH
			var rite_definition := load(path) as TaskDefinition
			return TaskFactory.build_task(rite_definition, {
				"target_position": PathfindingService.random_point_in_microcell(Vector2(rite_building.micro_x, rite_building.micro_y) + rite_macro_offset),
				"rite_target_building": rite_building,
				"rite_id": rite_rules.id,
			})
		"res://gameplay/scripts/tasks/definitions/wander.tres":
			if not WANDER_ENABLED:
				return null
			var target_data := resolve_wander_targets(individual, world)
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"wander_target_1": target_data["target_1"],
				"wander_target_2": target_data["target_2"],
				"wander_target_3": target_data["target_3"],
			}
			return TaskFactory.build_task(definition, context)
		EXPLORE_TASK_DEFINITION_PATH:
			var explore_targets := resolve_explore_targets(individual)
			var explore_definition := load(path) as TaskDefinition
			return TaskFactory.build_task(explore_definition, build_explore_context(explore_targets))
		"res://gameplay/scripts/tasks/definitions/play.tres":
			var target_data := resolve_play_targets(individual, world)
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"play_target_1": target_data["target_1"],
				"play_target_2": target_data["target_2"],
			}
			return TaskFactory.build_task(definition, context)
		"res://gameplay/scripts/tasks/definitions/leisure_rest.tres":
			if not LEISURE_REST_ENABLED:
				return null
			# STESSO target (casa se c'è, altrimenti walk-around) della Rest da bisogno — riusa
			# NeedTaskAssignmentService.resolve_rest_target TALE E QUALE, nessuna copia della
			# logica "ha casa? vai lì" (2026-09-16, richiesta utente). A differenza di rest.tres
			# (NeedTaskAssignmentService.REST_TASK_MAX_DURATION_DAYS fisso, ignore_stamina_cap=
			# false): qui la durata è RANDOM ad ogni assegnazione (vedi LEISURE_REST_MIN/MAX_
			# DURATION_DAYS sopra) e ignore_stamina_cap=true — questa Rest non si ferma mai a
			# stamina piena, solo alla durata (vedi RestAction.is_complete per il perché).
			var target_data := NeedTaskAssignmentService.resolve_rest_target(individual, world)
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"target_position": target_data["target_position"],
				"rest_multiplier": target_data["rest_multiplier"],
				"walk_away_target_position": target_data["walk_away_target_position"],
				"rest_max_duration_days": randf_range(LEISURE_REST_MIN_DURATION_DAYS, LEISURE_REST_MAX_DURATION_DAYS),
				"rest_ignore_stamina_cap": true,
			}
			var leisure_rest_task := TaskFactory.build_task(definition, context)
			# Ultimo step di leisure_rest.tres = "allontanati" dopo il riposo (2026-09-27, stessa regola di rest.tres):
			# saltato se all'attivazione c'è un seguito noto (HumanIndividualActionService.has_known_follow_up).
			if not leisure_rest_task.steps.is_empty() and leisure_rest_task.steps[-1] is WalkAction:
				(leisure_rest_task.steps[-1] as WalkAction).is_walk_away = true
			return leisure_rest_task
		"res://gameplay/scripts/tasks/definitions/daydreaming.tres":
			# Filtro "esiste un edificio che accetta pensieri" GIÀ APPLICATO a monte da
			# assign_idle_fallback (vedi lì) — qui si assume che il chiamante l'abbia già verificato,
			# stesso principio "un guard, un solo posto" già seguito per allowed_age_bands. Nessun
			# WANDER_ENABLED/LEISURE_REST_ENABLED equivalente per Daydream: nessuna richiesta di
			# poterla disattivare separatamente oggi.
			var around_position: Vector2 = resolve_daydream_around_position(individual)
			var definition := load(path) as TaskDefinition
			var context: Dictionary = {
				"target_position": around_position,
				"think_duration": DAYDREAM_THINK_BASE_DURATION,
			}
			var task := TaskFactory.build_task(definition, context)
			# daydream_step_appended_connector (vedi sopra) — collegato SUBITO dopo la costruzione,
			# PRIMA che assign_idle_fallback assegni la Task: stesso ordine di GameScene.
			# _debug_test_daydream_task (costruisci, collega, assegna).
			if daydream_step_appended_connector.is_valid():
				daydream_step_appended_connector.call(task, individual)
			return task
		"res://gameplay/scripts/tasks/definitions/leisure_restock.tres":
			# Guard dello spazio libero GIA' APPLICATO a monte da assign_idle_fallback (vedi lì). Se nessun
			# magazzino ha cibo torna null e assign_idle_fallback ritira tra le altre perditempo.
			return NeedTaskAssignmentService.build_restock_task(
				individual, world, NeedTaskAssignmentService.LEISURE_RESTOCK_TASK_DEFINITION_PATH
			)
		_:
			push_error("IdleTaskAssignmentService._build_idle_task: path '%s' non riconosciuto — aggiungi un case quando estendi IDLE_FALLBACK_TASK_PATHS." % path)
			return null


# Assegna una Task "perditempo" scelta a caso tra quelle di IDLE_FALLBACK_TASK_PATHS compatibili
# con age_band (2026-09-13, richiesta utente) — chiamata SOLO quando l'individuo è davvero libero:
# nessuna Task in corso, nessun bisogno stamina attivo, task_queue vuota (vedi
# HumanIndividualActionService._handle_task_completion_need_and_queue, l'unico chiamante oggi).
#
# Filtro età LEGGERO (2026-09-16, richiesta utente — sostituisce il filtro precedente basato su
# individual.can_assign_task): letto direttamente da TaskDefinition.allowed_age_bands, PRIMA di
# costruire alcuna Task — niente più "costruisci tutto poi scarta chi non passa". `remaining` porta
# solo path + TaskDefinition già caricata (mai una Task), una entry per candidato ancora in gioco.
#
# Tiro PESATO tra le entry rimanenti (vedi _pick_weighted_index sotto) usando TaskDefinition.
# idle_weight — poi si costruisce SOLO la Task estratta (mai le altre): se l'assegnazione fallisce
# (_build_idle_task torna null, es. WANDER_ENABLED/LEISURE_REST_ENABLED spento, oppure individual.
# assign_task rifiuta per un guard più profondo per-Action) quella entry viene rimossa da
# `remaining` e si ritira tra le rimanenti, finché una assegnazione riesce o il pool si esaurisce.
#
# `world` — consultato da _build_idle_task (Rest per svago: resolve_rest_target ne ha bisogno per
# risolvere la Building casa dell'individuo).
#
# Ritorna true/false (esito dell'assegnazione riuscita, o false se il pool si esaurisce senza
# successo) — stesso principio "il chiamante sa se è davvero riuscita" già seguito da
# NeedTaskAssignmentService.assign_rest_task/assign_emergency_rest_task.
static func assign_idle_fallback(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	# Interruttore globale (2026-09-16, richiesta utente) — controllato PRIMA di valutare
	# qualunque candidato: a fallback_enabled=false, nessuna Task perditempo viene mai assegnata,
	# indipendentemente da WANDER_ENABLED/LEISURE_REST_ENABLED/età — il chiamante (resolve_idle_
	# individual) ricade sul proprio ultimo ramo, individual.stop(), esattamente come se nessun
	# candidato fosse mai risultato idoneo. Nessun log qui: il log [IDLE FALLBACK] vive in
	# set_fallback_enabled sopra, al momento del toggle, non ad ogni tentativo di assegnazione
	# (che sarebbe rumoroso quanto il numero di individui che si liberano mentre il servizio è
	# spento).
	if not fallback_enabled:
		return false

	var remaining: Array[Dictionary] = []
	for path in IDLE_FALLBACK_TASK_PATHS:
		var definition := load(path) as TaskDefinition
		if not definition.allowed_age_bands.is_empty() and not definition.allowed_age_bands.has(age_band):
			continue
		# Daydream esclusa a monte se non esiste nessun edificio COMPLETO che accetta pensieri
		# (2026-09-16, richiesta utente) — STESSO criterio/STESSA funzione già usata dal gate upfront
		# del tasto debug Y (vedi GameScene._debug_test_daydream_task): senza edificio, la Task
		# finirebbe comunque "a vuoto" (Think + nessun deposito, vedi _handle_pending_thought_
		# target_search), non un fallimento distruttivo ma inutile da estrarre nel tiro pesato.
		if path == "res://gameplay/scripts/tasks/definitions/daydreaming.tres" and not ThoughtTargetSelectionService.has_thought_accepting_building(world):
			continue
		# leisure_restock esclusa a monte se le provviste sono quasi piene (spazio libero sotto
		# LEISURE_RESTOCK_MIN_FREE_SPACE_RATIO della capacita'): il sorteggio ne pesca un'altra.
		if path == "res://gameplay/scripts/tasks/definitions/leisure_restock.tres" and not _is_leisure_restock_eligible(individual):
			continue
		# Rito spontaneo escluso a monte senza un edificio dove celebrarlo (2026-10-02, vedi LEISURE_RITE_TASK_DEFINITION_PATH).
		if path == LEISURE_RITE_TASK_DEFINITION_PATH and RiteService.find_spontaneous_rite_target(
			individual, world, age_band, GameSettings.active_human_individuals
		).is_empty():
			continue
		remaining.append({"path": path, "definition": definition})

	while not remaining.is_empty():
		var drawn_index := _pick_weighted_index(remaining)
		var path: String = remaining[drawn_index]["path"]
		var candidate_task := _build_idle_task(path, individual, world, age_band)
		var assigned := candidate_task != null and individual.assign_task(candidate_task, age_band)
		if assigned:
			if DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
				print("[IDLE FALLBACK] #%d %s: nessuna Task/bisogno/coda attivi — assegnata '%s'." % [
					individual.id, individual.name, candidate_task.task_name
				])
			return true
		remaining.remove_at(drawn_index)
	return false


# Tiro PESATO su indice tra le entry di `remaining` (2026-09-16, richiesta utente — sostituisce
# _pick_weighted_task/IDLE_FALLBACK_TASK_WEIGHTS: il peso vive ora su TaskDefinition.idle_weight,
# letto qui direttamente dall'entry — vedi assign_idle_fallback sopra). Nessuna normalizzazione
# esplicita a somma 1.0: il tiro (`randf() * total_weight`) avviene già sul solo totale delle entry
# ANCORA in gioco in questa chiamata — via via che una entry fallita viene rimossa da `remaining`
# dal chiamante, il rapporto relativo tra i pesi restanti resta quello dichiarato.
#
# total_weight <= 0.0 (caso limite — idle_weight <= 0 su ogni entry rimanente, mai un caso reale
# oggi ma non un crash) -> ripiega sul tiro uniforme, nessuna entry mai esclusa per un peso mancante.
#
# Ultimo indice come fallback finale dopo il ciclo (mai raggiunto in teoria: roll < total_weight
# per costruzione, garantisce che l'ultimo confronto cumulativo sia sempre vero) — solo per
# proteggere da un residuo di imprecisione in virgola mobile, stesso principio "mai un crash" già
# seguito ovunque nel progetto.
static func _pick_weighted_index(remaining: Array[Dictionary]) -> int:
	var total_weight: float = 0.0
	for entry in remaining:
		total_weight += float((entry["definition"] as TaskDefinition).idle_weight)
	if total_weight <= 0.0:
		return randi() % remaining.size()
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for i in range(remaining.size()):
		cumulative += float((remaining[i]["definition"] as TaskDefinition).idle_weight)
		if roll < cumulative:
			return i
	return remaining.size() - 1
