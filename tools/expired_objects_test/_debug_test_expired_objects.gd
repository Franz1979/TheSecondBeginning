@tool
extends EditorScript

# Test manuale TEMPORANEO per ExpiredObjectCalculator.is_expired (Step 2) — stesso stile/cartella
# di tools/mortality_test/_debug_test_check_mortality.gd: EditorScript, Script Editor -> File ->
# Run (Ctrl+Shift+X) mentre il file è aperto, nessuna scena richiesta. Da rimuovere una volta
# verificato lo step.
#
# Tre record fittizi (Dictionary piatti, stesso stile di GameData.expired_objects — position non
# serve per is_expired, omesso qui, la funzione non lo legge):
# - A: nessun attraversamento anno, days_to_expire=182 (dead_body_rules.tres reale).
# - B: l'ESEMPIO ESATTO della richiesta — comparso al giorno 300 con days_to_expire=182, scade al
#   giorno 300+182-365=117 dell'anno successivo.
# - C: attraversamento anno con un valore diverso (200 giorni, ExpiredObjectRules costruito al
#   volo, nessun secondo .tres necessario solo per un valore di test), per verificare che il
#   calcolo non sia specifico del singolo valore 182.
#
# Ogni caso stampa atteso (calcolato a mano nel commento) vs risultato reale, PASS/FAIL esplicito.

func _run() -> void:
	var dead_body_rules := load("res://gameplay/data/expired_objects/dead_body_rules.tres") as ExpiredObjectRules
	print("dead_body_rules.days_to_expire = %d (atteso 182)" % dead_body_rules.days_to_expire)

	var record_a := {"appeared_at_year": 0, "appeared_at_day": 0}
	# Scadenza assoluta = 0 + 182 = 182 -> anno 0, giorno 182 (nessun attraversamento).
	_check("A (giorno 181, stesso anno)", record_a, dead_body_rules, 0, 181, false)
	_check("A (giorno 182, appena scaduto)", record_a, dead_body_rules, 0, 182, true)

	var record_b := {"appeared_at_year": 0, "appeared_at_day": 300}
	# Scadenza assoluta = 300 + 182 = 482 = 1*365 + 117 -> anno 1, giorno 117 (l'esempio esatto
	# della richiesta: 300+182-365=117).
	_check("B (anno 0, giorno 364 — ancora nell'anno di comparsa)", record_b, dead_body_rules, 0, 364, false)
	_check("B (anno 1, giorno 116 — un giorno prima di scadere)", record_b, dead_body_rules, 1, 116, false)
	_check("B (anno 1, giorno 117 — atteso dalla richiesta)", record_b, dead_body_rules, 1, 117, true)
	_check("B (anno 2, giorno 0 — molto dopo)", record_b, dead_body_rules, 2, 0, true)

	var custom_rules := ExpiredObjectRules.new()
	custom_rules.days_to_expire = 200
	var record_c := {"appeared_at_year": 2, "appeared_at_day": 200}
	# Scadenza assoluta = (2*365+200) + 200 = 930 + 200 = 1130 = 3*365 + 35 -> anno 3, giorno 35.
	_check("C (anno 3, giorno 34 — un giorno prima di scadere)", record_c, custom_rules, 3, 34, false)
	_check("C (anno 3, giorno 35 — atteso dal calcolo a mano)", record_c, custom_rules, 3, 35, true)
	_check("C (anno 2, giorno 364 — ben prima)", record_c, custom_rules, 2, 364, false)


func _check(
	label: String, record: Dictionary, rules: ExpiredObjectRules, current_year: int, current_day: int,
	expected: bool
) -> void:
	var actual := ExpiredObjectCalculator.is_expired(record, rules, current_year, current_day)
	var status := "PASS" if actual == expected else "FAIL"
	print("[%s] %s -> is_expired=%s (atteso=%s)" % [status, label, actual, expected])
