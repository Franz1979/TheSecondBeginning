class_name VisitorPartyRules
extends Resource

# Dati per TIPO di gruppo di visitatori (2026-09-27, richiesta utente — dote dei visitatori accolti). Un .tres
# per VisitorTypes.PartyType in gameplay/visitors/data/{tipo}_party.tres ({tipo} = chiave dell'enum in
# minuscolo, es. migrants_party.tres), caricato da VisitorService.get_party_rules. Tipo senza .tres = nessuna dote.

@export_group("Dowry")
# Dote portata nello zaino da chi viene accolto: risorsa (nome come in CaloricCalculator/secondary_resources,
# "" = nessuna dote) e frazione della capacità di trasporto di ciascuno riempita con essa (1.0 = zaino pieno).
@export var dowry_resource_name: String = ""
@export_range(0.0, 1.0) var dowry_carry_fill_ratio: float = 1.0
# Ruoli (VisitorTypes.MemberRole) che portano la dote; gli altri arrivano a mani vuote.
@export var dowry_member_roles: Array[int] = []
