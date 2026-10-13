class_name VillageInfluenceService
extends RefCounted

# Valori assoluti di influenza dei villaggi (2026-10-12, passo 4 Folk/Village). Stateless. Regola 1, crescita annuale:
# a ogni cambio d'anno, per ogni villaggio CON un centro e per ogni InfluenceService.InfluenceType: valore += somma dei
# raggi effettivi di quel momento (InfluenceService.get_effective_radius: base + livelli, danneggiati compresi con il
# loro raggio ridotto) dei suoi edifici completi e non demoliti. Un villaggio senza centro non accumula nulla. Il valore
# del popolo è la somma dei villaggi (Folk.get_influence_value). Gli altri incrementi/decrementi sono degli eventi.


static func apply_annual_growth(folk: Folk, world: World) -> void:
	if folk == null or world == null:
		return
	for village in folk.villages:
		if village.center_building_id == -1:
			continue
		var gains := compute_annual_gains(village, world.buildings)
		for influence_type in gains:
			village.add_influence_value(influence_type, float(gains[influence_type]))
		if not DebugLogging.ENABLED:
			continue
		print("[VILLAGE INFLUENCE] %s: +P %d +C %d +R %d -> P %d C %d R %d" % [
			village.get_display_name(),
			gains[InfluenceService.InfluenceType.POLITICAL], gains[InfluenceService.InfluenceType.CULTURAL],
			gains[InfluenceService.InfluenceType.RELIGIOUS],
			roundi(village.get_influence_value(InfluenceService.InfluenceType.POLITICAL)),
			roundi(village.get_influence_value(InfluenceService.InfluenceType.CULTURAL)),
			roundi(village.get_influence_value(InfluenceService.InfluenceType.RELIGIOUS)),
		])


# Guadagno della regola 1 con i raggi di ADESSO: InfluenceType -> int. Usato a fine anno e, come "incremento previsto a
# fine anno", dalla scheda Influenza delle statistiche. Tutto 0 per un villaggio senza centro.
static func compute_annual_gains(village: Village, buildings: Array[Building]) -> Dictionary:
	var gains := {}
	for influence_type in InfluenceService.InfluenceType.values():
		gains[influence_type] = 0
	if village == null or village.center_building_id == -1:
		return gains
	for building in buildings:
		if building.village_id != village.id:
			continue
		for influence_type in gains:
			gains[influence_type] += InfluenceService.get_effective_radius(building, influence_type)
	return gains


# Regola culturale (2026-10-12): idea `idea_id` appena sbloccata dal pensiero depositato in `building` — al villaggio di
# quell'edificio, se ha un centro, HumanRules.idea_culture_gain_fraction × thoughts_cost dell'idea come valore C. Con più
# villaggi tutto a quello dell'ultimo pensiero (scelta voluta: semplice, da rivedere col secondo villaggio se serve).
static func add_idea_culture(folk: Folk, building: Building, idea_id: String) -> void:
	if folk == null or building == null or folk.human_rules_ref == null:
		return
	var village := folk.find_village(building.village_id)
	var idea := IdeaCalculator.get_idea(idea_id)
	if village == null or village.center_building_id == -1 or idea == null:
		return
	var amount := float(idea.thoughts_cost) * folk.human_rules_ref.idea_culture_gain_fraction
	village.add_influence_value(InfluenceService.InfluenceType.CULTURAL, amount)
	if DebugLogging.ENABLED:
		print("[VILLAGE INFLUENCE] %s: idea '%s' sbloccata, +C %.1f (totale %.1f)" % [
			village.get_display_name(), idea_id, amount, village.get_influence_value(InfluenceService.InfluenceType.CULTURAL)
		])


# Regola politica (2026-10-12): `adult_count` adulti accolti in `village` — HumanRules.accepted_adult_political_gain
# ciascuno come valore P. Solo con un centro (gli arrivi lo richiedono comunque).
static func add_accepted_adults(folk: Folk, village: Village, adult_count: int) -> void:
	if folk == null or village == null or folk.human_rules_ref == null or adult_count <= 0 or village.center_building_id == -1:
		return
	var amount := float(adult_count) * folk.human_rules_ref.accepted_adult_political_gain
	village.add_influence_value(InfluenceService.InfluenceType.POLITICAL, amount)
	if DebugLogging.ENABLED:
		print("[VILLAGE INFLUENCE] %s: %d adulti accolti, +P %.1f (totale %.1f)" % [
			village.get_display_name(), adult_count, amount, village.get_influence_value(InfluenceService.InfluenceType.POLITICAL)
		])
