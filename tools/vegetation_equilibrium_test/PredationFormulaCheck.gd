extends Node

# Verifica numerica mirata (non un tool permanente): replica la formula di attempt_count/
# success_probability per branchi di taglia crescente, usando i valori reali di wolf.tres, per
# confermare che dopo la modifica: (a) attempt_count resta cappato a 4 anche per branchi grandi,
# (b) il rapporto efficacia/max nella probabilita' di successo supera 1.0 (prima del clamp finale)
# per branchi sopra la vecchia soglia di 8. Non chiama PredationService direttamente (richiederebbe
# un mondo/territorio/prede completi) — verifica la sola formula con gli stessi valori di
# PredatorRules che PredationService legge.

func _ready() -> void:
	var rules := AnimalCalculator.get_animal_rules("wolf") as PredatorRules
	print("=== Verifica formula caccia (wolf: max_pack_hunting_efficiency=%.1f, attempts_per_efficiency=%.1f) ===" % [
		rules.max_pack_hunting_efficiency, rules.attempts_per_efficiency
	])
	print("%-20s %-12s %-18s %-14s" % ["adulti nel branco", "efficacia_grezza", "attempt_count", "rapporto_successo"])

	for adult_count in [4, 8, 10, 12, 15, 20]:
		# hunting_efficiency_by_age default = [0.2, 1.0, 0.8], qui tutti adulti (peso 1.0) per
		# semplicita' — stessa formula di _compute_raw_pack_efficiency.
		var raw_efficiency: float = float(adult_count) * float(rules.hunting_efficiency_by_age[GameTypes.AgeBand.ADULT])

		var attempts_efficiency: float = min(raw_efficiency, rules.max_pack_hunting_efficiency)
		var attempt_count: int = int(round(attempts_efficiency / rules.attempts_per_efficiency))

		var success_ratio: float = raw_efficiency / rules.max_pack_hunting_efficiency

		print("%-20d %-12.1f %-18d %-14.2f" % [adult_count, raw_efficiency, attempt_count, success_ratio])

	print("")
	print("Atteso: attempt_count si ferma a 4 dal branco di 8 in poi; rapporto_successo continua a")
	print("crescere oltre 1.0 per branchi piu' grandi (prima del clamp finale in PredationService).")

	get_tree().quit()
