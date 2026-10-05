class_name ThrowAction
extends Action

# Scagliare l'arma contro un bersaglio (2026-09-26, richiesta utente — caccia: mira e tiro separati, prima
# accorpati in HuntAction). Parametrizzata dal BERSAGLIO (CombatTarget), non dalla preda: servirà anche per
# il combattimento contro bersagli umani; oggi il bersaglio è sempre un animale.
#
# Istantanea, costo fisso di stamina (STAMINA_COST) solo se il tiro parte. Al primo tick (_resolve):
#   - bersaglio sparito o perso di vista, o nessuna arma in cintura -> la caccia si chiude;
#   - bersaglio fuori gittata ALL'ISTANTE del lancio -> "tiro non partito": nessun uso, nessuna fuga, si torna
#     ad avvicinarsi (con il tetto di HuntService.MAX_REAPPROACHES);
#   - altrimenti l'arma parte: si consuma un uso (ToolGateService.consume_tool_uses, rottura segnalata) e,
#     se è ancora integra, lascia la cintura (2026-09-26, recupero dell'arma scagliata); il punto in cui si
#     trovava il bersaglio va in Task.context (HuntService.CONTEXT_WEAPON_DROP). Gli animali entro il loro
#     raggio di fuga scappano (AnimalGroupRenderer.trigger_flee) e si risolve l'esito con la formula di
#     HuntService.compute_hit_chance:
#       - a segno e letale: segnale target_killed (GameScene rimuove il bersaglio); l'arma integra è caduta
#         con lui -> recupero (RecoverWeaponAction), poi la caccia si conclude;
#       - a segno non letale: il bersaglio ferito fugge portando via l'arma (persa) e la caccia si chiude;
#       - a vuoto: arma integra -> recupero, poi si torna ad avvicinarsi se il bersaglio è ancora in vista;
#         arma rotta -> si torna subito ad avvicinarsi se c'è un'altra arma di caccia, altrimenti si chiude.
#     Il recupero è chiesto con HuntService.CONTEXT_PENDING_WEAPON_RECOVERY e inserito da
#     HumanIndividualActionService._handle_pending_hunt_weapon_recovery.

# Emesso quando un colpo porta il bersaglio a salute 0: chi ha accesso al mondo (GameScene._on_target_killed)
# lo rimuove. `target_kind` = CombatTarget.Kind; per un animale `label` è la specie e `age_band` la sua fascia.
signal target_killed(target_kind: int, target_id: int, label: String, age_band: int, target_macro_coords: Vector2i)

# Costo di stamina del lancio, fisso (solo se il tiro parte).
const STAMINA_COST: float = 10.0

var combat_target: CombatTarget = null
var weapon_category: TaskTypes.ToolCategory = TaskTypes.ToolCategory.HUNTING

# Lancio già risolto (non salvato: lo step si completa nello stesso frame in cui si risolve).
var _done: bool = false


func _init(p_combat_target: CombatTarget = null, p_weapon_category: TaskTypes.ToolCategory = TaskTypes.ToolCategory.HUNTING) -> void:
	target = null
	combat_target = p_combat_target if p_combat_target != null else CombatTarget.new()
	weapon_category = p_weapon_category
	required_tool_categories = [weapon_category]
	disallowed_age_bands = AimAction.attack_disallowed_age_bands(weapon_category)
	# Effetto della skill di caccia sulla probabilità di colpire (2026-09-27, SkillEffectService).
	skill_effect_key = HuntService.SKILL_EFFECT_KEY


func is_target_valid() -> bool:
	return combat_target.is_valid()


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_done = false


# Istantanea: si risolve al primo tick e costa STAMINA_COST solo se l'arma parte davvero.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done:
		return 0.0
	_done = true
	return -STAMINA_COST if _resolve(individual, context) else 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


# Ritorna true se il tiro è partito (arma scagliata), false se non è partito.
func _resolve(individual: Variant, context: Dictionary) -> bool:
	var status := combat_target.get_status()
	if status != CombatTarget.Status.OK:
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = CombatTarget.describe_status(status)
		return false
	# Arma della caccia (2026-09-27): la stessa per tutta la caccia (HuntService.resolve_weapon_for_target); gittata,
	# attacco e usura sono i suoi.
	var weapon_name := HuntService.resolve_weapon_for_target(individual, context, weapon_category, combat_target)
	if weapon_name == "":
		# Cambio d'arma (2026-10-01): un'altra arma nello zaino -> riavvicinamento (che la porta in cintura), altrimenti stop.
		HuntService.continue_with_other_weapon_or_stop(individual, context, "nessuna arma in cintura al momento del lancio", HuntService.REAPPROACH_AFTER_THROW_NOT_STARTED)
		return false
	var distance := combat_target.distance_from(individual)
	var reach := HuntService.compute_weapon_reach(weapon_name)
	if distance > reach:
		context[HuntService.CONTEXT_PENDING_REAPPROACH] = HuntService.REAPPROACH_AFTER_THROW_NOT_STARTED
		HuntService.log_event(individual, "tiro NON PARTITO: %s fuori gittata al momento del lancio (distanza %.2f > gittata %.2f)." % [
			combat_target.describe(), distance, reach
		])
		return false

	# L'arma parte: uso consumato, arma fuori dalla cintura se integra, fuga, esito.
	var weapon_display := IconRegistry.get_resource_display_name(weapon_name)
	# Forza del tiro (2026-10-04): quella della munizione in uso per un'arma a munizioni, altrimenti quella dell'arma.
	var attack_power: float = HuntService.get_attack_power(individual, weapon_name)
	# Usura dello slot dell'arma scelta (non del primo attrezzo della categoria in cintura).
	var weapon_slot := HuntService.find_weapon_slot(individual, weapon_name)
	var broken: Array[String] = []
	if weapon_slot != -1 and individual.consume_equipped_tool_use(weapon_slot, null):
		broken.append(weapon_name)
	# Munizione (2026-10-04): un uso anche della munizione in cintura; a zero sparisce come gli altri attrezzi.
	var ammo_broken := HuntService.consume_ammo(individual, weapon_name)
	if ammo_broken != "":
		broken.append(ammo_broken)
	if not broken.is_empty():
		report_broken_tools(individual, broken)
		HuntService.log_event(individual, "arma rotta dopo il lancio: %s." % str(broken))
	# Arma integra = ancora nel suo slot dopo il consumo. Arma da lancio integra: lascia la cintura, da qui esiste solo
	# nel recupero. Arma da mischia (HuntService.is_melee_weapon, 2026-10-01): mai lanciata, resta in cintura.
	# Munizioni finite (2026-10-04): l'arma resta in cintura ma non può più tirare — stesso percorso dell'arma rotta
	# (cambio d'arma o chiusura della caccia).
	var weapon_intact: bool = weapon_slot != -1 and individual.get_equipped_tool(weapon_slot) == weapon_name \
		and ToolGateService.has_required_ammo(individual, weapon_name)
	var melee := HuntService.is_melee_weapon(weapon_name)
	# Scagliata solo se lo dice l'arma (HuntService.is_thrown_weapon: a distanza e thrown_on_attack, il default).
	var weapon_thrown: bool = weapon_intact and HuntService.is_thrown_weapon(weapon_name)
	var weapon_uses := 0
	if weapon_thrown:
		weapon_uses = individual.get_equipped_tool_uses(weapon_slot)
		individual.take_equipped_tool(weapon_slot, null)
	var animal := combat_target.get_animal()
	if weapon_thrown:
		HuntService.write_weapon_drop(context, animal.macro_coords, animal.position)
	else:
		context.erase(HuntService.CONTEXT_WEAPON_DROP)
	AnimalGroupRenderer.trigger_flee(animal.macro_coords, animal.position, individual.home_macro_coords, individual.position)
	HuntService.log_event(individual, "%s di %s su %s (distanza %.2f): gli animali entro il raggio di fuga scappano." % [
		"colpo in mischia" if melee else ("lancio" if weapon_thrown else "tiro"), weapon_display, combat_target.describe(), distance
	])

	var skill_factor := SkillEffectService.get_factor_for_action(self, individual, context)
	var hit_chance := HuntService.compute_hit_chance(attack_power, skill_factor, combat_target.label, animal.age_band)
	var roll := randf()
	if roll >= hit_chance:
		HuntService.log_event(individual, "tiro a VUOTO su %s (probabilità %.0f%%, tiro %.2f)." % [combat_target.describe(), hit_chance * 100.0, roll])
		if weapon_thrown:
			_request_recovery(context, weapon_name, weapon_uses, false)
		elif weapon_intact:
			# Mischia: l'arma è in mano, si torna sotto la preda per un altro colpo.
			context[HuntService.CONTEXT_PENDING_REAPPROACH] = HuntService.REAPPROACH_AFTER_THROW
		else:
			HuntService.continue_with_other_weapon_or_stop(individual, context, "%s rotta nel colpo a vuoto" % weapon_display)
		return true

	var health_before: float = animal.health
	animal.health = maxf(animal.health - attack_power, 0.0)
	HuntService.log_event(individual, "COLPITO %s (probabilità %.0f%%, tiro %.2f): danno %.1f, salute %.1f -> %.1f." % [
		combat_target.describe(), hit_chance * 100.0, roll, attack_power, health_before, animal.health
	])
	if animal.health <= 0.0:
		HuntService.log_event(individual, "%s UCCISO (fascia %s)." % [
			combat_target.describe(), String(GameTypes.AgeBand.keys()[animal.age_band])
		])
		# Carcassa a terra nel punto della preda (2026-09-26 — prima la creava GameScene._on_prey_killed), con la
		# regola di posa dei mucchi; il riferimento resta nel context per la macellazione dopo la caccia.
		var carcass_pile := GroundPileService.drop_carcass(
			GameSettings.active_game_data, animal.macro_coords, animal.position, combat_target.label, int(animal.age_band)
		)
		if carcass_pile != null:
			context[HuntService.CONTEXT_KILL_CARCASS] = {
				"macro_x": carcass_pile.macro_coords.x, "macro_y": carcass_pile.macro_coords.y,
				"micro_x": carcass_pile.microcell.x, "micro_y": carcass_pile.microcell.y,
				"id": int(carcass_pile.carcasses[-1]["id"]),
			}
		target_killed.emit(combat_target.kind, combat_target.target_id, combat_target.label, int(animal.age_band), animal.macro_coords)
		if weapon_thrown:
			_request_recovery(context, weapon_name, weapon_uses, true)
		else:
			# Nessuna arma da recuperare (mischia, o arma rotta): la macellazione si chiede subito.
			if context.has(HuntService.CONTEXT_KILL_CARCASS):
				# "requested_by" (2026-09-27, diagnosi): origine della richiesta, letta solo dai log [HUNT].
				var butcher_request: Dictionary = (context[HuntService.CONTEXT_KILL_CARCASS] as Dictionary).duplicate()
				butcher_request["requested_by"] = "ThrowAction (colpo mortale senza arma a terra)"
				context[HuntService.CONTEXT_PENDING_BUTCHER] = butcher_request
				HuntService.log_event(individual, "richiesta macellazione scritta da %s, carcassa #%d (%s)." % [
					butcher_request["requested_by"], int(butcher_request.get("id", -1)), HuntService.describe_now()
				])
		return true
	# Ferito (2026-10-01, regole delle armi): la preda fugge e la caccia la insegue ancora.
	#   - arma da lancio integra: conficcata nell'animale, persa -> si continua con un'altra arma, se c'è;
	#   - mischia: l'arma è rimasta in mano -> nuovo avvicinamento;
	#   - arma rotta: si continua con un'altra arma, se c'è.
	context.erase(HuntService.CONTEXT_WEAPON_DROP)
	var wounded := "%s ferito (salute %.1f) è fuggito" % [combat_target.describe(), animal.health]
	if weapon_thrown:
		HuntService.continue_with_other_weapon_or_stop(individual, context, "%s portando via %s" % [wounded, weapon_display])
	elif weapon_intact:
		context[HuntService.CONTEXT_PENDING_REAPPROACH] = HuntService.REAPPROACH_AFTER_THROW
		HuntService.log_event(individual, "%s: lo si insegue ancora." % wounded)
	else:
		HuntService.continue_with_other_weapon_or_stop(individual, context, "%s, %s rotta" % [wounded, weapon_display])
	return true


# Chiede lo step di recupero dell'arma a terra (vedi RecoverWeaponAction): l'arma passa per il context solo
# fino al finish_current_step di questo step.
func _request_recovery(context: Dictionary, weapon: String, uses: int, prey_killed: bool) -> void:
	context[HuntService.CONTEXT_PENDING_WEAPON_RECOVERY] = {"weapon": weapon, "uses": uses, "prey_killed": prey_killed}


func get_save_data() -> Dictionary:
	var data := combat_target.to_save_data()
	data["weapon_category"] = weapon_category
	return data
