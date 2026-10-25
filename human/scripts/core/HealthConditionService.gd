class_name HealthConditionService
extends RefCounted

# Condizioni di salute (2026-10-25, richiesta utente — malattie e ferite nello stesso modello; prima IllnessService):
# la "cartella clinica" del pipottino. HumanIndividual.health_conditions è una lista di {"id", "days", "phase"} (salvata
# con la partita): una febbre e una ferita insieme, o due ferite diverse. Qui si aggiunge una condizione, la si fa
# avanzare ogni giorno dentro l'interazione dei vitali (HumanVitalsInteractionService.apply_daily_interaction) e la si
# toglie quando guarisce. PERCHÉ arriva lo decide chi la provoca (eventi, in futuro contagio/caccia/incidenti/guerra),
# che chiama can_get/add_condition. Fasi (acuta → convalescenza → guarigione): vedi HealthConditionRules. Stateless,
# stesso pattern degli altri *Service; regole lette una volta e tenute in memoria.

const DATA_DIR := "res://human/data/health_conditions/"
# Sottocartella -> categoria (DataFileIndex avvisa se un file sta nella cartella sbagliata).
const FOLDER_CATEGORIES := {
	"illnesses": HealthConditionRules.Category.ILLNESS,
	"wounds": HealthConditionRules.Category.WOUND,
}
const PHASE_ACUTE := "acute"
const PHASE_CONVALESCENCE := "convalescence"
# Rimedio preso oggi (2026-10-25, richiesta utente — infuso): chiave nel dizionario della condizione, messa da
# apply_remedy e tolta dal prossimo advance_daily (che quel giorno non toglie salute se il rimedio lo blocca). Vale anche
# come "massimo un rimedio al giorno per condizione". Salvata con la condizione.
const KEY_REMEDY := "remedy"
const RESOURCE_DIR := "res://simulation/data/secondary_resources/"

static var _rules_cache: Dictionary = {}  # id -> HealthConditionRules
static var _remedy_names_cache: Array[String] = []
static var _remedy_names_loaded: bool = false


static func get_rules(condition_id: String) -> HealthConditionRules:
	if condition_id == "":
		return null
	if not _rules_cache.has(condition_id):
		var path := DataFileIndex.resolve_path(DATA_DIR, condition_id, FOLDER_CATEGORIES)
		_rules_cache[condition_id] = load(path) as HealthConditionRules if path != "" else null
	return _rules_cache[condition_id]


static func has_condition(individual: HumanIndividual, condition_id: String) -> bool:
	for entry in individual.health_conditions:
		if String(entry.get("id", "")) == condition_id:
			return true
	return false


# `individual` può prendere `condition_id`: condizione esistente, non già presente (la stessa due volte non si somma) e
# fascia d'età ammessa (HealthConditionRules.age_bands, vuota = tutte).
static func can_get(individual: HumanIndividual, condition_id: String, game_data: GameData) -> bool:
	var rules := get_rules(condition_id)
	if rules == null or individual == null or has_condition(individual, condition_id):
		return false
	return rules.age_bands.is_empty() or GameContext.age_band_for(individual, game_data) in rules.age_bands


# Dà a `individual` la condizione `condition_id` (se can_get): toglie subito immediate_health_loss ed estrae la durata
# della fase acuta.
static func add_condition(individual: HumanIndividual, condition_id: String, game_data: GameData) -> bool:
	if not can_get(individual, condition_id, game_data):
		return false
	var rules := get_rules(condition_id)
	individual.current_health = maxf(individual.current_health - rules.immediate_health_loss, 0.0)
	var days := randi_range(rules.min_duration_days, maxi(rules.min_duration_days, rules.max_duration_days))
	individual.health_conditions.append({"id": condition_id, "days": days, "phase": PHASE_ACUTE})
	return true


# Un giorno di tutte le condizioni. Fase acuta: perdite acute e un giorno in meno; a fine durata guarita se la salute è
# almeno alla soglia, altrimenti convalescenza. Convalescenza: perdite di convalescenza; guarita appena la salute è alla
# soglia. Ritorna la salute tolta in totale.
static func advance_daily(individual: HumanIndividual) -> float:
	if individual.health_conditions.is_empty():
		return 0.0
	var health_before := individual.current_health
	var remaining: Array[Dictionary] = []
	for entry in individual.health_conditions:
		var rules := get_rules(String(entry.get("id", "")))
		if rules == null:
			continue
		var phase := String(entry.get("phase", PHASE_ACUTE))
		var days := int(entry.get("days", 0))
		# Rimedio preso oggi che blocca la perdita: niente salute tolta (la felicità sì), il giorno conta comunque.
		var remedy_rules := CaloricCalculator.get_caloric_source_rules(String(entry.get(KEY_REMEDY, "")))
		var health_factor := 0.0 if remedy_rules != null and remedy_rules.remedy_blocks_daily_loss else 1.0
		if phase == PHASE_ACUTE:
			_lose(individual, rules.daily_health_loss * health_factor, rules.daily_happiness_loss)
			days -= 1
			if days <= 0:
				if _is_recovered(individual, rules):
					continue
				phase = PHASE_CONVALESCENCE
		else:
			_lose(individual, rules.convalescence_daily_health_loss * health_factor, rules.convalescence_daily_happiness_loss)
			if _is_recovered(individual, rules):
				continue
		remaining.append({"id": rules.id, "days": maxi(days, 0), "phase": phase})
	individual.health_conditions = remaining
	return health_before - individual.current_health


# Fase di ogni condizione (id -> fase), da prendere prima di advance_daily per confrontarla dopo con phase_changes.
# --- Rimedi (2026-10-25, richiesta utente) ---
# Le risorse con SecondaryResourceRules.remedy_treats_condition_ids non vuoto, lette una volta.
static func remedy_names() -> Array[String]:
	if not _remedy_names_loaded:
		_remedy_names_loaded = true
		for resource_name in CaloricCalculator.list_secondary_resource_names():
			var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
			if rules != null and not rules.remedy_treats_condition_ids.is_empty():
				_remedy_names_cache.append(resource_name)
	return _remedy_names_cache


# Condizioni di `individual` che `remedy_name` cura e che oggi non hanno ancora preso un rimedio.
static func treatable_conditions(individual: HumanIndividual, remedy_name: String) -> Array[String]:
	var result: Array[String] = []
	var rules := CaloricCalculator.get_caloric_source_rules(remedy_name)
	if rules == null or individual == null:
		return result
	for entry in individual.health_conditions:
		var condition_id := String(entry.get("id", ""))
		if condition_id in rules.remedy_treats_condition_ids and String(entry.get(KEY_REMEDY, "")) == "":
			result.append(condition_id)
	return result


# Rimedi che oggi servirebbero a `individual` (almeno una condizione curabile non ancora trattata), in ordine di file.
static func useful_remedies(individual: HumanIndividual) -> Array[String]:
	var result: Array[String] = []
	if individual == null or individual.health_conditions.is_empty():
		return result
	for remedy_name in remedy_names():
		if not treatable_conditions(individual, remedy_name).is_empty():
			result.append(remedy_name)
	return result


# Applica un'unità di `remedy_name` a `individual`: salute + remedy_health_restore × health_factor (tetto al massimo) e
# ogni condizione curata segnata come trattata oggi. false se non c'era nulla da curare (il rimedio non va consumato).
# `health_factor`: 1.0 per l'autocura; la Medicina di chi cura per la cura somministrata (SkillEffectService, "heal").
static func apply_remedy(individual: HumanIndividual, remedy_name: String, health_factor: float = 1.0) -> bool:
	var treated := treatable_conditions(individual, remedy_name)
	if treated.is_empty():
		return false
	var rules := CaloricCalculator.get_caloric_source_rules(remedy_name)
	individual.current_health = minf(individual.current_health + rules.remedy_health_restore * health_factor, individual.max_health)
	for entry in individual.health_conditions:
		if String(entry.get("id", "")) in treated:
			entry[KEY_REMEDY] = remedy_name
	return true


# A letto e con un rimedio utile: lo deve portare un guaritore (HealJobProvider); chi non è a letto se lo prende da sé.
static func needs_remedy_from_healer(individual: HumanIndividual) -> bool:
	return requires_bed_rest(individual) and not useful_remedies(individual).is_empty()


static func phases(individual: HumanIndividual) -> Dictionary:
	var result := {}
	for entry in individual.health_conditions:
		result[String(entry.get("id", ""))] = String(entry.get("phase", PHASE_ACUTE))
	return result


# Cambi rispetto a `before` (phases di prima): [{"id", "change": "convalescence" | "recovered"}]. Le condizioni nuove
# non contano (le annuncia chi le provoca).
static func phase_changes(individual: HumanIndividual, before: Dictionary) -> Array[Dictionary]:
	var after := phases(individual)
	var changes: Array[Dictionary] = []
	for condition_id in before:
		if not after.has(condition_id):
			changes.append({"id": condition_id, "change": "recovered"})
		elif before[condition_id] == PHASE_ACUTE and after[condition_id] == PHASE_CONVALESCENCE:
			changes.append({"id": condition_id, "change": PHASE_CONVALESCENCE})
	return changes


static func _lose(individual: HumanIndividual, health_loss: float, happiness_loss: float) -> void:
	individual.current_health = maxf(individual.current_health - health_loss, 0.0)
	individual.current_happiness = maxf(individual.current_happiness - happiness_loss, 0.0)


static func _is_recovered(individual: HumanIndividual, rules: HealthConditionRules) -> bool:
	return individual.current_health >= rules.recovery_health_ratio * individual.max_health


static func has_category(individual: HumanIndividual, category: HealthConditionRules.Category) -> bool:
	for entry in individual.health_conditions:
		var rules := get_rules(String(entry.get("id", "")))
		if rules != null and rules.category == category:
			return true
	return false


# Almeno una condizione che manda a letto nella sua fase attuale (HumanIndividual.is_sick).
static func requires_bed_rest(individual: HumanIndividual) -> bool:
	for entry in individual.health_conditions:
		var rules := get_rules(String(entry.get("id", "")))
		if rules == null:
			continue
		var convalescent := String(entry.get("phase", PHASE_ACUTE)) == PHASE_CONVALESCENCE
		if rules.convalescence_bed_rest if convalescent else rules.bed_rest:
			return true
	return false


# Causa della morte a salute 0: ferite se ha solo ferite, altrimenti malattia (anche con salute a 0 senza condizioni).
static func death_cause(individual: HumanIndividual) -> DeathTypes.DeathCause:
	if has_category(individual, HealthConditionRules.Category.WOUND) and not has_category(individual, HealthConditionRules.Category.ILLNESS):
		return DeathTypes.DeathCause.WOUNDS
	return DeathTypes.DeathCause.ILLNESS


# Nomi tradotti delle condizioni in corso, separati da virgola ("" = nessuna); in convalescenza "convalescente da X".
static func display_names(individual: HumanIndividual) -> String:
	var names: Array[String] = []
	for entry in individual.health_conditions:
		var rules := get_rules(String(entry.get("id", "")))
		if rules == null:
			continue
		var name := GameContext.tr_text(rules.display_name)
		if String(entry.get("phase", PHASE_ACUTE)) == PHASE_CONVALESCENCE:
			name = GameContext.tr_text("health_condition_convalescent").format({"condition": name})
		names.append(name)
	return ", ".join(names)


# Righe del tooltip della barra della salute (2026-10-25): una per condizione, "lacerazione: fase acuta, a letto" o
# "febbre: convalescenza"; niente giorni (il giocatore non sa quando guarirà).
static func tooltip_lines(individual: HumanIndividual) -> Array[String]:
	var lines: Array[String] = []
	for entry in individual.health_conditions:
		var rules := get_rules(String(entry.get("id", "")))
		if rules == null:
			continue
		var convalescent := String(entry.get("phase", PHASE_ACUTE)) == PHASE_CONVALESCENCE
		var phase := GameContext.tr_text("health_condition_phase_convalescence" if convalescent else "health_condition_phase_acute")
		var bed_rest := rules.convalescence_bed_rest if convalescent else rules.bed_rest
		if bed_rest:
			phase += ", " + GameContext.tr_text("health_condition_bed_rest")
		lines.append("%s: %s" % [GameContext.tr_text(rules.display_name), phase])
	return lines


# Per il log: "fever (7 gg), laceration (convalescenza)".
static func debug_text(individual: HumanIndividual) -> String:
	var parts: Array[String] = []
	for entry in individual.health_conditions:
		if String(entry.get("phase", PHASE_ACUTE)) == PHASE_CONVALESCENCE:
			parts.append("%s (convalescenza)" % String(entry.get("id", "")))
		else:
			parts.append("%s (%d gg)" % [String(entry.get("id", "")), int(entry.get("days", 0))])
	return ", ".join(parts)
