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
# Macrocella e microcella (continua, locale alla macrocella) dove si trova (passo 3), copiata dal corpo a ogni fotogramma;
# -1 = non ancora sulla mappa: lo piazza vicino al magazzino DomesticAnimalBodyService.
var macro_coords: Vector2i = Vector2i(-1, -1)
var position: Vector2 = Vector2(-1.0, -1.0)
# Corpo nel renderer (AnimalVisualGroup.id), 0 = nessuno: mai creato o cella non viva. Mai salvato.
var body_id: int = 0
# Era nell'inquadratura al giro prima e ultimo verso per questo motivo (Time.get_ticks_msec, DomesticAnimalBodyService). Mai
# salvati.
var was_framed: bool = false
var last_framed_call_msec: int = -1


func get_age_years(absolute_day: int) -> int:
	return maxi(absolute_day - birth_day, 0) / GameData.DAYS_PER_YEAR


# Fascia d'età dalle durate della specie selvatica, come WildAnimal.get_age_band.
func get_age_band(absolute_day: int, wild_rules: AnimalRules) -> GameTypes.AgeBand:
	var age := get_age_years(absolute_day)
	if wild_rules == null or age < wild_rules.youth_duration_years:
		return GameTypes.AgeBand.YOUNG
	if age < wild_rules.youth_duration_years + wild_rules.adult_duration_years:
		return GameTypes.AgeBand.ADULT
	return GameTypes.AgeBand.OLD


func to_save_data() -> Dictionary:
	return {"id": id, "species": species, "is_male": is_male, "birth_day": birth_day, "village_id": village_id,
		"macro_x": macro_coords.x, "macro_y": macro_coords.y, "x": position.x, "y": position.y}


static func from_save_data(data: Dictionary) -> DomesticAnimal:
	var animal := DomesticAnimal.new()
	animal.id = int(data.get("id", 0))
	animal.species = String(data.get("species", ""))
	animal.is_male = bool(data.get("is_male", true))
	animal.birth_day = int(data.get("birth_day", 0))
	animal.village_id = int(data.get("village_id", -1))
	animal.macro_coords = Vector2i(int(data.get("macro_x", -1)), int(data.get("macro_y", -1)))
	animal.position = Vector2(float(data.get("x", -1.0)), float(data.get("y", -1.0)))
	return animal
