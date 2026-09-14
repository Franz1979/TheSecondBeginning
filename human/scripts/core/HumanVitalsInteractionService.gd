class_name HumanVitalsInteractionService
extends RefCounted

# Interazione GIORNALIERA tra i 5 parametri vitali, per un SINGOLO individuo (2026-09-13,
# richiesta utente) — due regole indipendenti applicate in cascata nello stesso passaggio:
# 1. stamina -> happiness: current_stamina >= max_stamina / 2.0 ? +100.0 : -100.0 su current_happiness.
# 2. happiness -> loyalty: current_happiness >= max_happiness / 2.0 ? +100.0 : -100.0 su current_loyalty,
#    valutata sul current_happiness GIÀ aggiornato dalla regola 1 (un solo passaggio coerente per
#    individuo — "risolvi quel che serve una sola volta", non due letture di due stati diversi
#    dello stesso giorno per le due regole).
#
# Stesso schema RefCounted stateless di HumanVitalsIndividualService: il chiamante
# (GameTimeService._on_day_advanced) itera l'intera popolazione, questo service opera su un
# individuo alla volta.
#
# Chiamato SUBITO DOPO HumanVitalsIndividualService.recalculate_vitals nello stesso giorno (vedi
# GameTimeService._on_day_advanced) — cruciale: questo service legge max_stamina/max_happiness
# (già ricalcolati per l'era/age_band corrente) e current_happiness/current_loyalty (già clampati
# al nuovo tetto) di OGGI, non dati stantii di ieri.
#
# NESSUN clamp scritto qui (richiesta esplicita) — il limite superiore giornaliero è già applicato
# da HumanVitalsIndividualService._clamp_current_to_max PRIMA che questo service giri; un valore
# incrementato qui può quindi superare max_* fino al prossimo ricalcolo giornaliero, stesso
# principio già accettato per current_stamina altrove nel progetto. NESSUN limite inferiore
# (può scendere sotto zero, l'auto-interrupt per vitali a zero arriverà in futuro).
static func apply_daily_interaction(individual: HumanIndividual) -> void:
	var happiness_before := individual.current_happiness
	var loyalty_before := individual.current_loyalty

	var stamina_threshold := individual.max_stamina / 2.0
	if individual.current_stamina >= stamina_threshold:
		individual.current_happiness += 100.0
	else:
		individual.current_happiness -= 100.0

	var happiness_threshold := individual.max_happiness / 2.0
	if individual.current_happiness >= happiness_threshold:
		individual.current_loyalty += 100.0
	else:
		individual.current_loyalty -= 100.0

	if not DebugLogging.ENABLED or not DebugLogging.SHOW_VITALS_INTERACTION_LOGS:
		return
	print("[VITALS INTERACTION] #%d %s: stamina=%.1f/soglia=%.1f | happiness %.1f -> %.1f | loyalty %.1f -> %.1f" % [
		individual.id, individual.name, individual.current_stamina, stamina_threshold,
		happiness_before, individual.current_happiness, loyalty_before, individual.current_loyalty
	])
