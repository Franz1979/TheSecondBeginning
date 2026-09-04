class_name HumanIndividualMovementService
extends RefCounted

# Servizio single-responsibility (stesso pattern di FirstStartMacroCellSelectionService/
# CellRichnessCalculator): muove un HumanIndividual verso il suo target_position in linea retta a
# move_speed (microcelle/secondo). Girato ogni frame da GameScene._process, indipendentemente
# dal clock giorno/anno (confermato con l'utente: il movimento del player resta attivo anche a
# clock in pausa).

func advance_movement(individual: HumanIndividual, delta: float) -> void:
	if not individual.is_moving:
		return

	var to_target := individual.target_position - individual.position
	var distance := to_target.length()
	var step := individual.move_speed * delta

	# Aggiorna facing_direction PRIMA di muovere position (2026-09-04, richiesta utente: persistere
	# l'orientamento) — soglia minima invece di un confronto diretto con zero: a un passo
	# dall'arrivo to_target può essere quasi nullo ma non esattamente, normalized() su un vettore
	# ~zero produce un risultato instabile/rumoroso (stessa soglia già in uso prima in
	# HumanIndividualView, spostata qui insieme al campo). Se distance è già sotto soglia,
	# facing_direction resta quella di prima — mai azzerata.
	if distance > 0.01:
		individual.facing_direction = to_target.normalized()

	if step >= distance:
		individual.position = individual.target_position
		individual.stop()
	else:
		individual.position += to_target.normalized() * step
