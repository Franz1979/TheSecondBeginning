class_name RepairAction
extends Action

# Riparazione a mano di un edificio completo (2026-10-10, richiesta utente — secondo step di repair.tres: Walk → Repair).
# Stesso schema di DemolishAction/BuildAction (lavoro a cicli giornalieri a STAMINA_DRAIN_PER_DAY, fattore della skill
# "build", stessi limiti d'età), ma l'edificio resta completo e in funzione: residenti, magazzino e produzione non
# vengono toccati e non serve nessun materiale. Il lavoro si trasforma subito in Integrità: ogni punto di lavoro
# restituisce max_durability / (required_labor × LABOR_FRACTION_OF_BUILD) punti, così riportare l'edificio da 0 al
# massimo costa metà del lavoro di costruzione. Nessun accumulatore proprio: il progresso È Building.current_durability
# (salvato con l'edificio), quindi interruzione, ripresa e salvataggio non perdono nulla. Finisce a Integrità piena.
#
# Edificio non più riparabile durante il lavoro (demolito, "da demolire", miglioramento avviato): la Task si chiude
# senza effetti di completamento (CONTEXT_PENDING_TASK_ABORT, come CutAction), l'Integrità recuperata resta.

# Stesso drain della costruzione (BuildAction.STAMINA_DRAIN_PER_DAY), costante propria come ogni Action.
const STAMINA_DRAIN_PER_DAY: float = 200.0
# Frazione del lavoro di costruzione che costa riportare l'Integrità da 0 al massimo.
const LABOR_FRACTION_OF_BUILD: float = 0.5

var target_building: Building = null
var _aborted: bool = false


func _init(p_target_building: Building = null) -> void:
	target = null
	target_building = p_target_building
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	skill_effect_key = "build"


# Edificio riparabile in questo momento: esiste, completo (un miglioramento in corso non lo è), non "da demolire".
static func is_building_repairable(building: Building) -> bool:
	return building != null and building.rules != null and not building.is_demolished and building.is_complete \
		and not building.is_marked_for_demolition and building.rules.max_durability > 0


# Lavoro (non scontato dalla skill) che serve ora per riportare `building` all'Integrità piena.
static func get_labor_to_full(building: Building) -> float:
	if building == null or building.rules == null or building.rules.max_durability <= 0:
		return 0.0
	var missing_ratio: float = clampf(1.0 - building.current_durability / float(building.rules.max_durability), 0.0, 1.0)
	return missing_ratio * float(building.rules.required_labor) * LABOR_FRACTION_OF_BUILD


# Punti di Integrità restituiti da un punto di lavoro. 0 se l'edificio non ha lavoro di costruzione.
static func get_durability_per_labor(building: Building) -> float:
	if building == null or building.rules == null or building.rules.required_labor <= 0:
		return 0.0
	return float(building.rules.max_durability) / (float(building.rules.required_labor) * LABOR_FRACTION_OF_BUILD)


func is_target_valid() -> bool:
	return is_building_repairable(target_building)


func _is_full() -> bool:
	return target_building.current_durability >= float(target_building.rules.max_durability)


# --- Piano dei materiali (2026-10-10, richiesta utente — materiali della Ripara, passo 2) ---
# Alla prima unità di lavoro di una riparazione si fissa su Building.repair_plan (salvato con l'edificio, così chi
# riprende il lavoro dopo un'interruzione trova lo stesso piano): "range" = Integrità mancante in quel momento,
# "materials" = per ogni risorsa di required_materials (non l'allestimento) quantità × quota mancante × MATERIAL_FRACTION,
# per difetto (voci a zero omesse), "consumed" = unità già consumate per risorsa, "repaired" = Integrità già restituita
# con questo piano. Ogni unità di una risorsa copre una fetta uguale di "range": l'unità i-esima si toglie da
# Building.repair_materials quando "repaired" arriva all'inizio della sua fetta; se nel contenitore non c'è, il lavoro si
# ferma lì (nessuna stamina spesa) e aspetta. Piano senza materiali: solo lavoro, come prima. A piano esaurito
# ("repaired" >= "range", 2026-10-10) il lavoro continua senza altri materiali fino a Integrità piena (il deperimento durante
# i lavori non fa partire una seconda riparazione); la riparazione finisce solo a Integrità piena, e lì si chiudono il
# piano e la richiesta di riparazione. Il piano si cancella alla fine o all'abbandono.
const MATERIAL_FRACTION: float = 0.5
const PLAN_RANGE := "range"
const PLAN_MATERIALS := "materials"
const PLAN_CONSUMED := "consumed"
const PLAN_REPAIRED := "repaired"
# Margine sui confronti in virgola mobile tra "repaired" e i confini delle fette.
const PLAN_EPSILON: float = 0.0001


# Materiali che servirebbero ADESSO per riportare `building` all'Integrità piena (stessa formula del piano): risorsa ->
# unità, voci a zero omesse. Usata dal piano e dal tooltip di "Ripara".
static func compute_plan_materials(building: Building) -> Dictionary:
	var materials: Dictionary = {}
	if building == null or building.rules == null or building.rules.max_durability <= 0:
		return materials
	var missing_ratio: float = clampf(1.0 - building.current_durability / float(building.rules.max_durability), 0.0, 1.0)
	for material_name in building.rules.required_materials.keys():
		var units: int = floori(float(building.rules.required_materials[material_name]) * missing_ratio * MATERIAL_FRACTION)
		if units > 0:
			materials[String(material_name)] = units
	return materials


# Materiali ancora da portare per la riparazione di `building` (passo 3, rifornimento): quello che il piano richiede
# ancora (richiesti meno consumati), meno quello che è già nel contenitore (Building.repair_materials). Senza piano, il
# piano che nascerebbe adesso. Risorsa -> unità, voci a zero omesse. Letto da MaterialSupplyService e da UnloadAction
# (scarico dedicato DepositKind.REPAIR, che non deposita mai oltre questo).
static func get_supply_missing(building: Building) -> Dictionary:
	var missing: Dictionary = {}
	if building == null or building.rules == null:
		return missing
	var materials: Dictionary = compute_plan_materials(building)
	var consumed: Dictionary = {}
	if not building.repair_plan.is_empty():
		materials = building.repair_plan.get(PLAN_MATERIALS, {})
		consumed = building.repair_plan.get(PLAN_CONSUMED, {})
	for material_name in materials.keys():
		var units: int = int(materials[material_name]) - int(consumed.get(material_name, 0)) \
			- int(building.repair_materials.get(material_name, 0))
		if units > 0:
			missing[String(material_name)] = units
	return missing


# All'attivazione (anche dopo ogni giro di rifornimento): piano fissato e, se al contenitore mancano materiali, richiesta
# di rifornimento come la Build (pending_material_shortage, consumato da HumanIndividualActionService: giro
# Walk → Retrieve → Walk → Unload dedicato verso il contenitore, MaterialSupplyService). Senza sorgente la riparazione
# resta in attesa, ferma dove finiscono i materiali (get_stamina_delta).
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if target_building != null:
		target_building.repair_awaiting_material = false
	if _aborted or not is_target_valid() or _is_full():
		return
	_ensure_plan()
	if _plan_exhausted():
		return
	var missing := get_supply_missing(target_building)
	if not missing.is_empty():
		context["pending_material_shortage"] = {"missing": missing, "target_building_id": target_building.id}


func _ensure_plan() -> void:
	if not target_building.repair_plan.is_empty():
		return
	target_building.repair_plan = {
		PLAN_RANGE: maxf(float(target_building.rules.max_durability) - target_building.current_durability, 0.0),
		PLAN_MATERIALS: compute_plan_materials(target_building),
		PLAN_CONSUMED: {},
		PLAN_REPAIRED: 0.0,
	}


func _plan_exhausted() -> bool:
	var plan: Dictionary = target_building.repair_plan
	if plan.is_empty():
		return false
	return float(plan.get(PLAN_REPAIRED, 0.0)) >= float(plan.get(PLAN_RANGE, 0.0)) - PLAN_EPSILON


# Integrità che il piano permette di restituire con le unità consumate: le unità la cui fetta è già cominciata vengono
# tolte dal contenitore se ci sono. min(consumate / richieste) su tutte le risorse, per "range". Senza materiali: tutto.
func _allowed_repaired() -> float:
	var plan: Dictionary = target_building.repair_plan
	var plan_range: float = float(plan.get(PLAN_RANGE, 0.0))
	var materials: Dictionary = plan.get(PLAN_MATERIALS, {})
	if materials.is_empty():
		return plan_range
	var consumed: Dictionary = plan.get(PLAN_CONSUMED, {})
	var repaired: float = float(plan.get(PLAN_REPAIRED, 0.0))
	var allowed_ratio: float = 1.0
	for material_name in materials.keys():
		var required: int = int(materials[material_name])
		var used: int = int(consumed.get(material_name, 0))
		# Fetta corrente finita (o mai cominciata): consuma l'unità successiva, se c'è nel contenitore.
		while used < required and repaired >= float(used) / float(required) * plan_range - PLAN_EPSILON \
				and int(target_building.repair_materials.get(material_name, 0)) > 0:
			var left: int = int(target_building.repair_materials[material_name]) - 1
			if left > 0:
				target_building.repair_materials[material_name] = left
			else:
				target_building.repair_materials.erase(material_name)
			used += 1
		consumed[material_name] = used
		allowed_ratio = minf(allowed_ratio, float(used) / float(required))
	plan[PLAN_CONSUMED] = consumed
	return allowed_ratio * plan_range


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _aborted:
		return 0.0
	if not is_target_valid():
		_aborted = true
		if target_building != null:
			target_building.repair_plan = {}
			target_building.repair_awaiting_material = false
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "edificio non più riparabile"
		return 0.0
	if _is_full():
		return 0.0
	_ensure_plan()
	var plan: Dictionary = target_building.repair_plan
	var repaired: float = float(plan.get(PLAN_REPAIRED, 0.0))
	# Piano esaurito: solo lavoro, senza limite dei materiali, fino a Integrità piena.
	var room: float = INF if _plan_exhausted() else _allowed_repaired() - repaired
	# In attesa dei materiali della fetta successiva: nessun lavoro, nessuna stamina spesa.
	if room <= PLAN_EPSILON:
		return 0.0
	target_building.repair_awaiting_material = false
	var stamina_spent: float = STAMINA_DRAIN_PER_DAY * delta
	# Skill come BuildAction: il lavoro aggiunto è moltiplicato per il fattore (stesso tempo, lavoro richiesto diviso).
	var skill_factor := SkillEffectService.get_factor_for_action(self, individual, context)
	var restored: float = stamina_spent * skill_factor * get_durability_per_labor(target_building)
	restored = minf(restored, room)
	restored = minf(restored, float(target_building.rules.max_durability) - target_building.current_durability)
	target_building.current_durability += restored
	plan[PLAN_REPAIRED] = repaired + restored
	return -stamina_spent


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if _aborted:
		return true
	return is_target_valid() and _is_full()


# Fine della riparazione (Integrità piena): si chiudono il piano e la richiesta di riparazione; la prossima riparazione
# farà un piano nuovo.
func on_complete(individual: Variant, context: Dictionary) -> void:
	if target_building != null and not _aborted:
		target_building.repair_plan = {}
		target_building.repair_awaiting_material = false
		target_building.repair_requested = false


# Punto casuale dentro la microcella dell'edificio, come BuildAction/DemolishAction.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + macro_offset)


# Solo l'identità del bersaglio: il progresso è Building.current_durability (salvato da GameSaveService).
func get_save_data() -> Dictionary:
	var data := {}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data
