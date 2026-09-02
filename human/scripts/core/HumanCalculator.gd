class_name HumanCalculator
extends RefCounted

# Calcoli di supporto per il dominio umano, stateless — stesso ruolo/pattern di
# AnimalCalculator/BuildingCalculator lato simulazione, ma nessuna dipendenza da quelli.

# Fascia d'età corrispondente a `age` (anni) per il sesso dato, camminando cumulativamente
# HumanRules.age_band_durations_male/female fino a trovare quella che la contiene — stesso ordine
# di HumanTypes.AgeBand (0=CHILD..3=OLD). Età oltre l'ultima fascia (durate tutte esaurite, es.
# durations non ancora tarate/zero) ricade su OLD, l'ultima fascia esistente, invece di andare
# fuori range: nessun individuo può risultare "senza fascia".
static func get_age_band(human_rules: HumanRules, sex: HumanTypes.Sex, age: float) -> HumanTypes.AgeBand:
	var durations: Array[float] = (
		human_rules.age_band_durations_female if sex == HumanTypes.Sex.FEMALE else human_rules.age_band_durations_male
	)
	var cumulative := 0.0
	for i in range(durations.size()):
		cumulative += durations[i]
		if age < cumulative:
			return i
	return HumanTypes.AgeBand.OLD
