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
#   - punti di influenza RELIGIOUS dell'edificio + influence_gain × fattore skill (InfluenceService.add_points,
#     2026-10-03 punti e soglie), aggiunti DOPO aver contato i presenti, quindi con il raggio di prima del rito;
#   - giorno del rito sull'edificio (Building.last_rite_absolute_day), letto dalla regola giornaliera della fede;
#   - parenti del defunto (2026-10-04, funerale — `relative_ids`, id -> "partner"/"parent"/"child"): un presente che è
#     parente riceve faith_relatives al posto di faith_present (se il rito ne ha uno, > 0); fuori dal raggio resta
#     faith_population.
#
# Log [RITE] (2026-10-04, DebugLogging.SHOW_RITE_LOGS): intestazione, una riga per ogni pipottino che riceve fede con il
# motivo, punti di influenza. Solo lettura dei valori già calcolati, nessun effetto sul rito. `deceased_name`: solo per
# il log del funerale.


static func apply_completion(
	celebrant: HumanIndividual, building: Building, rules: RiteRules, individuals: Array, relative_ids: Dictionary = {},
	deceased_name: String = ""
) -> void:
	if celebrant == null or building == null or rules == null:
		return
	var log_enabled := DebugLogging.ENABLED and DebugLogging.SHOW_RITE_LOGS
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null:
		building.last_rite_absolute_day = game_data.get_absolute_day()
	var skill_factor := SkillEffectService.get_factor(RiteAction.SKILL_EFFECT_KEY, celebrant)
	if log_enabled:
		print("[RITE] '%s' presso %s #%d — celebra #%d %s (ritualità %.1f, moltiplicatore x%.2f)%s." % [
			TranslationServer.translate(rules.display_name), TranslationServer.translate(building.rules.building_name) if building.rules != null else building.building_type_name,
			building.id, celebrant.id, celebrant.name, celebrant.skill_ritual, skill_factor,
			" — defunto: %s" % deceased_name if deceased_name != "" else ""
		])
	var celebrant_before := celebrant.current_faith
	celebrant.current_faith = _clamp_faith(celebrant, celebrant.current_faith + rules.faith_celebrant)
	if log_enabled:
		_log_faith(celebrant, celebrant_before, "celebrante" + _relative_suffix(relative_ids, celebrant.id))
	var radius := InfluenceService.get_effective_radius(building, InfluenceService.InfluenceType.RELIGIOUS)
	var center := InfluenceService.building_absolute_center(building)
	for other in individuals:
		var member := other as HumanIndividual
		if member == null or member == celebrant:
			continue
		var before := member.current_faith
		if radius > 0 and _absolute_position(member).distance_to(center) <= float(radius):
			var is_relative := rules.faith_relatives > 0.0 and relative_ids.has(member.id)
			# Un solo valore per pipottino, il più alto che gli spetta (2026-10-04).
			var present_faith := maxf(rules.faith_relatives, rules.faith_present) if is_relative else rules.faith_present
			member.current_faith = _clamp_faith(member, member.current_faith + present_faith * skill_factor)
			if log_enabled:
				_log_faith(member, before, "parente presente (%s)" % _relative_kind_text(relative_ids[member.id]) if is_relative else "presente nel raggio")
		elif celebrant.source_group_ref != null and member.source_group_ref == celebrant.source_group_ref:
			member.current_faith = _clamp_faith(member, member.current_faith + rules.faith_population * skill_factor)
			if log_enabled:
				var reason := "popolazione"
				if relative_ids.has(member.id):
					reason += " (parente: %s, fuori dal raggio)" % _relative_kind_text(relative_ids[member.id])
				_log_faith(member, before, reason)
		elif log_enabled and relative_ids.has(member.id):
			print("[RITE]   #%d %s: parente (%s) fuori dal raggio e fuori dalla popolazione di chi celebra — nessuna fede." % [
				member.id, member.name, _relative_kind_text(relative_ids[member.id])
			])
	var influence_amount := rules.influence_gain * skill_factor
	InfluenceService.add_points(building, InfluenceService.InfluenceType.RELIGIOUS, influence_amount, game_data)
	if log_enabled:
		print("[RITE]   influenza religiosa all'edificio: +%.1f punti (totale %.1f)." % [
			influence_amount, InfluenceService.get_points(building, InfluenceService.InfluenceType.RELIGIOUS)
		])


static func _log_faith(member: HumanIndividual, before: float, reason: String) -> void:
	print("[RITE]   #%d %s: +%.1f fede (%.1f -> %.1f) — %s." % [
		member.id, member.name, member.current_faith - before, before, member.current_faith, reason
	])


# `kind`: "partner"/"parent"/"child", oppure {"kind", "of"} per i parenti dei sepolti (ricordo dei defunti): "genitore
# di Anna".
static func _relative_kind_text(kind: Variant) -> String:
	if kind is Dictionary:
		return "%s di %s" % [_relative_kind_text((kind as Dictionary).get("kind", "")), String((kind as Dictionary).get("of", "?"))]
	match String(kind):
		"partner":
			return "partner"
		"parent":
			return "genitore"
		"child":
			return "figlio"
	return "parente"


static func _relative_suffix(relative_ids: Dictionary, member_id: int) -> String:
	return " (anche parente: %s)" % _relative_kind_text(relative_ids[member_id]) if relative_ids.has(member_id) else ""


# Posizione del pipottino in microcelle ASSOLUTE del mondo (stessa misura di InfluenceService.building_absolute_center).
static func _absolute_position(individual: HumanIndividual) -> Vector2:
	return Vector2(individual.home_macro_coords.x * World.WIDTH, individual.home_macro_coords.y * World.HEIGHT) + individual.position


static func _clamp_faith(individual: HumanIndividual, value: float) -> float:
	return clampf(value, 0.0, maxf(individual.max_faith, 0.0))
