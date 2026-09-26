class_name ToolGateService
extends RefCounted

# Controllo degli attrezzi richiesti da una Task, al momento dell'assegnazione (2026-09-25, richiesta
# utente — primo collaudo sulla produzione, vedi GameScene._assign_produce_task). Stateless, stesso
# pattern dei *Service del progetto.
#
# Categorie richieste = unione di Action.required_tool_categories di TUTTI gli step della Task e, per
# ogni ProduceAction, di SecondaryResourceRules.recipe_required_tool_categories della risorsa da
# produrre. Per ogni categoria, nell'ordine:
#   - un attrezzo in cintura (HumanIndividual.equipped_tools) la copre -> ok;
#   - altrimenti un attrezzo nello zaino la copre -> viene spostato in cintura
#     (HumanIndividual.equip_tool_from_backpack) -> ok;
#   - lo zaino ce l'ha ma la cintura è piena -> la Task non parte (BELT_FULL);
#   - non c'è né in cintura né nello zaino -> la Task non parte (MISSING_TOOLS).
# Prima si PIANIFICA (nessuno spostamento), e solo se tutte le categorie sono coperte si eseguono gli
# spostamenti: una Task rifiutata non lascia attrezzi spostati a metà. Un attrezzo pianificato copre
# anche le altre categorie che sa fare (es. il coltello: CUTTING, BUTCHERING, COMBAT).
#
# Non decide né mostra nulla lato UI: restituisce l'esito, GameScene compone avviso/popup.
#
# Usura (2026-09-26, attrezzi come istanze — step 3): consume_tool_uses toglie un uso a ogni attrezzo
# distinto usato in un ciclo (get_slots_used_for/find_belt_slot_for) e riporta quelli rotti.
#
# Attesa invece di rifiuto (2026-09-25, richiesta utente): con MISSING_TOOLS la Task viene assegnata
# comunque e resta in attesa — ProduceAction richiama try_satisfy a ogni tick sulle proprie categorie
# (get_action_required_categories) e parte da sola quando gli attrezzi arrivano nello zaino. Solo
# BELT_FULL/CANNOT_EQUIP (attrezzo presente ma che non entra in cintura) rifiutano l'assegnazione.

enum Result { OK, MISSING_TOOLS, BELT_FULL, CANNOT_EQUIP }


static func get_required_categories(task: Task) -> Array[TaskTypes.ToolCategory]:
	var required: Array[TaskTypes.ToolCategory] = []
	if task == null:
		return required
	for step in task.steps:
		for category in get_action_required_categories(step):
			if not required.has(category):
				required.append(category)
	return required


# Categorie richieste da UN singolo step: le sue required_tool_categories più, per una ProduceAction,
# le recipe_required_tool_categories della risorsa da produrre. Usata anche dalla ProduceAction
# stessa per il controllo ricorrente mentre è in attesa degli attrezzi.
static func get_action_required_categories(action: Action) -> Array[TaskTypes.ToolCategory]:
	var required: Array[TaskTypes.ToolCategory] = []
	if action == null:
		return required
	for category in action.required_tool_categories:
		if not required.has(category):
			required.append(category)
	if action is ProduceAction:
		var recipe_rules := CaloricCalculator.get_caloric_source_rules((action as ProduceAction).resource_name)
		if recipe_rules != null:
			for category in recipe_rules.recipe_required_tool_categories:
				if not required.has(category):
					required.append(category)
	return required


# Nomi delle risorse attrezzo (tool_categories non vuoto) che coprono la categoria, in ordine
# alfabetico — per i messaggi ("es. Coltello di pietra"). Scansione dei .tres delle risorse
# secondarie, regole in cache in CaloricCalculator.
static func get_tools_covering(category: TaskTypes.ToolCategory) -> Array[String]:
	var tools: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if _tool_categories(resource_name).has(category):
			tools.append(resource_name)
	tools.sort()
	return tools


# Esito: {"result": Result, "missing_categories": Array[ToolCategory] (MISSING_TOOLS),
# "tool_name": String (BELT_FULL/CANNOT_EQUIP: l'attrezzo che non è entrato in cintura),
# "equipped": Array[String] (attrezzi spostati dallo zaino alla cintura, se OK)}.
static func check_and_prepare(individual: HumanIndividual, task: Task, game_data: GameData) -> Dictionary:
	return try_satisfy(individual, get_required_categories(task), game_data)


# Stesso controllo di check_and_prepare, su un elenco di categorie già risolto (una Task intera o un
# singolo step, vedi ProduceAction). game_data può essere null: la capacità di trasporto viene allora
# corretta del solo bonus dello slot (vedi HumanIndividual._recalculate_carry_capacity_after_tool_change).
static func try_satisfy(individual: HumanIndividual, required: Array[TaskTypes.ToolCategory], game_data: GameData) -> Dictionary:
	var outcome := {"result": Result.OK, "missing_categories": [], "tool_name": "", "equipped": []}
	if individual == null or required.is_empty():
		return outcome

	var planned_equips: Array[String] = []
	var missing: Array = []
	for category in required:
		if _belt_covers(individual, category) or _tools_cover(planned_equips, category):
			continue
		var backpack_tool := _find_backpack_tool_for(individual, category, planned_equips)
		if backpack_tool == "":
			missing.append(category)
		else:
			planned_equips.append(backpack_tool)

	if not missing.is_empty():
		outcome["result"] = Result.MISSING_TOOLS
		outcome["missing_categories"] = missing
		return outcome

	var free_slots: int = individual.get_tool_slot_count() - individual.equipped_tool_count
	if planned_equips.size() > free_slots:
		outcome["result"] = Result.BELT_FULL
		# Il primo attrezzo pianificato che non trova posto.
		outcome["tool_name"] = planned_equips[maxi(free_slots, 0)]
		return outcome

	for tool_name in planned_equips:
		if not individual.equip_tool_from_backpack(tool_name, game_data):
			# Zaino oltre la capacità ridotta dal bonus dello slot occupato (vedi
			# HumanIndividual.equip_tool_from_backpack): caso raro, gli spostamenti già fatti restano.
			outcome["result"] = Result.CANNOT_EQUIP
			outcome["tool_name"] = tool_name
			return outcome
		outcome["equipped"].append(tool_name)
	return outcome


static func _tool_categories(tool_name: String) -> Array:
	var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
	return rules.tool_categories if rules != null else []


static func _belt_covers(individual: HumanIndividual, category: TaskTypes.ToolCategory) -> bool:
	return find_belt_slot_for(individual, category) != -1


# Primo slot della cintura il cui attrezzo copre la categoria, -1 se nessuno (2026-09-26, attrezzi come
# istanze — step 3: serve sapere QUALE attrezzo consumare, non solo se la categoria è coperta). Stesso
# ordine di scansione di sempre: lo slot scelto qui è quello che il gate ha considerato "coprente".
static func find_belt_slot_for(individual: HumanIndividual, category: TaskTypes.ToolCategory) -> int:
	for slot in range(individual.get_tool_slot_count()):
		var tool_name := individual.get_equipped_tool(slot)
		if tool_name != "" and _tool_categories(tool_name).has(category):
			return slot
	return -1


# Gittata massima (SecondaryResourceRules.max_range, microcelle) tra gli attrezzi in cintura che coprono
# la categoria (2026-09-26, caccia step 2 — ApproachPreyAction: entro quanto l'individuo può colpire
# la preda). -1.0 se nessun attrezzo in cintura copre la categoria; 0.0 = solo armi da corpo a corpo.
static func get_belt_max_range_for(individual: HumanIndividual, category: TaskTypes.ToolCategory) -> float:
	var best := -1.0
	for slot in range(individual.get_tool_slot_count()):
		var tool_name := individual.get_equipped_tool(slot)
		if tool_name == "" or not _tool_categories(tool_name).has(category):
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
		best = maxf(best, rules.max_range if rules != null else 0.0)
	return best


# Slot DISTINTI della cintura che coprono le categorie richieste (2026-09-26, step 3): un attrezzo già
# scelto per una categoria copre anche le altre che sa fare, quindi conta una volta sola (es. il
# coltello per CUTTING e BUTCHERING insieme). Categorie non coperte ignorate: qui si guarda solo cosa
# è stato davvero usato.
static func get_slots_used_for(individual: HumanIndividual, required: Array[TaskTypes.ToolCategory]) -> Array[int]:
	var slots: Array[int] = []
	for category in required:
		var already_covered := false
		for chosen_slot in slots:
			if _tool_categories(individual.get_equipped_tool(chosen_slot)).has(category):
				already_covered = true
				break
		if already_covered:
			continue
		var slot := find_belt_slot_for(individual, category)
		if slot != -1:
			slots.append(slot)
	return slots


# Consumo di UN uso per ogni attrezzo distinto usato (2026-09-26, step 3 — chiamato da ProduceAction a
# ogni ciclo completato). Un attrezzo che arriva a 0 usi sparisce dallo slot (HumanIndividual.
# consume_equipped_tool_use, che aggiorna anche la capacità di trasporto). Ritorna i nomi degli
# attrezzi rotti in questa chiamata (vuoto = nessuna rottura), per l'avviso al giocatore. Nessuna logica
# di Task qui: al tick successivo il normale try_satisfy non trova più la categoria e rimette in cintura
# un attrezzo di scorta dallo zaino, o lascia lo step in attesa (MISSING_TOOLS).
static func consume_tool_uses(individual: HumanIndividual, required: Array[TaskTypes.ToolCategory], game_data: GameData) -> Array[String]:
	var broken: Array[String] = []
	if individual == null or required.is_empty():
		return broken
	for slot in get_slots_used_for(individual, required):
		var tool_name := individual.get_equipped_tool(slot)
		if individual.consume_equipped_tool_use(slot, game_data):
			broken.append(tool_name)
	return broken


static func _tools_cover(tool_names: Array[String], category: TaskTypes.ToolCategory) -> bool:
	for tool_name in tool_names:
		if _tool_categories(tool_name).has(category):
			return true
	return false


# Primo attrezzo nello zaino (ordine di inserimento) che copre la categoria e non è già pianificato.
static func _find_backpack_tool_for(
	individual: HumanIndividual, category: TaskTypes.ToolCategory, already_planned: Array[String]
) -> String:
	for resource_name in individual.carried_resources.keys():
		var candidate := String(resource_name)
		if already_planned.has(candidate) or individual.get_carried_quantity(candidate) <= 0:
			continue
		if HumanIndividual.is_tool_resource(candidate) and _tool_categories(candidate).has(category):
			return candidate
	return ""
