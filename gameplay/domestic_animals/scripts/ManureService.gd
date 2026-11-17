class_name ManureService
extends RefCounted

# Letame degli edifici con animali (2026-11-17, richiesta utente — conigliera, fase 1). Ogni animale tenuto ne fa
# DomesticAnimalRules.manure_per_day (coniglio 0.025: 50 conigli ~1,25 al giorno), con o senza lettiera. Si accumula nel
# deposito dell'edificio (Building.stored_resources[RESOURCE], scritto direttamente: l'edificio non lo accetta da fuori)
# fino a BuildingRules.manure_capacity (conigliera 100); oltre, quello che fanno in più si perde. Le frazioni di oggi
# restano in Building.manure_pending finché non fanno un'unità intera. Lo porta via la pulizia del gestore scorte
# (ManureStockService): al letamaio più vicino con posto, altrimenti alla Fossa dei rifiuti. Il letame non deperisce. Le
# conseguenze del letame al massimo (malattie) arriveranno nel passo dopo. Stateless, statico.

const RESOURCE := "manure"


# Letame che l'edificio tiene (0 = nessun deposito di letame).
static func capacity(building: Building) -> int:
	return building.rules.manure_capacity if building != null and building.rules != null else 0


static func has_manure_store(building: Building) -> bool:
	return building != null and capacity(building) > 0 and building.is_complete and not building.is_demolished


# Letame dentro adesso (unità intere).
static func stored(building: Building) -> int:
	if building == null:
		return 0
	return int((building.stored_resources.get(RESOURCE, {}) as Dictionary).get("quantity", 0))


# Letame al giorno degli animali presenti.
static func daily_production(game_data: GameData, building: Building) -> float:
	if building == null or game_data == null:
		return 0.0
	var total := 0.0
	for animal in DomesticAnimalService.get_kept_animals(game_data, building.id):
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules != null:
			total += rules.manure_per_day
	return total


# Produzione di oggi: `animals` sono quelli vivi nell'edificio. true se il letame è arrivato al massimo proprio oggi (avviso).
static func produce_day(building: Building, animals: Array) -> bool:
	if building == null or capacity(building) <= 0 or animals.is_empty():
		return false
	var made := 0.0
	for animal: DomesticAnimal in animals:
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules != null:
			made += rules.manure_per_day
	if made <= 0.0:
		return false
	building.manure_pending += made
	var whole := floori(building.manure_pending + 0.000001)
	if whole <= 0:
		return false
	building.manure_pending = maxf(building.manure_pending - float(whole), 0.0)
	var before := stored(building)
	var after := mini(before + whole, capacity(building))
	if after == before:
		return false
	building.stored_resources[RESOURCE] = {"quantity": after, "decay_fraction": 0.0}
	return after >= capacity(building)
