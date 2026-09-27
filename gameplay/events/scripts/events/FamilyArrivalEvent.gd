class_name FamilyArrivalEvent
extends RandomEvent

# Arrivo di una famiglia (2026-09-27, richiesta utente): una coppia di adulti fertili con due figli entra nella
# macrocella del villaggio come gruppo di migranti (VisitorService.spawn_party) e cammina fino al centro del
# villaggio; da lì proseguono i meccanismi dei visitatori già esistenti (popup di decisione in GameScene,
# accoglienza o rifiuto). Nessun popup all'applicazione: la domanda al giocatore arriva all'arrivo del gruppo.
#
# Il sorteggio richiede il centro del villaggio (requires_village_center nel .tres); l'attivazione manuale dal
# menu di debug salta i vincoli, quindi qui l'assenza del centro è ricontrollata e segnalata.

const FATHER_AGE: int = 25
const MOTHER_AGE: int = 24
const CHILDREN: Array[Dictionary] = [
	{"age": 4, "sex": HumanTypes.Sex.MALE},
	{"age": 3, "sex": HumanTypes.Sex.FEMALE},
]
# Moltiplicatore della probabilità annua quando le abitazioni del villaggio hanno posti liberi per almeno tutti
# i membri della famiglia (2026-09-27, richiesta utente): un villaggio con spazio attira chi cerca casa.
const HOUSING_AVAILABLE_MULTIPLIER: float = 1.5


# Membri della famiglia in arrivo: padre, madre e figli.
static func get_group_size() -> int:
	return 2 + CHILDREN.size()


# Posti liberi (AssignHouseService: max_residents meno residenti assegnati) >= membri della famiglia -> x1.5.
func get_probability_multiplier(context: RandomEventContext) -> float:
	if AssignHouseService.count_free_slots(context.world, context.human_individuals) >= get_group_size():
		return HOUSING_AVAILABLE_MULTIPLIER
	return 1.0


# Riuscito (true) solo se il gruppo compare davvero: senza centro del villaggio o senza un bordo raggiungibile
# ritorna false, e il raffreddamento dei visitatori non riparte.
func apply(context: RandomEventContext) -> bool:
	var center := VisitorService.find_village_center(context.world)
	if center == null:
		push_warning("FamilyArrivalEvent: nessun centro del villaggio completo (Pebble Circle), la famiglia non arriva.")
		return false
	var members := VisitorService.build_family_members(FATHER_AGE, MOTHER_AGE, CHILDREN)
	var party := VisitorService.spawn_party(context.game_data, context.world, center, VisitorTypes.PartyType.MIGRANTS, members)
	if party == null:
		push_warning("FamilyArrivalEvent: nessuna microcella di bordo raggiungibile (tutta acqua), la famiglia non arriva.")
		return false
	if DebugLogging.ENABLED:
		print("[VISITORS] Famiglia in arrivo: gruppo #%d (%d membri) entra da %s verso %s nella macrocella %s." % [
			party.id, party.members.size(), str(party.entry_point), str(party.target_point), str(party.macro_coords)
		])
	return true
