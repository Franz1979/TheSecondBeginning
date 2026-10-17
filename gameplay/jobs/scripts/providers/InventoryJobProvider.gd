class_name InventoryJobProvider
extends RefCounted

# Fornitore "inventario" della lista dei lavori (2026-10-11; spostato da GameScene il 2026-10-17, refactoring GameScene
# blocco 4): un lavoro alla volta ("inventory:0") quando l'inventario del magazzino è scaduto (WarehouseManagerService), al
# deposito. Chi lo prende va al deposito più vicino (InventoryAction). Assegnazione e Rimetti in coda restano alla scena.


# `now`: momento di gioco in giorni (scadenza dell'inventario).
static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary, now: float) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if not WarehouseManagerService.is_enabled(ctx):
		return jobs
	var workers := WarehouseManagerService.inventory_workers(ctx.individuals)
	if workers.is_empty() and not WarehouseManagerService.is_inventory_due(ctx.game_data, now):
		return jobs
	var depot := WarehouseManagerService.first_storage_building(ctx.world)
	jobs.append({
		"key": "inventory:0", "kind": "inventory", "name": GameContext.tr_text("task_inventory_name"),
		"text": GameContext.tr_text("task_assignment_inventory_tooltip"),
		"log_name": "inventario del magazzino", "icon": {"building_type": depot.building_type_name},
		"macro": Vector2i(depot.macro_x, depot.macro_y), "microcell": Vector2i(depot.micro_x, depot.micro_y),
		"reach_target": depot, "entry_kind": "building", "id": depot.id, "sort": -1.0,
		"assigned": not workers.is_empty(), "hidden": false, "blocked_reason": "",
		"target": depot, "provider": provider,
	})
	return jobs


static func rejection(ctx: GameContext, worker: HumanIndividual, _job: Dictionary) -> String:
	var age_band := ctx.age_band_of(worker)
	if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD:
		return HumanIndividual.ASSIGN_REJECT_TOO_YOUNG
	var depot := WarehouseManagerService.nearest_storage_building(ctx.world, worker)
	if depot == null:
		return "nessun deposito raggiungibile"
	var task := TaskBuilderService.build_inventory_task(worker, depot)
	if task == null:
		return "definizione mancante"
	return worker.get_assign_rejection_reason(task, age_band)


static func workers(ctx: GameContext, _job: Dictionary) -> Array[HumanIndividual]:
	return WarehouseManagerService.inventory_workers(ctx.individuals)
