class_name HumanCalculator
extends RefCounted

# Calcoli di supporto per il dominio umano, stateless — stesso ruolo/pattern di
# AnimalCalculator/BuildingCalculator lato simulazione, ma nessuna dipendenza da quelli.

# Fascia d'età corrispondente a `age` (anni) per il sesso dato, camminando cumulativamente
# durations_male/female fino a trovare quella che la contiene — stesso ordine di HumanTypes.AgeBand
# (0=CHILD..4=OLD). Età oltre l'ultima fascia (durate tutte esaurite, es. durations non ancora
# tarate/zero) ricade su OLD, l'ultima fascia esistente, invece di andare fuori range: nessun
# individuo può risultare "senza fascia".
#
# durations_male/female sono le durate GIA' scalate per l'Era corrente (bugfix, richiesta utente
# 2026-09-04 — PRIMA questo metodo prendeva HumanRules e leggeva age_band_durations_male/female
# DIRETTAMENTE, ignorando i moltiplicatori dell'Era: un individuo già MATURE_ADULT/OLD per l'Era
# corrente poteva risultare mostrato come FERTILE_ADULT). Tipicamente
# game_data.era_effective_age_band_durations_male/female — vedi EraCalculator.
# compute_effective_age_band_durations/GameData.set_current_era. Stesso principio già applicato a
# HumanSeedingService: mai HumanRules.age_band_durations_male/female letto direttamente da qui.
static func get_age_band(durations_male: Array[float], durations_female: Array[float], sex: HumanTypes.Sex, age: float) -> HumanTypes.AgeBand:
	var durations: Array[float] = durations_female if sex == HumanTypes.Sex.FEMALE else durations_male
	var cumulative := 0.0
	for i in range(durations.size()):
		cumulative += durations[i]
		if age < cumulative:
			return i
	return HumanTypes.AgeBand.OLD


# Workforce di BASE per fascia d'età + sesso — solo HumanRules.base_daily_workforce ×
# workforce_multiplier_by_age[age_band] × workforce_multiplier_by_sex[sex], nessuna stanchezza/
# wellness (quelle arriveranno in un passo successivo insieme a un vero
# available_workforce_per_day). Non chiama get_age_band: il chiamante passa già l'age_band
# risolto, stesso schema di size_multiplier_by_age/caloric_multiplier_by_age altrove nel progetto.
# TODO (quando esisterà la classe Action): alcune azioni potrebbero voler ignorare la differenza
# di sesso nella workforce (es. compiti dove la dimorfia non ha senso di modellazione) — servirà
# un campo booleano su Action per decidere se applicare workforce_multiplier_by_sex o no. Non
# implementato qui.
static func get_base_workforce(human_rules: HumanRules, age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> float:
	return (
		human_rules.base_daily_workforce
		* human_rules.workforce_multiplier_by_age[age_band]
		* human_rules.workforce_multiplier_by_sex[sex]
	)
