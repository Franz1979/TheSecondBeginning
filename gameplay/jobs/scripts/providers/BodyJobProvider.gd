class_name BodyJobProvider
extends RefCounted

# Fornitore "corpi" della lista dei lavori (2026-10-07; spostato da GameScene il 2026-10-17, refactoring GameScene blocco
# 2b): corpi da seppellire (body:<id>). La task è quella del clic destro sul corpo (BodyBurialService.build_bury_task);
# assegnazione, X e Rimetti in coda restano alla scena.

# Corpi prima degli edifici nelle righe del cassetto, i più vicini alla scadenza in cima (come in "In sospeso").
const SORT_OFFSET: float = 1000000.0


# Un lavoro per corpo non ancora sepolto e non scaduto (a terra, sulla lastra, o in spalla se qualcuno lo sta già
# portando). Riga: il nome del morto e, accanto più in piccolo, "restano N gg per la sepoltura"; tooltip: la voce di
# "In sospeso". Nascosto (fuori dalla coda, solo "In sospeso"): nessun cumulo sepolcrale finito con un posto libero
# (BodyBurialService.resolve_mound), lavoro impossibile.
static func collect(ctx: GameContext, provider: Dictionary, assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	var rules := ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY)
	for record in ctx.game_data.expired_objects:
		if record["object_type"] != ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY or BodyBurialService.is_expired(record):
			continue
		var body_id := int(record["individual_id"])
		var is_assigned: bool = assigned["bodies"].has(body_id)
		if ExpiredObjectCalculator.is_carried(record) and not is_assigned:
			continue
		var days := ExpiredObjectCalculator.get_days_remaining(record, rules, ctx.game_data.year, ctx.game_data.current_day) if rules != null else 0
		var body_name := BodyBurialService.get_body_name(record)
		var days_text := GameContext.tr_text("pending_body_days").format({"days": days})
		var text := GameContext.tr_text("pending_body").format({"name": body_name, "days": days})
		var macro: Vector2i = record["home_macro_coords"]
		var position := Vector2(record["position"])
		var microcell := Vector2i(floori(position.x), floori(position.y))
		jobs.append({
			"key": "body:%d" % body_id, "kind": "body", "name": body_name, "name_detail": days_text, "text": text, "log_name": body_name,
			# Icona della riga: il 💀 del bottone del riquadro "Famiglia" del pannello dell'abitante (2026-10-07).
			"icon": {"text": IconRegistry.get_command_icon("bury")}, "macro": macro, "microcell": microcell,
			"reach_target": {"macro_x": macro.x, "macro_y": macro.y, "micro_x": microcell.x, "micro_y": microcell.y},
			"entry_kind": "body", "id": body_id, "sort": float(days) - SORT_OFFSET,
			"assigned": is_assigned, "hidden": not is_assigned and BodyBurialService.resolve_mound(record, body_id, ctx.individuals) == null,
			"target": record, "provider": provider,
		})
	return jobs


# Motivo per cui `worker` non potrebbe ricevere la sepoltura (HumanIndividual.ASSIGN_OK se può): la stessa task del clic
# destro (BodyBurialService.build_bury_task), mai assegnata.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var record: Dictionary = job["target"]
	var body_id := int(job["id"])
	var mound := BodyBurialService.resolve_mound(record, body_id, ctx.individuals)
	if mound == null:
		return "nessun cumulo"
	var task := BodyBurialService.build_bury_task(worker, record, body_id, mound)
	if task == null:
		return "definizione mancante"
	return worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))


# Lavoratore: solo chi ha la task Seppellisci del corpo (i partecipanti al corteo no).
static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	var assignee := BodyBurialService.get_bury_assignee(int(job["id"]), ctx.individuals)
	if assignee != null:
		result.append(assignee)
	return result
