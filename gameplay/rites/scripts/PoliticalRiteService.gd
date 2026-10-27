class_name PoliticalRiteService
extends RefCounted

# Calcoli delle riunioni politiche al Cerchio del consiglio (2026-10-26, richiesta utente — consiglio degli anziani). Il
# raduno (convocazione, attesa, durata, felicità e socialità, coesione) è quello dei riti sociali (SocialRiteService); qui
# solo ciò che è proprio delle riunioni: dove si possono tenere, ogni quanto, e gli effetti a fine riunione. Senza stato.

# Fattore della leadership di chi guida (skill_action_effects.tres, 2026-10-26: bonus 0.25): moltiplica l'Autorità e il
# valore politico prodotti e la lealtà data, non la leadership, la socialità né la coesione guadagnate.
const SKILL_EFFECT_KEY := "council"
# Icone di esito mostrate dalla scena a fine riunione (IconRegistry, 2026-10-26).
const SUCCESS_ICON_KEY := "council_success"
const QUARREL_ICON_KEY := "council_quarrel"


# Motivo (già tradotto) per cui `rules` non si può ordinare a `building` adesso; "" = si può.
static func get_start_rejection(building: Building, rules: PoliticalRiteRules, game_data: GameData) -> String:
	if rules.requires_village_center:
		var folk: Folk = GameSettings.active_human_folk
		if folk == null or VillageService.find_village_by_center(folk, building.id) == null:
			return TranslationServer.translate("political_rite_reject_not_center")
	var days_left := get_days_until_allowed(building, rules, game_data)
	if days_left > 0:
		return TranslationServer.translate("political_rite_reject_too_soon").format({"days": days_left})
	return ""


# Giorni che mancano perché il rito si possa ordinare di nuovo a `building` (0 = subito).
static func get_days_until_allowed(building: Building, rules: PoliticalRiteRules, game_data: GameData) -> int:
	if building == null or game_data == null or not building.last_rite_end_day.has(rules.id):
		return 0
	var elapsed := game_data.get_absolute_day() - int(building.last_rite_end_day[rules.id])
	return maxi(rules.min_days_between - elapsed, 0)


# Felicità sotto questa frazione del massimo = scontento, per la lite (2026-10-26).
const UNHAPPY_FRACTION := 0.5


# Probabilità di lite della riunione (PoliticalRiteRules, gruppo Quarrel): 0 se la base è 0. `present` = tutti i presenti,
# chi guida compreso.
static func get_quarrel_chance(
	rules: PoliticalRiteRules, leader: HumanIndividual, present: Array[HumanIndividual], village: Village
) -> float:
	if rules.quarrel_base_chance <= 0.0:
		return 0.0
	var chance := rules.quarrel_base_chance + rules.quarrel_unhappy_weight * get_unhappy_share(present)
	if village != null and village.cohesion < rules.quarrel_low_cohesion_threshold:
		chance += rules.quarrel_low_cohesion_chance
	if leader != null:
		chance -= rules.quarrel_leadership_reduction * leader.skill_leadership / HumanIndividual.SKILL_MAX
	return clampf(chance, 0.0, rules.quarrel_max_chance)


static func get_unhappy_share(present: Array[HumanIndividual]) -> float:
	if present.is_empty():
		return 0.0
	var unhappy := 0
	for member in present:
		if _is_unhappy(member):
			unhappy += 1
	return float(unhappy) / float(present.size())


static func _is_unhappy(member: HumanIndividual) -> bool:
	return member.current_happiness < member.max_happiness * UNHAPPY_FRACTION


# Riunione saltata (attesa scaduta, SocialRiteService.advance): coesione persa dal villaggio, lealtà persa da tutti i suoi
# abitanti con la lealtà attiva. `village` = villaggio dell'edificio.
static func apply_skip(building: Building, rules: PoliticalRiteRules, village: Village, individuals: Array) -> void:
	if village == null:
		return
	VillageCohesionService.add(village, -rules.skip_cohesion_loss, "riunione '%s' saltata" % rules.id)
	var losers := 0
	if rules.skip_loyalty_loss > 0.0:
		for member in individuals:
			var individual := member as HumanIndividual
			if individual == null or individual.village_ref != village or not VillageService.is_loyalty_active(individual):
				continue
			individual.current_loyalty = clampf(individual.current_loyalty - rules.skip_loyalty_loss, 0.0, individual.max_loyalty)
			losers += 1
	SocialRiteService.log_event("'%s' all'edificio #%d saltato: coesione -%.2f, lealtà -%.0f a %d abitanti." % [
		rules.id, building.id, rules.skip_cohesion_loss, rules.skip_loyalty_loss, losers,
	])


# Effetti propri della riunione a fine durata (felicità, socialità e coesione li dà SocialRiteService._finish): tiro della
# lite, poi leadership ai presenti, lealtà, Autorità all'edificio, valore politico al villaggio, oppure — se litigano — solo
# la lealtà persa dagli scontenti. Sempre il giorno di fine per l'attesa del prossimo ordine e l'esito per la scena
# (BuildingRuntimeState.political_rite_outcomes). Torna true se è finita in lite.
static func apply_meeting(
	building: Building, rules: PoliticalRiteRules, leader: HumanIndividual, participants: Array[HumanIndividual],
	game_data: GameData
) -> bool:
	building.last_rite_end_day[rules.id] = game_data.get_absolute_day()
	var present: Array[HumanIndividual] = participants.duplicate()
	if leader != null:
		present.append(leader)
	var folk: Folk = GameSettings.active_human_folk
	var village: Village = folk.find_village(building.village_id) if folk != null else null
	var quarrel_chance := get_quarrel_chance(rules, leader, present, village)
	var quarrel := quarrel_chance > 0.0 and randf() < quarrel_chance
	game_data.building_runtime.political_rite_outcomes[building.id] = {"rite_id": rules.id, "quarrel": quarrel}
	if quarrel:
		var losers := 0
		for member in present:
			if _is_unhappy(member) and VillageService.is_loyalty_active(member):
				member.current_loyalty = clampf(member.current_loyalty - rules.quarrel_loyalty_loss_unhappy, 0.0, member.max_loyalty)
				losers += 1
		SocialRiteService.log_event("'%s' all'edificio #%d finisce in LITE (probabilità %.0f%%): %d scontenti su %d perdono %.0f di lealtà." % [
			rules.id, building.id, quarrel_chance * 100.0, losers, present.size(), rules.quarrel_loyalty_loss_unhappy,
		])
		return true
	if leader != null:
		leader.skill_leadership = minf(leader.skill_leadership + rules.leadership_gain_organizer, HumanIndividual.SKILL_MAX)
	for participant in participants:
		participant.skill_leadership = minf(participant.skill_leadership + rules.leadership_gain_participant, HumanIndividual.SKILL_MAX)
	var leader_factor := SkillEffectService.get_factor(SKILL_EFFECT_KEY, leader) if leader != null else 1.0
	if rules.loyalty_gain > 0.0:
		for member in present:
			if not VillageService.is_loyalty_active(member):
				continue
			member.current_loyalty = clampf(member.current_loyalty + rules.loyalty_gain * leader_factor, 0.0, member.max_loyalty)
	var points := (rules.influence_points_base + rules.influence_points_per_participant * float(participants.size())) * leader_factor
	var authority_before := InfluenceService.get_points(building, InfluenceService.InfluenceType.POLITICAL)
	InfluenceService.add_points(building, InfluenceService.InfluenceType.POLITICAL, points, game_data)
	var authority_after := InfluenceService.get_points(building, InfluenceService.InfluenceType.POLITICAL)
	if village != null and village.center_building_id != -1:
		var village_gain := (rules.village_political_gain + rules.village_political_gain_per_participant * float(participants.size())) * leader_factor
		if village_gain > 0.0:
			village.add_influence_value(InfluenceService.InfluenceType.POLITICAL, village_gain)
			SocialRiteService.log_event("  valore politico di %s: +%.2f (totale %.2f)." % [
				village.get_display_name(), village_gain, village.get_influence_value(InfluenceService.InfluenceType.POLITICAL)
			])
	SocialRiteService.log_event("'%s' all'edificio #%d guidato da %s (x%.2f, lite %.0f%%): %d partecipanti; autorità %.1f -> %.1f (+%.1f)." % [
		rules.id, building.id, "#%d %s" % [leader.id, leader.name] if leader != null else "nessuno", leader_factor,
		quarrel_chance * 100.0, participants.size(), authority_before, authority_after, points,
	])
	return false
