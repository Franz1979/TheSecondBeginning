class_name AssignRequest
extends RefCounted

# Un'assegnazione di comando da far passare per AssignService (2026-10-24, refactoring GameScene 5B.2): chi, quale Task,
# per quale attività (messaggi di rifiuto) e dove mostrare l'icona del comando. Si costruisce con create() e, se il
# comando ha un'icona, at_microcell()/at_point().

var worker: HumanIndividual
var task: Task
var activity_key: String = ""
# Presa dalla lista dei lavori (2026-10-09): nessun avviso, popup né X.
var silent: bool = false
var has_icon: bool = false
var icon_macro: Vector2i = Vector2i.ZERO
# Punto dell'icona in coordinate di microcella continue (centro di una microcella = microcella + 0.5).
var icon_point: Vector2 = Vector2.ZERO
var success_icon_key: String = ""
# Icona di riuscita anche quando `silent` (false per caccia di zona e riti: nessuna icona se silenziosi).
var icon_when_silent: bool = true
# Riuscita = Task in corso o in coda (Building/riti/caccia/sepoltura); altrimenti vale l'esito di assign_task, che
# risulta vero anche per una Task non sospendibile scartata dietro il carico di un'altra (comportamento di sempre di
# trasporto, raccolta e zone).
var strict: bool = false


static func create(worker: HumanIndividual, task: Task, activity_key: String, silent: bool = false) -> AssignRequest:
	var request := AssignRequest.new()
	request.worker = worker
	request.task = task
	request.activity_key = activity_key
	request.silent = silent
	return request


# Icona al centro della microcella `microcell` della macrocella `macro`.
func at_microcell(macro: Vector2i, microcell: Vector2i, key: String) -> AssignRequest:
	return at_point(macro, Vector2(microcell) + Vector2(0.5, 0.5), key)


# Icona nel punto `point` (coordinate di microcella continue) della macrocella `macro`.
func at_point(macro: Vector2i, point: Vector2, key: String) -> AssignRequest:
	has_icon = true
	icon_macro = macro
	icon_point = point
	success_icon_key = key
	return self
