class_name AssignService
extends RefCounted

# Parte comune delle assegnazioni dei comandi (2026-10-24, refactoring GameScene 5B.2 — prima ripetuta in ogni
# GameScene._assign_*): idoneità con motivo e X, assegnazione, motivo se non riesce, icona del comando. Tra check() e
# commit() il chiamante fa i suoi controlli (attrezzi, coltello, ordini); chi mette la Task in coda da sé chiama
# finish() con l'esito. Senza stato; avvisi e icone passano dagli effetti.

enum Result { ASSIGNED, INELIGIBLE, FAILED }


# Idoneità (HumanIndividual.get_assign_rejection_reason): se rifiutata e non silenziosa, motivo e X.
static func check(request: AssignRequest, age_band: HumanTypes.AgeBand, effects: GameEffects) -> bool:
	var reason := request.worker.get_assign_rejection_reason(request.task, age_band)
	if reason == HumanIndividual.ASSIGN_OK:
		return true
	if not request.silent:
		CommandFeedback.assign_rejection(request.worker, reason, request.activity_key, effects)
		reject_icon(request, effects)
	return false


# Assegnazione (assign_task) ed esito con avvisi e icona (finish).
static func commit(request: AssignRequest, age_band: HumanTypes.AgeBand, effects: GameEffects) -> bool:
	var returned := request.worker.assign_task(request.task, age_band)
	return finish(request, returned, age_band, effects)


# Esito di una Task già passata ad assign_task o messa in coda dal chiamante (`returned`): con `strict` conta che sia
# in corso o in coda. Non riuscita e non silenziosa: motivo e X; riuscita: icona del comando (se silenziosa solo con
# icon_when_silent).
static func finish(request: AssignRequest, returned: bool, age_band: HumanTypes.AgeBand, effects: GameEffects) -> bool:
	var assigned := is_placed(request.worker, request.task) if request.strict else returned
	if not assigned:
		if not request.silent:
			CommandFeedback.failed_assignment(request.worker, request.task, request.activity_key, age_band, effects)
			reject_icon(request, effects)
	elif request.has_icon and (not request.silent or request.icon_when_silent):
		effects.command_icon_at_point(request.icon_macro, request.icon_point, request.success_icon_key)
	return assigned


# check + commit.
static func assign(request: AssignRequest, age_band: HumanTypes.AgeBand, effects: GameEffects) -> Result:
	if not check(request, age_band, effects):
		return Result.INELIGIBLE
	return Result.ASSIGNED if commit(request, age_band, effects) else Result.FAILED


# X rossa nel punto dell'icona del comando (anche per i rifiuti decisi dal chiamante: attrezzi, coda piena...).
static func reject_icon(request: AssignRequest, effects: GameEffects) -> void:
	if request.has_icon:
		effects.command_icon_at_point(request.icon_macro, request.icon_point, "task_rejected")


static func is_placed(worker: HumanIndividual, task: Task) -> bool:
	return worker.current_task == task or worker.task_queue.has(task)
