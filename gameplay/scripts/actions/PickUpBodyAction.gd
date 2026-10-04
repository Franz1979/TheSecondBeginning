class_name PickUpBodyAction
extends Action

# "Prendi il corpo" (2026-10-04, richiesta utente — cumulo sepolcrale passo 2, secondo step di bury.tres: cammina al
# cadavere → prendi il corpo → cammina al cumulo → posa il corpo). Istantanea: il pipottino, arrivato sul corpo, se lo
# carica in spalla (BodyBurialService.pick_up — non occupa lo zaino). Il corpo è il record DEAD_BODY con individual_id
# `body_id`, ritrovato ogni volta in game_data.expired_objects (nessun riferimento tenuto).
#
# Validità: il corpo esiste ancora e non è scaduto — un corpo scaduto con la task in coda la fa annullare alla ripresa
# (HumanIndividualActionService.is_task_valid). Posizione richiesta: quella del corpo a terra, così la ripresa dalla
# coda dopo un'interruzione (che ha fatto posare il corpo, BodyBurialService.enforce_carrier) riporta il pipottino al
# corpo prima di riprenderlo.

var body_id: int = -1


func _init(p_body_id: int = -1) -> void:
	target = null
	body_id = p_body_id
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func is_target_valid() -> bool:
	var record := BodyBurialService.find_body_record(body_id)
	return not record.is_empty() and not BodyBurialService.is_expired(record)


func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	var record := BodyBurialService.find_body_record(body_id)
	if record.is_empty() or ExpiredObjectCalculator.is_carried(record):
		return null
	return BodyBurialService.get_body_position_relative_to(record, individual.home_macro_coords)


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return true


func on_complete(individual: Variant, context: Dictionary) -> void:
	var record := BodyBurialService.find_body_record(body_id)
	if record.is_empty() or BodyBurialService.is_expired(record):
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "corpo #%d non più a terra" % body_id
		return
	var carrier_id := int(record.get("carried_by_id", -1))
	if carrier_id == individual.id:
		return
	if carrier_id != -1:
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "corpo #%d già in spalla a #%d" % [body_id, carrier_id]
		return
	# Mai due corpi in spalla: un eventuale altro corpo (stato incoerente) viene posato qui.
	BodyBurialService.put_down_carried_body(individual)
	BodyBurialService.pick_up(individual, record)
	# Corteo funebre (2026-10-04): a ogni presa del corpo, anche a una ripresa dalla coda.
	BodyBurialService.convoke_funeral_procession(individual as HumanIndividual, record)


func get_save_data() -> Dictionary:
	return {"body_id": body_id}
