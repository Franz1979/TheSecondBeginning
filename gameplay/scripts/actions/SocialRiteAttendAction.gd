class_name SocialRiteAttendAction
extends Action

# Ultimo step della task di un rito sociale (2026-10-14, SocialRiteService.build_attend_task — prima BanquetAttendAction):
# il partecipante resta all'edificio. All'arrivo si registra (SocialRiteService.on_arrival; banchetto: il cibo dello zaino
# passa nel suo piatto); a ogni fotogramma fa avanzare il rito (SocialRiteService.advance, una volta per fotogramma
# qualunque sia il partecipante). Lo step finisce quando il rito non c'è più: concluso (effetti già dati) o saltato.

# Emesso da chi, arrivando, fa cominciare il raduno (2026-10-14 — icona e suono d'inizio). Collegato da
# GameScene._track_social_rite_tasks.
signal rite_started(building: Building, rite_id: String)
# Emesso una volta quando lo step vede il rito sparito, finito o annullato (2026-10-17 — spegne il falò del banchetto).
# Collegato da GameScene._track_social_rite_tasks.
signal rite_ended(building: Building)

var target_building: Building = null
# Numero del rito per cui è nato lo step (record "uid", 2026-10-24, bugfix "banchetto con due organizzatori"): -1 = qualunque
# (task di salvataggi precedenti). Uno step di un rito chiuso non vale per il successivo sullo stesso edificio.
var rite_uid: int = -1
var _done: bool = false
# Preparazione del banchetto (2026-10-16, come ProduceAction): l'organizzatore fermo per materiale mancante scrive una
# volta per blocco pending_material_shortage; HumanIndividualActionService lo fa rifornire (MaterialSupplyService).
var _blocked_by_materials: bool = false
var _material_shortage_reported: bool = false


func _init(p_target_building: Building = null, p_rite_uid: int = -1) -> void:
	target = null
	target_building = p_target_building
	rite_uid = p_rite_uid
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_material_shortage_reported = false
	if target_building == null or not (individual is HumanIndividual):
		return
	# Rito diverso da quello dello step (2026-10-24): nessun arrivo; lo step finisce al primo tick.
	if not _is_own_rite(SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id)):
		return
	if SocialRiteService.on_arrival(target_building, individual as HumanIndividual, GameSettings.active_game_data):
		var record := SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id)
		rite_started.emit(target_building, String(record.get("rite_id", "")))


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done or target_building == null:
		_done = true
		return 0.0
	# Rito chiuso e un altro partito sullo stesso edificio (2026-10-24): lo step finisce senza rite_ended, che spegnerebbe
	# il falò del rito nuovo.
	var own_record := SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id)
	if not own_record.is_empty() and not _is_own_rite(own_record):
		_done = true
		return 0.0
	# Preparazione (solo l'organizzatore ha la task in questa fase): rifornimento come la Produce, poi la convocazione.
	_blocked_by_materials = false
	if SocialRiteService.is_preparing(target_building) and bool(context.get(SocialRiteService.CONTEXT_ORGANIZER, false)):
		var missing := SocialRiteService.get_preparation_missing(target_building)
		if not missing.is_empty():
			_blocked_by_materials = true
			if not _material_shortage_reported:
				_material_shortage_reported = true
				context["pending_material_shortage"] = {"missing": missing, "target_building_id": target_building.id}
			return 0.0
		SocialRiteService.on_prepared(target_building, individual as HumanIndividual, GameSettings.active_human_individuals, GameSettings.active_game_data)
	SocialRiteService.advance(target_building, delta, GameSettings.active_human_individuals, GameSettings.active_game_data)
	var record := SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id)
	if record.is_empty():
		_done = true
		rite_ended.emit(target_building)
		return 0.0
	# Organizzatore al lavoro (2026-10-17): consuma stamina solo durante il raduno vero e proprio.
	if bool(context.get(SocialRiteService.CONTEXT_ORGANIZER, false)) and String(record.get("phase", "")) == SocialRiteService.PHASE_FEASTING:
		var rules := RiteService.get_rules(String(record.get("rite_id", ""))) as SocialRiteRules
		if rules != null and rules.organizer_stamina_per_day > 0.0:
			return -rules.organizer_stamina_per_day * delta
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


# true se l'ultimo tick si è fermato per materiale mancante (retry giornaliero del rifornimento).
func is_blocked_by_materials() -> bool:
	return _blocked_by_materials


# Valido finché l'edificio c'è e il rito è ancora in corso: una task del rito rimasta in coda dopo la fine (o l'annullo)
# viene scartata invece di riprendere.
func is_target_valid() -> bool:
	if target_building == null or target_building.is_demolished:
		return false
	var record := SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id)
	return not record.is_empty() and _is_own_rite(record)


# true se `record` è il rito per cui è nato lo step: stesso uid, o uid mancante da una delle due parti (salvataggi
# precedenti al 2026-10-24).
func _is_own_rite(record: Dictionary) -> bool:
	var record_uid := int(record.get("uid", -1))
	return rite_uid < 0 or record_uid < 0 or record_uid == rite_uid


func get_save_data() -> Dictionary:
	return {"target_building_id": target_building.id if target_building != null else -1, "rite_uid": rite_uid}
