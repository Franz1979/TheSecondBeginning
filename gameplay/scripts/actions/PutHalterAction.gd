class_name PutHalterAction
extends Action

# Mette la cavezza a un animale preso vivo nell'imbuto di caccia (2026-11-18, richiesta utente — lavoro "Conduci al recinto",
# riga Allevamento, LeadAnimalJobProvider). Chiede un attrezzo di Conduzione (la cavezza, in cintura). All'arrivo all'imbuto,
# dopo una breve sosta (più corta con Allevamento), toglie dalla trappola l'animale che aspetta col meno giorni da vivere
# (TrapService.take_led_catch), consuma un uso della cavezza, lo prende in mano (LedAnimalService.start) e aggiunge dopo di
# sé il cammino fino al recinto prenotato e la tappa KeepAnimalAction che lo sistema (recinto sparito o pieno: un altro con
# posto, altrimenti si macella lì). L'animale è condotto, non portato: niente spazio nello zaino. Nessun animale che
# aspetta: la Task si chiude.
#
# Animale legato (`led_id` >= 0): chi lo conduceva si è fermato e l'ha legato lì (LedAnimalService). Qui lo si riprende:
# la cavezza ce l'ha già, quindi nessun attrezzo e nessun uso consumato.
#
# Dal recinto alla stalla (`animal_id` >= 0, 2026-11-19, "Conduci alla stalla"): un domestico grosso nato nel recinto. Con
# la cavezza (un uso), lo segna in mano (DomesticAnimal.carried_by: resta del recinto fino all'arrivo) e lo porta alla
# stalla della sua specie con posto più vicina (DomesticTransferService.nearest_breeding_building).

const HALTER_DAYS: float = 0.01

var trap_id: int = -1
var led_id: int = -1
var animal_id: int = -1
var _elapsed: float = 0.0
var _done: bool = false


func _init(p_trap_id: int = -1, p_led_id: int = -1, p_animal_id: int = -1) -> void:
	target = null
	trap_id = p_trap_id
	led_id = p_led_id
	animal_id = p_animal_id
	if led_id < 0:
		required_tool_categories = [TaskTypes.ToolCategory.LEADING]
	skill_effect_key = DomesticTransferService.SKILL_EFFECT_KEY
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done:
		return 0.0
	var game_data: GameData = GameSettings.active_game_data
	var trap: PlacedTrap = null
	if led_id >= 0:
		var record := LedAnimalService.find(game_data, led_id)
		if record.is_empty() or int(record["holder_id"]) >= 0:
			_done = true
			context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "l'animale legato non c'è più"
			return 0.0
	elif animal_id >= 0:
		var animal := DomesticAnimalService.find_animal(game_data, animal_id)
		if animal == null or animal.carried_by >= 0 or animal.slaughter_requested or animal.building_id < 0:
			_done = true
			context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "l'animale non è più nel recinto"
			return 0.0
		if not ensure_required_tools(individual):
			return 0.0
	else:
		trap = TrapService.find_trap(game_data, trap_id)
		if trap == null or TrapService.waiting_indices(trap, game_data.get_absolute_day()).is_empty():
			_done = true
			context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "nessun animale da condurre nell'imbuto"
			return 0.0
		if not ensure_required_tools(individual):
			return 0.0
	_elapsed += delta * SkillEffectService.get_factor_for_action(self, individual, context)
	if _elapsed >= HALTER_DAYS:
		_done = true
		if animal_id >= 0:
			_lead_domestic(individual, context)
		else:
			_lead(individual, trap)
	return 0.0


func is_complete(_individual: Variant, _context: Dictionary) -> bool:
	return _done


# Prende l'animale (dall'imbuto: quello con meno giorni da vivere, con un uso della cavezza; legato: quello) e accoda cammino
# e tappa al recinto.
func _lead(individual: Variant, trap: PlacedTrap) -> void:
	var game_data: GameData = GameSettings.active_game_data
	var entry: Dictionary = {}
	if trap != null:
		var waiting := TrapService.waiting_indices(trap, game_data.get_absolute_day())
		entry = TrapService.take_led_catch(game_data, trap, waiting[0])
		var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, null)
		if not broken.is_empty():
			report_broken_tools(individual, broken)
		LedAnimalService.start(game_data, entry, individual)
	else:
		var record := LedAnimalService.take(game_data, led_id, individual)
		if record.is_empty():
			return
		entry = record["entry"]
		# Domestico ripreso (2026-11-19): di nuovo in mano a questa persona.
		if entry.has("animal_id"):
			var held := DomesticAnimalService.find_animal(game_data, int(entry["animal_id"]))
			if held != null:
				held.carried_by = individual.id
	var pen := WarehouseManagerService.find_building(GameSettings.active_world, int(entry.get("building_id", -1)))
	TrapService.log_line("#%d %s: %s con la cavezza (%s), verso il recinto #%d" % [individual.id, individual.name,
		entry.get("wild_species", "?"), "dall'imbuto #%d" % trap.id if trap != null else "ripreso dove era legato",
		pen.id if pen != null else -1])
	var task: Task = individual.current_task
	if task == null:
		return
	var steps: Array[Action] = []
	var descriptions: Array[String] = []
	if pen != null:
		steps.append(WalkAction.new(KeepAnimalAction.walk_point(individual, pen)))
		descriptions.append("task_lead_animal_step_walk_pen")
	steps.append(KeepAnimalAction.new(pen, [entry]))
	descriptions.append("task_lead_animal_step_place")
	# Domestico ripreso verso la stalla (2026-11-19): i testi della stalla.
	if entry.has("animal_id"):
		for i in range(descriptions.size()):
			descriptions[i] = descriptions[i].replace("walk_pen", "walk_stable").replace("step_place", "step_place_stable")
	task.insert_steps_after_current(steps, descriptions)


# Dal recinto: la stalla con posto più vicina, un uso della cavezza, l'animale in mano, cammino e tappa alla stalla.
func _lead_domestic(individual: Variant, context: Dictionary) -> void:
	var game_data: GameData = GameSettings.active_game_data
	var world: World = GameSettings.active_world
	var animal := DomesticAnimalService.find_animal(game_data, animal_id)
	if animal == null:
		return
	var pen := WarehouseManagerService.find_building(world, animal.building_id)
	var macro: Vector2i = Vector2i(pen.macro_x, pen.macro_y) if pen != null else individual.home_macro_coords
	var stable := DomesticTransferService.nearest_breeding_building(game_data, world, animal.species, macro,
		KeptAnimalService.reservations(GameSettings.active_human_individuals))
	if stable == null:
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "nessuna stalla con posto"
		return
	var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, null)
	if not broken.is_empty():
		report_broken_tools(individual, broken)
	var entry := DomesticTransferService.transfer_entry(animal,
		DomesticTransferService.age_band_of(animal, game_data.get_absolute_day()), stable.id)
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	entry["wild_species"] = rules.wild_species_name if rules != null else animal.species
	entry["space"] = 0.0
	entry["led"] = true
	entry["catch_day"] = game_data.get_absolute_day()
	animal.carried_by = individual.id
	LedAnimalService.start(game_data, entry, individual)
	DebugLogging.print_event("[TRANSFER] #%d %s: %s #%d con la cavezza dal recinto #%d alla stalla #%d" % [individual.id,
		individual.name, animal.species, animal.id, animal.building_id, stable.id])
	var task: Task = individual.current_task
	if task == null:
		return
	var steps: Array[Action] = [WalkAction.new(KeepAnimalAction.walk_point(individual, stable)), KeepAnimalAction.new(stable, [entry])]
	var descriptions: Array[String] = ["task_lead_animal_step_walk_stable", "task_lead_animal_step_place_stable"]
	task.insert_steps_after_current(steps, descriptions)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "done": _done, "trap_id": trap_id, "led_id": led_id, "animal_id": animal_id}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	_done = bool(data.get("done", false))
