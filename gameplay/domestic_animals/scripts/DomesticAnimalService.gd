class_name DomesticAnimalService
extends RefCounted

# Animali domestici della partita (cane, passo 1, 2026-11-03): unico punto che aggiunge a GameData.domestic_animals.


# null con warning se la specie non esiste o non ha animali veri (DomesticAnimalRules.individuals_enabled).
static func add_animal(game_data: GameData, species: String, is_male: bool, birth_day: int, village_id: int = -1) -> DomesticAnimal:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null or not rules.individuals_enabled:
		push_warning("DomesticAnimalService: specie domestica '%s' inesistente o non attiva" % species)
		return null
	var animal := DomesticAnimal.new()
	animal.id = game_data.allocate_domestic_animal_id()
	animal.species = species
	animal.is_male = is_male
	animal.birth_day = birth_day
	animal.village_id = village_id
	game_data.domestic_animals.append(animal)
	return animal


# Quanti animali di quel sesso mancano al numero voluto per gli arrivi (DomesticAnimalRules.arrival_target_*).
static func missing_for_arrival(game_data: GameData, rules: DomesticAnimalRules, is_male: bool) -> int:
	var target := rules.arrival_target_males if is_male else rules.arrival_target_females
	var present := 0
	for animal in get_animals(game_data, rules.species_name):
		if animal.is_male == is_male:
			present += 1
	return maxi(target - present, 0)


# Specie attiva con tutti gli animali voluti: la selvatica non dà più punti (cane: le 2 coppie).
static func has_all_arrivals(game_data: GameData, rules: DomesticAnimalRules) -> bool:
	return rules.individuals_enabled and missing_for_arrival(game_data, rules, true) == 0 \
		and missing_for_arrival(game_data, rules, false) == 0


static func get_animals(game_data: GameData, species: String) -> Array[DomesticAnimal]:
	var animals: Array[DomesticAnimal] = []
	for animal in game_data.domestic_animals:
		if animal.species == species:
			animals.append(animal)
	return animals
