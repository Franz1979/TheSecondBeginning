@tool
extends EditorScript

# Test manuale TEMPORANEO per HumanMortalityIndividualService.check_mortality (Step 3/4) — stesso
# stile/cartella di _debug_test_mortality_curve.gd (Step 2): EditorScript, Script Editor ->
# File -> Run (Ctrl+Shift+X) mentre il file è aperto, nessuna scena richiesta. Da rimuovere una
# volta verificato lo step.
#
# Popolazione fittizia con età fisse, costruita valorizzando solo birth_year_virtual (l'unico
# campo anagrafico che HumanIndividual salva davvero — vedi il commento su
# HumanMortalityIndividualService.check_mortality) rispetto a TEST_YEAR sotto, cosicché age =
# TEST_YEAR - birth_year_virtual dia esattamente l'età voluta. `id` riusato come chiave di comodo
# per il conteggio (age stesso, univoco in questa lista di test) — nessun significato oltre questo
# test.
#
# durations_male/female (richiesta utente, 2026-09-05 — check_mortality/get_annual_death_
# probability ora le richiedono esplicite, per l'aggancio all'Era): questo test isolato non ha
# alcun concetto di Era, quindi passa semplicemente le durate BASE di HumanRules — equivalente a
# "nessuno scaling", coerente con quello che il test ha sempre verificato finora.
const TEST_YEAR := 1000
const TEST_AGES: Array[int] = [20, 35, 55, 75, 95, 101]
const RUNS := 1000

func _run() -> void:
	var rules := load("res://human/data/human_rules/player_human_rules.tres") as HumanRules

	_run_mortality_frequency_check(rules)
	_run_scheduled_death_day_check(rules)


# Step 3: stesso test di sempre — frequenza di marcatura su 1000 run, confrontata con la
# probabilità attesa da HumanCalculator.get_annual_death_probability.
func _run_mortality_frequency_check(rules: HumanRules) -> void:
	var individuals := _build_test_population()
	var marked_counts: Dictionary = {}
	for individual in individuals:
		marked_counts[individual.id] = 0

	for i in range(RUNS):
		var marked := HumanMortalityIndividualService.check_mortality(
			individuals, rules, TEST_YEAR, rules.age_band_durations_male, rules.age_band_durations_female
		)
		for individual in marked:
			marked_counts[individual.id] += 1

	print("--- Frequenza di marcatura su %d run ---" % RUNS)
	for age in TEST_AGES:
		print("age=%d -> marcato %d/%d volte (probabilità attesa=%s)" % [
			age, marked_counts[age], RUNS,
			HumanCalculator.get_annual_death_probability(
				age, rules, rules.age_band_durations_male, rules.age_band_durations_female
			)
		])


# Step 4 (nuovo): UNA sola chiamata (non 1000 come sopra — qui vogliamo vedere scheduled_death_day
# assegnato per davvero, un tiro di dado ripetuto lo sovrascriverebbe ad ogni run) — verifica che
# i non marcati restino a -1 e i marcati abbiano un giorno 0..364. Chiamata una seconda volta per
# mostrare che il giorno assegnato cambia da un tiro all'altro (non un valore fisso).
func _run_scheduled_death_day_check(rules: HumanRules) -> void:
	print("--- scheduled_death_day (due tiri separati, per mostrare che cambia) ---")
	for attempt in range(2):
		var individuals := _build_test_population()
		var marked := HumanMortalityIndividualService.check_mortality(
			individuals, rules, TEST_YEAR, rules.age_band_durations_male, rules.age_band_durations_female
		)
		var marked_ids: Dictionary = {}
		for individual in marked:
			marked_ids[individual.id] = true

		print("tiro #%d:" % (attempt + 1))
		for individual in individuals:
			print("  age=%d -> marcato=%s, scheduled_death_day=%d" % [
				individual.id, marked_ids.has(individual.id), individual.scheduled_death_day
			])


func _build_test_population() -> Array[HumanIndividual]:
	var individuals: Array[HumanIndividual] = []
	for age in TEST_AGES:
		var individual := HumanIndividual.new()
		individual.id = age
		individual.sex = HumanTypes.Sex.MALE
		individual.birth_year_virtual = TEST_YEAR - age
		individuals.append(individual)
	return individuals
