class_name ThirstService
extends RefCounted

# Sete (2026-10-30, richiesta utente). current_thirst è l'acqua nel corpo: cala in modo continuo con il tempo di gioco,
# di HumanIndividual.daily_water_consumption al giorno (ricalcolato una volta al giorno da HumanVitalsIndividualService).
# Si beve in tre modi, tutti sull'elenco delle rive della cella viva (LiveMacroCell.water_access):
#   1. sorso al passaggio: chi entra in una microcella accanto all'acqua (o nel ruscello) torna pieno all'istante, a
#      qualsiasi livello, con l'icona "drink", senza fermarsi (try_sip, da GameSimulation.tick_frame);
#   2. drink.tres (priorità -1): da liberi sotto SIP_THRESHOLD, cammina alla riva più vicina e beve (DrinkAction);
#   3. emergency_drink.tres (priorità 15): sotto EMERGENCY_THRESHOLD interrompe il lavoro (handle_interrupt).
# Fonti: ruscello, fiume, e il bordo della cella verso un lago. Il mare no (salato).
# Fascia (2026-10-30, richiesta utente): entro WATER_BAND_RADIUS microcelle dall'acqua non si perde acqua (chi lavora
# vicino al ruscello beve quando vuole); ricaricarsi resta solo alla riva.
# Peso: ogni controllo esce al primo confronto finché l'acqua è sopra soglia; la ricerca della riva gira solo quando si
# assegna un compito, e dopo un fallimento si riprova solo quando l'acqua è calata di altre RETRY_DROP_DAYS di consumo
# (HumanIndividual.thirst_retry_below), non a ogni frame. Stateless.
# Otre (2026-10-30, richiesta utente): attrezzo in cintura con SecondaryResourceRules.water_capacity (categoria WATERSKIN);
# l'acqua sta in HumanIndividual.waterskin_water. Alla riva si riempie insieme al corpo (un uso dell'attrezzo per ogni
# riempimento); lontano dall'acqua, sotto SIP_THRESHOLD, si beve dall'otre sul posto, senza fermarsi, prima di cercare una
# riva. A corpo e otre vuoti, avviso giallo una volta per episodio (come la riserva corporea per la fame).
# Effetti (2026-10-30): salute in calo ogni giorno sotto EMERGENCY_THRESHOLD, di più a zero
# (HumanVitalsInteractionService); dopo DEHYDRATION_DAYS giorni a zero si muore subito (apply_drain → GameSimulation).

# Interruttore unico: spento = la sete non cala e nessuno beve, come prima.
const THIRST_ENABLED := true

const SIP_THRESHOLD: float = 0.60
const EMERGENCY_THRESHOLD: float = 0.25
# Calo dopo cui si riprova a cercare una riva, in giorni di consumo (2 ore).
const RETRY_DROP_DAYS: float = 2.0 / 24.0
# Distanza massima dall'acqua (in microcelle, anche in diagonale) entro cui non si perde acqua.
const WATER_BAND_RADIUS: int = 3
# Salute persa al giorno (su 5000 di un adulto): sotto EMERGENCY_THRESHOLD come un'infezione, a zero più del doppio.
const LOW_WATER_DAILY_HEALTH_LOSS: float = 150.0
const NO_WATER_DAILY_HEALTH_LOSS: float = 400.0
# Giorni di gioco a zero (contati fotogramma per fotogramma) dopo i quali si muore.
const DEHYDRATION_DAYS: float = 3.0

const DRINK_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/drink.tres"
const EMERGENCY_DRINK_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/emergency_drink.tres"
const DRINK_TASK_NAME := "task_drink_name"
const EMERGENCY_DRINK_TASK_NAME := "task_emergency_drink_name"
const DRINK_ICON_KEY := "drink"

const _NEIGHBORS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


# Calo di un fotogramma: `game_delta` è la frazione di giorno trascorsa (0 in pausa), quindi in un giorno di gioco la
# somma dei pezzi dà esattamente il consumo giornaliero. Chiamato da GameSimulation.tick_frame per ogni individuo, nel
# giro che c'è già. Sotto SIP_THRESHOLD con acqua nell'otre beve dall'otre (la cintura si guarda solo in quel caso); a
# zero, l'avviso e il tempo di disidratazione. true = DEHYDRATION_DAYS raggiunti: chi chiama lo fa morire.
static func apply_drain(individual: HumanIndividual, game_delta: float, effects: GameEffects) -> bool:
	if not THIRST_ENABLED or game_delta <= 0.0 or individual.daily_water_consumption <= 0.0 or individual.thirst_in_water_band:
		return false
	individual.current_thirst = maxf(individual.current_thirst - individual.daily_water_consumption * game_delta, 0.0)
	if individual.waterskin_water > 0.0 and _ratio(individual) < SIP_THRESHOLD:
		_drink_from_waterskin(individual, effects)
	if individual.current_thirst > 0.0:
		individual.dehydration_elapsed = 0.0
		return false
	if not individual.thirst_zero_alerted:
		individual.thirst_zero_alerted = true
		if effects != null:
			effects.notify(NotificationTypes.NotificationPopupType.THIRST_ZERO,
				TranslationServer.translate("notification_thirst_zero").format({"name": individual.name}))
	individual.dehydration_elapsed += game_delta
	return individual.dehydration_elapsed >= DEHYDRATION_DAYS


# Giorni che restano prima di morire di sete, -1 se non è a zero (barra rossa di HumanIndividualInfoPanel).
static func dehydration_days_left(individual: HumanIndividual) -> float:
	if not THIRST_ENABLED or individual.daily_water_consumption <= 0.0 or individual.current_thirst > 0.0:
		return -1.0
	return maxf(DEHYDRATION_DAYS - individual.dehydration_elapsed, 0.0)


# Beve dall'otre quanto serve a tornare pieno (o fino a vuotarlo). Otre non più in cintura: acqua azzerata.
static func _drink_from_waterskin(individual: HumanIndividual, effects: GameEffects) -> void:
	if waterskin_slot(individual) == -1:
		individual.waterskin_water = 0.0
		return
	var amount := minf(individual.max_thirst - individual.current_thirst, individual.waterskin_water)
	individual.current_thirst += amount
	individual.waterskin_water -= amount
	individual.thirst_retry_below = INF
	if effects != null:
		effects.individual_icon(individual, DRINK_ICON_KEY)
	if DebugLogging.ENABLED and DebugLogging.SHOW_THIRST_LOGS:
		print("[THIRST] #%d %s: beve %.1f dall'otre (resta %.1f)." % [individual.id, individual.name, amount, individual.waterskin_water])


# Primo slot della cintura con un otre, -1 se nessuno.
static func waterskin_slot(individual: HumanIndividual) -> int:
	for slot_index in range(individual.equipped_tools.size()):
		var tool_name: String = individual.equipped_tools[slot_index]
		if tool_name == "":
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
		if rules != null and rules.water_capacity > 0.0:
			return slot_index
	return -1


# Capacità dell'otre in cintura, 0 senza otre.
static func waterskin_capacity(individual: HumanIndividual) -> float:
	var slot_index := waterskin_slot(individual)
	if slot_index == -1:
		return 0.0
	return CaloricCalculator.get_caloric_source_rules(individual.equipped_tools[slot_index]).water_capacity


# Rive della cella viva, calcolate una volta all'attivazione (l'acqua non cambia in partita): microcelle del ruscello
# (calpestabili), microcelle accanto al ruscello o alla fascia del fiume, e la fila di bordo verso un lago vicino. Poi la
# fascia senza calo: le rive allargate di WATER_BAND_RADIUS - 1 (la riva è già a 1 dall'acqua).
# Le microcelle bloccate (rocce, edifici) si scartano al momento della ricerca, non qui.
static func build_water_access(cell: LiveMacroCell, macro_world: World) -> void:
	var access: Dictionary = {}
	if THIRST_ENABLED and cell.macro_cell != null and cell.macro_cell.terrain_base != GameTypes.TerrainBase.WATER:
		for position in cell.stream_positions:
			access[position] = true
			_add_neighbors(access, position, {})
		var river: Dictionary = {}
		for position in cell.river_positions:
			river[position] = true
		for position in river:
			_add_neighbors(access, position, river)
		if macro_world != null:
			for direction in _NEIGHBORS:
				var neighbor := macro_world.get_cell_at(cell.macro_x + direction.x, cell.macro_y + direction.y)
				if neighbor == null or neighbor.terrain_base != GameTypes.TerrainBase.WATER or neighbor.water_type != GameTypes.WaterType.LAKE:
					continue
				for i in range(World.WIDTH):
					var position := Vector2i(0, i)
					if direction.y == -1:
						position = Vector2i(i, 0)
					elif direction.x == 1:
						position = Vector2i(World.WIDTH - 1, i)
					elif direction.y == 1:
						position = Vector2i(i, World.HEIGHT - 1)
					access[position] = true
	cell.water_access = access
	cell.drink_spots = access.keys()
	var band: Dictionary = {}
	var reach := WATER_BAND_RADIUS - 1
	for position in access:
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var near: Vector2i = position + Vector2i(dx, dy)
				if near.x >= 0 and near.y >= 0 and near.x < World.WIDTH and near.y < World.HEIGHT:
					band[near] = true
	cell.water_band = band


static func _add_neighbors(access: Dictionary, position: Vector2i, excluded: Dictionary) -> void:
	for direction in _NEIGHBORS:
		var neighbor: Vector2i = position + direction
		if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= World.WIDTH or neighbor.y >= World.HEIGHT:
			continue
		if not excluded.has(neighbor):
			access[neighbor] = true


static func _ratio(individual: HumanIndividual) -> float:
	return individual.current_thirst / individual.max_thirst if individual.max_thirst > 0.0 else 1.0


static func needs_drink(individual: HumanIndividual) -> bool:
	return THIRST_ENABLED and individual.daily_water_consumption > 0.0 and _ratio(individual) < SIP_THRESHOLD


static func needs_emergency_drink(individual: HumanIndividual) -> bool:
	return THIRST_ENABLED and individual.daily_water_consumption > 0.0 and _ratio(individual) < EMERGENCY_THRESHOLD


# Salute persa oggi per la sete (HumanVitalsInteractionService.apply_daily_interaction): 0 sopra EMERGENCY_THRESHOLD.
static func daily_health_loss(individual: HumanIndividual) -> float:
	if not THIRST_ENABLED or individual.daily_water_consumption <= 0.0:
		return 0.0
	if individual.current_thirst <= 0.0:
		return NO_WATER_DAILY_HEALTH_LOSS
	return LOW_WATER_DAILY_HEALTH_LOSS if _ratio(individual) < EMERGENCY_THRESHOLD else 0.0


# Bevuta alla riva (DrinkAction o sorso al passaggio): corpo al massimo, otre pieno (un uso dell'attrezzo se mancava
# acqua; se si rompe l'acqua va persa), ricerca della riva di nuovo libera, giorni a zero e avviso azzerati.
static func refill(individual: HumanIndividual) -> void:
	individual.current_thirst = individual.max_thirst
	individual.thirst_retry_below = INF
	individual.dehydration_elapsed = 0.0
	individual.thirst_zero_alerted = false
	var slot_index := waterskin_slot(individual)
	if slot_index == -1:
		individual.waterskin_water = 0.0
		return
	var capacity := CaloricCalculator.get_caloric_source_rules(individual.equipped_tools[slot_index]).water_capacity
	if individual.waterskin_water >= capacity:
		return
	individual.waterskin_water = capacity
	if individual.consume_equipped_tool_use(slot_index, GameSettings.active_game_data):
		individual.waterskin_water = 0.0


# Sorso al passaggio e fascia (GameSimulation.tick_frame, dopo il movimento): solo quando l'individuo entra in una
# microcella nuova, due lookup (fascia, rive). Alla riva torna pieno a qualsiasi livello e l'otre si riempie; l'icona
# solo se mancava acqua (la cintura si guarda solo a corpo pieno, sulla riva).
static func try_sip(individual: HumanIndividual, effects: GameEffects) -> void:
	if not THIRST_ENABLED or individual.daily_water_consumption <= 0.0:
		return
	var microcell := Vector2i(floori(individual.position.x), floori(individual.position.y))
	if microcell == individual.thirst_last_microcell:
		return
	individual.thirst_last_microcell = microcell
	var cell := PathfindingService.get_live_cell(individual.home_macro_coords)
	individual.thirst_in_water_band = cell != null and cell.water_band.has(microcell)
	if cell == null or not cell.water_access.has(microcell):
		return
	if individual.current_thirst >= individual.max_thirst and individual.waterskin_water >= waterskin_capacity(individual):
		return
	refill(individual)
	if effects != null:
		effects.individual_icon(individual, DRINK_ICON_KEY)
	if DebugLogging.ENABLED and DebugLogging.SHOW_THIRST_LOGS:
		print("[THIRST] #%d %s: sorso al passaggio in %s." % [individual.id, individual.name, str(microcell)])


static func is_drink_task(task: Task) -> bool:
	return task != null and (task.task_name == DRINK_TASK_NAME or task.task_name == EMERGENCY_DRINK_TASK_NAME)


# Bere urgente mentre si lavora (HumanIndividualActionService.apply_action, accanto agli altri bisogni): esce subito se
# l'acqua è sopra soglia, se il compito in corso è già un bere o non si può interrompere (fuga, riposo d'emergenza), o
# se l'ultima ricerca è fallita e l'acqua non è ancora calata abbastanza. true = compito assegnato.
static func handle_interrupt(individual: HumanIndividual, task: Task, age_band: HumanTypes.AgeBand) -> bool:
	if not needs_emergency_drink(individual) or is_drink_task(task):
		return false
	if task.interrupt_priority != -1 and task.interrupt_priority <= HumanIndividualActionService.INTERRUPT_PRIORITY_EMERGENCY_DRINK:
		return false
	return assign_drink_task(individual, age_band, true, true)


# Assegna drink (emergency = false) o emergency_drink. Niente compito se nessuna riva è raggiungibile o se l'ultima
# ricerca è fallita e l'acqua non è calata abbastanza da allora.
static func assign_drink_task(
	individual: HumanIndividual, age_band: HumanTypes.AgeBand, emergency: bool, is_interrupt_transition: bool
) -> bool:
	if individual.current_thirst >= individual.thirst_retry_below:
		return false
	var definition_path := EMERGENCY_DRINK_TASK_DEFINITION_PATH if emergency else DRINK_TASK_DEFINITION_PATH
	var target: Variant = _find_drink_target(individual)
	if target == null:
		_postpone_retry(individual, "nessuna riva raggiungibile")
		return false
	var task := TaskFactory.build_task(TaskDefinitionCache.get_definition(definition_path), {"drink_target_position": target})
	if not individual.can_assign_task(task, age_band) or not individual.assign_task(task, age_band, is_interrupt_transition):
		_postpone_retry(individual, "compito rifiutato")
		return false
	if DebugLogging.ENABLED and DebugLogging.SHOW_THIRST_LOGS:
		print("[THIRST] #%d %s: %s verso %s (acqua %.1f/%.1f)." % [
			individual.id, individual.name, definition_path.get_file(), str(target), individual.current_thirst, individual.max_thirst
		])
	return true


static func _postpone_retry(individual: HumanIndividual, reason: String) -> void:
	individual.thirst_retry_below = individual.current_thirst - individual.daily_water_consumption * RETRY_DROP_DAYS
	if DebugLogging.ENABLED and DebugLogging.SHOW_THIRST_LOGS:
		print("[THIRST] #%d %s: niente da bere (%s), riprovo sotto %.1f." % [
			individual.id, individual.name, reason, individual.thirst_retry_below
		])


# Riva più vicina in linea d'aria: prima nella cella dell'individuo (libera e raggiungibile), poi nelle altre celle vive
# (come PathfindingService.reachability_for, senza controllo di raggiungibilità fuori dalla propria cella). Punto nel
# riferimento dell'individuo, al centro della microcella; null se nessuna.
static func _find_drink_target(individual: HumanIndividual) -> Variant:
	var home := individual.home_macro_coords
	var from := Vector2i(floori(individual.position.x), floori(individual.position.y))
	var own_cell := PathfindingService.get_live_cell(home)
	var best: Variant = null
	var best_distance := INF
	if own_cell != null:
		for spot in own_cell.drink_spots:
			var distance := Vector2(spot - from).length_squared()
			if distance >= best_distance:
				continue
			if PathfindingService.is_blocked(own_cell, spot) or not PathfindingService.is_reachable(own_cell, from, spot):
				continue
			best_distance = distance
			best = Vector2(spot) + Vector2(0.5, 0.5)
	if best != null:
		return best
	var live_cells := PathfindingService.get_live_cells()
	for macro in live_cells:
		if macro == home:
			continue
		var cell: LiveMacroCell = live_cells[macro]
		var offset := (Vector2i(macro) - home) * World.WIDTH
		for spot in cell.drink_spots:
			var point: Vector2i = spot + offset
			var distance := Vector2(point - from).length_squared()
			if distance >= best_distance or PathfindingService.is_blocked(cell, spot):
				continue
			best_distance = distance
			best = Vector2(point) + Vector2(0.5, 0.5)
	return best
