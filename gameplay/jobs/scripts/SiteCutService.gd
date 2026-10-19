class_name SiteCutService
extends RefCounted

# Cantiere nel bosco (2026-10-18, richiesta utente): con un'ascia nel villaggio un edificio si piazza anche su microcelle
# con alberi o cespugli vivi; il taglio diventa parte del cantiere. Alla pulizia (ClearAction) il costruttore con l'ascia
# taglia lui (il "taglia tutto" di una cella, serie di cella di CutZoneService, davanti alla costruzione sospesa); senza
# ascia la costruzione si rimanda (HumanIndividualActionService, tipo "site_cut") e nella coda dei lavori c'è un lavoro di
# taglio per ogni cella con piante (SiteCutJobProvider), per chiunque abbia l'ascia. Stateless, funzioni statiche.

const TOOL_CATEGORIES: Array = [TaskTypes.ToolCategory.CHOPPING]
# Età per il taglio (ToolFetchService.age_ok): come gli ordini Taglia del cassetto.
const AGE_KIND := DrawerOrderService.TYPE_CUT


# true se nel villaggio c'è un'ascia: addosso (o in arrivo) a qualcuno in età, o in un deposito.
static func village_has_axe(ctx: GameContext) -> bool:
	if ctx == null:
		return false
	if ToolFetchService.has_equipped_member(ctx, TOOL_CATEGORIES, AGE_KIND):
		return true
	return not ToolFetchService.find_storage_tool(ctx.world, null, TaskTypes.ToolCategory.CHOPPING).is_empty()


# Microcelle del cantiere (ingombro) con alberi o cespugli vivi.
static func cells_with_plants(world: World, site: Building) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if world == null or site == null:
		return cells
	var macro_state := world.get_cell_state_at(site.macro_x, site.macro_y)
	for cell in BuildingFootprint.cells_of(site):
		if BuildingSiteClearingService.has_woody_vegetation(macro_state, cell):
			cells.append(cell)
	return cells


# Chi sta tagliando (o consegnando la legna di) la microcella `cell` di `macro` con un "taglia tutto" di cella.
static func cell_claimers(individuals: Array[HumanIndividual], macro: Vector2i, cell: Vector2i) -> Array[HumanIndividual]:
	var claimers: Array[HumanIndividual] = []
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			var series := CutZoneService.get_series(task.context)
			if series.is_empty():
				series = CutZoneService.get_delivery_series(task)
			if CutZoneService.is_cell_series(series) and CutZoneService.get_cell_series_macro_coords(series) == macro \
					and CutZoneService.get_cell_series_lot(series) == cell:
				claimers.append(member)
				break
	return claimers


# Pianta da tagliare per `worker` sulla microcella `cell` del cantiere ({} se nessuna viva, libera e raggiungibile).
static func pick_plant(ctx: GameContext, worker: HumanIndividual, site: Building, cell: Vector2i) -> Dictionary:
	return CutZoneService.choose_plant_in_lot(
		ctx.live_cells, Vector2i(site.macro_x, site.macro_y), cell, worker, CutZoneService.collect_reserved_plants(ctx.individuals)
	)


# Microcella da tagliare per il costruttore: la prima con piante che nessuno sta già tagliando e con una pianta per lui.
# null se nessuna.
static func pick_cell(ctx: GameContext, worker: HumanIndividual, site: Building) -> Variant:
	var macro := Vector2i(site.macro_x, site.macro_y)
	for cell in cells_with_plants(ctx.world, site):
		if not cell_claimers(ctx.individuals, macro, cell).is_empty():
			continue
		if not pick_plant(ctx, worker, site, cell).is_empty():
			return cell
	return null


# Serie "taglia tutto" sulla microcella `cell` del cantiere (fino a cella libera).
static func make_series(ctx: GameContext, site: Building, cell: Vector2i) -> Dictionary:
	var macro := Vector2i(site.macro_x, site.macro_y)
	var plants := CutZoneService.list_available_plants_in_lot(ctx.live_cells, macro, cell, null, {})
	return CutZoneService.make_cell_series(macro, cell, plants.size())


# Cantiere in attesa del taglio la cui microcella `cell` di `macro` fa parte dell'ingombro; null se nessuno.
static func find_awaiting_site_at(world: World, macro: Vector2i, cell: Vector2i) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.awaiting_site_cut and not building.is_demolished and BuildingFootprint.covers(building, macro, cell):
			return building
	return null


# Fine del taglio di un cantiere in attesa: se nessuna sua cella ha più piante, torna un cantiere normale. true se è
# appena cambiato.
static func try_finish(world: World, site: Building) -> bool:
	if site == null or not site.awaiting_site_cut:
		return false
	if not cells_with_plants(world, site).is_empty():
		return false
	site.awaiting_site_cut = false
	return true
