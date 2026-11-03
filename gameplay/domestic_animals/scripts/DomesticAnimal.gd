class_name DomesticAnimal
extends RefCounted

# Un animale domestico seguito per individuo (cane, passo 1, 2026-11-03): generico per ogni specie con
# DomesticAnimalRules.individuals_enabled. Si crea solo con DomesticAnimalService.add_animal.
# L'età non si salva: si calcola da birth_day (giorno assoluto, GameData.get_absolute_day), come per WildAnimal.

var id: int = 0
# Nome del file di DomesticAnimalRules (es. "dog").
var species: String = ""
var is_male: bool = true
var birth_day: int = 0
# Village.id del magazzino a cui è arrivato (passo 2); -1 = nessuno (cani di debug).
var village_id: int = -1


func get_age_years(absolute_day: int) -> int:
	return maxi(absolute_day - birth_day, 0) / GameData.DAYS_PER_YEAR


func to_save_data() -> Dictionary:
	return {"id": id, "species": species, "is_male": is_male, "birth_day": birth_day, "village_id": village_id}


static func from_save_data(data: Dictionary) -> DomesticAnimal:
	var animal := DomesticAnimal.new()
	animal.id = int(data.get("id", 0))
	animal.species = String(data.get("species", ""))
	animal.is_male = bool(data.get("is_male", true))
	animal.birth_day = int(data.get("birth_day", 0))
	animal.village_id = int(data.get("village_id", -1))
	return animal
