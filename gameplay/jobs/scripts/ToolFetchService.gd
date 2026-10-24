class_name ToolFetchService
extends RefCounted

# Attrezzi per i lavori della coda (2026-10-11; spostati da GameScene il 2026-10-17, refactoring GameScene blocco 2d —
# regole invariate). Categorie richieste: quelle del comando per gli ordini di zona (Taglia CHOPPING, Estrai DIGGING,
# Caccia BUTCHERING + HUNTING), quelle della ricetta per la produzione. Regola (dal 2026-10-24 senza "lo ha già un altro"):
#   - chi arriva e ha addosso tutte le categorie lavora subito;
#   - a chi manca qualcosa prende il lavoro se ha posti liberi in cintura e un deposito raggiungibile per ciò che gli
#     manca (rejection): prima va a prenderlo (equip_tool.tres, in cintura), poi lavora;
#   - nessuno lo ha addosso e nessuno può prenderlo (nessun deposito, cintura piena): lavoro bloccato (blocked_reason).
# Scelta in deposito (category_fetch_option, 2026-10-24): l'attrezzo più efficace (HuntService.weapon_score, attacco ×
# gittata), la strada solo a parità. Attrezzi a munizioni (es. arco): solo insieme ad abbastanza munizioni (MIN_AMMO_SHOTS
# colpi, fino a MAX_AMMO_BUNDLES mazzi dai più pieni, da un deposito), anche da due depositi; chi ha già l'arma prende solo
# le munizioni, e per la caccia integra se ne ha poche (plan_fetch). Con la regola "Riponi gli
# attrezzi presi per un lavoro" accesa gli attrezzi presi restano "in prestito" (HumanIndividual.borrowed_tools) e tornano
# al deposito quando l'individuo è libero (return_borrowed_tools); spenta, diventano suoi. Statico e senza stato; le task create si restituiscono a
# chi chiama, che ne collega i segnali (griglia del magazzino) e aggiorna i pannelli.

const ZONE_ORDER_TOOL_FETCH_KEY := "zone_order_tool_fetch"
# Attrezzo che un prelievo per un lavoro sta andando a prendere (start_fetch): "id edificio:nome" nel context, la
# prenotazione (2026-10-23): due pipottini non puntano più allo stesso coltello.
const TOOL_FETCH_SOURCE_KEY := "tool_fetch_source"
# Riposizione automatica di un attrezzo in prestito (return_borrowed_tools): riga "Automatico" in "In corso".
const BORROWED_TOOL_RETURN_KEY := "borrowed_tool_return"
# Sacca presa con la regola "Prendi la sacca se disponibile" (try_take_bag): "id edificio:nome" nel context, la prenotazione.
const BAG_FETCH_KEY := "bag_fetch"
# Capo preso con la regola "Indossa i capi disponibili" (try_wear_apparel): "id edificio:nome" nel context, la prenotazione.
const APPAREL_FETCH_KEY := "apparel_fetch"
# Mezzo da traino preso prima di un lavoro a più viaggi (start_towed_fetch): "id edificio:nome", la prenotazione.
const TOWED_FETCH_KEY := "towed_fetch"
# Riposizione automatica del mezzo da traino (try_return_towed): riga "Automatico" in "In corso".
const TOWED_RETURN_KEY := "towed_return"
# Ordine degli slot del vestiario per la regola: prima il corpo, poi calzari, testa, collo, polsi.
const APPAREL_FETCH_ORDER: Array[int] = [
	HumanIndividual.ApparelSlot.BODY, HumanIndividual.ApparelSlot.FEET, HumanIndividual.ApparelSlot.HEAD,
	HumanIndividual.ApparelSlot.NECK, HumanIndividual.ApparelSlot.WRIST_LEFT, HumanIndividual.ApparelSlot.WRIST_RIGHT,
]

# Collegamento dei segnali di deposito della task della sacca (refresh di griglia e pannelli), registrato da GameScene in
# _ready — stesso schema di CargoReturnService.unload_signal_connector. Callable(task: Task, owner: HumanIndividual).
static var storage_signal_connector: Callable = Callable()
const ZONE_ORDER_TOOL_BLOCK_KEYS := {
	TaskTypes.ToolCategory.BUTCHERING: "drawer_hunt_nobody_has_knife",
	TaskTypes.ToolCategory.HUNTING: "drawer_hunt_nobody_has_weapon",
	TaskTypes.ToolCategory.CHOPPING: "drawer_cut_nobody_has_axe",
	TaskTypes.ToolCategory.DIGGING: "drawer_quarry_nobody_has_pickaxe",
}


# Età giusta per il lavoro: caccia (`age_kind` DrawerOrderService.TYPE_HUNT) = età della task hunt_zone.tres; gli altri =
# niente neonati né bambini.
static func age_ok(ctx: GameContext, member: HumanIndividual, age_kind: String) -> bool:
	var age_band := ctx.age_band_of(member)
	if age_kind == DrawerOrderService.TYPE_HUNT:
		var definition := TaskDefinitionCache.get_definition(HuntZoneService.TASK_DEFINITION_PATH)
		return definition == null or definition.allowed_age_bands.is_empty() or definition.allowed_age_bands.has(int(age_band))
	return age_band != HumanTypes.AgeBand.INFANT and age_band != HumanTypes.AgeBand.CHILD


# `member` copre `category` addosso: armi da caccia con le munizioni se servono (HuntService), il resto in cintura o zaino.
static func member_covers_tool(member: HumanIndividual, category: int) -> bool:
	if category == TaskTypes.ToolCategory.HUNTING:
		return HuntService.has_hunting_weapon_available(member)
	return ToolGateService.has_tool_for(member, category)


# `member` sta andando a prendere un attrezzo di `category` per un lavoro (task in corso o in coda).
static func member_fetching_tool(member: HumanIndividual, category: int) -> bool:
	for task in JobWorkScanService.open_tasks(member):
		var fetching: Variant = task.context.get(ZONE_ORDER_TOOL_FETCH_KEY, null)
		if fetching != null and int(fetching) == category:
			return true
	return false


# Categorie tra `categories` che `member` non ha addosso e non sta già andando a prendere.
static func member_missing_categories(member: HumanIndividual, categories: Array) -> Array:
	var missing: Array = []
	for category in categories:
		if not member_covers_tool(member, int(category)) and not member_fetching_tool(member, int(category)):
			missing.append(int(category))
	return missing


# true se qualcuno in età (per `age_kind`, vedi age_ok) ha (o sta prendendo) tutte le `categories`.
static func has_equipped_member(ctx: GameContext, categories: Array, age_kind: String) -> bool:
	for member in ctx.individuals:
		if age_ok(ctx, member, age_kind) and member_missing_categories(member, categories).is_empty():
			return true
	return false


# Posti liberi della cintura di `member`, in ordine.
static func free_belt_slots(member: HumanIndividual) -> Array[int]:
	var slots: Array[int] = []
	for slot in range(member.get_tool_slot_count()):
		if member.get_equipped_tool(slot) == "":
			slots.append(slot)
	return slots


# Attrezzi che coprono `category` e si possono prendere da soli in deposito per un lavoro: mai quelli che richiedono una
# munizione (per ogni categoria dal 2026-10-23; prima solo per la caccia), che si prendono solo insieme alla munizione
# (category_fetch_option).
static func fetchable_tool_names(category: int) -> Array[String]:
	var names: Array[String] = []
	for tool_name in ToolGateService.get_tools_covering(category):
		var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
		if (rules == null and category == TaskTypes.ToolCategory.HUNTING) or (rules != null and rules.required_ammo_category >= 0):
			continue
		names.append(tool_name)
	return names


# Deposito e attrezzo che copre `category` per `worker` (raggiungibile; tra i nomi, il deposito più vicino); con `worker`
# null basta che un deposito ne abbia uno. {} se nessuno. Gli attrezzi che altri stanno già andando a prendere
# (TOOL_FETCH_SOURCE_KEY, 2026-10-23) non contano.
# Tenuto per il fotogramma in corso, per pipottino e categoria (2026-10-22, scatti: stessa ricerca nei depositi ripetuta
# da blocked_reason/rejection per ogni ordine e ogni pipottino).
static var _storage_tool_cache: Dictionary = {}
static var _storage_tool_frame: int = -1


static func find_storage_tool(world: World, worker: HumanIndividual, category: int) -> Dictionary:
	var frame := Engine.get_process_frames()
	if frame != _storage_tool_frame:
		_storage_tool_cache.clear()
		_storage_tool_frame = frame
	var cache_key := [worker.get_instance_id() if worker != null else 0, category]
	if not _storage_tool_cache.has(cache_key):
		_storage_tool_cache[cache_key] = _find_storage_tool(world, worker, category)
	return _storage_tool_cache[cache_key]


static func _find_storage_tool(world: World, worker: HumanIndividual, category: int) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var reserved := _reserved_fetches(worker, TOOL_FETCH_SOURCE_KEY)
	for tool_name in fetchable_tool_names(category):
		var origin := worker.position if worker != null else Vector2.ZERO
		var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
		var timing := JobBoardTimingService.is_enabled()
		var started := JobBoardTimingService.now() if timing else 0
		var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
		if timing:
			JobBoardTimingService.add("deposito: raggiungibilità", started)
		var source := _find_unreserved_source(world, origin, origin_macro, tool_name, reserved, reachability)
		if source == null:
			continue
		if worker == null:
			return {"building": source, "tool_name": tool_name}
		var offset := Vector2(Vector2i(source.macro_x, source.macro_y) - worker.home_macro_coords) * World.WIDTH
		var distance := worker.position.distance_to(Vector2(source.micro_x, source.micro_y) + offset)
		if distance < best_distance:
			best_distance = distance
			best = {"building": source, "tool_name": tool_name}
	return best


# Deposito più vicino a `origin` con almeno un `tool_name` non prenotato (`reserved`: _fetch_key -> quanti); null se nessuno.
static func _find_unreserved_source(
	world: World, origin: Vector2, origin_macro: Vector2i, tool_name: String, reserved: Dictionary, reachability: Callable
) -> Building:
	# Tempo (2026-10-24, assegnatore): "deposito: ricerca depositi" (con la raggiungibilità di ogni deposito provato).
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	var excluded: Array[int] = []
	var found: Building = null
	while true:
		var source := WarehouseSelectionService.find_source_for_retrieval(world, origin, origin_macro, tool_name, excluded, 1, -1, reachability)
		if source == null:
			break
		if BuildingStorageService.get_available_quantity(source, tool_name) > int(reserved.get(_fetch_key(source, tool_name), 0)):
			found = source
			break
		excluded.append(source.id)
	if timing:
		JobBoardTimingService.add("deposito: ricerca depositi", started)
	return found


# Motivo per cui nessuno può fare un lavoro che richiede `categories` ("" = qualcuno può): una categoria che nessuno ha
# addosso e nessun deposito ha; oppure nessuno in età con abbastanza posto in cintura per prenderle.
# Tenuto per il fotogramma in corso (2026-10-22, scatti: il ridisegno della coda lo chiedeva per ogni ordine, quasi
# sempre con le stesse categorie, e ognuno cercava gli attrezzi in tutti i depositi).
static var _blocked_reason_cache: Dictionary = {}
static var _blocked_reason_frame: int = -1


static func blocked_reason(ctx: GameContext, categories: Array, age_kind: String) -> String:
	var frame := Engine.get_process_frames()
	if frame != _blocked_reason_frame:
		_blocked_reason_cache.clear()
		_blocked_reason_frame = frame
	var cache_key := [categories, age_kind]
	if not _blocked_reason_cache.has(cache_key):
		_blocked_reason_cache[cache_key] = _compute_blocked_reason(ctx, categories, age_kind)
	return _blocked_reason_cache[cache_key]


static func _compute_blocked_reason(ctx: GameContext, categories: Array, age_kind: String) -> String:
	if categories.is_empty() or ctx.world == null or has_equipped_member(ctx, categories, age_kind):
		return ""
	var nowhere: Array = []
	for category in categories:
		var someone_has := false
		for member in ctx.individuals:
			if age_ok(ctx, member, age_kind) and member_covers_tool(member, int(category)):
				someone_has = true
				break
		if not someone_has and category_fetch_option(ctx.world, null, int(category)).is_empty():
			nowhere.append(int(category))
	if not nowhere.is_empty():
		if nowhere.size() == 1 and ZONE_ORDER_TOOL_BLOCK_KEYS.has(nowhere[0]):
			return GameContext.tr_text(String(ZONE_ORDER_TOOL_BLOCK_KEYS[nowhere[0]]))
		return GameContext.tr_text("task_assignment_nobody_has_tool").format({"tools": describe_missing_categories(nowhere)})
	var needed: Array = []
	for member in ctx.individuals:
		if not age_ok(ctx, member, age_kind):
			continue
		var missing := member_missing_categories(member, categories)
		if missing_tools_in_storage(ctx.world, member, missing):
			return ""
		for category in missing:
			if not needed.has(category):
				needed.append(category)
	return GameContext.tr_text("drawer_order_nobody_has_belt_room").format({"tools": describe_missing_categories(needed)})


# true se per ogni categoria di `missing` c'è un prelievo possibile (category_fetch_option) e tutti insieme stanno nei
# posti liberi della cintura di `member` (arma + munizione ne usano due).
static func missing_tools_in_storage(world: World, member: HumanIndividual, missing: Array) -> bool:
	var slots := free_belt_slots(member).size()
	for category in missing:
		var option := category_fetch_option(world, member, int(category), slots)
		if option.is_empty():
			return false
		slots -= option.size()
	return true


# Prelievo per una categoria (2026-10-23, arco e frecce per la caccia automatica; 2026-10-24, richiesta utente — scelta per
# efficacia, regola valida per ogni arma con required_ammo_category). Vince l'attrezzo col punteggio più alto
# (HuntService.weapon_score, attacco × gittata: per le categorie senza armi tutti 0, quindi decide la strada come prima);
# la strada decide solo tra attrezzi con lo stesso punteggio. La classifica dei tipi presenti nei depositi è comune a tutti
# (_weapon_ranking), qui si cerca solo il deposito per `worker`, tipo per tipo dal migliore. Opzioni:
#   - un attrezzo senza munizioni (un posto);
#   - la sola munizione per un'arma a munizioni che `worker` ha già, in cintura o nello zaino;
#   - arma a munizioni + munizione, anche da due depositi: conta il giro intero (pipottino → primo deposito → secondo).
# Munizioni: almeno MIN_AMMO_SHOTS colpi con al massimo MAX_AMMO_BUNDLES mazzi dai più pieni, tutti da un deposito (il
# più vicino che ci arriva); qui solo i mazzi che servono alla soglia, quelli in più li aggiunge plan_fetch. Un'arma a
# munizioni senza abbastanza colpi prendibili non si considera. Le opzioni con più attrezzi dei `max_slots` si scartano.
# [{"building", "tool_name", "fullest"?}, ...] in ordine di tappa, vuoto se nessuna. Con `worker` null basta che un'opzione
# esista (la sola munizione conta se qualcuno ha l'arma). Prenotazioni e tenuta per il fotogramma come find_storage_tool.
const MIN_AMMO_SHOTS := 5
const MAX_AMMO_BUNDLES := 3


static func category_fetch_option(world: World, worker: HumanIndividual, category: int, max_slots: int = 99) -> Array[Dictionary]:
	var frame := Engine.get_process_frames()
	if frame != _storage_tool_frame:
		_storage_tool_cache.clear()
		_storage_tool_frame = frame
	var cache_key := ["option", worker.get_instance_id() if worker != null else 0, category, max_slots]
	if not _storage_tool_cache.has(cache_key):
		_storage_tool_cache[cache_key] = _compute_fetch_option(world, worker, category, max_slots)
	return _storage_tool_cache[cache_key]


static func _compute_fetch_option(world: World, worker: HumanIndividual, category: int, max_slots: int) -> Array[Dictionary]:
	var best: Array[Dictionary] = []
	if max_slots < 1:
		return best
	var origin := worker.position if worker != null else Vector2.ZERO
	var origin_macro := worker.home_macro_coords if worker != null else Vector2i.ZERO
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	var reachability := PathfindingService.reachability_for(worker) if worker != null else Callable()
	if timing:
		JobBoardTimingService.add("deposito: raggiungibilità", started)
	var reserved := _reserved_fetches(worker, TOOL_FETCH_SOURCE_KEY)
	var ranking := _weapon_ranking(world, category)
	var index := 0
	while index < ranking.size():
		# Un gruppo di tipi con lo stesso punteggio: vince il giro più corto; il primo gruppo con un'opzione chiude la ricerca.
		var tier_score := float(ranking[index]["score"])
		var best_distance := INF
		while index < ranking.size() and is_equal_approx(float(ranking[index]["score"]), tier_score):
			var option := _option_for(world, worker, ranking[index], max_slots, origin, origin_macro, reserved, reachability)
			index += 1
			if option.is_empty():
				continue
			if worker == null:
				return option
			var distance := _route_length(worker, option)
			if distance < best_distance:
				best_distance = distance
				best = option
		if not best.is_empty():
			return best
	return best


# Classifica comune dei tipi di attrezzo di `category` prendibili da un deposito (2026-10-24): [{"tool_name", "ammo_name",
# "score"}] per punteggio decrescente (HuntService.weapon_score), a parità in ordine di nome. Un attrezzo senza munizioni
# entra se almeno un deposito ne ha un pezzo; un'arma a munizioni entra una volta per tipo di munizione se un deposito ha
# abbastanza colpi (_bundles_for), anche se l'arma non è in deposito (può averla già il pipottino: lo vede _option_for).
# Raggiungibilità e prenotazioni non contano qui (sono del singolo pipottino). Tenuta per il fotogramma.
static func _weapon_ranking(world: World, category: int) -> Array[Dictionary]:
	var frame := Engine.get_process_frames()
	if frame != _storage_tool_frame:
		_storage_tool_cache.clear()
		_storage_tool_frame = frame
	var cache_key := ["ranking", category]
	if _storage_tool_cache.has(cache_key):
		return _storage_tool_cache[cache_key]
	var ranking: Array[Dictionary] = []
	for tool_name in ToolGateService.get_tools_covering(category):
		var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
		if rules == null:
			continue
		if rules.required_ammo_category < 0:
			if _any_building_has(world, tool_name):
				ranking.append({"tool_name": tool_name, "ammo_name": "", "score": HuntService.weapon_score(tool_name)})
			continue
		for ammo_name in ToolGateService.get_tools_covering(rules.required_ammo_category):
			for building in world.buildings:
				if _bundles_for(_ammo_shots_in(building, ammo_name, 0), MIN_AMMO_SHOTS, MAX_AMMO_BUNDLES) > 0:
					ranking.append({"tool_name": tool_name, "ammo_name": ammo_name, "score": HuntService.weapon_score(tool_name, ammo_name)})
					break
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	_storage_tool_cache[cache_key] = ranking
	return ranking


static func _any_building_has(world: World, resource_name: String) -> bool:
	for building in world.buildings:
		if BuildingStorageService.get_available_quantity(building, resource_name) > 0:
			return true
	return false


# Opzione di prelievo per una voce della classifica (vedi category_fetch_option), [] se non c'è per `worker`.
static func _option_for(
	world: World, worker: HumanIndividual, entry: Dictionary, max_slots: int, origin: Vector2, origin_macro: Vector2i,
	reserved: Dictionary, reachability: Callable
) -> Array[Dictionary]:
	var stops: Array[Dictionary] = []
	var tool_name := String(entry["tool_name"])
	var ammo_name := String(entry["ammo_name"])
	if ammo_name == "":
		var source := _find_unreserved_source(world, origin, origin_macro, tool_name, reserved, reachability)
		if source != null:
			stops.append({"building": source, "tool_name": tool_name})
		return stops
	if _owns_tool(worker, tool_name):
		# Arma già sua: solo i mazzi, dal deposito più vicino che arriva alla soglia.
		var own_ammo := _find_ammo_source(world, origin, origin_macro, ammo_name, MIN_AMMO_SHOTS, mini(MAX_AMMO_BUNDLES, max_slots), reserved, reachability)
		return _ammo_stops(own_ammo, ammo_name)
	if max_slots < 2:
		return stops
	var weapon_source := _find_unreserved_source(world, origin, origin_macro, tool_name, reserved, reachability)
	if weapon_source == null:
		return stops
	var weapon_entry := {"building": weapon_source, "tool_name": tool_name}
	var max_bundles := mini(MAX_AMMO_BUNDLES, max_slots - 1)
	# Giro arma → mazzi (deposito dei mazzi più vicino all'arma) e giro mazzi → arma (più vicino al pipottino).
	var near_weapon := _find_ammo_source(
		world, Vector2(weapon_source.micro_x, weapon_source.micro_y), Vector2i(weapon_source.macro_x, weapon_source.macro_y),
		ammo_name, MIN_AMMO_SHOTS, max_bundles, reserved, reachability
	)
	if near_weapon.is_empty():
		return stops
	stops.append(weapon_entry)
	stops.append_array(_ammo_stops(near_weapon, ammo_name))
	if worker == null:
		return stops
	var near_worker := _find_ammo_source(world, origin, origin_macro, ammo_name, MIN_AMMO_SHOTS, max_bundles, reserved, reachability)
	if not near_worker.is_empty() and near_worker["building"] != near_weapon["building"]:
		var ammo_first := _ammo_stops(near_worker, ammo_name)
		ammo_first.append(weapon_entry)
		if _route_length(worker, ammo_first) < _route_length(worker, stops):
			return ammo_first
	return stops


# Una tappa per mazzo ({"building", "count"} di _find_ammo_source), da prelevare dal più pieno; [] se nessun deposito.
static func _ammo_stops(source: Dictionary, ammo_name: String) -> Array[Dictionary]:
	var stops: Array[Dictionary] = []
	if source.is_empty():
		return stops
	for i in range(int(source["count"])):
		stops.append({"building": source["building"], "tool_name": ammo_name, "fullest": true})
	return stops


# Deposito più vicino a `origin` i cui mazzi di `ammo_name` (dai più pieni, senza i prenotati da altri) danno almeno
# `need_shots` colpi con al massimo `max_bundles` mazzi: {"building", "count"} (mazzi necessari), {} se nessuno.
static func _find_ammo_source(
	world: World, origin: Vector2, origin_macro: Vector2i, ammo_name: String, need_shots: int, max_bundles: int,
	reserved: Dictionary, reachability: Callable
) -> Dictionary:
	if max_bundles < 1:
		return {}
	var excluded: Array[int] = []
	while true:
		var source := WarehouseSelectionService.find_source_for_retrieval(world, origin, origin_macro, ammo_name, excluded, 1, -1, reachability)
		if source == null:
			break
		var shots := _ammo_shots_in(source, ammo_name, int(reserved.get(_fetch_key(source, ammo_name), 0)))
		var count := _bundles_for(shots, need_shots, max_bundles)
		if count > 0:
			return {"building": source, "count": count}
		excluded.append(source.id)
	return {}


# Usi rimasti dei pezzi di `ammo_name` nel deposito (magazzino + prodotti finiti, questi sempre nuovi), dal più pieno,
# senza i primi `reserved_count` (prenotati da altri, che prelevano anche loro dal più pieno).
static func _ammo_shots_in(building: Building, ammo_name: String, reserved_count: int) -> Array[int]:
	var shots: Array[int] = []
	if BuildingStorageService.get_available_quantity(building, ammo_name) <= 0:
		return shots
	var max_uses := ToolInstance.get_max_uses(ammo_name)
	shots = _unit_uses(building.stored_resources.get(ammo_name, {}), max_uses)
	for i in range(int(building.production_output.get(ammo_name, 0))):
		shots.append(max_uses)
	shots.sort()
	shots.reverse()
	return shots.slice(mini(reserved_count, shots.size()))


# Usi rimasti di ogni pezzo di una voce (magazzino o zaino): istanze usate utilizzabili + nuovi a `max_uses`.
static func _unit_uses(entry: Dictionary, max_uses: int) -> Array[int]:
	var uses: Array[int] = []
	var used := ToolInstance.get_used_instances(entry)
	for instance in used:
		if ToolInstance.is_usable(instance):
			uses.append(ToolInstance.get_remaining_uses(instance))
	for i in range(maxi(int(entry.get("quantity", 0)) - used.size(), 0)):
		uses.append(max_uses)
	return uses


# Mazzi necessari (dai primi di `shots`, già dal più pieno) per arrivare a `need_shots` colpi, al massimo `max_bundles`;
# 0 se non ci si arriva.
static func _bundles_for(shots: Array[int], need_shots: int, max_bundles: int) -> int:
	var total := 0
	for i in range(mini(shots.size(), max_bundles)):
		total += shots[i]
		if total >= need_shots:
			return i + 1
	return 0


# Lunghezza del giro di `worker` lungo le tappe (pipottino → prima → seconda…; tappe consecutive nello stesso deposito 0).
static func _route_length(worker: HumanIndividual, stops: Array[Dictionary]) -> float:
	var length := _distance_to(worker, stops[0]["building"])
	for i in range(1, stops.size()):
		length += _distance_between(stops[i - 1]["building"], stops[i]["building"])
	return length


# `worker` ha `tool_name` in cintura o nello zaino; con `worker` null, qualcuno della partita.
static func _owns_tool(worker: HumanIndividual, tool_name: String) -> bool:
	var members: Array[HumanIndividual] = []
	if worker != null:
		members.append(worker)
	else:
		members.assign(GameSettings.active_human_individuals)
	for member in members:
		if find_belt_slot_by_name(member, tool_name) != -1 or member.get_carried_quantity(tool_name) > 0:
			return true
	return false


static func _distance_between(from: Building, to: Building) -> float:
	var offset := Vector2(Vector2i(to.macro_x, to.macro_y) - Vector2i(from.macro_x, from.macro_y)) * World.WIDTH
	return Vector2(from.micro_x, from.micro_y).distance_to(Vector2(to.micro_x, to.micro_y) + offset)


# Idoneità di `worker` per gli attrezzi ("" = può): tutto addosso; oppure posti liberi in cintura e un deposito
# raggiungibile per ogni categoria che gli manca.
# Senza "lo ha già un altro" (2026-10-24, richiesta utente — nel paleolitico nessuno si ricorda chi ha un attrezzo; prima
# un attrezzato altrove teneva fermi i lavori di chi arrivava al punto, e il giro su tutto il villaggio costava ~6 ms a ogni
# arrivo): chi arriva prende il lavoro e va a prendere gli attrezzi in deposito, se ci sono. Con la regola "Riponi gli
# attrezzi presi per un lavoro" accesa tornano al deposito appena è libero (try_return_borrowed_tools). `_age_kind` resta
# nella firma per i chiamanti. Tempi (JobBoardTimingService): "attrezzi: cintura", "attrezzi: deposito".
static func rejection(_ctx: GameContext, worker: HumanIndividual, categories: Array, _age_kind: String) -> String:
	var missing := member_missing_categories(worker, categories)
	if missing.is_empty():
		return ""
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	var belt_full := free_belt_slots(worker).size() < missing.size()
	if timing:
		JobBoardTimingService.add("attrezzi: cintura", started)
	if belt_full:
		return "cintura piena per gli attrezzi da prendere"
	started = JobBoardTimingService.now() if timing else 0
	var in_storage := missing_tools_in_storage(_ctx.world, worker, missing)
	if timing:
		JobBoardTimingService.add("attrezzi: deposito", started)
	if not in_storage:
		return "attrezzo mancante e non raggiungibile in deposito (o cintura piena per arma e munizione)"
	return ""


# Attrezzi da prendere prima del lavoro: [{"category", "building", "tool_name", "slot"}], vuoto se ha già tutto. Per
# categoria l'opzione più corta di category_fetch_option (arma + munizione = due voci, in ordine di tappa).
# Caccia (2026-10-24): mazzi in più dopo le categorie mancanti (_plan_extra_ammo).
static func plan_fetch(world: World, worker: HumanIndividual, categories: Array) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var missing := member_missing_categories(worker, categories)
	var slots := free_belt_slots(worker)
	for category in missing:
		for found in category_fetch_option(world, worker, int(category), slots.size()):
			var entry := found.duplicate()
			entry["category"] = int(category)
			entry["slot"] = slots.pop_front()
			plan.append(entry)
	if categories.has(TaskTypes.ToolCategory.HUNTING):
		# Posti tenuti per gli attrezzi che ha nello zaino e che la caccia metterà in cintura (es. il coltello).
		var keep := 0
		for category in categories:
			if not missing.has(int(category)) and ToolGateService.find_belt_slot_for(worker, int(category)) == -1:
				keep += 1
		_plan_extra_ammo(world, worker, plan, slots, keep)
	return plan


# Mazzi in più per la caccia (2026-10-24, richiesta utente), sempre dal più pieno e senza superare MAX_AMMO_BUNDLES mazzi
# in cintura né i posti liberi (meno `keep`):
#   - il piano prende un'arma a munizioni: altri mazzi dallo stesso deposito dei suoi, oltre la soglia;
#   - il piano non prende armi e l'arma con cui caccerebbe (HuntService.choose_weapon) è a munizioni con meno di
#     MIN_AMMO_SHOTS colpi in cintura: integrazione dal deposito più vicino che ha mazzi (anche se non arriva alla soglia).
static func _plan_extra_ammo(world: World, worker: HumanIndividual, plan: Array[Dictionary], slots: Array[int], keep: int) -> void:
	var building: Building = null
	var ammo_name := ""
	var planned := 0
	var hunting_in_plan := false
	for entry in plan:
		if int(entry["category"]) != TaskTypes.ToolCategory.HUNTING:
			continue
		hunting_in_plan = true
		if bool(entry.get("fullest", false)):
			building = entry["building"]
			ammo_name = String(entry["tool_name"])
			planned += 1
	var reserved := {}
	var belt_bundles := 0
	if building == null:
		if hunting_in_plan:
			return
		var weapon := HuntService.choose_weapon(worker, TaskTypes.ToolCategory.HUNTING, "", -1)
		var rules := CaloricCalculator.get_caloric_source_rules(weapon) if weapon != "" else null
		if rules == null or rules.required_ammo_category < 0:
			return
		var belt := _belt_ammo(worker, rules.required_ammo_category)
		if belt.y >= MIN_AMMO_SHOTS:
			return
		belt_bundles = belt.x
		reserved = _reserved_fetches(worker, TOOL_FETCH_SOURCE_KEY)
		var reachability := PathfindingService.reachability_for(worker)
		for candidate in ToolGateService.get_tools_covering(rules.required_ammo_category):
			var source := _find_ammo_source(world, worker.position, worker.home_macro_coords, candidate, 1, 1, reserved, reachability)
			if not source.is_empty() and (building == null or _distance_to(worker, source["building"]) < _distance_to(worker, building)):
				building = source["building"]
				ammo_name = candidate
		if building == null:
			return
	else:
		var ammo_categories := ToolGateService._tool_categories(ammo_name)
		belt_bundles = _belt_ammo(worker, int(ammo_categories[0])).x if not ammo_categories.is_empty() else 0
		reserved = _reserved_fetches(worker, TOOL_FETCH_SOURCE_KEY)
	var available :=_ammo_shots_in(building, ammo_name, int(reserved.get(_fetch_key(building, ammo_name), 0))).size() - planned
	var extra := mini(mini(available, slots.size() - keep), MAX_AMMO_BUNDLES - belt_bundles - planned)
	for i in range(extra):
		plan.append({
			"building": building, "tool_name": ammo_name, "fullest": true,
			"category": TaskTypes.ToolCategory.HUNTING, "slot": slots.pop_front(),
		})


# Munizioni della categoria `ammo_category` in cintura: Vector2i(mazzi, colpi).
static func _belt_ammo(worker: HumanIndividual, ammo_category: int) -> Vector2i:
	var result := Vector2i.ZERO
	for slot in range(worker.get_tool_slot_count()):
		var tool_name := worker.get_equipped_tool(slot)
		if tool_name != "" and ToolGateService._tool_categories(tool_name).has(ammo_category):
			result.x += 1
			result.y += worker.get_equipped_tool_uses(slot)
	return result


# Prelievi in deposito prima del lavoro appena assegnato: una task equip_tool per attrezzo, assegnata dopo il lavoro (che
# è sospendibile e va in coda personale, riprendendo a prelievo finito). Prelievo fallito (attrezzo sparito): il lavoro
# riparte lo stesso e aspetta l'attrezzo come ogni altro passo senza attrezzo. Ogni attrezzo preso è "in prestito" se la
# regola "Riponi gli attrezzi presi per un lavoro" è accesa.
# `work_label` = cosa fa dopo, per il log. Ritorna le task assegnate (chi chiama ne collega i segnali).
static func start_fetch(ctx: GameContext, worker: HumanIndividual, plan: Array[Dictionary], work_label: Variant) -> Array[Task]:
	var assigned: Array[Task] = []
	for fetch in plan:
		var building: Building = fetch["building"]
		var tool_name := String(fetch["tool_name"])
		var task := TaskBuilderService.build_equip_tool_task(worker, building, tool_name, int(fetch["slot"]))
		if task == null:
			continue
		task.context[ZONE_ORDER_TOOL_FETCH_KEY] = int(fetch["category"])
		task.context[TOOL_FETCH_SOURCE_KEY] = _fetch_key(building, tool_name)
		# Munizioni (2026-10-24): esce il mazzo più pieno, quello contato dalla scelta (_ammo_shots_in).
		if bool(fetch.get("fullest", false)):
			task.context[RetrieveAction.CONTEXT_EQUIP_FULLEST] = true
		if not worker.assign_task(task, ctx.age_band_of(worker)):
			continue
		assigned.append(task)
		# Prenotazione nuova: le ricerche tenute per il fotogramma non la vedono, si rifanno.
		_storage_tool_frame = -1
		_blocked_reason_frame = -1
		# In prestito solo con la regola "Riponi gli attrezzi presi per un lavoro" accesa (2026-10-23, richiesta utente):
		# spenta, l'attrezzo preso diventa del pipottino e non torna in deposito nemmeno riaccendendola.
		if ctx.game_data != null and ctx.game_data.job_board_return_borrowed_tools:
			worker.borrowed_tools.append({"tool_name": tool_name, "building_id": building.id})
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] #%d %s: va a prendere %s in %s #%d prima di %s." % [
				worker.id, worker.name, tool_name, building.building_type_name, building.id,
				("ordine del cassetto #%d" % int(work_label)) if work_label is int else str(work_label)
			])
	return assigned


# Prelievo ritentato (2026-10-23, richiesta utente — Ashi ferma al focolare con "Attrezzi mancanti: taglio" e 5 coltelli
# in deposito): il prelievo si decideva solo alla presa del lavoro, e chi poi aspettava guardava solo cintura e zaino. Una
# volta al secondo, chi è fermo su una produzione per attrezzi mancanti (MISSING_TOOLS, categorie già senza quelle
# coperte dall'Attrezzeria dell'edificio) riprova plan_fetch: le categorie che sta già andando a prendere sono escluse da
# member_missing_categories, quindi mai due prelievi per la stessa. Ritorna {"member", "task"} per ogni task creata
# (chi chiama ne collega i segnali).
static func retry_waiting_fetches(ctx: GameContext) -> Array[Dictionary]:
	var created: Array[Dictionary] = []
	if ctx.world == null:
		return created
	for member in ctx.individuals:
		var task := member.current_task
		if task == null or task.is_finished():
			continue
		var produce := task.get_current_action() as ProduceAction
		if produce == null or produce.tool_wait_result != ToolGateService.Result.MISSING_TOOLS:
			continue
		var plan := plan_fetch(ctx.world, member, produce.tool_wait_missing_categories)
		if plan.is_empty():
			continue
		for fetch_task in start_fetch(ctx, member, plan, "produrre %s (ritentato)" % produce.resource_name):
			created.append({"member": member, "task": fetch_task})
	return created


# Regola "Riponi gli attrezzi presi per un lavoro" (2026-10-11, GameData.job_board_return_borrowed_tools): chi si libera
# riporta gli attrezzi in prestito ancora in cintura — task store_tool (come "Riponi attrezzo" del pannello) verso l'edificio
# da cui li ha presi, se c'è ancora e li accetta, altrimenti il deposito migliore. Chiamata da HumanIndividualActionService.
# resolve_idle_individual appena libero, dopo il travois e prima di vestiario e sacca (2026-10-24, correzione: prima era un
# giro una volta al secondo che cercava chi era senza task, ma resolve_idle_individual dà subito "Cerca lavoro" o un'attività
# di ripiego, quindi nessuno risultava mai libero e gli attrezzi non tornavano: chi li teneva bloccava i lavori degli altri,
# "lo ha già un altro"). Il primo attrezzo sceglie la destinazione; gli altri con la stessa destinazione si accodano allo
# stesso viaggio, quelli diretti altrove alla prossima pausa. Senza destinazione si tiene e si riprova. true = task assegnata.
# Spenta (2026-10-23): i prelievi non segnano più prestiti (start_fetch) e quelli già segnati si cancellano allo
# spegnimento (forget_borrowed_tools): gli attrezzi restano a chi li ha.
static func try_return_borrowed_tools(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or world == null:
		return false
	_prune_borrowed_tools(individual)
	if individual.borrowed_tools.is_empty() or not game_data.job_board_return_borrowed_tools:
		return false
	var trip_destination: Building = null
	var assigned_any := false
	var remaining: Array = []
	for entry in individual.borrowed_tools:
		var tool_name := String(entry.get("tool_name", ""))
		var slot := find_belt_slot_by_name(individual, tool_name)
		var destination := _borrowed_tool_destination(world, individual, tool_name, int(entry.get("building_id", -1)))
		if slot == -1 or destination == null or (trip_destination != null and destination != trip_destination):
			remaining.append(entry)
			continue
		var task := TaskBuilderService.build_tool_task(individual, TaskBuilderService.STORE_TOOL_TASK_DEFINITION_PATH, tool_name, destination, slot)
		if task == null:
			remaining.append(entry)
			continue
		task.context[BORROWED_TOOL_RETURN_KEY] = true
		if not assigned_any:
			if not individual.assign_task(task, age_band):
				remaining.append(entry)
				continue
			assigned_any = true
			trip_destination = destination
		else:
			TaskQueueService.push_follow_up_task(individual, task)
		if storage_signal_connector.is_valid():
			storage_signal_connector.call(task, individual)
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] #%d %s: ripone %s in %s #%d (preso per un lavoro)." % [
				individual.id, individual.name, tool_name, destination.building_type_name, destination.id
			])
	individual.borrowed_tools = remaining
	return assigned_any


# Toglie dai prestiti gli attrezzi non più in cintura (rotti, spostati a mano). Una volta al secondo per tutti (GameSimulation,
# così il pannello resta giusto anche per chi non si libera) e prima di ogni restituzione.
static func prune_borrowed_tools(ctx: GameContext) -> void:
	for member in ctx.individuals:
		if not member.borrowed_tools.is_empty():
			_prune_borrowed_tools(member)


static func _prune_borrowed_tools(member: HumanIndividual) -> void:
	var still_equipped: Array = []
	for entry in member.borrowed_tools:
		if find_belt_slot_by_name(member, String(entry.get("tool_name", ""))) != -1:
			still_equipped.append(entry)
	member.borrowed_tools = still_equipped


# --- Mezzo da traino (2026-10-23, richiesta utente — travois) ---
# Si prende prima di un lavoro che richiede più di un viaggio (ordini di zona con più viaggi, trasporti oltre il carico),
# se ce n'è uno libero: prima dall'appoggio più vicino (deposito che lo accetta per nome), poi da un magazzino. Nessuno
# libero = il lavoro parte lo stesso, senza. Si riporta sempre quando il pipottino è libero (try_return_towed), qualunque sia
# la regola "Riponi gli attrezzi presi per un lavoro": all'appoggio più vicino con posto, altrimenti in un magazzino (2 usi,
# UnloadAction._complete_towed_return). I rifornimenti dei materiali restano senza travois per ora.

# true se `quantity` unità di `resource_name` non stanno nel carico attuale di `worker` (serve più di un viaggio).
static func needs_towing_for(worker: HumanIndividual, resource_name: String, quantity: int) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return rules != null and float(quantity) * rules.space_per_unit > worker.max_carry_capacity


# Task di presa del mezzo da traino, assegnata dopo il lavoro (che va in coda e riprende a presa finita), come start_fetch.
# null se lo traina già, se lo sta già andando a prendere o se nessun mezzo libero è raggiungibile.
static func start_towed_fetch(ctx: GameContext, worker: HumanIndividual, work_label: Variant) -> Task:
	if ctx.world == null or worker.is_towing():
		return null
	for task in JobWorkScanService.open_tasks(worker):
		if task.context.has(TOWED_FETCH_KEY):
			return null
	var towed_names := fetchable_tool_names(TaskTypes.ToolCategory.TOWING)
	towed_names.sort_custom(func(a: String, b: String) -> bool:
		return _carry_bonus_of(a) > _carry_bonus_of(b)
	)
	var reserved := _reserved_fetches(worker, TOWED_FETCH_KEY)
	var reachability := PathfindingService.reachability_for(worker)
	for towed_name in towed_names:
		var source := _find_towed_source(ctx.world, worker, towed_name, reserved, reachability)
		if source == null:
			continue
		var task := TaskBuilderService.build_equip_tool_task(worker, source, towed_name, HumanIndividual.TOWED_SLOT)
		if task == null:
			return null
		task.context[TOWED_FETCH_KEY] = _fetch_key(source, towed_name)
		if not worker.assign_task(task, ctx.age_band_of(worker)):
			return null
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] #%d %s: va a prendere %s in %s #%d prima di %s." % [
				worker.id, worker.name, towed_name, source.building_type_name, source.id,
				("ordine del cassetto #%d" % int(work_label)) if work_label is int else str(work_label)
			])
		return task
	return null


# Sorgente del mezzo: l'appoggio raggiungibile più vicino con un mezzo non prenotato, altrimenti il deposito più vicino.
static func _find_towed_source(
	world: World, worker: HumanIndividual, towed_name: String, reserved: Dictionary, reachability: Callable
) -> Building:
	var not_dedicated: Array[int] = []
	for building in world.buildings:
		if building.rules == null or not building.rules.storage_accepted_resources.has(towed_name):
			not_dedicated.append(building.id)
	var excluded := not_dedicated.duplicate()
	while true:
		var rack := WarehouseSelectionService.find_source_for_retrieval(
			world, worker.position, worker.home_macro_coords, towed_name, excluded, 1, -1, reachability
		)
		if rack == null:
			break
		if BuildingStorageService.get_available_quantity(rack, towed_name) > int(reserved.get(_fetch_key(rack, towed_name), 0)):
			return rack
		excluded.append(rack.id)
	return _find_free_source(worker, world, towed_name, reserved, reachability)


# Chi traina un mezzo lo riporta appena si libera (2026-10-24, correzione: prima un giro una volta al secondo cercava chi
# era senza task, ma resolve_idle_individual dà subito "Cerca lavoro" o un'attività di ripiego, quindi nessuno risultava
# mai libero e i travois non tornavano più). Chiamata da HumanIndividualActionService.resolve_idle_individual prima delle
# regole del vestiario e della sacca, con la coda già ripresa. Destinazione: l'appoggio più vicino con posto
# (WarehouseSelectionService.find_best mette prima i depositi dedicati), altrimenti il deposito migliore; senza
# destinazione lo tiene e si riprova alla prossima pausa. Se il lavoro successivo ne vuole uno, lo riprende
# (start_towed_fetch). true = task assegnata.
static func try_return_towed(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	if world == null or not individual.is_towing():
		return false
	var destination := WarehouseSelectionService.find_best(
		world, individual.position, individual.home_macro_coords, individual.towed_resource, 1, [],
		PathfindingService.reachability_for(individual)
	)
	if destination == null:
		return false
	var task := TaskBuilderService.build_tool_task(
		individual, TaskBuilderService.STORE_TOOL_TASK_DEFINITION_PATH, individual.towed_resource, destination, HumanIndividual.TOWED_SLOT
	)
	if task == null:
		return false
	task.context[TOWED_RETURN_KEY] = true
	if not individual.assign_task(task, age_band):
		return false
	if storage_signal_connector.is_valid():
		storage_signal_connector.call(task, individual)
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		print("[JOB BOARD] #%d %s: riporta %s in %s #%d." % [
			individual.id, individual.name, individual.towed_resource, destination.building_type_name, destination.id
		])
	return true


# Regola "Riponi gli attrezzi presi per un lavoro" spenta (2026-10-23): i prestiti segnati si cancellano, gli attrezzi
# diventano di chi li ha. Riaccendendola si ripone solo quello preso da quel momento.
static func forget_borrowed_tools(individuals: Array[HumanIndividual]) -> void:
	for member in individuals:
		member.borrowed_tools.clear()


# Regola "Prendi la sacca se disponibile" (2026-10-19, richiesta utente — GameData.job_board_take_bag): chiamata da
# HumanIndividualActionService.resolve_idle_individual appena `individual` si libera, prima della lista dei lavori (subito
# dopo la regola del vestiario). Senza sacca in cintura e con un posto libero va a prendere in deposito la sacca col bonus
# di capacità più alto (equip_tool.tres, in cintura). La sacca resta sua: niente borrowed_tools. Le sacche che altri stanno
# già andando a prendere (BAG_FETCH_KEY) non contano, così una sacca manda una persona sola. true = task assegnata.
static func try_take_bag(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or world == null or not game_data.job_board_take_bag:
		return false
	if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD:
		return false
	if HumanCalculator.get_equipped_carry_bonus(individual.equipped_tools) > 0.0:
		return false
	var slots := free_belt_slots(individual)
	if slots.is_empty() or not JobBoardService.is_enabled(GameSettings.active_human_folk):
		return false
	var reserved := _reserved_fetches(individual, BAG_FETCH_KEY)
	var bag_names := fetchable_tool_names(TaskTypes.ToolCategory.CARRYING)
	bag_names.sort_custom(func(a: String, b: String) -> bool:
		return _carry_bonus_of(a) > _carry_bonus_of(b)
	)
	var reachability := PathfindingService.reachability_for(individual)
	for bag_name in bag_names:
		var source := _find_free_source(individual, world, bag_name, reserved, reachability)
		if source == null:
			continue
		var task := TaskBuilderService.build_equip_tool_task(individual, source, bag_name, slots[0])
		if task == null:
			return false
		task.context[BAG_FETCH_KEY] = _fetch_key(source, bag_name)
		if not individual.assign_task(task, age_band):
			return false
		if storage_signal_connector.is_valid():
			storage_signal_connector.call(task, individual)
		if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
			print("[JOB BOARD] #%d %s: va a prendere %s in %s #%d (regola della sacca)." % [
				individual.id, individual.name, bag_name, source.building_type_name, source.id
			])
		return true
	return false


# Regola "Indossa i capi disponibili" (2026-10-19, richiesta utente — GameData.job_board_wear_apparel): chiamata da
# resolve_idle_individual appena libero, prima della sacca e della lista dei lavori. Il primo slot vuoto in ordine APPAREL_FETCH_ORDER sceglie il deposito (il più
# vicino con un capo del suo tipo); nello STESSO deposito si prendono anche i capi per gli altri slot vuoti, così è un
# viaggio solo: prima task assegnata, le altre accodate subito dopo. Quelli che lì mancano, a un momento libero successivo.
# Scelta per stagione (2026-10-20, richiesta utente): si considerano solo i capi convenienti nella stagione corrente
# (HumanVitalsInteractionService.is_apparel_convenient: meglio dello slot vuoto), dal punteggio più alto. Il primo slot
# sceglie il deposito più vicino che ha un capo della fascia di punteggio migliore disponibile, scendendo di fascia solo
# se nessuno ce l'ha; negli altri slot, nello stesso deposito, il capo conveniente col punteggio più alto e a parità
# quello con più pezzi. Solo slot vuoti: nessuno si toglie un capo indossato (il cambio stagionale è della Hut).
# L'unità prelevata è la più consumata (BuildingStorageService.withdraw_tool_units). I capi che altri stanno già andando
# a prendere (APPAREL_FETCH_KEY) non contano. Il capo resta suo. true = task assegnata.
static func try_wear_apparel(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or world == null or not game_data.job_board_wear_apparel:
		return false
	if not HumanIndividual.is_apparel_age_band(age_band):
		return false
	var empty_slots: Array[int] = []
	for slot in APPAREL_FETCH_ORDER:
		if individual.get_equipped_apparel(slot) == "":
			empty_slots.append(slot)
	if empty_slots.is_empty() or not JobBoardService.is_enabled(GameSettings.active_human_folk):
		return false
	var reserved := _reserved_fetches(individual, APPAREL_FETCH_KEY)
	var reachability := PathfindingService.reachability_for(individual)
	var season := HumanVitalsInteractionService.current_season()
	# Guardaroba di casa (2026-10-22, Hut): chi ci abita cerca prima lì, poi nei magazzini.
	var home := HouseWardrobeService.home_wardrobe(world, individual)
	var depot: Building = null
	var plan: Array[Dictionary] = []
	for slot in empty_slots:
		var chosen := ""
		var candidates := _convenient_apparel_for_slot(individual, slot, season)
		if depot == null:
			if home != null:
				chosen = _best_free_in(home, candidates, reserved)
				if chosen != "":
					depot = home
			# Fasce di punteggio dalla migliore: il deposito più vicino con un capo della fascia; la successiva solo se
			# nessun capo della fascia è disponibile.
			var index := 0
			while index < candidates.size() and depot == null:
				var tier_score := float(candidates[index]["score"])
				var best_distance := INF
				while index < candidates.size() and is_equal_approx(float(candidates[index]["score"]), tier_score):
					var apparel_name := String(candidates[index]["name"])
					index += 1
					var source := _find_free_source(individual, world, apparel_name, reserved, reachability)
					if source == null:
						continue
					var distance := _distance_to(individual, source)
					if distance < best_distance:
						best_distance = distance
						depot = source
						chosen = apparel_name
		else:
			var chosen_score := -INF
			var chosen_free := 0
			for candidate in candidates:
				var apparel_name := String(candidate["name"])
				var score := float(candidate["score"])
				var free := BuildingStorageService.get_available_quantity(depot, apparel_name) - int(reserved.get(_fetch_key(depot, apparel_name), 0))
				if free <= 0:
					continue
				if chosen == "" or score > chosen_score + 0.0001 or (is_equal_approx(score, chosen_score) and free > chosen_free):
					chosen = apparel_name
					chosen_score = score
					chosen_free = free
		if chosen == "":
			continue
		plan.append({"slot": slot, "name": chosen})
		var key := _fetch_key(depot, chosen)
		reserved[key] = int(reserved.get(key, 0)) + 1
	if plan.is_empty():
		return false
	var tasks: Array[Task] = []
	for entry in plan:
		var task := TaskBuilderService.build_tool_task(
			individual, TaskBuilderService.EQUIP_TOOL_TASK_DEFINITION_PATH, String(entry["name"]), depot, int(entry["slot"]), true
		)
		if task == null:
			continue
		task.context[APPAREL_FETCH_KEY] = _fetch_key(depot, String(entry["name"]))
		tasks.append(task)
	if tasks.is_empty() or not individual.assign_task(tasks[0], age_band):
		return false
	# La coda riprende dall'ultima (pop_back): i seguiti entrano al contrario, così escono nell'ordine degli slot.
	for index in range(tasks.size() - 1, 0, -1):
		TaskQueueService.push_follow_up_task(individual, tasks[index])
	for task in tasks:
		if storage_signal_connector.is_valid():
			storage_signal_connector.call(task, individual)
	if DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_LOGS:
		var names: Array[String] = []
		for entry in plan:
			names.append(String(entry["name"]))
		print("[JOB BOARD] #%d %s: va a prendere %s in %s #%d (regola del vestiario)." % [
			individual.id, individual.name, ", ".join(names), depot.building_type_name, depot.id
		])
	return true


# Primo capo di `candidates` ({"name", "score"}, dal migliore) con almeno un pezzo libero (meno le prenotazioni) in
# `building`; "" se nessuno.
static func _best_free_in(building: Building, candidates: Array, reserved: Dictionary) -> String:
	for candidate in candidates:
		var apparel_name := String(candidate["name"])
		if BuildingStorageService.get_available_quantity(building, apparel_name) - int(reserved.get(_fetch_key(building, apparel_name), 0)) > 0:
			return apparel_name
	return ""


# --- Guardaroba della Hut: cambio stagionale (2026-10-22, richiesta utente) ---
# Chi vive in una casa di nucleo (HouseWardrobeService.home_wardrobe), dall'adolescenza in su, con la regola "Indossa i capi
# disponibili", al primo momento libero cambia UN capo indossato con uno di punteggio stagionale strettamente migliore:
# prima dal guardaroba di casa (a casa ripone il vecchio e indossa il nuovo), altrimenti dal magazzino più vicino (lo
# mette nello zaino, torna a casa, ripone il vecchio e lo indossa — mai nudo). Guardaroba senza posto per il vecchio, o
# zaino senza posto per il nuovo: nessun cambio. Mai un cambio senza un capo migliore (mai nudi). true = task assegnata.
static func try_swap_seasonal_apparel(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or world == null or not game_data.job_board_wear_apparel:
		return false
	if not HumanIndividual.is_apparel_age_band(age_band) or not JobBoardService.is_enabled(GameSettings.active_human_folk):
		return false
	var home := HouseWardrobeService.home_wardrobe(world, individual)
	if home == null:
		return false
	var season := HumanVitalsInteractionService.current_season()
	var reserved := _reserved_fetches(individual, APPAREL_FETCH_KEY)
	var reachability := PathfindingService.reachability_for(individual)
	for slot in APPAREL_FETCH_ORDER:
		var current := individual.get_equipped_apparel(slot)
		if current == "" or BuildingStorageService.get_max_depositable(home, current) < 1:
			continue
		var current_score := HumanVitalsInteractionService.apparel_season_score(current, season)
		var better: Array[Dictionary] = []
		for apparel_name in apparel_names_for_slot(slot):
			var score := HumanVitalsInteractionService.apparel_season_score(apparel_name, season)
			if score > current_score + 0.0001:
				better.append({"name": apparel_name, "score": score})
		if better.is_empty():
			continue
		better.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
		var at_home := _best_free_in(home, better, reserved)
		if at_home != "":
			if not _has_backpack_room(individual, at_home):
				continue
			return _assign_depot_swap(individual, age_band, home, home, slot, current, at_home)
		for candidate in better:
			var apparel_name := String(candidate["name"])
			if not _has_backpack_room(individual, apparel_name):
				continue
			var source := _find_free_source(individual, world, apparel_name, reserved, reachability)
			if source != null and source != home:
				return _assign_depot_swap(individual, age_band, home, source, slot, current, apparel_name)
	return false


static func _has_backpack_room(individual: HumanIndividual, apparel_name: String) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(apparel_name)
	var space: float = rules.space_per_unit if rules != null else 0.0
	return individual.can_carry_variety(apparel_name) and individual.max_carry_capacity - individual.get_carried_space() >= space


# Cambio: prende il capo nuovo nello zaino da `source` (il guardaroba di casa o un magazzino, prenotato), poi a casa
# ripone il vecchio e indossa il nuovo dallo zaino (seguito). Il vecchio si toglie solo se il nuovo è nello zaino
# (UnloadAction.replace_with_apparel): mai nudi.
static func _assign_depot_swap(
	individual: HumanIndividual, age_band: HumanTypes.AgeBand, home: Building, source: Building, slot: int, current: String, new_name: String
) -> bool:
	var fetch := TaskBuilderService.build_tool_task(individual, TaskBuilderService.EQUIP_TOOL_TASK_DEFINITION_PATH, new_name, source, -1, true)
	var store := TaskBuilderService.build_tool_task(individual, TaskBuilderService.STORE_TOOL_TASK_DEFINITION_PATH, current, home, slot, true)
	if fetch == null or store == null:
		return false
	var replaced := false
	for step in store.steps:
		if step is UnloadAction:
			(step as UnloadAction).replace_with_apparel = new_name
			replaced = true
	if not replaced:
		return false
	fetch.context[APPAREL_FETCH_KEY] = _fetch_key(source, new_name)
	if not individual.assign_task(fetch, age_band):
		return false
	TaskQueueService.push_follow_up_task(individual, store)
	for task in [fetch, store]:
		if storage_signal_connector.is_valid():
			storage_signal_connector.call(task, individual)
	print("[WARDROBE] #%d %s: cambio di stagione, prende %s %s #%d per sostituire %s." % [
		individual.id, individual.name, new_name, "dal guardaroba di casa" if source == home else "in %s" % source.building_type_name,
		source.id, current,
	])
	return true


# Capi (categoria APPAREL) che vanno nello slot del vestiario `slot` (HumanIndividual.can_wear_in_slot).
static func apparel_names_for_slot(slot: int) -> Array[String]:
	var names: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		if HumanIndividual.can_wear_in_slot(resource_name, slot):
			names.append(resource_name)
	return names


# Capi per lo slot `slot` convenienti nella stagione `season` (HumanVitalsInteractionService.is_apparel_convenient), come
# {"name", "score"} dal punteggio più alto (2026-10-20, regola del vestiario).
static func _convenient_apparel_for_slot(individual: HumanIndividual, slot: int, season: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for apparel_name in apparel_names_for_slot(slot):
		if HumanVitalsInteractionService.is_apparel_convenient(individual, apparel_name, slot, season):
			result.append({"name": apparel_name, "score": HumanVitalsInteractionService.apparel_season_score(apparel_name, season)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return result


# true se un edificio qualsiasi ha un capo per lo slot `slot` (riga "Senza vestito" della campanella).
static func has_apparel_in_storage(world: World, slot: int) -> bool:
	for apparel_name in apparel_names_for_slot(slot):
		if WarehouseSelectionService.has_retrieval_source(world, apparel_name):
			return true
	return false


# Deposito raggiungibile più vicino con almeno un `resource_name` non prenotato (`reserved`: chiave _fetch_key -> quanti).
static func _find_free_source(individual: HumanIndividual, world: World, resource_name: String, reserved: Dictionary, reachability: Callable) -> Building:
	return _find_unreserved_source(world, individual.position, individual.home_macro_coords, resource_name, reserved, reachability)


static func _fetch_key(building: Building, resource_name: String) -> String:
	return "%d:%s" % [building.id, resource_name]


static func _distance_to(individual: HumanIndividual, building: Building) -> float:
	var offset := Vector2(Vector2i(building.macro_x, building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return individual.position.distance_to(Vector2(building.micro_x, building.micro_y) + offset)


# Prelievi già prenotati da altri (task aperte con `context_key` nel context): "id edificio:nome" -> quanti.
static func _reserved_fetches(except: HumanIndividual, context_key: String) -> Dictionary:
	# Tempo (2026-10-24, assegnatore): "deposito: prenotazioni" (giro su tutti i pipottini e le loro task).
	var timing := JobBoardTimingService.is_enabled()
	var started := JobBoardTimingService.now() if timing else 0
	var reserved: Dictionary = {}
	for member in GameSettings.active_human_individuals:
		if member == except:
			continue
		for task in JobWorkScanService.open_tasks(member):
			var key: Variant = task.context.get(context_key, null)
			if key != null:
				reserved[key] = int(reserved.get(key, 0)) + 1
	if timing:
		JobBoardTimingService.add("deposito: prenotazioni", started)
	return reserved


static func _carry_bonus_of(tool_name: String) -> float:
	var rules := CaloricCalculator.get_caloric_source_rules(tool_name)
	return rules.carry_capacity_bonus if rules != null else 0.0


# Primo slot della cintura con l'attrezzo `tool_name`, -1 se nessuno.
static func find_belt_slot_by_name(member: HumanIndividual, tool_name: String) -> int:
	if tool_name == "":
		return -1
	for slot in range(member.get_tool_slot_count()):
		if member.get_equipped_tool(slot) == tool_name:
			return slot
	return -1


# Dove riporre un attrezzo in prestito: l'edificio da cui è stato preso, se esiste ancora e lo accetta; altrimenti il
# deposito migliore (WarehouseSelectionService.find_best). null se nessuno.
static func _borrowed_tool_destination(world: World, member: HumanIndividual, tool_name: String, building_id: int) -> Building:
	var origin: Building = null
	if building_id >= 0:
		for building in world.buildings:
			if building.id == building_id:
				origin = building
				break
	if origin != null and not origin.is_demolished and origin.is_complete and BuildingStorageService.can_accept(origin, tool_name):
		return origin
	return WarehouseSelectionService.find_best(
		world, member.position, member.home_macro_coords, tool_name, 1, [], PathfindingService.reachability_for(member)
	)


# Attrezzi richiesti dalla ricetta (SecondaryResourceRules.recipe_required_tool_categories), vuoto se nessuno.
static func recipe_tool_categories(recipe: String) -> Array[TaskTypes.ToolCategory]:
	var categories: Array[TaskTypes.ToolCategory] = []
	var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe)
	if recipe_rules != null:
		categories.assign(recipe_rules.recipe_required_tool_categories)
	return categories


# Categorie di `categories` che nessun pipottino adulto (non neonato né bambino, le fasce escluse dalla Produce) ha in
# cintura o nello zaino (ToolGateService.has_tool_for, sola lettura) — 2026-10-09, ordini di produzione in coda.
static func categories_nobody_has(ctx: GameContext, categories: Array) -> Array:
	var missing: Array = []
	for category in categories:
		var owned := false
		for member in ctx.individuals:
			var age_band := ctx.age_band_of(member)
			if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD:
				continue
			if ToolGateService.has_tool_for(member, category):
				owned = true
				break
		if not owned:
			missing.append(category)
	return missing


# Categorie mancanti con esempi di attrezzi che le coprono (2026-09-25 — il messaggio deve dire QUALI attrezzi servono):
# "taglio (es. Coltello di pietra); caccia (es. Lancia di legno)". Una categoria senza alcun attrezzo noto compare col
# solo nome.
static func describe_missing_categories(categories: Array) -> String:
	var parts: PackedStringArray = []
	for category in categories:
		var category_name := GameContext.tr_text("tool_category_" + String(TaskTypes.ToolCategory.keys()[category]).to_lower())
		var examples: PackedStringArray = []
		for tool_name in ToolGateService.get_tools_covering(category):
			examples.append(IconRegistry.get_resource_display_name(tool_name))
		if examples.is_empty():
			parts.append(category_name)
		else:
			parts.append(GameContext.tr_text("tool_gate_category_with_examples").format({
				"category": category_name, "examples": ", ".join(examples),
			}))
	return "; ".join(parts)
