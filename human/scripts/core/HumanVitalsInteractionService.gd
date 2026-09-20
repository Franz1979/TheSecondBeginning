class_name HumanVitalsInteractionService
extends RefCounted

# Interazione GIORNALIERA tra i parametri vitali, per un SINGOLO individuo (2026-09-13, richiesta
# utente; estesa 2026-09-19) - quattro regole applicate in cascata nello stesso passaggio, in
# quest'ordine (ciascuna legge i valori GIA' aggiornati dalle precedenti, cosi' un solo passaggio
# coerente per individuo):
# 1. riserva corporea -> health: body_calories < body_calories_capacity (riserva non al massimo) ?
#    -100.0 : +50.0 su current_health.
# 2. stamina -> happiness: current_stamina >= max_stamina / 2.0 ? +100.0 : -100.0 su current_happiness.
# 3. health -> happiness: current_health > max_health * 2/3 (strettamente) ? +50.0 : -100.0 su
#    current_happiness (si somma alla regola 2: nello stesso giorno la happiness puo' muoversi da -200
#    a +150).
# 4. happiness -> loyalty: current_happiness >= max_happiness / 2.0 ? +100.0 : -100.0 su
#    current_loyalty, sulla happiness GIA' aggiornata dalle regole 2 e 3.
#
# Ogni parametro toccato e' limitato a [0, max] DOPO ogni singola regola (2026-09-19, richiesta
# utente: nessun parametro vitale sotto 0 ne' sopra il proprio massimo), cosi' le soglie delle regole
# successive leggono valori gia' nei limiti.
#
# Stesso schema RefCounted stateless di HumanVitalsIndividualService: il chiamante
# (GameTimeService._on_day_advanced) itera l'intera popolazione, questo service opera su un
# individuo alla volta.
#
# Chiamato SUBITO DOPO HumanVitalsIndividualService.recalculate_vitals nello stesso giorno (vedi
# GameTimeService._on_day_advanced) - cruciale: questo service legge i max_* (gia' ricalcolati per
# l'era/age_band corrente) e i current_* (gia' clampati al nuovo tetto) di OGGI, non dati stantii di
# ieri. La riserva corporea e' "al massimo" con una tolleranza (BODY_RESERVE_FULL_EPSILON): dopo un
# rifornimento la somma in virgola mobile puo' fermarsi un soffio sotto il massimo.
const BODY_RESERVE_FULL_EPSILON: float = 0.001

static func apply_daily_interaction(individual: HumanIndividual) -> void:
	var health_before := individual.current_health
	var happiness_before := individual.current_happiness
	var loyalty_before := individual.current_loyalty

	var body_reserve_full: bool = individual.body_calories >= individual.body_calories_capacity - BODY_RESERVE_FULL_EPSILON
	individual.current_health = _add_clamped(individual.current_health, 50.0 if body_reserve_full else -100.0, individual.max_health)

	var stamina_threshold := individual.max_stamina / 2.0
	individual.current_happiness = _add_clamped(
		individual.current_happiness, 100.0 if individual.current_stamina >= stamina_threshold else -100.0, individual.max_happiness
	)

	var health_threshold := individual.max_health * 2.0 / 3.0
	individual.current_happiness = _add_clamped(
		individual.current_happiness, 50.0 if individual.current_health > health_threshold else -100.0, individual.max_happiness
	)

	var happiness_threshold := individual.max_happiness / 2.0
	individual.current_loyalty = _add_clamped(
		individual.current_loyalty, 100.0 if individual.current_happiness >= happiness_threshold else -100.0, individual.max_loyalty
	)

	if not DebugLogging.ENABLED or not DebugLogging.SHOW_VITALS_INTERACTION_LOGS:
		return
	print("[VITALS INTERACTION] #%d %s: riserva_corpo=%.1f/%.1f | stamina=%.1f/soglia=%.1f | health %.1f -> %.1f (soglia=%.1f) | happiness %.1f -> %.1f | loyalty %.1f -> %.1f" % [
		individual.id, individual.name, individual.body_calories, individual.body_calories_capacity,
		individual.current_stamina, stamina_threshold,
		health_before, individual.current_health, health_threshold,
		happiness_before, individual.current_happiness, loyalty_before, individual.current_loyalty
	])


# value + delta limitato a [0, max_value]. max_value negativo (non dovrebbe accadere) e' trattato come 0.
static func _add_clamped(value: float, delta: float, max_value: float) -> float:
	return clampf(value + delta, 0.0, maxf(max_value, 0.0))
