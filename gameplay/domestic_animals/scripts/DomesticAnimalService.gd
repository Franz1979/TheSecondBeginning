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


# Animale tenuto in un edificio (2026-11-12, cattura viva: tettoia delle gabbie). Niente controllo su individuals_enabled:
# le specie da cattura non hanno ancora animali liberi. `is_wild` = specie non ancora arrivata alla soglia.
static func add_kept_animal(game_data: GameData, species: String, is_male: bool, birth_day: int, building_id: int,
		is_wild: bool) -> DomesticAnimal:
	if DomesticAnimalCalculator.get_rules(species) == null:
		push_warning("DomesticAnimalService: specie domestica '%s' inesistente" % species)
		return null
	var animal := DomesticAnimal.new()
	animal.id = game_data.allocate_domestic_animal_id()
	animal.species = species
	animal.is_male = is_male
	animal.birth_day = birth_day
	animal.building_id = building_id
	animal.is_wild = is_wild
	game_data.domestic_animals.append(animal)
	return animal


# Animali tenuti nell'edificio `building_id`.
static func get_kept_animals(game_data: GameData, building_id: int) -> Array[DomesticAnimal]:
	var animals: Array[DomesticAnimal] = []
	for animal in game_data.domestic_animals:
		if animal.building_id == building_id:
			animals.append(animal)
	return animals


static func find_animal(game_data: GameData, animal_id: int) -> DomesticAnimal:
	for animal in game_data.domestic_animals:
		if animal.id == animal_id:
			return animal
	return null


# Quanti animali di quel sesso mancano al numero voluto per gli arrivi (DomesticAnimalRules.arrival_target_*).
static func missing_for_arrival(game_data: GameData, rules: DomesticAnimalRules, is_male: bool) -> int:
	var target := rules.arrival_target_males if is_male else rules.arrival_target_females
	var present := 0
	for animal in get_animals(game_data, rules.species_name):
		if animal.is_male == is_male:
			present += 1
	return maxi(target - present, 0)


# Primo arrivo dal branco già avvenuto (2026-11-06): da qui la selvatica non dà più punti né animali, i rimpiazzi arrivano
# da fuori (DomesticAnimalLifeService) e le visite oltre una soglia di abitanti si diradano.
static func is_domesticated(game_data: GameData, species: String) -> bool:
	return game_data.domestic_first_arrival_day.has(species)


# Regola dei rimpiazzi (2026-11-06, richiesta utente): il branco manda animali solo se sono meno della somma di
# arrival_target_* (cane: 4), oppure se sono tutti dello stesso sesso. Arrivano quelli che mancano (missing_for_arrival).
static func needs_arrivals(game_data: GameData, rules: DomesticAnimalRules) -> bool:
	var males := 0
	var females := 0
	for animal in get_animals(game_data, rules.species_name):
		if animal.is_male:
			males += 1
		else:
			females += 1
	if males + females < rules.arrival_target_males + rules.arrival_target_females:
		return true
	return (males == 0 and rules.arrival_target_males > 0) or (females == 0 and rules.arrival_target_females > 0)



# Solo gli animali liberi (2026-11-12): quelli tenuti in un edificio (building_id) non contano per arrivi, cucciolate,
# partenze e pannello dei domestici; si leggono con get_kept_animals.
static func get_animals(game_data: GameData, species: String) -> Array[DomesticAnimal]:
	var animals: Array[DomesticAnimal] = []
	for animal in game_data.domestic_animals:
		if animal.species == species and animal.building_id < 0:
			animals.append(animal)
	return animals
