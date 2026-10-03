class_name ButcherDestinationService
extends RefCounted

# Destinazione dei prodotti della macellazione scelta dal giocatore nell'ordine di caccia (2026-10-03, richiesta
# utente — essiccazione passo 4). Stateless (RefCounted, static), stesso pattern degli altri *Service.
#
# La scelta viaggia come stringa nel context delle Task, sotto CONTEXT_KEY (salvato con la Task):
#   - caccia (diretta: GameScene._try_assign_hunt_command_on_right_click, con l'ultima scelta; nelle zone: dalla serie
#     di cacce, HuntZoneService.make_meat_series, scritta dal dialog) ->
#   - richiesta di macellazione (HumanIndividualActionService._handle_pending_hunt_butcher la copia nella carcassa) ->
#   - Task di macellazione (GameScene._build_butcher_task) -> ricerca della destinazione dopo ogni raccolta
#     (_search_warehouse_for_resource, _has_butcher_product_destination) e ritorno del carico (CargoReturnService).
# Una Task senza la chiave ma con il vecchio HumanIndividualActionService.CONTEXT_PREFER_RECIPE_WORKSTATION (salvataggi
# precedenti) vale CAMPFIRE; senza nessuna delle due, WAREHOUSE (nessuna preferenza, il comportamento di ogni altra
# raccolta).
#
# Scarico per destinazione:
#   - CAMPFIRE: come prima del 2026-10-03 — la carne (prefers_recipe_workstation) alla postazione più vicina che ne ha
#     una ricetta, il resto al magazzino;
#   - DRYING_RACK e SMOKEHOUSE ("postazioni di lavorazione", PROCESSING_DESTINATIONS — stessa logica, 2026-10-03): alla
#     postazione di quel tipo più vicina che ha posto le risorse che sono ingredienti materiali delle sue ricette
#     (recipe_inputs, mai il combustibile: is_processing_resource) — oggi carne e pelli —, il resto al magazzino. Nessuna
#     produzione parte da sola: all'essiccatoio le ricette avanzano da sé, all'affumicatoio la ordina il giocatore;
#   - WAREHOUSE: tutto al magazzino.
# Lo scarico alla postazione scelta per preferenza deposita solo quelle risorse (UnloadAction.only_preferred_resources),
# in ordine di day_durability crescente; il residuo segue il re-routing normale.

const CONTEXT_KEY := "butcher_destination"

const CAMPFIRE := "campfire"
const DRYING_RACK := "drying_rack"
const SMOKEHOUSE := "smokehouse"
const WAREHOUSE := "warehouse"

# Ordine delle opzioni nel dialog.
const ORDER: Array[String] = [CAMPFIRE, DRYING_RACK, SMOKEHOUSE, WAREHOUSE]
# Tipo di edificio di ogni destinazione (icona, idea richiesta, esistenza di un edificio completo).
const BUILDING_TYPES := {
	CAMPFIRE: "campfire",
	DRYING_RACK: "drying_rack",
	SMOKEHOUSE: "smokehouse",
	WAREHOUSE: "deposit_site",
}
# Chiavi tr() dei nomi delle opzioni.
const NAME_KEYS := {
	CAMPFIRE: "hunt_destination_campfire",
	DRYING_RACK: "hunt_destination_drying_rack",
	SMOKEHOUSE: "hunt_destination_smokehouse",
	WAREHOUSE: "hunt_destination_warehouse",
}
# Destinazioni sempre disabilitate per ora (lucchetto, "Non ancora disponibile"). Vuoto dal 2026-10-03 (affumicatoio
# acceso); il meccanismo resta per una destinazione futura.
const NOT_YET_AVAILABLE: Array[String] = []
# Postazioni di lavorazione (2026-10-03): ricevono gli ingredienti materiali delle proprie ricette, con la stessa logica.
const PROCESSING_DESTINATIONS: Array[String] = [DRYING_RACK, SMOKEHOUSE]


# Destinazione scritta nel context di una Task (vedi testa del file per i default).
static func get_destination(context: Dictionary) -> String:
	if context.has(CONTEXT_KEY):
		return String(context[CONTEXT_KEY])
	if bool(context.get(HumanIndividualActionService.CONTEXT_PREFER_RECIPE_WORKSTATION, false)):
		return CAMPFIRE
	return WAREHOUSE


# Edificio a cui portare `resource_name` per preferenza della destinazione, prima del magazzino: null se la
# destinazione non riguarda questa risorsa o nessun edificio adatto ne accetta almeno `min_quantity`.
static func find_preferred_building(
	world: World, origin_position: Vector2, origin_macro_coords: Vector2i, resource_name: String, destination: String,
	min_quantity: int = 1, excluded_building_ids: Array[int] = [], reachable: Callable = Callable()
) -> Building:
	if world == null:
		return null
	match destination:
		CAMPFIRE:
			if WarehouseSelectionService.prefers_recipe_workstation(resource_name):
				# Solo focolari (2026-10-03): la carne è ingrediente anche all'affumicatoio, che non va scelto qui.
				return WarehouseSelectionService.find_nearest_recipe_workstation(
					world, origin_position, origin_macro_coords, resource_name, min_quantity, excluded_building_ids, reachable,
					String(BUILDING_TYPES[CAMPFIRE])
				)
		DRYING_RACK, SMOKEHOUSE:
			if is_processing_resource(destination, resource_name):
				return _find_nearest_processing_station(
					world, origin_position, origin_macro_coords, resource_name, String(BUILDING_TYPES[destination]),
					min_quantity, excluded_building_ids, reachable
				)
	return null


# true se `resource_name` dovrebbe andare alla postazione di lavorazione `destination` (PROCESSING_DESTINATIONS):
# ingrediente materiale (recipe_inputs, non il combustibile) di una ricetta che elenca il tipo dell'edificio, ricette ad
# avanzamento automatico comprese. Per tipo, senza un edificio: serve anche quando nessuna postazione ha posto (avviso
# "pieno"). false per ogni altra destinazione.
static func is_processing_resource(destination: String, resource_name: String) -> bool:
	if not PROCESSING_DESTINATIONS.has(destination):
		return false
	var building_type := String(BUILDING_TYPES[destination])
	for recipe_name in CaloricCalculator.list_secondary_resource_names():
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe_name)
		if recipe_rules != null and recipe_rules.recipe_workstation_types.has(building_type) \
				and recipe_rules.recipe_inputs.has(resource_name):
			return true
	return false


# true se uno scarico riservato alle risorse preferite (UnloadAction.only_preferred_resources) può lasciare
# `resource_name` in `building`: alla postazione di lavorazione di una destinazione i suoi ingredienti materiali
# (is_processing_resource), altrove — il focolare — solo le risorse con prefers_recipe_workstation (la carne), come
# prima.
static func is_preferred_deposit_allowed(building: Building, resource_name: String) -> bool:
	if building != null:
		for destination in PROCESSING_DESTINATIONS:
			if building.building_type_name == String(BUILDING_TYPES[destination]):
				return is_processing_resource(destination, resource_name)
	return WarehouseSelectionService.prefers_recipe_workstation(resource_name)


# Postazione di tipo `building_type` più vicina, completa e non da demolire, che accetta almeno `min_quantity` unità di
# `resource_name` (il chiamante ha già verificato che è un suo ingrediente, is_processing_resource).
static func _find_nearest_processing_station(
	world: World, origin_position: Vector2, origin_macro_coords: Vector2i, resource_name: String, building_type: String,
	min_quantity: int, excluded_building_ids: Array[int], reachable: Callable
) -> Building:
	var predicate := func(building: Building) -> bool:
		return building.building_type_name == building_type and building.is_complete and not building.is_demolished \
			and not building.is_marked_for_demolition \
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


# "" se `destination` si può scegliere nel dialog, altrimenti il motivo già tradotto (tooltip): non ancora
# disponibile, idea dell'edificio non scoperta, o nessun edificio di quel tipo completo e non da demolire. Il magazzino
# è sempre disponibile.
static func get_unavailable_reason(destination: String, world: World, folk: Folk) -> String:
	if destination == WAREHOUSE:
		return ""
	if NOT_YET_AVAILABLE.has(destination):
		return TranslationServer.translate("hunt_destination_not_yet_available")
	var building_type := String(BUILDING_TYPES.get(destination, ""))
	var rules := BuildingCalculator.get_building_rules(building_type)
	if rules != null and rules.required_idea_id != "" and (folk == null or not folk.completed_ideas.has(rules.required_idea_id)):
		var idea := IdeaCalculator.get_idea(rules.required_idea_id)
		var idea_name: String = TranslationServer.translate(idea.display_name) if idea != null else rules.required_idea_id
		return TranslationServer.translate("hunt_destination_requires_idea").format({"idea": idea_name})
	if not _has_complete_building(world, building_type):
		return TranslationServer.translate("hunt_destination_no_building").format({
			"building": TranslationServer.translate(String(NAME_KEYS.get(destination, ""))).to_lower(),
		})
	return ""


static func is_available(destination: String, world: World, folk: Folk) -> bool:
	return get_unavailable_reason(destination, world, folk) == ""


# Destinazioni selezionabili adesso, in ordine (2026-10-03 — scelta dalla barra dei comandi, senza opzioni spente).
static func list_available(world: World, folk: Folk) -> Array[String]:
	var available: Array[String] = []
	for destination in ORDER:
		if is_available(destination, world, folk):
			available.append(destination)
	return available


# true se oltre al focolare c'è almeno un'altra destinazione di lavorazione disponibile (oggi l'essiccatoio): solo
# allora la barra dei comandi mostra il pulsante della destinazione (2026-10-03).
static func has_alternative_processing_destination(world: World, folk: Folk) -> bool:
	for destination in ORDER:
		if destination != CAMPFIRE and destination != WAREHOUSE and is_available(destination, world, folk):
			return true
	return false


# Destinazione proposta all'apertura del dialog (e usata dalla caccia diretta): l'ultima scelta se è ancora
# disponibile, altrimenti il focolare, altrimenti il magazzino.
static func resolve_default(last_destination: String, world: World, folk: Folk) -> String:
	if ORDER.has(last_destination) and is_available(last_destination, world, folk):
		return last_destination
	if is_available(CAMPFIRE, world, folk):
		return CAMPFIRE
	return WAREHOUSE


static func _has_complete_building(world: World, building_type: String) -> bool:
	if world == null:
		return false
	for building in world.buildings:
		if building.building_type_name == building_type and building.is_complete and not building.is_demolished \
				and not building.is_marked_for_demolition:
			return true
	return false
