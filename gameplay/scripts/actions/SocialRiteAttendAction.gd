class_name SocialRiteAttendAction
extends Action

# Ultimo step della task di un rito sociale (2026-10-14, SocialRiteService.build_attend_task — prima BanquetAttendAction):
# il partecipante resta all'edificio. All'arrivo si registra (SocialRiteService.on_arrival; banchetto: il cibo dello zaino
# passa nel suo piatto); a ogni fotogramma fa avanzare il rito (SocialRiteService.advance, una volta per fotogramma
# qualunque sia il partecipante). Lo step finisce quando il rito non c'è più: concluso (effetti già dati) o saltato.

# Emesso da chi, arrivando, fa cominciare il raduno (2026-10-14 — icona e suono d'inizio). Collegato da
# GameScene._track_social_rite_tasks.
signal rite_started(building: Building, rite_id: String)

var target_building: Building = null
var _done: bool = false
# Preparazione del banchetto (2026-10-16, come ProduceAction): l'organizzatore fermo per materiale mancante scrive una
# volta per blocco pending_material_shortage; HumanIndividualActionService lo fa rifornire (MaterialSupplyService).
var _blocked_by_materials: bool = false
var _material_shortage_reported: bool = false


func _init(p_target_building: Building = null) -> void:
	target = null
	target_building = p_target_building
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_material_shortage_reported = false
	if target_building == null or not (individual is HumanIndividual):
		return
	if SocialRiteService.on_arrival(target_building, individual as HumanIndividual, GameSettings.active_game_data):
		var record := SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id)
		rite_started.emit(target_building, String(record.get("rite_id", "")))


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done or target_building == null:
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
	if SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id).is_empty():
		_done = true
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


# true se l'ultimo tick si è fermato per materiale mancante (retry giornaliero del rifornimento).
func is_blocked_by_materials() -> bool:
	return _blocked_by_materials


# Valido finché l'edificio c'è e il rito è ancora in corso: una task del rito rimasta in coda dopo la fine (o l'annullo)
# viene scartata invece di riprendere.
func is_target_valid() -> bool:
	return target_building != null and not target_building.is_demolished 		and not SocialRiteService.find_rite(GameSettings.active_game_data, target_building.id).is_empty()


func get_save_data() -> Dictionary:
	return {"target_building_id": target_building.id if target_building != null else -1}
