class_name BuildingToolkitService
extends RefCounted

# Attrezzeria di un edificio di produzione (2026-10-04, richiesta utente): un piccolo deposito di attrezzi che appartiene
# all'edificio; chi produce lì usa quelli prima dei propri. Capienza da BuildingRules: toolkit_tool_types tipi di
# attrezzo, toolkit_units_per_type pezzi per tipo. Generica (2026-10-04, richiesta utente): un edificio QUALSIASI ha
# l'Attrezzeria se entrambi i campi sono > 0 — basta impostarli nei dati, nessun tipo di edificio nominato nel codice.
# Funzioni pensate anche per un uso futuro in cui l'attrezzo viene preso, portato via e riportato (take_unit/add_unit).
#
# Contenuto in Building.toolkit, stesso schema del magazzino per gli attrezzi (ToolInstance): nome attrezzo ->
# {"quantity": pezzi, "used_instances": [istanze dei pezzi usati]} — nuovi = quantity - used_instances.size(). Accetta
# solo attrezzi (categoria TOOL). Separata dal magazzino: non conta come spazio di magazzino e nessun trasporto ne
# preleva. Salvata da GameSaveService ("toolkit"), vuota per i save precedenti. Alla demolizione e con "Svuota tutto"
# finisce a terra con il magazzino (GroundPileService.drop_building_contents).
#
# Uso nella produzione (ProduceAction): ogni categoria richiesta dalla ricetta si cerca prima qui (covers / find_tool_for)
# e solo dopo sul pipottino; l'uso si consuma qui sul pezzo più usato (consume_use), a zero usi il pezzo sparisce.
# Nessun blocco tra due lavoratori che usano lo stesso attrezzo. Stateless, funzioni statiche.


static func has_toolkit(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.toolkit_tool_types > 0 		and building.rules.toolkit_units_per_type > 0


# Danneggiato (2026-10-10): posti (tipi di attrezzo) a metà; gli attrezzi già dentro restano.
static func get_type_capacity(building: Building) -> int:
	return building.get_effective_capacity(maxi(building.rules.toolkit_tool_types, 0)) if has_toolkit(building) else 0


static func get_units_per_type(building: Building) -> int:
	return maxi(building.rules.toolkit_units_per_type, 0) if has_toolkit(building) else 0


static func get_quantity(building: Building, tool_name: String) -> int:
	if building == null:
		return 0
	return int((building.toolkit.get(tool_name, {}) as Dictionary).get("quantity", 0))


# Nomi degli attrezzi presenti (ordine di inserimento).
static func get_tool_names(building: Building) -> Array[String]:
	var names: Array[String] = []
	if building == null:
		return names
	for tool_name in building.toolkit.keys():
		if get_quantity(building, String(tool_name)) > 0:
			names.append(String(tool_name))
	return names


# Usi rimasti di ogni pezzo del tipo (i nuovi a usi pieni), dal più usato.
static func get_remaining_uses_list(building: Building, tool_name: String) -> Array[int]:
	var uses: Array[int] = []
	var entry: Dictionary = building.toolkit.get(tool_name, {}) if building != null else {}
	var used_instances := ToolInstance.get_used_instances(entry)
	for instance in used_instances:
		uses.append(ToolInstance.get_remaining_uses(instance))
	var max_uses := ToolInstance.get_max_uses(tool_name)
	for i in range(maxi(int(entry.get("quantity", 0)) - used_instances.size(), 0)):
		uses.append(max_uses)
	uses.sort()
	return uses


# Regola (2026-10-08, richiesta utente): nell'Attrezzeria vanno solo gli attrezzi che servono alle ricette dell'edificio,
# cioè con almeno una categoria d'uso (SecondaryResourceRules.tool_categories) richiesta da una ricetta che elenca il
# suo tipo (recipe_required_tool_categories). Armi e attrezzi che nessuna sua ricetta usa restano fuori. Controllata da
# can_add, quindi vale per ogni strada (spunta "Tieni per l'edificio", fine pezzo, spostamento a mano dal pannello).
static func is_accepted_tool(building: Building, tool_name: String) -> bool:
	if not has_toolkit(building) or not ToolInstance.is_tool_resource(tool_name):
		return false
	var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
	if rules == null:
		return false
	var needed := get_recipe_tool_categories(building)
	for category in rules.tool_categories:
		if needed.has(int(category)):
			return true
	return false


# Categorie d'attrezzo richieste dalle ricette che elencano il tipo di `building` (int, senza doppioni).
static func get_recipe_tool_categories(building: Building) -> Array[int]:
	var categories: Array[int] = []
	if building == null:
		return categories
	for recipe_name in CaloricCalculator.list_secondary_resource_names():
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe_name)
		if recipe_rules == null or not recipe_rules.recipe_workstation_types.has(building.building_type_name):
			continue
		for category in recipe_rules.recipe_required_tool_categories:
			if not categories.has(int(category)):
				categories.append(int(category))
	return categories


# true se c'è posto per un pezzo di `tool_name`: è un attrezzo che serve alle ricette dell'edificio (is_accepted_tool),
# il suo tipo ha meno pezzi del massimo, oppure è un tipo nuovo e l'Attrezzeria ha ancora un tipo libero.
static func can_add(building: Building, tool_name: String) -> bool:
	if not is_accepted_tool(building, tool_name):
		return false
	var quantity := get_quantity(building, tool_name)
	if quantity > 0:
		return quantity < get_units_per_type(building)
	return get_tool_names(building).size() < get_type_capacity(building)


# Pezzi di `tool_name` che l'Attrezzeria può ancora ricevere (2026-10-08, avviso dell'ordine nel pannello): posti liberi
# del suo tipo se è già presente, un tipo intero se c'è un tipo libero, altrimenti 0 (0 anche se non è un attrezzo).
static func get_free_units_for(building: Building, tool_name: String) -> int:
	if not is_accepted_tool(building, tool_name):
		return 0
	var quantity := get_quantity(building, tool_name)
	if quantity > 0:
		return maxi(get_units_per_type(building) - quantity, 0)
	return get_units_per_type(building) if get_tool_names(building).size() < get_type_capacity(building) else 0


# Aggiunge un pezzo (istanza; usi pieni = pezzo nuovo). false se non c'è posto o il pezzo è rotto.
static func add_unit(building: Building, tool_name: String, instance: Dictionary) -> bool:
	if not can_add(building, tool_name):
		return false
	var max_uses := ToolInstance.get_max_uses(tool_name)
	var entry: Dictionary = (building.toolkit.get(tool_name, {}) as Dictionary).duplicate(true)
	if ToolInstance.is_full(instance, max_uses):
		entry["quantity"] = int(entry.get("quantity", 0)) + 1
	elif ToolInstance.is_usable(instance):
		ToolInstance.add_instance_to_entry(entry, instance)
	else:
		return false
	building.toolkit[tool_name] = entry
	return true


# Toglie un pezzo (il più usato per primo) e lo restituisce come istanza; {} se non ce ne sono.
static func take_unit(building: Building, tool_name: String) -> Dictionary:
	if building == null or get_quantity(building, tool_name) <= 0:
		return {}
	var entry: Dictionary = (building.toolkit[tool_name] as Dictionary).duplicate(true)
	var units := ToolInstance.take_units_from_entry(entry, 1, ToolInstance.get_max_uses(tool_name))
	_write_entry(building, tool_name, entry)
	return units[0] if not units.is_empty() else {}


# Toglie il pezzo MENO usato (un pezzo nuovo se c'è, altrimenti l'istanza con più usi rimasti), così l'edificio continua
# a consumare quello già iniziato (2026-10-04 — rimessa in magazzino dal pannello). {} se non ce ne sono.
static func take_least_used_unit(building: Building, tool_name: String) -> Dictionary:
	var quantity := get_quantity(building, tool_name)
	if quantity <= 0:
		return {}
	var entry: Dictionary = (building.toolkit[tool_name] as Dictionary).duplicate(true)
	var used_instances: Array = ToolInstance.get_used_instances(entry).duplicate()
	var instance: Dictionary = {}
	if quantity > used_instances.size():
		instance = ToolInstance.create(ToolInstance.get_max_uses(tool_name))
	else:
		var best_index := 0
		for i in range(used_instances.size()):
			if ToolInstance.get_remaining_uses(used_instances[i]) > ToolInstance.get_remaining_uses(used_instances[best_index]):
				best_index = i
		instance = ToolInstance.normalized(used_instances[best_index])
		used_instances.remove_at(best_index)
		ToolInstance.set_used_instances(entry, used_instances)
	entry["quantity"] = quantity - 1
	_write_entry(building, tool_name, entry)
	return instance


# Rimette un pezzo appena tolto (annullo di uno spostamento fallito): senza controlli di posto.
static func put_back_unit(building: Building, tool_name: String, instance: Dictionary) -> void:
	var entry: Dictionary = (building.toolkit.get(tool_name, {}) as Dictionary).duplicate(true)
	if ToolInstance.is_full(instance, ToolInstance.get_max_uses(tool_name)):
		entry["quantity"] = int(entry.get("quantity", 0)) + 1
	else:
		ToolInstance.add_instance_to_entry(entry, instance)
	building.toolkit[tool_name] = entry


# Attrezzo dell'Attrezzeria che copre `category` ("" se nessuno): quello con il pezzo più usato.
static func find_tool_for(building: Building, category: TaskTypes.ToolCategory) -> String:
	var best_name := ""
	var best_uses := 1 << 30
	for tool_name in get_tool_names(building):
		var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
		if rules == null or not rules.tool_categories.has(category):
			continue
		var uses := get_remaining_uses_list(building, tool_name)
		var lowest: int = uses[0] if not uses.is_empty() else best_uses
		if lowest < best_uses:
			best_uses = lowest
			best_name = tool_name
	return best_name


static func covers(building: Building, category: TaskTypes.ToolCategory) -> bool:
	return find_tool_for(building, category) != ""


# Categorie di `required` che l'Attrezzeria NON copre (quelle da cercare sul pipottino).
static func filter_uncovered(building: Building, required: Array[TaskTypes.ToolCategory]) -> Array[TaskTypes.ToolCategory]:
	var remaining: Array[TaskTypes.ToolCategory] = []
	for category in required:
		if not covers(building, category):
			remaining.append(category)
	return remaining


# Consuma un uso sul pezzo più usato di `tool_name` (un pezzo nuovo diventa un'istanza a usi pieni meno uno). A zero
# usi il pezzo sparisce. Ritorna true se il pezzo si è rotto. Attrezzo che non si usura (max_uses <= 0): nessun effetto.
static func consume_use(building: Building, tool_name: String) -> bool:
	var max_uses := ToolInstance.get_max_uses(tool_name)
	if max_uses <= 0 or get_quantity(building, tool_name) <= 0:
		return false
	var instance := take_unit(building, tool_name)
	if instance.is_empty():
		return false
	var remaining := ToolInstance.get_remaining_uses(instance) - 1
	if remaining <= 0:
		return true
	put_back_unit(building, tool_name, ToolInstance.create(remaining))
	return false


static func _write_entry(building: Building, tool_name: String, entry: Dictionary) -> void:
	if int(entry.get("quantity", 0)) <= 0:
		building.toolkit.erase(tool_name)
	else:
		building.toolkit[tool_name] = entry


# Contenuto letto da un salvataggio: solo attrezzi, quantità positive, istanze utilizzabili (come il magazzino).
static func load_toolkit(raw: Dictionary) -> Dictionary:
	var toolkit: Dictionary = {}
	for raw_name in raw.keys():
		var tool_name := String(raw_name)
		var raw_entry: Variant = raw[raw_name]
		if not (raw_entry is Dictionary) or not ToolInstance.is_tool_resource(tool_name):
			continue
		var quantity := int((raw_entry as Dictionary).get("quantity", 0))
		if quantity <= 0:
			continue
		var used: Array = []
		for instance in ToolInstance.get_used_instances(raw_entry):
			if instance is Dictionary and ToolInstance.is_usable(instance) and used.size() < quantity:
				used.append(ToolInstance.normalized(instance))
		var entry := {"quantity": quantity}
		ToolInstance.set_used_instances(entry, used)
		toolkit[tool_name] = entry
	return toolkit
