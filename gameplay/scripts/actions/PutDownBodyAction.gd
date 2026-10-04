class_name PutDownBodyAction
extends Action

# "Posa il corpo accanto al cumulo" (2026-10-04, richiesta utente — cumulo sepolcrale passo 2, ultimo step di
# bury.tres). Istantanea: il pipottino, arrivato accanto al cumulo (CarryBodyAction), posa il corpo sulla lastra del cumulo (passo 3a, 2026-10-04 — BodyBurialService.put_down_carried_body); il
# record ricorda il cumulo ("mound_id", da context[BodyBurialService.CONTEXT_MOUND_ID] scritto dal passo precedente) e
# continua a occuparne un posto finché resta a terra. Il funerale, che lo seppellirà davvero, è il passo successivo.

var body_id: int = -1


func _init(p_body_id: int = -1) -> void:
	target = null
	body_id = p_body_id
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func is_target_valid() -> bool:
	return not BodyBurialService.find_body_record(body_id).is_empty()


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return true


func on_complete(individual: Variant, context: Dictionary) -> void:
	if individual.carried_body_id != body_id:
		return
	BodyBurialService.put_down_carried_body(individual, int(context.get(BodyBurialService.CONTEXT_MOUND_ID, -1)))


func get_save_data() -> Dictionary:
	return {"body_id": body_id}
