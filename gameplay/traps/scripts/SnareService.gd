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


# Ora di gioco nuova: conta i passaggi nelle celle accese con lacci e aggiorna le aree da evitare dei gruppetti.
static func sample_hour(game_data: GameData, live_cells: Dictionary, day_progress: float, individuals: Array = []) -> void:
	if game_data == null:
		return
	var day := game_data.get_absolute_day()
	var slot := day * HOURS_PER_DAY + clampi(int(day_progress * HOURS_PER_DAY), 0, HOURS_PER_DAY - 1)
	if slot == game_data.snare_sample_slot:
		return
	game_data.snare_sample_slot = slot
	_prune_disturbances(game_data, day)
	_apply_avoidance(game_data, live_cells)
	_update_pit_lots(game_data, live_cells)
	PitDriveService.refresh(game_data, live_cells, individuals)
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
		if passages <= 0 or not _can_take(game_data, trap, species, herds) or is_disturbed(game_data, area_key, species, day):
			continue
		var weight := float(rules.trap_prey_weights.get(species, 1.0))
		threshold += rules.trap_daily_catch_chance * weight * minf(float(passages) / full_hours, 1.0)
		if roll < threshold:
			return species
	return ""


# Specie prendibile dalla trappola: la mandria sta nella cella, oppure (2026-11-14, richiesta utente) sta uscendo a piedi
# e i suoi animali sono ancora qui — finché il riquadro ha la mandria, così take_prey toglie davvero un capo.
static func _can_take(game_data: GameData, trap: PlacedTrap, species: String, herds: Dictionary) -> bool:
	if herds.has(species):
		return true
	var live_cell := PathfindingService.get_live_cell(trap.macro_coords)
	var renderer: AnimalGroupRenderer = live_cell.animal_renderers.get(species) if live_cell != null else null
	return renderer != null and renderer.get_individual_count() > 0 \
		and WildFaunaService.has_herd_in_region(game_data, species, trap.macro_coords)


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
	_disturb_after_catch(game_data, trap, rules, species, live_cell)
	return age_band


# Dopo una cattura l'area resta evitata da quella specie per trap_disturbance_days giorni.
static func _disturb_after_catch(game_data: GameData, trap: PlacedTrap, rules: SecondaryResourceRules, species: String,
		live_cell: LiveMacroCell) -> void:
	var area := passage_area(game_data, trap, rules)
	var rect: Rect2 = area["rect"]
	game_data.snare_disturbances[_key(String(area["key"]), species)] = {
		"until_day": game_data.get_absolute_day() + maxi(rules.trap_disturbance_days, 0), "species": species,
		"macro_x": trap.macro_coords.x, "macro_y": trap.macro_coords.y,
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
	}
	if live_cell != null:
		_apply_avoidance(game_data, {trap.macro_coords: live_cell})


# Caduta in fuga (2026-11-14, richiesta utente — "spingere verso le fosse", passo 1). Ogni ora ogni renderer delle celle
# accese riceve le microcelle delle trappole ancora vuote che fanno cadere chi fugge (trap_flee_fall_chance > 0) e che
# hanno la sua specie tra le prede; il renderer chiama _on_pit_fall quando un suo animale in fuga entra in una di quelle.
static func _update_pit_lots(game_data: GameData, live_cells: Dictionary) -> void:
	var lots_by_renderer := {}
	for trap in game_data.placed_traps:
		var rules := TrapService.get_rules(trap.trap_name)
		if rules == null or rules.trap_flee_fall_chance <= 0.0 or trap.get_caught() >= rules.trap_capacity:
			continue
		var cell: LiveMacroCell = live_cells.get(trap.macro_coords)
		if cell == null:
			continue
		for species in TrapService.prey_species(rules):
			var renderer: AnimalGroupRenderer = cell.animal_renderers.get(species)
			if renderer == null:
				continue
			if not lots_by_renderer.has(renderer):
				lots_by_renderer[renderer] = {}
			# Bordo della fossa (2026-11-14, richiesta utente): cade anche chi in corsa passa su una delle 8 microcelle attorno,
			# non solo su quella della fossa. Le fosse distano almeno trap_min_spacing, quindi i bordi non si toccano.
			for dy in range(-PIT_EDGE_CELLS, PIT_EDGE_CELLS + 1):
				for dx in range(-PIT_EDGE_CELLS, PIT_EDGE_CELLS + 1):
					var edge := trap.lot + Vector2i(dx, dy)
					if edge.x >= 0 and edge.y >= 0 and edge.x < World.WIDTH and edge.y < World.HEIGHT \
							and not lots_by_renderer[renderer].has(edge):
						lots_by_renderer[renderer][edge] = trap.lot
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell == null:
			continue
		for renderer in cell.animal_renderers.values():
			var herd_renderer := renderer as AnimalGroupRenderer
			herd_renderer.pit_lots = lots_by_renderer.get(herd_renderer, {})
			herd_renderer.pit_fall_test = SnareService._on_pit_fall.bind(game_data) if not herd_renderer.pit_lots.is_empty() else Callable()


# Microcelle attorno alla fossa da cui si cade (1 = quadrato 3×3).
const PIT_EDGE_CELLS := 1


# Toglie dal renderer tutte le microcelle che portano alla fossa in `lot`.
static func _forget_pit(renderer: AnimalGroupRenderer, lot: Vector2i) -> void:
	for cell in renderer.pit_lots.keys():
		if renderer.pit_lots[cell] == lot:
			renderer.pit_lots.erase(cell)


# Un animale in fuga è entrato in una microcella della trappola in `lot` (la sua o una attorno; un tiro per passaggio,
# AnimalGroupRenderer._check_pit_fall): tiro con trap_flee_fall_chance. Se cade, la preda
# è registrata come quelle del tiro di fine giornata (la mandria perde un capo, l'area resta evitata) e il renderer toglie
# l'animale. True se è caduto.
static func _on_pit_fall(renderer: AnimalGroupRenderer, body: AnimalVisualGroup, lot: Vector2i, game_data: GameData) -> bool:
	var species := renderer.species_name
	var trap: PlacedTrap = null
	var rules: SecondaryResourceRules = null
	for candidate in game_data.placed_traps:
		if candidate.macro_coords != renderer.macro_coords or candidate.lot != lot:
			continue
		var candidate_rules := TrapService.get_rules(candidate.trap_name)
		if candidate_rules != null and candidate_rules.trap_flee_fall_chance > 0.0 				and candidate.get_caught() < candidate_rules.trap_capacity and TrapService.prey_species(candidate_rules).has(species):
			trap = candidate
			rules = candidate_rules
			break
	if trap == null:
		_forget_pit(renderer, lot)
		return false
	if not _can_take(game_data, trap, species, WildFaunaService.get_herds_in_cell(game_data, trap.macro_coords)):
		return false
	if randf() >= rules.trap_flee_fall_chance:
		TrapService.log_line("%s #%d in %s %s: %s in fuga ci passa sopra e non cade" % [trap.trap_name, trap.id, trap.macro_coords, trap.lot, species])
		return false
	var day := game_data.get_absolute_day()
	var age_band := int(body.age_band)
	WildFaunaService.remove_one(game_data, species, age_band, trap.macro_coords)
	trap.catch_days.append(day)
	trap.catch_species.append(species)
	trap.catch_ages.append(age_band)
	var alive := TrapService.is_live_catch(rules)
	trap.catch_sexes.append((1 if randf() < 0.5 else 0) if alive else -1)
	trap.catch_death_days.append(-1 if alive else day)
	game_data.placed_traps_revision += 1
	TrapService.log_line("%s #%d in %s %s: %s in fuga ci cade dentro (ora %d/%d)" % [trap.trap_name, trap.id, trap.macro_coords, trap.lot,
		species, trap.get_caught(), rules.trap_capacity])
	if trap.get_caught() >= rules.trap_capacity:
		_forget_pit(renderer, lot)
	_disturb_after_catch(game_data, trap, rules, species, PathfindingService.get_live_cell(trap.macro_coords))
	return true


# Fine giornata (dopo i tiri): i passaggi ricominciano da zero.
static func end_day(game_data: GameData) -> void:
	if game_data != null:
		game_data.snare_passages.clear()


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
