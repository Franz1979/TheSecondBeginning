class_name FishZoneService
extends RefCounted

# Pesca nelle zone di lavoro (2026-10-31, richiesta utente — pesca nelle aree di lavoro, passo 1): lavoro "fish" della
# zona (WorkAreaTypes.JOBS, sbloccato da work_areas_advanced come caccia, estrazione e taglio), zone valide, scelta della
# zona e del punto di pesca. Stesso schema di QuarryZoneService: il punto è una microcella di ruscello della zona, al
# posto della roccia; i punti prenotati da un pipottino (una FishAction in corso o in coda) sono ESCLUSI, non penalizzati.
# Un punto è buono se ha pesci adesso (StreamFishService.get_fish) e almeno una microcella di riva da cui pescare
# (bank_cells, la stessa regola di TaskBuilderService.build_fish_task) raggiungibile dal pipottino. I ruscelli esistono
# solo nelle macrocelle vive (LiveMacroCell.stream_positions): una zona in una macrocella non viva non ha punti.
# Stateless, funzioni statiche. La pesca vera passa dalle stesse funzioni del clic destro (FishCommandService).

const FISH_JOB := "fish"
# Zona della task (etichetta "Pesca (Zona 1)"), scritta nel context all'assegnazione.
const CONTEXT_WORK_AREA_ID := "fish_work_area_id"
# Stesso punteggio della cava (QuarryZoneService): punti disponibili / (distanza + offset) × fattore per ogni altro
# pipottino che pesca già nella zona.
const ZONE_DISTANCE_OFFSET: float = 10.0
const ZONE_CROWDING_FACTOR: float = 0.7
# Scelta del punto: distanza + penalità per ogni punto prenotato da altri a una microcella di distanza (affollamento).
const NEIGHBOR_RESERVED_PENALTY: float = 6.0

# Serie di pesca (2026-10-31, passi 2-3): "pesci da consegnare" del comando Pesca, uno di TARGET_OPTIONS come la carne
# della caccia (ricordato in UserOptions.fish_zone_target). Viaggia nel context della pesca (CONTEXT_SERIES):
#   {"work_area_id": int, "target": int, "delivered": int (pesci consegnati, contati allo scarico: add_delivered_fish),
#    "in_hand": int (pesci presi e non ancora consegnati, portati da un punto all'altro), "butcher_destination": String,
#    "stop_reason": String (solo se la serie si deve fermare dopo il viaggio in corso, motivo tradotto)}.
# Destinazione: stesse scelte della carne (ButcherDestinationService), ma valore suo (GameData.last_fish_destination).
# Pesca di fila (passo 3, richiesta utente): nella serie la FishAction non ha il tempo della sessione; pesca finché ha in
# mano i pesci che mancano, lo zaino è pieno, il punto si svuota (si passa a un altro punto della zona senza consegnare) o
# la lenza si rompe senza ricambio; poi un solo viaggio di consegna. Alla fine della Task (HumanIndividualActionService.
# _continue_fish_zone_series) WorkFollowUpService.continue_fish_series accoda la pesca successiva o chiude la serie.
const TARGET_OPTIONS: Array[int] = [5, 10, 15, 20]
const TARGET_DEFAULT: int = 10
const CONTEXT_SERIES := "fish_zone_series"
# Messaggio di serie interrotta (chiave tr() di HumanIndividualActionService.series_stopped_message).
const SERIES_STOPPED_KEY := "fish_series_stopped"


static func make_series(area_id: int, target: int, butcher_destination: String) -> Dictionary:
	return {
		# Qualunque obiettivo positivo (2026-10-31): l'ordine del cassetto ripreso dopo un'interruzione chiede quello che
		# resta (es. 6), non uno dei valori del popup.
		"work_area_id": area_id, "target": target if target > 0 else TARGET_DEFAULT, "delivered": 0,
		"in_hand": 0, "butcher_destination": butcher_destination,
	}


# Serie del context di una pesca ({} se non ne fa parte).
static func get_series(context: Dictionary) -> Dictionary:
	var series: Variant = context.get(CONTEXT_SERIES, {})
	return series if series is Dictionary else {}


# Pesci che mancano alla serie, tolti quelli già consegnati (mai sotto 0).
static func remaining(series: Dictionary) -> int:
	return maxi(int(series.get("target", 0)) - int(series.get("delivered", 0)), 0)


static func is_series_complete(series: Dictionary) -> bool:
	return remaining(series) <= 0


# Pesce consegnato da uno scarico della serie (UnloadAction, come HuntZoneService.add_delivered_meat).
static func add_delivered_fish(context: Dictionary, quantity: int) -> void:
	var series := get_series(context)
	if series.is_empty() or quantity <= 0:
		return
	series["delivered"] = int(series.get("delivered", 0)) + quantity
	context[CONTEXT_SERIES] = series


const _BANK_DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func is_fish_job_unlocked() -> bool:
	return WorkAreaTypes.is_job_unlocked(FISH_JOB)


# Zone con la pesca attiva (ordine di GameData.work_areas). Vuoto senza l'idea.
static func list_fish_work_areas(game_data: GameData) -> Array[WorkArea]:
	var areas: Array[WorkArea] = []
	if game_data == null or not is_fish_job_unlocked():
		return areas
	for area in game_data.work_areas:
		if area.enabled_jobs.has(FISH_JOB):
			areas.append(area)
	return areas


# true se esiste almeno una zona con la pesca attiva (stato del bottone: nessun giro sui ruscelli).
static func has_fish_work_area(game_data: GameData) -> bool:
	return not list_fish_work_areas(game_data).is_empty()


# true se la zona contiene almeno una microcella di ruscello (spunta "Pesca" del pannello della zona). Macrocella non
# viva = ruscelli sconosciuti: true, la spunta resta libera.
static func area_has_stream(area: WorkArea) -> bool:
	if area == null:
		return false
	var cell := PathfindingService.get_live_cell(area.macro_coords)
	if cell == null:
		return true
	for position in cell.stream_positions:
		if area.rect.has_point(position):
			return true
	return false


# Microcelle di riva da cui si pesca il punto `spot`: i 4 vicini dentro la macrocella, non ruscello, non bloccati.
# Usata anche da TaskBuilderService.build_fish_task per voltare il pescatore verso la riva.
static func bank_cells(cell: LiveMacroCell, spot: Vector2i) -> Array[Vector2i]:
	var banks: Array[Vector2i] = []
	if cell == null:
		return banks
	for direction in _BANK_DIRECTIONS:
		var bank: Vector2i = spot + direction
		if bank.x < 0 or bank.y < 0 or bank.x >= World.WIDTH or bank.y >= World.HEIGHT:
			continue
		if cell.stream_positions.has(bank) or PathfindingService.is_blocked(cell, bank):
			continue
		banks.append(bank)
	return banks


# Punti prenotati: chiave "macro_x|macro_y|x|y" di ogni FishAction in corso o in coda di qualunque pipottino.
static func collect_reserved_spots(individuals: Array) -> Dictionary:
	var reserved: Dictionary = {}
	for member in individuals:
		var tasks: Array = member.task_queue.duplicate()
		if member.current_task != null and not member.current_task.is_finished():
			tasks.append(member.current_task)
		for task in tasks:
			for step in task.steps:
				if step is FishAction:
					reserved[_spot_key((step as FishAction).macro_coords, (step as FishAction).fish_position)] = true
	return reserved


# Punti della zona pescabili da `individual`: microcelle di ruscello dentro la zona con pesci adesso, non prenotate e con
# una riva raggiungibile. Array[Vector2i] di microcelle locali alla macrocella della zona. `first_only`: si ferma al primo.
static func list_available_spots(
	area: WorkArea, individual: HumanIndividual, reserved: Dictionary, first_only: bool = false
) -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	if area == null:
		return spots
	var cell := PathfindingService.get_live_cell(area.macro_coords)
	var game_data: GameData = GameSettings.active_game_data
	if cell == null or game_data == null:
		return spots
	var day := game_data.get_absolute_day()
	for position in cell.stream_positions:
		var spot: Vector2i = position
		if not area.rect.has_point(spot):
			continue
		if reserved.has(_spot_key(area.macro_coords, spot)):
			continue
		if StreamFishService.get_fish(cell.macro_state, cell.stream_positions, area.macro_coords.x, area.macro_coords.y, spot, day) <= 0:
			continue
		if not _has_reachable_bank(cell, spot, individual, area.macro_coords):
			continue
		spots.append(spot)
		if first_only:
			return spots
	return spots


# Punto per `individual` nella zona: tra quelli disponibili, il più vicino con la penalità di affollamento; null se
# nessuno.
static func choose_spot(area: WorkArea, individual: HumanIndividual, reserved: Dictionary) -> Variant:
	return choose_spot_from(area, individual.home_macro_coords, individual.position, individual, reserved)


# Come choose_spot, ma la distanza si misura da `origin_pos` (locale a `origin_macro`) invece che dal pipottino
# (bersaglio scelto dall'ordine). `individual` solo per la raggiungibilità (null = nessun controllo).
static func choose_spot_from(
	area: WorkArea, origin_macro: Vector2i, origin_pos: Vector2, individual: HumanIndividual, reserved: Dictionary
) -> Variant:
	var best: Variant = null
	var best_score := INF
	var offset := Vector2(area.macro_coords - origin_macro) * World.WIDTH
	for spot in list_available_spots(area, individual, reserved):
		var score := origin_pos.distance_to(Vector2(spot) + Vector2(0.5, 0.5) + offset)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if (dx != 0 or dy != 0) and reserved.has(_spot_key(area.macro_coords, spot + Vector2i(dx, dy))):
					score += NEIGHBOR_RESERVED_PENALTY
		if score < best_score:
			best_score = score
			best = spot
	return best


# Scelta automatica della zona: valide le zone con la pesca attiva e almeno un punto disponibile per `individual`;
# punteggio come la cava (punti disponibili / (distanza dal centro + offset) × fattore per ogni altro pipottino che
# pesca già lì). null se nessuna.
static func choose_work_area(game_data: GameData, individual: HumanIndividual, reserved: Dictionary) -> WorkArea:
	if game_data == null or individual == null:
		return null
	return choose_work_area_from(game_data, individual.home_macro_coords, individual.position, individual, reserved)


# Come choose_work_area, ma la distanza si misura da `origin_pos` (locale a `origin_macro`). `individual` solo per
# raggiungibilità e affollamento (null = nessun controllo).
static func choose_work_area_from(
	game_data: GameData, origin_macro: Vector2i, origin_pos: Vector2, individual: HumanIndividual, reserved: Dictionary
) -> WorkArea:
	var best: WorkArea = null
	var best_score := -1.0
	for area in list_fish_work_areas(game_data):
		var available := list_available_spots(area, individual, reserved).size()
		if available <= 0:
			continue
		var center := Vector2(area.rect.position) + Vector2(area.rect.size) * 0.5 + Vector2(area.macro_coords - origin_macro) * World.WIDTH
		var score := float(available) / (origin_pos.distance_to(center) + ZONE_DISTANCE_OFFSET)
		for other in GameSettings.active_human_individuals:
			if other != individual and is_fishing_in(other, area.id):
				score *= ZONE_CROWDING_FACTOR
		if score > best_score:
			best_score = score
			best = area
	return best


# true se l'individuo ha una pesca in corso nella zona `area_id`.
static func is_fishing_in(individual: HumanIndividual, area_id: int) -> bool:
	if individual == null or individual.current_task == null or individual.current_task.is_finished():
		return false
	return int(individual.current_task.context.get(CONTEXT_WORK_AREA_ID, -1)) == area_id


# Chiave di prenotazione di un punto, come in collect_reserved_spots.
static func spot_reservation_key(macro_coords: Vector2i, spot: Vector2i) -> String:
	return _spot_key(macro_coords, spot)


# Almeno una riva del punto raggiungibile da `individual` (stessa regola di HaulZoneService.is_cell_reachable: fuori
# dalla macrocella home vale sempre; null = nessun controllo).
static func _has_reachable_bank(cell: LiveMacroCell, spot: Vector2i, individual: HumanIndividual, macro_coords: Vector2i) -> bool:
	for bank in bank_cells(cell, spot):
		if individual == null or HaulZoneService.is_cell_reachable(individual, macro_coords, bank):
			return true
	return false


static func _spot_key(macro_coords: Vector2i, spot: Vector2i) -> String:
	return "%d|%d|%d|%d" % [macro_coords.x, macro_coords.y, spot.x, spot.y]
