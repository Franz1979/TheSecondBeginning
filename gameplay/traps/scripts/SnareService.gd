class_name SnareService
extends RefCounted

# Catture dei lacci (2026-11-09, TrapService.QUARRY_SMALL_GAME): conigli e pernici veri, presi dalle mandrie della fauna
# ad hoc (WildFaunaService) solo quando passano dove sta il laccio. Solo celle accese: è lì che le mandrie hanno i gruppetti
# disegnati (AnimalGroupRenderer) con una posizione.
#   - Passaggi (sample_hour, ogni ora di gioco): per ogni area dei lacci (la zona di caccia del laccio, o un quadrato
#     attorno a quello piazzato fuori zona) e ogni specie preda (trap_prey_species), +1 se il centro di un gruppetto è
#     dentro l'area. GameData.snare_passages, azzerati a fine giornata (end_day).
#   - Tiro (roll_catch, fine giornata da TrapService.advance_daily): per specie trap_daily_catch_chance × peso della specie
#     × passaggi / trap_full_passage_hours (al massimo 1); al massimo una preda al giorno per laccio.
#   - Preda (take_prey): un capo in meno nella mandria (remove_one) e la figura più vicina al laccio tolta dalla mappa.
#   - Disturbo: dopo una cattura i gruppetti di quella specie evitano l'area per trap_disturbance_days giorni
#     (AnimalGroupRenderer.avoid_rects, spinti fuori come dagli edifici); in quei giorni nessun passaggio.
# Celle spente: nessun passaggio e quindi nessuna cattura. DA FARE: decidere cosa succede quando la cella non è accesa
# (vale per tutte le trappole: rete e nassa oggi prendono anche lì).
# Fossa con pali (2026-11-11): stessa logica per le prede grosse (TrapService.QUARRY_BIG_GAME); le specie di ogni trappola
# da TrapService.prey_species (max_hunters), i pesi per nome (trap_prey_weights).
# Statico; lo stato (passaggi, disturbi, ultima ora contata) sta in GameData.

const HOURS_PER_DAY := 24

# TEMPORANEO (misura 2026-11-12, con _log_day_measure): per area e specie, {"min", "sum", "n"} della distanza oraria dal
# rettangolo del centro di gruppetto più vicino, e "building" = distanza dall'edificio non stradale più vicino, "avoid" = raggio
# da cui i centri stanno lontani. Azzerata a fine giornata.
static var _measure := {}
# Righe MISURA delle mandrie (passaggi, distanze): spente il 2026-11-13, i passaggi sono verificati.
const _MEASURE_LOGS := false


# Ora di gioco nuova: conta i passaggi nelle celle accese con lacci e aggiorna le aree da evitare dei gruppetti.
static func sample_hour(game_data: GameData, live_cells: Dictionary, day_progress: float) -> void:
	if game_data == null:
		return
	var day := game_data.get_absolute_day()
	var slot := day * HOURS_PER_DAY + clampi(int(day_progress * HOURS_PER_DAY), 0, HOURS_PER_DAY - 1)
	if slot == game_data.snare_sample_slot:
		return
	game_data.snare_sample_slot = slot
	_prune_disturbances(game_data, day)
	_apply_avoidance(game_data, live_cells)
	# Aree dei lacci per cella accesa: coords -> {chiave area: {"rect", "species"}}.
	var areas_by_cell := {}
	for trap in game_data.placed_traps:
		var rules := TrapService.get_rules(trap.trap_name)
		if rules == null or not TrapService.is_herd_quarry(rules) or not live_cells.has(trap.macro_coords):
			continue
		var area := passage_area(game_data, trap, rules)
		if not areas_by_cell.has(trap.macro_coords):
			areas_by_cell[trap.macro_coords] = {}
		# Più trappole nella stessa area (lacci, cesto, fossa): si uniscono le loro prede, senza sovrascriverle.
		var entry: Dictionary = areas_by_cell[trap.macro_coords].get(area["key"], {"rect": area["rect"], "species": []})
		for species in TrapService.prey_species(rules):
			if not entry["species"].has(species):
				entry["species"].append(species)
		areas_by_cell[trap.macro_coords][area["key"]] = entry
	for coords in areas_by_cell:
		var cell: LiveMacroCell = live_cells[coords]
		var areas: Dictionary = areas_by_cell[coords]
		for area_key in areas:
			var rect: Rect2 = areas[area_key]["rect"]
			for species in areas[area_key]["species"]:
				var renderer: AnimalGroupRenderer = cell.animal_renderers.get(species)
				if renderer == null or is_disturbed(game_data, area_key, species, day):
					continue
				if _MEASURE_LOGS:
					_measure_hour(_key(area_key, species), rect, renderer)
				# Passaggio (2026-11-12, richiesta utente): basta un animale qualunque della mandria dentro l'area, non il
				# centro del suo gruppetto. Vale per tutte le trappole a mandria: lacci, cesti e fosse.
				if renderer.has_individual_in_rect(rect):
					var key := _key(area_key, species)
					game_data.snare_passages[key] = int(game_data.snare_passages.get(key, 0)) + 1


# Area dei passaggi del laccio: la sua zona di caccia, o (piazzato fuori zona) un quadrato di lato 2×trap_passage_radius+1
# attorno a lui. {"key": String, "rect": Rect2 in microcelle}.
static func passage_area(game_data: GameData, trap: PlacedTrap, rules: SecondaryResourceRules) -> Dictionary:
	var area := WorkAreaService.find_by_id(game_data, trap.work_area_id) if trap.work_area_id > 0 else null
	if area != null:
		return {"key": "zone%d" % area.id, "rect": Rect2(area.rect)}
	var radius := maxi(rules.trap_passage_radius, 0)
	return {"key": "trap%d" % trap.id, "rect": Rect2(Vector2(trap.lot - Vector2i(radius, radius)), Vector2.ONE * float(radius * 2 + 1))}


static func is_disturbed(game_data: GameData, area_key: String, species: String, day: int) -> bool:
	var entry: Dictionary = game_data.snare_disturbances.get(_key(area_key, species), {})
	return not entry.is_empty() and int(entry.get("until_day", 0)) > day


# Specie presa oggi dal laccio, o "" se nessuna. `roll` in 0..1.
static func roll_catch(game_data: GameData, trap: PlacedTrap, rules: SecondaryResourceRules, roll: float) -> String:
	var area_key := String(passage_area(game_data, trap, rules)["key"])
	var day := game_data.get_absolute_day()
	var herds := WildFaunaService.get_herds_in_cell(game_data, trap.macro_coords)
	var full_hours := maxf(float(rules.trap_full_passage_hours), 1.0)
	var threshold := 0.0
	for species in TrapService.prey_species(rules):
		var passages := int(game_data.snare_passages.get(_key(area_key, species), 0))
		if passages <= 0 or not herds.has(species) or is_disturbed(game_data, area_key, species, day):
			continue
		var weight := float(rules.trap_prey_weights.get(species, 1.0))
		threshold += rules.trap_daily_catch_chance * weight * minf(float(passages) / full_hours, 1.0)
		if roll < threshold:
			return species
	return ""


# Preda presa: la figura della specie più vicina al laccio sparisce dalla mappa, la mandria perde un capo della sua età e
# l'area resta evitata da quella specie per trap_disturbance_days giorni. Restituisce la fascia d'età della preda.
static func take_prey(game_data: GameData, trap: PlacedTrap, rules: SecondaryResourceRules, species: String) -> int:
	var age_band := int(GameTypes.AgeBand.ADULT)
	var live_cell := PathfindingService.get_live_cell(trap.macro_coords)
	var renderer: AnimalGroupRenderer = live_cell.animal_renderers.get(species) if live_cell != null else null
	if renderer != null:
		var nearest: AnimalVisualGroup = null
		var nearest_distance := INF
		var snare_point := Vector2(trap.lot) + Vector2(0.5, 0.5)
		for body in renderer.get_individuals():
			var distance: float = (body as AnimalVisualGroup).position.distance_squared_to(snare_point)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = body
		if nearest != null:
			age_band = int(nearest.age_band)
			renderer.remove_individual(nearest.id)
	WildFaunaService.remove_one(game_data, species, age_band, trap.macro_coords)
	var area := passage_area(game_data, trap, rules)
	var rect: Rect2 = area["rect"]
	game_data.snare_disturbances[_key(String(area["key"]), species)] = {
		"until_day": game_data.get_absolute_day() + maxi(rules.trap_disturbance_days, 0), "species": species,
		"macro_x": trap.macro_coords.x, "macro_y": trap.macro_coords.y,
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
	}
	if live_cell != null:
		_apply_avoidance(game_data, {trap.macro_coords: live_cell})
	return age_band


# Fine giornata (dopo i tiri): i passaggi ricominciano da zero.
static func end_day(game_data: GameData) -> void:
	if game_data != null:
		if _MEASURE_LOGS:
			_log_day_measure(game_data)
		_measure.clear()
		game_data.snare_passages.clear()


# TEMPORANEO (2026-11-12, misura: lacci e cesti non prendono niente): a fine giornata, per ogni area di lacci/cesti e
# specie preda, i passaggi contati, se la mandria risulta presente nella macrocella e se l'area è disturbata. Da togliere
# appena trovata la causa.
static func _log_day_measure(game_data: GameData) -> void:
	var day := game_data.get_absolute_day()
	var seen := {}
	for trap in game_data.placed_traps:
		var rules := TrapService.get_rules(trap.trap_name)
		if rules == null or not TrapService.is_herd_quarry(rules):
			continue
		var area_key := String(passage_area(game_data, trap, rules)["key"])
		var herds := WildFaunaService.get_herds_in_cell(game_data, trap.macro_coords)
		for species in TrapService.prey_species(rules):
			var key := _key(area_key, species)
			if seen.has(key):
				continue
			seen[key] = true
			TrapService.log_line("MISURA %s %s (%s): passaggi %d, mandria presente %s, disturbata %s" % [area_key, species,
				trap.trap_name, int(game_data.snare_passages.get(key, 0)), herds.has(species), is_disturbed(game_data, area_key, species, day)])
			var entry: Dictionary = _measure.get(key, {})
			if entry.is_empty() or int(entry.get("n", 0)) == 0:
				TrapService.log_line("MISURA %s %s: nessun gruppetto misurato (cella spenta o mandria senza renderer)" % [area_key, species])
			else:
				TrapService.log_line("MISURA %s %s: gruppetto più vicino al rettangolo min %.1f media %.1f (%d ore); edificio più vicino %.1f, i centri ne stanno a %.1f" % [
					area_key, species, float(entry["min"]), float(entry["sum"]) / float(entry["n"]), int(entry["n"]),
					float(entry["building"]), float(entry["avoid"])])
				var at: Vector2 = entry.get("at", Vector2.ZERO)
				var r: Rect2 = entry.get("rect", Rect2())
				TrapService.log_line("MISURA %s %s: al minimo il centro era in (%.1f, %.1f), a %.1f dall'edificio più vicino; rettangolo (%.0f, %.0f)-(%.0f, %.0f)" % [
					area_key, species, at.x, at.y, float(entry.get("at_building", INF)), r.position.x, r.position.y, r.end.x, r.end.y])


# TEMPORANEO (misura): distanza oraria del centro più vicino dal rettangolo, ed edificio non stradale più vicino al rettangolo.
static func _measure_hour(key: String, rect: Rect2, renderer: AnimalGroupRenderer) -> void:
	var nearest := INF
	var nearest_center := Vector2.ZERO
	for center in renderer.get_cluster_positions():
		var d := _distance_to_rect(center, rect)
		if d < nearest:
			nearest = d
			nearest_center = center
	if nearest == INF:
		return
	# Il centro più vicino al rettangolo: quanto dista dall'edificio più vicino (ciò che lo spinge via).
	var center_to_building := INF
	for building_position: Vector2 in renderer._cluster_avoid_buildings:
		center_to_building = minf(center_to_building, nearest_center.distance_to(building_position))
	var building := INF
	for building_position: Vector2 in renderer._cluster_avoid_buildings:
		building = minf(building, _distance_to_rect(building_position, rect))
	var entry: Dictionary = _measure.get(key, {"min": INF, "sum": 0.0, "n": 0})
	if nearest < float(entry["min"]):
		entry["at"] = nearest_center
		entry["at_building"] = center_to_building
	entry["min"] = minf(float(entry["min"]), nearest)
	entry["rect"] = rect
	entry["sum"] = float(entry["sum"]) + nearest
	entry["n"] = int(entry["n"]) + 1
	entry["building"] = building
	entry["avoid"] = renderer._cluster_building_avoid_distance()
	_measure[key] = entry


static func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	return point.distance_to(Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y)))


static func _key(area_key: String, species: String) -> String:
	return "%s|%s" % [area_key, species]


static func _prune_disturbances(game_data: GameData, day: int) -> void:
	for key in game_data.snare_disturbances.keys():
		if int((game_data.snare_disturbances[key] as Dictionary).get("until_day", 0)) <= day:
			game_data.snare_disturbances.erase(key)


# Aree da evitare dei renderer delle celle accese, dai disturbi ancora attivi.
static func _apply_avoidance(game_data: GameData, live_cells: Dictionary) -> void:
	var rects_by_renderer := {}
	for entry in game_data.snare_disturbances.values():
		var coords := Vector2i(int(entry.get("macro_x", 0)), int(entry.get("macro_y", 0)))
		var cell: LiveMacroCell = live_cells.get(coords)
		var renderer: AnimalGroupRenderer = cell.animal_renderers.get(String(entry.get("species", ""))) if cell != null else null
		if renderer == null:
			continue
		var raw: Array = entry.get("rect", [0, 0, 0, 0])
		if not rects_by_renderer.has(renderer):
			rects_by_renderer[renderer] = []
		rects_by_renderer[renderer].append(Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3])))
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell == null:
			continue
		for renderer in cell.animal_renderers.values():
			var rects: Array[Rect2] = []
			rects.assign(rects_by_renderer.get(renderer, []))
			(renderer as AnimalGroupRenderer).avoid_rects = rects
