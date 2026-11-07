class_name WaterShelterStockService
extends RefCounted

# Regola del gestore scorte "Acqua per tettoia" (2026-11-07, richiesta utente — Vasellame, giare: passo 3, regola generale).
# Un solo valore per tutte le Tettoie dell'acqua (GameData.stock_water_per_shelter, 0 = spenta), al massimo la capienza
# d'acqua di una tettoia. A ogni inventario, per ogni tettoia completa e in servizio: appena l'acqua (con i viaggi già
# decisi) scende sotto il valore, un ordine "transport" del cassetto con WATER_TARGET_KEY e "quantity" = giare da riempire
# (WaterJarService.trips_to_reach). Un ordine aperto per tettoia: aggiornato, o tolto se non serve più. Chi lo prende fa il
# riempimento come il comando diretto (serve un travois). Senza stato.
# Valore della singola tettoia (2026-11-07): Building.water_target_override, dal pannello della tettoia (target_for).
# Giare scarse (2026-11-07, richiesta utente): i viaggi oltre le giare vuote della tettoia vogliono una giara dal magazzino;
# quelle in magazzino vanno prima alla tettoia più a secco rispetto al suo livello (acqua / livello più basso). Una tettoia
# che resta senza viaggi possibili non ha ordine; le giare che mancano in tutto vanno nell'avviso ("missing": riga rossa
# del WM e campanella, StockRuntimeState.water_jars_missing). La produzione automatica delle giare NON si fa (decisione
# utente 2026-11-07).

# Nell'ordine del cassetto: id della tettoia da riempire.
const WATER_TARGET_KEY := "water_shelter_target_id"


# Tettoia che la regola serve: completa, non demolita, in servizio.
static func is_served(building: Building) -> bool:
	return WaterJarService.is_shelter(building) and building.is_complete and not building.is_demolished and not building.is_out_of_service()


# Acqua voluta in `shelter`: il valore suo (Building.water_target_override; 0 = esclusa), altrimenti la regola generale;
# al massimo quanta ne può tenere.
static func target_for(shelter: Building, game_data: GameData) -> int:
	var level := shelter.water_target_override
	if level < 0:
		level = game_data.stock_water_per_shelter if game_data != null else 0
	return clampi(level, 0, WaterJarService.shelter_capacity(shelter) * WaterJarService.jar_water_capacity())


# true se il WM è sbloccato (idea della gestione scorte): solo allora il pannello della tettoia mostra "Livello voluto".
static func is_rule_available() -> bool:
	var folk: Folk = GameSettings.active_human_folk
	return folk != null and folk.completed_ideas.has(WarehousePanel.REQUIRED_IDEA_ID)


# Massimo del valore della regola: l'acqua di una tettoia con tutti i posti pieni di giare piene.
static func max_water_per_shelter() -> int:
	var rules := BuildingCalculator.get_building_rules(WaterJarService.SHELTER_TYPE)
	if rules == null:
		return 0
	return rules.storage_slot_count * WaterJarService.jar_water_capacity()


# Ordini da togliere (id), da aggiornare ({"order", "quantity"}) e da creare ({WATER_TARGET_KEY, "quantity"}), più
# "missing" (giare che mancano nei magazzini). `open_orders`: gli ordini del cassetto con WATER_TARGET_KEY (si tolgono alla
# presa: sono tutti non presi); `storage_jars`: giare nei magazzini (scorta del villaggio, le tettoie non contano).
static func plan_orders(world: World, game_data: GameData, open_orders: Array, storage_jars: int) -> Dictionary:
	var result := {"remove": [], "update": [], "create": [], "missing": 0}
	var open_by_target: Dictionary = {}
	for order in open_orders:
		var target_id := int(order.get(WATER_TARGET_KEY, -1))
		if open_by_target.has(target_id):
			(result["remove"] as Array).append(int(order["id"]))
		else:
			open_by_target[target_id] = order
	var served: Dictionary = {}
	var needs: Array[Dictionary] = []
	var available := storage_jars
	if world != null:
		for building in world.buildings:
			if not is_served(building):
				continue
			# Giare già attese da un magazzino da viaggi decisi (anche a mano): non sono più disponibili per altri.
			available -= WaterJarService.pending_storage_trips(building)
			var target := target_for(building, game_data)
			if target <= 0:
				continue
			var trips := WaterJarService.trips_to_reach(building, target)
			if trips <= 0:
				continue
			needs.append({
				"building": building, "trips": trips, "own": WaterJarService.free_empty_jars(building),
				"ratio": float(WaterJarService.shelter_water(building)) / float(target),
			})
	# Prima la più a secco rispetto al suo livello; a parità, l'id più basso (ordine stabile).
	needs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["ratio"]), float(b["ratio"])):
			return float(a["ratio"]) < float(b["ratio"])
		return (a["building"] as Building).id < (b["building"] as Building).id
	)
	available = maxi(available, 0)
	for need in needs:
		var building: Building = need["building"]
		var from_storage := maxi(int(need["trips"]) - int(need["own"]), 0)
		var given := mini(from_storage, available)
		available -= given
		result["missing"] = int(result["missing"]) + from_storage - given
		var trips := mini(int(need["trips"]), int(need["own"]) + given)
		if trips <= 0:
			continue
		served[building.id] = true
		if open_by_target.has(building.id):
			var order: Dictionary = open_by_target[building.id]
			if int(order.get("quantity", 0)) != trips:
				(result["update"] as Array).append({"order": order, "quantity": trips})
		else:
			(result["create"] as Array).append({WATER_TARGET_KEY: building.id, "quantity": trips})
	for target_id in open_by_target.keys():
		if not served.has(int(target_id)):
			(result["remove"] as Array).append(int(open_by_target[target_id]["id"]))
	return result

