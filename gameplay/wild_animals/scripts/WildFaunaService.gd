class_name WildFaunaService
extends RefCounted

# Fauna selvatica "ad hoc" (2026-10-31, richiesta utente — piano fauna, passo 1a; acceso da
# SimulationSettings.WILD_FAUNA_AD_HOC): niente popolazioni simulate in tutto il mondo. Ogni specie divide la mappa in
# riquadri fissi di lato AnimalRules.herd_region_side macrocelle (coniglio 1×1, cinghiale 2×2, uro 5×5); ogni riquadro
# ha al più una mandria, sempre tutta insieme in una sola macrocella. Un riquadro si crea la prima volta che una sua
# cella diventa viva (ensure_cell) e poi si riprende soltanto: habitat sbagliato -> "mai", altrimenti un tiro con la
# densità del menu (PRESENCE_CHANCE) -> mandria o "assente". Il lupo resta fuori: esiste solo come branco del villaggio
# (WildAnimalGroup). Spostamenti (1b, tick_day): la mandria resta in una cella per herd_stay_days_min..max giorni, poi
# passa a un'altra cella adatta del riquadro; con lato 1 non si sposta mai. Passo 2: la scena disegna le mandrie che
# stanno in una cella (get_herds_in_cell) e la caccia toglie un capo (remove_one). Conti col tempo e salvataggio
# arrivano nei passi dopo.

# Probabilità che un riquadro adatto abbia la mandria, per densità del menu (GameData.starting_animal_density).
const PRESENCE_CHANCE := {
	"FEW": 0.3,
	"MEDIUM": 0.5,
	"MANY": 0.7,
}
const DEFAULT_PRESENCE_CHANCE := 0.5
# Un riquadro senza mandria la perde "da un giorno nel passato" estratto fino a tanti anni fa: gli arrivi futuri
# (ritorno della specie, passi successivi) non scattano tutti insieme.
const ABSENT_SINCE_MAX_YEARS := 3

# Specie con mandria (tutte tranne i predatori), lette una volta: AnimalCalculator.list_species_names apre la cartella.
static var _herd_species: Array[String] = []


static func herd_species() -> Array[String]:
	if _herd_species.is_empty():
		for species in AnimalCalculator.list_species_names():
			var rules := AnimalCalculator.get_animal_rules(species)
			if rules != null and not rules is PredatorRules:
				_herd_species.append(species)
	return _herd_species


static func region_side(rules: AnimalRules) -> int:
	return maxi(1, rules.herd_region_side)


# Fattore della taglia del menu sulla mandria (min, max e tetto insieme): normale 1, rada ~0.67, densa ~1.8 — gli
# stessi rapporti dei divisori della semina vecchia (AnimalSeedingService.POPULATION_SIZE_DIVISOR).
static func herd_size_scale(game_data: GameData) -> float:
	var size := AnimalSeedingService.population_size_from_string(game_data.starting_population_size)
	return AnimalSeedingService.POPULATION_SIZE_DIVISOR[GameTypes.PopulationSize.NORMAL] \
		/ AnimalSeedingService.POPULATION_SIZE_DIVISOR[size]


static func region_key(species: String, region: Vector2i) -> String:
	return "%s|%d|%d" % [species, region.x, region.y]


# Riquadri di tutte le specie che contengono `coords`: presi se già noti, creati altrimenti. Una riga di log per ogni
# riquadro nuovo e una di riepilogo per la cella. `forced_species` (1c, "presenza animali" alla partenza): per quelle
# specie un riquadro nuovo ha la mandria senza tiro di densità, se l'habitat va bene.
static func ensure_cell(world: World, game_data: GameData, coords: Vector2i, forced_species: Array[String] = []) -> void:
	if world == null or game_data == null:
		return
	var today := game_data.get_absolute_day()
	var created := 0
	var known := 0
	for species in herd_species():
		var rules := AnimalCalculator.get_animal_rules(species)
		var side := region_side(rules)
		var region := Vector2i(coords.x / side, coords.y / side)
		var key := region_key(species, region)
		if game_data.wild_fauna.has(key):
			known += 1
			# Nessuno guardava il riquadro da più di un giorno: la mandria si rimette in una cella a caso.
			var known_entry: WildFaunaRegion = game_data.wild_fauna[key]
			if _moves(known_entry) and known_entry.last_move_day < today - 1:
				_place(world, rules, known_entry, today, "rientro: ")
			continue
		var entry := _create_region(world, game_data, rules, species, region, side, today, forced_species.has(species))
		game_data.wild_fauna[key] = entry
		created += 1
		_log_region(entry)
	if DebugLogging.ENABLED:
		print("[WILD FAUNA] cella (%d, %d): %d riquadri nuovi, %d già noti" % [coords.x, coords.y, created, known])


static func _create_region(world: World, game_data: GameData, rules: AnimalRules, species: String, region: Vector2i,
		side: int, today: int, forced: bool = false) -> WildFaunaRegion:
	var entry := WildFaunaRegion.new()
	entry.species = species
	entry.region = region
	entry.side = side
	entry.last_update_day = today
	var suitable := _suitable_cells(world, rules, region, side)
	if suitable.is_empty():
		entry.status = WildFaunaRegion.Status.NEVER
		if forced:
			push_warning("WildFaunaService: la cella di partenza non è adatta a '%s' (probabile cella di ripiego), nessuna mandria garantita." % species)
		return entry
	var chance: float = PRESENCE_CHANCE.get(game_data.starting_animal_density, DEFAULT_PRESENCE_CHANCE)
	if not forced and randf() >= chance:
		entry.status = WildFaunaRegion.Status.ABSENT
		entry.extinct_since_day = today - randi_range(0, ABSENT_SINCE_MAX_YEARS * GameData.DAYS_PER_YEAR)
		return entry
	entry.status = WildFaunaRegion.Status.PRESENT
	# Mandria tra herd_size_min e herd_size_max della specie, scalata dalla taglia del menu; età dalla specie.
	var scale := herd_size_scale(game_data)
	var total := maxi(1, roundi(randi_range(rules.herd_size_min, maxi(rules.herd_size_min, rules.herd_size_max)) * scale))
	var weights := rules.initial_age_ratio
	if weights.is_empty():
		weights = {GameTypes.AgeBand.YOUNG: 1.0, GameTypes.AgeBand.ADULT: 1.0, GameTypes.AgeBand.OLD: 1.0}
	var split := MacroCellState._split_by_weight(weights, total)
	for age_band in [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]:
		entry.age_counts[age_band] = int(split.get(age_band, 0))
	entry.current_cell = suitable.pick_random()
	entry.stay_remaining = randi_range(rules.herd_stay_days_min, maxi(rules.herd_stay_days_min, rules.herd_stay_days_max))
	entry.last_move_day = today
	return entry


# Mandrie che in questo momento stanno in `coords`: specie -> conteggi per fascia d'età (GameTypes.AgeBand -> int).
static func get_herds_in_cell(game_data: GameData, coords: Vector2i) -> Dictionary:
	var herds: Dictionary = {}
	if game_data == null:
		return herds
	for species in herd_species():
		var entry := _region_at(game_data, species, coords)
		if entry != null and entry.status == WildFaunaRegion.Status.PRESENT and entry.current_cell == coords \
				and entry.get_total() > 0:
			herds[species] = entry.age_counts
	return herds


# Preda uccisa (passo 2, HuntService.apply_prey_kill): un capo in meno nella mandria del riquadro, nella sua fascia
# d'età (o in un'altra se quella è già vuota). Mandria a zero -> riquadro "assente" da oggi.
static func remove_one(game_data: GameData, species: String, age_band: int, coords: Vector2i) -> void:
	if game_data == null:
		return
	var entry := _region_at(game_data, species, coords)
	if entry == null or entry.status != WildFaunaRegion.Status.PRESENT:
		return
	var band := age_band
	if int(entry.age_counts.get(band, 0)) <= 0:
		band = -1
		for other in entry.age_counts:
			if int(entry.age_counts[other]) > 0:
				band = other
				break
	if band == -1:
		return
	entry.age_counts[band] = int(entry.age_counts[band]) - 1
	var total := entry.get_total()
	if total <= 0:
		entry.status = WildFaunaRegion.Status.ABSENT
		entry.extinct_since_day = game_data.get_absolute_day()
		entry.current_cell = Vector2i(-1, -1)
	if DebugLogging.ENABLED:
		print("[WILD FAUNA] %s (%d,%d): preda uccisa in (%d, %d), restano %d%s" % [species, entry.region.x, entry.region.y,
			coords.x, coords.y, total, " — mandria sterminata" if total <= 0 else ""])


static func _region_at(game_data: GameData, species: String, coords: Vector2i) -> WildFaunaRegion:
	var rules := AnimalCalculator.get_animal_rules(species)
	if rules == null:
		return null
	var side := region_side(rules)
	return game_data.wild_fauna.get(region_key(species, Vector2i(coords.x / side, coords.y / side)))


# Giro giornaliero (1b, GameSimulation.tick_day): solo le mandrie dei riquadri che contengono una cella viva, una volta
# ciascuna. Finito il soggiorno, la mandria passa a un'altra cella adatta del riquadro.
static func tick_day(ctx: GameContext) -> void:
	if not SimulationSettings.WILD_FAUNA_AD_HOC or ctx.game_data == null or ctx.world == null:
		return
	var today := ctx.game_data.get_absolute_day()
	var done: Dictionary = {}
	for coords in ctx.live_cells.keys():
		for species in herd_species():
			var rules := AnimalCalculator.get_animal_rules(species)
			var side := region_side(rules)
			var key := region_key(species, Vector2i(coords.x / side, coords.y / side))
			if done.has(key):
				continue
			done[key] = true
			var entry: WildFaunaRegion = ctx.game_data.wild_fauna.get(key)
			if entry == null or not _moves(entry) or entry.last_move_day >= today:
				continue
			if entry.last_move_day < today - 1:
				_place(ctx.world, rules, entry, today, "rientro: ")
				ctx.game_data.wild_fauna_moved = true
				continue
			entry.last_move_day = today
			entry.stay_remaining -= 1
			if entry.stay_remaining <= 0:
				_place(ctx.world, rules, entry, today, "")
				ctx.game_data.wild_fauna_moved = true


# Mandria che si sposta: presente, in un riquadro più grande di una cella.
static func _moves(entry: WildFaunaRegion) -> bool:
	return entry.status == WildFaunaRegion.Status.PRESENT and entry.side > 1


# Mette la mandria in una cella adatta del riquadro diversa da quella di adesso (se ce n'è più di una) e tira un nuovo
# soggiorno.
static func _place(world: World, rules: AnimalRules, entry: WildFaunaRegion, today: int, log_prefix: String) -> void:
	var suitable := _suitable_cells(world, rules, entry.region, entry.side)
	if suitable.is_empty():
		return
	if suitable.size() > 1:
		suitable.erase(entry.current_cell)
	var from := entry.current_cell
	entry.current_cell = suitable.pick_random()
	entry.stay_remaining = randi_range(rules.herd_stay_days_min, maxi(rules.herd_stay_days_min, rules.herd_stay_days_max))
	entry.last_move_day = today
	if DebugLogging.ENABLED:
		print("[WILD FAUNA] giorno %d %s (%d,%d): %sda (%d, %d) a (%d, %d), resta %d giorni" % [today, entry.species,
			entry.region.x, entry.region.y, log_prefix, from.x, from.y, entry.current_cell.x, entry.current_cell.y, entry.stay_remaining])


# Macrocelle del riquadro (dentro la mappa) adatte alla specie: niente acqua, bioma e terreno ammessi.
static func _suitable_cells(world: World, rules: AnimalRules, region: Vector2i, side: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(side):
		for dx in range(side):
			var cell_coords := Vector2i(region.x * side + dx, region.y * side + dy)
			var cell := world.get_cell_at(cell_coords.x, cell_coords.y)
			if cell == null or cell.terrain_base == GameTypes.TerrainBase.WATER:
				continue
			if rules.is_suitable_for(cell.biome, cell.terrain_base):
				cells.append(cell_coords)
	return cells


static func _log_region(entry: WildFaunaRegion) -> void:
	if not DebugLogging.ENABLED:
		return
	var origin := entry.region * entry.side
	var head := "[WILD FAUNA]   riquadro %s (%d,%d) %dx%d [celle %d-%d, %d-%d]:" % [entry.species, entry.region.x,
		entry.region.y, entry.side, entry.side, origin.x, origin.x + entry.side - 1, origin.y, origin.y + entry.side - 1]
	match entry.status:
		WildFaunaRegion.Status.NEVER:
			print("%s mai (habitat non adatto)" % head)
		WildFaunaRegion.Status.ABSENT:
			print("%s assente dal giorno %d" % [head, entry.extinct_since_day])
		WildFaunaRegion.Status.PRESENT:
			print("%s mandria %d/%d/%d (giovani/adulti/vecchi) in (%d, %d)" % [head,
				int(entry.age_counts.get(GameTypes.AgeBand.YOUNG, 0)), int(entry.age_counts.get(GameTypes.AgeBand.ADULT, 0)),
				int(entry.age_counts.get(GameTypes.AgeBand.OLD, 0)), entry.current_cell.x, entry.current_cell.y])
