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

# "Prendi tutti i prodotti" (2026-09-24, richiesta utente — popup di prelievo delle workstation):
# valore speciale di resource_name. Invece di una sola risorsa, lo step preleva TUTTE le varietà del
# buffer di uscita (Building.production_output), nei limiti di spazio e di varietà dello zaino
# (HumanIndividual.MAX_CARRIED_VARIETIES) — quanto non entra resta nel buffer. Non tocca MAI
# stored_resources (materiali consegnati per la produzione). Viaggia come un normale resource_name
# attraverso la Transport Task (context, TaskFactory, salvataggio): solo questa classe lo interpreta.
const ALL_PRODUCTS := "__all_products__"

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

# Piano di prelievo in modalità ALL_PRODUCTS (2026-09-24): [{"resource_name", "quantity"}, ...],
# risolto in activate() come _quantity_to_retrieve (che ne diventa la somma). Vuoto negli altri casi.
var _retrieve_plan: Array = []

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
#   spazio_libero  = max_carry_capacity - individual.get_carried_space() (somma di quantity ×
#                    space_per_unit di ogni varietà già trasportata)
#   disponibile    = target_building.stored_resources.get(resource_name, {}).get("quantity", 0)
#   quantità       = min(quantity_requested, floor(spazio_libero / space_per_unit), disponibile)
#   spazio_prelevato = quantità × space_per_unit
# Stessa assunzione esplicita di PickUpAction: l'individuo arriva con lo zaino vuoto
# (carried_resources vuoto) — se non è così, quantità resta 0 (nessuna azione), nessuna gestione mista di due
# risorse diverse in questo step.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if _restored_from_save:
		return

	var free_space: float = individual.max_carry_capacity - individual.get_carried_space()
	_retrieve_plan = []

	if resource_name == ALL_PRODUCTS:
		_activate_all_products(individual, free_space)
		return

	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var space_per_unit: float = resource_rules.space_per_unit if resource_rules != null else 0.0

	var available: int = 0
	if target_building != null:
		# Include il buffer di uscita della produzione (2026-09-23): BuildingStorageService.withdraw
		# preleva da entrambi.
		available = BuildingStorageService.get_available_quantity(target_building, resource_name)

	_quantity_to_retrieve = 0
	if individual.carried_resources.is_empty() and space_per_unit > 0.0:
		_quantity_to_retrieve = max(0, min(quantity_requested, min(int(floor(free_space / space_per_unit)), available)))

	var space_retrieved: float = float(_quantity_to_retrieve) * space_per_unit
	_duration = 0.0
	_total_stamina_cost = 0.0
	if _quantity_to_retrieve > 0 and individual.max_carry_capacity > 0.0:
		_duration = space_retrieved / individual.max_carry_capacity
		_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_retrieved
	_elapsed = 0.0


# Modalità ALL_PRODUCTS (2026-09-24): una voce di piano per ogni varietà del buffer di uscita, in
# ordine di nome, finché c'è spazio e posto per una varietà in più; stessa formula di quantità e di
# costo del ramo singolo (min(disponibile, floor(spazio_libero / space_per_unit)), durata e stamina
# proporzionali allo spazio prelevato in totale). Stessa assunzione di zaino vuoto all'arrivo.
func _activate_all_products(individual: Variant, free_space: float) -> void:
	_quantity_to_retrieve = 0
	_duration = 0.0
	_total_stamina_cost = 0.0
	_elapsed = 0.0
	if target_building == null or not individual.carried_resources.is_empty():
		return
	var output_names: Array[String] = []
	for output_name in target_building.production_output.keys():
		output_names.append(String(output_name))
	output_names.sort()
	var remaining_space: float = free_space
	var space_retrieved: float = 0.0
	for output_name in output_names:
		if _retrieve_plan.size() >= HumanIndividual.MAX_CARRIED_VARIETIES:
			break
		var rules := CaloricCalculator.get_caloric_source_rules(output_name)
		var space_per_unit: float = rules.space_per_unit if rules != null else 0.0
		if space_per_unit <= 0.0:
			continue
		var available: int = int(target_building.production_output.get(output_name, 0))
		var quantity: int = mini(available, int(floor(remaining_space / space_per_unit)))
		if quantity <= 0:
			continue
		_retrieve_plan.append({"resource_name": output_name, "quantity": quantity})
		_quantity_to_retrieve += quantity
		remaining_space -= float(quantity) * space_per_unit
		space_retrieved += float(quantity) * space_per_unit
	if _quantity_to_retrieve > 0 and individual.max_carry_capacity > 0.0:
		_duration = space_retrieved / individual.max_carry_capacity
		_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_retrieved


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
# carried_resources (add_carried_resource) caricato con la quantità EFFETTIVAMENTE prelevata
# (`withdrawn`, il valore di ritorno di withdraw()), MAI _quantity_to_retrieve stesso — richiesta
# esplicita utente: "il chiamante deve sapere quanto ha in spalla l'individuo dopo, non presumere
# sempre la quantità richiesta". In pratica coincidono sempre (nessuna finestra in cui lo stock del
# building possa cambiare tra activate() e questo on_complete(), la Task avanza sempre in modo
# sincrono step-per-step), ma questa Action non fa mai quell'assunzione.
func on_complete(individual: Variant, context: Dictionary) -> void:
	if _quantity_to_retrieve <= 0 or target_building == null:
		return
	if resource_name == ALL_PRODUCTS:
		_complete_all_products(individual)
		return
	var stored_entry: Dictionary = target_building.stored_resources.get(resource_name, {})
	var stored_quantity: int = int(stored_entry.get("quantity", 0))
	var stored_decay_fraction: float = float(stored_entry.get("decay_fraction", 0.0))
	var withdrawn: int = BuildingStorageService.withdraw(target_building, resource_name, _quantity_to_retrieve)
	if withdrawn <= 0:
		return
	# withdraw preleva prima da stored_resources, poi dal buffer di uscita (2026-09-23), dove il prodotto
	# è sempre fresco (0.0): media pesata sulle due parti.
	var from_stored: int = min(withdrawn, stored_quantity)
	var decay_fraction: float = float(from_stored) * stored_decay_fraction / float(withdrawn)
	individual.add_carried_resource(resource_name, withdrawn, decay_fraction)
	resource_retrieved.emit(resource_name, target_building, withdrawn)


# Modalità ALL_PRODUCTS (2026-09-24): preleva ogni voce del piano SOLO dal buffer di uscita
# (ProductionService.withdraw_output, mai stored_resources); il prodotto è sempre fresco (decay 0.0).
# Il resto rimasto nel buffer prova poi il travaso nello storage, come dopo un prelievo normale.
func _complete_all_products(individual: Variant) -> void:
	var any_withdrawn := false
	for entry in _retrieve_plan:
		var output_name: String = String(entry.get("resource_name", ""))
		var withdrawn: int = ProductionService.withdraw_output(target_building, output_name, int(entry.get("quantity", 0)))
		if withdrawn <= 0:
			continue
		var carried: int = individual.add_carried_resource(output_name, withdrawn, 0.0)
		# Mai perdere merce: quanto non entra nello zaino (caso limite) torna nel buffer.
		if carried < withdrawn:
			target_building.production_output[output_name] = int(target_building.production_output.get(output_name, 0)) + (withdrawn - carried)
		if carried > 0:
			any_withdrawn = true
			resource_retrieved.emit(output_name, target_building, carried)
	if any_withdrawn:
		ProductionService.flush_output_to_storage(target_building)


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
		"retrieve_plan": _retrieve_plan,
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
	_retrieve_plan = data.get("retrieve_plan", [])
	_restored_from_save = true
