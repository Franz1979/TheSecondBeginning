class_name RecoverWeaponAction
extends Action

# Recupero dell'arma scagliata (2026-09-26, richiesta utente — caccia: l'arma lanciata non resta più in
# cintura). Step inserito da HumanIndividualActionService._handle_pending_hunt_weapon_recovery subito dopo un
# ThrowAction che ha lasciato a terra un'arma ancora integra: preda uccisa (l'arma è caduta con lei) o tiro a
# vuoto. Non esiste se l'arma si è rotta con quel tiro, né se la preda ferita è fuggita portandosela via.
#
# L'arma a terra NON è un oggetto del mondo: vive solo in questo step (weapon_name/weapon_uses), nessun altro
# può raccoglierla. Se la Task si interrompe prima del recupero, lo step sparisce con lei e l'arma è persa. Il
# punto di caduta (dove si trovava il bersaglio al momento del tiro) è in Task.context[HuntService.
# CONTEXT_WEAPON_DROP], salvato con la Task. GameScene disegna un segnaposto in quel punto finché questo step è
# quello corrente (_sync_dropped_weapon_markers).
#
# Movimento: come ApproachPreyAction, la destinazione è ricalcolata a ogni tick dalla macrocella e dalla
# posizione locale del punto di caduta, così resta corretta anche dopo un attraversamento di bordo. Costo di
# stamina per microcella = WalkAction.compute_walk_stamina_delta.
#
# All'arrivo l'arma torna in cintura (primo slot libero; se non c'è posto, nello zaino; se nemmeno lì, persa
# con un log). Poi (on_complete):
#   - preda uccisa: la caccia si conclude (in futuro qui anche la raccolta della preda, quando la carne sarà
#     una risorsa — oggi non si fa nulla);
#   - tiro a vuoto e preda ancora in vista: si torna ad avvicinarsi (HuntService.REAPPROACH_AFTER_THROW);
#   - tiro a vuoto e preda sparita o persa di vista: la caccia si chiude.

# Distanza dal punto di caduta entro cui l'arma si raccoglie, in microcelle.
const PICKUP_REACH: float = 0.1

var weapon_name: String = ""
var weapon_uses: int = 0
var combat_target: CombatTarget = null
# true = la preda è morta con questo tiro (l'arma è caduta con lei): dopo il recupero la caccia è conclusa.
var prey_killed: bool = false

var _drop_macro_coords: Vector2i = Vector2i.ZERO
var _drop_local_position: Vector2 = Vector2.ZERO
var _last_position: Variant = null
# Arma raccolta (non salvato: lo step si completa nello stesso frame).
var _done: bool = false


func _init(p_weapon_name: String = "", p_weapon_uses: int = 0, p_combat_target: CombatTarget = null, p_prey_killed: bool = false) -> void:
	target = null
	weapon_name = p_weapon_name
	weapon_uses = p_weapon_uses
	combat_target = p_combat_target if p_combat_target != null else CombatTarget.new()
	prey_killed = p_prey_killed
	# Stesse fasce di WalkAction: raccogliere un'arma è solo camminare fino a lei.
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_done = false
	_last_position = null
	var drop := HuntService.read_weapon_drop(context)
	if drop.is_empty():
		# Punto di caduta mancante (non dovrebbe accadere): l'arma si raccoglie dove si trova l'individuo.
		_drop_macro_coords = individual.home_macro_coords
		_drop_local_position = individual.position
	else:
		_drop_macro_coords = drop["macro_coords"]
		_drop_local_position = drop["position"]
	_head_to_drop(individual)
	HuntService.log_event(individual, "recupero di %s: a %.2f microcelle dal punto di caduta." % [
		IconRegistry.get_resource_display_name(weapon_name), individual.position.distance_to(_drop_position_for(individual))
	])


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done:
		return 0.0
	var stamina_delta := 0.0
	if _last_position != null:
		var distance: float = individual.position.distance_to(_last_position)
		stamina_delta = WalkAction.compute_walk_stamina_delta(individual, distance, "RecoverWeapon")
	_last_position = individual.position
	if individual.position.distance_to(_drop_position_for(individual)) <= PICKUP_REACH:
		_done = true
		individual.target_position = individual.position
		individual.is_moving = false
		_pick_up_weapon(individual)
	else:
		_head_to_drop(individual)
	return stamina_delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


# Decisione dopo il recupero (vedi il commento in testa). Scrive le chiavi consumate da finish_current_step.
func on_complete(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	context.erase(HuntService.CONTEXT_WEAPON_DROP)
	if prey_killed:
		# Punto di aggancio futuro: raccolta della preda uccisa (la carne non esiste ancora come risorsa).
		HuntService.log_event(individual, "arma recuperata accanto a %s ucciso: la caccia è conclusa." % combat_target.describe())
		return
	var status := combat_target.get_status()
	if status == CombatTarget.Status.OK:
		context[HuntService.CONTEXT_PENDING_REAPPROACH] = HuntService.REAPPROACH_AFTER_THROW
		HuntService.log_event(individual, "arma recuperata, %s ancora in vista: si torna ad avvicinarsi." % combat_target.describe())
		return
	context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "arma recuperata, ma %s: %s" % [
		combat_target.describe(), CombatTarget.describe_status(status)
	]


# Punto di caduta nel sistema di coordinate dell'individuo (stesso scarto di macrocella di ApproachPreyAction).
func _drop_position_for(individual: Variant) -> Vector2:
	var macro_offset: Vector2 = Vector2(_drop_macro_coords - individual.home_macro_coords) * World.WIDTH
	return _drop_local_position + macro_offset


func _head_to_drop(individual: Variant) -> void:
	individual.target_position = _drop_position_for(individual)
	individual.is_moving = true


# Rimette l'arma in cintura (primo slot libero), altrimenti nello zaino se c'è spazio, altrimenti è persa.
func _pick_up_weapon(individual: Variant) -> void:
	var display_name := IconRegistry.get_resource_display_name(weapon_name)
	var instance := ToolInstance.create(weapon_uses)
	var slot: int = individual.find_slot_for_direct_equip(weapon_name, -1)
	if slot != -1 and individual.equip_tool_direct(weapon_name, slot, null, instance):
		HuntService.log_event(individual, "%s raccolta e rimessa in cintura (%d usi residui)." % [display_name, weapon_uses])
		return
	var rules := CaloricCalculator.get_caloric_source_rules(weapon_name)
	var space_per_unit: float = rules.space_per_unit if rules != null else 0.0
	if individual.get_carried_space() + space_per_unit <= individual.max_carry_capacity and individual.add_carried_tool_instance(weapon_name, instance):
		HuntService.log_event(individual, "%s raccolta: cintura piena, messa nello zaino (%d usi residui)." % [display_name, weapon_uses])
		return
	HuntService.log_event(individual, "%s raccolta ma né cintura né zaino hanno posto: arma persa." % display_name)


# Persistenza: l'arma (vive solo qui), l'esito del tiro e il bersaglio. Il punto di caduta è in Task.context.
func get_save_data() -> Dictionary:
	var data := combat_target.to_save_data()
	data["weapon_name"] = weapon_name
	data["weapon_uses"] = weapon_uses
	data["prey_killed"] = prey_killed
	return data
