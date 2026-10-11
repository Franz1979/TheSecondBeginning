class_name StockRequestService
extends RefCounted

# Richieste del magazzino (2026-10-11, richiesta utente — gestione scorte, primo passo: materiali grezzi). Dai livelli
# minimi della partita (GameData.stock_min_levels) e dalle scorte del villaggio (VillageStockService.get_village_stock)
# calcola quali ordini di zona del cassetto creare (raccolta, taglio, estrazione), solo in zona automatica. Il magazzino
# GENERA soltanto: chi prende gli ordini e quando lo decide la coda dei lavori, con le priorità dell'assegnazione.
#
# Un ordine = una serie per un solo individuo (ogni presa costa un'ora di istruzione al coordinatore): count =
# deficit scoperto / resa per unità (viaggio, pianta, roccia), al massimo una serie piena. Deficit più grande di una
# serie = altri ordini, fino a MAX_ORDERS_PER_RESOURCE, presi da individui diversi. Deficit scoperto = livello − scorta
# − copertura degli ordini del magazzino ancora aperti per quella risorsa (quello che resta × resa). Stateless, funzioni
# statiche e pure: nessuna lettura della scena.
#
# Prodotti animali (2026-10-11): caccia, una domanda unica in carne per il gruppo (SOURCE_HUNT). Fuori per ora: cibo
# (regola dei giorni di autonomia, da fare), semilavorati.

# Chiave nell'ordine del cassetto: nome della risorsa per cui il magazzino l'ha creato.
const ORDER_KEY := "stock_resource"
const MAX_ORDERS_PER_RESOURCE: int = 3
# Tetto degli ordini "Raccogli ogni cibo" per i giorni di autonomia (2026-10-11, richiesta utente): più alto, il cibo
# serve a tutti e con l'inventario gli ordini nascono una volta per giro.
const MAX_FOOD_DAYS_ORDERS: int = 5

const SOURCE_GATHER := "gather"
const SOURCE_CUT := "cut"
const SOURCE_QUARRY := "quarry"
# Caccia (2026-10-11): carne, pelle, tendini e ossa arrivano tutti dalla stessa preda macellata, quindi una sola domanda
# per il gruppo, in carne (vedi GameScene._auto_request_hunt). Ordini da 5 a STOCK_HUNT_MAX_MEAT carne, a passi di
# HUNT_MEAT_STEP: il 20 del cassetto resta per la caccia lanciata a mano.
const SOURCE_HUNT := "hunt"
const HUNT_GROUP_KEY := "meat"
const HUNT_MEAT_STEP: int = 5
const STOCK_HUNT_MAX_MEAT: int = 10
# Produzione (2026-10-11): prodotti con ricetta (non ad avanzamento automatico), ordini "Produci" del cassetto. Gli ordini
# NON procurano mai i propri ingredienti: la catena la organizza il giocatore con i livelli delle materie prime.
const SOURCE_PRODUCE := "produce"
# Essiccatoio (2026-10-11): prodotti ad avanzamento automatico (recipe_auto_progress_days > 0, carne e pelle essiccate):
# il magazzino trasporta l'ingrediente crudo dal deposito all'essiccatoio (GameScene._auto_request_dry).
const SOURCE_DRY := "dry"
# Nome del combustibile nel dizionario dei mancanti (missing_for_recipe).
const FUEL_KEY := "__fuel__"
# Giorni di autonomia del cibo (2026-10-11, GameScene._auto_request_food_days): ORDER_KEY degli ordini "Raccogli tutto il
# cibo" e marca (FOOD_DAYS_KEY) degli ordini "Produci carne cotta" nati per i giorni.
const FOOD_DAYS_ORDER_KEY := "food_days"
const FOOD_DAYS_KEY := "food_days_order"
# Unica eccezione alla regola "la catena la organizza il giocatore" (2026-10-11, richiesta utente): queste risorse non hanno
# un livello minimo proprio; il loro fabbisogno nasce dai livelli dei prodotti che le usano (la carne cruda: carne cotta,
# affumicata ed essiccata — GameScene._derived_meat_level). Il cassetto Scorte non mostra il loro campo del livello.
const DERIVED_LEVEL_RESOURCES: Array[String] = ["meat"]


# Come si procura la risorsa: SOURCE_GATHER (raccoglibile a terra, lot_source), SOURCE_CUT (resa del taglio di un
# sottotipo di albero o arbusto), SOURCE_QUARRY (resa dell'estrazione della roccia); "" = nessun ordine automatico
# (cibo, prodotti animali, semilavorati, risorse sconosciute). La raccolta vince sul taglio (stick: si raccoglie).
static func source_kind_for(resource_name: String) -> String:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null:
		return ""
	if not rules.recipe_inputs.is_empty() and rules.recipe_auto_progress_days > 0:
		return SOURCE_DRY
	if not rules.recipe_inputs.is_empty():
		return SOURCE_PRODUCE
	# Raccoglibile a terra di qualunque categoria (2026-10-11: cibi raccolti, erbe medicinali), non solo materie prime.
	if rules.generation_source != SecondaryResourceTypes.GenerationSource.ANIMAL_DERIVED \
			and TerrainScatteredResourceService.is_pickable(resource_name):
		return SOURCE_GATHER
	if rules.category != SecondaryResourceTypes.Category.RAW_MATERIAL:
		return ""
	if rules.generation_source == SecondaryResourceTypes.GenerationSource.ANIMAL_DERIVED:
		return SOURCE_HUNT if get_meat_per_unit(resource_name) > 0.0 else ""
	if rules.lot_source != SecondaryResourceTypes.LotSource.NONE:
		return SOURCE_GATHER
	if get_cut_yield_per_plant(resource_name) > 0:
		return SOURCE_CUT
	var rock_rules := ResourceCalculator.get_density_rules(GameTypes.WorldObjectType.ROCK)
	if rock_rules != null and rock_rules.extraction_yield_resource_name == resource_name:
		return SOURCE_QUARRY
	return ""


# Resa di una pianta tagliata per `resource_name`: la più bassa tra i sottotipi di albero e arbusto che la danno (stima
# prudente: meglio un taglio in più che uno in meno); 0 se nessuno la dà.
static func get_cut_yield_per_plant(resource_name: String) -> int:
	var best := 0
	for object_type in [GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB]:
		var growth_rules := ResourceCalculator.get_growth_rules(object_type)
		if growth_rules == null:
			continue
		for subtype in growth_rules.subtypes:
			var rule := subtype as SubtypeRules
			if rule == null or rule.cut_yield_resource_name != resource_name or rule.cut_yield_base <= 0:
				continue
			best = rule.cut_yield_base if best == 0 else mini(best, rule.cut_yield_base)
	return best


# Pietre di un'estrazione piena (ResourceDensityRules di ROCK); 0 se la roccia non si estrae.
static func get_quarry_yield_per_extraction() -> int:
	var rock_rules := ResourceCalculator.get_density_rules(GameTypes.WorldObjectType.ROCK)
	if rock_rules == null or rock_rules.extraction_yield_resource_name == "":
		return 0
	return maxi(rock_rules.extraction_units_per_extraction, 0)


# Unità di `resource_name` in un viaggio con `carry_capacity` di spazio nello zaino; almeno 1.
static func get_gather_units_per_trip(resource_name: String, carry_capacity: float) -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null or rules.space_per_unit <= 0.0:
		return 1
	return maxi(int(floor(carry_capacity / rules.space_per_unit + FoodSelectionService.UNIT_FIT_EPSILON)), 1)


# Massimo della serie per il tipo di ordine (lo stesso tetto del cassetto).
static func get_series_max(source_kind: String) -> int:
	match source_kind:
		SOURCE_GATHER:
			return HaulZoneService.WORK_AREA_MAX_TRIPS
		SOURCE_CUT:
			return CutZoneService.COUNT_MAX
		SOURCE_QUARRY:
			return QuarryZoneService.COUNT_MAX
		SOURCE_HUNT:
			return STOCK_HUNT_MAX_MEAT
	return 0


# Carne che "vale" un'unità di `resource_name` macellato: media, sulle specie che lo danno, di carne / prodotto per preda
# (ButcherAction.compute_yields a fascia piena). 1 per la carne; 0 se nessuna specie lo dà.
static func get_meat_per_unit(resource_name: String) -> float:
	if resource_name == HuntZoneService.MEAT_RESOURCE:
		return 1.0
	var total := 0.0
	var count := 0
	for species in AnimalCalculator.list_species_names():
		var yields := ButcherAction.compute_yields(species, -1)
		var meat := int(yields.get(HuntZoneService.MEAT_RESOURCE, 0))
		var product := int(yields.get(resource_name, 0))
		if meat <= 0 or product <= 0:
			continue
		total += float(meat) / float(product)
		count += 1
	return total / float(count) if count > 0 else 0.0


# Cosa manca per `quantity` cicli della ricetta `recipe` con le scorte `stock`: nome -> unità mancanti; il combustibile
# (FUEL_KEY) in valore di combustibile mancante (fuel_per_cycle × quantity meno la somma di quantità × fuel_value delle
# scorte che bruciano). Vuoto = si può fare tutto.
static func missing_for_recipe(recipe: String, quantity: int, stock: Dictionary, fuel_per_cycle: float) -> Dictionary:
	var missing: Dictionary = {}
	var rules := CaloricCalculator.get_caloric_source_rules(recipe)
	if rules == null:
		return missing
	for input_name in rules.recipe_inputs.keys():
		var needed := int(rules.recipe_inputs[input_name]) * quantity
		var have := int(stock.get(String(input_name), 0))
		if have < needed:
			missing[String(input_name)] = needed - have
	if fuel_per_cycle > 0.0:
		var fuel_needed := fuel_per_cycle * float(quantity)
		var fuel_have := 0.0
		for name in stock.keys():
			if rules.recipe_inputs.has(name):
				continue
			var fuel_rules := CaloricCalculator.get_caloric_source_rules(String(name))
			if fuel_rules != null and fuel_rules.fuel_value > 0.0:
				fuel_have += float(stock[name]) * fuel_rules.fuel_value
		if fuel_have + 0.0001 < fuel_needed:
			missing[FUEL_KEY] = fuel_needed - fuel_have
	return missing


# Carne di un ordine di caccia: per eccesso al passo HUNT_MEAT_STEP, tra HUNT_MEAT_STEP e STOCK_HUNT_MAX_MEAT.
static func snap_hunt_count(meat: int) -> int:
	return clampi(ceili(float(meat) / float(HUNT_MEAT_STEP)) * HUNT_MEAT_STEP, HUNT_MEAT_STEP, STOCK_HUNT_MAX_MEAT)


# Ordini da creare per `resource_name`: Array di count (uno per ordine nuovo). `level` livello minimo, `stock` scorta
# attuale, `open_coverage` unità già coperte dagli ordini aperti, `open_orders` quanti sono, `unit_yield` unità per
# viaggio / pianta / estrazione, `series_max` tetto della serie.
static func compute_new_order_counts(
	level: int, stock: int, open_coverage: int, open_orders: int, unit_yield: int, series_max: int,
	max_orders: int = MAX_ORDERS_PER_RESOURCE
) -> Array[int]:
	var counts: Array[int] = []
	if level <= 0 or unit_yield <= 0 or series_max <= 0:
		return counts
	var uncovered := level - stock - open_coverage
	var orders := open_orders
	while uncovered > 0 and orders < max_orders:
		var count := mini(ceili(float(uncovered) / float(unit_yield)), series_max)
		counts.append(count)
		uncovered -= count * unit_yield
		orders += 1
	return counts


# true se un ordine non preso con copertura `order_coverage` è di troppo: senza di lui scorta e copertura degli altri
# ordini aperti (`total_open_coverage` lo comprende) arrivano già al livello più `margin`. Livello tolto (0) = sempre di
# troppo. `margin` (2026-10-11, contro l'oscillazione: un ordine creato e tolto a ogni scarico perché la stima "in arrivo"
# sale e scende di poco) = la resa di un'unità dell'ordine (un viaggio, una pianta, un pezzo, un passo di carne).
static func is_order_surplus(level: int, stock: int, total_open_coverage: int, order_coverage: int, margin: int = 0) -> bool:
	if level <= 0:
		return true
	return stock + total_open_coverage - order_coverage >= level + margin
