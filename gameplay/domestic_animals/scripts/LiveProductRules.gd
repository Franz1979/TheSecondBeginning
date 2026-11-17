class_name LiveProductRules
extends Resource

# Prodotto "da vivo" di una specie tenuta (2026-11-17, richiesta utente — pollaio, uova): una risorsa secondaria che gli
# animali danno senza essere macellati (uova, poi latte e lana). Sta nella lista DomesticAnimalRules.live_products, una
# voce per prodotto. Resa stagionale: per_day_by_season, una per GameTypes.Season (inverno, primavera, estate, autunno),
# quanto ne dà al giorno ogni animale che produce in quella stagione; 0 = niente. Chi produce: is_male_only /
# is_female_only (nessuno dei due = tutti) e adults_only. Si accumula nell'edificio fino a BuildingRules.
# live_product_capacity (LiveProductService). Per ora solo il modo "raccolta" (il prodotto si accumula da solo);
# mungitura e tosatura col lavoro arriveranno con latte e lana.

# Nome della risorsa secondaria (es. "eggs").
@export var product: String = ""
@export var per_day_by_season: Array[float] = [0.0, 0.0, 0.0, 0.0]
@export var is_female_only: bool = false
@export var is_male_only: bool = false
@export var adults_only: bool = true


# Resa al giorno di un animale nella stagione `season` (0 fuori range).
func per_day(season: int) -> float:
	if season < 0 or season >= per_day_by_season.size():
		return 0.0
	return maxf(per_day_by_season[season], 0.0)


# Se `animal` produce (sesso ed età); `absolute_day` serve per l'età.
func produces(animal: DomesticAnimal, absolute_day: int) -> bool:
	if animal == null:
		return false
	if is_female_only and animal.is_male:
		return false
	if is_male_only and not animal.is_male:
		return false
	if adults_only and animal.get_age_band(absolute_day, DomesticAnimalCalculator.get_wild_rules(animal.species)) != GameTypes.AgeBand.ADULT:
		return false
	return true
