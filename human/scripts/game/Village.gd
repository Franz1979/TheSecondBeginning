class_name Village
extends RefCounted

# Un insediamento di un Folk (2026-10-12, richiesta utente — sostituisce HumanPopulationGroup): stato di partita,
# RefCounted come Folk. Nasce SOLO al completamento di un village center (1 villaggio = 1 centro) — la fondazione
# automatica arriverà in un passo successivo; finché non esiste, gli individui hanno folk_ref ma village_ref null.
# Abitanti mai salvati qui: si contano dagli individui con village_ref == questo villaggio (vedi Folk/count_*).

var id: int = 0
var folk_ref: Folk = null
# Vuoto finché il giocatore non lo battezza (idea paleolitica avanzata, passo futuro).
var name: String = ""
# Building.id del village center; -1 = senza centro (es. demolito: il villaggio resta in vita ma non genera).
var center_building_id: int = -1
# Valori assoluti di influenza (2026-10-12, passo 4 Folk/Village): InfluenceService.InfluenceType (int) -> float,
# voce assente = 0. Senza tetto, con i decimali (mostrati arrotondati). Crescita annuale: VillageInfluenceService;
# gli altri incrementi/decrementi arriveranno dagli eventi, sempre tramite add_influence_value. Mai sotto 0.
var influence_values: Dictionary = {}


# Nome mostrato: quello scelto dal giocatore, altrimenti il provvisorio "Village <id>" (2026-10-12, richiesta utente).
func get_display_name() -> String:
	return name if name != "" else "Village %d" % id


func get_influence_value(influence_type: InfluenceService.InfluenceType) -> float:
	return float(influence_values.get(influence_type, 0.0))


# Unico punto di modifica dei valori (crescita annuale, riti, eventi): mai sotto 0, nessun tetto (2026-10-12).
func add_influence_value(influence_type: InfluenceService.InfluenceType, amount: float) -> void:
	influence_values[influence_type] = maxf(get_influence_value(influence_type) + amount, 0.0)


# Abitanti di questo villaggio tra gli individui passati (tipicamente i vivi del player).
func count_inhabitants(individuals: Array[HumanIndividual]) -> int:
	var count := 0
	for individual in individuals:
		if individual.village_ref == self:
			count += 1
	return count
