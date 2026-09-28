class_name SearchHaulZoneAction
extends Action

# Primo step della raccolta su zona (2026-09-27, richiesta utente — work areas, passo 2): "cerca nella zona".
# Istantaneo, sullo stile della ricerca del magazzino: on_complete scrive solo CONTEXT_PENDING, e
# HumanIndividualActionService._handle_pending_haul_zone_search (che ha il World) sceglie la cella dentro la zona del
# context (HaulZoneService) e accoda Walk + PickUp verso di lei. Nessuna cella trovata = nessuno step accodato, la Task
# si chiude. Nessun dato proprio: la zona vive nel context della Task.

const CONTEXT_PENDING := "pending_haul_zone_search"


func _init() -> void:
	target = null
	# Stesse età escluse del PickUp che accoderà: il rifiuto all'assegnazione resta quello di sempre.
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return true


func on_complete(individual: Variant, context: Dictionary) -> void:
	context[CONTEXT_PENDING] = true
