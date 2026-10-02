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

# --- Macellazione dopo la caccia (2026-09-26, richiesta utente) ---
# Carcassa creata dal colpo letale (ThrowAction): {"macro_x", "macro_y", "micro_x", "micro_y", "id"}, solo numeri
# (il context passa da JSON). Resta in Task.context fino alla fine della caccia.
const CONTEXT_KILL_CARCASS := "hunt_kill_carcass"
# Richiesta di accodare la macellazione su quella carcassa (stessa forma), scritta dopo il recupero dell'arma
# (RecoverWeaponAction) o subito dal colpo letale se l'arma si è rotta e non c'è nulla da recuperare (ThrowAction);
# consumata nello stesso finish_current_step da HumanIndividualActionService._handle_pending_hunt_butcher.
const CONTEXT_PENDING_BUTCHER := "pending_hunt_butcher"
# Nessuna arma da caccia rimasta (2026-10-01, regole delle armi): scritta insieme alla chiusura anticipata da
# continue_with_other_weapon_or_stop. HumanIndividualActionService mostra il messaggio al giocatore e chiude la caccia,
# diretta o in zona (niente ritorno alla pattuglia).
const CONTEXT_NO_WEAPON := "hunt_no_weapon_left"
# Portata massima di un'arma da mischia (vedi is_melee_weapon).
const MELEE_MAX_REACH: float = 1.0

# --- Probabilità di colpire (da tarare) — vedi compute_hit_chance ---
#   p = clamp(scala_specie × arma × skill × taglia × età, HIT_CHANCE_MIN, HIT_CHANCE_MAX)
#   scala_specie = AnimalRules.hit_chance_scale (DEFAULT_HIT_CHANCE_SCALE se la specie non lo dichiara)
#   arma   = attack_power / (attack_power + WEAPON_HALF_POWER)     lancia 12 -> 0.55, coltello 5 -> 0.33
#   skill  = SkillEffectService, chiave SKILL_EFFECT_KEY ("hunt_throw", skill_action_effects.tres):
#            1 + 0.5 × clamp(skill_hunting / 1000, 0, 1)            0 -> 1.0, 1000 -> 1.5
#   taglia = clamp(sqrt(salute_max_preda / SIZE_REFERENCE_HEALTH), SIZE_FACTOR_MIN, SIZE_FACTOR_MAX)
#            salute_max_preda = AnimalRules.max_health × size_multiplier_by_age[fascia] (bersaglio più grande = più facile)
#   età    = AGE_HIT_FACTOR[fascia]                                giovane più sfuggente, anziano più lento
# Valore di riserva di AnimalRules.hit_chance_scale per le specie che non lo dichiarano (2026-09-26: il
# fattore è ora per specie; prima era la costante unica HIT_CHANCE_SCALE, 1.4 per tutte).
const DEFAULT_HIT_CHANCE_SCALE: float = 1.0
const WEAPON_HALF_POWER: float = 10.0
# Chiave dell'effetto della skill di caccia (2026-09-27 — prima SKILL_BONUS_AT_MAX/SKILL_MAX qui): bonus e skill_max
# sono in skill_action_effects.tres, il fattore lo calcola SkillEffectService. Usata da ThrowAction
# (skill_effect_key) e da choose_weapon.
const SKILL_EFFECT_KEY := "hunt_throw"
const SIZE_REFERENCE_HEALTH: float = 20.0
const SIZE_FACTOR_MIN: float = 0.6
const SIZE_FACTOR_MAX: float = 1.4
const AGE_HIT_FACTOR: Array[float] = [0.9, 1.0, 1.15]
const HIT_CHANCE_MIN: float = 0.05
const HIT_CHANCE_MAX: float = 0.95


# Probabilità di colpire un animale (formula e costanti sopra). Statica e pura. `skill_factor` (2026-09-27): il
# fattore della skill già calcolato da SkillEffectService (chiave SKILL_EFFECT_KEY), non più la skill grezza.
static func compute_hit_chance(attack_power: float, skill_factor: float, species: String, age_band: int) -> float:
	var weapon_factor: float = attack_power / (attack_power + WEAPON_HALF_POWER) if attack_power > 0.0 else 0.0
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


# --- Arma della caccia (2026-09-27, richiesta utente — scelta dell'arma) ---
# Una sola arma per tutta la caccia, salvata in Task.context[CONTEXT_HUNT_WEAPON] (nome della risorsa): la usano
# avvicinamento (gittata), mira, lancio (gittata, attacco, usura), log e recupero. Scelta con choose_weapon: tra gli
# attrezzi della categoria IN CINTURA (lo zaino non conta), quello con la probabilità di colpire più alta contro la
# preda (compute_hit_chance); a parità, quello con più usi rimasti. Se l'arma salvata non è più in cintura (persa,
# rotta), resolve_weapon sceglie di nuovo con la stessa regola; nessuna arma = "" (la caccia si chiude come prima).
const CONTEXT_HUNT_WEAPON := "hunt_weapon"


# Migliore arma in cintura della categoria contro la preda `species`/`age_band` (vedi sopra). "" se nessuna. Con
# species "" o age_band -1 i fattori della preda valgono 1: il confronto resta sull'attacco dell'arma.
static func choose_weapon(individual: Variant, category: TaskTypes.ToolCategory, species: String, age_band: int) -> String:
	var best_name := ""
	var best_chance := -1.0
	var best_uses := -1
	var skill_factor := SkillEffectService.get_factor(SKILL_EFFECT_KEY, individual)
	for slot in range(individual.get_tool_slot_count()):
		var tool_name: String = individual.get_equipped_tool(slot)
		if tool_name == "" or not ToolGateService._tool_categories(tool_name).has(category):
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
		var chance := compute_hit_chance(rules.attack_power if rules != null else 0.0, skill_factor, species, age_band)
		var uses: int = individual.get_equipped_tool_uses(slot)
		if chance > best_chance + 0.000001 or (absf(chance - best_chance) <= 0.000001 and uses > best_uses):
			best_name = tool_name
			best_chance = chance
			best_uses = uses
	return best_name


# Arma della caccia per questo step: quella salvata nel context se è ancora in cintura, altrimenti una nuova scelta
# (salvata nel context, con un log se cambia). "" = nessuna arma della categoria in cintura.
static func resolve_weapon(individual: Variant, context: Dictionary, category: TaskTypes.ToolCategory, species: String, age_band: int) -> String:
	var saved: String = String(context.get(CONTEXT_HUNT_WEAPON, ""))
	if saved != "" and find_weapon_slot(individual, saved) != -1:
		return saved
	var chosen := choose_weapon(individual, category, species, age_band)
	if chosen == "":
		context.erase(CONTEXT_HUNT_WEAPON)
		return ""
	context[CONTEXT_HUNT_WEAPON] = chosen
	if saved != chosen:
		log_event(individual, "arma della caccia: %s%s." % [
			describe_weapon(individual, chosen), (" (al posto di %s, non più in cintura)" % IconRegistry.get_resource_display_name(saved)) if saved != "" else ""
		])
	return chosen


# resolve_weapon con specie e fascia d'età presi dal bersaglio (-1 se l'animale non c'è più).
static func resolve_weapon_for_target(individual: Variant, context: Dictionary, category: TaskTypes.ToolCategory, combat_target: CombatTarget) -> String:
	var animal: AnimalVisualGroup = combat_target.get_animal() if combat_target != null else null
	return resolve_weapon(
		individual, context, category, combat_target.label if combat_target != null else "", int(animal.age_band) if animal != null else -1
	)


# Slot di cintura con `weapon_name`: se ce n'è più d'uno, quello con più usi rimasti (lo stesso che choose_weapon
# considera). -1 se non è in cintura.
static func find_weapon_slot(individual: Variant, weapon_name: String) -> int:
	var best_slot := -1
	var best_uses := -1
	for slot in range(individual.get_tool_slot_count()):
		if individual.get_equipped_tool(slot) != weapon_name:
			continue
		var uses: int = individual.get_equipped_tool_uses(slot)
		if uses > best_uses:
			best_slot = slot
			best_uses = uses
	return best_slot


# Gittata dell'arma `weapon_name` (la SUA max_range, non la massima della cintura), mai sotto la distanza di contatto
# per le armi da corpo a corpo. MELEE_REACH se nessuna arma.
# Arma da mischia (2026-10-01, regole delle armi — UNICO punto della regola, da sostituire un domani con un campo
# esplicito delle regole dell'arma): portata ≤ MELEE_MAX_REACH. Non viene mai lanciata: l'attacco avviene entro la
# portata, consuma un uso, ma l'arma resta in cintura — nessuna caduta, nessun recupero, mai persa con l'animale.
static func is_melee_weapon(weapon_name: String) -> bool:
	return compute_weapon_reach(weapon_name) <= MELEE_MAX_REACH


# Cambio d'arma (2026-10-01, regole delle armi): l'arma in uso si è rotta, è stata persa o non c'è più in cintura. Con
# un'altra arma da caccia (cintura o zaino, has_hunting_weapon_available) la caccia continua: arma della caccia
# azzerata (resolve_weapon sceglie la nuova) e riavvicinamento `reapproach_mode`. Senza: chiusura anticipata con
# CONTEXT_NO_WEAPON (messaggio al giocatore). `reason` = motivo per i log/la chiusura.
static func continue_with_other_weapon_or_stop(individual: Variant, context: Dictionary, reason: String, reapproach_mode: String = REAPPROACH_AFTER_THROW) -> void:
	context.erase(CONTEXT_HUNT_WEAPON)
	if has_hunting_weapon_available(individual):
		context[CONTEXT_PENDING_REAPPROACH] = reapproach_mode
		log_event(individual, "%s: si continua con un'altra arma (%s)." % [reason, describe_weapon(individual)])
		return
	context[CONTEXT_NO_WEAPON] = true
	context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "%s e nessun'altra arma da caccia" % reason


static func compute_weapon_reach(weapon_name: String) -> float:
	var rules: SecondaryResourceRules = CaloricCalculator.get_caloric_source_rules(weapon_name) if weapon_name != "" else null
	return maxf(rules.max_range if rules != null else 0.0, ApproachPreyAction.MELEE_REACH)


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


# Momento di gioco per i log (2026-09-27, diagnosi macellazione accodata due volte): "anno A giorno G, frame F".
# Il frame del motore distingue due righe nello stesso giorno (stesso frame = stessa chiamata a catena).
static func describe_now() -> String:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return "frame %d" % Engine.get_process_frames()
	return "anno %d giorno %d, frame %d" % [game_data.year, game_data.current_day, Engine.get_process_frames()]


static func is_hunt_task(task: Task) -> bool:
	# Anche la caccia in zona (2026-10-01, HuntZoneService.TASK_NAME): stessi step, stessi log, stesse regole di coda.
	return task != null and (task.task_name == "task_hunt_name" or task.task_name == HuntZoneService.TASK_NAME)


# Arma di caccia per i log: "Lancia di legno (gittata 3.0)", con la gittata di QUELL'arma. `weapon_name` vuoto = la
# migliore in cintura secondo choose_weapon (senza dati sulla preda). "nessuna arma in cintura" se manca.
static func describe_weapon(individual: Variant, weapon_name: String = "") -> String:
	var weapon := weapon_name if weapon_name != "" else choose_weapon(individual, TaskTypes.ToolCategory.HUNTING, "", -1)
	if weapon == "":
		return "nessuna arma in cintura"
	return "%s (gittata %.1f)" % [IconRegistry.get_resource_display_name(weapon), compute_weapon_reach(weapon)]


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
