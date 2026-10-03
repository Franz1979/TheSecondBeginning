class_name RiteEffectService
extends RefCounted

# Effetti del COMPLETAMENTO di un rito (2026-10-02, richiesta utente — task Rite, punto 3). Stateless, chiamato da
# RiteAction.on_complete; una Task interrotta o annullata non arriva mai qui, quindi nessun effetto.
#   - chi celebra: current_faith + faith_celebrant;
#   - presenti: ogni altro pipottino, di qualunque età, che in quell'istante si trova entro InfluenceService.
#     get_effective_radius(edificio, RELIGIOUS) dal centro dell'edificio: current_faith + faith_present × fattore
#     skill di chi celebra (SkillEffectService, chiave RiteAction.SKILL_EFFECT_KEY);
#   - popolazione (2026-10-02): ogni altro pipottino dello stesso HumanPopulationGroup di chi celebra (source_group_ref,
#     non il Folk), ovunque e di qualunque età, che non sia chi celebra né un presente: current_faith + faith_population
#     × lo stesso fattore skill. Un solo bonus per pipottino e per rito (celebrante, presente o popolazione);
#   - ogni fede limitata a [0, max_faith];
#   - raggio RELIGIOUS dell'edificio + radius_gain × fattore skill (InfluenceService.add_radius, 2026-10-02 passo 4c),
#     applicato DOPO aver contato i presenti, quindi con il raggio di prima del rito;
#   - giorno del rito sull'edificio (Building.last_rite_absolute_day), letto dalla regola giornaliera della fede.


static func apply_completion(celebrant: HumanIndividual, building: Building, rules: RiteRules, individuals: Array) -> void:
	if celebrant == null or building == null or rules == null:
		return
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null:
		building.last_rite_absolute_day = game_data.get_absolute_day()
	celebrant.current_faith = _clamp_faith(celebrant, celebrant.current_faith + rules.faith_celebrant)
	var skill_factor := SkillEffectService.get_factor(RiteAction.SKILL_EFFECT_KEY, celebrant)
	var radius := InfluenceService.get_effective_radius(building, InfluenceService.InfluenceType.RELIGIOUS)
	var center := InfluenceService.building_absolute_center(building)
	for other in individuals:
		var member := other as HumanIndividual
		if member == null or member == celebrant:
			continue
		if radius > 0 and _absolute_position(member).distance_to(center) <= float(radius):
			member.current_faith = _clamp_faith(member, member.current_faith + rules.faith_present * skill_factor)
		elif celebrant.source_group_ref != null and member.source_group_ref == celebrant.source_group_ref:
			member.current_faith = _clamp_faith(member, member.current_faith + rules.faith_population * skill_factor)
	InfluenceService.add_radius(building, InfluenceService.InfluenceType.RELIGIOUS, rules.radius_gain * skill_factor)


# Posizione del pipottino in microcelle ASSOLUTE del mondo (stessa misura di InfluenceService.building_absolute_center).
static func _absolute_position(individual: HumanIndividual) -> Vector2:
	return Vector2(individual.home_macro_coords.x * World.WIDTH, individual.home_macro_coords.y * World.HEIGHT) + individual.position


static func _clamp_faith(individual: HumanIndividual, value: float) -> float:
	return clampf(value, 0.0, maxf(individual.max_faith, 0.0))
