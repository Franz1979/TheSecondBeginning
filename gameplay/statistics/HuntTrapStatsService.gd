class_name HuntTrapStatsService
extends RefCounted

# Contatori di debug di caccia e trappole (2026-11-15, richiesta utente — «caccia grossi animali»: capire perché le prede
# grosse non si prendono quasi mai). Unico scrittore di GameData.hunt_trap_stats; letti da HuntTrapStatsPanel (barra di
# debug viola). Per anno (chiave = str(GameData.year)), il totale è la somma degli anni.
#
# Struttura di un anno:
#   "hunt":        specie -> {"attempts", "throws", "hits", "kills"}
#                  attempts = inseguimenti iniziati su una preda (ApproachPreyAction, uno per preda per Task),
#                  throws = armi partite (ThrowAction), hits = colpi a segno (anche non letali), kills = prede uccise.
#   "trap_placed": trappola -> trappole posate
#   "trap_catch":  trappola -> specie -> catture (contate quando la preda entra, anche se poi marcisce o la trappola
#                  non viene svuotata; nasse e reti senza specie: la risorsa pescata/presa)
#                  butchered = carcasse di caccia macellate (ButcherAction), rotted = marcite a terra (GroundPileService).
#   "trap_outcome": trappola -> specie -> {"recovered", "spoiled"}: prede tolte allo svuotamento (macellate sul posto o
#                  portate vive alla tettoia) e prede marcite dentro o perse con la trappola che si rompe.
#   "drive":       specie -> {"drives", "animals"} spinte verso le fosse (PitDriveService.drive) e animali partiti
#   "hides":       origine -> pelli grezze (hide) prodotte: caccia (macellazione di una carcassa di caccia), trappole
#                  (svuotamento), altro (allevamento, carcasse non di caccia).
# Il fabbisogno di pelli (hides_demand) non è un contatore: si calcola sul momento da cantieri, riparazioni e produzioni.

const HUNT_ATTEMPTS := "attempts"
const HUNT_THROWS := "throws"
const HUNT_HITS := "hits"
const HUNT_KILLS := "kills"
const HUNT_BUTCHERED := "butchered"
const HUNT_ROTTED := "rotted"
const TRAP_RECOVERED := "recovered"
const TRAP_SPOILED := "spoiled"
const HIDE_SOURCE_HUNT := "caccia"
const HIDE_SOURCE_TRAPS := "trappole"
const HIDE_SOURCE_OTHER := "altro"
# Pelli e lavorati di pelle seguiti dal fabbisogno.
const HIDE_RESOURCES: Array[String] = ["hide", "dried_hide", "smoked_hide"]
# Chiave della carcassa (GroundPile.carcasses) uccisa a caccia (ThrowAction): solo quelle contano come macellate/marcite.
const CARCASS_HUNTED_KEY := "hunted"
# Chiave del context della Task di caccia: preda già contata come tentativo (ApproachPreyAction).
const CONTEXT_COUNTED_PREY := "hunt_stats_counted_prey"
# Periodi di get_stats oltre agli anni: tutti gli anni, e da quando la partita è stata caricata o creata.
const PERIOD_TOTAL := -1
const PERIOD_SINCE_LOAD := -2

# Periodo "Dal caricamento" (2026-11-15, richiesta utente): copia del totale quando la partita è entrata in GameScene
# (mark_session_start). Solo in memoria, non salvata: vale per la partita `_session_owner`.
static var _session_baseline: Dictionary = {}
static var _session_owner: WeakRef = null


static func add_hunt(game_data: GameData, species: String, counter: String) -> void:
	_bump(game_data, ["hunt", _label(species), counter], 1)


# Tentativo contato una volta per preda per Task: i riavvicinamenti sulla stessa preda non contano di nuovo.
static func add_hunt_attempt_once(game_data: GameData, context: Dictionary, prey_id: int, species: String) -> void:
	if int(context.get(CONTEXT_COUNTED_PREY, 0)) == prey_id:
		return
	context[CONTEXT_COUNTED_PREY] = prey_id
	add_hunt(game_data, species, HUNT_ATTEMPTS)


static func add_trap_placed(game_data: GameData, trap_name: String) -> void:
	_bump(game_data, ["trap_placed", _label(trap_name)], 1)


static func add_trap_catch(game_data: GameData, trap_name: String, species: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_bump(game_data, ["trap_catch", _label(trap_name), _label(species)], amount)


static func add_trap_outcome(game_data: GameData, trap_name: String, species: String, kind: String, amount: int = 1) -> void:
	_bump(game_data, ["trap_outcome", _label(trap_name), _label(species), kind], amount)


static func add_hides_produced(game_data: GameData, source: String, amount: int) -> void:
	if amount > 0:
		_bump(game_data, ["hides", source], amount)


# Fabbisogno di pelli ADESSO: per risorsa di HIDE_RESOURCES, {"construction", "repair", "production", "orders", "stock",
# "missing"}. construction = cantieri (setup e materiali, MaterialSupplyService.get_missing_materials), production = input
# mancanti alle produzioni in corso sulle postazioni, repair = materiali da portare alle riparazioni (RepairAction.
# get_supply_missing, edifici sotto l'Integrità piena), orders = ingredienti degli ordini "Produci" del cassetto non ancora
# presi, stock = scorte del villaggio (VillageStockService), missing = richieste totali meno le scorte.
static func hides_demand(game_data: GameData, world: World) -> Dictionary:
	var result := {}
	for name in HIDE_RESOURCES:
		result[name] = {"construction": 0, "repair": 0, "production": 0, "orders": 0, "stock": 0, "missing": 0}
	if game_data == null or world == null:
		return result
	for building in world.buildings:
		if building == null or building.rules == null or building.is_demolished:
			continue
		var phase := "production" if building.is_complete else "construction"
		var missing := MaterialSupplyService.get_missing_materials(building)
		for name in HIDE_RESOURCES:
			result[name][phase] += int(missing.get(name, 0))
		if RepairAction.is_building_repairable(building) and building.current_durability < float(building.rules.max_durability):
			var repair := RepairAction.get_supply_missing(building)
			for name in HIDE_RESOURCES:
				result[name]["repair"] += int(repair.get(name, 0))
	for order in game_data.drawer_orders:
		if String(order.get("type", "")) != DrawerOrderService.TYPE_PRODUCE or bool(order.get("taken", false)):
			continue
		var rules := CaloricCalculator.get_caloric_source_rules(String(order.get("recipe", "")))
		if rules == null:
			continue
		var units := maxi(int(order.get("quantity", 1)), 1)
		for name in HIDE_RESOURCES:
			result[name]["orders"] += int(rules.recipe_inputs.get(name, 0)) * units
	var stock := VillageStockService.get_village_stock(world)
	for name in HIDE_RESOURCES:
		var entry: Dictionary = result[name]
		entry["stock"] = int(stock.get(name, 0))
		var asked: int = entry["construction"] + entry["repair"] + entry["production"] + entry["orders"]
		entry["missing"] = maxi(asked - entry["stock"], 0)
	return result


static func add_drive(game_data: GameData, species: String, animals: int) -> void:
	_bump(game_data, ["drive", _label(species), "drives"], 1)
	_bump(game_data, ["drive", _label(species), "animals"], maxi(animals, 0))


# Inizio del periodo "Dal caricamento": da chiamare quando la partita entra in GameScene. Lo stesso GameData (ritorno
# dalla vista di una macrocella) non lo azzera.
static func mark_session_start(game_data: GameData) -> void:
	if game_data == null or (_session_owner != null and _session_owner.get_ref() == game_data):
		return
	_session_owner = weakref(game_data)
	_session_baseline = get_stats(game_data, PERIOD_TOTAL).duplicate(true)


# Anni con dati, in ordine.
static func years(game_data: GameData) -> Array[int]:
	var result: Array[int] = []
	if game_data == null:
		return result
	for key in game_data.hunt_trap_stats.keys():
		result.append(int(key))
	result.sort()
	return result


# Dati di un anno, la somma di tutti gli anni (PERIOD_TOTAL) o quello che è cambiato dal caricamento (PERIOD_SINCE_LOAD).
static func get_stats(game_data: GameData, year: int = PERIOD_TOTAL) -> Dictionary:
	if game_data == null:
		return {}
	if year >= 0:
		return game_data.hunt_trap_stats.get(str(year), {})
	var total := {}
	for year_data in game_data.hunt_trap_stats.values():
		_merge_into(total, year_data)
	if year == PERIOD_SINCE_LOAD and _session_owner != null and _session_owner.get_ref() == game_data:
		_subtract_from(total, _session_baseline)
	return total


# Copia dal salvataggio: i numeri del JSON tornano float, qui interi.
static func from_save(data: Variant) -> Dictionary:
	var result := {}
	if not data is Dictionary:
		return result
	for key in data:
		var value: Variant = data[key]
		result[String(key)] = from_save(value) if value is Dictionary else int(value)
	return result


static func _bump(game_data: GameData, path: Array, amount: int) -> void:
	if game_data == null or amount == 0:
		return
	var node: Dictionary = game_data.hunt_trap_stats
	var year_key := str(game_data.year)
	if not node.has(year_key):
		node[year_key] = {}
	node = node[year_key]
	for i in range(path.size() - 1):
		var key: String = path[i]
		if not node.has(key):
			node[key] = {}
		node = node[key]
	var last: String = path[-1]
	node[last] = int(node.get(last, 0)) + amount


static func _merge_into(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		var value: Variant = source[key]
		if value is Dictionary:
			if not target.has(key):
				target[key] = {}
			_merge_into(target[key], value)
		else:
			target[key] = int(target.get(key, 0)) + int(value)


# total -= baseline, voce per voce; le voci che restano a zero (o vuote) spariscono.
static func _subtract_from(total: Dictionary, baseline: Dictionary) -> void:
	for key in baseline:
		if not total.has(key):
			continue
		var value: Variant = total[key]
		if value is Dictionary:
			_subtract_from(value, baseline[key] if baseline[key] is Dictionary else {})
			if (value as Dictionary).is_empty():
				total.erase(key)
		else:
			var left := int(value) - int(baseline[key])
			if left > 0:
				total[key] = left
			else:
				total.erase(key)


static func _label(name: String) -> String:
	return name if name != "" else "?"
