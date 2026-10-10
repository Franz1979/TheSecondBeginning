class_name HumanVitalsInteractionService
extends RefCounted

# Interazione GIORNALIERA tra i parametri vitali, per un SINGOLO individuo (2026-09-13, richiesta
# utente; estesa 2026-09-19 e 2026-09-20) - cinque regole applicate in cascata nello stesso
# passaggio, in quest'ordine (ciascuna legge i valori GIA' aggiornati dalle precedenti, cosi' un solo
# passaggio coerente per individuo):
# 0. casa -> health e happiness (2026-09-20, richiesta utente): house_id != -1 ? +HOME_HEALTH_DELTA /
#    +HOME_HAPPINESS_DELTA : -HOMELESS_HEALTH_PENALTY / -HOMELESS_HAPPINESS_PENALTY (+10/+5 con casa,
#    -10/-5 senza) su current_health/current_happiness. Applicata PER PRIMA, cosi' le regole 1-4
#    (soglie su health/happiness) leggono i valori gia' toccati dalla casa. Il service non ha `world`:
#    "ha casa" = house_id != -1, senza verificare che il Building esista ancora (la demolizione, vedi
#    GameScene._demolish_building, riporta gia' house_id a -1 per i residenti).
# 1. riserva corporea -> health: body_calories < body_calories_capacity (riserva non al massimo) ?
#    -100.0 : +50.0 su current_health.
# 2. stamina -> happiness: current_stamina >= max_stamina / 2.0 ? +gain : -loss su current_happiness (dal 2026-10-10
#    HumanRules.stamina_daily_happiness_gain/loss, 30/30; prima +100/-100 fissi).
# 3. health -> happiness: current_health > max_health * 2/3 (strettamente) ? +gain : -loss su current_happiness (dal
#    2026-10-10 HumanRules.health_daily_happiness_gain/loss, 10/20; prima +50/-100 fissi). Si somma alla regola 2.
# 4. happiness -> loyalty: current_happiness >= max_happiness / 2.0 ? +100.0 : -100.0 su
#    current_loyalty, sulla happiness GIA' aggiornata dalle regole 2 e 3. Fede (2026-10-02): con current_faith >=
#    max_faith × FAITH_LOYALTY_CUSHION_THRESHOLD la perdita (-100.0) è moltiplicata per FAITH_LOYALTY_LOSS_MULTIPLIER;
#    il ramo in cui la lealtà sale resta invariato.
# 4b. faith -> loyalty (2026-10-02): current_faith >= max_faith × FAITH_LOYALTY_BONUS_THRESHOLD ? +FAITH_LOYALTY_DAILY_BONUS
#    su current_loyalty, qualunque sia la felicità. La fede letta dalle regole 4 e 4b è quella di PRIMA della regola
#    giornaliera della fede (regola 5, più sotto): la fede dà solo vantaggi, sotto le soglie nulla cambia.
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

const HOME_HEALTH_DELTA: float = 10.0
const HOME_HAPPINESS_DELTA: float = 5.0
const HOMELESS_HEALTH_PENALTY: float = 10.0
const HOMELESS_HAPPINESS_PENALTY: float = 5.0

# Fede -> lealtà (2026-10-02, regole 4 e 4b sopra).
const FAITH_LOYALTY_CUSHION_THRESHOLD: float = 0.5
const FAITH_LOYALTY_LOSS_MULTIPLIER: float = 0.5
const FAITH_LOYALTY_BONUS_THRESHOLD: float = 0.75
const FAITH_LOYALTY_DAILY_BONUS: float = 20.0

# Quando esisteranno le specializzazioni: chi ha la specializzazione sacerdote non perde fede con questa regola.
# Fede (2026-10-02, richiesta utente) — regola 5, dopo le altre e indipendente da esse. Ogni giorno:
#   - nessuna casa, o casa non coperta dall'influenza RELIGIOUS: − HumanRules.faith_daily_loss_uncovered;
#   - casa coperta, ma nessun rito nel giorno appena concluso in nessuno degli edifici che la coprono:
#     − HumanRules.faith_daily_loss_covered;
#   - casa coperta e almeno un rito nel giorno appena concluso in uno di quegli edifici: nessuna perdita.
# Poi limite a [0, max_faith]. Edifici che coprono la casa: cache di InfluenceService (get_covering_buildings), nessun
# calcolo di distanza qui. "Giorno appena concluso": questa regola gira in GameTimeService._on_day_advanced, DOPO che
# GameData.advance_day ha già portato il calendario al giorno nuovo, quindi è get_absolute_day() − 1; un rito
# completato in quel giorno ha scritto proprio quel valore in Building.last_rite_absolute_day (RiteEffectService).
# La fede non entra in nessun'altra regola.
# Ripiego quando HumanRules non è risolvibile (2026-10-02): stessi valori dei default di HumanRules.
const FALLBACK_FAITH_DAILY_LOSS_COVERED: float = 2.0
const FALLBACK_FAITH_DAILY_LOSS_UNCOVERED: float = 5.0

# Copertura della casa (2026-10-02): casa coperta dall'influenza CULTURAL -> + HumanRules.
# cultural_coverage_daily_happiness alla felicità, subito dopo le altre regole sulla felicità (prima di felicità ->
# lealtà); casa coperta dall'influenza POLITICAL -> + HumanRules.political_coverage_daily_loyalty alla lealtà, dopo le
# regole esistenti sulla lealtà. Solo bonus; letto da InfluenceService.is_house_covered (cache, nessuna distanza).
# Ripiego se HumanRules non è risolvibile: stessi valori dei default.
const FALLBACK_CULTURAL_COVERAGE_DAILY_HAPPINESS: float = 5.0
# Regole 2 e 3 senza HumanRules risolvibile: gli stessi valori di partenza dei campi di HumanRules.
const FALLBACK_STAMINA_DAILY_HAPPINESS_GAIN: float = 30.0
const FALLBACK_STAMINA_DAILY_HAPPINESS_LOSS: float = 30.0
const FALLBACK_HEALTH_DAILY_HAPPINESS_GAIN: float = 10.0
const FALLBACK_HEALTH_DAILY_HAPPINESS_LOSS: float = 20.0
const FALLBACK_POLITICAL_COVERAGE_DAILY_LOYALTY: float = 5.0

static func apply_daily_interaction(individual: HumanIndividual) -> void:
	var health_before := individual.current_health
	var happiness_before := individual.current_happiness
	var loyalty_before := individual.current_loyalty

	var has_home: bool = individual.house_id != -1
	individual.current_health = _add_clamped(
		individual.current_health, HOME_HEALTH_DELTA if has_home else -HOMELESS_HEALTH_PENALTY, individual.max_health
	)
	individual.current_happiness = _add_clamped(
		individual.current_happiness, HOME_HAPPINESS_DELTA if has_home else -HOMELESS_HAPPINESS_PENALTY, individual.max_happiness
	)

	var body_reserve_full: bool = individual.body_calories >= individual.body_calories_capacity - BODY_RESERVE_FULL_EPSILON
	individual.current_health = _add_clamped(individual.current_health, 50.0 if body_reserve_full else -100.0, individual.max_health)

	var human_rules := _resolve_human_rules(individual)
	var stamina_gain: float = human_rules.stamina_daily_happiness_gain if human_rules != null else FALLBACK_STAMINA_DAILY_HAPPINESS_GAIN
	var stamina_loss: float = human_rules.stamina_daily_happiness_loss if human_rules != null else FALLBACK_STAMINA_DAILY_HAPPINESS_LOSS
	var health_gain: float = human_rules.health_daily_happiness_gain if human_rules != null else FALLBACK_HEALTH_DAILY_HAPPINESS_GAIN
	var health_loss: float = human_rules.health_daily_happiness_loss if human_rules != null else FALLBACK_HEALTH_DAILY_HAPPINESS_LOSS

	var stamina_threshold := individual.max_stamina / 2.0
	individual.current_happiness = _add_clamped(
		individual.current_happiness, stamina_gain if individual.current_stamina >= stamina_threshold else -stamina_loss, individual.max_happiness
	)

	var health_threshold := individual.max_health * 2.0 / 3.0
	individual.current_happiness = _add_clamped(
		individual.current_happiness, health_gain if individual.current_health > health_threshold else -health_loss, individual.max_happiness
	)

	if has_home and InfluenceService.is_house_covered(individual.house_id, InfluenceService.InfluenceType.CULTURAL):
		var happiness_bonus: float = human_rules.cultural_coverage_daily_happiness if human_rules != null else FALLBACK_CULTURAL_COVERAGE_DAILY_HAPPINESS
		individual.current_happiness = _add_clamped(individual.current_happiness, happiness_bonus, individual.max_happiness)

	var happiness_threshold := individual.max_happiness / 2.0
	var loyalty_delta: float = 100.0
	if individual.current_happiness < happiness_threshold:
		loyalty_delta = -100.0
		if individual.max_faith > 0.0 and individual.current_faith >= individual.max_faith * FAITH_LOYALTY_CUSHION_THRESHOLD:
			loyalty_delta *= FAITH_LOYALTY_LOSS_MULTIPLIER
	individual.current_loyalty = _add_clamped(individual.current_loyalty, loyalty_delta, individual.max_loyalty)

	if individual.max_faith > 0.0 and individual.current_faith >= individual.max_faith * FAITH_LOYALTY_BONUS_THRESHOLD:
		individual.current_loyalty = _add_clamped(individual.current_loyalty, FAITH_LOYALTY_DAILY_BONUS, individual.max_loyalty)

	if has_home and InfluenceService.is_house_covered(individual.house_id, InfluenceService.InfluenceType.POLITICAL):
		var loyalty_bonus: float = human_rules.political_coverage_daily_loyalty if human_rules != null else FALLBACK_POLITICAL_COVERAGE_DAILY_LOYALTY
		individual.current_loyalty = _add_clamped(individual.current_loyalty, loyalty_bonus, individual.max_loyalty)

	individual.current_faith = _add_clamped(individual.current_faith, -_daily_faith_loss(individual, has_home), individual.max_faith)

	if not DebugLogging.ENABLED or not DebugLogging.SHOW_VITALS_INTERACTION_LOGS:
		return
	print("[VITALS INTERACTION] #%d %s: casa=%s | riserva_corpo=%.1f/%.1f | stamina=%.1f/soglia=%.1f | health %.1f -> %.1f (soglia=%.1f) | happiness %.1f -> %.1f | loyalty %.1f -> %.1f" % [
		individual.id, individual.name, str(has_home), individual.body_calories, individual.body_calories_capacity,
		individual.current_stamina, stamina_threshold,
		health_before, individual.current_health, health_threshold,
		happiness_before, individual.current_happiness, loyalty_before, individual.current_loyalty
	])


# Perdita di fede del giorno appena concluso (regola 5): valori da HumanRules (faith_daily_loss_uncovered/covered),
# FALLBACK_FAITH_DAILY_LOSS_* se le regole non sono risolvibili.
static func _daily_faith_loss(individual: HumanIndividual, has_home: bool) -> float:
	var loss_uncovered: float = FALLBACK_FAITH_DAILY_LOSS_UNCOVERED
	var loss_covered: float = FALLBACK_FAITH_DAILY_LOSS_COVERED
	var human_rules := _resolve_human_rules(individual)
	if human_rules != null:
		loss_uncovered = human_rules.faith_daily_loss_uncovered
		loss_covered = human_rules.faith_daily_loss_covered
	if not has_home:
		return loss_uncovered
	var sources := InfluenceService.get_covering_buildings(individual.house_id, InfluenceService.InfluenceType.RELIGIOUS)
	if sources.is_empty():
		return loss_uncovered
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null:
		var concluded_day: int = game_data.get_absolute_day() - 1
		for source in sources:
			# >= e non ==: un rito completato nel frame stesso del cambio di giorno, dopo questo calcolo, scrive già il
			# giorno nuovo e protegge comunque il calcolo successivo.
			if source.last_rite_absolute_day >= concluded_day:
				return 0.0
	return loss_covered


# Evento di felicità una tantum (2026-10-10, richiesta utente — sul modello di GameTimeService._apply_unburied_penalty):
# `village_delta` a ogni individuo di `individuals`, `special_delta` AL POSTO suo a chi è in `special_ids` (id -> qualunque
# valore: parenti, genitori); `excluded_id` saltato (il morto, il neonato). Limite tra 0 e il massimo. `label` per il log.
static func apply_happiness_event(
	individuals: Array, village_delta: float, special_ids: Dictionary = {}, special_delta: float = 0.0, excluded_id: int = -1,
	label: String = ""
) -> void:
	var log_enabled := DebugLogging.ENABLED and DebugLogging.SHOW_VITALS_INTERACTION_LOGS
	if log_enabled:
		print("[HAPPINESS EVENT] %s: %+.0f al villaggio, %+.0f a %d individui speciali." % [label, village_delta, special_delta, special_ids.size()])
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null or individual.id == excluded_id:
			continue
		var delta: float = special_delta if special_ids.has(individual.id) else village_delta
		if delta == 0.0:
			continue
		var before := individual.current_happiness
		individual.current_happiness = clampf(individual.current_happiness + delta, 0.0, maxf(individual.max_happiness, 0.0))
		if log_enabled:
			print("[HAPPINESS EVENT]   #%d %s: felicità %.1f -> %.1f." % [individual.id, individual.name, before, individual.current_happiness])


# HumanRules di `individual` per chi sta fuori da questo service (eventi di felicità), null se non risolvibile.
static func get_human_rules(individual: HumanIndividual) -> HumanRules:
	return _resolve_human_rules(individual) if individual != null else null


# HumanRules dell'individuo (source_group_ref -> folk_ref -> human_rules_ref), null se la catena non è risolvibile.
static func _resolve_human_rules(individual: HumanIndividual) -> HumanRules:
	if individual.source_group_ref == null or individual.source_group_ref.folk_ref == null:
		return null
	return individual.source_group_ref.folk_ref.human_rules_ref


# value + delta limitato a [0, max_value]. max_value negativo (non dovrebbe accadere) e' trattato come 0.
static func _add_clamped(value: float, delta: float, max_value: float) -> float:
	return clampf(value + delta, 0.0, maxf(max_value, 0.0))
