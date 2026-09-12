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

# Costo stamina TOTALE = questo × spazio_raccolto (richiesta utente) — valore di partenza
# ARBITRARIO, stesso trattamento "da bilanciare" di ogni altra costante di questo sistema (vedi
# WalkAction.STAMINA_DRAIN_PER_MICROCELL_BASE/STAMINA_DRAIN_PER_TOOL, ThinkAction.STAMINA_DRAIN_
# PER_DAY).
const STAMINA_COST_PER_SPACE_UNIT: float = 2.0

# Emesso da on_complete() SOLO quando una raccolta reale è avvenuta (_quantity_to_collect > 0,
# 2026-09-09, richiesta utente — bug "pebble/stick restano disegnati dopo la raccolta") — stesso
# principio di disaccoppiamento già seguito da UnloadAction.idea_completed/thought_deposited:
# questa classe non conosce MicroCellRenderer/GameScene, si limita a segnalare "ho consumato
# `quantity` unità di `resource_name` in `target_position`", chi ha creato la Task (oggi
# GameScene._assign_pickup_task/_debug_test_two_walk_task) decide se/come rinfrescare il disegno
# (vedi GameScene._refresh_resource_visuals, il consumatore).
signal resource_collected(resource_name: String, target_position: Vector2i, quantity: int)

var target_position: Vector2i
var resource_name: String = "pebble"
var macro_state: MacroCellState = null

# Quantità che questo step raccoglierà davvero — risolta in activate() (mai ricalcolata dopo),
# consumata da on_complete() per il decremento/assegnazione carico. 0 = niente da raccogliere
# (spazio libero insufficiente, nessun pebble disponibile in quella posizione, o zaino già occupato
# da un'altra risorsa — vedi activate() sotto), stesso significato di "azione immediatamente
# completa" richiesto esplicitamente.
var _quantity_to_collect: int = 0

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
# li ritocca), ma qui activate() RICALCOLA da zero _quantity_to_collect/_duration/_elapsed=0.0: senza
# questa guardia, un salvataggio a metà raccolta perderebbe silenziosamente il progresso già
# maturato (_elapsed) ripartendo da 0 — esattamente il bug che questa persistenza deve evitare.
var _restored_from_save: bool = false


func _init(p_target_position: Vector2i, p_macro_state: MacroCellState, p_resource_name: String = "pebble") -> void:
	target_position = p_target_position
	macro_state = p_macro_state
	resource_name = p_resource_name
	target = null


# Risolve UNA VOLTA (mai più ricalcolato dopo, stesso principio di WalkAction.target/ThinkAction.
# duration) quanto verrà raccolto — formula esatta richiesta:
#   spazio_libero = max_carry_capacity - (carried_quantity × space_per_unit della risorsa già
#                   trasportata, se presente)
#   disponibile   = TerrainScatteredResourceService.get_available(macro_state, resource_name, target_position)
#   quantità      = min(floor(spazio_libero / space_per_unit), disponibile)
#   spazio_raccolto = quantità × space_per_unit
# Assunzione richiesta esplicitamente: l'individuo arriva con carried_resource_name == "" (zaino
# vuoto) — se non è così, quantità resta 0 (nessuna azione), nessuna gestione mista di due risorse
# diverse in questo passo.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	# Stato già ripristinato da un salvataggio (vedi _restored_from_save sopra) — NON ricalcolare,
	# altrimenti si perderebbe _elapsed (progresso già maturato) e si rischierebbe di ottenere
	# valori diversi da quelli persistiti se lo stato dell'individuo/della macrocella nel frattempo
	# fosse cambiato (non dovrebbe succedere tra un save e il load immediatamente successivo, ma
	# questa guardia lo rende comunque impossibile per costruzione).
	if _restored_from_save:
		return

	var used_space := 0.0
	if individual.carried_resource_name != "":
		var carried_rules := CaloricCalculator.get_caloric_source_rules(individual.carried_resource_name)
		if carried_rules != null:
			used_space = float(individual.carried_quantity) * carried_rules.space_per_unit
	var free_space: float = individual.max_carry_capacity - used_space

	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var space_per_unit: float = resource_rules.space_per_unit if resource_rules != null else 0.0

	var available: int = 0
	if macro_state != null:
		available = TerrainScatteredResourceService.get_available(macro_state, resource_name, target_position)

	_quantity_to_collect = 0
	if individual.carried_resource_name == "" and space_per_unit > 0.0:
		_quantity_to_collect = max(0, min(int(floor(free_space / space_per_unit)), available))

	var space_collected: float = float(_quantity_to_collect) * space_per_unit
	_duration = 0.0
	_total_stamina_cost = 0.0
	if _quantity_to_collect > 0 and individual.max_carry_capacity > 0.0:
		_duration = space_collected / individual.max_carry_capacity
		_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_collected
	_elapsed = 0.0


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


# Consuma _quantity_to_collect dal pool di resource_name tramite TerrainScatteredResourceService
# (2026-09-09) — non più un tocco diretto a MacroCellState.pebble_quantities: il service smista
# internamente su pebble_quantities/stick_quantities per formato/comportamento di consumo. No-op
# se _quantity_to_collect è 0 (niente da applicare, stesso principio "istantaneo senza effetti" di
# UnloadAction.on_complete quando pending_thought è false).
#
# carried_decay_fraction = 0.0 SEMPRE (2026-09-09, richiesta utente — Step 3 decadimento):
# SEMPLIFICAZIONE ESPLICITA segnalata come richiesto, non un caso già coperto correttamente. Lo
# zaino è garantito vuoto quando questo ramo esegue (activate() sopra risolve _quantity_to_collect
# > 0 SOLO se individual.carried_resource_name == "", vedi lì), quindi non serve una media pesata
# come in BuildingStorageService.store — ma la SORGENTE (TerrainScatteredResourceService/
# MacroCellState.pebble_quantities/stick_quantities) non traccia da quanto tempo quel pebble/stick
# è a terra, quindi non esiste un valore "vero" da propagare: il carico raccolto parte SEMPRE
# fresco (0.0), anche se fisicamente lì da anni. Impatto pratico oggi NULLO: pebble/stick sono le
# uniche due risorse che PickUpAction gestisce, ed ENTRAMBE hanno day_durability = -1 (mai
# deperiscono, vedi pebble.tres/stick.tres) — questa semplificazione non altera alcun comportamento
# osservabile finché resta così; tornerebbe rilevante solo se un futuro tipo raccoglibile da terra
# avesse un day_durability finito.
func on_complete(individual: Variant, context: Dictionary) -> void:
	if _quantity_to_collect <= 0:
		return
	if macro_state != null:
		TerrainScatteredResourceService.consume(macro_state, resource_name, target_position, _quantity_to_collect)
	individual.carried_resource_name = resource_name
	individual.carried_quantity += _quantity_to_collect
	individual.carried_decay_fraction = 0.0
	resource_collected.emit(resource_name, target_position, _quantity_to_collect)

	# Ricerca magazzino INIZIALE (2026-09-09, richiesta utente — haul_resource, stesso canale
	# generico usato dal re-routing di UnloadAction.activate, vedi lì per il Dictionary gemello):
	# scritto SOLO quando una raccolta reale è avvenuta (già garantito da _quantity_to_collect > 0,
	# il return anticipato sopra) — resource_name/quantity sono quelli EFFETTIVAMENTE raccolti
	# (_quantity_to_collect, non una stima iniziale: lo zaino era garantito vuoto prima di questo
	# step, vedi activate(), quindi individual.carried_quantity qui sopra vale esattamente questo
	# stesso numero). excluded_building_ids parte vuoto: nessun magazzino ancora tentato.
	#
	# NESSUN "discard_on_failure" qui (a differenza di UnloadAction.activate) — default false in
	# HumanIndividualActionService._handle_pending_warehouse_search: se la ricerca non trova nulla,
	# l'individuo resta semplicemente con la merce in spalla (nessun edificio "vicino da
	# abbandonare" in questo caso, richiesta esplicita utente — non un fallimento distruttivo).
	context["pending_warehouse_search"] = {
		"resource_name": resource_name,
		"quantity": _quantity_to_collect,
		"excluded_building_ids": [],
	}


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
		"quantity_to_collect": _quantity_to_collect,
		"duration": _duration,
		"elapsed": _elapsed,
	}


# Ripristina SOLO il progresso/esito già calcolato da un'activate() precedente (_quantity_to_
# collect/_duration/_elapsed) — MAI target_position/resource_name, già risolti dal costruttore (vedi
# get_save_data sopra). Marca _restored_from_save cosi' la ripetizione di activate() che
# GameLoadService invoca subito dopo (per ripristinare gli effetti collaterali non persistiti delle
# altre Action, es. WalkAction) non sovrascriva questo stato appena ripristinato.
func load_save_data(data: Dictionary) -> void:
	_quantity_to_collect = int(data.get("quantity_to_collect", 0))
	_duration = float(data.get("duration", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
	_restored_from_save = true
