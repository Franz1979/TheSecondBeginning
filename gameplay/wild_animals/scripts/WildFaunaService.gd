class_name WildFaunaService
extends RefCounted

# Fauna selvatica "ad hoc" (2026-10-31, richiesta utente — piano fauna, passo 1a): niente popolazioni simulate in tutto il mondo. Ogni specie divide la mappa in
# riquadri fissi di lato AnimalRules.herd_region_side macrocelle (coniglio 1×1, cinghiale 2×2, uro 5×5); ogni riquadro
# ha al più una mandria, sempre tutta insieme in una sola macrocella. Un riquadro si crea la prima volta che una sua
# cella diventa viva (ensure_cell) e poi si riprende soltanto: habitat sbagliato -> "mai", altrimenti un tiro con la
# densità del menu (PRESENCE_CHANCE) -> mandria o "assente". Il lupo resta fuori: esiste solo come branco del villaggio
# (WildAnimalGroup). Spostamenti (1b, tick_day): la mandria resta in una cella per herd_stay_days_min..max giorni, poi
# passa a un'altra cella adatta del riquadro; con lato 1 non si sposta mai. Passo 2: la scena disegna le mandrie che
# stanno in una cella (get_herds_in_cell) e la caccia toglie un capo (remove_one). Passo 3a: tre momenti dell'anno
# uguali per tutte le specie (BIRTH_DAY, SPLIT_DAY, OLD_AGE_DEATH_DAY), applicati a ogni mandria quando la si guarda
# (tick_day) o quando ci si torna (ensure_cell), recuperando in ordine quelli passati (_catch_up). Passo 3b: una mandria
# sparita (caccia, vecchiaia) torna dopo AnimalRules.recolonization_years con un gruppetto (RECOLONIZE_START_RATIO);
# i riquadri vuoti fin dall'inizio restano vuoti. Salvataggio al passo 4.

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

# Momenti dell'anno delle mandrie (giorno 0..DAYS_PER_YEAR-1, lontani dai cambi di stagione e dal giorno 10):
# inizio primavera invecchiamento poi nascite, fine estate split, fine autunno morti per vecchiaia.
const SPLIT_DAY := 265
const BIRTH_DAY := 96
const OLD_AGE_DEATH_DAY := 359
# Dopo lo split la mandria torna tra queste quote del suo massimo (herd_size_max).
const SPLIT_TARGET_MIN_RATIO := 0.75
const SPLIT_TARGET_MAX_RATIO := 0.9
# Oltre tanti anni senza nessuno a guardarla la mandria non recupera i momenti persi: si rifà nuova (_catch_up).
const RECREATE_AFTER_YEARS := 5
# Partenza di una mandria per taglia del menu, come quota di herd_size_max (coniglio max 100 -> 50/70/90).
const START_RATIO_BY_SIZE := {
	GameTypes.PopulationSize.SPARSE: 0.5,
	GameTypes.PopulationSize.NORMAL: 0.7,
	GameTypes.PopulationSize.DENSE: 0.9,
}
# Gruppetto che ricolonizza un riquadro, come quota di herd_size_max (coniglio 30, uro 8).
const RECOLONIZE_START_RATIO := 0.3
# Passo 7c: quanto lontano dal centro del lato può cadere il punto di entrata o uscita (microcelle), e tentativi per
# trovare una microcella libera da cui misurare se il bordo è raggiungibile.
const BORDER_AIM_SPREAD := 35.0
const FREE_MICROCELL_ATTEMPTS := 20

# Prede piccole garantite sulla cella di partenza con "presenza sicura animali". SMALL_PREY_HABITAT_SPECIES è la specie il
# cui habitat fa da criterio di scelta della cella (FirstStartMacroCellSelectionService): coniglio e pernice hanno lo stesso.
const SMALL_PREY_SPECIES: Array[String] = ["rabbit", "partridge"]
const SMALL_PREY_HABITAT_SPECIES := "rabbit"

# Specie con mandria (AnimalRules.has_wild_herds), lette una volta: AnimalCalculator.list_species_names apre la cartella.
static var _herd_species: Array[String] = []


static func herd_species() -> Array[String]:
	if _herd_species.is_empty():
		for species in AnimalCalculator.list_species_names():
			var rules := AnimalCalculator.get_animal_rules(species)
			if rules != null and rules.has_wild_herds:
				_herd_species.append(species)
	return _herd_species


static func region_side(rules: AnimalRules) -> int:
	return maxi(1, rules.herd_region_side)


# Taglia del menu: solo con quanti animali parte una mandria, come quota del suo massimo fisso (herd_size_max). Il
# massimo non cambia mai: lo split lo fa sempre rispettare.
static func herd_start_ratio(game_data: GameData) -> float:
	var size := population_size_from_string(game_data.starting_population_size)
	return START_RATIO_BY_SIZE.get(size, START_RATIO_BY_SIZE[GameTypes.PopulationSize.NORMAL])


# Taglia scelta nel menu (stringa di GameData.starting_population_size) -> enum. Valore sconosciuto -> NORMAL.
static func population_size_from_string(value: String) -> GameTypes.PopulationSize:
	match value:
		"SPARSE":
			return GameTypes.PopulationSize.SPARSE
		"DENSE":
			return GameTypes.PopulationSize.DENSE
		_:
			return GameTypes.PopulationSize.NORMAL


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
			_catch_up(world, game_data, rules, known_entry, today)
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
	_roll_herd(game_data, rules, entry)
	entry.current_cell = suitable.pick_random()
	entry.stay_remaining = randi_range(rules.herd_stay_days_min, maxi(rules.herd_stay_days_min, rules.herd_stay_days_max))
	entry.last_move_day = today
	return entry


# Mandria a herd_start_ratio del massimo della specie (taglia del menu); età dalla specie. Usata alla creazione e quando
# la mandria si rifà dopo RECREATE_AFTER_YEARS senza nessuno a guardarla; `ratio` diverso per la ricolonizzazione.
static func _roll_herd(game_data: GameData, rules: AnimalRules, entry: WildFaunaRegion, ratio: float = -1.0) -> void:
	if ratio < 0.0:
		ratio = herd_start_ratio(game_data)
	var total := maxi(1, roundi(rules.herd_size_max * ratio))
	var weights := rules.initial_age_ratio
	if weights.is_empty():
		weights = {GameTypes.AgeBand.YOUNG: 1.0, GameTypes.AgeBand.ADULT: 1.0, GameTypes.AgeBand.OLD: 1.0}
	var split := MacroCellState._split_by_weight(weights, total)
	for age_band in [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]:
		entry.age_counts[age_band] = int(split.get(age_band, 0))


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


# Punto del bordo da cui la mandria entra in `coords`, dal lato della cella da cui viene (passo 7c). Null se non c'è.
static func herd_entry_point(world: World, game_data: GameData, species: String, coords: Vector2i) -> Variant:
	var entry := _region_at(game_data, species, coords)
	return _border_point_toward(world, coords, entry.previous_cell if entry != null else Vector2i(-1, -1))


# Punto del bordo da cui la mandria esce da `coords`, dal lato della cella in cui va (passo 7c). Null se non c'è.
static func herd_exit_point(world: World, game_data: GameData, species: String, coords: Vector2i) -> Variant:
	var entry := _region_at(game_data, species, coords)
	return _border_point_toward(world, coords, entry.current_cell if entry != null else Vector2i(-1, -1))


# Punto del bordo sul lato rivolto a `other` (il lato dell'asse più distante, a caso se pari), in un punto a caso del lato;
# un bordo qualunque se `other` non è una cella diversa. Libero e raggiungibile, se la cella ha la griglia.
static func _border_point_toward(world: World, coords: Vector2i, other: Vector2i) -> Variant:
	var center := Vector2(World.WIDTH, World.HEIGHT) * 0.5
	var reach_from: Variant = _random_free_microcell(coords)
	if other.x < 0 or other == coords:
		return VisitorService.find_border_point(world, coords, center, reach_from, true)
	var offset := other - coords
	var along_x := absi(offset.x) > absi(offset.y) or (absi(offset.x) == absi(offset.y) and randf() < 0.5)
	var side := Vector2(signi(offset.x), 0.0) if along_x else Vector2(0.0, signi(offset.y))
	var aim := center + side * (center.x - 1.0) + side.orthogonal() * randf_range(-BORDER_AIM_SPREAD, BORDER_AIM_SPREAD)
	return VisitorService.find_border_point(world, coords, aim, reach_from)


# Una microcella libera a caso da cui misurare la raggiungibilità del bordo; null senza griglia o se non ne trova.
static func _random_free_microcell(coords: Vector2i) -> Variant:
	var live_cell := PathfindingService.get_live_cell(coords)
	if live_cell == null or live_cell.path_grid == null:
		return null
	for attempt in range(FREE_MICROCELL_ATTEMPTS):
		var microcell := Vector2i(randi_range(0, World.WIDTH - 1), randi_range(0, World.HEIGHT - 1))
		if not PathfindingService.is_blocked(live_cell, microcell):
			return microcell
	return null


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
		_empty_region(entry, game_data.get_absolute_day())
	if DebugLogging.ENABLED:
		print("[WILD FAUNA] %s (%d,%d): preda uccisa in (%d, %d), restano %d%s" % [species, entry.region.x, entry.region.y,
			coords.x, coords.y, total, " — mandria sterminata" if total <= 0 else ""])


# Debug (pulsante ☠ della DebugBar): toglie tutte le mandrie che ora stanno in `coords`, come se fossero state cacciate
# fino all'ultimo capo (torneranno dopo recolonization_years).
static func exterminate_in_cell(game_data: GameData, coords: Vector2i) -> void:
	for species in get_herds_in_cell(game_data, coords):
		var entry := _region_at(game_data, species, coords)
		var total := entry.get_total()
		for age_band in entry.age_counts:
			entry.age_counts[age_band] = 0
		_empty_region(entry, game_data.get_absolute_day())
		game_data.wild_fauna_moved = true
		if DebugLogging.ENABLED:
			print("[WILD FAUNA] %s (%d,%d): sterminata in (%d, %d) dal debug, %d capi" % [species, entry.region.x,
				entry.region.y, coords.x, coords.y, total])


static func _region_at(game_data: GameData, species: String, coords: Vector2i) -> WildFaunaRegion:
	var rules := AnimalCalculator.get_animal_rules(species)
	if rules == null:
		return null
	var side := region_side(rules)
	return game_data.wild_fauna.get(region_key(species, Vector2i(coords.x / side, coords.y / side)))


# Giro giornaliero (1b, GameSimulation.tick_day): solo le mandrie dei riquadri che contengono una cella viva, una volta
# ciascuna. Finito il soggiorno, la mandria passa a un'altra cella adatta del riquadro.
static func tick_day(ctx: GameContext) -> void:
	if ctx.game_data == null or ctx.world == null:
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
			if entry == null:
				continue
			if _catch_up(ctx.world, ctx.game_data, rules, entry, today):
				ctx.game_data.wild_fauna_moved = true
			if not _moves(entry) or entry.last_move_day >= today:
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


# Applica in ordine i momenti dell'anno caduti tra l'ultimo aggiornamento (escluso) e oggi (incluso): uno solo se la
# mandria era guardata ieri, tutti quelli persi se ci si torna dopo tempo. True se la mandria è cambiata.
static func _catch_up(world: World, game_data: GameData, rules: AnimalRules, entry: WildFaunaRegion, today: int) -> bool:
	var from_day := entry.last_update_day
	entry.last_update_day = today
	if today <= from_day:
		return false
	var recolonized := false
	if entry.status == WildFaunaRegion.Status.ABSENT and entry.returns:
		var arrival_day := entry.extinct_since_day + maxi(0, rules.recolonization_years) * GameData.DAYS_PER_YEAR
		if arrival_day > today or not _recolonize(world, game_data, rules, entry, arrival_day, today):
			return false
		recolonized = true
		from_day = maxi(from_day, arrival_day)
	if entry.status != WildFaunaRegion.Status.PRESENT or today <= from_day:
		return recolonized
	# Assente da troppo tempo: niente recupero anno per anno, la mandria si rifà nuova (resta "presente": l'esito del
	# riquadro non si ritira).
	if today - from_day > RECREATE_AFTER_YEARS * GameData.DAYS_PER_YEAR:
		_roll_herd(game_data, rules, entry)
		if DebugLogging.ENABLED:
			print("[WILD FAUNA] giorno %d %s (%d,%d): nessuno la guardava da %d anni, mandria rifatta %d/%d/%d (giovani/adulti/vecchi)" % [
				today, entry.species, entry.region.x, entry.region.y, (today - from_day) / GameData.DAYS_PER_YEAR,
				_count(entry, GameTypes.AgeBand.YOUNG), _count(entry, GameTypes.AgeBand.ADULT), _count(entry, GameTypes.AgeBand.OLD)])
		return true
	var recovering := today - from_day > 1
	var changed := recolonized
	for year in range(from_day / GameData.DAYS_PER_YEAR, today / GameData.DAYS_PER_YEAR + 1):
		for moment in [BIRTH_DAY, SPLIT_DAY, OLD_AGE_DEATH_DAY]:
			var day: int = year * GameData.DAYS_PER_YEAR + moment
			if day <= from_day or day > today:
				continue
			if entry.status != WildFaunaRegion.Status.PRESENT:
				return true
			var note := ""
			match moment:
				SPLIT_DAY:
					note = _apply_split(rules, entry)
				BIRTH_DAY:
					note = _apply_aging_and_births(rules, entry)
				OLD_AGE_DEATH_DAY:
					note = _apply_old_age_deaths(rules, entry, day)
			if note == "":
				continue
			changed = true
			if DebugLogging.ENABLED:
				print("[WILD FAUNA] giorno %d %s%s (%d,%d): %s -> %d/%d/%d (giovani/adulti/vecchi)" % [day,
					"recupero " if recovering else "", entry.species, entry.region.x, entry.region.y, note,
					_count(entry, GameTypes.AgeBand.YOUNG), _count(entry, GameTypes.AgeBand.ADULT),
					_count(entry, GameTypes.AgeBand.OLD)])
	return changed


# Mandria a zero (caccia, vecchiaia): riquadro "assente" da `day`, e la specie ci tornerà (returns).
static func _empty_region(entry: WildFaunaRegion, day: int) -> void:
	entry.status = WildFaunaRegion.Status.ABSENT
	entry.extinct_since_day = day
	entry.current_cell = Vector2i(-1, -1)
	entry.returns = true


# Passo 3b: arriva un gruppetto nel riquadro il giorno `arrival_day`, in una cella adatta a caso. False se il riquadro
# non ha celle adatte.
static func _recolonize(world: World, game_data: GameData, rules: AnimalRules, entry: WildFaunaRegion, arrival_day: int,
		today: int) -> bool:
	var suitable := _suitable_cells(world, rules, entry.region, entry.side)
	if suitable.is_empty():
		return false
	entry.status = WildFaunaRegion.Status.PRESENT
	entry.extinct_since_day = -1
	entry.returns = false
	_roll_herd(game_data, rules, entry, RECOLONIZE_START_RATIO)
	entry.previous_cell = Vector2i(-1, -1)
	entry.current_cell = suitable.pick_random()
	entry.stay_remaining = randi_range(rules.herd_stay_days_min, maxi(rules.herd_stay_days_min, rules.herd_stay_days_max))
	entry.last_move_day = today
	if DebugLogging.ENABLED:
		print("[WILD FAUNA] giorno %d %s (%d,%d): ricolonizzato, arrivati %d/%d/%d (giovani/adulti/vecchi) in (%d, %d)" % [
			arrival_day, entry.species, entry.region.x, entry.region.y, _count(entry, GameTypes.AgeBand.YOUNG),
			_count(entry, GameTypes.AgeBand.ADULT), _count(entry, GameTypes.AgeBand.OLD), entry.current_cell.x,
			entry.current_cell.y])
	return true


# Fine estate: sopra il massimo una parte se ne va (per età: dispersal_share_by_age × capi della fascia)
# e la mandria torna tra SPLIT_TARGET_MIN_RATIO e SPLIT_TARGET_MAX_RATIO del massimo.
static func _apply_split(rules: AnimalRules, entry: WildFaunaRegion) -> String:
	var cap := maxi(1, rules.herd_size_max)
	var total := entry.get_total()
	if total <= cap:
		return ""
	var target := maxi(1, randi_range(roundi(cap * SPLIT_TARGET_MIN_RATIO), roundi(cap * SPLIT_TARGET_MAX_RATIO)))
	# Peso di ogni fascia = voglia di partire (dispersal_share_by_age) × quanti ce ne sono: partono soprattutto i giovani,
	# ma una fascia piccola non si svuota da sola.
	var weights: Dictionary = {}
	for age_band in [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]:
		var share := maxf(0.0001, rules.dispersal_share_by_age[age_band]) \
			if age_band < rules.dispersal_share_by_age.size() else 1.0
		weights[age_band] = share * _count(entry, age_band)
	var leaving := MacroCellState._split_by_weight_capped(weights, entry.age_counts.duplicate(), total - target)
	for age_band in leaving:
		entry.age_counts[age_band] = _count(entry, age_band) - int(leaving[age_band])
	return "split, partiti %d/%d/%d" % [int(leaving.get(GameTypes.AgeBand.YOUNG, 0)),
		int(leaving.get(GameTypes.AgeBand.ADULT, 0)), int(leaving.get(GameTypes.AgeBand.OLD, 0))]


# Inizio primavera: prima l'invecchiamento (così i nuovi nati non diventano subito adulti), poi le nascite piene col
# tasso della specie, senza freno — il massimo lo riporta a posto lo split dell'anno dopo.
static func _apply_aging_and_births(rules: AnimalRules, entry: WildFaunaRegion) -> String:
	var young := _count(entry, GameTypes.AgeBand.YOUNG)
	var adult := _count(entry, GameTypes.AgeBand.ADULT)
	var to_adult := mini(young, _random_round(float(young) / maxi(1, rules.youth_duration_years)))
	var to_old := mini(adult, _random_round(float(adult) / maxi(1, rules.adult_duration_years)))
	entry.age_counts[GameTypes.AgeBand.YOUNG] = young - to_adult
	entry.age_counts[GameTypes.AgeBand.ADULT] = adult - to_old + to_adult
	entry.age_counts[GameTypes.AgeBand.OLD] = _count(entry, GameTypes.AgeBand.OLD) + to_old
	var fertile := 0.0
	for age_band in [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]:
		if age_band < rules.fertility_multiplier_by_age.size():
			fertile += _count(entry, age_band) * rules.fertility_multiplier_by_age[age_band]
	var births := _random_round(fertile * rules.base_birth_rate)
	entry.age_counts[GameTypes.AgeBand.YOUNG] = _count(entry, GameTypes.AgeBand.YOUNG) + births
	return "%d diventati adulti, %d diventati vecchi, +%d nati" % [to_adult, to_old, births]


# Fine autunno: muore di vecchiaia 1/old_duration_years dei vecchi. Mandria a zero -> riquadro "assente" da quel giorno.
static func _apply_old_age_deaths(rules: AnimalRules, entry: WildFaunaRegion, day: int) -> String:
	var old := _count(entry, GameTypes.AgeBand.OLD)
	var deaths := mini(old, _random_round(float(old) / maxi(1, rules.old_duration_years)))
	entry.age_counts[GameTypes.AgeBand.OLD] = old - deaths
	if entry.get_total() <= 0:
		_empty_region(entry, day)
		return "%d morti di vecchiaia — mandria estinta" % deaths
	return "%d morti di vecchiaia" % deaths


static func _count(entry: WildFaunaRegion, age_band: int) -> int:
	return int(entry.age_counts.get(age_band, 0))


# Arrotondamento a caso secondo la parte decimale (2.3 -> 3 una volta su 3 circa): con mandrie piccole un
# arrotondamento normale non farebbe mai invecchiare o nascere nessuno.
static func _random_round(value: float) -> int:
	var whole := floori(value)
	return whole + (1 if randf() < value - whole else 0)


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
	entry.previous_cell = from
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
