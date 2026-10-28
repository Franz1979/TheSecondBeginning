class_name WildAnimal
extends RefCounted

# Un animale selvatico seguito per individuo, membro di un WildAnimalGroup (2026-10-26, richiesta utente — primo uso: il branco di lupi della
# fossa, vedi WildAnimalGroup). Dati simulati ma coerenti, non un individuo della fauna selvatica (PopulationGroup).
# L'età non si salva: si calcola da birth_day (giorno assoluto, GameData.get_absolute_day), come per gli umani.

var id: int = 0
var is_male: bool = true
var birth_day: int = 0
# 0..100, propria di ogni animale (non del gruppo): deciderà il rischio di attacco.
var aggression: float = 100.0


func get_age_years(absolute_day: int) -> int:
	return maxi(absolute_day - birth_day, 0) / GameData.DAYS_PER_YEAR


# Fascia d'età dalle durate della specie selvatica (AnimalRules.youth/adult_duration_years).
func get_age_band(absolute_day: int, wild_rules: AnimalRules) -> GameTypes.AgeBand:
	var age := get_age_years(absolute_day)
	if wild_rules == null or age < wild_rules.youth_duration_years:
		return GameTypes.AgeBand.YOUNG
	if age < wild_rules.youth_duration_years + wild_rules.adult_duration_years:
		return GameTypes.AgeBand.ADULT
	return GameTypes.AgeBand.OLD


func to_save_data() -> Dictionary:
	return {"id": id, "is_male": is_male, "birth_day": birth_day, "aggression": aggression}


static func from_save_data(data: Dictionary) -> WildAnimal:
	var animal := WildAnimal.new()
	animal.id = int(data.get("id", 0))
	animal.is_male = bool(data.get("is_male", true))
	animal.birth_day = int(data.get("birth_day", 0))
	animal.aggression = float(data.get("aggression", 100.0))
	return animal
