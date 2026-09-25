class_name ProductionService
extends RefCounted

# Logica pura del sistema di produzione (2026-09-23, richiesta utente — step 4: ProduceAction) —
# funzioni statiche stateless, stesso pattern di BuildingStorageService/ResourceDecayService: opera
# sempre su un Building passato dal chiamante. Vive nel layer di simulazione (non su ProduceAction,
# gameplay/) perché serve a ENTRAMBI i livelli: BuildingStorageService.can_accept/get_max_depositable
# (simulation/) e ProduceAction/GameScene/BuildingInfoPanel (gameplay/) — stesso motivo per cui
# setup_site_material_name vive su BuildingRules e non su SetupSiteAction.
#
# La ricetta è sulla risorsa PRODOTTA (SecondaryResourceRules gruppo Recipe), la capacità
# produttiva sull'edificio (BuildingRules gruppo Production). Lo stato delle produzioni in corso
# vive su Building.production_progress, UN RECORD PER RICETTA (2026-09-24, richiesta utente — più
# ricette contemporanee): {resource_name: {"labor_accumulated": float}}, al più get_queue_capacity
# record. Ogni ProduceAction lavora solo sul record della propria ricetta; più individui sulla
# stessa ricetta sommano il lavoro sullo stesso record. Una ricetta nuova non sovrascrive mai un
# record esistente: se l'edificio è pieno aspetta (start_production ritorna false) finché
# make_room_for non libera un record che nessuno sta più lavorando. Il buffer di uscita resta UNO,
# condiviso da tutte le ricette. Vecchio formato a record singolo convertito da normalize_progress.
#
# Combustibile (recipe_fuel_required/production_fuel_multiplier/fuel_value): gestito dal 2026-09-24,
# vedi la sezione "Combustibile" sotto (get_missing_fuel_for/get_production_demand/_consume_fuel).
#
# BUFFER DI USCITA (2026-09-23, richiesta utente): il prodotto di un ciclo va in
# Building.production_output (a pezzi, capienza BuildingRules.production_output_slots), mai
# direttamente in stored_resources né nello zaino. Se l'edificio ha storage con posto, il buffer si
# travasa lì (flush_output_to_storage: al completamento, dopo ogni prelievo e una volta al giorno);
# a buffer pieno nessun nuovo ciclo avanza né si completa (has_output_room).


# true se `building` può produrre `resource_name` ADESSO: edificio completo, non demolito,
# workstation, e il suo tipo è in recipe_workstation_types della risorsa.
static func can_produce_at(building: Building, resource_name: String) -> bool:
	if building == null or building.rules == null:
		return false
	if building.is_demolished or not building.is_complete or not building.rules.is_workstation:
		return false
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if recipe_rules == null:
		return false
	return recipe_rules.recipe_workstation_types.has(building.building_type_name)


# Nomi delle risorse producibili presso `building` (ordine di list_secondary_resource_names). Vuoto se
# l'edificio non è una workstation valida o nessuna ricetta lo elenca.
static func get_producible_resources(building: Building) -> Array[String]:
	var names: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if can_produce_at(building, resource_name):
			names.append(resource_name)
	return names


# Converte production_progress letto da un salvataggio nel formato a record per ricetta. Il vecchio
# formato a record singolo ({"resource_name": String, "labor_accumulated": float}, save precedenti
# al 2026-09-24) diventa {resource_name: {"labor_accumulated": ...}} senza perdere il progresso.
# Voci non-Dictionary scartate; labor_accumulated sempre float (JSON non distingue int/float).
static func normalize_progress(raw: Dictionary) -> Dictionary:
	var progress: Dictionary = {}
	if raw.has("resource_name") and not (raw["resource_name"] is Dictionary):
		var legacy_name := String(raw["resource_name"])
		if legacy_name != "":
			progress[legacy_name] = {"labor_accumulated": float(raw.get("labor_accumulated", 0.0))}
		return progress
	for resource_name in raw.keys():
		var record: Variant = raw[resource_name]
		if record is Dictionary:
			progress[String(resource_name)] = {"labor_accumulated": float(record.get("labor_accumulated", 0.0))}
	return progress


# Ricette con un record di produzione sull'edificio (ordine di inserimento).
static func get_active_resource_names(building: Building) -> Array[String]:
	var names: Array[String] = []
	if building == null:
		return names
	for resource_name in building.production_progress.keys():
		names.append(String(resource_name))
	return names


static func has_active_production(building: Building) -> bool:
	return building != null and not building.production_progress.is_empty()


# true se `resource_name` ha un record di produzione su `building`.
static func is_recipe_active(building: Building, resource_name: String) -> bool:
	return building != null and building.production_progress.has(resource_name)


# Avvia (o riprende) la produzione di `resource_name`: se il record esiste già il progresso resta
# invariato (ripresa, o un secondo individuo sulla stessa ricetta); altrimenti ne crea uno nuovo a
# zero, SOLO se l'edificio ha ancora un record libero (get_queue_capacity). Ritorna true se il record
# c'è (esistente o appena creato), false se l'edificio è pieno: nessun record altrui viene toccato.
static func start_production(building: Building, resource_name: String) -> bool:
	if building == null or resource_name == "":
		return false
	if building.production_progress.has(resource_name):
		return true
	if building.production_progress.size() >= get_queue_capacity(building):
		return false
	building.production_progress[resource_name] = {"labor_accumulated": 0.0}
	return true


# Libera posto per `resource_name` quando l'edificio ha già tutti i record occupati: rimuove record di
# ricette NON in `claimed_resource_names` (nessuna Produce Task assegnata le sta più lavorando — es.
# resti di una Task annullata), a partire da quello con meno lavoro accumulato, finché non c'è un
# record libero. I record in claimed_resource_names non vengono mai toccati. Chi conosce le Task
# assegnate è il chiamante (GameScene). Ritorna true se c'è posto (o il record esiste già).
static func make_room_for(building: Building, resource_name: String, claimed_resource_names: Array[String]) -> bool:
	if building == null:
		return false
	if building.production_progress.has(resource_name):
		return true
	var capacity := get_queue_capacity(building)
	while building.production_progress.size() >= capacity:
		var evict_name := ""
		var evict_labor := INF
		for active_name in building.production_progress.keys():
			if claimed_resource_names.has(String(active_name)):
				continue
			var labor := get_labor_accumulated(building, String(active_name))
			if labor < evict_labor:
				evict_labor = labor
				evict_name = String(active_name)
		if evict_name == "":
			return false
		building.production_progress.erase(evict_name)
	return true


# Avanzamento del ciclo in corso di `resource_name`, 0.0..1.0 (lavoro accumulato / richiesto) — 0.0
# se il record non esiste o la ricetta non richiede lavoro. Letto dal pannello per le produzioni
# sospese (2026-09-24).
static func get_cycle_progress(building: Building, resource_name: String) -> float:
	var required := get_required_labor(building, resource_name)
	if required <= 0.0:
		return 0.0
	return clampf(get_labor_accumulated(building, resource_name) / required, 0.0, 1.0)


# Lavoro accumulato sul record di `resource_name` (0.0 se il record non esiste).
static func get_labor_accumulated(building: Building, resource_name: String) -> float:
	if building == null:
		return 0.0
	var record: Dictionary = building.production_progress.get(resource_name, {})
	return float(record.get("labor_accumulated", 0.0))


# Aggiunge `amount` di lavoro al record di `resource_name`; no-op se il record non esiste.
static func add_labor(building: Building, resource_name: String, amount: float) -> void:
	if building == null or not building.production_progress.has(resource_name):
		return
	var record: Dictionary = building.production_progress[resource_name]
	record["labor_accumulated"] = float(record.get("labor_accumulated", 0.0)) + amount


# Lavoro richiesto per UN ciclo della ricetta di `resource_name` presso `building` =
# recipe_labor × BuildingRules.production_labor_multiplier. 0.0 se la ricetta non è risolvibile.
static func get_required_labor(building: Building, resource_name: String) -> float:
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if recipe_rules == null:
		return 0.0
	var multiplier: float = building.rules.production_labor_multiplier if building != null and building.rules != null else 1.0
	return recipe_rules.recipe_labor * multiplier


# Materiali mancanti per UN ciclo della ricetta di `resource_name`: recipe_inputs meno quanto c'è
# già in building.stored_resources — {resource_name: missing_quantity}, stessa forma di
# BuildAction.get_missing_materials. Vuoto = nulla manca.
static func get_missing_inputs_for(building: Building, resource_name: String) -> Dictionary:
	var missing: Dictionary = {}
	if building == null:
		return missing
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if recipe_rules == null:
		return missing
	for input_name in recipe_rules.recipe_inputs.keys():
		var required: int = int(recipe_rules.recipe_inputs[input_name])
		if required <= 0:
			continue
		var stored_entry: Dictionary = building.stored_resources.get(input_name, {})
		var stored: int = int(stored_entry.get("quantity", 0))
		var missing_quantity: int = max(required - stored, 0)
		if missing_quantity > 0:
			missing[String(input_name)] = missing_quantity
	return missing


# Materiali mancanti per UN ciclo di OGNI ricetta in corso, insieme: il fabbisogno di un input
# condiviso da più ricette è la SOMMA dei rispettivi recipe_inputs, confrontata con lo storage
# (condiviso anch'esso). Vuoto se nessuna produzione è in corso o nulla manca. Usato da
# BuildingStorageService (quanto accettare) e dal pannello (cosa manca).
static func get_missing_inputs(building: Building) -> Dictionary:
	return get_missing_inputs_for_recipes(building, get_active_resource_names(building))


# Come get_missing_inputs, ma solo per le ricette in `recipe_names` (2026-09-24 — il pannello mostra
# il fabbisogno delle sole produzioni con una Task che ci lavora, non di quelle sospese).
static func get_missing_inputs_for_recipes(building: Building, recipe_names: Array[String]) -> Dictionary:
	var missing: Dictionary = {}
	if building == null:
		return missing
	var required_totals: Dictionary = {}
	for active_name in recipe_names:
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(String(active_name))
		if recipe_rules == null:
			continue
		for input_name in recipe_rules.recipe_inputs.keys():
			var required: int = int(recipe_rules.recipe_inputs[input_name])
			if required > 0:
				required_totals[String(input_name)] = int(required_totals.get(String(input_name), 0)) + required
	for input_name in required_totals.keys():
		var stored_entry: Dictionary = building.stored_resources.get(input_name, {})
		var missing_quantity: int = max(int(required_totals[input_name]) - int(stored_entry.get("quantity", 0)), 0)
		if missing_quantity > 0:
			missing[input_name] = missing_quantity
	return missing


# --- Combustibile (2026-09-24, richiesta utente) ---
# Una ricetta con recipe_fuel_required > 0 richiede, oltre ai materiali, un valore combustibile pari a
# recipe_fuel_required × BuildingRules.production_fuel_multiplier. Lo si copre con le risorse in
# building.stored_resources che hanno fuel_value > 0: quantità × fuel_value sommate. Le unità che la
# stessa ricetta usa come MATERIALE (es. lo stick della lancia di legno) non contano come
# combustibile: vengono riservate prima (reserved_inputs), così una risorsa non è mai contata due
# volte. Al completamento il combustibile si consuma a unità intere (per difetto mai: si arrotonda
# per eccesso), decrementando la quantità esatta — vedi _consume_fuel.

const FUEL_EPSILON: float = 0.0001


# Valore combustibile richiesto da UN ciclo della ricetta di `resource_name` presso `building`.
static func get_required_fuel(building: Building, resource_name: String) -> float:
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if recipe_rules == null or recipe_rules.recipe_fuel_required <= 0.0:
		return 0.0
	var multiplier: float = building.rules.production_fuel_multiplier if building != null and building.rules != null else 1.0
	return recipe_rules.recipe_fuel_required * multiplier


# fuel_value di UNA unità di `resource_name` (0.0 = non combustibile o risorsa sconosciuta).
static func get_fuel_value(resource_name: String) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules.fuel_value if rules != null else 0.0


# Valore combustibile disponibile nello storage, escluse le unità riservate come materiali
# (`reserved_inputs`: {resource_name: quantità}).
static func get_available_fuel(building: Building, reserved_inputs: Dictionary = {}) -> float:
	if building == null:
		return 0.0
	var available := 0.0
	for stored_name in building.stored_resources.keys():
		var fuel_value := get_fuel_value(String(stored_name))
		if fuel_value <= 0.0:
			continue
		var stored_entry: Dictionary = building.stored_resources[stored_name]
		var usable: int = max(int(stored_entry.get("quantity", 0)) - int(reserved_inputs.get(stored_name, 0)), 0)
		available += float(usable) * fuel_value
	return available


# Combustibile mancante per UN ciclo della ricetta di `resource_name` (0.0 = coperto o non richiesto).
static func get_missing_fuel_for(building: Building, resource_name: String) -> float:
	var required := get_required_fuel(building, resource_name)
	if required <= 0.0:
		return 0.0
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var missing := required - get_available_fuel(building, recipe_rules.recipe_inputs)
	return missing if missing > FUEL_EPSILON else 0.0


# Combustibile mancante per UN ciclo di OGNI ricetta in corso, insieme (fabbisogni sommati, materiali
# di tutte le ricette in corso riservati) — stessa logica aggregata di get_missing_inputs. Usato da
# BuildingStorageService (quanto accettare) e dal pannello.
static func get_missing_fuel(building: Building) -> float:
	return get_missing_fuel_for_recipes(building, get_active_resource_names(building))


# Come get_missing_fuel, ma solo per le ricette in `recipe_names` (2026-09-24, vedi
# get_missing_inputs_for_recipes).
static func get_missing_fuel_for_recipes(building: Building, recipe_names: Array[String]) -> float:
	if building == null:
		return 0.0
	var required := 0.0
	var reserved: Dictionary = {}
	for active_name in recipe_names:
		required += get_required_fuel(building, String(active_name))
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(String(active_name))
		if recipe_rules == null:
			continue
		for input_name in recipe_rules.recipe_inputs.keys():
			reserved[input_name] = int(reserved.get(input_name, 0)) + int(recipe_rules.recipe_inputs[input_name])
	if required <= 0.0:
		return 0.0
	var missing := required - get_available_fuel(building, reserved)
	return missing if missing > FUEL_EPSILON else 0.0


# true se almeno una ricetta in corso richiede combustibile.
static func requires_fuel(building: Building) -> bool:
	for active_name in get_active_resource_names(building):
		if get_required_fuel(building, active_name) > 0.0:
			return true
	return false


# true se `resource_name` serve alle produzioni in corso: materiale di una ricetta, oppure
# combustibile (fuel_value > 0) quando almeno una ricetta ne richiede. In quel caso
# BuildingStorageService la accetta solo fino a get_production_demand, come un cantiere.
static func is_production_demand(building: Building, resource_name: String) -> bool:
	if is_active_recipe_input(building, resource_name):
		return true
	return get_fuel_value(resource_name) > 0.0 and requires_fuel(building)


# Unità di `resource_name` che mancano alle produzioni in corso: materiale mancante + unità intere
# necessarie a coprire il combustibile mancante (se è un combustibile). 0 = nulla da accettare.
static func get_production_demand(building: Building, resource_name: String) -> int:
	var demand: int = int(get_missing_inputs(building).get(resource_name, 0))
	var fuel_value := get_fuel_value(resource_name)
	if fuel_value > 0.0:
		var missing_fuel := get_missing_fuel(building)
		if missing_fuel > 0.0:
			demand += int(ceil(missing_fuel / fuel_value - FUEL_EPSILON))
	return demand


# Brucia combustibile dallo storage fino a coprire `required`: prima le risorse con fuel_value più
# alto (meno unità consumate), a parità in ordine di nome; unità intere, decremento esatto via
# BuildingStorageService.withdraw_stored (la voce sparisce solo se arriva a 0). Chiamata DOPO il
# prelievo dei materiali della ricetta, così non tocca le unità appena consumate come materiale.
static func _consume_fuel(building: Building, required: float) -> void:
	if required <= 0.0:
		return
	var fuel_names: Array[String] = []
	for stored_name in building.stored_resources.keys():
		if get_fuel_value(String(stored_name)) > 0.0:
			fuel_names.append(String(stored_name))
	fuel_names.sort_custom(func(a: String, b: String) -> bool:
		var value_a := get_fuel_value(a)
		var value_b := get_fuel_value(b)
		return value_a > value_b if value_a != value_b else a < b
	)
	var remaining := required
	for fuel_name in fuel_names:
		if remaining <= FUEL_EPSILON:
			break
		var fuel_value := get_fuel_value(fuel_name)
		var stored_entry: Dictionary = building.stored_resources.get(fuel_name, {})
		var units: int = mini(int(stored_entry.get("quantity", 0)), int(ceil(remaining / fuel_value - FUEL_EPSILON)))
		if units <= 0:
			continue
		var burned := BuildingStorageService.withdraw_stored(building, fuel_name, units)
		remaining -= float(burned) * fuel_value


# true se `input_name` è un materiale di almeno una ricetta in corso — letto da
# BuildingStorageService per decidere se applicare il vincolo "quantità esatta mancante".
static func is_active_recipe_input(building: Building, input_name: String) -> bool:
	if building == null:
		return false
	for active_name in building.production_progress.keys():
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(String(active_name))
		if recipe_rules != null and recipe_rules.recipe_inputs.has(input_name):
			return true
	return false


# Tetto di Produce Task contemporanee sull'edificio (BuildingRules.production_queue_slots, minimo 1)
# — 2026-09-24, richiesta utente. Chi conta le Task assegnate è il chiamante (GameScene: questo layer
# non vede individui/Task); qui solo il confronto, così pannello e assegnazione usano la stessa regola.
static func get_queue_capacity(building: Building) -> int:
	if building == null or building.rules == null:
		return 1
	return max(building.rules.production_queue_slots, 1)


# true se l'edificio non accetta un'altra Produce Task: `assigned_count` (Task già assegnate, attive
# o in coda, anche con l'individuo non ancora arrivato) ha raggiunto get_queue_capacity.
static func is_production_queue_full(building: Building, assigned_count: int) -> bool:
	return assigned_count >= get_queue_capacity(building)


# Pezzi ordinabili con un solo comando (BuildingRules.production_max_quantity, minimo 1).
static func get_max_order_quantity(building: Building) -> int:
	if building == null or building.rules == null:
		return 1
	return max(building.rules.production_max_quantity, 1)


# Capienza del buffer di uscita, in pezzi (BuildingRules.production_output_slots).
static func get_output_capacity(building: Building) -> int:
	if building == null or building.rules == null:
		return 0
	return max(building.rules.production_output_slots, 0)


# Pezzi attualmente nel buffer di uscita (somma di tutte le risorse).
static func get_output_used(building: Building) -> int:
	if building == null:
		return 0
	var used := 0
	for output_name in building.production_output.keys():
		used += int(building.production_output[output_name])
	return used


# true se il buffer di uscita può ricevere un ciclo intero della ricetta di `resource_name`
# (recipe_output_quantity pezzi). false = buffer pieno: il ciclo non avanza né si completa finché
# non viene svuotato (Retrieve, o travaso nello storage).
static func has_output_room(building: Building, resource_name: String) -> bool:
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if recipe_rules == null:
		return false
	return get_output_used(building) + max(recipe_rules.recipe_output_quantity, 0) <= get_output_capacity(building)


# true se il buffer (condiviso) non ha posto per un ciclo di almeno una ricetta in corso — letto da
# BuildingInfoPanel per l'avviso.
static func is_output_blocking(building: Building) -> bool:
	for active_name in get_active_resource_names(building):
		if not has_output_room(building, active_name):
			return true
	return false


# Travasa il buffer di uscita nello storage normale dell'edificio, per quanto c'è posto
# (BuildingStorageService.store: slot, filtri di categoria). Il prodotto entra a decay_fraction 0.0.
# No-op per un edificio senza storage (campfire: il buffer resta pieno finché non lo si svuota) o con
# buffer vuoto. Chiamata al completamento di un ciclo, dopo ogni prelievo (BuildingStorageService.
# withdraw) e una volta al giorno (WorldTimeService), così il buffer si svuota appena si libera spazio.
static func flush_output_to_storage(building: Building) -> void:
	if building == null or building.production_output.is_empty() or BuildingStorageService.get_capacity(building) <= 0:
		return
	var emptied: Array[String] = []
	for output_name in building.production_output.keys():
		var quantity: int = int(building.production_output[output_name])
		var stored := BuildingStorageService.store(building, String(output_name), quantity, 0.0)
		if stored >= quantity:
			emptied.append(String(output_name))
		elif stored > 0:
			building.production_output[output_name] = quantity - stored
	for output_name in emptied:
		building.production_output.erase(output_name)


# Preleva fino a `quantity_requested` pezzi di `resource_name` dal buffer di uscita. Ritorna quanto
# è stato prelevato davvero; la voce sparisce quando arriva a 0. Usata da BuildingStorageService.
# withdraw (il buffer è una normale sorgente per Retrieve/Transport).
static func withdraw_output(building: Building, resource_name: String, quantity_requested: int) -> int:
	if building == null or quantity_requested <= 0:
		return 0
	var current: int = int(building.production_output.get(resource_name, 0))
	var withdrawn: int = min(quantity_requested, current)
	if withdrawn <= 0:
		return 0
	if current - withdrawn <= 0:
		building.production_output.erase(resource_name)
	else:
		building.production_output[resource_name] = current - withdrawn
	return withdrawn


# Conclude UN ciclo della ricetta `active_name`: consuma la quantità ESATTA di ogni input (decremento
# via BuildingStorageService.withdraw — la voce sparisce solo se arriva a 0, a differenza del
# consumo della Build che cancella l'intera voce), aggiunge recipe_output_quantity della risorsa
# prodotta al buffer di uscita (Building.production_output), rimuove SOLO il record di questa
# ricetta (gli altri restano intatti) e prova il travaso nello storage. Ritorna la quantità prodotta
# (0 se non c'era nulla da concludere: nessun record per la ricetta, ricetta irrisolvibile, materiali
# insufficienti per QUESTA ricetta, combustibile non coperto o buffer pieno — mai un consumo
# parziale). Il combustibile si brucia dopo i materiali (_consume_fuel).
static func complete_production(building: Building, active_name: String) -> int:
	if not is_recipe_active(building, active_name):
		return 0
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(active_name)
	if recipe_rules == null or not get_missing_inputs_for(building, active_name).is_empty() or not has_output_room(building, active_name):
		return 0
	# Combustibile (2026-09-24): senza copertura completa nessun consumo, come per i materiali.
	if get_missing_fuel_for(building, active_name) > 0.0:
		return 0
	for input_name in recipe_rules.recipe_inputs.keys():
		var required: int = int(recipe_rules.recipe_inputs[input_name])
		if required > 0:
			# Solo da stored_resources: gli input non stanno mai nel buffer di uscita.
			BuildingStorageService.withdraw_stored(building, String(input_name), required)
	_consume_fuel(building, get_required_fuel(building, active_name))

	var produced: int = max(recipe_rules.recipe_output_quantity, 0)
	if produced > 0:
		building.production_output[active_name] = int(building.production_output.get(active_name, 0)) + produced
	building.production_progress.erase(active_name)
	flush_output_to_storage(building)
	return produced
