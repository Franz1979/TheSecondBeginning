class_name TeachingRiteService
extends RefCounted

# Calcoli della lezione al Ceppo dell'insegnamento (2026-10-16, richiesta utente — insegnamento orale, passo 2). Il raduno
# (convocazione, attesa, durata, felicità e socialità, coesione) è quello dei riti sociali (SocialRiteService); qui solo
# ciò che è proprio della lezione: chi può insegnare, la materia e gli effetti a fine lezione. Senza stato.

# Nel record del rito (GameData.active_social_rites): la skill insegnata, fissata all'avvio.
const RECORD_SUBJECT_KEY := "subject"


# Skill insegnabile migliore di `individual` ("" se nessuna): la più alta tra le skill_* non escluse; a parità la prima
# nell'ordine di HumanIndividual.get_skill_property_names.
static func best_skill(rules: TeachingRiteRules, individual: HumanIndividual) -> String:
	if rules == null or individual == null:
		return ""
	var best := ""
	var best_value := -1.0
	for skill_name in individual.get_skill_property_names():
		if rules.excluded_subjects.has(skill_name):
			continue
		var value := float(individual.get(skill_name))
		if value > best_value:
			best_value = value
			best = skill_name
	return best


# true se `individual` ha qualcosa da insegnare: skill insegnabile migliore almeno min_teach_skill (l'età la controlla
# RiteService.can_celebrate con allowed_age_bands).
static func can_teach(rules: TeachingRiteRules, individual: HumanIndividual) -> bool:
	var subject := best_skill(rules, individual)
	return subject != "" and float(individual.get(subject)) >= rules.min_teach_skill


# Guadagno nella materia di un allievo: (insegnante − allievo) × gain_fraction × (1 + cognizione/SKILL_MAX), intero tra
# min_gain e max_gain; 0 se l'allievo ne sa già quanto l'insegnante.
static func student_gain(rules: TeachingRiteRules, teacher_value: float, student_value: float, teacher_cognition: float) -> int:
	var difference := teacher_value - student_value
	if difference <= 0.0:
		return 0
	var raw := difference * rules.gain_fraction * (1.0 + teacher_cognition / HumanIndividual.SKILL_MAX)
	return clampi(floori(raw), rules.min_gain, rules.max_gain)


# Effetti propri della lezione a fine durata (felicità, socialità e coesione li dà SocialRiteService._finish): materia e
# cognizione agli allievi presenti, punti culturali all'edificio. Senza l'insegnante presente nessun insegnamento.
static func apply_lesson(
	record: Dictionary, building: Building, rules: TeachingRiteRules, teacher: HumanIndividual,
	students: Array[HumanIndividual], game_data: GameData
) -> void:
	var subject := String(record.get(RECORD_SUBJECT_KEY, ""))
	if teacher == null or subject == "":
		SocialRiteService.log_event("lezione all'edificio #%d: insegnante assente, nessun insegnamento." % building.id)
		return
	var teacher_value := float(teacher.get(subject))
	var parts: Array[String] = []
	for student in students:
		var gain := student_gain(rules, teacher_value, float(student.get(subject)), teacher.skill_cognition)
		if gain > 0:
			student.set(subject, minf(float(student.get(subject)) + float(gain), HumanIndividual.SKILL_MAX))
		student.skill_cognition = minf(student.skill_cognition + rules.cognition_gain, HumanIndividual.SKILL_MAX)
		parts.append("#%d %s +%d" % [student.id, student.name, gain])
	var points := rules.influence_points_base + rules.influence_points_per_student * float(students.size())
	var tradition_before := InfluenceService.get_points(building, InfluenceService.InfluenceType.CULTURAL)
	InfluenceService.add_points(building, InfluenceService.InfluenceType.CULTURAL, points, game_data)
	var tradition_after := InfluenceService.get_points(building, InfluenceService.InfluenceType.CULTURAL)
	# Cultura del villaggio (2026-10-17, richiesta utente): come la religione con i riti religiosi.
	var folk: Folk = GameSettings.active_human_folk
	var village: Village = folk.find_village(building.village_id) if folk != null else null
	if village != null and village.center_building_id != -1:
		var village_gain := rules.village_culture_gain + rules.village_culture_gain_per_student * float(students.size())
		if village_gain > 0.0:
			village.add_influence_value(InfluenceService.InfluenceType.CULTURAL, village_gain)
			SocialRiteService.log_event("  valore culturale di %s: +%.2f (totale %.2f)." % [
				village.get_display_name(), village_gain, village.get_influence_value(InfluenceService.InfluenceType.CULTURAL)
			])
	SocialRiteService.log_event("lezione di #%d %s all'edificio #%d: %s %d, allievi %s; tradizione dell'edificio %.0f -> %.0f (+%.0f)." % [
		teacher.id, teacher.name, building.id, subject, roundi(teacher_value),
		", ".join(parts) if not parts.is_empty() else "nessuno", tradition_before, tradition_after, points,
	])
