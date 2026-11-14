class_name HerdHabitService
extends RefCounted

# Mete abituali delle mandrie (2026-11-14, richiesta utente — "le mandrie passano sempre negli stessi percorsi?", passo 1).
# Prima i centri dei gruppetti vagavano a caso per tutta la macrocella; ora una mandria di prede grosse si sceglie due
# pascoli fissi e il renderer (AnimalGroupRenderer, "Mete abituali") la fa camminare dall'uno all'altro con calma,
# fermandosi qualche giorno a ciascuno. Qui solo la SCELTA delle mete, una volta per cella e specie, mai a ogni frame.
# Registro (2026-11-15, richiesta utente): scelte una volta per cella e specie e salvate in GameData.herd_habit_goals,
# poi sempre quelle — ogni mandria di quella specie che passa dalla cella va negli stessi posti (base per i sentieri).
# Il seme fisso per cella e specie resta per le scelte non registrate (erba non ancora nota).
# Le mandrie di passaggio (quasi tutte) fanno un giro solo: vedi AnimalGroupRenderer, "Mete abituali".
# Anello attorno al villaggio (2026-11-15, richiesta utente — "il player non ha il log, come saprò dove trovarli?"):
# nella cella del centro villaggio i pascoli stanno tra VILLAGE_RING_MIN e VILLAGE_RING_MAX dal centro, così la gente
# le mandrie le vede. Niente più acqua tra le mete (tolta su richiesta: il bere vicino al villaggio sarà un passo a sé).

# Interruttore della prova: false = mandrie che vagano a caso come prima (anche per confrontare i tempi).
const ENABLED := true
# Versione della regola di scelta, nella chiave del registro: le mete registrate con una regola vecchia si ignorano e si
# rifanno (2 = anello attorno al villaggio, senza acqua; 3 = anello stretto a 35; 4 = solo blocchi con erba).
const RULE_VERSION := 4
# Blocchi in cui si conta l'erba per cercare i pascoli (microcelle per lato) e quanti pascoli al massimo.
const PASTURE_BLOCK := 10
const PASTURE_COUNT := 2
# Erba minima di un blocco per essere pascolo (con l'erba nota): sotto, niente pascolo lì. Se ne resta uno solo, la
# mandria ha un pascolo solo e torna sempre lì.
const PASTURE_MIN_GRASS := 10
# Distanza minima tra i due pascoli (microcelle).
const PASTURE_MIN_SEPARATION := 25.0
# Margine oltre la distanza che i centri dei gruppetti tengono dagli edifici.
const BUILDING_MARGIN := 5.0
# Anello dei pascoli attorno al centro villaggio (microcelle dal centro), solo nella sua cella.
const VILLAGE_RING_MIN := 20.0
const VILLAGE_RING_MAX := 35.0
# Quanto ci si ferma a ogni pascolo, in giorni di gioco (min, max).
const PASTURE_DWELL_DAYS := Vector2(3.0, 6.0)


# Mete per la mandria di `renderer` nella cella `cell`, se non le ha già e se è una mandria di prede grosse. Dal registro
# (GameData.herd_habit_goals) se la cella le ha già per questa specie; sennò scelte ora e registrate, ma solo con l'erba
# della cella già disposta (senza, la scelta sarebbe a caso: vale per questa volta e si ripete la prossima).
static func ensure_goals(world: World, game_data: GameData, cell: LiveMacroCell, renderer: AnimalGroupRenderer) -> void:
	if not ENABLED or game_data == null or cell == null or renderer == null or renderer.has_habit_goals() \
			or not renderer.is_big_prey():
		return
	var key := registry_key(cell.coords(), renderer.species_name)
	if game_data.herd_habit_goals.has(key):
		var saved: Array = []
		for entry in game_data.herd_habit_goals[key]:
			saved.append({"kind": "pascolo", "point": Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
				"dwell": PASTURE_DWELL_DAYS})
		if not saved.is_empty():
			renderer.set_habit_goals(saved)
			_log(renderer, "mete dal registro (%d)" % saved.size())
		return
	# Mete di una regola vecchia (prima della versione nella chiave): via, si rifanno con questa.
	game_data.herd_habit_goals.erase("%d,%d:%s" % [cell.coords().x, cell.coords().y, renderer.species_name])
	var buildings: Array = renderer.get_cluster_avoid_buildings_now()
	var keep_away := renderer.cluster_building_avoid_distance() + BUILDING_MARGIN
	var village: Variant = _village_point_in(world, cell.coords())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell.coords(), renderer.species_name])
	var grass_known := not (cell.cached_vegetation_positions.get(GameTypes.WorldObjectType.GRASS, []) as Array).is_empty()
	var pastures := _pick_pastures(cell, renderer, buildings, keep_away, village, rng)
	if pastures.is_empty():
		_log(renderer, "nessun pascolo adatto, vaga a caso come prima")
		return
	var goals: Array = []
	for pasture in pastures:
		goals.append({"kind": "pascolo", "point": pasture, "dwell": PASTURE_DWELL_DAYS})
	renderer.set_habit_goals(goals)
	if grass_known:
		var record: Array = []
		for pasture in pastures:
			record.append({"kind": "pascolo", "x": pasture.x, "y": pasture.y})
		game_data.herd_habit_goals[key] = record
	var text := "mete scelte%s —" % ("" if grass_known else " (non registrate, erba non ancora nota)")
	for i in range(pastures.size()):
		text += "%s pascolo %s (erba %d%s)" % ["" if i == 0 else ",", Vector2i(pastures[i]), _grass_near(cell, pastures[i]),
			"" if village == null else ", a %.0f dal centro villaggio" % pastures[i].distance_to(village)]
	_log(renderer, text)


# Punto del centro villaggio se sta nella cella `coords`; null sennò.
static func _village_point_in(world: World, coords: Vector2i) -> Variant:
	if world == null:
		return null
	var center := VisitorService.find_village_center(world)
	if center == null or Vector2i(center.macro_x, center.macro_y) != coords:
		return null
	return VisitorService.get_building_point(center)


# I pascoli: centri dei blocchi PASTURE_BLOCK×PASTURE_BLOCK con più erba, lontani dagli edifici, nell'anello attorno al
# villaggio (se è in questa cella), distanti tra loro. Senza erba nota (vegetazione non ancora disposta) conta il caso.
static func _pick_pastures(cell: LiveMacroCell, renderer: AnimalGroupRenderer, buildings: Array, keep_away: float,
		village: Variant, rng: RandomNumberGenerator) -> Array[Vector2]:
	var counts := _grass_by_block(cell)
	var grass_known := not counts.is_empty()
	var scored: Array = []
	var blocks_per_side := World.WIDTH / PASTURE_BLOCK
	for by in range(blocks_per_side):
		for bx in range(blocks_per_side):
			var center := Vector2((bx + 0.5) * PASTURE_BLOCK, (by + 0.5) * PASTURE_BLOCK)
			if renderer.is_wander_blocked_at(Vector2i(center.floor())):
				continue
			if grass_known and int(counts.get(Vector2i(bx, by), 0)) < PASTURE_MIN_GRASS:
				continue
			if _nearest_distance(center, buildings) <= keep_away:
				continue
			if village != null:
				var from_village := center.distance_to(village)
				if from_village < VILLAGE_RING_MIN or from_village > VILLAGE_RING_MAX:
					continue
			# Un po' di caso (±20%) così a parità d'erba non vince sempre lo stesso angolo.
			var score := float(counts.get(Vector2i(bx, by), 0)) * rng.randf_range(0.8, 1.2) + rng.randf() * 0.5
			scored.append({"point": center, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var chosen: Array[Vector2] = []
	for entry in scored:
		var point: Vector2 = entry["point"]
		var far_enough := true
		for other in chosen:
			if point.distance_to(other) < PASTURE_MIN_SEPARATION:
				far_enough = false
				break
		if far_enough:
			chosen.append(point)
			if chosen.size() >= PASTURE_COUNT:
				break
	return chosen


static func registry_key(coords: Vector2i, species: String) -> String:
	return "%d,%d:%s#%d" % [coords.x, coords.y, species, RULE_VERSION]


static func _grass_by_block(cell: LiveMacroCell) -> Dictionary:
	var counts: Dictionary = {}
	# L'erba è un elenco di Vector2i (microcella), alberi e arbusti di Vector3i: si leggono solo x e y, vanno bene entrambi.
	for key in cell.cached_vegetation_positions.get(GameTypes.WorldObjectType.GRASS, []):
		var block := Vector2i(int(key.x) / PASTURE_BLOCK, int(key.y) / PASTURE_BLOCK)
		counts[block] = int(counts.get(block, 0)) + 1
	return counts


static func _grass_near(cell: LiveMacroCell, point: Vector2) -> int:
	var block := Vector2i(int(point.x) / PASTURE_BLOCK, int(point.y) / PASTURE_BLOCK)
	return int(_grass_by_block(cell).get(block, 0))


static func _nearest_distance(point: Vector2, others: Array) -> float:
	var best := INF
	for other in others:
		best = minf(best, point.distance_to(other))
	return best


static func _log(renderer: AnimalGroupRenderer, text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_HERD_HABIT_LOGS:
		print("[HERD] %s in %s: %s" % [renderer.species_name, str(renderer.macro_coords), text])
