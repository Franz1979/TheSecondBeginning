class_name StorageContainerService
extends RefCounted

# Risorse tenute nei contenitori dell'Attrezzeria (2026-11-13, richiesta utente — vasi da semi, punto 1d). Una risorsa
# con SecondaryResourceRules.stored_in_container (es. wild_seeds -> "seed_jar") entra in un magazzino solo fino alla
# capienza dei contenitori MONTATI nella sua Attrezzeria (pezzi × seed_capacity del contenitore), e lì non occupa slot né
# spazio: lo spazio è quello dei contenitori. La capienza è condivisa da tutte le risorse dello stesso contenitore.
# La quantità resta in Building.stored_resources come ogni altra risorsa (prelievi, scorte, deperimento invariati).
# Usura: ogni misura che entra o esce consuma un uso del contenitore più consumato (BuildingToolkitService.consume_use);
# un contenitore che si rompe abbassa la capienza e le misure in più si perdono (trim_overflow).
# Un contenitore, una risorsa (2026-11-15, richiesta utente): ogni risorsa occupa contenitori interi (units_used).
# Stateless, funzioni statiche.


static func container_of(resource_name: String) -> String:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules.stored_in_container if rules != null else ""


static func is_container_resource(resource_name: String) -> bool:
	return container_of(resource_name) != ""


# Granaglie sfuse (2026-11-15, Casa delle granaglie — BuildingRules.loose_categories): in `building` la categoria della
# risorsa sta sfusa negli slot, non nei contenitori.
static func is_loose_in(building: Building, resource_rules: SecondaryResourceRules) -> bool:
	return building != null and building.rules != null and resource_rules != null and not resource_rules.always_in_container \
		and building.rules.loose_categories.has(int(resource_rules.category))


# true se in `building` la risorsa sta nei contenitori dell'Attrezzeria (ha un contenitore e lì non è sfusa).
static func uses_container(building: Building, resource_rules: SecondaryResourceRules) -> bool:
	return resource_rules != null and resource_rules.stored_in_container != "" and not is_loose_in(building, resource_rules)


# Stessa cosa per nome, ristretta al contenitore `container`.
static func _held_in(building: Building, resource_name: String, container: String) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules != null and rules.stored_in_container == container and not is_loose_in(building, rules)


# Misure che tiene un pezzo del contenitore (0 = non è un contenitore).
static func unit_capacity(container: String) -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(container)
	return maxi(rules.seed_capacity, 0) if rules != null else 0


static func capacity_of(building: Building, container: String) -> int:
	if building == null or container == "":
		return 0
	return BuildingToolkitService.get_quantity(building, container) * unit_capacity(container)


# Misure presenti nel magazzino di `building` di tutte le risorse tenute in `container`.
static func stored_in(building: Building, container: String) -> int:
	var total := 0
	if building == null or container == "":
		return 0
	for resource_name in building.stored_resources.keys():
		if _held_in(building, String(resource_name), container):
			total += int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0))
	return total


# Contenitori interi occupati da `quantity` misure (un contenitore, una risorsa — 2026-11-15, richiesta utente: orzo e
# grano selvatici non si mischiano; nessun contenuto per pezzo, è un calcolo sulle quantità).
static func units_for(quantity: int, container: String) -> int:
	var per_unit := unit_capacity(container)
	if per_unit <= 0 or quantity <= 0:
		return 0
	return ceili(float(quantity) / float(per_unit))


# Contenitori occupati da tutte le risorse di `container` nel magazzino, esclusa `except_resource` ("" = nessuna).
static func units_used(building: Building, container: String, except_resource: String = "") -> int:
	var total := 0
	if building == null or container == "":
		return 0
	for resource_name in building.stored_resources.keys():
		if String(resource_name) == except_resource or not _held_in(building, String(resource_name), container):
			continue
		total += units_for(int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0)), container)
	return total


# Misure di `resource_name` che il magazzino può ancora ricevere: il resto del suo contenitore non pieno più i contenitori
# liberi (un contenitore, una risorsa).
static func room(building: Building, resource_name: String) -> int:
	var container := container_of(resource_name)
	if building == null or container == "" or is_loose_in(building, CaloricCalculator.get_caloric_source_rules(resource_name)):
		return 0
	var own := 0
	if building.stored_resources.has(resource_name):
		own = int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0))
	var free_units := BuildingToolkitService.get_quantity(building, container) - units_used(building, container, resource_name)
	return maxi(free_units * unit_capacity(container) - own, 0)


# true se almeno un magazzino in funzione del mondo ha posto nei contenitori per `resource_name` (raccolta: niente
# raccolta oltre lo spazio nei vasi, HaulZoneService.work_area_accepts).
static func village_has_room(resource_name: String) -> bool:
	var world := GameSettings.active_world
	if world == null:
		return false
	for building in world.buildings:
		if building.is_demolished or not building.is_complete or building.is_out_of_service():
			continue
		# Casa delle granaglie (2026-11-15): dove la risorsa sta sfusa conta il posto negli slot.
		var free := BuildingStorageService.get_max_depositable(building, resource_name) \
			if is_loose_in(building, CaloricCalculator.get_caloric_source_rules(resource_name)) else room(building, resource_name)
		if free > 0 and BuildingStorageService.can_accept(building, resource_name):
			return true
	return false


# Motivo per cui `resource_name` non si raccoglie (nessun posto nei contenitori montati): popup della raccolta a mano e X
# rossa degli ordini di raccolta (2026-11-13, richiesta utente: la regola va detta).
static func no_room_reason(resource_name: String) -> String:
	return TranslationServer.translate("container_no_room_reason").format({
		"resource": IconRegistry.get_resource_display_name(resource_name),
		"container": IconRegistry.get_resource_display_name(container_of(resource_name)),
	})


# Usura per `amount` misure entrate o uscite di `resource_name`. Se un contenitore si rompe, le misure oltre la nuova
# capienza si perdono.
static func wear(building: Building, resource_name: String, amount: int) -> void:
	var container := container_of(resource_name)
	if building == null or container == "" or amount <= 0 \
			or is_loose_in(building, CaloricCalculator.get_caloric_source_rules(resource_name)):
		return
	var broke := 0
	for i in range(amount):
		if BuildingToolkitService.get_quantity(building, container) <= 0:
			break
		if BuildingToolkitService.consume_use(building, container):
			broke += 1
	if broke > 0:
		var lost := trim_overflow(building, container)
		if DebugLogging.ENABLED:
			print("[SEED JAR] %s #%d: %d %s rotti, %d misure perse." % [building.building_type_name, building.id, broke, container, lost])


# Toglie le misure che non stanno più nei contenitori montati (un contenitore, una risorsa, 2026-11-15): finché le risorse
# occupano più contenitori di quelli montati, svuota il contenitore meno pieno (l'ultimo, parziale, della risorsa che lì ne
# ha meno). Ritorna quante misure ha tolto.
static func trim_overflow(building: Building, container: String) -> int:
	var per_unit := unit_capacity(container)
	var lost := 0
	if building == null or per_unit <= 0:
		return 0
	var mounted := BuildingToolkitService.get_quantity(building, container)
	while units_used(building, container) > mounted:
		var emptiest := ""
		var emptiest_amount := per_unit + 1
		for resource_name in building.stored_resources.keys():
			if not _held_in(building, String(resource_name), container):
				continue
			var quantity := int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0))
			if quantity <= 0:
				continue
			var last_unit := quantity % per_unit
			if last_unit == 0:
				last_unit = per_unit
			if last_unit < emptiest_amount:
				emptiest_amount = last_unit
				emptiest = String(resource_name)
		if emptiest == "":
			break
		var entry: Dictionary = (building.stored_resources[emptiest] as Dictionary).duplicate(true)
		var remaining := int(entry.get("quantity", 0)) - emptiest_amount
		if remaining <= 0:
			building.stored_resources.erase(emptiest)
		else:
			entry["quantity"] = remaining
			building.stored_resources[emptiest] = entry
		lost += emptiest_amount
	return lost


# true se il magazzino accetta (filtri di categoria del tipo e dell'istanza) almeno una risorsa tenuta in `container`
# (2026-11-13, richiesta utente: un magazzino che non accetta i Materiali grezzi non accetta nemmeno i vasi da semi; dal 2026-11-15 i semi sono
# Granaglie, la regola è la stessa con la loro categoria).
# true per un attrezzo che non è un contenitore.
static func building_accepts_contents(building: Building, container: String) -> bool:
	if unit_capacity(container) <= 0:
		return true
	if building == null or building.rules == null:
		return false
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules != null and rules.stored_in_container == container \
				and BuildingStorageService._free_storage_allows(building, resource_name, rules):
			return true
	return false


# true se togliere un pezzo di `container` dall'Attrezzeria farebbe perdere misure (il giocatore deve prima prelevarle).
static func blocks_removal(building: Building, container: String) -> bool:
	var per_unit := unit_capacity(container)
	if building == null or per_unit <= 0:
		return false
	# Un contenitore, una risorsa (2026-11-15): conta i contenitori occupati, non le misure.
	return units_used(building, container) > BuildingToolkitService.get_quantity(building, container) - 1


# true se il TIPO di `building` può tenere almeno una risorsa di `category` (2026-11-15, richiesta utente — spunta Granaglie
# nel Sito di deposito): una risorsa senza contenitore basta; una nei contenitori conta solo se l'Attrezzeria del tipo
# elenca quel contenitore (toolkit_extra_tools). Non guarda il filtro per istanza (enabled_categories), sennò togliere la
# spunta la farebbe sparire. Categoria senza risorse = true (comportamento di prima).
static func type_can_hold_category(building: Building, category: int) -> bool:
	if building == null or building.rules == null:
		return false
	if building.rules.loose_categories.has(category):
		return true
	var found := false
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null or int(rules.category) != category:
			continue
		found = true
		if rules.stored_in_container == "" or (BuildingToolkitService.has_toolkit(building)
				and building.rules.toolkit_extra_tools.has(rules.stored_in_container)):
			return true
	return not found
