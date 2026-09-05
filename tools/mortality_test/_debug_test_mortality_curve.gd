@tool
extends EditorScript

# Test manuale TEMPORANEO per HumanCalculator.get_annual_death_probability — nessun framework di
# test nel progetto (vedi CLAUDE.md), quindi un EditorScript da eseguire con Script Editor ->
# File -> Run (Ctrl+Shift+X) mentre il file è aperto, nessuna scena richiesta. Da rimuovere una
# volta verificato lo step (o quando arriverà check_mortality e sostituirà questa verifica).
func _run() -> void:
	var rules := load("res://human/data/human_rules/player_human_rules.tres") as HumanRules
	var test_ages: Array[int] = [30, 40, 50, 60, 70, 80, 90, 99, 100, 105]
	for age in test_ages:
		print("age=%d -> death_probability=%s" % [
			age,
			HumanCalculator.get_annual_death_probability(
				age, rules, rules.age_band_durations_male, rules.age_band_durations_female
			)
		])
