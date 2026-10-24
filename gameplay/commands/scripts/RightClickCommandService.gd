class_name RightClickCommandService
extends RefCounted

# Scelta dei comandi del clic destro con un pipottino selezionato (2026-10-24, refactoring GameScene 5B.7 — prima la
# catena di _try_assign_*_command_on_right_click in GameScene._unhandled_input, con hit-test e condizioni in ogni
# funzione). La scena raccoglie i bersagli una volta (RightClickTargets), qui si decide quali comandi valgono e in che
# ordine; la scena li prova in quell'ordine e il primo che consuma il clic vince (un comando può ancora rinunciare, per
# esempio il trasporto da un edificio vuoto). Nessun comando = movimento verso il punto. Senza stato.

enum Command { BURY, HUNT, BUTCHER, CUT, QUARRY, PICKUP, BUILD, TRANSPORT }


# Comandi possibili per `targets`, in ordine di priorità:
#   - trasporto a metà (`transport_pending`, sorgente già scelta): solo TRANSPORT, il clic vale per la destinazione;
#   - sulla sagoma di un corpo vince sempre la sepoltura; poi un animale (bersaglio esplicito, si muove), una carcassa;
#   - taglio e cava solo con l'attrezzo (CHOPPING / DIGGING, in cintura o nello zaino), con la pianta o la roccia
#     visibile in dettaglio e mai su un edificio con un lavoro da riprendere (è per Costruisci/Demolisci/Ripara);
#   - raccolta, poi costruzione (o riparazione) e trasporto sull'edificio.
static func candidates(ctx: GameContext, worker: HumanIndividual, targets: RightClickTargets, transport_pending: bool) -> Array[Command]:
	var commands: Array[Command] = []
	if transport_pending:
		if targets.building != null:
			commands.append(Command.TRANSPORT)
		return commands
	if targets.body_id != -1:
		commands.append(Command.BURY)
	if targets.prey != null:
		commands.append(Command.HUNT)
	if targets.carcass_pile != null:
		commands.append(Command.BUTCHER)
	var on_resumable_building := has_resumable_work(ctx, targets.building)
	var day := ctx.game_data.get_absolute_day()
	if not on_resumable_building and not targets.plant.is_empty() \
			and ToolGateService.has_tool_for(worker, TaskTypes.ToolCategory.CHOPPING):
		var plant_key: Vector3i = targets.plant["individual_key"]
		if FogOfWarVerificationService.is_detail_visible(ctx.live_cells, targets.plant["macro_coords"], Vector2i(plant_key.x, plant_key.y), day):
			commands.append(Command.CUT)
	if not on_resumable_building and not targets.rock.is_empty() \
			and ToolGateService.has_tool_for(worker, TaskTypes.ToolCategory.DIGGING):
		if FogOfWarVerificationService.is_detail_visible(ctx.live_cells, targets.rock["macro_coords"], targets.rock["position"], day):
			commands.append(Command.QUARRY)
	if not targets.pickup_candidates.is_empty():
		commands.append(Command.PICKUP)
	if targets.building != null:
		commands.append(Command.BUILD)
		commands.append(Command.TRANSPORT)
	return commands


# true se `building` ha un lavoro da riprendere col clic destro: cantiere o "da demolire" (has_resumable_task), o una
# riparazione richiesta che si può assegnare adesso.
static func has_resumable_work(ctx: GameContext, building: Building) -> bool:
	if building == null:
		return false
	return building.has_resumable_task() or has_assignable_repair(ctx, building)


# Riparazione richiesta (2026-10-10) che si può assegnare adesso col clic destro sull'edificio.
static func has_assignable_repair(ctx: GameContext, building: Building) -> bool:
	return building.repair_requested and BuildingCommandService.can_assign_repair(ctx.individuals, building)
