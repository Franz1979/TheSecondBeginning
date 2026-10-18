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
