class_name HumanVitalsIndividualService
extends RefCounted

# Ricalcolo CONSOLIDATO dei 5 nuovi parametri vitali (hunger/thirst/health/happiness/loyalty) di
# HumanIndividual per un SINGOLO individuo (2026-09-13, richiesta utente) — stesso identico
# principio/pattern di HumanStaminaIndividualService.recalculate_max_stamina/
# HumanCarryCapacityIndividualService.recalculate_max_carry_capacity: un *Service RefCounted
# stateless, il chiamante (GameTimeService._on_day_advanced) itera l'intera popolazione, questo
# service opera su un individuo alla volta. UN SOLO service per tutti e 5 (richiesta esplicita),
# non 5 service separati come stamina/carry capacity avrebbero suggerito per precedente — age_band/
# human_rules risolti UNA VOLTA sola qui dentro e riusati per tutti e 5 i calcoli, invece di
# ripetere la stessa risoluzione 5 volte in 5 file diversi.
#
# STESSA SOLUZIONE TEMPORANEA di HumanStaminaIndividualService/HumanCarryCapacityIndividualService
# (ricalcolo PERIODICO, una volta al giorno, incondizionato, per ogni individuo, invece che
# event-driven) — stessa motivazione strutturale identica, vedi il commento di testa a
# HumanStaminaIndividualService per il perché.
#
# age_band risolto con le durate EFFETTIVE per l'Era corrente (game_data.era_effective_age_band_
# durations_male/female), MAI human_rules.age_band_durations_male/female direttamente — stesso
# principio già fissato ovunque nel dominio umano.
#
# Nessun era_rules qui (a differenza di HumanStaminaIndividualService): nessuno dei 5 nuovi
# get_max_* di HumanCalculator ha un ramo gravidanza/figlio-a-carico (firma semplificata a 3
# parametri, richiesta esplicita — vedi HumanCalculator.gd) — questi 5 parametri non hanno ancora
# alcun consumatore reale che ne giustifichi uno.
#
# Fallback HumanIndividual.FALLBACK_MAX_VITAL (UNICO per tutti e 5, vedi quel campo) quando la
# catena source_group_ref->folk_ref->human_rules_ref non è risolvibile — stesso criterio già usato
# da HumanIndividual._resolve_initial_max_hunger/thirst/health/happiness/loyalty.
#
# Clamp SOLO verso il basso su ciascun current_* (2026-09-13, stesso principio di
# HumanStaminaIndividualService.recalculate_max_stamina) — se il nuovo max_* scende sotto l'attuale
# current_*, quest'ultimo viene tagliato al nuovo tetto; MAI il contrario. NESSUN incremento
# automatico dei current_* qui (richiesta esplicita): il current cambia solo per una futura
# azione/evento, non per questo ricalcolo — stesso principio già stabilito per current_stamina.
static func recalculate_vitals(individual: HumanIndividual, game_data: GameData) -> void:
	var human_rules: HumanRules = null
	if individual.source_group_ref != null and individual.source_group_ref.folk_ref != null:
		human_rules = individual.source_group_ref.folk_ref.human_rules_ref
	if human_rules == null:
		individual.max_hunger = HumanIndividual.FALLBACK_MAX_VITAL
		individual.max_thirst = HumanIndividual.FALLBACK_MAX_VITAL
		individual.max_health = HumanIndividual.FALLBACK_MAX_VITAL
		individual.max_happiness = HumanIndividual.FALLBACK_MAX_VITAL
		individual.max_loyalty = HumanIndividual.FALLBACK_MAX_VITAL
	else:
		var age := float(game_data.year - individual.birth_year_virtual)
		var age_band := HumanCalculator.get_age_band(
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
			individual.sex, age
		)
		individual.max_hunger = HumanCalculator.get_max_hunger(human_rules, age_band, individual.sex)
		individual.max_thirst = HumanCalculator.get_max_thirst(human_rules, age_band, individual.sex)
		individual.max_health = HumanCalculator.get_max_health(human_rules, age_band, individual.sex)
		individual.max_happiness = HumanCalculator.get_max_happiness(human_rules, age_band, individual.sex)
		individual.max_loyalty = HumanCalculator.get_max_loyalty(human_rules, age_band, individual.sex)
	individual.current_hunger = _clamp_current_to_max(individual, "hunger", individual.current_hunger, individual.max_hunger)
	individual.current_thirst = _clamp_current_to_max(individual, "thirst", individual.current_thirst, individual.max_thirst)
	individual.current_health = _clamp_current_to_max(individual, "health", individual.current_health, individual.max_health)
	individual.current_happiness = _clamp_current_to_max(individual, "happiness", individual.current_happiness, individual.max_happiness)
	individual.current_loyalty = _clamp_current_to_max(individual, "loyalty", individual.current_loyalty, individual.max_loyalty)


# Un solo punto per il clamp+log ripetuto 5 volte sopra (a differenza di
# HumanStaminaIndividualService, che ha un solo campo da clampare e quindi nessun bisogno di questo
# helper) — ritorna il valore clampato, il chiamante lo riassegna al proprio current_* (stesso
# idioma "funzione pura, il chiamante assegna" già usato ovunque nel dominio umano, es.
# HumanCalculator.get_max_stamina): nessun nuovo meccanismo di indirezione (Callable) introdotto,
# solo un valore di ritorno in più rispetto a scrivere 5 volte lo stesso blocco if/log/assegnazione.
# Log SOLO quando il clamp scatta davvero (stesso principio "non ogni ricalcolo, solo l'evento
# reale" di [HUMAN STAMINA RECALC]), tag [HUMAN VITALS RECALC] + nome del parametro, gated da
# DebugLogging.SHOW_VITALS_RECALC_LOGS (nuovo flag dedicato, stesso schema di
# SHOW_STAMINA_RECALC_LOGS/SHOW_CARRY_CAPACITY_RECALC_LOGS).
static func _clamp_current_to_max(individual: HumanIndividual, vital_name: String, current_value: float, max_value: float) -> float:
	if current_value <= max_value:
		return current_value
	if DebugLogging.ENABLED and DebugLogging.SHOW_VITALS_RECALC_LOGS:
		print("[HUMAN VITALS RECALC] #%d %s: current_%s %.1f > nuovo max_%s %.1f -> tagliata a %.1f" % [
			individual.id, individual.name, vital_name, current_value, vital_name, max_value, max_value
		])
	return max_value
