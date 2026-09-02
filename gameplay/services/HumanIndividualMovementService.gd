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

	if step >= distance:
		individual.position = individual.target_position
		individual.stop()
	else:
		individual.position += to_target.normalized() * step
