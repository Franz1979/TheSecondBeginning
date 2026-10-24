class_name CommandFeedback
extends RefCounted

# Avvisi all'individuo e al giocatore quando un lavoro non si può fare (2026-10-18, refactoring GameScene blocco 5d — primo
# pezzo del 5B.0; prima GameScene._report_command_rejection / _report_tool_gate_failure). La scritta resta sull'individuo
# (tool_gate_warning, mostrata nel suo pannello) e il popup e il refresh del pannello passano dagli effetti, che la scena
# applica (i popup solo se l'opzione utente li mostra). Senza stato.


# Rifiuto con un testo già tradotto: avviso sull'individuo, popup TASK_REJECTED, pannello dell'individuo selezionato.
static func reject(worker: HumanIndividual, text: String, effects: GameEffects) -> void:
	if worker != null:
		worker.tool_gate_warning = text
	effects.notify(NotificationTypes.NotificationPopupType.TASK_REJECTED, text)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Attrezzo mancante o non indossabile (esito di ToolGateService.try_satisfy / check_and_prepare): testo per il tipo di
# esito, avviso sull'individuo, popup TOOL_REQUIRED solo se c'è un testo, pannello dell'individuo selezionato.
static func tool_gate_failure(worker: HumanIndividual, tool_gate: Dictionary, effects: GameEffects) -> void:
	var text := ""
	match tool_gate["result"]:
		ToolGateService.Result.MISSING_TOOLS:
			text = GameContext.tr_text("tool_gate_missing_tools").format({
				"name": worker.name, "tools": ToolFetchService.describe_missing_categories(tool_gate["missing_categories"]),
			})
		ToolGateService.Result.BELT_FULL:
			text = GameContext.tr_text("tool_gate_belt_full").format({
				"name": worker.name, "tool": IconRegistry.get_resource_display_name(tool_gate["tool_name"]),
			})
		ToolGateService.Result.CANNOT_EQUIP:
			text = GameContext.tr_text("tool_gate_cannot_equip").format({
				"name": worker.name, "tool": IconRegistry.get_resource_display_name(tool_gate["tool_name"]),
			})
	worker.tool_gate_warning = text
	if text != "":
		effects.notify(NotificationTypes.NotificationPopupType.TOOL_REQUIRED, text)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Rifiuto di idoneità (esito di HumanIndividual.get_assign_rejection_reason) per l'attività `activity_key` (2026-10-24,
# refactoring GameScene 5B.0 — prima GameScene._report_assign_rejection): testo per il motivo, poi reject.
static func assign_rejection(worker: HumanIndividual, reason: String, activity_key: String, effects: GameEffects) -> void:
	var reason_key := "task_reject_generic"
	match reason:
		HumanIndividual.ASSIGN_REJECT_TOO_YOUNG:
			reason_key = "task_reject_too_young"
		HumanIndividual.ASSIGN_REJECT_AGE_NOT_ALLOWED:
			reason_key = "task_reject_age_not_allowed"
		HumanIndividual.ASSIGN_REJECT_LOW_STAMINA:
			reason_key = "task_reject_low_stamina"
		HumanIndividual.ASSIGN_REJECT_SICK:
			reason_key = "task_reject_sick"
	reject(worker, GameContext.tr_text(reason_key).format({
		"name": worker.name, "activity": GameContext.tr_text(activity_key),
	}), effects)


# Motivo del rifiuto di un'assegnazione GIÀ tentata e fallita (assign_task ha restituito false) (2026-10-24, 5B.0 — prima
# GameScene._report_failed_assignment): il guard di idoneità è puro, quindi rileggerlo ora dà lo stesso esito; se passa,
# il rifiuto è venuto da assign_task stessa (Task non sospendibile scartata) -> messaggio generico.
static func failed_assignment(worker: HumanIndividual, task: Task, activity_key: String, age_band: HumanTypes.AgeBand, effects: GameEffects) -> void:
	assign_rejection(worker, worker.get_assign_rejection_reason(task, age_band), activity_key, effects)


# Lavori della bacheca non più in attesa (2026-10-24, 5B.0 — prima solo GameScene._forget_job_board_wait): l'attesa si
# cancella in GameData, la scena toglie le icone lampeggianti (effetto job_board_waits_forgotten).
static func forget_job_board_waits(game_data: GameData, job_keys: Array[String], effects: GameEffects) -> void:
	if game_data != null:
		JobBoardService.forget_waits(game_data, job_keys)
	effects.job_board_waits_forgotten(job_keys)
