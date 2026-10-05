class_name ProduceAction
extends Action

# Step "produci" della Produce Task (2026-09-23, richiesta utente — sistema di produzione, step 4:
# Walk → Produce, vedi produce.tres): presso una workstation completa, accumula lavoro giorno per
# giorno sul record di resource_name in target_building.production_progress fino al lavoro richiesto
# dalla ricetta, poi consuma gli input, aggiunge il prodotto al buffer di uscita (production_output) e
# rimuove il record (un record per ricetta, vedi ProductionService). Schema di BuildAction, con queste differenze:
#   - il progresso vive su Building.production_progress (non construction_progress) e viene gestito
#     da ProductionService (layer di simulazione, condiviso con BuildingStorageService.can_accept);
#   - il consumo DECREMENTA la quantità esatta della ricetta (ProductionService.complete_production),
#     non cancella l'intera voce come BuildAction.on_complete;
#   - il prodotto va nel buffer di uscita (Building.production_output): a buffer pieno lo step resta
#     fermo come in attesa di materiale, finché il buffer non viene svuotato;
#   - in attesa di materiale o combustibile lo step resta fermo (zero stamina, zero lavoro, mai completo) e, dal
#     2026-09-29, scrive pending_material_shortage come la Build (_report_material_shortage): il pipottino va da sé
#     a rifornire la postazione (MaterialSupplyService), altrimenti attesa con popup e retry giornaliero. Nessun
#     bonus di partenza. BuildingInfoPanel mostra cosa manca leggendo ProductionService.get_missing_inputs.
#
# Nessun accumulatore interno: labor_accumulated letto/scritto dal vivo su Building, stesso motivo
# di BuildAction (sopravvive a interruzione/riassegnazione e al salvataggio senza load_save_data).
#
# Combustibile (recipe_fuel_required, dal 2026-09-24): gestito da ProductionService — un ciclo non si
# completa senza combustibile sufficiente, bruciato al completamento dopo i materiali (_consume_fuel).
#
# QUANTITÀ (2026-09-24, richiesta utente): lo step produce `quantity` pezzi (1..BuildingRules.
# production_max_quantity, scelti nel pannello) ripetendo il ciclo sul record della propria ricetta:
# a ogni ciclo concluso (_try_complete_cycle) il progresso riparte da zero per la stessa ricetta, e
# lo step termina quando produced_count >= quantity. Ogni ciclo richiede i propri input e posto nel
# buffer: se mancano, lo step resta fermo come per il primo ciclo. produced_count conta PEZZI
# (recipe_output_quantity per ciclo), quindi con un'uscita > 1 per ciclo l'ultimo ciclo può superare
# di poco la quantità ordinata.
#
# ORDINI SEPARATI (2026-10-04, richiesta utente — ProductionService "ORDINI SEPARATI"): lo step lavora sul PROPRIO
# ordine (order_key), creato da GameScene all'assegnazione: lavoro, ciclo e pezzi dovuti sono di quell'ordine, mai
# sommati a quelli di un altro ordine della stessa ricetta. Ordine sparito (annullato dal pannello o liberato per far
# posto) = lo step si chiude e la Task con lui. Step di un salvataggio vecchio, senza chiave: si crea il proprio ordine
# al primo tick, se l'edificio ha posto (_adopt_legacy_order), altrimenti aspetta.

# Stesso ordine di grandezza di BuildAction.STAMINA_DRAIN_PER_DAY — da bilanciare in seguito.
const STAMINA_DRAIN_PER_DAY: float = 150
# Effetto della skill (2026-09-27, SkillEffectService, chiave "produce"): il lavoro richiesto (già moltiplicato per
# production_labor_multiplier della postazione) diviso per il fattore non scende mai sotto questa frazione del
# recipe_labor base della ricetta.
const MIN_REQUIRED_LABOR_FRACTION: float = 0.4

var target_building: Building = null
# Nome della risorsa da produrre (SecondaryResourceRules.secondary_resource_name).
var resource_name: String = ""
# Moltiplicatore degli attrezzi, oggi sempre 1.0 (servirà più avanti). La skill non è più un campo salvato: il fattore
# si legge a ogni tick da SkillEffectService (2026-09-27, _get_labor_scale).
var tool_multiplier: float = 1.0
# Pezzi ordinati (minimo 1) e pezzi già prodotti da questo step — vedi QUANTITÀ in testa al file.
var quantity: int = 1
var produced_count: int = 0
# Ordine dell'edificio su cui lavora questo step (ProductionService, chiave in Building.production_progress); "" = step
# di un salvataggio precedenti agli ordini separati. Salvato.
var order_key: String = ""
# true se l'ordine non c'è più: lo step si chiude (is_complete) e la Task con lui. Non salvato.
var _order_lost: bool = false
# DEBUG TEMPORANEO [PRODUCE BLOCK] (2026-09-27): ultimo messaggio stampato, per stampare solo i cambiamenti.
# Non salvato. Vedi DebugLogging.SHOW_PRODUCTION_BLOCK_LOGS.
var _debug_last_block_message: String = ""
# Rifornimento automatico (2026-09-29, MaterialSupplyService): true se l'ultimo tick si è fermato per materiale o
# combustibile mancanti (letto dal retry giornaliero, HumanIndividualActionService.retry_blocked_material_shortages), e
# se la richiesta pending_material_shortage per questo blocco è già stata scritta (una volta per blocco, non a ogni
# tick — azzerata quando il blocco finisce e a ogni activate, cioè al ritorno da un giro di rifornimento). Non salvati:
# dopo un caricamento il primo tick bloccato riscrive la richiesta.
var _blocked_by_materials: bool = false
var _material_shortage_reported: bool = false
# Attesa degli attrezzi (2026-09-25, "task in attesa invece di rifiuto"): stato tool_wait_* e
# ensure_required_tools vivono nella classe base Action dal 2026-09-26 (condivisi con la caccia).


func _init(
	p_target_building: Building = null,
	p_resource_name: String = "",
	p_tool_multiplier: float = 1.0,
	p_quantity: int = 1
) -> void:
	target = null
	target_building = p_target_building
	resource_name = p_resource_name
	tool_multiplier = p_tool_multiplier
	skill_effect_key = "produce"
	quantity = max(p_quantity, 1)
	# Stesse fasce escluse di BuildAction.
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Validità (vedi Action.is_target_valid): edificio nullo, demolito o non più una workstation valida
# per questa ricetta (incompleto, is_workstation false, tipo non in recipe_workstation_types).
func is_target_valid() -> bool:
	if target_building == null or target_building.is_demolished or not ProductionService.can_produce_at(target_building, resource_name):
		return false
	# Ordine annullato mentre la Task era in coda: la Task si scarta alla ripresa.
	return order_key == "" or ProductionService.has_order(target_building, order_key)


# Fabbisogno materiale per la ricetta di resource_name — {resource_name: missing_quantity}, stessa
# forma di BuildAction.get_missing_materials. Vuoto = nulla manca.
func get_missing_materials() -> Dictionary:
	return ProductionService.get_missing_inputs_for(target_building, resource_name)


# L'ordine esiste già dall'assegnazione (ORDINI SEPARATI, 2026-10-04): activate non crea più record.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_material_shortage_reported = false


# true se il proprio ordine c'è. Step di un salvataggio vecchio (order_key ""): prova a crearsi l'ordine per i pezzi che
# gli mancano (ProductionService.create_order, riparte dalla produzione sospesa della ricetta); edificio pieno = aspetta.
func _ensure_order(individual: Variant) -> bool:
	if order_key == "":
		_adopt_legacy_order(individual)
	return ProductionService.has_order(target_building, order_key)


func _adopt_legacy_order(individual: Variant) -> void:
	var worker_id: int = int(individual.id) if individual is HumanIndividual else -1
	order_key = ProductionService.create_order(target_building, resource_name, maxi(quantity - produced_count, 1), worker_id)


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_blocked_by_materials = false
	if produced_count >= quantity:
		return 0.0
	if not is_target_valid():
		_debug_log_block(individual, "edificio non valido (demolito, incompleto o non più workstation per la ricetta)")
		return 0.0
	if order_key != "" and not ProductionService.has_order(target_building, order_key):
		# Ordine annullato o liberato per far posto: lo step si chiude, la Task con lui.
		_order_lost = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "ordine di produzione %s annullato" % order_key
		return 0.0
	if not _ensure_order(individual):
		_debug_log_block(individual, _debug_describe_no_record())
		return 0.0
	# Attrezzi (2026-09-25): come per il materiale mancante, lo step resta fermo (zero stamina, zero
	# lavoro) finché gli attrezzi richiesti non ci sono; appena compaiono nello zaino vengono spostati
	# in cintura e il lavoro parte da solo, senza riassegnare la Task.
	if not ensure_required_tools(individual):
		_debug_log_block(individual, _debug_describe_tools())
		return 0.0
	if not get_missing_materials().is_empty():
		_debug_log_block(individual, _debug_describe_materials())
		_report_material_shortage(context)
		return 0.0
	if not ProductionService.has_output_room(target_building, resource_name):
		_debug_log_block(individual, _debug_describe_output_buffer())
		return 0.0
	# Combustibile mancante (2026-09-24): fermo come per i materiali.
	if ProductionService.get_missing_fuel_for(target_building, resource_name) > 0.0:
		_debug_log_block(individual, _debug_describe_fuel())
		_report_material_shortage(context)
		return 0.0
	_debug_log_block(individual, "")
	# Blocco per materiale finito: nuova richiesta al prossimo blocco, e il pannello non resta "in attesa".
	_material_shortage_reported = false
	if target_building.is_awaiting_material:
		target_building.is_awaiting_material = false
	var required_labor := ProductionService.get_required_labor(target_building, resource_name)
	var labor_accumulated := ProductionService.get_labor_accumulated(target_building, order_key)
	var stamina_spent_this_day: float = 0.0
	if labor_accumulated < required_labor:
		stamina_spent_this_day = STAMINA_DRAIN_PER_DAY * delta
		ProductionService.add_labor(target_building, order_key, stamina_spent_this_day * _get_labor_scale(individual, context) * tool_multiplier)
	_try_complete_cycle(individual)
	return -stamina_spent_this_day


# Materiale o combustibile mancanti (2026-09-29, rifornimento automatico): stessa richiesta della Build
# (context["pending_material_shortage"], consumata da HumanIndividualActionService._handle_pending_material_shortage,
# che prova MaterialSupplyService e altrimenti ricade nell'attesa con popup), scritta UNA volta per blocco. Il
# fabbisogno riportato è quello dell'ordine intero (MaterialSupplyService.get_missing_materials), non del ciclo.
func _report_material_shortage(context: Dictionary) -> void:
	_blocked_by_materials = true
	if _material_shortage_reported:
		return
	_material_shortage_reported = true
	context["pending_material_shortage"] = {
		"missing": MaterialSupplyService.get_missing_materials(target_building),
		"target_building_id": target_building.id,
	}


# true se l'ultimo tick si è fermato per materiale o combustibile mancanti (retry giornaliero del rifornimento).
func is_blocked_by_materials() -> bool:
	return _blocked_by_materials


# Effetto della skill sul lavoro (2026-09-27, SkillEffectService, chiave "produce"). Lavoro richiesto effettivo =
# max(lavoro della postazione / fattore, MIN_REQUIRED_LABOR_FRACTION × recipe_labor base). Realizzato scalando il
# lavoro AGGIUNTO (lavoro della postazione / lavoro effettivo) invece di cambiare il lavoro richiesto salvato: stesso
# tempo di produzione, e il progresso condiviso sull'edificio (pannello, più lavoratori, salvataggi) resta sempre
# misurato sul lavoro della postazione.
func _get_labor_scale(individual: Variant, context: Dictionary) -> float:
	var station_labor := ProductionService.get_required_labor(target_building, resource_name)
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if station_labor <= 0.0 or recipe_rules == null:
		return 1.0
	var skill_factor := SkillEffectService.get_factor_for_action(self, individual, context)
	var effective_labor: float = maxf(station_labor / skill_factor, MIN_REQUIRED_LABOR_FRACTION * recipe_rules.recipe_labor)
	if effective_labor <= 0.0:
		return 1.0
	return station_labor / effective_labor


# Conclude un ciclo appena lavoro, input e posto nel buffer lo consentono (ProductionService.
# complete_production sul proprio ordine: consumo esatto, prodotto nel buffer, lavoro azzerato per il ciclo
# successivo; 0 = non ancora possibile).
func _try_complete_cycle(individual: Variant) -> void:
	if ProductionService.get_labor_accumulated(target_building, order_key) < ProductionService.get_required_labor(target_building, resource_name):
		return
	# L'ordine resta (lavoro azzerato) finché ha pezzi dovuti, poi sparisce: nessun record da ricreare.
	var produced := ProductionService.complete_production(target_building, order_key)
	if produced <= 0:
		return
	produced_count += produced
	_consume_tools_for_cycle(individual)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[PRODUCE] Building #%d: prodotte %d unità di '%s' (%d/%d)." % [target_building.id, produced, resource_name, produced_count, quantity])


# --- DEBUG TEMPORANEO [PRODUCE BLOCK] (2026-09-27, richiesta utente) — rimuovere insieme al flag ---
# `message` "" = lo step lavora: stampa "ripresa" solo se prima era fermo. Stampa solo quando il messaggio
# cambia (quantità comprese), quindi una riga per consegna/consumo, non una per tick.
func _debug_log_block(individual: Variant, message: String) -> void:
	if not (DebugLogging.ENABLED and DebugLogging.SHOW_PRODUCTION_BLOCK_LOGS):
		return
	if message == _debug_last_block_message:
		return
	var previous := _debug_last_block_message
	_debug_last_block_message = message
	var who: String = ("#%d" % int(individual.id)) if individual is HumanIndividual else "?"
	var building_id: int = target_building.id if target_building != null else -1
	if message == "":
		if previous != "":
			print("[PRODUCE BLOCK] %s edificio #%d '%s' (%d/%d): ripresa, lavoro %.1f/%.1f." % [
				who, building_id, resource_name, produced_count, quantity,
				ProductionService.get_labor_accumulated(target_building, order_key),
				ProductionService.get_required_labor(target_building, resource_name)])
		return
	print("[PRODUCE BLOCK] %s edificio #%d '%s' (%d/%d): FERMO — %s" % [who, building_id, resource_name, produced_count, quantity, message])


func _debug_describe_no_record() -> String:
	return "ordine assente e ordini al massimo sull'edificio: ordini %s, massimo %d." % [
		str(target_building.production_progress.keys()), ProductionService.get_max_concurrent_orders(target_building)]


func _debug_describe_tools() -> String:
	return "attrezzi mancanti: esito %s, categorie mancanti %s, attrezzo %s." % [
		ToolGateService.Result.keys()[tool_wait_result], str(tool_wait_missing_categories), tool_wait_tool_name if tool_wait_tool_name != "" else "-"]


# Per ciclo (il controllo che ferma lo step) e per l'ordine intero (quello che mostra il pannello).
func _debug_describe_materials() -> String:
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var parts: PackedStringArray = []
	if recipe_rules != null:
		for input_name in recipe_rules.recipe_inputs.keys():
			var stored_entry: Dictionary = target_building.stored_resources.get(input_name, {})
			# Anche il buffer di uscita della postazione vale come ingrediente (2026-09-27, ProductionService.get_input_available).
			parts.append("%s servono %d/ciclo, in deposito %d, nel buffer %d" % [
				input_name, int(recipe_rules.recipe_inputs[input_name]), int(stored_entry.get("quantity", 0)),
				int(target_building.production_output.get(input_name, 0))])
	var own_recipe: Array[String] = [resource_name]
	return "materiale mancante per il ciclo %s [%s]; ordine: pezzi dovuti %d, cicli %d, mancanti per l'ordine %s; chiavi in deposito %s." % [
		str(get_missing_materials()), ", ".join(parts),
		ProductionService.get_units_remaining(target_building, resource_name),
		ProductionService.get_cycles_due(target_building, resource_name),
		str(ProductionService.get_missing_inputs_for_recipes(target_building, own_recipe)),
		str(target_building.stored_resources.keys())]


func _debug_describe_output_buffer() -> String:
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return "buffer di uscita pieno: occupato %d, capienza %d, pezzi per ciclo %d, contenuto %s." % [
		ProductionService.get_output_used(target_building), ProductionService.get_output_capacity(target_building),
		recipe_rules.recipe_output_quantity if recipe_rules != null else 0, str(target_building.production_output)]


func _debug_describe_fuel() -> String:
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var reserved: Dictionary = recipe_rules.recipe_inputs if recipe_rules != null else {}
	var sources: PackedStringArray = []
	for stored_name in target_building.stored_resources.keys():
		var fuel_value := ProductionService.get_fuel_value(String(stored_name))
		if fuel_value > 0.0:
			sources.append("%s x%d (valore %.1f, riservate come materiale %d)" % [
				stored_name, int(target_building.stored_resources[stored_name].get("quantity", 0)), fuel_value, int(reserved.get(stored_name, 0))])
	return "combustibile mancante: richiesto %.1f/ciclo, disponibile %.1f, manca %.1f; fonti [%s]." % [
		ProductionService.get_required_fuel(target_building, resource_name),
		ProductionService.get_available_fuel(target_building, reserved),
		ProductionService.get_missing_fuel_for(target_building, resource_name),
		", ".join(sources)]


# Usura degli attrezzi (2026-09-26, attrezzi come istanze — step 3): a ciclo completato ogni attrezzo
# distinto usato per le categorie di questo step perde un uso (ToolGateService.consume_tool_uses). Se
# uno si rompe: avviso sul pannello dell'individuo (stesso canale di tool_gate_warning) e log. Nessuna
# gestione della Task qui: al tick successivo ensure_required_tools non trova più la categoria e
# rimette in cintura un attrezzo di scorta dallo zaino, oppure lascia lo step in attesa (MISSING_TOOLS)
# — stesso percorso di quando gli attrezzi mancano fin dall'inizio. game_data null: lo step non lo
# possiede (capacità corretta del solo bonus dello slot liberato, come per l'equipaggiamento automatico).
# Attrezzeria (2026-10-04): ogni categoria richiesta si cerca prima nell'Attrezzeria dell'edificio — lì si consuma un uso
# sul pezzo più usato dell'attrezzo che la copre (un uso per attrezzo, anche se copre più categorie) — e solo le
# categorie che l'Attrezzeria non copre si consumano sulla cintura del pipottino, come prima.
func get_tool_categories_for_individual() -> Array[TaskTypes.ToolCategory]:
	return BuildingToolkitService.filter_uncovered(target_building, ToolGateService.get_action_required_categories(self))


func _consume_tools_for_cycle(individual: Variant) -> void:
	if not (individual is HumanIndividual):
		return
	var broken: Array[String] = []
	var toolkit_tools: Array[String] = []
	var belt_categories: Array[TaskTypes.ToolCategory] = []
	for category in ToolGateService.get_action_required_categories(self):
		var toolkit_tool := BuildingToolkitService.find_tool_for(target_building, category)
		if toolkit_tool == "":
			belt_categories.append(category)
		elif not toolkit_tools.has(toolkit_tool):
			toolkit_tools.append(toolkit_tool)
	for toolkit_tool in toolkit_tools:
		if BuildingToolkitService.consume_use(target_building, toolkit_tool):
			broken.append(toolkit_tool)
	broken.append_array(ToolGateService.consume_tool_uses(individual, belt_categories, null))
	if broken.is_empty():
		return
	report_broken_tools(individual, broken)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[PRODUCE] #%d: attrezzi rotti dopo il ciclo di '%s': %s." % [individual.id, resource_name, str(broken)])


# Completa solo quando l'ordine è evaso (produced_count >= quantity). Record assente (edificio pieno),
# materiali mancanti o buffer pieno = resta fermo finché la situazione si sblocca o il giocatore
# annulla la Task (H). Nessuna altra ricetta può più far terminare questo step (2026-09-24: un
# record per ricetta, mai sovrascritto).
func is_complete(individual: Variant, context: Dictionary) -> bool:
	return produced_count >= quantity or _order_lost


# Stessa formula di BuildAction.get_required_position: ritorno esatto all'edificio alla ripresa dopo
# una sospensione.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	# Punto casuale dentro la microcella, mai l'angolo esatto (2026-09-27, PathfindingService.random_point_in_microcell).
	return PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + macro_offset)


# Nessun effetto: ogni ciclo, compreso l'ultimo, si conclude già in _try_complete_cycle.
# Pezzi prodotti dall'ordine (2026-09-26): li legge lo step di consegna al magazzino che segue (RetrieveAction in
# modalità deliver_to_warehouse), per prelevare solo quanto prodotto da questo ordine.
func on_complete(individual: Variant, context: Dictionary) -> void:
	context[RetrieveAction.CONTEXT_PRODUCED_COUNT] = produced_count


# Dati "di identità" (edificio via id, risorsa, moltiplicatori, quantità ordinata) più i pezzi già
# prodotti: il progresso del ciclo corrente vive su Building.production_progress, già serializzato
# da GameSaveService — stesso principio di BuildAction.get_save_data. "quantity" è letta da
# TaskPersistenceService (argomento di _init), "produced_count" da load_save_data.
func get_save_data() -> Dictionary:
	var data := {
		"resource_name": resource_name,
		"tool_multiplier": tool_multiplier,
		"quantity": quantity,
		"produced_count": produced_count,
		"order_key": order_key,
	}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


# Default 0 per i save precedenti alla quantità (2026-09-24).
func load_save_data(data: Dictionary) -> void:
	produced_count = int(data.get("produced_count", 0))
