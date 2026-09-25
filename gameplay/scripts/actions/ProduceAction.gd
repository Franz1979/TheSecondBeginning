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
#   - nessun pending_material_shortage/bonus di partenza/notifica: in attesa di materiale lo step
#     resta fermo (zero stamina, zero lavoro, mai completo) finché gli input non arrivano o il
#     giocatore annulla la Task (tasto H) — BuildingInfoPanel mostra cosa manca leggendo
#     ProductionService.get_missing_inputs.
#
# Nessun accumulatore interno: labor_accumulated letto/scritto dal vivo su Building, stesso motivo
# di BuildAction (sopravvive a interruzione/riassegnazione e al salvataggio senza load_save_data).
#
# Combustibile (recipe_fuel_required): non ancora gestito in questo step.
#
# QUANTITÀ (2026-09-24, richiesta utente): lo step produce `quantity` pezzi (1..BuildingRules.
# production_max_quantity, scelti nel pannello) ripetendo il ciclo sul record della propria ricetta:
# a ogni ciclo concluso (_try_complete_cycle) il progresso riparte da zero per la stessa ricetta, e
# lo step termina quando produced_count >= quantity. Ogni ciclo richiede i propri input e posto nel
# buffer: se mancano, lo step resta fermo come per il primo ciclo. produced_count conta PEZZI
# (recipe_output_quantity per ciclo), quindi con un'uscita > 1 per ciclo l'ultimo ciclo può superare
# di poco la quantità ordinata.

# Stesso ordine di grandezza di BuildAction.STAMINA_DRAIN_PER_DAY — da bilanciare in seguito.
const STAMINA_DRAIN_PER_DAY: float = 150

var target_building: Building = null
# Nome della risorsa da produrre (SecondaryResourceRules.secondary_resource_name).
var resource_name: String = ""
var skill_multiplier: float = 1.0
var tool_multiplier: float = 1.0
# Pezzi ordinati (minimo 1) e pezzi già prodotti da questo step — vedi QUANTITÀ in testa al file.
var quantity: int = 1
var produced_count: int = 0


func _init(
	p_target_building: Building = null,
	p_resource_name: String = "",
	p_skill_multiplier: float = 1.0,
	p_tool_multiplier: float = 1.0,
	p_quantity: int = 1
) -> void:
	target = null
	target_building = p_target_building
	resource_name = p_resource_name
	skill_multiplier = p_skill_multiplier
	tool_multiplier = p_tool_multiplier
	quantity = max(p_quantity, 1)
	# Stesse fasce escluse di BuildAction.
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Validità (vedi Action.is_target_valid): edificio nullo, demolito o non più una workstation valida
# per questa ricetta (incompleto, is_workstation false, tipo non in recipe_workstation_types).
func is_target_valid() -> bool:
	return target_building != null and not target_building.is_demolished and ProductionService.can_produce_at(target_building, resource_name)


# Fabbisogno materiale per la ricetta di resource_name — {resource_name: missing_quantity}, stessa
# forma di BuildAction.get_missing_materials. Vuoto = nulla manca.
func get_missing_materials() -> Dictionary:
	return ProductionService.get_missing_inputs_for(target_building, resource_name)


# Registra la produzione sull'edificio (ProductionService.start_production: record della propria
# ricetta ripreso se esiste già, creato se c'è un record libero) — da qui in poi can_accept accetta
# gli input della ricetta fino alla quantità mancante. Se l'edificio è pieno lo step aspetta e
# riprova a ogni giorno (get_stamina_delta), senza toccare i record delle altre ricette.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if is_target_valid():
		ProductionService.start_production(target_building, resource_name)


# true se il record della propria ricetta esiste; altrimenti prova a crearlo (dopo l'ultimo ciclo di un
# altro individuo sulla stessa ricetta, che lo rimuove, o se all'activate l'edificio era pieno).
func _ensure_own_record() -> bool:
	return ProductionService.start_production(target_building, resource_name)


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if not is_target_valid() or produced_count >= quantity or not _ensure_own_record():
		return 0.0
	if not get_missing_materials().is_empty() or not ProductionService.has_output_room(target_building, resource_name):
		return 0.0
	# Combustibile mancante (2026-09-24): fermo come per i materiali.
	if ProductionService.get_missing_fuel_for(target_building, resource_name) > 0.0:
		return 0.0
	var required_labor := ProductionService.get_required_labor(target_building, resource_name)
	var labor_accumulated := ProductionService.get_labor_accumulated(target_building, resource_name)
	var stamina_spent_this_day: float = 0.0
	if labor_accumulated < required_labor:
		stamina_spent_this_day = STAMINA_DRAIN_PER_DAY * delta
		ProductionService.add_labor(target_building, resource_name, stamina_spent_this_day * skill_multiplier * tool_multiplier)
	_try_complete_cycle()
	return -stamina_spent_this_day


# Conclude un ciclo appena lavoro, input e posto nel buffer lo consentono (ProductionService.
# complete_production: consumo esatto, prodotto nel buffer, rimozione del SOLO record di questa
# ricetta; 0 = non ancora possibile). Se mancano ancora pezzi all'ordine, ricrea subito il record
# (start_production, il posto appena liberato è il suo) così il ciclo successivo riparte da zero e
# can_accept continua ad accettarne gli input.
func _try_complete_cycle() -> void:
	if ProductionService.get_labor_accumulated(target_building, resource_name) < ProductionService.get_required_labor(target_building, resource_name):
		return
	var produced := ProductionService.complete_production(target_building, resource_name)
	if produced <= 0:
		return
	produced_count += produced
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[PRODUCE] Building #%d: prodotte %d unità di '%s' (%d/%d)." % [target_building.id, produced, resource_name, produced_count, quantity])
	if produced_count < quantity:
		ProductionService.start_production(target_building, resource_name)


# Completa solo quando l'ordine è evaso (produced_count >= quantity). Record assente (edificio pieno),
# materiali mancanti o buffer pieno = resta fermo finché la situazione si sblocca o il giocatore
# annulla la Task (H). Nessuna altra ricetta può più far terminare questo step (2026-09-24: un
# record per ricetta, mai sovrascritto).
func is_complete(individual: Variant, context: Dictionary) -> bool:
	return produced_count >= quantity


# Stessa formula di BuildAction.get_required_position: ritorno esatto all'edificio alla ripresa dopo
# una sospensione.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(target_building.micro_x, target_building.micro_y) + macro_offset


# Nessun effetto: ogni ciclo, compreso l'ultimo, si conclude già in _try_complete_cycle.
func on_complete(individual: Variant, context: Dictionary) -> void:
	pass


# Dati "di identità" (edificio via id, risorsa, moltiplicatori, quantità ordinata) più i pezzi già
# prodotti: il progresso del ciclo corrente vive su Building.production_progress, già serializzato
# da GameSaveService — stesso principio di BuildAction.get_save_data. "quantity" è letta da
# TaskPersistenceService (argomento di _init), "produced_count" da load_save_data.
func get_save_data() -> Dictionary:
	var data := {
		"resource_name": resource_name,
		"skill_multiplier": skill_multiplier,
		"tool_multiplier": tool_multiplier,
		"quantity": quantity,
		"produced_count": produced_count,
	}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


# Default 0 per i save precedenti alla quantità (2026-09-24).
func load_save_data(data: Dictionary) -> void:
	produced_count = int(data.get("produced_count", 0))
