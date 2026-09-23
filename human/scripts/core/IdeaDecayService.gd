class_name IdeaDecayService
extends RefCounted

# Decadimento dei pensieri investiti in un'idea NON attiva e NON completata (2026-09-21, richiesta
# utente). Regola: grazia di EraRules.idea_decay_grace_years dal momento in cui l'idea smette di
# essere attiva; poi, a ogni anniversario completo, si perde EraRules.idea_decay_percent_of_cost del
# thoughts_cost dell'idea (per eccesso, minimo 1), fino a zero. Mai decadimento frazionale nel corso
# dell'anno. L'idea attiva e le completate non decadono mai.
#
# Stato in Folk.idea_decay_due_day (Idea.id -> giorno assoluto del prossimo decadimento), persistito.
# Stateless (RefCounted, static func) come gli altri *Service di questa cartella; il tick giornaliero
# è agganciato in GameTimeService._on_day_advanced.


# Un'idea smette di essere attiva (switch, vedi IdeaProgressService.select_idea): se ha pensieri
# investiti, primo decadimento a oggi + (grazia + 1 anno).
static func on_idea_deactivated(folk: Folk, idea_id: String, current_day: int, era_rules: EraRules) -> void:
	if idea_id == "" or folk.completed_ideas.has(idea_id):
		return
	if int(folk.thoughts_invested.get(idea_id, 0)) <= 0:
		return
	folk.idea_decay_due_day[idea_id] = current_day + _first_decay_delay_days(era_rules)


# Un'idea torna attiva: non decade più finché resta tale.
static func on_idea_activated(folk: Folk, idea_id: String) -> void:
	folk.idea_decay_due_day.erase(idea_id)


# Tick giornaliero. Per ogni voce scaduta applica il taglio e sposta la scadenza di un anno (più
# tagli se più anniversari sono già passati, es. dopo un salto di giorni). Ritorna true se ha
# modificato thoughts_invested.
static func apply_daily(folk: Folk, current_day: int, era_rules: EraRules) -> bool:
	if era_rules == null:
		return false
	var changed := false

	# Scadenza mancante per un'idea con pensieri non attiva/non completata (es. salvataggio
	# precedente al decadimento): la grazia parte da oggi.
	for idea_id in folk.thoughts_invested.keys():
		if int(folk.thoughts_invested[idea_id]) > 0 and idea_id != folk.active_idea_id \
				and not folk.completed_ideas.has(idea_id) and not folk.idea_decay_due_day.has(idea_id):
			folk.idea_decay_due_day[idea_id] = current_day + _first_decay_delay_days(era_rules)

	for idea_id in folk.idea_decay_due_day.keys():
		var invested := int(folk.thoughts_invested.get(idea_id, 0))
		if idea_id == folk.active_idea_id or folk.completed_ideas.has(idea_id) or invested <= 0:
			folk.idea_decay_due_day.erase(idea_id)
			if invested <= 0:
				folk.thoughts_invested.erase(idea_id)
			continue
		var idea := IdeaCalculator.get_idea(idea_id)
		if idea == null:
			continue
		# snappedf prima di ceili: es. 30 * 0.1 = 3.0000000000000004 in virgola mobile, che
		# ceili porterebbe a 4 invece di 3.
		var cut := maxi(1, ceili(snappedf(idea.thoughts_cost * era_rules.idea_decay_percent_of_cost, 0.0001)))
		var due_day := int(folk.idea_decay_due_day[idea_id])
		while due_day <= current_day and invested > 0:
			invested -= cut
			due_day += GameData.DAYS_PER_YEAR
			changed = true
		if invested <= 0:
			folk.thoughts_invested.erase(idea_id)
			folk.idea_decay_due_day.erase(idea_id)
		else:
			folk.thoughts_invested[idea_id] = invested
			folk.idea_decay_due_day[idea_id] = due_day
	return changed


static func _first_decay_delay_days(era_rules: EraRules) -> int:
	var grace_years: int = era_rules.idea_decay_grace_years if era_rules != null else 1
	return (grace_years + 1) * GameData.DAYS_PER_YEAR
