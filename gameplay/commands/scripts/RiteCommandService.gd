class_name RiteCommandService
extends RefCounted

# Comando del rito ordinato (2026-10-24, refactoring GameScene 5B.5 — prima GameScene._assign_rite_task,
# _reject_rite_command, _building_has_active_rite). Senza stato: avvisi, icone e pannelli passano dagli effetti. In scena
# restano la sezione "Riti" del pannello, il mirino del celebrante e gli effetti visivi del rito.


# Costruisce e assegna la Task Rite (o avvia il rito sociale). Ricontrolla tutto (il mondo può essere cambiato col popup
# aperto): edificio ancora utilizzabile, nessun altro rito sull'edificio, rito ammesso e consentito al pipottino.
# `silent` (2026-10-14, lavoro "rite:" preso dalla coda): niente icona di comando né pannello individuo. I rifiuti per
# edificio occupato, celebrante non ammesso e idoneità avvisano anche se silenziosi, come prima (incoerenza annotata in
# docs/design/gamescene_refactoring.md).
static func assign_rite(ctx: GameContext, worker: HumanIndividual, building: Building, rite_id: String, silent: bool, effects: GameEffects) -> void:
	if worker == null or building == null:
		return
	var rules := RiteService.get_rules(rite_id)
	if rules == null or not RiteService.get_rites_for_building(building).has(rules):
		return
	if has_active_rite(ctx.individuals, building) or (building.requested_rite_id != "" and building.requested_rite_id != rite_id):
		reject(worker, building, GameContext.tr_text("rite_reject_building_busy"), effects)
		return
	var age_band := ctx.age_band_of(worker)
	if not RiteService.can_celebrate(rules, worker, age_band):
		reject(worker, building, GameContext.tr_text("rite_reject_none_available").format({"name": worker.name}), effects)
		return
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	var center := BuildingFootprint.center_micro(building)
	var job_keys: Array[String] = ["rite:%d" % building.id]
	# Rito sociale (2026-10-14, es. il banchetto): niente task Rite, lo avvia SocialRiteService (convocazione del villaggio).
	if rules is SocialRiteRules:
		var rejection_text := SocialRiteService.start(worker, building, rules as SocialRiteRules, ctx.individuals, ctx.game_data, ctx.world)
		if rejection_text != "":
			if not silent:
				reject(worker, building, rejection_text, effects)
			return
		building.requested_rite_id = rite_id
		CommandFeedback.forget_job_board_waits(ctx.game_data, job_keys, effects)
		if not silent:
			effects.command_icon_at_point(macro_coords, center, rules.command_icon_key)
			effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		return
	# Rito ordinato (2026-10-14): al completamento evade l'ordine dell'edificio (RiteAction.on_complete).
	var task := TaskBuilderService.build_rite_task(worker, building, rite_id)
	if task == null:
		return
	# Icona al centro dell'edificio; silenzioso = nessuna icona. L'idoneità avvisa anche se silenzioso.
	var request := AssignRequest.create(worker, task, "task_activity_rite").at_point(macro_coords, center, rules.command_icon_key)
	request.strict = true
	request.icon_when_silent = false
	if not AssignService.check(request, age_band, effects):
		return
	request.silent = silent
	if AssignService.commit(request, age_band, effects):
		# Ordine dell'edificio (2026-10-14): resta finché il rito non è celebrato; preso, esce dall'attesa della coda.
		building.requested_rite_id = rite_id
		CommandFeedback.forget_job_board_waits(ctx.game_data, job_keys, effects)
	if not silent:
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)


# Rifiuto di un comando di rito: X al centro dell'edificio e motivo.
static func reject(worker: HumanIndividual, building: Building, text: String, effects: GameEffects) -> void:
	effects.command_icon_at_point(Vector2i(building.macro_x, building.macro_y), BuildingFootprint.center_micro(building), "task_rejected")
	CommandFeedback.reject(worker, text, effects)


# true se un pipottino ha una Task con un RiteAction su `building`, in corso o in coda (non ancora conclusa).
static func has_active_rite(individuals: Array, building: Building) -> bool:
	return RiteService.get_active_rite_buildings(individuals).has(building.id)
