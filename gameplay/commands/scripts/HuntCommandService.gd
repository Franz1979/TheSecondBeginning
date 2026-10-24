class_name HuntCommandService
extends RefCounted

# Comandi di caccia e macellazione (2026-10-24, refactoring GameScene 5B.6 — prima i controlli di GameScene._order_hunt,
# la zona automatica di _on_hunt_order_confirmed, _assign_work_area_hunt e il corpo di
# _try_assign_hunt_command_on_right_click e _try_assign_butcher_command_on_right_click). Senza stato: avvisi, icone,
# collegamenti dei segnali e pannelli passano dagli effetti. In scena restano il clic destro (quale animale o mucchio),
# il dialog della caccia e la scelta a mano della zona.

const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/hunt.tres"


# Cacciatori idonei tra `selected` per la caccia nelle zone: età e stamina (Task di prova), coltello in cintura o nello
# zaino con posto in cintura (HuntZoneService.get_hunt_rejection), con il motivo per chi non va. Nessuna zona con la
# caccia attiva: avviso a ciascuno e nessun cacciatore.
static func eligible_zone_hunters(ctx: GameContext, selected: Array[HumanIndividual], effects: GameEffects) -> Array[HumanIndividual]:
	var hunters: Array[HumanIndividual] = []
	for member in selected:
		var probe := TaskBuilderService.build_hunt_zone_task(-1)
		if probe == null:
			HuntZoneService.log_event(member, "Task di prova NON creata (%s non caricabile) — controllo di età/stamina saltato." % HuntZoneService.TASK_DEFINITION_PATH)
		else:
			# Idoneità con il motivo, senza icona (AssignService, 5B.2).
			if not AssignService.check(AssignRequest.create(member, probe, "task_activity_hunt"), ctx.age_band_of(member), effects):
				HuntZoneService.log_event(member, "rifiutato da età/stamina: %s." % member.get_assign_rejection_reason(probe, ctx.age_band_of(member)))
				continue
		var knife_rejection := HuntZoneService.get_hunt_rejection(member)
		if knife_rejection != "":
			HuntZoneService.log_event(member, "rifiutato: %s" % knife_rejection)
			CommandFeedback.reject(member, knife_rejection, effects)
			continue
		HuntZoneService.log_event(member, "età, stamina e coltello in cintura: ok.")
		hunters.append(member)
	if hunters.is_empty():
		HuntZoneService.log_event(null, "nessun cacciatore idoneo: comando chiuso.")
		return hunters
	var areas := HuntZoneService.list_hunt_work_areas(ctx.game_data)
	HuntZoneService.log_event(null, "zone con la caccia attiva: %s (idea Aree di lavoro %s)." % [
		str(areas.map(func(area: WorkArea) -> String: return "%s #%d" % [area.name, area.id])),
		"completata" if HuntZoneService.is_hunt_job_unlocked() else "NON completata"
	])
	if areas.is_empty():
		for hunter in hunters:
			CommandFeedback.reject(hunter, GameContext.tr_text("work_area_hunt_no_zone").format({"name": hunter.name}), effects)
		hunters.clear()
	return hunters


# Zona automatica dopo il dialog della caccia: ognuno nella propria zona migliore (HuntZoneService.choose_work_area), con
# una serie fino a `meat_target` di carne; avviso per chi non ne ha una.
static func assign_auto_zone_hunt(ctx: GameContext, hunters: Array[HumanIndividual], meat_target: int, butcher_destination: String, effects: GameEffects) -> void:
	for hunter in hunters:
		var area := HuntZoneService.choose_work_area(ctx.game_data, hunter, ctx.live_cells)
		if area == null:
			HuntZoneService.log_event(hunter, "nessuna zona scelta in automatico.")
			CommandFeedback.reject(hunter, GameContext.tr_text("work_area_hunt_no_zone").format({"name": hunter.name}), effects)
			continue
		HuntZoneService.log_event(hunter, "zona scelta in automatico: %s #%d." % [area.name, area.id])
		assign_work_area_hunt(
			ctx, hunter, area, HuntZoneService.make_meat_series(area.id, meat_target, butcher_destination, true), false, false, effects
		)


# Caccia nella zona `area` con la serie `series`. `silent` (ordini di caccia del cassetto): nessun messaggio né icona.
# `tools_from_storage` (ordini di zona della coda): chi parte va prima a prendere in deposito il coltello o l'arma che
# non ha (ZoneOrderCommandService.start_tool_fetch, subito dopo): niente controllo del coltello qui.
static func assign_work_area_hunt(
	ctx: GameContext, hunter: HumanIndividual, area: WorkArea, series: Dictionary, silent: bool, tools_from_storage: bool,
	effects: GameEffects
) -> void:
	if hunter == null or area == null or not ctx.individuals.has(hunter):
		return
	var task := TaskBuilderService.build_hunt_zone_task(area.id, series)
	if task == null:
		HuntZoneService.log_event(hunter, "Task NON creata per la zona %s #%d." % [area.name, area.id])
		return
	HuntZoneService.log_event(hunter, "Task '%s' creata per la zona %s #%d: %d step." % [task.task_name, area.name, area.id, task.steps.size()])
	# Icona al centro della zona; silenziosa = nessuna icona, nemmeno di riuscita.
	var request := AssignRequest.create(hunter, task, "task_activity_hunt", silent).at_microcell(
		area.macro_coords, area.rect.position + area.rect.size / 2, "hunt"
	)
	request.icon_when_silent = false
	var age_band := ctx.age_band_of(hunter)
	if not AssignService.check(request, age_band, effects):
		return
	# Coltello (2026-10-09, regola generale degli attrezzi): dallo zaino in cintura prima di partire; cintura piena = no.
	if not tools_from_storage and not WorkFollowUpService.prepare_hunt_knife(ctx, hunter, silent, effects):
		if not silent:
			AssignService.reject_icon(request, effects)
		return
	var assigned := AssignService.commit(request, age_band, effects)
	HuntZoneService.log_event(hunter, "assegnazione della caccia nella zona %s #%d: %s (Task corrente: '%s')." % [
		area.name, area.id, "riuscita" if assigned else "FALLITA",
		hunter.current_task.task_name if hunter.current_task != null else "nessuna"
	])


# Caccia diretta all'animale `prey` (clic destro): Hunt Task [ApproachPrey → Hunt]. Gate degli attrezzi (categoria
# HUNTING) SENZA attesa: nessuna arma né in cintura né nello zaino = rifiutata (la preda si muove); arma nello zaino ma
# cintura/zaino pieni = rifiutata. L'idoneità viene PRIMA del gate, che sposta davvero l'arma dallo zaino alla cintura.
static func assign_prey_hunt(ctx: GameContext, worker: HumanIndividual, prey: AnimalVisualGroup, species: String, effects: GameEffects) -> void:
	var definition := TaskDefinitionCache.get_definition(TASK_DEFINITION_PATH)
	if definition == null:
		return
	var task := TaskFactory.build_task(definition, {
		"hunt_prey_id": prey.id,
		"hunt_prey_species": species,
		"hunt_prey_macro_coords": prey.macro_coords,
	})
	# Specie per il pannello individuo (Task.get_activity_description): chiave NON consumata da TaskFactory (a differenza
	# di "hunt_prey_species"), resta in task.context e nel salvataggio.
	task.context["hunt_activity_species"] = species
	# Destinazione della macellazione (2026-10-03): la caccia diretta non ha un dialog, usa l'ultima scelta (o il
	# focolare/magazzino se non è più disponibile), come la proposta del dialog della caccia nelle zone.
	task.context[ButcherDestinationService.CONTEXT_KEY] = ButcherDestinationService.resolve_default(
		ctx.game_data.last_butcher_destination, ctx.world, ctx.folk
	)
	# Icona nel punto della preda; riuscita = caccia in corso o in coda.
	var request := AssignRequest.create(worker, task, "task_activity_hunt").at_point(prey.macro_coords, prey.position, "hunt")
	request.strict = true
	var age_band := ctx.age_band_of(worker)
	if not AssignService.check(request, age_band, effects):
		HuntService.log_event(worker, "caccia RIFIUTATA (preda %s #%d): individuo non idoneo (%s)." % [
			species, prey.id, worker.get_assign_rejection_reason(task, age_band)
		])
		return
	var tool_gate := ToolGateService.check_and_prepare(worker, task, ctx.game_data)
	if tool_gate["result"] == ToolGateService.Result.MISSING_TOOLS:
		# Senza arma la caccia viene RIFIUTATA, non messa in attesa come la produzione (2026-09-26): quando l'arma
		# arrivasse l'animale sarebbe ormai lontano. Esempi di armi che coprono HUNTING, omessi se nessuna è nota.
		var weapon_names: PackedStringArray = []
		for weapon_name in ToolGateService.get_tools_covering(TaskTypes.ToolCategory.HUNTING):
			weapon_names.append(IconRegistry.get_resource_display_name(weapon_name))
		var examples_text := "" if weapon_names.is_empty() else " " + GameContext.tr_text("tool_gate_hunt_weapon_examples").format({"tools": ", ".join(weapon_names)})
		var text := GameContext.tr_text("tool_gate_hunt_no_weapon").format({"name": worker.name, "examples": examples_text})
		# Armi a munizioni (2026-10-04): l'arma c'è ma manca la sua munizione in cintura — testo proprio.
		var weapon_without_ammo := HuntService.find_weapon_missing_ammo(worker)
		if weapon_without_ammo != "":
			text = GameContext.tr_text("tool_gate_hunt_no_ammo").format({"name": worker.name, "weapon": IconRegistry.get_resource_display_name(weapon_without_ammo)})
		worker.tool_gate_warning = text
		effects.notify(NotificationTypes.NotificationPopupType.TOOL_REQUIRED, text)
		AssignService.reject_icon(request, effects)
		HuntService.log_event(worker, "caccia RIFIUTATA (preda %s #%d): nessuna arma da caccia né in cintura né nello zaino." % [species, prey.id])
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
		return
	elif tool_gate["result"] != ToolGateService.Result.OK:
		CommandFeedback.tool_gate_failure(worker, tool_gate, effects)
		AssignService.reject_icon(request, effects)
		HuntService.log_event(worker, "caccia RIFIUTATA (preda %s #%d): %s non entra in cintura (%s)." % [
			species, prey.id, String(tool_gate["tool_name"]), String(ToolGateService.Result.keys()[tool_gate["result"]])
		])
		return
	worker.tool_gate_warning = ""
	if not tool_gate["equipped"].is_empty():
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	# Arma della caccia (2026-09-27): scelta ora, dopo il gate, contro questa preda, e salvata nel context della Task — la
	# stessa per tutta la caccia (HuntService.resolve_weapon; se non è più in cintura si sceglie di nuovo con la stessa regola).
	var chosen_weapon := HuntService.choose_weapon(worker, TaskTypes.ToolCategory.HUNTING, species, int(prey.age_band))
	if chosen_weapon != "":
		task.context[HuntService.CONTEXT_HUNT_WEAPON] = chosen_weapon
	var assigned := AssignService.commit(request, age_band, effects)
	if HuntService.is_logging():
		if not assigned:
			HuntService.log_event(worker, "caccia RIFIUTATA (preda %s #%d): assegnazione non accettata (la task in corso ha lo zaino occupato)." % [species, prey.id])
		else:
			var weapon_text := HuntService.describe_weapon(worker, String(task.context.get(HuntService.CONTEXT_HUNT_WEAPON, "")))
			if not tool_gate["equipped"].is_empty():
				weapon_text += " — spostata dallo zaino alla cintura"
			HuntService.log_event(worker, "caccia assegnata%s: preda %s #%d in %s, arma %s." % [
				"" if worker.current_task == task else " (in coda)", species, prey.id, str(prey.macro_coords), weapon_text
			])


# Macellazione della carcassa più vecchia del mucchio `pile` (clic destro): Walk, ButcherAction, PickUp di tutto dal
# mucchio. Controlli come la caccia (idoneità, attrezzi BUTCHERING); icona "butcher" sul mucchio. false se la Task non
# nasce (macrocella non viva): il clic prosegue agli altri comandi.
static func assign_butcher(ctx: GameContext, worker: HumanIndividual, pile: GroundPile, effects: GameEffects) -> bool:
	var cell: LiveMacroCell = ctx.live_cells.get(pile.macro_coords)
	if cell == null or cell.macro_state == null:
		return false
	var task := TaskBuilderService.build_butcher_task(worker, pile, int(pile.carcasses[0]["id"]), cell.macro_state)
	if task == null:
		return false
	effects.wire_task(GameEffects.WireKind.BUTCHER, task, worker)
	# Idoneità, attrezzi, assegnazione (in corso o in coda) e icona sul mucchio.
	var request := AssignRequest.create(worker, task, "task_activity_butcher").at_microcell(pile.macro_coords, pile.microcell, "butcher")
	request.strict = true
	var age_band := ctx.age_band_of(worker)
	if not AssignService.check(request, age_band, effects):
		return true
	var tool_gate := ToolGateService.check_and_prepare(worker, task, ctx.game_data)
	if tool_gate["result"] != ToolGateService.Result.OK:
		CommandFeedback.tool_gate_failure(worker, tool_gate, effects)
		AssignService.reject_icon(request, effects)
		return true
	worker.tool_gate_warning = ""
	if not tool_gate["equipped"].is_empty():
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)
	AssignService.commit(request, age_band, effects)
	return true
