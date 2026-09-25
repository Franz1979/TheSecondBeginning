class_name PickUpAction
extends Action

# Quinta sottoclasse concreta di Action, prima con un bersaglio SPAZIALE che non è un movimento
# (2026-09-08, richiesta utente, Step 2 del piano raccolta/trasporto — Step 1 era solo verifica
# StonePositionService/MacroCellState.pebble_quantities, confermato come unica fonte di verità mai
# rigenerata per una macrocella già inizializzata). Bersaglio TEMPORALE come ThinkAction (un
# accumulatore _elapsed confrontato con _duration, stesso schema esatto — vedi
# get_stamina_delta/is_complete sotto), ma con `target_position` che identifica DOVE raccogliere
# (non un movimento: l'individuo deve già essere lì, garantito dal WalkAction precedente nella
# stessa Task, stesso principio già seguito da UnloadAction per lo Pebble Circle).
#
# `macro_state` (2026-09-08) — DEVIAZIONE dalla firma richiesta (solo target_position/resource_
# name): necessario per leggere/scrivere il pool della risorsa scattered, che Action non può
# raggiungere da sola (nessun collegamento a World/GameScene, vedi Action.gd). Iniettato dal
# chiamante esattamente come WalkAction riceve `target` già risolto — chi crea questa Action (oggi
# solo GameScene._debug_test_two_walk_task, vedi lì) ha già il MacroCellState della cella viva a
# portata di mano, nessun nuovo lookup necessario da parte sua.
#
# resource_name resta un parametro libero (default "pebble") per non dover toccare questa classe
# quando arriverà una nuova risorsa raccoglibile con lo stesso meccanismo — CaloricCalculator.
# get_caloric_source_rules(resource_name) risolve un .tres valido per qualunque nome, e
# TerrainScatteredResourceService (2026-09-09) smista internamente sul Dictionary/formato giusto
# di MacroCellState ("pebble" → pebble_quantities, "stick" → stick_quantities) — pebble e stick
# sono entrambi implementati lì oggi.

# ZAINO MULTI-RISORSA (2026-09-20, richiesta utente, passo 2): una PickUpAction non si ferma piu' alla prima
# risorsa. Riceve un CRITERIO (CriterionKind): NAME = una sola risorsa (`resource_name`, comportamento di
# prima), CATEGORY = tutte le risorse di una categoria (SecondaryResourceTypes.Category) presenti nella
# microcella, ALL = tutto quello che c'e'. Raccoglie finche' c'e' spazio e finche' le varieta' nello zaino non
# arrivano a HumanIndividual.MAX_CARRIED_VARIETIES (4); un'unita' entra solo se ci sta intera. Ordine:
# tra categorie priorita' fissa PRIORITY_CATEGORIES (cibo, materiali, medicinali); dentro il cibo
# calorie/spazio decrescente (FoodSelectionService.is_denser_food_first); dentro le altre categorie quantita'
# disponibile decrescente. Il vecchio requisito "zaino vuoto" non c'e' piu': si raccoglie anche con roba
# addosso (fusione con media pesata della decay_fraction in HumanIndividual.add_carried_resource). Cosa
# raccogliere e' deciso UNA VOLTA in activate() (il piano `_plan`), come prima per la quantita'.

# Costo stamina TOTALE = questo × spazio_raccolto (richiesta utente) — valore di partenza
# ARBITRARIO, stesso trattamento "da bilanciare" di ogni altra costante di questo sistema (vedi
# WalkAction.STAMINA_DRAIN_PER_MICROCELL_BASE/STAMINA_DRAIN_PER_TOOL, ThinkAction.STAMINA_DRAIN_
# PER_DAY).
const STAMINA_COST_PER_SPACE_UNIT: float = 2.0


# Emesso da on_complete() (una volta PER RISORSA raccolta) SOLO quando una raccolta reale è avvenuta (quantità > 0,
# 2026-09-09, richiesta utente — bug "pebble/stick restano disegnati dopo la raccolta") — stesso
# principio di disaccoppiamento già seguito da UnloadAction.idea_completed/thought_deposited:
# questa classe non conosce MicroCellRenderer/GameScene, si limita a segnalare "ho consumato
# `quantity` unità di `resource_name` in `target_position`", chi ha creato la Task (oggi
# GameScene._assign_pickup_task/_debug_test_two_walk_task) decide se/come rinfrescare il disegno
# (vedi GameScene._refresh_resource_visuals, il consumatore).
signal resource_collected(resource_name: String, target_position: Vector2i, quantity: int)

# Emesso UNA SOLA VOLTA a fine on_complete() se e' stato raccolto qualcosa (2026-09-20, zaino multi-
# risorsa): `collected` = {nome_risorsa: quantita' raccolta}. resource_collected sopra parte una volta per
# risorsa, quindi un refresh del disegno agganciato a quello ricostruirebbe la macrocella N volte;
# GameScene aggancia il refresh a questo segnale.
signal collection_completed(collected: Dictionary)

# Emesso da on_complete() quando la raccolta e' andata a buon fine, la ripetizione e' attiva nel context della
# Task, le ripetizioni fatte sono meno di TaskRepeatRules.MAX_REPEATS e nella microcella resta ancora qualcosa che il criterio
# puo' prendere: chiede a chi ha creato la Task (GameScene._queue_pickup_repeat) di generare una nuova Task di
# raccolta identica (stessa cella, stesso criterio) e accodarla a `individual`. `next_repeat_count` = numero di
# ripetizioni gia' fatte INCLUSA la nuova (la prima ripetizione porta 1). La classe non conosce Task ne'
# TaskFactory: come per collection_completed si limita a segnalare.
signal repeat_requested(individual: Variant, next_repeat_count: int)

# Criterio di raccolta (vedi il commento in testa al file). L'ordine dei valori e' persistito nei salvataggi
# (TaskPersistenceService): non riordinare, solo aggiungere in coda.
enum CriterionKind { NAME, CATEGORY, ALL }

# Priorita' fissa tra categorie (2026-09-20): cibo, poi materiali, poi medicinali; semilavorati e
# strumenti (2026-09-23) in coda.
const PRIORITY_CATEGORIES: Array = [
	SecondaryResourceTypes.Category.FOOD,
	SecondaryResourceTypes.Category.RAW_MATERIAL,
	SecondaryResourceTypes.Category.MEDICINAL,
	SecondaryResourceTypes.Category.SEMI_FINISHED,
	SecondaryResourceTypes.Category.TOOL,
]

var target_position: Vector2i
# Usato solo con criterion_kind == NAME (la risorsa da raccogliere); con CATEGORY/ALL e' ignorato, ma resta
# valorizzato (TaskFactory lo richiede sempre come argomento).
var resource_name: String = "pebble"
var macro_state: MacroCellState = null

var criterion_kind: CriterionKind = CriterionKind.NAME
# SecondaryResourceTypes.Category come int, valido solo con criterion_kind == CATEGORY (-1 altrimenti).
var criterion_category: int = -1

# Quantità RICHIESTA dal player (2026-09-18, richiesta utente — scelta quantità anche per il
# pickup, STESSO campo/STESSO significato di RetrieveAction.quantity_requested) — NON garantita:
# se lo spazio libero in spalla o la disponibilità reale sul lotto sono minori, la quantità nel piano
# (_plan) risulta comunque minore (vedi activate()). -1 (default) = nessun tetto scelto dal
# player, comportamento INVARIATO per ogni chiamante che non lo passa (debug hook, fallback "1
# candidato senza dialog"): risolve il massimo raccoglibile esattamente come prima di questo campo.
# Vale SOLO con criterion_kind == NAME (tetto su quella risorsa); con CATEGORY/ALL e' ignorata.
var quantity_requested: int = -1

# Piano di raccolta risolto in activate() (mai ricalcolato dopo), consumato da on_complete(): un elemento per
# risorsa, gia' nell'ordine di raccolta, {"resource_name": String, "quantity": int > 0}. Vuoto = niente da
# raccogliere (spazio libero insufficiente, varieta' al tetto, niente disponibile in quella posizione):
# "azione immediatamente completa", stesso significato di prima con quantita' 0.
var _plan: Array[Dictionary] = []

# Perche' la raccolta si e' fermata (solo per il log SHOW_PICKUP_LOGS): "spazio pieno", "4 varieta'",
# "quantita' richiesta raggiunta", "niente altro disponibile", anche piu' d'una separate da virgola. Risolto
# insieme al piano in activate() e persistito con lui.
var _stop_reason: String = ""

# Stesso schema esatto di ThinkAction.duration/_elapsed (richiesta esplicita utente, "non
# reinventarla") — _duration in FRAZIONI DI GIORNO DI GIOCO, stessa unità di `delta` in
# get_stamina_delta. _total_stamina_cost è il costo COMPLESSIVO da erogare uniformemente su
# _duration (non un drain/giorno fisso come ThinkAction.STAMINA_DRAIN_PER_DAY, perché qui il costo
# totale dipende dallo spazio raccolto, non è una costante di classe).
var _duration: float = 0.0
var _total_stamina_cost: float = 0.0
var _elapsed: float = 0.0

# Guardia persistenza (2026-09-09, richiesta utente) — vero SOLO dopo load_save_data(), mai
# azzerato dopo. Necessaria perché GameLoadService richiama SEMPRE activate() sullo step corrente
# subito dopo la deserializzazione (per ripristinare effetti collaterali non persistiti, es.
# WalkAction.target_position/is_moving — vedi GameLoadService.gd) — per WalkAction/ThinkAction
# questa seconda chiamata è innocua (il loro _init ha già fissato target/duration, activate() non
# li ritocca), ma qui activate() RICALCOLA da zero _plan/_duration/_elapsed=0.0: senza
# questa guardia, un salvataggio a metà raccolta perderebbe silenziosamente il progresso già
# maturato (_elapsed) ripartendo da 0 — esattamente il bug che questa persistenza deve evitare.
var _restored_from_save: bool = false


func _init(
	p_target_position: Vector2i, p_macro_state: MacroCellState, p_resource_name: String = "pebble", p_quantity_requested: int = -1,
	p_criterion_kind: int = CriterionKind.NAME, p_criterion_category: int = -1
) -> void:
	target_position = p_target_position
	macro_state = p_macro_state
	resource_name = p_resource_name
	quantity_requested = p_quantity_requested
	criterion_kind = p_criterion_kind as CriterionKind
	criterion_category = p_criterion_category
	target = null
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands). CHILD aggiunto 2026-09-13 (richiesta
	# utente).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Risolve UNA VOLTA (mai più ricalcolato dopo, stesso principio di WalkAction.target/ThinkAction.
# duration) cosa verrà raccolto — vedi _resolve_plan per le regole (criterio, ordine, spazio, varietà).
# Per ogni risorsa del piano, la formula di sempre:
#   spazio_libero = max_carry_capacity - individual.get_carried_space() (somma di quantity ×
#                   space_per_unit di ogni varietà già trasportata, meno quanto già pianificato)
#   disponibile   = TerrainScatteredResourceService.get_available(macro_state, nome, target_position)
#   quantità      = min(floor(spazio_libero / space_per_unit), disponibile)
# Durata e costo stamina restano proporzionali allo spazio TOTALE raccolto (la somma sulle risorse del piano),
# come prima erano proporzionali allo spazio della sola risorsa: spazio_raccolto = Σ quantità × space_per_unit.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	# Stato già ripristinato da un salvataggio (vedi _restored_from_save sopra) — NON ricalcolare,
	# altrimenti si perderebbe _elapsed (progresso già maturato) e si rischierebbe di ottenere
	# valori diversi da quelli persistiti se lo stato dell'individuo/della macrocella nel frattempo
	# fosse cambiato (non dovrebbe succedere tra un save e il load immediatamente successivo, ma
	# questa guardia lo rende comunque impossibile per costruzione).
	if _restored_from_save:
		return

	var space_collected: float = _resolve_plan(individual)
	_duration = 0.0
	_total_stamina_cost = 0.0
	if space_collected > 0.0 and individual.max_carry_capacity > 0.0:
		_duration = space_collected / individual.max_carry_capacity
		_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_collected
	_elapsed = 0.0


# Candidati alla raccolta in target_position secondo il criterio, GIA' ORDINATI: un Dictionary per risorsa
# {"name", "available" (> 0), "space" (space_per_unit > 0), "category", "density" (calorie/spazio)}.
#   - NAME: solo resource_name; CATEGORY: ogni risorsa con SecondaryResourceRules.category == criterion_category;
#     ALL: ogni risorsa secondaria (CaloricCalculator.list_secondary_resource_names()).
#   - la disponibilita' e' TerrainScatteredResourceService.get_available (la stessa fonte di pickup/ispezione,
#     con il gate required_idea_id: una risorsa bloccata risulta 0 e non e' candidata); una risorsa che non
#     esiste in quella microcella ha disponibilita' 0.
#   - ordine: categoria secondo PRIORITY_CATEGORIES; dentro il cibo calorie/spazio decrescente
#     (FoodSelectionService.is_denser_food_first); dentro le altre categorie quantita' disponibile
#     decrescente; a parita' per nome (esito deterministico).
func _build_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if macro_state == null:
		return candidates
	var names: Array[String] = []
	if criterion_kind == CriterionKind.NAME:
		names.append(resource_name)
	else:
		names = CaloricCalculator.list_secondary_resource_names()
	for candidate_name in names:
		var rules := CaloricCalculator.get_caloric_source_rules(candidate_name)
		if rules == null or rules.space_per_unit <= 0.0:
			continue
		if criterion_kind == CriterionKind.CATEGORY and int(rules.category) != criterion_category:
			continue
		var available: int = TerrainScatteredResourceService.get_available(macro_state, candidate_name, target_position)
		if available <= 0:
			continue
		candidates.append({
			"name": candidate_name,
			"available": available,
			"space": rules.space_per_unit,
			"category": int(rules.category),
			"density": rules.calories_per_unit / rules.space_per_unit,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a: int = PickUpAction.PRIORITY_CATEGORIES.find(a["category"])
		var priority_b: int = PickUpAction.PRIORITY_CATEGORIES.find(b["category"])
		if priority_a != priority_b:
			return priority_a < priority_b
		if int(a["category"]) == SecondaryResourceTypes.Category.FOOD:
			return FoodSelectionService.is_denser_food_first(float(a["density"]), String(a["name"]), float(b["density"]), String(b["name"]))
		if int(a["available"]) != int(b["available"]):
			return int(a["available"]) > int(b["available"])
		return String(a["name"]) < String(b["name"])
	)
	return candidates


# Riempie _plan/_stop_reason e ritorna lo spazio totale che il piano occupera' nello zaino. Scorre i
# candidati nell'ordine di _build_candidates e per ciascuno prende min(disponibile, unita' che ci stanno
# INTERE nello spazio residuo), poi scala lo spazio:
#   - se nemmeno un'unita' ci sta, quel candidato e' saltato (uno successivo, con unita' piu' piccole, puo'
#     ancora starci — stesso criterio di FoodSelectionService.select_food) => motivo "spazio pieno";
#   - una varieta' NUOVA (non gia' nello zaino) entra solo se le varieta' sono meno di
#     HumanIndividual.MAX_CARRIED_VARIETIES; una gia' presente si fonde sempre (non conta come nuova) e
#     puo' essere rabboccata anche a 4 varieta' => motivo "4 varieta'" per quelle rifiutate;
#   - con criterio NAME e quantity_requested >= 0 la quantita' e' limitata a quel tetto => motivo "quantita'
#     richiesta raggiunta" (CATEGORY/ALL ignorano quantity_requested);
#   - nessun motivo di stop vale "niente altro disponibile": tutto cio' che c'era e' stato preso.
func _resolve_plan(individual: Variant) -> float:
	_plan = []
	var candidates: Array[Dictionary] = _build_candidates()
	var free_space: float = individual.max_carry_capacity - individual.get_carried_space()
	var variety_count: int = individual.carried_resources.size()
	var space_limited: bool = false
	var variety_limited: bool = false
	var requested_limited: bool = false
	var space_collected: float = 0.0
	for candidate in candidates:
		var candidate_name: String = candidate["name"]
		var space_per_unit: float = candidate["space"]
		var available: int = candidate["available"]
		var fit_units: int = int(floor(free_space / space_per_unit + FoodSelectionService.UNIT_FIT_EPSILON))
		if fit_units <= 0:
			space_limited = true
			continue
		var is_new_variety: bool = not individual.carried_resources.has(candidate_name)
		if is_new_variety and variety_count >= HumanIndividual.MAX_CARRIED_VARIETIES:
			variety_limited = true
			continue
		var take: int = mini(available, fit_units)
		if criterion_kind == CriterionKind.NAME and quantity_requested >= 0 and take > quantity_requested:
			take = quantity_requested
			requested_limited = true
		elif fit_units < available:
			space_limited = true
		if take <= 0:
			continue
		_plan.append({"resource_name": candidate_name, "quantity": take})
		free_space -= float(take) * space_per_unit
		space_collected += float(take) * space_per_unit
		if is_new_variety:
			variety_count += 1
	var reasons: Array[String] = []
	if space_limited:
		reasons.append("spazio pieno")
	if variety_limited:
		reasons.append("4 varietà")
	if requested_limited:
		reasons.append("quantità richiesta raggiunta")
	if reasons.is_empty():
		reasons.append("niente altro disponibile")
	_stop_reason = ", ".join(reasons)
	return space_collected


# Stesso schema esatto di ThinkAction.get_stamina_delta/is_complete (richiesta esplicita utente) —
# unica differenza: il tasso non è una costante di classe ma _total_stamina_cost/_duration, risolto
# in activate() per QUESTA istanza. _duration <= 0.0 (quantità 0, "azione immediatamente completa,
# nessun costo, nessuna durata") non incrementa _elapsed e ritorna 0.0 — is_complete() sotto torna
# comunque vero da subito (0.0 >= 0.0), stesso principio con cui ThinkAction.duration=0 si
# completerebbe al primissimo controllo.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _duration <= 0.0:
		return 0.0
	_elapsed += delta
	return -(_total_stamina_cost / _duration) * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= _duration


# get_required_position (2026-09-13, richiesta utente — fix "Walk di ritorno alla ripresa", vedi
# Action.get_required_position) — SEMPLICE tra le 6 sovrascritture: target_position è già un
# campo diretto (Vector2i), nessuna conversione cross-macrocella necessaria (a differenza delle
# altre 5, basate su target_building — vedi quelle classi) perché è già nello stesso sistema di
# coordinate LOCALE di individual.position (entrambi relativi alla macrocella HOME
# dell'individuo, mai un target_position su una macrocella diversa: PickUpAction non ha mai
# rappresentato una risorsa fuori dalla cella viva corrente). `individual`/`context` inutilizzati
# qui, stessa firma di ogni altro override.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	return Vector2(target_position)


# Esegue il piano (_plan) risolto in activate(): per ogni risorsa la aggiunge allo zaino (add_carried_resource:
# fusione con media pesata della decay_fraction se e' gia' presente, rifiuto se sarebbe la quinta varieta') e
# la consuma dal pool tramite TerrainScatteredResourceService (2026-09-09) — non più un tocco diretto a
# MacroCellState.pebble_quantities: il service smista internamente per formato/comportamento di consumo. Si
# consuma SOLO quanto e' davvero entrato nello zaino. No-op se il piano e' vuoto (niente da applicare, stesso
# principio "istantaneo senza effetti" di UnloadAction.on_complete quando pending_thought è false).
#
# decay_fraction in arrivo = 0.0 SEMPRE (2026-09-09, richiesta utente — Step 3 decadimento):
# SEMPLIFICAZIONE ESPLICITA segnalata come richiesto: la SORGENTE (TerrainScatteredResourceService/
# MacroCellState) non traccia da quanto tempo quella risorsa è a terra, quindi non esiste un valore "vero" da
# propagare: il carico raccolto parte SEMPRE fresco (0.0), anche se fisicamente lì da anni. Con lo zaino
# multi-risorsa (2026-09-20) la fusione con una varieta' gia' presente in spalla usa la media pesata di
# add_carried_resource: il nuovo carico fresco "ringiovanisce" la media della varieta'.
func on_complete(individual: Variant, context: Dictionary) -> void:
	var collected: Dictionary = {}
	var searches: Array = []
	for entry in _plan:
		var entry_name: String = entry["resource_name"]
		var added: int = individual.add_carried_resource(entry_name, int(entry["quantity"]), 0.0)
		if added <= 0:
			continue
		if macro_state != null:
			TerrainScatteredResourceService.consume(macro_state, entry_name, target_position, added)
		collected[entry_name] = added
		resource_collected.emit(entry_name, target_position, added)
		# Quantita' cercata = TUTTO quello che ora si trasporta di questa risorsa (comprese eventuali unita'
		# gia' in spalla prima di questa raccolta), perche' l'Unload deposita tutto cio' che il magazzino
		# accetta.
		searches.append({"resource_name": entry_name, "quantity": individual.get_carried_quantity(entry_name)})

	if DebugLogging.ENABLED and DebugLogging.SHOW_PICKUP_LOGS:
		print("[PICKUP] #%d %s: %s in (%d,%d) — raccolto=%s | stop: %s | zaino=%s" % [
			individual.id, individual.name, _criterion_text(), target_position.x, target_position.y,
			str(collected), _stop_reason, str(individual.carried_resources)
		])
	if collected.is_empty():
		return
	collection_completed.emit(collected)

	# Ricerca magazzino INIZIALE (2026-09-09, richiesta utente — haul_resource, stesso canale
	# generico usato dal re-routing di UnloadAction.activate, vedi lì per il Dictionary gemello):
	# scritto SOLO quando una raccolta reale è avvenuta (return anticipato sopra). Zaino multi-risorsa
	# (2026-09-20): forma {"searches": [{"resource_name", "quantity"}, ...], ...}, UNA ricerca per risorsa
	# raccolta (vedi HumanIndividualActionService._handle_pending_warehouse_search: stesso magazzino per piu'
	# risorse => un solo Walk+Unload). excluded_building_ids parte vuoto: nessun magazzino ancora tentato.
	#
	# NESSUN "discard_on_failure" qui (a differenza di UnloadAction.activate) — default false in
	# HumanIndividualActionService._handle_pending_warehouse_search: se la ricerca non trova nulla per una
	# risorsa, quella varieta' viene scartata (Scenario B1).
	context["pending_warehouse_search"] = {
		"searches": searches,
		"excluded_building_ids": [],
	}

	_request_repeat_if_needed(individual, context)


# Ripetizione automatica (2026-09-20, richiesta utente). Attiva solo se il context della Task porta
# TaskRepeatRules.CONTEXT_ENABLED (scritto da GameScene alla creazione; il contatore CONTEXT_COUNT viaggia li',
# non nell'Action, e sopravvive al salvataggio insieme al context). Nessun controllo "in anticipo" sulla cella
# prima di partire: la nuova Task va comunque, e se qualcuno nel frattempo l'ha svuotata trova zero, si chiude
# senza raccogliere (piano vuoto, on_complete esce prima di arrivare qui) e non ne nasce un'altra. Qui, a
# raccolta avvenuta, si verifica solo che il criterio possa ancora prendere qualcosa (_build_candidates: stessa
# fonte di disponibilita' di activate).
func _request_repeat_if_needed(individual: Variant, context: Dictionary) -> void:
	if not TaskRepeatRules.is_enabled(context):
		return
	var repeats_done: int = TaskRepeatRules.get_count(context)
	if repeats_done >= TaskRepeatRules.MAX_REPEATS:
		return
	if _build_candidates().is_empty():
		if DebugLogging.ENABLED and DebugLogging.SHOW_PICKUP_LOGS:
			print("[PICKUP] #%d %s: ripetizione non richiesta (%d/%d) — la microcella non ha piu' nulla per il criterio." % [
				individual.id, individual.name, repeats_done, TaskRepeatRules.MAX_REPEATS
			])
		return
	if DebugLogging.ENABLED and DebugLogging.SHOW_PICKUP_LOGS:
		print("[PICKUP] #%d %s: ripetizione %d/%d richiesta — resta ancora qualcosa per il criterio." % [
			individual.id, individual.name, repeats_done + 1, TaskRepeatRules.MAX_REPEATS
		])
	repeat_requested.emit(individual, repeats_done + 1)


# Descrizione del criterio per il log SHOW_PICKUP_LOGS: nome=<risorsa>, categoria=<FOOD|RAW_MATERIAL|MEDICINAL>
# o tutto.
func _criterion_text() -> String:
	match criterion_kind:
		CriterionKind.CATEGORY:
			var category_names: Array = SecondaryResourceTypes.Category.keys()
			return "categoria=%s" % (category_names[criterion_category] if criterion_category >= 0 and criterion_category < category_names.size() else str(criterion_category))
		CriterionKind.ALL:
			return "tutto"
	return "nome=%s" % resource_name


# Persistenza (2026-09-09, richiesta utente) — target_position/resource_name qui SOLO per
# ridondanza col precedente già stabilito da ThinkAction (get_save_data() esporta anche `duration`,
# pur essendo anch'esso già passato al costruttore in TaskPersistenceService._build_step): la vera
# fonte di verità per la RICOSTRUZIONE resta il costruttore (TaskPersistenceService._build_step
# legge target_position_x/y/resource_name da step_data per chiamare PickUpAction.new(...), PRIMA di
# invocare load_save_data() — stesso ordine già in uso per ThinkAction.duration). Chiavi
# "target_position_x/y" (non "target_x/y"): quelle sono riservate al trattamento GENERICO di
# Action.target in TaskPersistenceService.serialize_task (target resta null qui, come per Rest/
# Think/Deposit — vedi _init sopra), target_position è un campo Vector2i separato, mai un
# Action.target Vector2.
func get_save_data() -> Dictionary:
	return {
		"target_position_x": target_position.x,
		"target_position_y": target_position.y,
		"resource_name": resource_name,
		"quantity_requested": quantity_requested,
		# Criterio e piano (2026-09-20, zaino multi-risorsa): criterion_kind/criterion_category servono a
		# TaskPersistenceService._build_step per ricostruire l'Action; plan/stop_reason sono il progresso gia'
		# risolto da activate() (ripristinato da load_save_data, vedi _restored_from_save).
		"criterion_kind": int(criterion_kind),
		"criterion_category": criterion_category,
		"plan": _plan.duplicate(true),
		"stop_reason": _stop_reason,
		"duration": _duration,
		"elapsed": _elapsed,
	}


# Ripristina SOLO il progresso/esito già calcolato da un'activate() precedente (_plan/_duration/_elapsed) —
# MAI target_position/resource_name/criterio, già risolti dal costruttore (vedi get_save_data sopra). Marca
# _restored_from_save cosi' la ripetizione di activate() che GameLoadService invoca subito dopo (per
# ripristinare gli effetti collaterali non persistiti delle altre Action, es. WalkAction) non sovrascriva
# questo stato appena ripristinato. Compatibilita' con i salvataggi precedenti allo zaino multi-risorsa: senza
# "plan" ma con "quantity_to_collect" > 0 si ricostruisce un piano di UNA risorsa (resource_name).
func load_save_data(data: Dictionary) -> void:
	_plan = []
	var saved_plan: Variant = data.get("plan", null)
	if saved_plan is Array:
		for saved_entry in saved_plan:
			var saved_quantity: int = int(saved_entry.get("quantity", 0))
			if saved_quantity > 0:
				_plan.append({"resource_name": String(saved_entry.get("resource_name", "")), "quantity": saved_quantity})
	else:
		var legacy_quantity: int = int(data.get("quantity_to_collect", 0))
		if legacy_quantity > 0:
			_plan.append({"resource_name": resource_name, "quantity": legacy_quantity})
	_stop_reason = String(data.get("stop_reason", ""))
	_duration = float(data.get("duration", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
	_restored_from_save = true
