class_name BeddingService
extends RefCounted

# Lettiera degli edifici con animali (2026-11-17, richiesta utente — conigliera, 100 paglia per 50 posti): un deposito a parte, come la mangiatoia,
# che accetta solo paglia (RESOURCE). Capienza in unità (BuildingRules.bedding_capacity, 0 = nessuna lettiera), contenuto
# in Building.bedding_straw (salvato). La paglia entrata non deperisce e non torna in magazzino. Ogni giorno ogni animale
# dentro ne consuma DomesticAnimalRules.bedding_per_day (coniglio 1 ogni 20 giorni: 0.05), in DomesticAnimalLifeService.
# tick_day. Rifornimento: regola "Lettiera" del gestore scorte (BeddingStockService) o Trasporto manuale.
# EFFETTO (2026-11-17, richiesta utente): gli adulti non ne soffrono, i piccoli sì. Si contano i giorni con animali e quelli
# con la lettiera vuota (meno di 1 paglia) dalle ultime nascite; il giorno delle nascite ogni piccolo muore appena nato con
# newborn_death_chance: con la lettiera vuota quel giorno DomesticAnimalRules.newborn_death_without_bedding (coniglio 0.75),
# altrimenti quella × giorni vuota / giorni con animali. Così conta tutto l'anno: riempirla solo per le nascite non basta,
# e non basta nemmeno tenerla piena tutto l'anno e lasciarla vuota quel giorno. Stateless, statico.

const RESOURCE := "straw"


# Paglia che la lettiera tiene (0 = nessuna).
static func capacity(building: Building) -> int:
	return building.rules.bedding_capacity if building != null and building.rules != null else 0


# true per un edificio finito, in piedi, con una lettiera.
static func has_bedding(building: Building) -> bool:
	return building != null and capacity(building) > 0 and building.is_complete and not building.is_demolished


static func accepts(building: Building, resource_name: String) -> bool:
	return resource_name == RESOURCE and has_bedding(building)


# Unità di paglia che ci stanno ancora.
static func max_depositable(building: Building, resource_name: String) -> int:
	if not accepts(building, resource_name):
		return 0
	return maxi(floori(float(capacity(building)) - building.bedding_straw + 0.000001), 0)


# Versa fino a `quantity` unità; ritorna quante ne sono entrate. Lo zaino lo svuota chi chiama.
static func deposit(building: Building, resource_name: String, quantity: int) -> int:
	var units := mini(quantity, max_depositable(building, resource_name))
	if units <= 0:
		return 0
	building.bedding_straw += float(units)
	DebugLogging.print_event("[BEDDING] Edificio %d: +%d paglia, lettiera %.1f/%d" % [building.id, units, building.bedding_straw,
		capacity(building)])
	return units


# Paglia al giorno di un animale della specie tenuta (0 se non è decisa).
static func use_per_animal(game_data: GameData, building: Building) -> float:
	var species := KeptAnimalService.current_species(game_data, building)
	var rules := DomesticAnimalCalculator.get_rules(species) if species != "" else null
	return rules.bedding_per_day if rules != null else 0.0


# Paglia al giorno degli animali presenti.
static func daily_use(game_data: GameData, building: Building) -> float:
	if building == null or game_data == null:
		return 0.0
	var total := 0.0
	for animal in DomesticAnimalService.get_kept_animals(game_data, building.id):
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules != null:
			total += rules.bedding_per_day
	return total


# Paglia al giorno con tutti i posti occupati (obiettivo del gestore scorte, come la mangiatoia).
static func target_daily_use(game_data: GameData, building: Building) -> float:
	return float(KeptAnimalService.capacity(building)) * use_per_animal(game_data, building)


# true con meno di una paglia dentro.
static func is_empty(building: Building) -> bool:
	return building.bedding_straw < 1.0


# Consumo di oggi: `animals` sono quelli vivi nell'edificio. Mai sotto 0. Conta il giorno (con animali, vuota). true se la
# lettiera è rimasta vuota proprio oggi (avviso).
static func consume_day(building: Building, animals: Array) -> bool:
	if building == null or capacity(building) <= 0 or animals.is_empty():
		return false
	var was_empty := is_empty(building)
	var use := 0.0
	for animal: DomesticAnimal in animals:
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules != null:
			use += rules.bedding_per_day
	if use <= 0.0:
		return false
	building.bedding_straw = maxf(building.bedding_straw - use, 0.0)
	building.bedding_days_with_animals += 1
	if is_empty(building):
		building.bedding_days_empty += 1
	return not was_empty and is_empty(building)


# Probabilità che un piccolo di `rules` nato oggi in `building` muoia per la lettiera (0 senza lettiera o senza effetto).
static func newborn_death_chance(building: Building, rules: DomesticAnimalRules) -> float:
	if building == null or capacity(building) <= 0 or rules == null or rules.newborn_death_without_bedding <= 0.0:
		return 0.0
	if is_empty(building):
		return rules.newborn_death_without_bedding
	return rules.newborn_death_without_bedding * year_empty_ratio(building)


# Quota di giorni vuota sui giorni con animali, dalle ultime nascite (0 senza giorni contati).
static func year_empty_ratio(building: Building) -> float:
	if building.bedding_days_with_animals <= 0:
		return 0.0
	return float(building.bedding_days_empty) / float(building.bedding_days_with_animals)


# Dopo le nascite i contatori ripartono.
static func reset_year(building: Building) -> void:
	if building != null:
		building.bedding_days_with_animals = 0
		building.bedding_days_empty = 0


# Regole della specie tenuta (null se non è decisa).
static func species_rules(game_data: GameData, building: Building) -> DomesticAnimalRules:
	var species := KeptAnimalService.current_species(game_data, building)
	return DomesticAnimalCalculator.get_rules(species) if species != "" else null
