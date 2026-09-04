class_name EraCalculator
extends RefCounted

# Servizio stateless che COMBINA HumanRules ed EraRules — nessuna delle due classi referenzia
# l'altra (vedi i rispettivi commenti), quindi questo è il "futuro service" già anticipato lì.
# get_era_rules segue lo stesso pattern di NaturalEventCalculator.get_event_rules (caricamento per
# convenzione: nome -> path, nessun indice/registro separato da mantenere sincronizzato).

const ERA_RULES_DIR := "res://human/data/era_rules/"


static func get_era_rules(era_name: String) -> EraRules:
	var path := ERA_RULES_DIR + era_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as EraRules


# Durate effettive delle age band = durata base di HumanRules (per sesso) × EraRules.
# longevity_multiplier_by_age, fascia per fascia — stessa indicizzazione posizionale di entrambi
# gli array sorgente (0=CHILD..4=OLD, vedi HumanTypes.AgeBand). Un solo longevity_multiplier_by_age
# (non diviso per sesso, a differenza di age_band_durations_male/female) si applica identico a
# entrambe le durate base: l'asse sesso resta di competenza esclusiva di HumanRules, l'Era modula
# solo l'asse età. Ritorna {"male": Array[float], "female": Array[float]} — stesso idioma "piccolo
# Dictionary di risultati" già usato altrove nel progetto (es. WorldTimeService.advance_day).
static func compute_effective_age_band_durations(human_rules: HumanRules, era_rules: EraRules) -> Dictionary:
	return {
		"male": _apply_multiplier(human_rules.age_band_durations_male, era_rules.longevity_multiplier_by_age),
		"female": _apply_multiplier(human_rules.age_band_durations_female, era_rules.longevity_multiplier_by_age),
	}


static func _apply_multiplier(base_durations: Array[float], multiplier_by_age: Array[float]) -> Array[float]:
	var result: Array[float] = []
	for i in range(base_durations.size()):
		result.append(base_durations[i] * multiplier_by_age[i])
	return result
