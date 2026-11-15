class_name ClearOrderService
extends RefCounted

# Sgombero di una microcella (2026-11-15, richiesta utente — "Rimuovi tutto" dal pannello della microcella, doppio clic):
# un ordine al villaggio, non a un pipottino. La microcella segnata (GameData.clear_orders) fa nascere nella lista dei
# lavori un lavoro ogni CHUNK piante (ClearOrderJobProvider), fino a MAX_WORKERS persone insieme: ciascuno fa una serie
# "taglia tutto qui" da CHUNK piante (CutZoneService.make_cell_series), la stessa del cantiere nel bosco, e porta la legna
# al deposito come sempre. Più persone sulla stessa microcella tagliano piante diverse: la prenotazione è sulla pianta.
# Il segno sparisce da solo quando la microcella non ha più alberi né cespugli vivi.
# Roccia (KIND_ROCK, passo 2): un lavoro ogni CHUNK estrazioni, ciascuno una serie da CHUNK estrazioni sulla stessa roccia
# (QuarryZoneService.make_rock_series con SERIES_FLAG): più persone sulla stessa roccia sommano il lavoro (l'avanzamento
# è della roccia, MacroCellState.cut_work_progress), la prenotazione della roccia non le ferma. Piccone, come la cava.
# Stateless, funzioni statiche.

const KIND_PLANTS := "plants"
const KIND_ROCK := "rock"
# Segno sulla serie di estrazione di uno sgombero: la roccia presa da altri non ferma né rifiuta (ExtractionCommandService,
# WorkFollowUpService.continue_quarry_rock_series).
const SERIES_FLAG := "clear_order"
# Piante per lavoro: una serie da tanto, poi il pipottino torna alla lista.
const CHUNK: int = 5
# Persone insieme sulla stessa microcella, al massimo.
const MAX_WORKERS: int = 4
# Come il taglio del cantiere: ascia, stesse età.
const TOOL_CATEGORIES: Array = [TaskTypes.ToolCategory.CHOPPING]
const AGE_KIND := DrawerOrderService.TYPE_CUT
const ROCK_TOOL_CATEGORIES: Array = [TaskTypes.ToolCategory.DIGGING]
const ROCK_AGE_KIND := DrawerOrderService.TYPE_QUARRY


static func order_key(macro_coords: Vector2i, lot: Vector2i) -> String:
	return "%d,%d,%d,%d" % [macro_coords.x, macro_coords.y, lot.x, lot.y]


static func get_order(game_data: GameData, macro_coords: Vector2i, lot: Vector2i) -> Dictionary:
	if game_data == null:
		return {}
	return game_data.clear_orders.get(order_key(macro_coords, lot), {})


static func is_marked(game_data: GameData, macro_coords: Vector2i, lot: Vector2i) -> bool:
	return not get_order(game_data, macro_coords, lot).is_empty()


static func mark(game_data: GameData, macro_coords: Vector2i, lot: Vector2i, kind: String) -> void:
	if game_data == null:
		return
	game_data.clear_orders[order_key(macro_coords, lot)] = {
		"macro_x": macro_coords.x, "macro_y": macro_coords.y, "x": lot.x, "y": lot.y, "kind": kind,
	}
	game_data.clear_orders_revision += 1


static func unmark(game_data: GameData, macro_coords: Vector2i, lot: Vector2i) -> void:
	if game_data == null or not game_data.clear_orders.erase(order_key(macro_coords, lot)):
		return
	game_data.clear_orders_revision += 1


static func order_macro(order: Dictionary) -> Vector2i:
	return Vector2i(int(order.get("macro_x", 0)), int(order.get("macro_y", 0)))


static func order_lot(order: Dictionary) -> Vector2i:
	return Vector2i(int(order.get("x", 0)), int(order.get("y", 0)))


# Microcelle segnate della macrocella `macro_coords`.
static func lots_in_cell(game_data: GameData, macro_coords: Vector2i) -> Array[Vector2i]:
	var lots: Array[Vector2i] = []
	if game_data == null:
		return lots
	for order in game_data.clear_orders.values():
		if order_macro(order) == macro_coords:
			lots.append(order_lot(order))
	return lots


# Alberi e cespugli vivi sulla microcella (anche quelli che qualcuno sta già tagliando). 0 se la cella non è viva.
static func count_plants(live_cells: Dictionary, macro_coords: Vector2i, lot: Vector2i) -> int:
	if not live_cells.has(macro_coords):
		return 0
	return CutZoneService.list_available_plants_in_lot(live_cells, macro_coords, lot, null, {}).size()


# true se sulla microcella c'è una roccia in piedi (cella viva).
static func is_rock_lot(live_cells: Dictionary, macro_coords: Vector2i, lot: Vector2i) -> bool:
	var cell: LiveMacroCell = live_cells.get(macro_coords)
	return cell != null and RockStoneService.is_standing_rock(cell.macro_state, lot)


# Estrazioni che restano per esaurire la roccia della microcella. 0 se la cella non è viva o la roccia è finita.
static func count_extractions(live_cells: Dictionary, macro_coords: Vector2i, lot: Vector2i) -> int:
	var cell: LiveMacroCell = live_cells.get(macro_coords)
	if cell == null or cell.macro_state == null:
		return 0
	return QuarryZoneService.extractions_to_deplete(cell.macro_state, lot)


# Lavori per la microcella: uno ogni CHUNK piante o estrazioni, da 1 a MAX_WORKERS.
static func jobs_for(amount: int) -> int:
	return clampi(ceili(float(amount) / float(CHUNK)), 1, MAX_WORKERS)


# Chi ha un'estrazione sulla roccia (in corso o in coda), nell'ordine di `individuals`.
static func rock_claimers(individuals: Array, macro_coords: Vector2i, rock: Vector2i) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in individuals:
		var tasks: Array = member.task_queue.duplicate()
		if member.current_task != null and not member.current_task.is_finished():
			tasks.append(member.current_task)
		var holds := false
		for task in tasks:
			for step in task.steps:
				if step is QuarryAction and (step as QuarryAction).is_same_rock(macro_coords, rock):
					holds = true
					break
			if holds:
				break
		if holds:
			result.append(member as HumanIndividual)
	return result


# Pianta da tagliare per `worker` sulla microcella ({} se nessuna viva, libera e raggiungibile).
static func pick_plant(ctx: GameContext, worker: HumanIndividual, macro_coords: Vector2i, lot: Vector2i) -> Dictionary:
	return CutZoneService.choose_plant_in_lot(ctx.live_cells, macro_coords, lot, worker, CutZoneService.collect_reserved_plants(ctx.individuals))


# Serie di un lavoro: "taglia tutto qui" fermo a CHUNK piante (finisce prima se la cella si svuota).
static func make_series(macro_coords: Vector2i, lot: Vector2i) -> Dictionary:
	return CutZoneService.make_cell_series(macro_coords, lot, CHUNK)


# Serie di un lavoro sulla roccia: CHUNK estrazioni sulla roccia della microcella (finisce prima se si esaurisce).
static func make_rock_series(macro_coords: Vector2i, lot: Vector2i) -> Dictionary:
	var series := QuarryZoneService.make_rock_series(macro_coords, lot, CHUNK)
	series[SERIES_FLAG] = true
	return series


static func is_clear_series(series: Dictionary) -> bool:
	return bool(series.get(SERIES_FLAG, false))
