class_name RiteJobProvider
extends RefCounted

# Fornitore "riti" della lista dei lavori (2026-10-14; spostato da GameScene il 2026-10-17, refactoring GameScene blocco
# 2b): edifici con un rito ordinato dal pannello (Building.requested_rite_id, "rite:<id>"). La task è la Rite esistente
# (TaskBuilderService.build_rite_task), un celebrante per edificio; il banchetto (SocialRiteRules) lo avvia
# SocialRiteService. Lo prende il primo libero idoneo (età, skill minima: RiteService.can_celebrate). Assegnazione, X e
# Rimetti in coda restano alla scena.


static func collect(ctx: JobBoardContext, provider: Dictionary, assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for building in ctx.world.buildings:
		if building.requested_rite_id == "":
			continue
		var rules := RiteService.get_rules(building.requested_rite_id)
		if rules == null or not RiteService.get_rites_for_building(building).has(rules):
			continue
		var building_name := JobBoardContext.tr_text(building.rules.building_name)
		var text := JobBoardContext.tr_text("pending_rite").format({"rite": JobBoardContext.tr_text(rules.display_name), "building": building_name})
		jobs.append({
			"key": "rite:%d" % building.id, "kind": "rite", "name": text, "text": text, "log_name": building_name,
			"icon": {"text": IconRegistry.get_command_icon(rules.command_icon_key)}, "map_icon_key": rules.command_icon_key,
			"macro": Vector2i(building.macro_x, building.macro_y), "microcell": Vector2i(building.micro_x, building.micro_y),
			"reach_target": building, "entry_kind": "building", "id": building.id, "sort": float(building.id),
			# Banchetto in corso (2026-10-14): preso anche se l'organizzatore se n'è andato.
			"assigned": assigned["rite"].has(building.id) or not SocialRiteService.find_rite(ctx.game_data, building.id).is_empty(),
			"hidden": false, "target": building, "rite_id": rules.id, "provider": provider,
		})
	return jobs


# Motivo per cui `worker` non potrebbe celebrare il rito (HumanIndividual.ASSIGN_OK se può): età e skill del rito, poi la
# task di prova come le altre (il banchetto ha le sue condizioni e nessuna task di prova).
static func rejection(ctx: JobBoardContext, worker: HumanIndividual, job: Dictionary) -> String:
	var building: Building = job["target"]
	var rules := RiteService.get_rules(String(job["rite_id"]))
	var age_band := ctx.age_band_of(worker)
	if rules == null or not RiteService.can_celebrate(rules, worker, age_band):
		return HumanIndividual.ASSIGN_REJECT_AGE_NOT_ALLOWED
	if rules is SocialRiteRules:
		var social_rejection := SocialRiteService.get_start_rejection(building, rules as SocialRiteRules, ctx.individuals, ctx.game_data)
		return social_rejection if social_rejection != "" else HumanIndividual.ASSIGN_OK
	var definition := load(TaskBuilderService.RITE_TASK_DEFINITION_PATH) as TaskDefinition
	if definition == null:
		return "definizione mancante"
	var probe := TaskFactory.build_task(definition, {
		"target_position": Vector2(building.micro_x, building.micro_y), "rite_target_building": building, "rite_id": rules.id,
	})
	return worker.get_assign_rejection_reason(probe, age_band)


static func workers(ctx: JobBoardContext, job: Dictionary) -> Array[HumanIndividual]:
	return RiteService.get_ordered_rite_workers(job["target"], ctx.individuals)
