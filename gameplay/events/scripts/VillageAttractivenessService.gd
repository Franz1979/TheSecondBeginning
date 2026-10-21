class_name VillageAttractivenessService
extends RefCounted

# Attrattiva del villaggio (2026-10-13, richiesta utente): servizio UNICO del moltiplicatore della probabilità degli
# eventi casuali dovuto al villaggio. Stateless. get_probability_multiplier = benessere × cultura × attrattiva generale,
# ognuno con la sua formula qui sotto, i suoi parametri in VillageAttractivenessRules (un solo .tres per tutti) e la
# sua sensibilità per evento in RandomEventRules. Oggi è attiva solo la cultura; benessere e attrattiva generale valgono
# 1.0 finché non saranno definiti (aggiungere allora i loro parametri nel .tres e la sensibilità in RandomEventRules).

const RULES_PATH := "res://gameplay/events/data/rules/village_attractiveness_rules.tres"

static var _rules: VillageAttractivenessRules = null


# Moltiplicatore complessivo del villaggio `village` per l'evento `event_rules` (RandomEventService.get_probability_
# breakdown, voce "village_multiplier"). `individuals` = i vivi del player, per contare gli abitanti. 1.0 senza villaggio.
static func get_probability_multiplier(village: Village, event_rules: RandomEventRules, individuals: Array[HumanIndividual]) -> float:
	if village == null or event_rules == null:
		return 1.0
	var wellbeing := get_wellbeing_multiplier(village)
	var culture := get_culture_multiplier(village, event_rules.culture_sensitivity, individuals)
	var attractiveness := get_attractiveness_multiplier(village)
	return wellbeing * culture * attractiveness


# Benessere del villaggio: DA DEFINIRE (formula, parametri, sensibilità per evento). Oggi 1.0.
static func get_wellbeing_multiplier(_village: Village) -> float:
	return 1.0


# Attrattiva generale del villaggio: DA DEFINIRE (formula, parametri, sensibilità per evento). Oggi 1.0.
static func get_attractiveness_multiplier(_village: Village) -> float:
	return 1.0


# 1 + sensitivity × culture_max_bonus × c / (c + K), c = valore culturale di `village` per abitante (2026-10-18, vedi
# VillageAttractivenessRules). 1.0 senza villaggio, senza abitanti, con sensibilità 0 o regole mancanti.
static func get_culture_multiplier(village: Village, sensitivity: float, individuals: Array[HumanIndividual]) -> float:
	var rules := _get_rules()
	if village == null or sensitivity <= 0.0 or rules == null or rules.culture_per_inhabitant_half_k <= 0.0:
		return 1.0
	var inhabitants := village.count_inhabitants(individuals)
	if inhabitants <= 0:
		return 1.0
	var culture := village.get_influence_value(InfluenceService.InfluenceType.CULTURAL) / float(inhabitants)
	return 1.0 + sensitivity * rules.culture_max_bonus * culture / (culture + rules.culture_per_inhabitant_half_k)


static func _get_rules() -> VillageAttractivenessRules:
	if _rules == null:
		_rules = load(RULES_PATH) as VillageAttractivenessRules
	return _rules
