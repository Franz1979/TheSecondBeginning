class_name HumanVitalsInteractionService
extends RefCounted

# Interazione GIORNALIERA tra i parametri vitali, per un SINGOLO individuo (2026-09-13, richiesta
# utente; estesa 2026-09-19 e 2026-09-20) - cinque regole applicate in cascata nello stesso
# passaggio, in quest'ordine (ciascuna legge i valori GIA' aggiornati dalle precedenti, cosi' un solo
# passaggio coerente per individuo):
# 0. casa -> health e happiness (2026-09-20, richiesta utente): house_id != -1 ? +HOME_HEALTH_DELTA /
#    +HOME_HAPPINESS_DELTA × moltiplicatore della casa : -HOMELESS_HEALTH_PENALTY / -HOMELESS_HAPPINESS_PENALTY (dal
#    2026-10-22 +4/+3 × BuildingRules.home_wellbeing_multiplier con casa, prima +10/+5; -10/-5 senza) su
#    current_health/current_happiness, più +NUCLEUS_UNITED_HAPPINESS_DELTA a chi vive con tutto il suo nucleo
#    famigliare (FamilyNucleusService.united_member_ids, qualsiasi casa). In autunno e inverno il bonus della casa è 0
#    nelle case non riscaldate oggi (HouseHeatingService; il chiamante passa home_multiplier 0), mai il malus. Applicata PER PRIMA, cosi' le regole 1-4
#    (soglie su health/happiness) leggono i valori gia' toccati dalla casa. Subito dopo, regola 0b (2026-10-11):
#    bonus/malus per stagione dei capi di vestiario indossati (vedi _apply_apparel_bonuses). Il service non ha `world`:
#    "ha casa" = house_id != -1, senza verificare che il Building esista ancora (la demolizione, vedi
#    GameScene._demolish_building, riporta gia' house_id a -1 per i residenti).
# 1. riserva corporea -> health: body_calories < body_calories_capacity (riserva non al massimo) ?
#    -BODY_RESERVE_NOT_FULL_HEALTH_PENALTY : +BODY_RESERVE_FULL_HEALTH_DELTA su current_health (dal 2026-10-11 -20/+10,
#    richiesta utente: prima -100/+50, troppo forti rispetto alle altre regole, es. il vestiario).
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

# Regola 1, riserva corporea -> salute (2026-10-11, richiesta utente: prima +50/-100).
const BODY_RESERVE_FULL_HEALTH_DELTA: float = 10.0
const BODY_RESERVE_NOT_FULL_HEALTH_PENALTY: float = 20.0

const HOME_HEALTH_DELTA: float = 4.0
const HOME_HAPPINESS_DELTA: float = 3.0
# Nucleo unito (2026-10-22, richiesta utente): tutti i membri del nucleo famigliare nella stessa casa.
const NUCLEUS_UNITED_HAPPINESS_DELTA: float = 1.0
const HOMELESS_HEALTH_PENALTY: float = 10.0
const HOMELESS_HAPPINESS_PENALTY: float = 5.0

# Fede -> lealtà (2026-10-02, regole 4 e 4b sopra).
# Lealtà dalla felicità (2026-10-26, richiesta utente — prima ±100 scritto nel codice, troppo forte): + se la felicità è
# almeno a metà del massimo, − sotto (dimezzata dalla fede, FAITH_LOYALTY_LOSS_MULTIPLIER).
const HAPPINESS_LOYALTY_DAILY_DELTA: float = 10.0
# Fascia neutra (2026-10-26, richiesta utente): la lealtà sale solo con la felicità da questa frazione del massimo in su;
# tra metà e questa soglia non cambia.
const HAPPINESS_LOYALTY_GAIN_THRESHOLD: float = 0.75
# Calo di base (2026-10-26): ogni giorno, a ogni età; la lealtà va mantenuta (raggio politico, fede, consigli).
const LOYALTY_DAILY_DECAY: float = 2.0
const FAITH_LOYALTY_CUSHION_THRESHOLD: float = 0.5
const FAITH_LOYALTY_LOSS_MULTIPLIER: float = 0.5
const FAITH_LOYALTY_BONUS_THRESHOLD: float = 0.75
const FAITH_LOYALTY_DAILY_BONUS: float = 5.0  # 2026-10-26: da 20, metà della felicità (±10)

# Quando esisteranno le specializzazioni: chi ha la specializzazione sacerdote non perde fede con questa regola.
# Fede (2026-10-02, richiesta utente) — regola 5, dopo le altre e indipendente da esse. Ogni giorno:
#   - nessuna casa, o casa non coperta dall'influenza RELIGIOUS: − HumanRules.faith_daily_loss_uncovered;
#   - casa coperta, ma nessun rito nel giorno appena concluso in nessuno degli edifici che la coprono:
#     − HumanRules.faith_daily_loss_covered;
#   - casa coperta e almeno un rito nel giorno appena concluso in uno di quegli edifici: + HumanRules.faith_daily_gain_rite
#     (2026-10-11, prima nessuna perdita).
# Poi limite a [0, max_faith]. Edifici che coprono la casa: cache di InfluenceService (get_covering_buildings), nessun
# calcolo di distanza qui. "Giorno appena concluso": questa regola gira in GameTimeService._on_day_advanced, DOPO che
# GameData.advance_day ha già portato il calendario al giorno nuovo, quindi è get_absolute_day() − 1; un rito
# completato in quel giorno ha scritto proprio quel valore in Building.last_rite_absolute_day (ReligiousRiteEffectService).
# La fede non entra in nessun'altra regola.
# Ripiego quando HumanRules non è risolvibile (2026-10-02): stessi valori dei default di HumanRules.
const FALLBACK_FAITH_DAILY_LOSS_COVERED: float = 1.0
const FALLBACK_FAITH_DAILY_LOSS_UNCOVERED: float = 3.0
const FALLBACK_FAITH_DAILY_GAIN_RITE: float = 10.0

# Copertura della casa (2026-10-02): casa coperta dall'influenza CULTURAL -> + HumanRules.
# cultural_coverage_daily_happiness alla felicità, subito dopo le altre regole sulla felicità (prima di felicità ->
# lealtà); casa coperta dall'influenza POLITICAL -> + HumanRules.political_coverage_daily_loyalty alla lealtà, dopo le
# regole esistenti sulla lealtà. Solo bonus; letto da InfluenceService.is_house_covered (cache, nessuna distanza).
# Ripiego se HumanRules non è risolvibile: stessi valori dei default.
const FALLBACK_CULTURAL_COVERAGE_DAILY_HAPPINESS: float = 5.0
# Disagio (2026-10-18): casa coperta dall'influenza DISCOMFORT (Fossa dei rifiuti, macerie) -> − HumanRules.
# discomfort_coverage_daily_happiness_loss alla felicità e − discomfort_coverage_daily_health_loss alla salute, subito dopo
# il bonus culturale. Ripiego senza HumanRules: gli stessi valori dei default.
const FALLBACK_DISCOMFORT_DAILY_HAPPINESS_LOSS: float = 5.0
const FALLBACK_DISCOMFORT_DAILY_HEALTH_LOSS: float = 2.0
# Regole 2 e 3 senza HumanRules risolvibile: gli stessi valori di partenza dei campi di HumanRules.
const FALLBACK_STAMINA_DAILY_HAPPINESS_GAIN: float = 30.0
const FALLBACK_STAMINA_DAILY_HAPPINESS_LOSS: float = 30.0
const FALLBACK_HEALTH_DAILY_HAPPINESS_GAIN: float = 10.0
const FALLBACK_HEALTH_DAILY_HAPPINESS_LOSS: float = 20.0
const FALLBACK_POLITICAL_COVERAGE_DAILY_LOYALTY: float = 2.0
# Senza vestiario, senza HumanRules risolvibile: gli stessi default dei campi di HumanRules.
const FALLBACK_MISSING_BODY_APPAREL_DELTA: Array[float] = [-4.0, 0.0, 0.0, -2.0]
const FALLBACK_MISSING_HEAD_APPAREL_DELTA: Array[float] = [-1.0, 0.0, 0.0, 0.0]
const FALLBACK_MISSING_FEET_APPAREL_DELTA: Array[float] = [-1.0, 0.0, 0.0, -0.5]

# `home_multiplier` = BuildingRules.home_wellbeing_multiplier della casa, `lives_with_nucleus` = vive con tutto il suo
# nucleo (calcolati una volta per tutta la popolazione da GameTimeService._apply_daily_vitals_interaction).
static func apply_daily_interaction(individual: HumanIndividual, home_multiplier: float = 1.0, lives_with_nucleus: bool = false) -> void:
	var health_before := individual.current_health
	var happiness_before := individual.current_happiness
	var loyalty_before := individual.current_loyalty

	var has_home: bool = individual.house_id != -1
	# Salute del giorno sommata senza limiti intermedi e limitata a [0, max] una volta sola, dopo l'ultima voce (2026-10-25,
	# bugfix "convalescenti fermi a 10"): prima la perdita della condizione si fermava a 0 e la riserva piena ridava +10
	# prima del controllo della morte, così nessuno moriva mai. Vale anche per vestiario e condizioni (_apply_apparel_bonuses,
	# HealthConditionService.advance_daily), che qui non limitano più la salute.
	individual.current_health += HOME_HEALTH_DELTA * home_multiplier if has_home else -HOMELESS_HEALTH_PENALTY
	var home_happiness: float = HOME_HAPPINESS_DELTA * home_multiplier if has_home else -HOMELESS_HAPPINESS_PENALTY
	if lives_with_nucleus:
		home_happiness += NUCLEUS_UNITED_HAPPINESS_DELTA
	individual.current_happiness = _add_clamped(individual.current_happiness, home_happiness, individual.max_happiness)

	var apparel_delta := _apply_apparel_bonuses(individual)
	# Condizioni di salute in corso (2026-10-25, HealthConditionService): la salute del giorno e un giorno in meno; lette
	# per il log PRIMA, perché a fine durata spariscono.
	var illness_log := ""
	if not individual.health_conditions.is_empty():
		illness_log = HealthConditionService.debug_text(individual)
		illness_log += " -%.1f" % HealthConditionService.advance_daily(individual)

	var body_reserve_full: bool = individual.body_calories >= individual.body_calories_capacity - BODY_RESERVE_FULL_EPSILON
	individual.current_health += BODY_RESERVE_FULL_HEALTH_DELTA if body_reserve_full else -BODY_RESERVE_NOT_FULL_HEALTH_PENALTY

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
	# Malato: la felicità persa sta nella scheda di ogni condizione (HealthConditionRules.daily_happiness_loss, applicata
	# da HealthConditionService.advance_daily sopra), non più una perdita generica (2026-10-25, richiesta utente).

	if has_home and InfluenceService.is_house_covered(individual.house_id, InfluenceService.InfluenceType.CULTURAL):
		var happiness_bonus: float = human_rules.cultural_coverage_daily_happiness if human_rules != null else FALLBACK_CULTURAL_COVERAGE_DAILY_HAPPINESS
		individual.current_happiness = _add_clamped(individual.current_happiness, happiness_bonus, individual.max_happiness)

	if has_home and InfluenceService.is_house_covered(individual.house_id, InfluenceService.InfluenceType.DISCOMFORT):
		var discomfort_happiness: float = human_rules.discomfort_coverage_daily_happiness_loss if human_rules != null else FALLBACK_DISCOMFORT_DAILY_HAPPINESS_LOSS
		var discomfort_health: float = human_rules.discomfort_coverage_daily_health_loss if human_rules != null else FALLBACK_DISCOMFORT_DAILY_HEALTH_LOSS
		individual.current_happiness = _add_clamped(individual.current_happiness, -discomfort_happiness, individual.max_happiness)
		individual.current_health -= discomfort_health
	# Unico limite della salute del giorno (vedi sopra): a 0 il controllo delle morti per malattia la trova a 0.
	individual.current_health = clampf(individual.current_health, 0.0, individual.max_health)

	# Lealtà ferma finché il villaggio non ha un nome (2026-10-26, VillageService.is_loyalty_active).
	if VillageService.is_loyalty_active(individual):
		_apply_daily_loyalty(individual, has_home, human_rules)

	individual.current_faith = _add_clamped(individual.current_faith, -_daily_faith_loss(individual, has_home), individual.max_faith)

	if not DebugLogging.ENABLED or not DebugLogging.SHOW_VITALS_INTERACTION_LOGS:
		return
	if DebugLogging.VITALS_INTERACTION_LOG_ONLY_ILL and illness_log == "":
		return
	print("[VITALS INTERACTION] #%d %s: malato=%s malattia=%s | casa=%s | vestiario: salute %+.1f, felicità %+.1f | riserva_corpo=%.1f/%.1f | stamina=%.1f/soglia=%.1f | health %.1f -> %.1f (soglia=%.1f) | happiness %.1f -> %.1f | loyalty %.1f -> %.1f" % [
		individual.id, individual.name, str(individual.is_sick()), illness_log if illness_log != "" else "-", str(has_home), apparel_delta.x, apparel_delta.y, individual.body_calories, individual.body_calories_capacity,
		individual.current_stamina, stamina_threshold,
		health_before, individual.current_health, health_threshold,
		happiness_before, individual.current_happiness, loyalty_before, individual.current_loyalty
	])


# Regole 4 e 4b più raggio politico e calo di base (2026-10-26): felicità almeno a HAPPINESS_LOYALTY_GAIN_THRESHOLD del
# massimo + , sotto metà − (dimezzata dalla fede), in mezzo niente; poi fede alta, casa nel raggio politico, calo.
static func _apply_daily_loyalty(individual: HumanIndividual, has_home: bool, human_rules: HumanRules) -> void:
	var loyalty_delta: float = 0.0
	if individual.current_happiness >= individual.max_happiness * HAPPINESS_LOYALTY_GAIN_THRESHOLD:
		loyalty_delta = HAPPINESS_LOYALTY_DAILY_DELTA
	elif individual.current_happiness < individual.max_happiness / 2.0:
		loyalty_delta = -HAPPINESS_LOYALTY_DAILY_DELTA
		if individual.max_faith > 0.0 and individual.current_faith >= individual.max_faith * FAITH_LOYALTY_CUSHION_THRESHOLD:
			loyalty_delta *= FAITH_LOYALTY_LOSS_MULTIPLIER
	if individual.max_faith > 0.0 and individual.current_faith >= individual.max_faith * FAITH_LOYALTY_BONUS_THRESHOLD:
		loyalty_delta += FAITH_LOYALTY_DAILY_BONUS
	if has_home and InfluenceService.is_house_covered(individual.house_id, InfluenceService.InfluenceType.POLITICAL):
		loyalty_delta += human_rules.political_coverage_daily_loyalty if human_rules != null else FALLBACK_POLITICAL_COVERAGE_DAILY_LOYALTY
	loyalty_delta -= LOYALTY_DAILY_DECAY
	individual.current_loyalty = _add_clamped(individual.current_loyalty, loyalty_delta, individual.max_loyalty)


# Regola 0b, vestiario (2026-10-11, richiesta utente): per ogni capo INDOSSATO (HumanIndividual.equipped_apparel; riposto
# in zaino o magazzino non conta) somma il suo SecondaryResourceRules.health_delta_by_season/happiness_delta_by_season
# della stagione del giorno appena concluso (stesso giorno della regola 5 della fede). Subito dopo la casa e con la
# stessa logica: le soglie delle regole successive leggono valori già toccati dal vestiario (una pelliccia d'estate
# abbassa la felicità, e con essa può calare la lealtà). Felicità limitata a [0, max] dopo ogni capo; la salute no, la
# limita apply_daily_interaction a fine giornata.
# Ritorna la variazione effettiva (x = salute, y = felicità, dopo i limiti) per il log.
static func _apply_apparel_bonuses(individual: HumanIndividual) -> Vector2:
	var game_data: GameData = GameSettings.active_game_data
	# Bambini (INFANT/CHILD): vestiti di recupero, nessun bonus né malus dal vestiario (HumanIndividual.is_apparel_age_band).
	if game_data == null or not individual.uses_village_apparel(game_data):
		return Vector2.ZERO
	var health_start := individual.current_health
	var happiness_start := individual.current_happiness
	var concluded_day: int = posmod(game_data.get_absolute_day() - 1, GameData.DAYS_PER_YEAR)
	var season: int = SeasonCalculator.get_season_for_day(concluded_day)
	for apparel_name in individual.equipped_apparel:
		if apparel_name == "":
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(apparel_name)
		if rules == null:
			continue
		# Salute senza limite: la limita apply_daily_interaction a fine giornata.
		individual.current_health += _season_value(rules.health_delta_by_season, season)
		individual.current_happiness = _add_clamped(
			individual.current_happiness, _season_value(rules.happiness_delta_by_season, season), individual.max_happiness
		)
	# Senza vestito / senza copricapo (2026-10-11; senza calzari dal 2026-10-20, richiesta utente): HumanRules.missing_*_apparel_daily_delta_by_season,
	# lo stesso valore a salute e felicità.
	var human_rules := _resolve_human_rules(individual)
	var missing_body: Array[float] = human_rules.missing_body_apparel_daily_delta_by_season if human_rules != null else FALLBACK_MISSING_BODY_APPAREL_DELTA
	var missing_head: Array[float] = human_rules.missing_head_apparel_daily_delta_by_season if human_rules != null else FALLBACK_MISSING_HEAD_APPAREL_DELTA
	var missing_feet: Array[float] = human_rules.missing_feet_apparel_daily_delta_by_season if human_rules != null else FALLBACK_MISSING_FEET_APPAREL_DELTA
	var missing_delta := 0.0
	if individual.get_equipped_apparel(HumanIndividual.ApparelSlot.BODY) == "":
		missing_delta += _season_value(missing_body, season)
	if individual.get_equipped_apparel(HumanIndividual.ApparelSlot.HEAD) == "":
		missing_delta += _season_value(missing_head, season)
	if individual.get_equipped_apparel(HumanIndividual.ApparelSlot.FEET) == "":
		missing_delta += _season_value(missing_feet, season)
	if missing_delta != 0.0:
		individual.current_health += missing_delta
		individual.current_happiness = _add_clamped(individual.current_happiness, missing_delta, individual.max_happiness)
	return Vector2(individual.current_health - health_start, individual.current_happiness - happiness_start)


# Valore della stagione da un array indicizzato da GameTypes.Season, 0 se l'array non la copre.
static func _season_value(values: Array[float], season: int) -> float:
	return values[season] if season >= 0 and season < values.size() else 0.0


# --- CONVENIENZA STAGIONALE DEI CAPI (2026-10-20, richiesta utente — regola "Indossa i capi disponibili") ---
# Stessi dati di _apply_apparel_bonuses, così la scelta e l'effetto reale non possono divergere. Salute e felicità pesano
# 1 a 1. Un capo è conveniente per uno slot vuoto se il suo punteggio supera quello dello slot vuoto, oppure lo pareggia
# e ha un effetto in più (has_extra_apparel_effect): a parità senza altri effetti non si prende, perché chi lo indossa se
# lo tiene (nessuno si spoglia: il cambio stagionale è della Hut) e un capo neutro oggi può essere pessimo domani.

# Stagione del giorno corrente (0 senza partita).
static func current_season() -> int:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return 0
	return SeasonCalculator.get_season_for_day(posmod(game_data.get_absolute_day(), GameData.DAYS_PER_YEAR))


# Salute + felicità al giorno del capo indossato nella stagione `season`.
static func apparel_season_score(apparel_name: String, season: int) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(apparel_name)
	if rules == null:
		return 0.0
	return _season_value(rules.health_delta_by_season, season) + _season_value(rules.happiness_delta_by_season, season)


# Punteggio dello slot vuoto nella stagione `season`: la penalità missing_* vale per salute E felicità, quindi conta
# due volte. Slot senza penalità (collo, polsi): 0.
static func empty_slot_season_score(individual: HumanIndividual, slot: int, season: int) -> float:
	var human_rules := _resolve_human_rules(individual)
	var values: Array[float] = []
	match slot:
		HumanIndividual.ApparelSlot.BODY:
			values = human_rules.missing_body_apparel_daily_delta_by_season if human_rules != null else FALLBACK_MISSING_BODY_APPAREL_DELTA
		HumanIndividual.ApparelSlot.HEAD:
			values = human_rules.missing_head_apparel_daily_delta_by_season if human_rules != null else FALLBACK_MISSING_HEAD_APPAREL_DELTA
		HumanIndividual.ApparelSlot.FEET:
			values = human_rules.missing_feet_apparel_daily_delta_by_season if human_rules != null else FALLBACK_MISSING_FEET_APPAREL_DELTA
		_:
			return 0.0
	return 2.0 * _season_value(values, season)


# Il capo ha un effetto oltre a salute e felicità (oggi solo il risparmio sulla camminata, walk_stamina_multiplier).
static func has_extra_apparel_effect(apparel_name: String) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(apparel_name)
	return rules != null and rules.walk_stamina_multiplier < 1.0


static func is_apparel_convenient(individual: HumanIndividual, apparel_name: String, slot: int, season: int) -> bool:
	var score := apparel_season_score(apparel_name, season)
	var empty_score := empty_slot_season_score(individual, slot, season)
	return score > empty_score or (is_equal_approx(score, empty_score) and has_extra_apparel_effect(apparel_name))


# Perdita di fede del giorno appena concluso (regola 5): valori da HumanRules (faith_daily_loss_uncovered/covered,
# faith_daily_gain_rite), FALLBACK_FAITH_DAILY_* se le regole non sono risolvibili. Negativa (guadagno) con il rito.
static func _daily_faith_loss(individual: HumanIndividual, has_home: bool) -> float:
	var loss_uncovered: float = FALLBACK_FAITH_DAILY_LOSS_UNCOVERED
	var loss_covered: float = FALLBACK_FAITH_DAILY_LOSS_COVERED
	var gain_rite: float = FALLBACK_FAITH_DAILY_GAIN_RITE
	var human_rules := _resolve_human_rules(individual)
	if human_rules != null:
		loss_uncovered = human_rules.faith_daily_loss_uncovered
		loss_covered = human_rules.faith_daily_loss_covered
		gain_rite = human_rules.faith_daily_gain_rite
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
				return -gain_rite
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


# HumanRules dell'individuo (folk_ref -> human_rules_ref), null se la catena non è risolvibile.
static func _resolve_human_rules(individual: HumanIndividual) -> HumanRules:
	if individual.folk_ref == null:
		return null
	return individual.folk_ref.human_rules_ref


# value + delta limitato a [0, max_value]. max_value negativo (non dovrebbe accadere) e' trattato come 0.
static func _add_clamped(value: float, delta: float, max_value: float) -> float:
	return clampf(value + delta, 0.0, maxf(max_value, 0.0))
