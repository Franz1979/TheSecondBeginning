class_name JobWorkScanService
extends RefCounted

# Chi sta lavorando a cosa (2026-10-17, refactoring GameScene blocco 2b — estratto da GameScene, regole invariate): nomi
# delle task di lavoro sugli edifici, "chi ha una task su questo edificio" e la scansione unica delle assegnazioni usata
# dalla lista dei lavori e dalla scheda "In sospeso". Statico e senza stato: legge le task in corso e in coda degli
# individui passati.

# Costruzione (SetupSite/Clear/Build): usata da conteggio costruttori, demolizione e completamento.
const BUILD_TASK_NAMES: Array[String] = ["task_build_name"]
# Produzione presso una workstation.
const PRODUCE_TASK_NAMES: Array[String] = ["task_produce_name"]
# "Lavoro sull'edificio" annullabile dal pannello edificio (X accanto al lavoratore).
const BUILDING_WORK_TASK_NAMES: Array[String] = ["task_build_name", "task_produce_name"]
# Demolizione (2026-09-27, demolish.tres).
const DEMOLISH_TASK_NAMES: Array[String] = ["task_demolish_name"]
# Sgombero delle macerie (2026-10-18, Fossa dei rifiuti): una Transport dei detriti (WasteDisposalService).
const RUBBLE_CLEARING_TASK_NAMES: Array[String] = ["task_transport_name"]
# Task chiuse quando un edificio viene abbattuto.
const BUILD_AND_DEMOLISH_TASK_NAMES: Array[String] = ["task_build_name", "task_demolish_name"]
# Riparazione (2026-10-10, repair.tres).
const REPAIR_TASK_NAMES: Array[String] = ["task_repair_name"]


# true se `task` è una Task NON conclusa, con task_name in `task_names`, e almeno uno dei suoi step ancora da fare ha
# `target_building` == `building`. Letto dagli step (non da task.context, ripulito da TaskFactory subito dopo la
# costruzione — BUGFIX 2026-09-14). "target_building" in step (duck typing): gli step senza quel campo (WalkAction, ...)
# si escludono da soli. Solo gli step ancora da fare (2026-09-26, consegna dopo la produzione): a ordine finito il
# produttore che porta il prodotto al magazzino non occupa più la postazione; lo step di consegna
# (RetrieveAction.deliver_to_warehouse) non conta come lavoro sull'edificio.
# Task di chi lavora a demolire `building`: il trasporto dei detriti per le macerie e le Fosse in svuotamento, la Demolisci
# per ogni altro edificio.
static func demolish_task_names_for(building: Building) -> Array[String]:
	return RUBBLE_CLEARING_TASK_NAMES if WasteDisposalService.is_debris_source(building) else DEMOLISH_TASK_NAMES


static func task_works_on_building(task: Task, building: Building, task_names: Array[String]) -> bool:
	if task == null or task.is_finished() or not task_names.has(task.task_name):
		return false
	for step_index in range(task.current_step_index, task.steps.size()):
		var step: Action = task.steps[step_index]
		if step is RetrieveAction and (step as RetrieveAction).deliver_to_warehouse:
			continue
		if "target_building" in step and step.target_building == building:
			return true
	return false


# Task in corso e in coda non concluse di `member`.
static func open_tasks(member: HumanIndividual) -> Array[Task]:
	var tasks: Array[Task] = []
	if member.current_task != null and not member.current_task.is_finished():
		tasks.append(member.current_task)
	for queued in member.task_queue:
		var task := queued as Task
		if task != null and not task.is_finished():
			tasks.append(task)
	return tasks


# Cella dove `individual` lavora al cantiere `building` (2026-10-17, più costruttori — BuildingFootprint.work_cell): i
# costruttori in ordine di id si dividono le celle del rettangolo. Usata da SetupSite, Clear e Build.
static func build_work_cell(building: Building, individual: HumanIndividual) -> Vector2i:
	var builders := workers_on_building(GameSettings.active_human_individuals, building, BUILD_TASK_NAMES)
	builders.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool: return a.id < b.id)
	var index := maxi(builders.find(individual), 0)
	var cell := BuildingFootprint.work_cell(building, index, builders.size())
	if DebugLogging.ENABLED and (DebugLogging.SHOW_TRANSPORT_BUILD_LOGS or DebugLogging.SHOW_BUILDERS_LOGS):
		print("[BUILD] #%d %s lavora alla cella %s del cantiere #%d (costruttore %d di %d)." % [
			individual.id, individual.name, str(cell), building.id, index + 1, builders.size()
		])
	return cell


# Individui (nell'ordine di `individuals`) con una Task di `task_names` su `building`, attiva (current_task) o sospesa in
# coda (task_queue) — un individuo compare una volta sola.
static func workers_on_building(individuals: Array[HumanIndividual], building: Building, task_names: Array[String]) -> Array[HumanIndividual]:
	var workers: Array[HumanIndividual] = []
	for member in individuals:
		if task_works_on_building(member.current_task, building, task_names):
			workers.append(member)
			continue
		for queued_task in member.task_queue:
			if task_works_on_building(queued_task, building, task_names):
				workers.append(member)
				break
	return workers


# Ordini di `target_building` con un pipottino che ci lavora (Task di produzione in corso o in coda, step dal corrente in
# poi): chiave d'ordine -> HumanIndividual.
static func production_order_workers(individuals: Array[HumanIndividual], target_building: Building) -> Dictionary:
	var workers: Dictionary = {}
	for member in individuals:
		var tasks: Array = [member.current_task]
		tasks.append_array(member.task_queue)
		for task in tasks:
			if task == null or task.is_finished() or not PRODUCE_TASK_NAMES.has(task.task_name):
				continue
			for step_index in range(task.current_step_index, task.steps.size()):
				var step: Action = task.steps[step_index]
				if step is ProduceAction and (step as ProduceAction).target_building == target_building \
						and (step as ProduceAction).order_key != "":
					workers[(step as ProduceAction).order_key] = member
	return workers


# Un solo giro sui pipottini (task in corso e in coda): edifici con un costruttore o un demolitore, ordini di produzione
# con un lavoratore ("id:ordine"), corpi con una task Seppellisci, riti ordinati, riparazioni. Stessi criteri di
# task_works_on_building (step dal corrente in poi, esclusa la consegna al magazzino); gli ordini di produzione per
# chiave d'ordine.
# "postponed" (2026-10-16): cantieri rimandati per materiale nella coda personale, edificio -> pipottino; "build_active":
# cantieri con un costruttore che non li ha rimandati. Un cantiere solo rimandato resta assegnato ma va in "In coda".
# Produce e riparazioni (2026-10-17): stesse coppie "rimandato" / "attivo" dei cantieri, per chiave d'ordine e per edificio.
# "builders" (2026-10-17, più costruttori): cantiere -> {id pipottino: true}, chi ha una task Costruisci su di lui (in corso,
# in coda o rimandata), per confrontarlo con BuildingRules.max_builders.
static func collect_assignments(individuals: Array[HumanIndividual]) -> Dictionary:
	var result := {
		"build": {}, "demolish": {}, "produce": {}, "bodies": {}, "repair": {}, "rite": {}, "postponed": {}, "build_active": {},
		"postponed_produce": {}, "produce_active": {}, "postponed_repair": {}, "repair_active": {}, "builders": {},
	}
	for member in individuals:
		var tasks: Array = []
		if member.current_task != null and not member.current_task.is_finished():
			tasks.append(member.current_task)
		tasks.append_array(member.task_queue)
		for task in tasks:
			var queued := task as Task
			if queued == null or queued.is_finished():
				continue
			if BodyBurialService.is_bury_task(queued):
				result["bodies"][BodyBurialService.get_task_body_id(queued)] = true
				continue
			# Rito ordinato (2026-10-14): per edificio.
			if bool(queued.context.get(RiteService.CONTEXT_ORDERED, false)):
				for step in queued.steps:
					if step is RiteAction and (step as RiteAction).target_building != null:
						result["rite"][(step as RiteAction).target_building.id] = true
				continue
			# Sgombero delle macerie (2026-10-18): conta come lavoro "demolish" sulle macerie sorgente.
			if WasteDisposalService.is_debris_clearing_task(queued):
				result["demolish"][int(queued.context.get("transport_source_id", -1))] = true
				continue
			var bucket := ""
			if BUILD_TASK_NAMES.has(queued.task_name):
				bucket = "build"
			elif DEMOLISH_TASK_NAMES.has(queued.task_name):
				bucket = "demolish"
			elif REPAIR_TASK_NAMES.has(queued.task_name):
				bucket = "repair"
			elif PRODUCE_TASK_NAMES.has(queued.task_name):
				# Ordini separati (2026-10-04): per chiave d'ordine.
				var produce_postponed := queued != member.current_task and queued.context.has(HumanIndividualActionService.CONTEXT_MATERIAL_POSTPONED)
				for step in queued.steps:
					if step is ProduceAction and step.target_building != null and (step as ProduceAction).order_key != "":
						var produce_key := "%d:%s" % [step.target_building.id, (step as ProduceAction).order_key]
						result["produce"][produce_key] = true
						result["postponed_produce" if produce_postponed else "produce_active"][produce_key] = member if produce_postponed else true
				continue
			else:
				continue
			for step_index in range(queued.current_step_index, queued.steps.size()):
				var step: Action = queued.steps[step_index]
				if step is RetrieveAction and (step as RetrieveAction).deliver_to_warehouse:
					continue
				if "target_building" in step and step.target_building != null:
					result[bucket][step.target_building.id] = true
					if bucket == "build":
						if not result["builders"].has(step.target_building.id):
							result["builders"][step.target_building.id] = {}
						result["builders"][step.target_building.id][member.id] = true
					if bucket == "build" or bucket == "repair":
						var postponed_key := "postponed" if bucket == "build" else "postponed_repair"
						var active_key := "build_active" if bucket == "build" else "repair_active"
						if queued != member.current_task and queued.context.has(HumanIndividualActionService.CONTEXT_MATERIAL_POSTPONED):
							result[postponed_key][step.target_building.id] = member
						else:
							result[active_key][step.target_building.id] = true
	return result


# Pezzi ancora dovuti per ogni ordine di produzione dell'edificio, riallineati alle Task VIVE (in corso e in coda) di tutti
# gli individui (2026-10-18, refactoring GameScene blocco 5e — prima GameScene._reconcile_production_units): per ogni
# ProduceAction sull'edificio non ancora conclusa, quantità ordinata - pezzi già prodotti. Ordini separati (2026-10-04):
# ogni ordine ha i suoi pezzi; un ordine senza Task resta com'è (lavoratore mancante). Chiamata all'assegnazione,
# all'annullo, al refresh del pannello e ogni giorno (reconcile_all_production_units).
static func reconcile_production_units(individuals: Array, target_building: Building) -> void:
	if target_building == null or target_building.production_progress.is_empty():
		return
	for step in _live_produce_steps(individuals, target_building):
		if ProductionService.has_order(target_building, step.order_key):
			ProductionService.set_order_units(target_building, step.order_key, maxi(step.quantity - step.produced_count, 0))


# Riallineamento giornaliero di tutti gli edifici con produzioni in corso (GameSimulation.tick_day).
static func reconcile_all_production_units(world: World, individuals: Array) -> void:
	if world == null:
		return
	for building in world.buildings:
		if not building.production_progress.is_empty():
			reconcile_production_units(individuals, building)


# ProduceAction ancora da concludere su `target_building`, nelle Task di produzione (in corso e in coda) di tutti.
static func _live_produce_steps(individuals: Array, target_building: Building) -> Array[ProduceAction]:
	var steps: Array[ProduceAction] = []
	for member in individuals:
		var tasks: Array = [member.current_task]
		tasks.append_array(member.task_queue)
		for task in tasks:
			if task == null or task.is_finished() or not PRODUCE_TASK_NAMES.has(task.task_name):
				continue
			for step_index in range(task.current_step_index, task.steps.size()):
				var step: Action = task.steps[step_index]
				if step is ProduceAction and (step as ProduceAction).target_building == target_building:
					steps.append(step as ProduceAction)
	return steps
