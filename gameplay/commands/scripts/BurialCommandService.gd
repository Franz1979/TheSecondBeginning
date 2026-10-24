class_name BurialCommandService
extends RefCounted

# Comando Seppellisci (2026-10-24, refactoring GameScene 5B.6 — prima GameScene._assign_bury_task e
# _spawn_bury_command_icon). Senza stato: avvisi, icone, collegamenti dei segnali e pannelli passano dagli effetti. In
# scena resta il clic destro sulla sagoma del corpo.


# Assegna a `worker` la task Seppellisci del corpo `body_id`, con destinazione il cumulo utilizzabile più vicino al corpo
# (che da qui ne occupa un posto). Rifiuti con l'icona di comando rifiutato sul corpo e una frase: corpo già assegnato a
# un altro, nessun cumulo con posti liberi, età del pipottino. Lo stesso pipottino che ha già la sepoltura di questo
# corpo: nessuna nuova task (l'icona della sepoltura sì, anche silenziosa, come prima).
# `silent` (2026-10-07, lista dei lavori): nessuna icona di rifiuto né messaggio — la lista ha già controllato prima.
static func assign_bury(ctx: GameContext, worker: HumanIndividual, body_id: int, silent: bool, effects: GameEffects) -> void:
	var record := BodyBurialService.find_body_record(body_id)
	if record.is_empty() or ExpiredObjectCalculator.is_carried(record) or BodyBurialService.is_expired(record):
		return
	var body_name := BodyBurialService.get_body_name(record)
	var assignee := BodyBurialService.get_bury_assignee(body_id, ctx.individuals)
	if assignee == worker:
		_body_icon(record, "bury", effects)
		return
	if assignee != null:
		if not silent:
			_body_icon(record, "task_rejected", effects)
			CommandFeedback.reject(worker, GameContext.tr_text("bury_reject_already_assigned").format({"body": body_name, "assignee": assignee.name}), effects)
		return
	var mound := BodyBurialService.resolve_mound(record, body_id, ctx.individuals)
	if mound == null:
		if not silent:
			_body_icon(record, "task_rejected", effects)
			CommandFeedback.reject(worker, GameContext.tr_text("bury_reject_no_mound").format({"name": worker.name, "body": body_name}), effects)
		return
	var task := BodyBurialService.build_bury_task(worker, record, body_id, mound)
	if task == null:
		return
	# Icona nel punto del corpo, anche silenziosa se riuscita.
	var request := AssignRequest.create(worker, task, "task_activity_bury", silent).at_point(
		Vector2i(record["home_macro_coords"]), Vector2(record["position"]), "bury"
	)
	request.strict = true
	if AssignService.assign(request, ctx.age_band_of(worker), effects) != AssignService.Result.ASSIGNED:
		return
	# Lavoro assegnato: esce dalla lista; se ci tornerà, l'attesa per l'assegnazione a mano ripartirà da capo.
	var job_keys: Array[String] = ["body:%d" % body_id]
	CommandFeedback.forget_job_board_waits(ctx.game_data, job_keys, effects)
	worker.tool_gate_warning = ""
	effects.wire_task(GameEffects.WireKind.STEP_SIGNALS, task, worker)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	effects.refresh_panel(GameEffects.PanelKind.DEAD_BODY)


# Icona di comando sul corpo, nel punto esatto in cui è disegnato. Comando accettato: "bury" (il teschio).
static func _body_icon(record: Dictionary, command_icon_key: String, effects: GameEffects) -> void:
	effects.command_icon_at_point(Vector2i(record["home_macro_coords"]), Vector2(record["position"]), command_icon_key)
