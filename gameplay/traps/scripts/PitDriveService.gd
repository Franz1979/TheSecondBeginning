class_name PitDriveService
extends RefCounted

# Spinta verso le fosse (2026-11-14, richiesta utente). Con la regola del WM accesa (GameData.pit_drive_enabled), una zona
# con almeno una fossa montata e vuota ha il lavoro "Spingi verso le fosse" (TrapJobProvider, lista Trappole, nessun
# attrezzo) quando una mandria grossa che la fossa può prendere ha un animale su terra CONOSCIUTA (già esplorata, non
# nera — 2026-11-14, prima era "visibile adesso", ma le fosse stanno dove di solito non c'è nessuno) a non più
# di VISIBLE_DISTANCE microcelle dalla zona, la specie non è stata spinta lì negli ultimi COOLDOWN_DAYS giorni e la zona
# non è disturbata per lei (SnareService). Il controllo gira una volta per ora di gioco (refresh, da SnareService.sample_hour);
# la lista dei lavori legge solo il risultato (GameData.pit_drive_candidates).
# Chi prende il lavoro va DIETRO il gruppetto più vicino, a STAND_BEHIND microcelle dal lato opposto alla fossa più vicina
# (stand_point), e all'arrivo (PitDriveAction) grida: gli animali entro DRIVE_RADIUS dal centro del gruppetto corrono verso
# la fossa (AnimalGroupRenderer.start_drive) e chi ci passa sopra può caderci (trap_flee_fall_chance, SnareService).
# Statico; lo stato sta in GameData.

const VISIBLE_DISTANCE := 25.0
const COOLDOWN_DAYS := 3
const STAND_BEHIND := 6.0
const DRIVE_RADIUS := 12.0
# true = mandria e gruppetto devono stare su terra conosciuta (_is_known). Provato false il 2026-11-14: la gente andava
# a spingere nel nero, lontanissimo (fino al bordo della macrocella), col rischio di morire. Lasciato true.
const DRIVE_NEEDS_KNOWN_LAND := true

# Callable(HumanIndividual): grido di chi spinge, alla sua posizione (GameScene.pit_drive_shouted, suono hunt_shout).
static var shout_sound_emitter: Callable = Callable()


# La regola del WM si vede solo dopo la prima fossa: una trappola che fa cadere chi fugge montata o a riposo.
static func has_any_pit(game_data: GameData) -> bool:
	if game_data == null:
		return false
	for trap in game_data.placed_traps:
		if _is_pit(TrapService.get_rules(trap.trap_name)):
			return true
	for entry in game_data.broken_traps:
		if _is_pit(TrapService.get_rules(String(entry.get("trap_name", "")))):
			return true
	return false


# Ogni ora di gioco: le zone che oggi hanno una mandria da spingere, e chi sta camminando per spingerne una si ri-mira.
static func refresh(game_data: GameData, live_cells: Dictionary, individuals: Array = []) -> void:
	_reaim_walkers(game_data, individuals)
	game_data.pit_drive_candidates.clear()
	if not game_data.pit_drive_enabled:
		_note("all", "regola del WM spenta")
		return
	_note("all", "regola del WM accesa")
	var day := game_data.get_absolute_day()
	var done := {}
	for trap in game_data.placed_traps:
		if trap.work_area_id <= 0 or done.has(trap.work_area_id) or not live_cells.has(trap.macro_coords):
			continue
		if not _is_vacant_pit(trap):
			var rules := TrapService.get_rules(trap.trap_name)
			if _is_pit(rules):
				_note("pit%d" % trap.id, "fossa #%d (zona #%d) in %s piena: %d/%d" % [trap.id, trap.work_area_id, trap.lot, trap.get_caught(), rules.trap_capacity])
			continue
		_note("pit%d" % trap.id, "fossa #%d (zona #%d) in %s vuota" % [trap.id, trap.work_area_id, trap.lot])
		done[trap.work_area_id] = true
		var area := WorkAreaService.find_by_id(game_data, trap.work_area_id)
		if area == null:
			continue
		var best := _best_herd(game_data, live_cells[trap.macro_coords], area, trap, day)
		if not best.is_empty():
			game_data.pit_drive_candidates[area.id] = best


# Punto dietro il gruppetto (microcelle locali della macrocella della zona), Vector2.INF se non c'è.
static func stand_point(game_data: GameData, area_id: int, species: String) -> Vector2:
	var points := _drive_points(game_data, area_id, species)
	if points.is_empty():
		return Vector2.INF
	var herd: Vector2 = points["herd"]
	var away: Vector2 = (herd - (points["pit"] as Vector2)).normalized()
	var point := herd + away * STAND_BEHIND
	point = Vector2(clampf(point.x, 0.5, World.WIDTH - 0.5), clampf(point.y, 0.5, World.HEIGHT - 0.5))
	# Terra conosciuta (2026-11-14, richiesta utente): nessuno va a spingere una mandria su terra mai esplorata (nera). Non
	# serve che si veda adesso: chi conosce il posto sa dove pascola, e le fosse stanno dove di solito non c'è nessuno. Il
	# punto dietro può essere anche nel nero (le mandrie arrivano dal bosco inesplorato): chi va a spingere lo scopre.
	if DRIVE_NEEDS_KNOWN_LAND and not _is_known(points["cell"], herd):
		return Vector2.INF
	return point


# All'arrivo: se la mandria è ancora entro VISIBLE_DISTANCE dalla zona, la spinge verso la fossa più vicina. Numero di
# animali partiti (0 = rinuncia).
static func drive(game_data: GameData, area_id: int, species: String, who: String) -> int:
	var day := game_data.get_absolute_day()
	game_data.pit_drive_last[_key(area_id, species)] = day
	game_data.pit_drive_candidates.erase(area_id)
	var area := WorkAreaService.find_by_id(game_data, area_id)
	var points := _drive_points(game_data, area_id, species)
	if area == null or points.is_empty() or _nearest_body_distance(points["renderer"], Rect2(area.rect)) > VISIBLE_DISTANCE:
		TrapService.log_line("%s: spinta di %s verso la zona #%d tolta, la mandria non è più vicina" % [who, species, area_id])
		return 0
	var renderer: AnimalGroupRenderer = points["renderer"]
	var started := renderer.start_drive(points["herd"], points["pit"], DRIVE_RADIUS)
	HuntTrapStatsService.add_drive(game_data, species, started)
	TrapService.log_line("%s spinge %d %s verso la fossa in %s (zona #%d)" % [who, started, species, Vector2i((points["pit"] as Vector2).floor()), area_id])
	return started


# Ricalcolo durante il cammino (2026-11-14, richiesta utente): una volta per ora, chi è ancora al passo di cammino della
# spinta va dietro la posizione NUOVA del gruppetto; se la mandria è sparita, su terra mai esplorata o oltre VISIBLE_DISTANCE dalla
# zona, si ferma dov'è e la Task si chiude (abbandono, come un bersaglio sparito) invece di camminare a vuoto.
static func _reaim_walkers(game_data: GameData, individuals: Array) -> void:
	for member in individuals:
		var human := member as HumanIndividual
		if human == null or human.current_task == null or not human.current_task.context.has(PitDriveAction.CONTEXT_AREA_ID):
			continue
		var task := human.current_task
		var walk := task.get_current_action() as WalkAction
		if walk == null:
			continue
		var area_id := int(task.context[PitDriveAction.CONTEXT_AREA_ID])
		var species := String(task.context.get(PitDriveAction.CONTEXT_SPECIES, ""))
		var area := WorkAreaService.find_by_id(game_data, area_id)
		var stand := stand_point(game_data, area_id, species) if area != null else Vector2.INF
		var points := _drive_points(game_data, area_id, species) if stand != Vector2.INF else {}
		var who := "#%d %s" % [human.id, human.name]
		# LOG TEMPORANEO (2026-11-14, richiesta utente): stato del cammino di chi va a spingere, una riga per ora.
		TrapService.log_line("%s, cammino della spinta: posizione %s (casa %s), meta %s a %.1f; percorso %d punti, in attesa %s, attivo %s, fallito %s, fermo a barriera %s; passo %s, vigore %.0f" % [
			who, Vector2i(human.position.floor()), human.home_macro_coords, Vector2i((walk.target as Vector2).floor()),
			human.position.distance_to(walk.target), human.path.size(), human.path_pending, human.path_active, human.path_failed,
			human.path_barrier_stop, task.get_current_action().get_script().get_global_name() if task.get_current_action() != null else "-",
			human.current_stamina])
		if stand == Vector2.INF or points.is_empty() or _nearest_body_distance(points["renderer"], Rect2(area.rect)) > VISIBLE_DISTANCE:
			TrapService.log_line("%s: spinta di %s verso la zona #%d tolta per strada, la mandria non si vede più o è lontana" % [who, species, area_id])
			task.context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "mandria da spingere sparita"
			# Arrivo immediato dove si trova: lo step si chiude al prossimo frame e la chiusura passa dall'abbandono.
			human.clear_path()
			walk.target = human.position
			human.target_position = human.position
			continue
		var target := stand + TaskBuilderService.macro_offset(human, area.macro_coords)
		if (walk.target as Vector2).distance_to(target) < 1.0:
			continue
		TrapService.log_line("%s: la mandria di %s si è spostata, nuovo punto %s (a %.1f)" % [
			who, species, Vector2i(stand.floor()), human.position.distance_to(target)])
		walk.target = target
		task.context[PitDriveAction.CONTEXT_POSITION] = target
		human.target_position = target
		walk.request_path(human, target)


static func _is_pit(rules: SecondaryResourceRules) -> bool:
	return rules != null and rules.trap_flee_fall_chance > 0.0


static func _is_vacant_pit(trap: PlacedTrap) -> bool:
	var rules := TrapService.get_rules(trap.trap_name)
	return _is_pit(rules) and trap.get_caught() < rules.trap_capacity


# Specie più vicina della zona tra quelle prendibili dalle sue fosse: {"species", "distance"} o {}.
static func _best_herd(game_data: GameData, cell: LiveMacroCell, area: WorkArea, pit: PlacedTrap, day: int) -> Dictionary:
	var rect := Rect2(area.rect)
	var herds := WildFaunaService.get_herds_in_cell(game_data, area.macro_coords)
	var best := {}
	for species in _pit_species(game_data, area.id):
		var key := _key(area.id, species)
		var renderer: AnimalGroupRenderer = cell.animal_renderers.get(species)
		if renderer == null or renderer.get_individual_count() <= 0:
			_note(key, "zona #%d, %s: nessun animale nella macrocella" % [area.id, species])
			continue
		var last := int(game_data.pit_drive_last.get(key, -COOLDOWN_DAYS))
		if day - last < COOLDOWN_DAYS:
			_note(key, "zona #%d, %s: già spinta il giorno %d, attesa fino al %d" % [area.id, species, last, last + COOLDOWN_DAYS])
			continue
		if SnareService.is_disturbed(game_data, "zone%d" % area.id, species, day):
			var entry: Dictionary = game_data.snare_disturbances.get(SnareService._key("zone%d" % area.id, species), {})
			_note(key, "zona #%d, %s: zona disturbata fino al giorno %d" % [area.id, species, int(entry.get("until_day", 0))])
			continue
		if not SnareService._can_take(game_data, pit, species, herds):
			_note(key, "zona #%d, %s: nessuna mandria nella cella né nella regione (%d figure)" % [area.id, species, renderer.get_individual_count()])
			continue
		var nearest := _nearest_body_distance(renderer, rect, cell if DRIVE_NEEDS_KNOWN_LAND else null)
		var nearest_any := _nearest_body_distance(renderer, rect)
		if nearest > VISIBLE_DISTANCE:
			_note(key, "zona #%d, %s (%d figure): animale su terra conosciuta più vicino a %s, contando il nero a %.0f (limite %d); rettangolo %s" % [
				area.id, species, renderer.get_individual_count(), "nessuno" if nearest == INF else "%.0f" % nearest, nearest_any, int(VISIBLE_DISTANCE), rect])
			continue
		# Il limite vale anche per il centro del gruppetto (2026-11-14, richiesta utente): è lì dietro che va chi spinge,
		# non dall'animale più vicino — un singolo entro 25 mandava Ghor a 40 microcelle nel bosco.
		var center := renderer.nearest_cluster_center(rect.get_center())
		if center == Vector2.INF:
			_note(key, "zona #%d, %s: nessun gruppetto trovato" % [area.id, species])
			continue
		if stand_point(game_data, area.id, species) == Vector2.INF:
			_note(key, "zona #%d, %s: gruppetto in %s su terra mai esplorata" % [area.id, species, Vector2i(center.floor())])
			continue
		var distance := SnareService._distance_to_rect(center, rect)
		if distance > VISIBLE_DISTANCE:
			_note(key, "zona #%d, %s: centro del gruppetto in %s a %.0f (limite %d, animale più vicino a %.0f)" % [
				area.id, species, Vector2i(center.floor()), distance, int(VISIBLE_DISTANCE), nearest])
			continue
		_note(key, "zona #%d, %s: candidata, gruppetto a %.0f" % [area.id, species, distance])
		if best.is_empty() or distance < float(best["distance"]):
			best = {"species": species, "distance": distance}
	return best


# LOG TEMPORANEO (2026-11-14, richiesta utente): motivo per cui una zona/specie non ha il lavoro di spinta, stampato solo
# quando cambia. Da togliere dopo le prove.
static var _last_reason := {}


static func _note(key: String, text: String) -> void:
	if String(_last_reason.get(key, "")) == text:
		return
	_last_reason[key] = text
	TrapService.log_line("spinta, " + text)


# Specie prendibili dalle fosse vuote della zona.
static func _pit_species(game_data: GameData, area_id: int) -> Array[String]:
	var result: Array[String] = []
	for trap in game_data.placed_traps:
		if trap.work_area_id != area_id or not _is_vacant_pit(trap):
			continue
		for species in TrapService.prey_species(TrapService.get_rules(trap.trap_name)):
			if not result.has(species):
				result.append(species)
	return result


# Distanza dal rettangolo dell'animale più vicino della mandria (con `known_in`, solo quelli su terra conosciuta di quella
# macrocella), INF se nessuno.
static func _nearest_body_distance(renderer: AnimalGroupRenderer, rect: Rect2, known_in: LiveMacroCell = null) -> float:
	var best := INF
	for body in renderer.get_individuals():
		var position: Vector2 = (body as AnimalVisualGroup).position
		var distance := SnareService._distance_to_rect(position, rect)
		if distance < best and (known_in == null or _is_known(known_in, position)):
			best = distance
	return best


# Terra conosciuta (usata solo con DRIVE_NEEDS_KNOWN_LAND): microcella già esplorata (FogOfWarMemory, non nera). Senza memoria della nebbia, tutto conosciuto.
static func _is_known(cell: LiveMacroCell, position: Vector2) -> bool:
	if cell == null or cell.fog_of_war_memory == null:
		return true
	var microcell := Vector2i(clampi(int(floor(position.x)), 0, World.WIDTH - 1), clampi(int(floor(position.y)), 0, World.HEIGHT - 1))
	return cell.fog_of_war_memory.has_ever_been_seen(microcell)


# Centro del gruppetto più vicino alle fosse vuote della zona e la fossa più vicina a lui:
# {"renderer", "herd", "pit"} in microcelle locali, o {} se manca qualcosa.
static func _drive_points(game_data: GameData, area_id: int, species: String) -> Dictionary:
	var area := WorkAreaService.find_by_id(game_data, area_id)
	if area == null:
		return {}
	var live_cell := PathfindingService.get_live_cell(area.macro_coords)
	var renderer: AnimalGroupRenderer = live_cell.animal_renderers.get(species) if live_cell != null else null
	if renderer == null or renderer.get_individual_count() <= 0:
		return {}
	var herd := renderer.nearest_cluster_center(Rect2(area.rect).get_center())
	if herd == Vector2.INF:
		return {}
	var pit := Vector2.INF
	for trap in game_data.placed_traps:
		if trap.work_area_id != area_id or not _is_vacant_pit(trap) or not TrapService.prey_species(TrapService.get_rules(trap.trap_name)).has(species):
			continue
		var point := Vector2(trap.lot) + Vector2(0.5, 0.5)
		if pit == Vector2.INF or point.distance_squared_to(herd) < pit.distance_squared_to(herd):
			pit = point
	if pit == Vector2.INF or pit.distance_squared_to(herd) < 0.01:
		return {}
	return {"renderer": renderer, "herd": herd, "pit": pit, "cell": live_cell}


static func _key(area_id: int, species: String) -> String:
	return "%d|%s" % [area_id, species]
