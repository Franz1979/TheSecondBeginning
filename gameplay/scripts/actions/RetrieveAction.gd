class_name RetrieveAction
extends Action

# Operazione simmetrica di UnloadAction ramo RESOURCE, ma in PRELIEVO invece che in deposito
# (2026-09-12, richiesta utente) — preleva una quantità di resource_name da target_building.
# stored_resources tramite BuildingStorageService.withdraw() (nuovo, vedi lì), invece di raccoglierla
# da terreno sparso come PickUpAction (TerrainScatteredResourceService). Pensata per due usi: (1)
# prelevare da un magazzino per portare merce altrove, (2) recuperare materiale già consegnato a un
# cantiere ABORTITO (target_building con is_complete == false) — per questo BuildingStorageService.
# withdraw() non ha alcun guard is_complete/is_demolished, a differenza di store()/can_accept()/
# get_max_depositable() usati per il DEPOSITO.
#
# Bersaglio TEMPORALE come PickUpAction/ThinkAction (un accumulatore _elapsed confrontato con
# _duration, stesso schema esatto — vedi get_stamina_delta/is_complete sotto), con target_building
# che identifica DOVE prelevare (non un movimento: l'individuo deve già essere lì, garantito da un
# WalkAction precedente nella stessa Task, stesso principio già seguito da UnloadAction/PickUpAction).
#
# NESSUN side-effect automatico tipo "cerca dove scaricare" (2026-09-12, richiesta utente, DEVIAZIONE
# deliberata da PickUpAction.on_complete, che scrive SEMPRE context["pending_warehouse_search"] dopo
# una raccolta riuscita) — chi costruisce la Task decide esplicitamente il prossimo step (Walk verso
# la destinazione, Unload lì), questa Action si limita a prelevare e basta.

# Costo stamina TOTALE = questo × spazio_prelevato — STESSO valore/STESSA formula di
# PickUpAction.STAMINA_COST_PER_SPACE_UNIT (richiesta esplicita utente: "verifica la formula esatta
# in PickUpAction e replicala identica, non inventare un nuovo coefficiente"). Costante SEPARATA
# (non condivisa/importata), stesso principio già seguito ovunque nel progetto: nessuna costante
# condivisa tra Action diverse.
const STAMINA_COST_PER_SPACE_UNIT: float = 2.0


# Emesso da on_complete() SOLO quando un prelievo reale è avvenuto (_quantity_to_retrieve > 0 E
# BuildingStorageService.withdraw ha davvero restituito qualcosa) — stesso principio di
# disaccoppiamento di PickUpAction.resource_collected/UnloadAction.resource_deposited: questa classe
# non conosce MicroCellRenderer/BuildingInfoPanel/GameScene, si limita a segnalare "ho prelevato
# `quantity` unità di `resource_name` da `building`", chi crea la Task decide se/come rinfrescare il
# disegno (es. la griglia di stoccaggio del pannello edificio, stesso consumatore di
# resource_deposited).
signal resource_retrieved(resource_name: String, building: Building, quantity: int)

var target_building: Building = null
var resource_name: String = ""
# Quantità RICHIESTA (2026-09-12, richiesta utente) — NON garantita: se target_building non ne ha
# abbastanza (o lo zaino dell'individuo non ha spazio sufficiente), _quantity_to_retrieve sotto
# risulta minore. Il chiamante non deve mai assumere che l'individuo torni con esattamente questa
# quantità in spalla.
var quantity_requested: int = 0

# Quantità che questo step preleverà davvero — risolta in activate() (mai ricalcolata dopo), stesso
# principio esatto di PickUpAction._quantity_to_collect. 0 = niente da prelevare (building senza
# quella risorsa, zaino già occupato da un'altra risorsa, o quantity_requested <= 0) — stesso
# significato di "azione immediatamente completa" già richiesto per PickUpAction.
var _quantity_to_retrieve: int = 0

# Stesso schema esatto di PickUpAction._duration/_total_stamina_cost/_elapsed — vedi lì per il
# perché (ThinkAction generalizzato a un costo/tasso non costante, ma dipendente dallo spazio
# prelevato invece che una costante di classe).
var _duration: float = 0.0
var _total_stamina_cost: float = 0.0
var _elapsed: float = 0.0

# Guardia persistenza — STESSO principio/STESSO motivo di PickUpAction._restored_from_save: senza
# questa guardia, un salvataggio a metà prelievo perderebbe silenziosamente _elapsed (progresso già
# maturato) al reload, dato che GameLoadService richiama SEMPRE activate() sullo step corrente subito
# dopo la deserializzazione.
var _restored_from_save: bool = false


func _init(p_target_building: Building, p_resource_name: String, p_quantity_requested: int) -> void:
	target_building = p_target_building
	resource_name = p_resource_name
	quantity_requested = p_quantity_requested
	target = null
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands). CHILD aggiunto 2026-09-13 (richiesta
	# utente).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Risolve UNA VOLTA (mai più ricalcolato dopo, stesso principio di PickUpAction.activate) quanto
# verrà prelevato — STESSA identica formula di PickUpAction, con l'unica differenza della fonte
# "disponibile" (target_building.stored_resources invece di TerrainScatteredResourceService):
#   spazio_libero  = max_carry_capacity - (carried_quantity × space_per_unit della risorsa già
#                    trasportata, se presente)
#   disponibile    = target_building.stored_resources.get(resource_name, {}).get("quantity", 0)
#   quantità       = min(quantity_requested, floor(spazio_libero / space_per_unit), disponibile)
#   spazio_prelevato = quantità × space_per_unit
# Stessa assunzione esplicita di PickUpAction: l'individuo arriva con carried_resource_name == ""
# (zaino vuoto) — se non è così, quantità resta 0 (nessuna azione), nessuna gestione mista di due
# risorse diverse in questo step.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
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
	if target_building != null:
		var stored_entry: Dictionary = target_building.stored_resources.get(resource_name, {})
		available = int(stored_entry.get("quantity", 0))

	_quantity_to_retrieve = 0
	if individual.carried_resource_name == "" and space_per_unit > 0.0:
		_quantity_to_retrieve = max(0, min(quantity_requested, min(int(floor(free_space / space_per_unit)), available)))

	var space_retrieved: float = float(_quantity_to_retrieve) * space_per_unit
	_duration = 0.0
	_total_stamina_cost = 0.0
	if _quantity_to_retrieve > 0 and individual.max_carry_capacity > 0.0:
		_duration = space_retrieved / individual.max_carry_capacity
		_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_retrieved
	_elapsed = 0.0


# Stesso schema esatto di PickUpAction.get_stamina_delta/is_complete — unica differenza: il tasso
# non è una costante di classe ma _total_stamina_cost/_duration, risolto in activate() per QUESTA
# istanza. _duration <= 0.0 (quantità 0, "azione immediatamente completa, nessun costo, nessuna
# durata") non incrementa _elapsed e ritorna 0.0 — is_complete() sotto torna comunque vero da subito
# (0.0 >= 0.0).
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _duration <= 0.0:
		return 0.0
	_elapsed += delta
	return -(_total_stamina_cost / _duration) * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= _duration


# get_required_position (2026-09-13, richiesta utente — fix "Walk di ritorno alla ripresa", vedi
# Action.get_required_position) — null se target_building non risolvibile (nessuna posizione da
# imporre, stesso trattamento difensivo già seguito da on_complete sopra). Altrimenti converte la
# posizione LOCALE dell'edificio (target_building.micro_x/y, relativa alla SUA macrocella
# OSPITANTE) nel sistema di coordinate GLOBALE di individual.position — STESSA identica formula
# già in uso in UnloadAction.on_complete (ramo fisico) per "cammina via dopo il deposito",
# duplicata qui apposta (nessuna costante/funzione condivisa tra Action diverse, stesso principio
# già seguito ovunque in questo sistema).
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(target_building.micro_x, target_building.micro_y) + macro_offset


# Preleva DAVVERO tramite BuildingStorageService.withdraw() — no-op se _quantity_to_retrieve è 0 o
# target_building è null, stesso principio "istantaneo senza effetti" di PickUpAction.on_complete
# quando _quantity_to_collect è 0.
#
# decay_fraction letta DA target_building.stored_resources PRIMA di chiamare withdraw() (2026-09-12,
# richiesta utente — coerenza col decadimento, DEVIAZIONE deliberata da PickUpAction, che invece
# forza sempre 0.0: lì la fonte, terreno sparso, non traccia mai un decadimento reale; qui invece
# target_building.stored_resources SÌ, vedi ResourceDecayService.advance_building_decay — ignorarla
# resetterebbe silenziosamente a "fresco" merce già parzialmente deperita) — withdraw() non la
# restituisce esplicitamente (lascia la entry residua invariata, stesso principio "lotto unico" di
# store(): prelevare una PARTE non cambia la media di quella che resta, quindi la media di quella
# prelevata è la STESSA), va letta a parte da chi chiama, PRIMA che l'eventuale svuotamento della
# entry (quantità residua a 0) la rimuova dal Dictionary.
#
# carried_quantity/carried_resource_name caricati con la quantità EFFETTIVAMENTE prelevata
# (`withdrawn`, il valore di ritorno di withdraw()), MAI _quantity_to_retrieve stesso — richiesta
# esplicita utente: "il chiamante deve sapere quanto ha in spalla l'individuo dopo, non presumere
# sempre la quantità richiesta". In pratica coincidono sempre (nessuna finestra in cui lo stock del
# building possa cambiare tra activate() e questo on_complete(), la Task avanza sempre in modo
# sincrono step-per-step), ma questa Action non fa mai quell'assunzione.
func on_complete(individual: Variant, context: Dictionary) -> void:
	if _quantity_to_retrieve <= 0 or target_building == null:
		return
	var stored_entry: Dictionary = target_building.stored_resources.get(resource_name, {})
	var decay_fraction: float = float(stored_entry.get("decay_fraction", 0.0))
	var withdrawn: int = BuildingStorageService.withdraw(target_building, resource_name, _quantity_to_retrieve)
	if withdrawn <= 0:
		return
	individual.carried_resource_name = resource_name
	individual.carried_quantity += withdrawn
	individual.carried_decay_fraction = decay_fraction
	resource_retrieved.emit(resource_name, target_building, withdrawn)


# Persistenza — STESSO schema esatto di PickUpAction.get_save_data/load_save_data, con l'aggiunta di
# target_building (via id, stesso principio già seguito da UnloadAction/SetupSiteAction/ClearAction/
# BuildAction: Building non è serializzabile per riferimento, JSON non trasporta oggetti vivi) e di
# total_stamina_cost — quest'ultimo persistito ESPLICITAMENTE a differenza di PickUpAction (che non
# lo fa, gap noto e commentato in unload_action.gd — "un gap preesistente non toccato qui, ma non
# replicato in questa classe"): la formula di costo richiesta va replicata identica, non il suo gap
# di persistenza, stesso principio già scelto da UnloadAction. quantity_requested/resource_name qui
# SOLO per ricostruire il costruttore (vedi TaskPersistenceService._build_step) — la vera quantità in
# corso resta quantity_to_retrieve.
func get_save_data() -> Dictionary:
	var data := {
		"resource_name": resource_name,
		"quantity_requested": quantity_requested,
		"quantity_to_retrieve": _quantity_to_retrieve,
		"duration": _duration,
		"elapsed": _elapsed,
		"total_stamina_cost": _total_stamina_cost,
	}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


# Ripristina SOLO il progresso/esito già calcolato da un'activate() precedente — MAI target_building/
# resource_name/quantity_requested, già risolti dal costruttore (vedi get_save_data sopra e
# TaskPersistenceService._build_step). Marca _restored_from_save cosi' la ripetizione di activate()
# che GameLoadService invoca subito dopo (per ripristinare gli effetti collaterali non persistiti
# delle altre Action, es. WalkAction) non sovrascriva questo stato appena ripristinato.
func load_save_data(data: Dictionary) -> void:
	_quantity_to_retrieve = int(data.get("quantity_to_retrieve", 0))
	_duration = float(data.get("duration", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
	_total_stamina_cost = float(data.get("total_stamina_cost", 0.0))
	_restored_from_save = true
