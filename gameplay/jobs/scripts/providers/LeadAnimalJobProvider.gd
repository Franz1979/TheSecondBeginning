class_name LeadAnimalJobProvider
extends RefCounted

# Fornitore "Conduci al recinto" della lista dei lavori (2026-11-18, richiesta utente — riga Allevamento, tipo "husbandry"):
# un lavoro per ogni animale preso vivo nell'imbuto di caccia che aspetta col suo recinto prenotato (TrapService.
# waiting_indices), e uno per ogni animale lasciato legato da chi lo conduceva (LedAnimalService). Dall'imbuto si va con la
# cavezza (attrezzo di Conduzione, da prendere in deposito se manca); un animale legato la cavezza ce l'ha già. Passa prima
# degli altri lavori di Allevamento ("priority_first"): fermo, l'animale muore dopo i giorni senza cibo della sua specie.
# Non lo prende chi sta per fermarsi per stanchezza o sete (si fermerebbe a metà strada). Solo celle vive. Assegnazione e
# Rimetti in coda restano alla scena.
#
# Conduci alla stalla (2026-11-19): un lavoro per ogni domestico grosso che aspetta nel recinto, se una stalla della sua specie
# ha posto (al massimo quanti posti ci sono, alternando maschi e femmine). Priorità normale: nel recinto mangia.

const KIND := "husbandry"
const SORT_OFFSET: float = 4480000.0
const CONTEXT_TRAP_ID := "lead_trap_id"
const CONTEXT_LED_ID := "lead_animal_id"
const CONTEXT_DOMESTIC_ID := "lead_domestic_id"
const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/lead_animal.tres"
const STABLE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/lead_animal_stable.tres"
const TOOL_AGE_KIND := DrawerOrderService.TYPE_TRANSPORT
# Margine sopra la soglia del riposo: sotto, la persona non parte (2026-11-18).
const STAMINA_MARGIN: float = 0.10


static func tool_categories() -> Array[TaskTypes.ToolCategory]:
	return [TaskTypes.ToolCategory.LEADING]


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null or ctx.world == null:
		return jobs
	var day := ctx.game_data.get_absolute_day()
	for trap in ctx.game_data.placed_traps:
		if not TrapService.is_led_catch(TrapService.get_rules(trap.trap_name)) or not ctx.live_cells.has(trap.macro_coords):
			continue
		var waiting := TrapService.waiting_indices(trap, day)
		var claimers := _workers_of(ctx, trap.id, -1)
		for n in range(maxi(waiting.size(), claimers.size())):
			var wild_species := trap.catch_species[waiting[n]] if n < waiting.size() and waiting[n] < trap.catch_species.size() else ""
			var claimer: HumanIndividual = claimers[n] if n < claimers.size() else null
			jobs.append(_job(ctx, provider, "%s:lead:%d:%d" % [KIND, trap.id, n], wild_species, trap.macro_coords, trap.lot,
				trap.work_area_id, float(trap.id) + float(n) * 0.001, claimer, true,
				{"trap_id": trap.id, "led_id": -1, "animal_id": -1}))
	for record in LedAnimalService.tied(ctx.game_data):
		var macro := Vector2i(int(record["macro_x"]), int(record["macro_y"]))
		if not ctx.live_cells.has(macro):
			continue
		var claimers := _workers_of(ctx, -1, int(record["id"]))
		var lot := Vector2i(int(floor(float(record["x"]))), int(floor(float(record["y"]))))
		var tied_entry: Dictionary = record["entry"]
		jobs.append(_job(ctx, provider, "%s:lead_tied:%d" % [KIND, int(record["id"])],
			String(tied_entry.get("wild_species", "")), macro, lot, 0, 0.5 + float(int(record["id"])),
			claimers[0] if not claimers.is_empty() else null, false, {"trap_id": -1, "led_id": int(record["id"]), "animal_id": -1},
			String(tied_entry.get("species", "")) if tied_entry.has("animal_id") else ""))
	# Dal recinto alla stalla (2026-11-19).
	for building in ctx.world.buildings:
		if not _is_waiting_pen(building) or not ctx.live_cells.has(Vector2i(building.macro_x, building.macro_y)):
			continue
		for animal in _stable_candidates(ctx, building):
			var claimers := _workers_of(ctx, -1, -1, animal.id)
			var job := _job(ctx, provider, "%s:lead_stable:%d" % [KIND, animal.id], "", Vector2i(building.macro_x, building.macro_y),
				Vector2i(building.micro_x, building.micro_y), 0, 0.7 + float(building.id) + float(animal.id) * 0.0001,
				claimers[0] if not claimers.is_empty() else null, true, {"trap_id": -1, "led_id": -1, "animal_id": animal.id},
				animal.species)
			job["entry_kind"] = "building"
			job["id"] = building.id
			job["priority_first"] = false
			jobs.append(job)
	return jobs


# Recinto (o tettoia) per animali grossi, finito: da qui i domestici vanno alla stalla.
static func _is_waiting_pen(building: Building) -> bool:
	return building != null and building.is_complete and not building.is_demolished and building.rules != null \
		and building.rules.keeps_big_animals and KeptAnimalService.capacity(building) > 0 and not KeptAnimalService.is_breeding(building)


# Domestici grossi di `pen` da portare alla stalla: prima quelli già presi da qualcuno (prima della cavezza), poi gli altri
# fino ai posti liberi nelle stalle della loro specie, alternando maschi e femmine (prima il sesso con meno, a parità le
# femmine), in ordine di id.
static func _stable_candidates(ctx: GameContext, pen: Building) -> Array[DomesticAnimal]:
	var result: Array[DomesticAnimal] = []
	var by_species := {}
	for animal in ctx.game_data.domestic_animals:
		if animal.building_id != pen.id or animal.is_wild or animal.slaughter_requested or animal.carried_by >= 0 \
				or not KeptAnimalService.is_big_species(animal.species):
			continue
		if not by_species.has(animal.species):
			by_species[animal.species] = []
		by_species[animal.species].append(animal)
	var reserved := KeptAnimalService.reservations(ctx.individuals)
	for species in by_species:
		var animals: Array = by_species[species]
		animals.sort_custom(func(a: DomesticAnimal, b: DomesticAnimal) -> bool: return a.id < b.id)
		var room := DomesticTransferService.breeding_room(ctx.game_data, ctx.world, species, reserved)
		var males: Array[DomesticAnimal] = []
		var females: Array[DomesticAnimal] = []
		for animal: DomesticAnimal in animals:
			if not _workers_of(ctx, -1, -1, animal.id).is_empty():
				result.append(animal)
				room -= 1
			elif animal.is_male:
				males.append(animal)
			else:
				females.append(animal)
		var next_male := 0
		var next_female := 0
		while room > 0 and (next_male < males.size() or next_female < females.size()):
			var take_female := next_female < females.size() and (next_female <= next_male or next_male >= males.size())
			if take_female:
				result.append(females[next_female])
				next_female += 1
			else:
				result.append(males[next_male])
				next_male += 1
			room -= 1
	return result


static func _job(ctx: GameContext, provider: Dictionary, key: String, wild_species: String, macro: Vector2i, lot: Vector2i,
		area_id: int, sort: float, claimer: HumanIndividual, needs_halter: bool, target: Dictionary,
		domestic_species: String = "") -> Dictionary:
	# Domestico verso la stalla (2026-11-19): nome domestico e testo "alla stalla".
	var species := domestic_species if domestic_species != "" else KeptAnimalService.domestic_species_for_wild(wild_species)
	var name := GameContext.tr_text("job_lead_animal_stable" if domestic_species != "" else "job_lead_animal").format({
		"species": KeptAnimalService.species_display_name(species, domestic_species == "") if species != "" else "",
	})
	var blocked := ""
	if claimer == null and needs_halter:
		blocked = ToolFetchService.blocked_reason(ctx, tool_categories(), TOOL_AGE_KIND)
	var job := {
		"key": key, "kind": KIND, "name": name, "text": name,
		"log_name": "conduci %s (%s)" % [wild_species, key],
		"icon": {"command": "transport"}, "macro": macro, "microcell": lot,
		"reach_target": {"macro_x": macro.x, "macro_y": macro.y, "micro_x": lot.x, "micro_y": lot.y},
		"entry_kind": "work_area", "id": area_id, "sort": sort + SORT_OFFSET,
		"assigned": claimer != null, "hidden": false, "blocked_reason": blocked,
		"provider": provider, "claimers": [claimer] if claimer != null else [],
		"priority_first": true,
	}
	job.merge(target)
	return job


# Motivo per cui `worker` non può prendere il lavoro (HumanIndividual.ASSIGN_OK se può): un animale ancora libero, non
# troppo stanco né assetato, la cavezza addosso o in deposito (solo dall'imbuto), il compito di prova.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var led_id := int(job.get("led_id", -1))
	var animal_id := int(job.get("animal_id", -1))
	var trap := TrapService.find_trap(ctx.game_data, int(job.get("trap_id", -1)))
	if animal_id >= 0:
		var animal := DomesticAnimalService.find_animal(ctx.game_data, animal_id)
		if animal == null or animal.carried_by >= 0 or animal.slaughter_requested or animal.building_id < 0 \
				or not _workers_of(ctx, -1, -1, animal_id).is_empty():
			return "nessun animale da condurre"
		if DomesticTransferService.breeding_room(ctx.game_data, ctx.world, animal.species,
				KeptAnimalService.reservations(ctx.individuals)) <= 0:
			return "nessuna stalla con posto"
	elif led_id >= 0:
		var record := LedAnimalService.find(ctx.game_data, led_id)
		if record.is_empty() or int(record["holder_id"]) >= 0 or not _workers_of(ctx, -1, led_id).is_empty():
			return "nessun animale da condurre"
	elif trap == null or TrapService.waiting_indices(trap, ctx.game_data.get_absolute_day()).size() <= _workers_of(ctx, trap.id, -1).size():
		return "nessun animale da condurre"
	if worker.max_stamina > 0.0 and worker.current_stamina / worker.max_stamina \
			< HumanIndividualActionService.STAMINA_REST_THRESHOLD + STAMINA_MARGIN:
		return "troppo stanco per condurre un animale"
	if ThirstService.is_enabled() and ThirstService.needs_drink(worker):
		return "deve prima bere"
	if led_id < 0:
		var tool_rejection := ToolFetchService.rejection(ctx, worker, tool_categories(), TOOL_AGE_KIND)
		if tool_rejection != "":
			return tool_rejection
	var probe := build_task(ctx, worker, job)
	if probe == null:
		return "animale non raggiungibile"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


# Definizione del compito: dal recinto alla stalla o dall'imbuto/animale legato al recinto.
static func definition_path(job: Dictionary) -> String:
	return STABLE_TASK_DEFINITION_PATH if int(job.get("animal_id", -1)) >= 0 else TASK_DEFINITION_PATH


static func build_task(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> Task:
	var definition := TaskDefinitionCache.get_definition(definition_path(job))
	if definition == null:
		return null
	var led_id := int(job.get("led_id", -1))
	var animal_id := int(job.get("animal_id", -1))
	var position := Vector2.ZERO
	if animal_id >= 0:
		var animal := DomesticAnimalService.find_animal(ctx.game_data, animal_id)
		var pen := WarehouseManagerService.find_building(ctx.world, animal.building_id) if animal != null else null
		if pen == null:
			return null
		position = KeepAnimalAction.walk_point(worker, pen)
	elif led_id >= 0:
		var record := LedAnimalService.find(ctx.game_data, led_id)
		if record.is_empty():
			return null
		position = LedAnimalService.walk_point(worker, record)
	else:
		var trap := TrapService.find_trap(ctx.game_data, int(job.get("trap_id", -1)))
		if trap == null:
			return null
		position = Vector2(trap.lot) + Vector2(0.5, 0.5) + TaskBuilderService.macro_offset(worker, trap.macro_coords)
	return TaskFactory.build_task(definition, {
		"lead_trap_position": position,
		CONTEXT_TRAP_ID: int(job.get("trap_id", -1)),
		CONTEXT_LED_ID: led_id,
		CONTEXT_DOMESTIC_ID: animal_id,
	})


static func is_lead_task(task: Task) -> bool:
	return task != null and task.context.has(CONTEXT_TRAP_ID)


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result


# Chi ha una Task "Conduci" per questo imbuto (`trap_id`), per questo animale legato (`led_id`) o per questo domestico del
# recinto (`animal_id`) non ancora arrivata alla cavezza: ognuno tiene un animale che aspetta. Dopo la cavezza l'animale è
# in mano sua e il lavoro non è più di questa lista.
static func _workers_of(ctx: GameContext, trap_id: int, led_id: int, animal_id: int = -1) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if not is_lead_task(task) or _halter_done(task):
				continue
			if int(task.context.get(CONTEXT_TRAP_ID, -1)) == trap_id and int(task.context.get(CONTEXT_LED_ID, -1)) == led_id \
					and int(task.context.get(CONTEXT_DOMESTIC_ID, -1)) == animal_id:
				result.append(member)
	return result


static func _halter_done(task: Task) -> bool:
	for i in range(task.steps.size()):
		var step := task.steps[i]
		if step is PutHalterAction:
			return task.current_step_index > i or (task.current_step_index == i and step.is_complete(null, task.context))
	return false
