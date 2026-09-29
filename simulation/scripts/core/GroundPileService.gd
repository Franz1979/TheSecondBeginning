class_name GroundPileService
extends RefCounted

# Logica dei mucchi a terra (2026-09-26, richiesta utente — ground drop, vedi GroundPile). Stateless, funzioni
# statiche, stesso pattern di BuildingStorageService/ResourceDecayService: opera sempre su un GameData
# passato dal chiamante (GameData.ground_piles).
#
#   - drop_entries: lascia a terra delle voci di risorsa (formato zaino/magazzino) nella microcella del punto
#     dato, sommandole al mucchio già presente lì o creandone uno nuovo;
#   - get_available/take: lettura e prelievo per PickUpAction (sorgente GROUND_PILE). Gli attrezzi escono come
#     istanze con i loro usi residui (ToolInstance.take_units_from_entry);
#   - advance_daily: deperimento giornaliero (stessa formula dei magazzini, velocità DECAY_SPEED_MULTIPLIER) e
#     durata massima del mucchio (ExpiredObjectRules di GROUND_PILE, ground_pile_rules.tres).
# Un mucchio che resta vuoto (raccolta, deperimento) viene rimosso subito.

# Velocità del deperimento a terra rispetto allo standard (ResourceDecayService): all'aperto le risorse si
# rovinano il doppio più in fretta.
const DECAY_SPEED_MULTIPLIER: float = 2.0


# Posa dei mucchi (2026-09-26, richiesta utente — mucchio davanti all'edificio, vedi find_drop_microcell).
# Raggio massimo (anelli di microcelle, distanza di Chebyshev) entro cui cercare una microcella libera; oltre,
# il carico va perso.
const MAX_DROP_SEARCH_RADIUS: int = 6
# Un mucchio esistente entro questa distanza dal punto di partenza viene preferito a una microcella vuota. 0 dal
# 2026-09-29 (richiesta utente — prima 2, un annullo di cantiere finiva "nascosto" in un mucchio vicino): si unisce
# solo a un mucchio nella STESSA microcella del punto di caduta, altrimenti nasce un mucchio nuovo. In ogni caso non
# esistono mai due mucchi nella stessa microcella: drop_entries/drop_carcass cercano sempre il mucchio della
# microcella scelta (find_at) prima di crearne uno, anche quando la ricerca ad anelli sceglie una microcella che ne
# ha già uno.
const MERGE_WITH_EXISTING_RADIUS: int = 0


# Lascia a terra `entries` (resource_name -> voce nel formato zaino/magazzino) partendo dal punto `position`
# (microcelle locali a `macro_coords`): la microcella di posa è scelta da find_drop_microcell, così un mucchio
# non nasce mai sopra un edificio, un cantiere, l'acqua, il fiume o un sasso. Nessuno si sposta: il mucchio
# nasce dove c'è posto. Ritorna il mucchio che ha ricevuto le voci; null se non c'era nulla da lasciare,
# game_data manca o non c'è una microcella libera entro MAX_DROP_SEARCH_RADIUS (carico perso).
static func drop_entries(game_data: GameData, macro_coords: Vector2i, position: Vector2, entries: Dictionary, world: World = null) -> GroundPile:
	if game_data == null or entries.is_empty():
		return null
	var resolved_world: World = world if world != null else GameSettings.active_world
	var drop_microcell: Variant = find_drop_microcell(game_data, resolved_world, macro_coords, microcell_for(position))
	if drop_microcell == null:
		push_warning("GroundPileService: nessuna microcella libera entro %d da %s in %s — carico perso (%s)." % [
			MAX_DROP_SEARCH_RADIUS, microcell_for(position), macro_coords, str(entries.keys())
		])
		return null
	var microcell: Vector2i = drop_microcell
	var pile := find_at(game_data, macro_coords, microcell)
	var created := false
	if pile == null:
		pile = _new_pile(game_data, macro_coords, microcell)
		created = true
	for resource_name in entries.keys():
		_merge_entry(pile, String(resource_name), entries[resource_name])
	if pile.is_empty():
		return null
	if created:
		game_data.ground_piles.append(pile)
	pile.revision += 1
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[GROUND PILE] mucchio #%d in %s microcella %s: %s (ora contiene %s)." % [
			pile.id, macro_coords, microcell, "creato" if created else "aggiornato", str(pile.resources)
		])
	return pile


# Svuota a terra un edificio (2026-09-27, richiesta utente — "Svuota tutto", riusabile dalla futura demolizione):
# deposito (stored_resources) e buffer dei prodotti (production_output) finiscono in UN mucchio posato con la regola
# di drop_entries a partire dalla microcella dell'edificio (davanti alla porta se ne ha una, altrimenti la prima
# microcella libera vicina). Le voci del deposito conservano deperimento e usura degli attrezzi; i pezzi del buffer
# entrano freschi (decay_fraction 0.0) e, se la stessa risorsa è anche nel deposito, si sommano a quella voce con la
# media pesata. L'edificio viene svuotato SEMPRE, anche senza una microcella libera: in quel caso il contenuto va
# perso (drop_entries lo segnala con un avviso). Non tocca production_progress. Ritorna il mucchio, o null se
# l'edificio era vuoto o non c'era posto.
# `extra_fresh` (2026-09-27, Demolish Task): nome risorsa -> quantità (int) aggiunte allo STESSO mucchio come i pezzi
# del buffer (fresche, sommate con la media pesata) — i materiali recuperati dalla demolizione.
static func drop_building_contents(game_data: GameData, building: Building, world: World = null, extra_fresh: Dictionary = {}) -> GroundPile:
	if building == null:
		return null
	var entries: Dictionary = building.stored_resources.duplicate(true)
	_merge_fresh_entries(entries, building.production_output)
	_merge_fresh_entries(entries, extra_fresh)
	building.stored_resources.clear()
	building.production_output.clear()
	if entries.is_empty():
		return null
	var building_position := Vector2(float(building.micro_x) + 0.5, float(building.micro_y) + 0.5)
	return drop_entries(game_data, Vector2i(building.macro_x, building.macro_y), building_position, entries, world)


# Somma a `entries` (formato magazzino) le quantità fresche di `fresh` (nome -> int, decay_fraction 0.0): una risorsa
# già presente si somma alla sua voce con la media pesata del deperimento.
static func _merge_fresh_entries(entries: Dictionary, fresh: Dictionary) -> void:
	for output_name in fresh.keys():
		var output_quantity: int = int(fresh[output_name])
		if output_quantity <= 0:
			continue
		var existing: Dictionary = entries.get(output_name, {})
		var existing_quantity: int = int(existing.get("quantity", 0))
		if existing_quantity <= 0:
			entries[output_name] = {"quantity": output_quantity, "decay_fraction": 0.0}
			continue
		var total_quantity: int = existing_quantity + output_quantity
		existing["decay_fraction"] = float(existing_quantity) * float(existing.get("decay_fraction", 0.0)) / float(total_quantity)
		existing["quantity"] = total_quantity
		entries[output_name] = existing


# Lascia a terra la carcassa di un animale ucciso (2026-09-26, richiesta utente — carcassa a terra) partendo
# dal punto `position` della preda (microcelle locali a `macro_coords`): stessa regola di posa di drop_entries
# (find_drop_microcell — microcella libera più vicina, mucchio esistente se c'è). La carcassa è un contenuto
# speciale del mucchio (GroundPile.carcasses), non una voce di risorsa. Ritorna il mucchio, null se non c'è
# posto (carcassa persa) o game_data manca.
static func drop_carcass(
	game_data: GameData, macro_coords: Vector2i, position: Vector2, species: String, age_band: int, world: World = null
) -> GroundPile:
	if game_data == null or species == "":
		return null
	var resolved_world: World = world if world != null else GameSettings.active_world
	var drop_microcell: Variant = find_drop_microcell(game_data, resolved_world, macro_coords, microcell_for(position))
	if drop_microcell == null:
		push_warning("GroundPileService: nessuna microcella libera entro %d da %s in %s — carcassa di %s persa." % [
			MAX_DROP_SEARCH_RADIUS, microcell_for(position), macro_coords, species
		])
		return null
	var microcell: Vector2i = drop_microcell
	var pile := find_at(game_data, macro_coords, microcell)
	if pile == null:
		pile = _new_pile(game_data, macro_coords, microcell)
		game_data.ground_piles.append(pile)
	pile.carcasses.append({
		"id": game_data.allocate_ground_pile_id(),
		"species": species, "age_band": age_band, "killed_year": game_data.year, "killed_day": game_data.current_day,
	})
	pile.revision += 1
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[GROUND PILE] carcassa di %s (fascia %d) nel mucchio #%d in %s microcella %s." % [
			species, age_band, pile.id, macro_coords, microcell
		])
	return pile


# Carcassa con questo id nel mucchio della microcella, {} se non c'è più (marcita, macellata, mucchio sparito).
static func find_carcass(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i, carcass_id: int) -> Dictionary:
	var pile := find_at(game_data, macro_coords, microcell)
	if pile == null:
		return {}
	for carcass in pile.carcasses:
		if int(carcass.get("id", -1)) == carcass_id:
			return carcass
	return {}


# Toglie la carcassa con questo id dal mucchio della microcella (macellazione); il mucchio rimasto vuoto viene
# rimosso. Ritorna true se la carcassa c'era.
static func remove_carcass(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i, carcass_id: int) -> bool:
	var pile := find_at(game_data, macro_coords, microcell)
	if pile == null:
		return false
	for i in range(pile.carcasses.size()):
		if int(pile.carcasses[i].get("id", -1)) == carcass_id:
			pile.carcasses.remove_at(i)
			pile.revision += 1
			if pile.is_empty():
				remove_pile(game_data, pile)
			return true
	return false


# Giorni prima che la carcassa marcisca (pannello), 0 se le regole mancano.
static func get_carcass_days_remaining(game_data: GameData, carcass: Dictionary) -> int:
	var rules := ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.CARCASS)
	if rules == null or game_data == null:
		return 0
	return ExpiredObjectCalculator.get_days_remaining(GroundPile.get_carcass_expiry_record(carcass), rules, game_data.year, game_data.current_day)


static func _new_pile(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i) -> GroundPile:
	var pile := GroundPile.new()
	pile.id = game_data.allocate_ground_pile_id()
	pile.macro_coords = macro_coords
	pile.microcell = microcell
	pile.appeared_at_year = game_data.year
	pile.appeared_at_day = game_data.current_day
	return pile


# Microcella in cui posare un mucchio partendo da `start` (dentro `macro_coords`, la ricerca non esce mai dalla
# macrocella). Microcella libera = BuildingVerificationService.is_microcell_free (niente acqua, fiume, sassi,
# edifici o cantieri; gli edifici MOVEMENT come i sentieri non bloccano; gli alberi sono ammessi). Ordine:
#   1. un mucchio esistente su una microcella libera entro MERGE_WITH_EXISTING_RADIUS da `start` (il più vicino; con
#      raggio 0 solo quello in `start` stessa);
#   2. se `start` è occupata da un edificio con porta, la microcella davanti alla porta;
#   3. anelli concentrici attorno a `start` (raggio 0, 1, …, MAX_DROP_SEARCH_RADIUS): la prima microcella
#      libera, la più vicina a `start` dentro l'anello.
# null se non c'è posto. world null = nessun controllo sugli ostacoli (si posa in `start`).
static func find_drop_microcell(game_data: GameData, world: World, macro_coords: Vector2i, start: Vector2i) -> Variant:
	if world == null:
		return start
	var macro_cell := world.get_cell_at(macro_coords.x, macro_coords.y)
	var macro_state := world.get_cell_state_at(macro_coords.x, macro_coords.y)
	if macro_cell == null:
		return null
	var river_lookup := BuildingVerificationService.get_river_lookup(macro_cell, macro_state)
	# Ostacoli raccolti UNA volta per tutta la ricerca (2026-09-27, MicrocellObstacles): stessa regola di
	# BuildingVerificationService.is_microcell_free, senza rifare le scansioni per ogni microcella candidata.
	var obstacles := MicrocellObstacles.build(macro_coords, macro_cell, macro_state, river_lookup, world)
	var is_free := func(microcell: Vector2i) -> bool:
		if microcell.x < 0 or microcell.y < 0 or microcell.x >= World.WIDTH or microcell.y >= World.HEIGHT:
			return false
		return obstacles.is_free(microcell, false, false, false, true)

	# 1. Mucchio già vicino.
	var best_pile: GroundPile = null
	var best_distance := INF
	if game_data != null:
		for pile in game_data.ground_piles:
			if pile.macro_coords != macro_coords:
				continue
			var offset: Vector2i = pile.microcell - start
			if maxi(absi(offset.x), absi(offset.y)) > MERGE_WITH_EXISTING_RADIUS:
				continue
			var distance := Vector2(offset).length()
			if distance < best_distance and is_free.call(pile.microcell):
				best_distance = distance
				best_pile = pile
	if best_pile != null:
		return best_pile.microcell

	# 2. Davanti alla porta dell'edificio che occupa il punto di partenza.
	for building in world.buildings:
		if building.macro_x != macro_coords.x or building.macro_y != macro_coords.y:
			continue
		if building.micro_x != start.x or building.micro_y != start.y:
			continue
		var door := BuildingVerificationService.get_door_front(building)
		if not door.is_empty() and door["macro"] == macro_coords and is_free.call(door["micro"]):
			return door["micro"]
		break

	# 3. Anelli concentrici.
	for radius in range(MAX_DROP_SEARCH_RADIUS + 1):
		var best_cell: Variant = null
		var best_cell_distance := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := start + Vector2i(dx, dy)
				var distance := Vector2(dx, dy).length()
				if distance < best_cell_distance and is_free.call(candidate):
					best_cell_distance = distance
					best_cell = candidate
		if best_cell != null:
			return best_cell
	return null


# Microcella di un punto, limitata alla macrocella (un individuo appena oltre il bordo resta sul bordo).
static func microcell_for(position: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(floor(position.x)), 0, World.WIDTH - 1),
		clampi(int(floor(position.y)), 0, World.HEIGHT - 1)
	)


static func find_at(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i) -> GroundPile:
	if game_data == null:
		return null
	for pile in game_data.ground_piles:
		if pile.macro_coords == macro_coords and pile.microcell == microcell:
			return pile
	return null


static func find_by_id(game_data: GameData, pile_id: int) -> GroundPile:
	if game_data == null:
		return null
	for pile in game_data.ground_piles:
		if pile.id == pile_id:
			return pile
	return null


# Quantità di `resource_name` nel mucchio della microcella, 0 se non c'è mucchio o risorsa.
static func get_available(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i, resource_name: String) -> int:
	var pile := find_at(game_data, macro_coords, microcell)
	return pile.get_quantity(resource_name) if pile != null else 0


# Preleva fino a `quantity` unità di `resource_name` dal mucchio della microcella. Ritorna
# {"quantity": int, "decay_fraction": float, "units": Array} — `units` sono le istanze ToolInstance per un
# attrezzo (prima le più consumate, come dal magazzino), vuoto per le altre risorse. Il mucchio rimasto vuoto
# viene rimosso.
static func take(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i, resource_name: String, quantity: int) -> Dictionary:
	var result := {"quantity": 0, "decay_fraction": 0.0, "units": []}
	var pile := find_at(game_data, macro_coords, microcell)
	if pile == null or quantity <= 0 or not pile.resources.has(resource_name):
		return result
	var entry: Dictionary = pile.resources[resource_name]
	result["decay_fraction"] = float(entry.get("decay_fraction", 0.0))
	if ToolInstance.is_tool_resource(resource_name):
		var units: Array = ToolInstance.take_units_from_entry(entry, quantity, ToolInstance.get_max_uses(resource_name))
		result["units"] = units
		result["quantity"] = units.size()
	else:
		var taken: int = mini(quantity, int(entry.get("quantity", 0)))
		entry["quantity"] = int(entry.get("quantity", 0)) - taken
		result["quantity"] = taken
	if int(entry.get("quantity", 0)) <= 0:
		pile.resources.erase(resource_name)
	else:
		pile.resources[resource_name] = entry
	pile.revision += 1
	if pile.is_empty():
		remove_pile(game_data, pile)
	return result


static func remove_pile(game_data: GameData, pile: GroundPile) -> void:
	if game_data == null or pile == null:
		return
	game_data.ground_piles.erase(pile)
	pile.revision += 1


# Giro giornaliero: deperimento di ogni voce (stessa formula di ResourceDecayService.advance_building_decay,
# a velocità DECAY_SPEED_MULTIPLIER; day_durability -1 = non deperisce), poi durata massima del mucchio
# (ExpiredObjectCalculator con le regole di GROUND_PILE). Una voce a fine vita sparisce; un mucchio vuoto o
# scaduto viene rimosso. Ritorna quanti mucchi sono stati rimossi (solo per il log).
static func advance_daily(game_data: GameData) -> int:
	if game_data == null or game_data.ground_piles.is_empty():
		return 0
	var rules := ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.GROUND_PILE)
	var carcass_rules := ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.CARCASS)
	var removed: Array[GroundPile] = []
	for pile in game_data.ground_piles:
		# La durata massima del mucchio vale per le RISORSE (2026-09-26): scaduta, le risorse spariscono, ma le
		# carcasse restano fino a quando marciscono (hanno la loro durata, carcass_rules.tres).
		if rules != null and not pile.resources.is_empty() and ExpiredObjectCalculator.is_expired(pile.get_expiry_record(), rules, game_data.year, game_data.current_day):
			pile.resources.clear()
			pile.revision += 1
		_advance_pile_decay(pile)
		_rot_carcasses(pile, carcass_rules, game_data)
		if pile.is_empty():
			removed.append(pile)
	for pile in removed:
		remove_pile(game_data, pile)
	if not removed.is_empty() and DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[GROUND PILE] %d mucchi rimossi oggi (vuoti o scaduti), rimasti %d." % [removed.size(), game_data.ground_piles.size()])
	return removed.size()


# Giorni che mancano alla scadenza del mucchio (pannello), 0 se le regole mancano.
static func get_days_remaining(game_data: GameData, pile: GroundPile) -> int:
	var rules := ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.GROUND_PILE)
	if rules == null or game_data == null:
		return 0
	return ExpiredObjectCalculator.get_days_remaining(pile.get_expiry_record(), rules, game_data.year, game_data.current_day)


# Carcasse marcite (giorni di carcass_rules.tres trascorsi dall'uccisione): spariscono dal mucchio.
static func _rot_carcasses(pile: GroundPile, carcass_rules: ExpiredObjectRules, game_data: GameData) -> void:
	if carcass_rules == null or pile.carcasses.is_empty():
		return
	var kept: Array = []
	for carcass in pile.carcasses:
		if not ExpiredObjectCalculator.is_expired(GroundPile.get_carcass_expiry_record(carcass), carcass_rules, game_data.year, game_data.current_day):
			kept.append(carcass)
	if kept.size() != pile.carcasses.size():
		pile.carcasses = kept
		pile.revision += 1


static func _advance_pile_decay(pile: GroundPile) -> void:
	var expired_names: Array = []
	var changed := false
	for resource_name in pile.resources.keys():
		var rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if rules == null or rules.day_durability == -1:
			continue
		var entry: Dictionary = pile.resources[resource_name]
		var decay_before: float = float(entry.get("decay_fraction", 0.0))
		var daily_step: float = DECAY_SPEED_MULTIPLIER / float(rules.day_durability)
		var decay_fraction: float = decay_before + daily_step
		if DebugLogging.ENABLED and DebugLogging.SHOW_RESOURCE_DECAY_LOGS:
			ResourceDecayService.log_decay_line("mucchio #%d %s/%s" % [pile.id, pile.macro_coords, pile.microcell], String(resource_name),
				int(entry.get("quantity", 0)), decay_before, decay_fraction, daily_step)
		changed = true
		if decay_fraction >= 1.0:
			expired_names.append(resource_name)
			continue
		entry["decay_fraction"] = decay_fraction
		pile.resources[resource_name] = entry
	for resource_name in expired_names:
		pile.resources.erase(resource_name)
	if changed:
		pile.revision += 1


# Somma una voce al mucchio: quantità sommate, decay_fraction come media pesata sulla quantità (stessa formula
# di BuildingStorageService.store e HumanIndividual.add_carried_resource), istanze usate degli attrezzi
# accodate (copie normalizzate, solo quelle ancora utilizzabili).
static func _merge_entry(pile: GroundPile, resource_name: String, incoming: Dictionary) -> void:
	var incoming_quantity: int = int(incoming.get("quantity", 0))
	if incoming_quantity <= 0:
		return
	var entry: Dictionary = (pile.resources.get(resource_name, {}) as Dictionary).duplicate(true)
	var current_quantity: int = int(entry.get("quantity", 0))
	var new_quantity: int = current_quantity + incoming_quantity
	entry["decay_fraction"] = (
		float(current_quantity) * float(entry.get("decay_fraction", 0.0))
		+ float(incoming_quantity) * float(incoming.get("decay_fraction", 0.0))
	) / float(new_quantity)
	entry["quantity"] = new_quantity
	var used_instances: Array = ToolInstance.get_used_instances(entry).duplicate()
	for instance in ToolInstance.get_used_instances(incoming):
		if instance is Dictionary and ToolInstance.is_usable(instance):
			used_instances.append(ToolInstance.normalized(instance))
	ToolInstance.set_used_instances(entry, used_instances)
	pile.resources[resource_name] = entry


# Ricostruisce un mucchio da GroundPile.to_save_data (GameLoadService). `parse_resources` = il parser delle voci
# già usato per i magazzini (GameLoadService._parse_stored_resources), passato dal chiamante.
static func from_save_data(data: Dictionary, parse_resources: Callable) -> GroundPile:
	var pile := GroundPile.new()
	pile.id = int(data.get("id", 0))
	pile.macro_coords = Vector2i(int(data.get("macro_x", 0)), int(data.get("macro_y", 0)))
	pile.microcell = Vector2i(int(data.get("micro_x", 0)), int(data.get("micro_y", 0)))
	pile.appeared_at_year = int(data.get("appeared_at_year", 0))
	pile.appeared_at_day = int(data.get("appeared_at_day", 0))
	var raw_resources = data.get("resources", {})
	pile.resources = parse_resources.call(raw_resources if raw_resources is Dictionary else {})
	# Carcasse (2026-09-26) — .get(key, []) per i salvataggi precedenti; numeri normalizzati (JSON li rende float).
	var raw_carcasses = data.get("carcasses", [])
	if raw_carcasses is Array:
		for raw_carcass in raw_carcasses:
			if raw_carcass is Dictionary and String(raw_carcass.get("species", "")) != "":
				pile.carcasses.append({
					# -1 = salvataggio senza id (precedente alla macellazione): GameLoadService ne assegna uno.
					"id": int(raw_carcass.get("id", -1)),
					"species": String(raw_carcass["species"]),
					"age_band": int(raw_carcass.get("age_band", GameTypes.AgeBand.ADULT)),
					"killed_year": int(raw_carcass.get("killed_year", 0)),
					"killed_day": int(raw_carcass.get("killed_day", 0)),
				})
	return pile
