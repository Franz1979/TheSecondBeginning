class_name HumanCarryCapacityIndividualService
extends RefCounted

# Ricalcolo di HumanIndividual.max_carry_capacity per un SINGOLO individuo (2026-09-08, richiesta
# utente) — stesso identico principio/pattern di HumanStaminaIndividualService.
# recalculate_max_stamina: un *Service RefCounted stateless, il chiamante (GameTimeService.
# _on_day_advanced) itera l'intera popolazione, questo service opera su un individuo alla volta.
#
# STESSA SOLUZIONE TEMPORANEA di HumanStaminaIndividualService (richiesta utente, 2026-09-08) —
# ricalcolo PERIODICO (una volta al giorno, incondizionato, per ogni individuo) invece che
# event-driven: nessun cambio di stato che influenzi max_carry_capacity (age_band) ha oggi un
# meccanismo di rilevazione generico nel progetto — vedi il commento di testa a
# HumanStaminaIndividualService per la stessa motivazione strutturale, identica qui.
#
# age_band risolto con le durate EFFETTIVE per l'Era corrente (game_data.era_effective_age_band_
# durations_male/female), MAI human_rules.age_band_durations_male/female direttamente — stesso
# principio già fissato ovunque nel dominio umano (vedi HumanStaminaIndividualService).
#
# Fallback HumanIndividual.FALLBACK_MAX_CARRY_CAPACITY quando la catena source_group_ref->
# folk_ref->human_rules_ref non è risolvibile — stesso criterio di HumanStaminaIndividualService/
# HumanIndividual._resolve_initial_max_carry_capacity (mai un secondo fallback diverso).
#
# Nessun clamp su carried_quantity qui (a differenza del clamp su current_stamina in
# HumanStaminaIndividualService): un max_carry_capacity che scende sotto lo spazio già occupato
# oggi non ha ancora una conseguenza definita (nessun sistema di trasporto/PickUp esiste ancora,
# vedi HumanIndividual.carried_resource_name/carried_quantity) — quando arriverà, la policy
# ("l'eccedenza cade a terra"? "non può più raccogliere finché non scarica"?) andrà decisa da chi
# implementerà quel sistema, non anticipata qui senza un consumatore reale.
static func recalculate_max_carry_capacity(individual: HumanIndividual, game_data: GameData) -> void:
	var human_rules: HumanRules = null
	if individual.source_group_ref != null and individual.source_group_ref.folk_ref != null:
		human_rules = individual.source_group_ref.folk_ref.human_rules_ref
	if human_rules == null:
		individual.max_carry_capacity = HumanIndividual.FALLBACK_MAX_CARRY_CAPACITY
		return
	var age := float(game_data.year - individual.birth_year_virtual)
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, age
	)
	individual.max_carry_capacity = HumanCalculator.get_max_carry_capacity(
		human_rules, age_band, individual.sex, individual.equipped_tool_count
	)
