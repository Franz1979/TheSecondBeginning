class_name ContagionService
extends RefCounted

# Contagio delle malattie (2026-10-25, richiesta utente): passa solo da contatti concreti, mai a distanza. Tira sempre il
# SANO esposto, con la probabilità del .tres della malattia della sorgente (HealthConditionRules, gruppo "Contagion"):
#   - stessa casa (HOUSEHOLD): un tiro al giorno per ogni contagioso con cui si dorme (expose_household, dal giro
#     giornaliero dei vitali di GameTimeService — nessun giro nuovo: household_sources una volta al giorno sui soli
#     contagiosi, poi un lookup per abitante);
#   - chi cura (CAREGIVER): un tiro a ogni somministrazione (RemedyAction GIVE);
#   - contatto (CONTACT): a fine conversazione (TalkAction, ognuno tira per sé) e a fine rito sociale — lezione,
#     banchetto — ogni presente sano tira una volta per ogni contagioso presente (SocialRiteService._finish).
# Contagiosi: l'incubazione e la fase acuta delle malattie con almeno una probabilità > 0; mai la convalescenza né le
# ferite. Prima del tiro, dal controllo più economico: ha già la malattia (anche in incubazione) o la sua età non la può
# prendere (HealthConditionService.can_get), poi immune (HumanIndividual.immunities). Gli immuni non tirano.
# Incubazione (HumanIndividual.incubating_conditions, {"id", "days", "source_id"}): invisibile al giocatore (fuori da
# health_conditions: niente icona, pannello, rimedi), finita la quale parte la fase acuta (HealthConditionService.
# add_condition). Alla guarigione l'immunità (grant_immunity, -1 = per sempre). Log [CONTAGION] solo quando c'è un
# contagioso coinvolto. Stateless, stesso pattern degli altri *Service.

enum Channel { HOUSEHOLD, CAREGIVER, CONTACT }

const KEY_SOURCE_ID := "source_id"
# Valore di HumanIndividual.immunities: immune per sempre (HealthConditionRules.immunity_days = -1).
const IMMUNE_FOREVER := -1
const CHANNEL_NAMES := {Channel.HOUSEHOLD: "casa", Channel.CAREGIVER: "cura", Channel.CONTACT: "contatto"}


# Malattie con cui `individual` oggi contagia: quelle in incubazione e quelle in fase acuta, se contagiose.
static func contagious_ids(individual: HumanIndividual) -> Array[String]:
	var result: Array[String] = []
	if individual == null:
		return result
	for entry in individual.incubating_conditions:
		result.append(String(entry.get("id", "")))
	for entry in individual.health_conditions:
		if String(entry.get("phase", HealthConditionService.PHASE_ACUTE)) != HealthConditionService.PHASE_ACUTE:
			continue
		var rules := HealthConditionService.get_rules(String(entry.get("id", "")))
		if rules != null and is_contagious(rules) and not result.has(rules.id):
			result.append(rules.id)
	return result


static func is_contagious(rules: HealthConditionRules) -> bool:
	return rules.category == HealthConditionRules.Category.ILLNESS and (
		rules.contagion_household_per_day > 0.0 or rules.contagion_caregiver > 0.0 or rules.contagion_contact > 0.0
	)


static func is_incubating(individual: HumanIndividual, condition_id: String) -> bool:
	for entry in individual.incubating_conditions:
		if String(entry.get("id", "")) == condition_id:
			return true
	return false


# `target` esposto a `source` su `channel`: un tiro per ogni malattia con cui `source` contagia. `place` per il log.
static func expose(target: HumanIndividual, source: HumanIndividual, channel: Channel, game_data: GameData, place: String) -> void:
	if target == null or source == null or target == source or game_data == null:
		return
	if source.incubating_conditions.is_empty() and source.health_conditions.is_empty():
		return
	for condition_id in contagious_ids(source):
		_try_infect(target, source, condition_id, channel, game_data, place)


# Fine di un evento di gruppo (rito sociale): ogni presente tira una volta per ogni contagioso presente.
static func expose_group(present: Array[HumanIndividual], game_data: GameData, place: String) -> void:
	var sources: Array[HumanIndividual] = []
	for member in present:
		if not contagious_ids(member).is_empty():
			sources.append(member)
	if sources.is_empty():
		return
	for target in present:
		for source in sources:
			expose(target, source, Channel.CONTACT, game_data, place)


# Contagiosi per casa {house_id: [HumanIndividual]}, una volta al giorno prima del giro dei vitali. Vuoto = nessuno.
static func household_sources(individuals: Array[HumanIndividual]) -> Dictionary:
	var result := {}
	for member in individuals:
		if member.house_id == -1 or (member.incubating_conditions.is_empty() and member.health_conditions.is_empty()):
			continue
		if contagious_ids(member).is_empty():
			continue
		if not result.has(member.house_id):
			result[member.house_id] = []
		(result[member.house_id] as Array).append(member)
	if DebugLogging.ENABLED and not result.is_empty():
		var parts: Array[String] = []
		for house_id in result:
			for member in result[house_id]:
				parts.append("#%d %s %s (casa #%d)" % [member.id, member.name, str(contagious_ids(member)), house_id])
		print("[CONTAGION] giorno %d: contagiosi %s." % [_today(), ", ".join(parts)])
	return result


# Giro giornaliero di `individual` (GameTimeService, dopo l'interazione dei vitali): prima un giorno di incubazione in
# meno (alla fine parte la malattia: ritorna gli id appena manifestati, per l'avviso), poi i tiri con i contagiosi di
# casa sua (`sources_by_house` da household_sources).
static func advance_daily(individual: HumanIndividual, sources_by_house: Dictionary, game_data: GameData) -> Array[String]:
	var onset: Array[String] = []
	if not individual.incubating_conditions.is_empty():
		onset = _advance_incubation(individual, game_data)
	if not sources_by_house.is_empty() and individual.house_id != -1 and sources_by_house.has(individual.house_id):
		for source in sources_by_house[individual.house_id]:
			expose(individual, source, Channel.HOUSEHOLD, game_data, "casa #%d" % individual.house_id)
	return onset


# Alla guarigione da `condition_id` (GameTimeService, cambio "recovered"): immune per immunity_days (-1 = per sempre).
static func grant_immunity(individual: HumanIndividual, condition_id: String, game_data: GameData) -> void:
	var rules := HealthConditionService.get_rules(condition_id)
	if rules == null or rules.immunity_days == 0 or game_data == null:
		return
	var until := IMMUNE_FOREVER if rules.immunity_days < 0 else game_data.get_absolute_day() + rules.immunity_days
	individual.immunities[condition_id] = until
	_log("#%d %s guarisce da %s: immune %s." % [
		individual.id, individual.name, condition_id, "per sempre" if until == IMMUNE_FOREVER else "fino al giorno %d" % until
	])


# Può prendere `condition_id` adesso: non già malato né in incubazione, età ammessa, non immune (stessi filtri del tiro).
static func can_catch(individual: HumanIndividual, condition_id: String, game_data: GameData) -> bool:
	return not is_incubating(individual, condition_id) and HealthConditionService.can_get(individual, condition_id, game_data) \
		and not is_immune(individual, condition_id, game_data)


# Immune a `condition_id` oggi. Una voce scaduta si toglie qui.
static func is_immune(individual: HumanIndividual, condition_id: String, game_data: GameData) -> bool:
	if not individual.immunities.has(condition_id):
		return false
	var until := int(individual.immunities[condition_id])
	if until == IMMUNE_FOREVER or until > game_data.get_absolute_day():
		return true
	individual.immunities.erase(condition_id)
	return false


static func _try_infect(
	target: HumanIndividual, source: HumanIndividual, condition_id: String, channel: Channel, game_data: GameData, place: String
) -> void:
	var rules := HealthConditionService.get_rules(condition_id)
	if rules == null:
		return
	var probability := _probability(rules, channel)
	if probability <= 0.0:
		return
	var head := "%s, %s: #%d %s esposto a %s da #%d %s" % [
		CHANNEL_NAMES[channel], place, target.id, target.name, condition_id, source.id, source.name
	]
	if is_incubating(target, condition_id) or not HealthConditionService.can_get(target, condition_id, game_data):
		_log("%s — già malato o età esclusa, nessun tiro." % head)
		return
	if is_immune(target, condition_id, game_data):
		_log("%s — immune, nessun tiro." % head)
		return
	var roll := randf()
	if roll >= probability:
		_log("%s — tiro %.3f su %.3f: niente." % [head, roll, probability])
		return
	var days := start_incubation(target, condition_id, game_data, source.id)
	if days <= 0:
		_log("%s — tiro %.3f su %.3f: CONTAGIATO, senza incubazione si ammala subito." % [head, roll, probability])
		return
	_log("%s — tiro %.3f su %.3f: CONTAGIATO, incubazione %d gg." % [head, roll, probability, days])


# Dà a `target` la malattia `condition_id` in incubazione (giorni estratti dal .tres; 0 = parte subito acuta con
# HealthConditionService.add_condition). Nessun controllo: lo fa chi chiama. `source_id` -1 = nessuna sorgente (paziente
# zero di IllnessEvent). Ritorna i giorni di incubazione.
static func start_incubation(target: HumanIndividual, condition_id: String, game_data: GameData, source_id: int = -1) -> int:
	var rules := HealthConditionService.get_rules(condition_id)
	if rules == null:
		return 0
	var days := randi_range(rules.incubation_min_days, maxi(rules.incubation_min_days, rules.incubation_max_days))
	if days <= 0:
		HealthConditionService.add_condition(target, condition_id, game_data)
		return 0
	target.incubating_conditions.append({"id": condition_id, "days": days, KEY_SOURCE_ID: source_id})
	return days


static func _advance_incubation(individual: HumanIndividual, game_data: GameData) -> Array[String]:
	var onset: Array[String] = []
	var remaining: Array[Dictionary] = []
	for entry in individual.incubating_conditions:
		var condition_id := String(entry.get("id", ""))
		var days := int(entry.get("days", 0)) - 1
		if days > 0:
			remaining.append({"id": condition_id, "days": days, KEY_SOURCE_ID: int(entry.get(KEY_SOURCE_ID, -1))})
			continue
		if HealthConditionService.add_condition(individual, condition_id, game_data):
			onset.append(condition_id)
			_log("#%d %s: finita l'incubazione, si manifesta %s (contagio da #%d)." % [
				individual.id, individual.name, condition_id, int(entry.get(KEY_SOURCE_ID, -1))
			])
	individual.incubating_conditions = remaining
	return onset


static func _probability(rules: HealthConditionRules, channel: Channel) -> float:
	match channel:
		Channel.HOUSEHOLD:
			return rules.contagion_household_per_day
		Channel.CAREGIVER:
			return rules.contagion_caregiver
	return rules.contagion_contact


static func _today() -> int:
	return GameSettings.active_game_data.get_absolute_day() if GameSettings.active_game_data != null else -1


static func _log(text: String) -> void:
	if DebugLogging.ENABLED:
		print("[CONTAGION] %s" % text)


# Individuo vivo con id `individual_id`, null se non c'è (partner della conversazione, malato).
static func find_individual(individual_id: int) -> HumanIndividual:
	for member in GameSettings.active_human_individuals:
		if member != null and member.id == individual_id:
			return member
	return null
