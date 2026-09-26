class_name HuntService
extends RefCounted

# Funzioni condivise della caccia (2026-09-26, richiesta utente — mira e tiro separati: HuntAction è stata
# sostituita da AimAction + ThrowAction, e quello che non appartiene a un'azione sola vive qui). Stateless,
# funzioni statiche, stesso pattern degli altri *Service:
#   - log di debug della caccia ([HUNT], DebugLogging.SHOW_HUNT_LOGS);
#   - arma di caccia in cintura e sua descrizione;
#   - probabilità di colpire (formula e costanti di taratura, invariate);
#   - recupero dell'arma scagliata (punto di caduta in Task.context, vedi RecoverWeaponAction);
#   - riavvicinamento: quando un tiro non parte o va a vuoto, la Task torna ad avvicinarsi (step aggiunti a
#     metà Task da HumanIndividualActionService._handle_pending_hunt_reapproach, vedi build_reapproach_steps).

# --- Margine di gittata nell'avvicinamento (da tarare) ---
# L'avvicinamento (ApproachPreyAction) si ferma solo quando la preda è entro questa frazione della gittata,
# non al limite esatto: resta un margine per il movimento della preda durante la mira. Mira e lancio
# controllano sempre la gittata piena. 0.8 = con gittata 3.00 ci si ferma a 2.40.
const APPROACH_REACH_FRACTION: float = 0.8

# --- Riavvicinamento (da tarare) ---
# Quante volte, in una stessa caccia, un tiro NON partito (bersaglio uscito dalla gittata durante la mira o
# al lancio) può far tornare ad avvicinarsi. Superato il tetto la caccia si chiude.
const MAX_REAPPROACHES: int = 3

# Chiavi di Task.context usate per chiedere il riavvicinamento (scritte da AimAction/ThrowAction, consumate
# da HumanIndividualActionService._handle_pending_hunt_reapproach nello stesso finish_current_step) e per
# contare i riavvicinamenti da tiro non partito (resta in context, salvata con la Task).
const CONTEXT_PENDING_REAPPROACH := "pending_hunt_reapproach"
const CONTEXT_REAPPROACH_COUNT := "hunt_reapproach_count"
# Valori di CONTEXT_PENDING_REAPPROACH: quale step lo chiede, quindi quali step aggiungere.
const REAPPROACH_AFTER_AIM := "after_aim"       # mira interrotta: [Approach, Aim] (il Throw già in coda resta)
const REAPPROACH_AFTER_THROW_NOT_STARTED := "after_throw_not_started" # lancio non partito: [Approach, Aim, Throw]
const REAPPROACH_AFTER_THROW := "after_throw"   # tiro a vuoto (dopo il recupero dell'arma): [Approach, Aim, Throw], senza tetto

# --- Recupero dell'arma scagliata (2026-09-26, richiesta utente) — vedi RecoverWeaponAction ---
# Punto di caduta dell'arma: dove si trovava il bersaglio al momento del tiro. Scritto da ThrowAction, letto
# da RecoverWeaponAction e dal segnaposto di GameScene, tolto dopo il recupero. Resta in Task.context (salvato
# con la Task): {"macro_x", "macro_y", "x", "y"}, solo numeri perché il context passa da JSON.
const CONTEXT_WEAPON_DROP := "hunt_weapon_drop"
# Richiesta di recupero, scritta da ThrowAction e consumata nello stesso finish_current_step da
# HumanIndividualActionService._handle_pending_hunt_weapon_recovery: {"weapon", "uses", "prey_killed"}.
# L'arma passa da qui allo step RecoverWeaponAction e non resta mai nel context.
const CONTEXT_PENDING_WEAPON_RECOVERY := "pending_hunt_weapon_recovery"

# --- Probabilità di colpire (da tarare) — vedi compute_hit_chance ---
#   p = clamp(scala_specie × arma × skill × taglia × età, HIT_CHANCE_MIN, HIT_CHANCE_MAX)
#   scala_specie = AnimalRules.hit_chance_scale (DEFAULT_HIT_CHANCE_SCALE se la specie non lo dichiara)
#   arma   = attack_power / (attack_power + WEAPON_HALF_POWER)     lancia 12 -> 0.55, coltello 5 -> 0.33
#   skill  = 1 + SKILL_BONUS_AT_MAX × skill_hunting / SKILL_MAX    0 -> 1.0, 1000 -> 1.5
#   taglia = clamp(sqrt(salute_max_preda / SIZE_REFERENCE_HEALTH), SIZE_FACTOR_MIN, SIZE_FACTOR_MAX)
#            salute_max_preda = AnimalRules.max_health × size_multiplier_by_age[fascia] (bersaglio più grande = più facile)
#   età    = AGE_HIT_FACTOR[fascia]                                giovane più sfuggente, anziano più lento
# Valore di riserva di AnimalRules.hit_chance_scale per le specie che non lo dichiarano (2026-09-26: il
# fattore è ora per specie; prima era la costante unica HIT_CHANCE_SCALE, 1.4 per tutte).
const DEFAULT_HIT_CHANCE_SCALE: float = 1.0
const WEAPON_HALF_POWER: float = 10.0
const SKILL_BONUS_AT_MAX: float = 0.5
const SKILL_MAX: float = 1000.0
const SIZE_REFERENCE_HEALTH: float = 20.0
const SIZE_FACTOR_MIN: float = 0.6
const SIZE_FACTOR_MAX: float = 1.4
const AGE_HIT_FACTOR: Array[float] = [0.9, 1.0, 1.15]
const HIT_CHANCE_MIN: float = 0.05
const HIT_CHANCE_MAX: float = 0.95


# Probabilità di colpire un animale (formula e costanti sopra). Statica e pura.
static func compute_hit_chance(attack_power: float, skill_hunting: float, species: String, age_band: int) -> float:
	var weapon_factor: float = attack_power / (attack_power + WEAPON_HALF_POWER) if attack_power > 0.0 else 0.0
	var skill_factor: float = 1.0 + SKILL_BONUS_AT_MAX * clampf(skill_hunting / SKILL_MAX, 0.0, 1.0)
	var size_factor: float = 1.0
	var rules := AnimalCalculator.get_animal_rules(species)
	var species_scale: float = DEFAULT_HIT_CHANCE_SCALE
	if rules != null and rules.hit_chance_scale >= 0.0:
		species_scale = rules.hit_chance_scale
	if rules != null and rules.max_health > 0.0:
		var age_scale: float = 1.0
		if age_band >= 0 and age_band < rules.size_multiplier_by_age.size():
			age_scale = rules.size_multiplier_by_age[age_band]
		size_factor = clampf(sqrt(rules.max_health * age_scale / SIZE_REFERENCE_HEALTH), SIZE_FACTOR_MIN, SIZE_FACTOR_MAX)
	var age_factor: float = AGE_HIT_FACTOR[age_band] if age_band >= 0 and age_band < AGE_HIT_FACTOR.size() else 1.0
	return clampf(species_scale * weapon_factor * skill_factor * size_factor * age_factor, HIT_CHANCE_MIN, HIT_CHANCE_MAX)


# Arma usata per l'attacco nella categoria `category`: il primo slot della cintura che la copre
# (ToolGateService.find_belt_slot_for) — lo stesso che il gate considera, che describe_weapon mostra nei log
# e che consume_tool_uses consuma, così l'arma che colpisce è sempre quella che si usura. "" se non c'è.
static func pick_weapon(individual: Variant, category: TaskTypes.ToolCategory) -> String:
	var slot := ToolGateService.find_belt_slot_for(individual, category)
	return individual.get_equipped_tool(slot) if slot != -1 else ""


# Gittata utile dell'attaccante: la max_range più alta tra le armi in cintura della categoria, mai sotto la
# distanza di contatto per le armi da corpo a corpo. Stessa regola dell'avvicinamento.
static func compute_reach(individual: Variant, category: TaskTypes.ToolCategory) -> float:
	return maxf(ToolGateService.get_belt_max_range_for(individual, category), ApproachPreyAction.MELEE_REACH)


# Step da aggiungere per tornare ad avvicinarsi al bersaglio (vedi le costanti REAPPROACH_*). Oggi il
# bersaglio è sempre un animale: l'avvicinamento è ApproachPreyAction.
static func build_reapproach_steps(combat_target: CombatTarget, include_throw: bool) -> Array[Action]:
	var steps: Array[Action] = [
		ApproachPreyAction.new(combat_target.target_id, combat_target.label, combat_target.macro_coords),
		AimAction.new(combat_target),
	]
	if include_throw:
		steps.append(ThrowAction.new(combat_target))
	return steps


# Punto di caduta dell'arma letto dal context: {"macro_coords": Vector2i, "position": Vector2 locale alla
# macrocella}, {} se assente.
static func read_weapon_drop(context: Dictionary) -> Dictionary:
	if not context.has(CONTEXT_WEAPON_DROP):
		return {}
	var drop: Dictionary = context[CONTEXT_WEAPON_DROP]
	return {
		"macro_coords": Vector2i(int(drop.get("macro_x", 0)), int(drop.get("macro_y", 0))),
		"position": Vector2(float(drop.get("x", 0.0)), float(drop.get("y", 0.0))),
	}


static func write_weapon_drop(context: Dictionary, macro_coords: Vector2i, local_position: Vector2) -> void:
	context[CONTEXT_WEAPON_DROP] = {
		"macro_x": macro_coords.x, "macro_y": macro_coords.y, "x": local_position.x, "y": local_position.y,
	}


# true se l'individuo ha ancora un'arma di caccia in cintura o nello zaino (dopo che quella scagliata si è rotta).
static func has_hunting_weapon_available(individual: HumanIndividual) -> bool:
	if ToolGateService.find_belt_slot_for(individual, TaskTypes.ToolCategory.HUNTING) != -1:
		return true
	for tool_name in ToolGateService.get_tools_covering(TaskTypes.ToolCategory.HUNTING):
		if individual.get_carried_quantity(tool_name) > 0:
			return true
	return false


# --- Log di debug della caccia (DebugLogging.SHOW_HUNT_LOGS) — punto unico di stampa ---

static func is_logging() -> bool:
	return DebugLogging.ENABLED and DebugLogging.SHOW_HUNT_LOGS


# Riga "[HUNT] #id Nome: testo", solo con il flag acceso.
static func log_event(individual: Variant, text: String) -> void:
	if not is_logging():
		return
	if individual == null:
		print("[HUNT] %s" % text)
		return
	print("[HUNT] #%d %s: %s" % [individual.id, individual.name, text])


static func is_hunt_task(task: Task) -> bool:
	return task != null and task.task_name == "task_hunt_name"


# Arma di caccia in cintura, per i log: "Lancia di legno (gittata 3.0)". "nessuna arma in cintura" se manca.
static func describe_weapon(individual: HumanIndividual) -> String:
	var slot := ToolGateService.find_belt_slot_for(individual, TaskTypes.ToolCategory.HUNTING)
	if slot == -1:
		return "nessuna arma in cintura"
	var tool_range := ToolGateService.get_belt_max_range_for(individual, TaskTypes.ToolCategory.HUNTING)
	return "%s (gittata %.1f)" % [IconRegistry.get_resource_display_name(individual.get_equipped_tool(slot)), tool_range]


# Motivo leggibile della perdita del bersaglio di una Task di caccia (per i log di chiusura fuori dalle
# azioni): stato del bersaglio del primo step che ne ha uno.
static func describe_task_prey_loss(task: Task) -> String:
	if task != null:
		for step in task.steps:
			if step is AimAction:
				return CombatTarget.describe_status((step as AimAction).combat_target.get_status())
			if step is ThrowAction:
				return CombatTarget.describe_status((step as ThrowAction).combat_target.get_status())
			if step is RecoverWeaponAction:
				return CombatTarget.describe_status((step as RecoverWeaponAction).combat_target.get_status())
			if step is ApproachPreyAction:
				return CombatTarget.describe_status(ApproachPreyAction.get_prey_status((step as ApproachPreyAction).prey_id))
	return "bersaglio non valido"
