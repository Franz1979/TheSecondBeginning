class_name ButcherDestinationService
extends RefCounted

# Destinazione dei prodotti della macellazione (2026-10-03, richiesta utente — essiccazione passo 4; dal 2026-10-19 due
# scelte separate, carne e pelli). Stateless (RefCounted, static), stesso pattern degli altri *Service.
#
# La scelta viaggia come UNA stringa nel context delle Task, sotto CONTEXT_KEY (salvata con la Task):
#   - caccia (diretta: GameScene._try_assign_hunt_command_on_right_click, con l'ultima scelta; nelle zone: dalla serie
#     di cacce, HuntZoneService.make_meat_series, scritta dal dialog; ordini del gestore scorte) ->
#   - richiesta di macellazione (HumanIndividualActionService._handle_pending_hunt_butcher la copia nella carcassa) ->
#   - Task di macellazione (TaskBuilderService.build_butcher_task) -> ricerca della destinazione dopo ogni raccolta
#     (_search_warehouse_for_resource, _has_butcher_product_destination) e ritorno del carico (CargoReturnService).
# Formato (2026-10-19): "pair:<carne>:<pelli>" (compose/parse), con ":auto" in fondo per le cacce del gestore scorte
# (HuntProductAllocationService: prima si coprono i minimi, poi la coppia vale per ciò che avanza). <carne>/<pelli> sono
# uno dei TARGETS (magazzino, focolare, essiccatoio, affumicatoio). I valori di prima (una voce sola, es.
# "drying_rack_meat") si leggono ancora: parse li traduce nella coppia equivalente (LEGACY_PAIRS). Una Task senza la chiave
# ma con il vecchio HumanIndividualActionService.CONTEXT_PREFER_RECIPE_WORKSTATION vale focolare per la carne.
#
# Tipo di risorsa (resource_kind): "carne" = ingrediente di ricette che producono cibo (la carne: anche
# prefers_recipe_workstation, il focolare); "pelli" = ingrediente non-cibo delle postazioni di lavorazione (la pelle);
# tutto il resto (ossa, tendini) va sempre al magazzino. Una risorsa va al suo target (target_for) solo se è davvero
# ingrediente delle ricette di quell'edificio, altrimenti al magazzino.
# Lo scarico alla postazione scelta per preferenza deposita solo quelle risorse (UnloadAction.only_preferred_resources),
# in ordine di day_durability crescente; il residuo segue il re-routing normale.

const CONTEXT_KEY := "butcher_destination"

const CAMPFIRE := "campfire"
const DRYING_RACK := "drying_rack"
const SMOKEHOUSE := "smokehouse"
const WAREHOUSE := "warehouse"

const KIND_MEAT := "meat"
const KIND_HIDE := "hide"

const PAIR_PREFIX := "pair"
const AUTO_SUFFIX := "auto"

# Destinazioni scelte per tipo di risorsa, in ordine di menu.
const MEAT_TARGETS: Array[String] = [CAMPFIRE, DRYING_RACK, SMOKEHOUSE, WAREHOUSE]
const HIDE_TARGETS: Array[String] = [DRYING_RACK, SMOKEHOUSE, WAREHOUSE]
# Tipo di edificio di ogni destinazione (icona, idea richiesta, esistenza di un edificio completo).
const BUILDING_TYPES := {
	CAMPFIRE: "campfire",
	DRYING_RACK: "drying_rack",
	SMOKEHOUSE: "smokehouse",
	WAREHOUSE: "deposit_site",
}
# Chiavi tr() dei nomi delle destinazioni.
const NAME_KEYS := {
	CAMPFIRE: "hunt_destination_campfire",
	DRYING_RACK: "hunt_destination_drying_rack",
	SMOKEHOUSE: "hunt_destination_smokehouse",
	WAREHOUSE: "hunt_destination_warehouse",
}
# Destinazioni sempre disabilitate per ora (lucchetto, "Non ancora disponibile"). Il meccanismo resta per il futuro.
const NOT_YET_AVAILABLE: Array[String] = []
# Postazioni di lavorazione: ricevono gli ingredienti materiali delle proprie ricette.
const PROCESSING_TARGETS: Array[String] = [DRYING_RACK, SMOKEHOUSE]
# Valori di prima del 2026-10-19 (una voce per tutta la carcassa) -> [carne, pelli].
const LEGACY_PAIRS := {
	"campfire": [CAMPFIRE, WAREHOUSE],
	"drying_rack": [DRYING_RACK, DRYING_RACK],
	"drying_rack_meat": [DRYING_RACK, WAREHOUSE],
	"drying_rack_hide": [WAREHOUSE, DRYING_RACK],
	"smokehouse": [SMOKEHOUSE, SMOKEHOUSE],
	"smokehouse_meat": [SMOKEHOUSE, WAREHOUSE],
	"smokehouse_hide": [WAREHOUSE, SMOKEHOUSE],
	"warehouse": [WAREHOUSE, WAREHOUSE],
}

# Tipo per nome di risorsa, calcolato una volta (le ricette non cambiano durante la partita).
static var _kind_cache: Dictionary = {}


# --- Coppia carne/pelli ---

static func compose(meat_target: String, hide_target: String, auto: bool = false) -> String:
	var value := "%s:%s:%s" % [PAIR_PREFIX, meat_target, hide_target]
	return value + ":" + AUTO_SUFFIX if auto else value


# {"meat", "hide", "auto"} da un valore salvato (coppia o voce di prima). Vuoto o sconosciuto = magazzino.
static func parse(destination: String) -> Dictionary:
	var parts := destination.split(":")
	if parts.size() >= 3 and parts[0] == PAIR_PREFIX:
		return {
			KIND_MEAT: parts[1] if MEAT_TARGETS.has(parts[1]) else WAREHOUSE,
			KIND_HIDE: parts[2] if HIDE_TARGETS.has(parts[2]) else WAREHOUSE,
			"auto": parts.size() >= 4 and parts[3] == AUTO_SUFFIX,
		}
	var legacy: Array = LEGACY_PAIRS.get(destination, [WAREHOUSE, WAREHOUSE])
	return {KIND_MEAT: String(legacy[0]), KIND_HIDE: String(legacy[1]), "auto": false}


static func is_auto(destination: String) -> bool:
	return bool(parse(destination)["auto"])


# Destinazione scritta nel context di una Task (vedi testa del file per i default).
static func get_destination(context: Dictionary) -> String:
	if context.has(CONTEXT_KEY):
		return String(context[CONTEXT_KEY])
	if bool(context.get(HumanIndividualActionService.CONTEXT_PREFER_RECIPE_WORKSTATION, false)):
		return compose(CAMPFIRE, WAREHOUSE)
	return compose(WAREHOUSE, WAREHOUSE)


# "meat", "hide" o "" (ossa, tendini, tutto il resto: sempre al magazzino).
static func resource_kind(resource_name: String) -> String:
	if _kind_cache.has(resource_name):
		return String(_kind_cache[resource_name])
	var kind := ""
	if WarehouseSelectionService.prefers_recipe_workstation(resource_name):
		kind = KIND_MEAT
	else:
		for recipe_name in CaloricCalculator.list_secondary_resource_names():
			var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe_name)
			if recipe_rules == null or not recipe_rules.recipe_inputs.has(resource_name):
				continue
			var at_processing := false
			for target in PROCESSING_TARGETS:
				if recipe_rules.recipe_workstation_types.has(String(BUILDING_TYPES[target])):
					at_processing = true
			if not at_processing:
				continue
			if recipe_rules.category == SecondaryResourceTypes.Category.FOOD:
				kind = KIND_MEAT
				break
			kind = KIND_HIDE
	_kind_cache[resource_name] = kind
	return kind


# Destinazione di `resource_name` secondo `destination` (la scelta del suo tipo), oppure WAREHOUSE se la risorsa non ha
# un tipo o non è ingrediente delle ricette dell'edificio scelto.
static func target_for(destination: String, resource_name: String) -> String:
	var kind := resource_kind(resource_name)
	if kind == "":
		return WAREHOUSE
	var target := String(parse(destination)[kind])
	return target if accepts_resource(target, resource_name) else WAREHOUSE


# true se l'edificio `target` riceve `resource_name` per preferenza: il focolare la carne (prefers_recipe_workstation), le
# postazioni di lavorazione gli ingredienti materiali delle loro ricette (mai il combustibile), il magazzino tutto.
static func accepts_resource(target: String, resource_name: String) -> bool:
	if target == WAREHOUSE:
		return true
	if target == CAMPFIRE:
		return WarehouseSelectionService.prefers_recipe_workstation(resource_name)
	if not PROCESSING_TARGETS.has(target):
		return false
	var building_type := String(BUILDING_TYPES[target])
	for recipe_name in CaloricCalculator.list_secondary_resource_names():
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe_name)
		if recipe_rules != null and recipe_rules.recipe_workstation_types.has(building_type) \
				and recipe_rules.recipe_inputs.has(resource_name):
			return true
	return false


# Edificio a cui portare `resource_name` per preferenza della destinazione, prima del magazzino: null se la
# destinazione manda la risorsa al magazzino o nessun edificio adatto ne accetta almeno `min_quantity`.
static func find_preferred_building(
	world: World, origin_position: Vector2, origin_macro_coords: Vector2i, resource_name: String, destination: String,
	min_quantity: int = 1, excluded_building_ids: Array[int] = [], reachable: Callable = Callable()
) -> Building:
	return find_target_building(
		world, origin_position, origin_macro_coords, resource_name, target_for(destination, resource_name), min_quantity,
		excluded_building_ids, reachable
	)


# Edificio più vicino del tipo di `target` che accetta almeno `min_quantity` di `resource_name`; null per il magazzino
# (lo sceglie WarehouseSelectionService.find_best) o se nessuno ha posto.
static func find_target_building(
	world: World, origin_position: Vector2, origin_macro_coords: Vector2i, resource_name: String, target: String,
	min_quantity: int = 1, excluded_building_ids: Array[int] = [], reachable: Callable = Callable()
) -> Building:
	if world == null or target == WAREHOUSE or not accepts_resource(target, resource_name):
		return null
	if target == CAMPFIRE:
		# Solo focolari (2026-10-03): la carne è ingrediente anche all'affumicatoio, che non va scelto qui.
		return WarehouseSelectionService.find_nearest_recipe_workstation(
			world, origin_position, origin_macro_coords, resource_name, min_quantity, excluded_building_ids, reachable,
			String(BUILDING_TYPES[CAMPFIRE])
		)
	return _find_nearest_processing_station(
		world, origin_position, origin_macro_coords, resource_name, String(BUILDING_TYPES[target]),
		min_quantity, excluded_building_ids, reachable
	)


# true se `destination` manda `resource_name` a una postazione di lavorazione (avviso "postazione piena").
static func is_processing_resource(destination: String, resource_name: String) -> bool:
	return PROCESSING_TARGETS.has(target_for(destination, resource_name))


# true se uno scarico riservato alle risorse preferite (UnloadAction.only_preferred_resources) può lasciare
# `resource_name` in `building`: l'edificio è proprio quello che `task_destination` sceglie per la risorsa.
# `task_destination` "" (scarichi salvati prima del 2026-10-13): alla postazione di lavorazione i suoi ingredienti, al
# focolare la carne, come allora.
static func is_preferred_deposit_allowed(building: Building, resource_name: String, task_destination: String = "") -> bool:
	if building == null:
		return false
	if task_destination != "":
		var target := target_for(task_destination, resource_name)
		return target != WAREHOUSE and building.building_type_name == String(BUILDING_TYPES[target])
	for target in PROCESSING_TARGETS:
		if building.building_type_name == String(BUILDING_TYPES[target]):
			return accepts_resource(target, resource_name)
	return WarehouseSelectionService.prefers_recipe_workstation(resource_name)


# Postazione di tipo `building_type` più vicina, completa e non da demolire, che accetta almeno `min_quantity` unità di
# `resource_name` (il chiamante ha già verificato che è un suo ingrediente, accepts_resource).
static func _find_nearest_processing_station(
	world: World, origin_position: Vector2, origin_macro_coords: Vector2i, resource_name: String, building_type: String,
	min_quantity: int, excluded_building_ids: Array[int], reachable: Callable
) -> Building:
	var predicate := func(building: Building) -> bool:
		return building.building_type_name == building_type and building.is_complete and not building.is_demolished \
			and not building.is_out_of_service() \
			and BuildingStorageService.can_accept(building, resource_name) \
			and BuildingStorageService.get_max_depositable(building, resource_name) >= min_quantity
	return SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, predicate, excluded_building_ids, reachable
	) as Building


# Nomi ordinati per day_durability crescente (chi deperisce prima per primo); -1 (non deperisce) in fondo, a parità per
# nome. Copia: non tocca l'array ricevuto.
static func sort_by_shortest_durability(resource_names: Array) -> Array:
	var sorted := resource_names.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		var durability_a := _durability_for_sort(String(a))
		var durability_b := _durability_for_sort(String(b))
		if durability_a != durability_b:
			return durability_a < durability_b
		return String(a) < String(b)
	)
	return sorted


static func _durability_for_sort(resource_name: String) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null or rules.day_durability < 0:
		return INF
	return float(rules.day_durability)


# --- Disponibilità delle destinazioni (per edificio) ---

# "" se `target` si può scegliere, altrimenti il motivo già tradotto (tooltip): non ancora disponibile, idea
# dell'edificio non scoperta, o nessun edificio di quel tipo completo e non da demolire. Il magazzino è sempre disponibile.
static func get_unavailable_reason(target: String, world: World, folk: Folk) -> String:
	if target == WAREHOUSE:
		return ""
	if NOT_YET_AVAILABLE.has(target):
		return TranslationServer.translate("hunt_destination_not_yet_available")
	var building_type := String(BUILDING_TYPES.get(target, ""))
	var rules := BuildingCalculator.get_building_rules(building_type)
	if rules != null and rules.required_idea_id != "" and (folk == null or not folk.completed_ideas.has(rules.required_idea_id)):
		var idea := IdeaCalculator.get_idea(rules.required_idea_id)
		var idea_name: String = TranslationServer.translate(idea.display_name) if idea != null else rules.required_idea_id
		return TranslationServer.translate("hunt_destination_requires_idea").format({"idea": idea_name})
	if not _has_complete_building(world, building_type):
		return TranslationServer.translate("hunt_destination_no_building").format({
			"building": TranslationServer.translate(rules.building_name if rules != null else String(NAME_KEYS.get(target, ""))).to_lower(),
		})
	return ""


static func is_available(target: String, world: World, folk: Folk) -> bool:
	return get_unavailable_reason(target, world, folk) == ""


# true se oltre al focolare c'è almeno una postazione di lavorazione disponibile (oggi l'essiccatoio): solo allora la
# barra dei comandi mostra il pulsante della destinazione (2026-10-03).
static func has_alternative_processing_destination(world: World, folk: Folk) -> bool:
	for target in PROCESSING_TARGETS:
		if is_available(target, world, folk):
			return true
	return false


# Coppia proposta (e usata dalla caccia diretta): per ciascun tipo l'ultima scelta se è ancora disponibile, altrimenti il
# focolare per la carne e il magazzino per le pelli (poi il magazzino).
static func resolve_default(last_destination: String, world: World, folk: Folk) -> String:
	var last := parse(last_destination) if last_destination != "" else {KIND_MEAT: CAMPFIRE, KIND_HIDE: WAREHOUSE, "auto": false}
	var meat := String(last[KIND_MEAT])
	if not is_available(meat, world, folk):
		meat = CAMPFIRE if is_available(CAMPFIRE, world, folk) else WAREHOUSE
	var hide := String(last[KIND_HIDE])
	if not is_available(hide, world, folk):
		hide = WAREHOUSE
	return compose(meat, hide)


# Coppia per le cacce del gestore scorte (destinazione di ciò che non serve ai minimi): la scelta salvata, con le parti non
# più disponibili sul magazzino, e il segno ":auto".
static func resolve_stock(stock_destination: String, world: World, folk: Folk) -> String:
	var pair := parse(stock_destination)
	var meat := String(pair[KIND_MEAT]) if is_available(String(pair[KIND_MEAT]), world, folk) else WAREHOUSE
	var hide := String(pair[KIND_HIDE]) if is_available(String(pair[KIND_HIDE]), world, folk) else WAREHOUSE
	return compose(meat, hide, true)


static func _has_complete_building(world: World, building_type: String) -> bool:
	if world == null:
		return false
	for building in world.buildings:
		if building.building_type_name == building_type and building.is_complete and not building.is_demolished \
				and not building.is_out_of_service():
			return true
	return false
