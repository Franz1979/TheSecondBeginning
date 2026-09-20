class_name RestockPouchAction
extends Action

# Riempie le provviste (food_space_used / food_calories_held) e ripristina la riserva corporea
# (body_calories) prelevando cibo da un edificio (2026-09-19, richiesta utente). NON passa dallo zaino: preleva DIRETTAMENTE dal magazzino alle
# provviste, cosi' un individuo puo' rifornirsi anche mentre trasporta qualcosa (lo zaino serve al
# trasporto e RetrieveAction funziona solo a zaino vuoto).
#
# RISERVA CORPOREA (2026-09-19, richiesta utente): nella stessa sosta l'individuo prima ricostituisce
# body_calories fino a body_calories_capacity e poi riempie le provviste. All'attivazione chiede a
# FoodSelectionService.select_food(edificio, spazio libero delle provviste, calorie mancanti alla
# riserva): la selezione ha due gruppi (riserva, che ha la precedenza se il cibo non basta, e
# provviste). La riserva non occupa spazio: le calorie del gruppo riserva vanno a body_calories fino
# al massimo; l'eventuale eccedenza (meno di un'unita') passa alle provviste con lo spazio
# proporzionale. Durata: quella delle provviste piu' BODY_RESTORE_DURATION_PER_CALORIE per ogni caloria
# di riserva ripristinata.
#
# Provviste: select_food(target_building, spazio libero delle
# provviste = food_space_capacity - food_space_used); in on_complete toglie le quantita' scelte dal
# magazzino con BuildingStorageService.withdraw e somma spazio e calorie prelevati a
# food_space_used/food_calories_held. Se select_food non sceglie nulla (magazzino svuotato nel
# frattempo, provviste gia' piene) l'azione "fallisce": durata 0, completa subito e NON modifica
# niente - stesso comportamento di RetrieveAction con quantita' 0.
#
# Bersaglio TEMPORALE come RetrieveAction (accumulatore _elapsed confrontato con _duration), con
# target_building che identifica DOVE prelevare: l'individuo deve gia' essere sulla microcella
# dell'edificio (get_required_position, garantito da un WalkAction precedente nella stessa Task).
# Durata e costo stamina sullo schema di RetrieveAction ma DIMEZZATI (2026-09-19, richiesta utente):
# durata = DURATION_FACTOR (0.5) x spazio prelevato / max_carry_capacity, costo stamina totale =
# STAMINA_COST_PER_SPACE_UNIT (1.0, meta' di RetrieveAction) x spazio prelevato. Non
# ammette INFANT. Nessuna Task la usa ancora.

# META' di RetrieveAction.STAMINA_COST_PER_SPACE_UNIT (2.0): 1.0 per unita' di spazio (richiesta utente).
# Costante SEPARATA, nessuna costante condivisa tra Action diverse, come nel resto del progetto.
const STAMINA_COST_PER_SPACE_UNIT: float = 1.0

# Fattore sulla durata di RetrieveAction a parita' di spazio (spazio / max_carry_capacity): 0.5 = la
# meta' del tempo (richiesta utente).
const DURATION_FACTOR: float = 0.5

# Tempo aggiuntivo per OGNI caloria di riserva corporea ripristinata (2026-09-19, richiesta utente:
# "mangiare tanto richiede tempo"): si SOMMA alla durata delle provviste. Stessa unita' della durata
# (frazione di giorno di gioco): 0.001 -> ripristinare le 200 calorie di una riserva vuota aggiunge
# 0.2. Valore iniziale da tarare. Non aggiunge costo di stamina (resta proporzionale allo spazio
# prelevato per le provviste).
const BODY_RESTORE_DURATION_PER_CALORIE: float = 0.001


# Emesso da on_complete() SOLO quando un rifornimento reale e' avvenuto (almeno un'unita' davvero
# prelevata) - stesso principio di RetrieveAction.resource_retrieved: chi crea la Task decide se/come
# rinfrescare il disegno/il pannello. `quantities`: nome risorsa -> unita' effettivamente prelevate.
signal pouch_restocked(building: Building, quantities: Dictionary)

var target_building: Building = null

# Esito di FoodSelectionService.select_food calcolato in activate(): {"quantities", "space_used",
# "calories"}. Vuoto = niente da prelevare.
var _selection: Dictionary = {}
var _duration: float = 0.0
var _total_stamina_cost: float = 0.0
var _elapsed: float = 0.0
# true dopo load_save_data: activate() non deve ricalcolare la scelta (stessa logica di
# RetrieveAction._restored_from_save).
var _restored_from_save: bool = false


func _init(p_target_building: Building = null) -> void:
	target_building = p_target_building
	target = null
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if _restored_from_save:
		return
	var free_space: float = maxf(individual.food_space_capacity - individual.food_space_used, 0.0)
	var body_deficit: float = maxf(individual.body_calories_capacity - individual.body_calories, 0.0)
	_selection = FoodSelectionService.select_food(target_building, free_space, body_deficit)
	var space_to_take: float = float(_selection.get("space_used", 0.0))
	_duration = 0.0
	_total_stamina_cost = 0.0
	if space_to_take > 0.0 and individual.max_carry_capacity > 0.0:
		_duration = DURATION_FACTOR * space_to_take / individual.max_carry_capacity
		_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_to_take
	# Quota di durata per la riserva: calorie che la selezione destina alla riserva, al massimo quelle
	# davvero mancanti.
	var body_restore: float = minf(float(_selection.get("body_calories", 0.0)), body_deficit)
	_duration += BODY_RESTORE_DURATION_PER_CALORIE * body_restore
	_elapsed = 0.0


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _duration <= 0.0:
		return 0.0
	_elapsed += delta
	return -(_total_stamina_cost / _duration) * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= _duration


# Stessa formula di RetrieveAction.get_required_position: posizione dell'edificio nello spazio locale
# di individual.home_macro_coords.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(target_building.micro_x, target_building.micro_y) + macro_offset


# Toglie dal magazzino le quantita' scelte (gruppo riserva + gruppo provviste, sommati per risorsa) e
# distribuisce quanto EFFETTIVAMENTE prelevato (withdraw puo' restituire meno del richiesto se lo stock
# e' cambiato dopo activate: la riserva ha la precedenza, la mancanza ricade sulle provviste).
#   - le calorie del gruppo riserva vanno a body_calories fino al massimo (calcolato al momento del
#     completamento); l'eccedenza passa alle provviste, con lo spazio del gruppo riserva in
#     proporzione (l'ultima unita' puo' superare il mancante di meno di un'unita');
#   - spazio e calorie del gruppo provviste vanno a food_space_used/food_calories_held; se il totale
#     supera la capacita' (ricalcolata nel frattempo) HumanFoodPouchService.clamp_to_capacity riduce
#     in proporzione.
# Selezione vuota o edificio nullo -> non modifica niente.
func on_complete(individual: Variant, context: Dictionary) -> void:
	var pouch_quantities: Dictionary = _selection.get("quantities", {})
	var body_quantities: Dictionary = _selection.get("body_quantities", {})
	var space_before: float = individual.food_space_used
	var calories_before: float = individual.food_calories_held
	var body_before: float = individual.body_calories
	if target_building == null or (pouch_quantities.is_empty() and body_quantities.is_empty()):
		_log_completion(individual, {}, space_before, calories_before, body_before, 0.0, 0.0)
		return
	var resource_names: Array = []
	for resource_name in body_quantities.keys():
		resource_names.append(String(resource_name))
	for resource_name in pouch_quantities.keys():
		if not resource_names.has(String(resource_name)):
			resource_names.append(String(resource_name))
	var withdrawn_quantities: Dictionary = {}
	var body_calories_taken: float = 0.0
	var body_space_taken: float = 0.0
	var pouch_calories_added: float = 0.0
	var pouch_space_added: float = 0.0
	for resource_name in resource_names:
		var requested_body: int = int(body_quantities.get(resource_name, 0))
		var requested_pouch: int = int(pouch_quantities.get(resource_name, 0))
		var withdrawn: int = BuildingStorageService.withdraw(target_building, resource_name, requested_body + requested_pouch)
		if withdrawn <= 0:
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null:
			continue
		withdrawn_quantities[resource_name] = withdrawn
		var body_units: int = mini(requested_body, withdrawn)
		var pouch_units: int = mini(requested_pouch, withdrawn - body_units)
		body_calories_taken += float(body_units) * rules.calories_per_unit
		body_space_taken += float(body_units) * rules.space_per_unit
		pouch_calories_added += float(pouch_units) * rules.calories_per_unit
		pouch_space_added += float(pouch_units) * rules.space_per_unit
	if withdrawn_quantities.is_empty():
		_log_completion(individual, {}, space_before, calories_before, body_before, 0.0, 0.0)
		return
	var body_deficit: float = maxf(individual.body_calories_capacity - individual.body_calories, 0.0)
	var body_gain: float = minf(body_calories_taken, body_deficit)
	individual.body_calories += body_gain
	var body_overflow: float = body_calories_taken - body_gain
	if body_overflow > 0.0 and body_calories_taken > 0.0:
		pouch_calories_added += body_overflow
		pouch_space_added += body_space_taken * body_overflow / body_calories_taken
	individual.food_space_used += pouch_space_added
	individual.food_calories_held += pouch_calories_added
	HumanFoodPouchService.clamp_to_capacity(individual)
	_log_completion(individual, withdrawn_quantities, space_before, calories_before, body_before, body_gain, pouch_calories_added)
	pouch_restocked.emit(target_building, withdrawn_quantities)


# Log diagnostico del completamento (DebugLogging.SHOW_RESTOCK_LOGS, filtro per individuo
# RESTOCK_LOG_INDIVIDUAL_ID, -1 = tutti): quantita' prelevate per risorsa, spazio e calorie prima/dopo,
# e (2026-09-19) le calorie andate alla riserva corporea (con la riserva prima/dopo e il massimo) e
# quelle andate alle provviste. `withdrawn` vuoto = niente prelevato (selezione vuota o stock svuotato
# nel frattempo).
func _log_completion(
	individual: Variant, withdrawn: Dictionary, space_before: float, calories_before: float,
	body_before: float, body_gain: float, pouch_calories_added: float
) -> void:
	if not DebugLogging.should_log_restock(int(individual.id)):
		return
	print("[RESTOCK] #%d %s: rifornimento da %s %s - prelevato=%s spazio %.2f->%.2f (capacita=%.2f) calorie %.2f->%.2f | calorie_riserva=+%.2f (riserva %.2f->%.2f, max=%.2f) calorie_provviste=+%.2f" % [
		individual.id, individual.name,
		target_building.building_type_name if target_building != null else "(nessun edificio)",
		("#%d" % target_building.id) if target_building != null else "",
		str(withdrawn) if not withdrawn.is_empty() else "niente (nulla da prelevare)",
		space_before, individual.food_space_used, individual.food_space_capacity,
		calories_before, individual.food_calories_held,
		body_gain, body_before, individual.body_calories, individual.body_calories_capacity,
		pouch_calories_added
	])


# Stato interno di progresso da persistere (stesso schema di RetrieveAction.get_save_data): la scelta
# fatta in activate, durata/trascorso/costo stamina, e l'id dell'edificio (TaskPersistenceService lo
# risolve al caricamento).
func get_save_data() -> Dictionary:
	var data := {
		"selection": _selection,
		"duration": _duration,
		"elapsed": _elapsed,
		"total_stamina_cost": _total_stamina_cost,
	}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


func load_save_data(data: Dictionary) -> void:
	_selection = data.get("selection", {})
	_duration = float(data.get("duration", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
	_total_stamina_cost = float(data.get("total_stamina_cost", 0.0))
	_restored_from_save = true
