class_name WildAnimalGroup
extends RefCounted

# Gruppo di animali selvatici seguiti uno per uno (2026-10-26, richiesta utente; rinominato da "visitatori" il 2026-10-27): un'istanza simulata, sempre la stessa,
# indipendente dalla fauna selvatica della mappa — un elemento di gioco garantito, non realismo. Primo uso: il branco
# di lupi (species "wolf", regole in gameplay/wild_animals/data/groups/wolf_group.tres). Nascite, morti e partenze in
# WildAnimalGroupService.tick_day; il comportamento (visite, punti, attacchi) arriverà in servizi propri per specie.

var id: int = 0
# Nome del file di WildAnimalGroupRules (es. "wolf").
var species: String = ""
var animals: Array[WildAnimal] = []
var next_animal_id: int = 1
# Coppia riproduttrice (id dei WildAnimal, -1 se manca: la rimpiazza WildAnimalGroupService.tick_day).
var breeding_male_id: int = -1
var breeding_female_id: int = -1
# Anno (GameData.year) dell'ultima cucciolata, per non ripeterla nella stessa stagione dopo un caricamento.
var last_litter_year: int = -1
# Punti addomesticazione non ancora interi (lupi L3, 2026-10-30): le visite danno anche mezzi punti per animale, i punti
# della specie domestica sono interi — la parte decimale aspetta qui la visita successiva (WildAnimalVisitService).
var pending_domestication_points: float = 0.0
# Diffidenza (lupi L6.1, 2026-10-30, richiesta utente): quante volte il branco è stato scacciato in gruppo e giorno
# assoluto (GameData.get_absolute_day) dell'ultima cacciata, -1 mai. Per ora solo annotati: li useranno le visite
# spontanee (L2) per diradare le visite.
var driven_off_count: int = 0
var last_driven_off_day: int = -1


func find_animal(animal_id: int) -> WildAnimal:
	for animal in animals:
		if animal.id == animal_id:
			return animal
	return null


func to_save_data() -> Dictionary:
	var saved_animals: Array = []
	for animal in animals:
		saved_animals.append(animal.to_save_data())
	return {"id": id, "species": species, "animals": saved_animals, "next_animal_id": next_animal_id,
		"breeding_male_id": breeding_male_id, "breeding_female_id": breeding_female_id,
		"last_litter_year": last_litter_year, "pending_domestication_points": pending_domestication_points,
		"driven_off_count": driven_off_count, "last_driven_off_day": last_driven_off_day}


static func from_save_data(data: Dictionary) -> WildAnimalGroup:
	var group := WildAnimalGroup.new()
	group.id = int(data.get("id", 0))
	group.species = String(data.get("species", ""))
	group.next_animal_id = int(data.get("next_animal_id", 1))
	group.breeding_male_id = int(data.get("breeding_male_id", -1))
	group.breeding_female_id = int(data.get("breeding_female_id", -1))
	group.last_litter_year = int(data.get("last_litter_year", -1))
	group.pending_domestication_points = float(data.get("pending_domestication_points", 0.0))
	group.driven_off_count = int(data.get("driven_off_count", 0))
	group.last_driven_off_day = int(data.get("last_driven_off_day", -1))
	for saved_animal in data.get("animals", []):
		group.animals.append(WildAnimal.from_save_data(saved_animal))
	return group
