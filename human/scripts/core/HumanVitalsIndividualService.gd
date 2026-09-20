class_name HumanVitalsIndividualService
extends RefCounted

# Ricalcolo CONSOLIDATO dei parametri vitali thirst/health/happiness/loyalty (hunger e' diventato la
# saccoccia del cibo, ricalcolata da HumanCarryCapacityIndividualService - 2026-09-19) di
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
# da HumanIndividual._resolve_initial_max_thirst/health/happiness/loyalty.
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
		individual.max_thirst = HumanCalculator.get_max_thirst(human_rules, age_band, individual.sex)
		individual.max_health = HumanCalculator.get_max_health(human_rules, age_band, individual.sex)
		individual.max_happiness = HumanCalculator.get_max_happiness(human_rules, age_band, individual.sex)
		individual.max_loyalty = HumanCalculator.get_max_loyalty(human_rules, age_band, individual.sex)
	individual.current_thirst = _clamp_current_to_range(individual, "thirst", individual.current_thirst, individual.max_thirst)
	individual.current_health = _clamp_current_to_range(individual, "health", individual.current_health, individual.max_health)
	individual.current_happiness = _clamp_current_to_range(individual, "happiness", individual.current_happiness, individual.max_happiness)
	individual.current_loyalty = _clamp_current_to_range(individual, "loyalty", individual.current_loyalty, individual.max_loyalty)


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
# Rinominata da _clamp_current_to_max (2026-09-19, richiesta utente): oltre al tetto applica anche il
# PAVIMENTO a 0 - nessun parametro vitale puo' andare sotto 0. Rete di sicurezza per qualunque
# scrittore e per i salvataggi che contengono gia' valori negativi (li porta a 0 al primo ricalcolo,
# anche all'ingresso in scena).
static func _clamp_current_to_range(individual: HumanIndividual, vital_name: String, current_value: float, max_value: float) -> float:
	if current_value < 0.0:
		if DebugLogging.ENABLED and DebugLogging.SHOW_VITALS_RECALC_LOGS:
			print("[HUMAN VITALS RECALC] #%d %s: current_%s %.1f < 0 -> portata a 0" % [
				individual.id, individual.name, vital_name, current_value
			])
		return 0.0
	if current_value <= max_value:
		return current_value
	if DebugLogging.ENABLED and DebugLogging.SHOW_VITALS_RECALC_LOGS:
		print("[HUMAN VITALS RECALC] #%d %s: current_%s %.1f > nuovo max_%s %.1f -> tagliata a %.1f" % [
			individual.id, individual.name, vital_name, current_value, vital_name, max_value, max_value
		])
	return max_value


# Consumo calorico giornaliero della saccoccia del cibo (2026-09-19, richiesta utente): consuma
# min(get_daily_calorie_consumption, food_calories_held) calorie e riduce food_space_used nella stessa
# proporzione (le calorie residue occupano lo spazio residuo). A zero calorie lo spazio va a zero e ci
# resta: nessuna penalita' per ora. Con moltiplicatore 0 (INFANT) il consumo e' zero e non cambia
# niente; senza HumanRules risolvibili non consuma nulla.
#
# FUNZIONE A PARTE, NON dentro recalculate_vitals: quest'ultima e' richiamata anche all'ingresso in
# scena (GameScene, per ogni individuo caricato o appena creato) e applicherebbe un giorno di consumo
# ad ogni ingresso/caricamento. Chiamata SOLO da GameTimeService._recalculate_daily_vitals, cioe' una
# volta al giorno per l'INTERA popolazione (non solo per chi ha una task attiva).
# era_rules (2026-09-19): serve al moltiplicatore dell'allattamento (dependent_child_calorie_multiplier),
# risolto UNA volta dal chiamante per l'intera popolazione.
# Ritorna true SOLO nel giorno in cui l'individuo comincia a intaccare la riserva corporea (vedi
# started_using_reserve): il chiamante (GameTimeService) lo trasforma in un segnale per l'avviso.
static func apply_daily_calorie_consumption(individual: HumanIndividual, game_data: GameData, era_rules: EraRules = null) -> bool:
	var human_rules: HumanRules = null
	if individual.source_group_ref != null and individual.source_group_ref.folk_ref != null:
		human_rules = individual.source_group_ref.folk_ref.human_rules_ref
	if human_rules == null:
		return false
	var calories_before: float = individual.food_calories_held
	var space_before: float = individual.food_space_used
	var age := float(game_data.year - individual.birth_year_virtual)
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, age
	)
	var daily_consumption: float = HumanCalculator.get_daily_calorie_consumption(
		human_rules, age_band, individual.sex, individual.dependent_child_id != -1, era_rules
	)
	var consumed: float = 0.0
	if calories_before > 0.0:
		consumed = minf(daily_consumption, calories_before)
	if consumed > 0.0:
		individual.food_space_used *= (calories_before - consumed) / calories_before
		individual.food_calories_held -= consumed
	# Riserva corporea (2026-09-19, richiesta utente): la parte di consumo che le provviste non coprono
	# intacca body_calories, che si ferma a 0 (nessuna penalita' ne' morte per ora).
	var body_before: float = individual.body_calories
	var shortfall: float = daily_consumption - consumed
	var consumed_from_body: float = 0.0
	if shortfall > 0.0 and body_before > 0.0:
		consumed_from_body = minf(shortfall, body_before)
		individual.body_calories = body_before - consumed_from_body
	# Transizione "comincia a consumare la riserva" (2026-09-19, richiesta utente - alert popup): vera solo
	# il PRIMO giorno in cui la riserva viene intaccata; body_reserve_in_use resta true finche' il consumo
	# continua e torna false quando un giorno le provviste bastano (o la riserva e' a 0), cosi' un
	# nuovo inizio genera un nuovo avviso.
	var started_using_reserve: bool = consumed_from_body > 0.0 and not individual.body_reserve_in_use
	individual.body_reserve_in_use = consumed_from_body > 0.0
	if DebugLogging.ENABLED and DebugLogging.SHOW_DAILY_CALORIE_LOGS \
			and individual.id == DebugLogging.DAILY_CALORIE_LOG_INDIVIDUAL_ID:
		print("[DAILY CALORIE DEBUG] anno=%d giorno=%d #%d eta=%.1f fascia=%s sesso=%s consumo_calcolato=%.3f consumato=%.3f calorie %.3f->%.3f spazio %.3f->%.3f capacita=%.3f | dal_corpo=%.3f riserva %.3f->%.3f max=%.3f" % [
			game_data.year, game_data.current_day, individual.id, age, HumanTypes.AgeBand.keys()[age_band],
			HumanTypes.Sex.keys()[individual.sex], daily_consumption, consumed, calories_before,
			individual.food_calories_held, space_before, individual.food_space_used, individual.food_space_capacity,
			consumed_from_body, body_before, individual.body_calories, individual.body_calories_capacity
		])
	return started_using_reserve
