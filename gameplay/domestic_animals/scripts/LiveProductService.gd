class_name LiveProductService
extends RefCounted

# Prodotti da vivi degli animali tenuti (2026-11-17, richiesta utente — pollaio, uova). Ogni giorno ogni animale che
# produce (LiveProductRules.produces) dà per_day della stagione di oggi di ciascun prodotto della sua specie
# (DomesticAnimalRules.live_products). Si accumula nel deposito dell'edificio (Building.stored_resources, scritto
# direttamente come il letame: l'edificio non accetta il prodotto da fuori), un massimo per prodotto =
# BuildingRules.live_product_capacity (pollaio 40); oltre, quello in più si perde. Le frazioni restano in
# Building.live_product_pending finché non fanno un'unità intera. Le unità nuove entrano fresche (deperimento 0) e si
# mediano con quelle già dentro; poi deperiscono come in ogni edificio (ResourceDecayService, moltiplicatore 1.0 se
# l'edificio non ne ha uno suo). Lo svuotamento verso il magazzino è il passo dopo. Stateless, statico.


static func capacity(building: Building) -> int:
	return building.rules.live_product_capacity if building != null and building.rules != null else 0


static func stored(building: Building, product: String) -> int:
	if building == null:
		return 0
	return int((building.stored_resources.get(product, {}) as Dictionary).get("quantity", 0))


static func season_of(game_data: GameData) -> int:
	if game_data == null:
		return 0
	return SeasonCalculator.get_season_for_day(posmod(game_data.get_absolute_day(), GameData.DAYS_PER_YEAR))


# Prodotti delle specie tenute in `building`, in ordine: nome -> resa al giorno di oggi (0 se fuori stagione).
static func daily_production(game_data: GameData, building: Building) -> Dictionary:
	var result: Dictionary = {}
	if building == null or game_data == null or capacity(building) <= 0:
		return result
	_add_production(result, DomesticAnimalService.get_kept_animals(game_data, building.id), season_of(game_data),
		game_data.get_absolute_day())
	return result


# Produzione di oggi: `animals` sono quelli vivi nell'edificio. Ritorna i prodotti arrivati al massimo proprio oggi (avviso).
static func produce_day(game_data: GameData, building: Building, animals: Array) -> Array[String]:
	var just_full: Array[String] = []
	if building == null or game_data == null or capacity(building) <= 0 or animals.is_empty():
		return just_full
	var made: Dictionary = {}
	_add_production(made, animals, season_of(game_data), game_data.get_absolute_day())
	for product: String in made:
		if float(made[product]) <= 0.0:
			continue
		var pending := float(building.live_product_pending.get(product, 0.0)) + float(made[product])
		var whole := floori(pending + 0.000001)
		building.live_product_pending[product] = maxf(pending - float(whole), 0.0)
		if whole <= 0:
			continue
		var entry: Dictionary = building.stored_resources.get(product, {})
		var before := int(entry.get("quantity", 0))
		var after := mini(before + whole, capacity(building))
		if after == before:
			continue
		var decay := ToolInstance.merged_lot_decay(entry, after - before, 0.0)
		building.stored_resources[product] = {"quantity": after, "decay_fraction": decay}
		if after >= capacity(building):
			just_full.append(product)
	return just_full


static func _add_production(result: Dictionary, animals: Array, season: int, absolute_day: int) -> void:
	for animal: DomesticAnimal in animals:
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null:
			continue
		for entry in rules.live_products:
			var product_rules := entry as LiveProductRules
			if product_rules == null or product_rules.product.is_empty():
				continue
			if not result.has(product_rules.product):
				result[product_rules.product] = 0.0
			if product_rules.produces(animal, absolute_day):
				result[product_rules.product] = float(result[product_rules.product]) + product_rules.per_day(season)
