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
	# move_speed_multiplier (2026-09-13, bugfix RunAction) — 1.0 per default/WalkAction, raddoppiato
	# da RunAction.activate() finché quello step resta attivo (vedi HumanIndividual.gd per il campo
	# e il perché): questo service resta comunque agnostico su QUALE Action sia attiva, legge solo i
	# due campi che qualunque Action di movimento scrive, stesso principio già in uso per is_moving/
	# target_position.
	var step := individual.move_speed * individual.move_speed_multiplier * delta

	# Aggiorna facing_direction PRIMA di muovere position (2026-09-04, richiesta utente: persistere
	# l'orientamento) — soglia minima invece di un confronto diretto con zero: a un passo
	# dall'arrivo to_target può essere quasi nullo ma non esattamente, normalized() su un vettore
	# ~zero produce un risultato instabile/rumoroso (stessa soglia già in uso prima in
	# HumanIndividualView, spostata qui insieme al campo). Se distance è già sotto soglia,
	# facing_direction resta quella di prima — mai azzerata.
	if distance > 0.01:
		individual.facing_direction = to_target.normalized()

	if step >= distance:
		# NON più individual.stop() qui (2026-09-07, richiesta utente — bugfix necessario per Task a
		# più step): stop() ora azzera current_task (vedi HumanIndividual.gd), e advance_movement
		# gira SEMPRE prima di HumanIndividualActionService.apply_action nello stesso frame (vedi
		# GameScene._process) — chiamarlo qui distruggerebbe la Task PRIMA che apply_action possa
		# vedere che il WalkAction attivo è completo e far avanzare allo step successivo, impedendo
		# per costruzione qualunque sequenza multi-step di funzionare mai. La decisione "fermarsi per
		# davvero" spetta ora SOLO a apply_action, quando la Task risulta conclusa dopo l'ultimo step
		# (vedi lì): fino ad allora is_moving resta true anche se position == target_position, senza
		# effetti collaterali (i frame successivi ricalcolano to_target/distance a zero, un no-op,
		# finché apply_action non decide se proseguire con lo step successivo o fermare per intero).
		individual.position = individual.target_position
	else:
		individual.position += to_target.normalized() * step
