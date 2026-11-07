class_name WaterJarCommandService
extends RefCounted

# Comando "Riempi giare" (2026-11-06, richiesta utente — Vasellame, giare: passo 1): clic destro sulla Tettoia dell'acqua
# con un pipottino selezionato, numero di giare da riempire dal dialogo (GameScene._right_click_fill_jar), poi qui. Un solo
# compito che fa un viaggio alla volta (WaterJarService). Rifiutato con X e motivo se la tettoia è piena d'acqua, se per un
# posto libero nessun magazzino ha una giara, se nessuna riva è raggiungibile o se non c'è un travois da trainare (una
# giara piena non si porta a mano). Il travois, se non lo traina già, lo va a prendere prima
# (ToolFetchService.start_towed_fetch: il riempimento aspetta in coda). Senza stato; avvisi e icone dagli effetti.


static func assign_fill(ctx: GameContext, worker: HumanIndividual, shelter: Building, count: int, effects: GameEffects) -> void:
	if worker == null or shelter == null:
		return
	var macro := Vector2i(shelter.macro_x, shelter.macro_y)
	var microcell := Vector2i(shelter.micro_x, shelter.micro_y)
	var fillable := WaterJarService.fillable_count(shelter)
	if fillable <= 0:
		_reject(worker, macro, microcell, GameContext.tr_text("fill_jar_reject_shelter_full").format({
			"building": shelter.get_display_name(),
		}), effects)
		return
	var pick := WaterJarService.pick_source(ctx.world, worker, shelter)
	if pick.has("error"):
		_reject(worker, macro, microcell, GameContext.tr_text(String(pick["error"])).format({
			"name": worker.name, "building": shelter.get_display_name(),
		}), effects)
		return
	if not ToolFetchService.can_get_towed(ctx, worker):
		_reject(worker, macro, microcell, GameContext.tr_text("fill_jar_reject_no_travois").format({"name": worker.name}), effects)
		return
	var task := WaterJarService.build_fill_task(worker, pick["source"], shelter, clampi(count, 1, fillable))
	if task == null:
		_reject(worker, macro, microcell, GameContext.tr_text("fill_jar_reject_no_water").format({"name": worker.name}), effects)
		return
	var request := AssignRequest.create(worker, task, "task_activity_fill_jar").at_microcell(macro, microcell, "transport")
	var age_band := ctx.age_band_of(worker)
	if not AssignService.check(request, age_band, effects):
		return
	if not AssignService.commit(request, age_band, effects):
		return
	# Travois (come i trasporti del cassetto): lo prende prima, il riempimento riparte a presa finita.
	if not worker.is_towing():
		ZoneOrderCommandService.start_towed_fetch(ctx, worker, "riempimento giare", effects)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[FILL JAR] #%d %s: %d giare per la tettoia #%d, primo viaggio da %s #%d." % [
			worker.id, worker.name, clampi(count, 1, fillable), shelter.id, pick["source"].building_type_name, pick["source"].id
		])


static func _reject(worker: HumanIndividual, macro: Vector2i, microcell: Vector2i, text: String, effects: GameEffects) -> void:
	effects.command_icon_at_microcell(macro, microcell, "task_rejected")
	CommandFeedback.reject(worker, text, effects)
