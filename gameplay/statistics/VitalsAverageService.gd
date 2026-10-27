class_name VitalsAverageService
extends RefCounted

# Medie dei parametri e delle skill dei pipottini (2026-10-25, richiesta utente — schede Parametri e Skill delle
# statistiche). Un solo giro sugli individui per ogni gruppo; usato all'apertura delle statistiche (valori attuali) e
# una volta l'anno (StatisticsSnapshotService.record_year_end). Percentuali sul massimo di ognuno: per i parametri il
# massimo cambia con età e sesso (la media assoluta calerebbe a ogni nascita), per le skill è HumanIndividual.SKILL_MAX.
# Stateless.

const PARAMETERS: Array[String] = ["health", "happiness", "stamina", "thirst", "loyalty", "faith"]
const CURRENT_FIELDS: Array[StringName] = [&"current_health", &"current_happiness", &"current_stamina", &"current_thirst", &"current_loyalty", &"current_faith"]
const MAX_FIELDS: Array[StringName] = [&"max_health", &"max_happiness", &"max_stamina", &"max_thirst", &"max_loyalty", &"max_faith"]

const SKILLS: Array[String] = [
	"leadership", "builder", "management", "transporter", "gathering", "cognition", "hunting", "crafting", "ritual", "social", "medicine",
]
const SKILL_FIELDS: Array[StringName] = [
	&"skill_leadership", &"skill_builder", &"skill_management", &"skill_transporter", &"skill_gathering",
	&"skill_cognition", &"skill_hunting", &"skill_crafting", &"skill_ritual", &"skill_social", &"skill_medicine",
]


# parametro -> {"current": media del valore, "max": media del massimo, "percent": media di valore/massimo in 0-100}.
static func averages(individuals: Array[HumanIndividual]) -> Dictionary:
	return _averages(individuals, PARAMETERS, CURRENT_FIELDS, MAX_FIELDS, 0.0)


# skill -> stessa forma di averages(), massimo fisso HumanIndividual.SKILL_MAX.
static func skill_averages(individuals: Array[HumanIndividual]) -> Dictionary:
	return _averages(individuals, SKILLS, SKILL_FIELDS, [], HumanIndividual.SKILL_MAX)


# Solo le percentuali: chiave -> 0-100 (per gli snapshot annuali e il punto dell'anno in corso).
static func percents_of(all: Dictionary) -> Dictionary:
	var result := {}
	for key in all:
		result[key] = float(all[key]["percent"])
	return result


static func average_percents(individuals: Array[HumanIndividual]) -> Dictionary:
	return percents_of(averages(individuals))


static func skill_average_percents(individuals: Array[HumanIndividual]) -> Dictionary:
	return percents_of(skill_averages(individuals))


# `max_fields` vuoto = massimo fisso `fixed_max` per tutti. Senza individui tutto a 0.
static func _averages(
	individuals: Array[HumanIndividual], keys: Array[String], current_fields: Array[StringName], max_fields: Array, fixed_max: float
) -> Dictionary:
	var count := keys.size()
	var current_sums: Array[float] = []
	var max_sums: Array[float] = []
	var percent_sums: Array[float] = []
	var percent_counts: Array[int] = []
	current_sums.resize(count)
	max_sums.resize(count)
	percent_sums.resize(count)
	percent_counts.resize(count)
	var people_counts: Array[int] = []
	people_counts.resize(count)
	for individual in individuals:
		for i in range(count):
			# Lealtà ferma prima del battesimo del villaggio (2026-10-26, VillageService.is_loyalty_active): fuori dalla media.
			if current_fields[i] == &"current_loyalty" and not VillageService.is_loyalty_active(individual):
				continue
			people_counts[i] += 1
			var current_value: float = individual.get(current_fields[i])
			var max_value: float = individual.get(max_fields[i]) if not max_fields.is_empty() else fixed_max
			current_sums[i] += current_value
			max_sums[i] += max_value
			if max_value > 0.0:
				percent_sums[i] += current_value / max_value
				percent_counts[i] += 1
	var result := {}
	for i in range(count):
		var people := people_counts[i]
		result[keys[i]] = {
			"current": current_sums[i] / people if people > 0 else 0.0,
			"max": max_sums[i] / people if people > 0 else 0.0,
			"percent": 100.0 * percent_sums[i] / percent_counts[i] if percent_counts[i] > 0 else 0.0,
		}
	return result
