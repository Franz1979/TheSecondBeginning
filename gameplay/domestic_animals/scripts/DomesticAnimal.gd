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
# Salute, 0..1 di quella piena (passo 4): la scrive solo DomesticAnimalLifeService, il corpo ne è una copia.
var health_ratio: float = 1.0
# Macella (passo 7): ordine in lista dei lavori.
var slaughter_requested: bool = false
# Corpo nel renderer (AnimalVisualGroup.id), 0 = nessuno: mai creato o cella non viva. Mai salvato.
var body_id: int = 0
# Era nell'inquadratura al giro prima e ultimo verso per questo motivo (Time.get_ticks_msec, DomesticAnimalBodyService). Mai
# salvati.
var was_framed: bool = false
var last_framed_call_msec: int = -1
# Dietro alle persone (passo 8.3, DomesticAnimalFollowService): persona seguita (-1 nessuna), ore di gioco alla prossima
# scelta, centro dell'anello dato al corpo. Corsa di guardia in corso (DomesticAnimalGuardService). Mai salvati.
var follow_person_id: int = -1
var follow_hours_left: float = 0.0
var follow_center: Vector2 = Vector2.ZERO
var guard_running: bool = false
# A caccia con una persona (DomesticAnimalHuntService, 2026-11-07): cacciatore (-1 nessuno), centro dato al corpo, di corsa
# per raggiungerlo. Mai salvati: dopo un caricamento il cacciatore se ne riprende uno al primo fotogramma.
var hunt_person_id: int = -1
# Contro il branco in arrivo o in sosta (DomesticAnimalGuardService, 2026-11-07): gruppo affrontato (-1 nessuno), punto da
# cui è partito, punto dove si piazza, di corsa per arrivarci. Mai salvati.
var guard_confront_group_id: int = -1
var guard_post: Vector2 = Vector2.ZERO
var guard_confront_point: Vector2 = Vector2(-1.0, -1.0)
var guard_confront_running: bool = false
var hunt_center: Vector2 = Vector2(-1.0, -1.0)
var hunt_catching_up: bool = false
# Inseguimento della preda del cacciatore (passo 3): preda inseguita (-1 nessuna), ore che restano a tenerla a bada (0 =
# non la tiene), ultimo punto di corsa dato al corpo. Mai salvati.
var hunt_chase_prey_id: int = -1
var hunt_hold_hours_left: float = 0.0
var hunt_chase_point: Vector2 = Vector2(-1.0, -1.0)


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
		"macro_x": macro_coords.x, "macro_y": macro_coords.y, "x": position.x, "y": position.y, "health_ratio": health_ratio,
		"slaughter_requested": slaughter_requested}


static func from_save_data(data: Dictionary) -> DomesticAnimal:
	var animal := DomesticAnimal.new()
	animal.id = int(data.get("id", 0))
	animal.species = String(data.get("species", ""))
	animal.is_male = bool(data.get("is_male", true))
	animal.birth_day = int(data.get("birth_day", 0))
	animal.village_id = int(data.get("village_id", -1))
	animal.macro_coords = Vector2i(int(data.get("macro_x", -1)), int(data.get("macro_y", -1)))
	animal.position = Vector2(float(data.get("x", -1.0)), float(data.get("y", -1.0)))
	animal.health_ratio = float(data.get("health_ratio", 1.0))
	animal.slaughter_requested = bool(data.get("slaughter_requested", false))
	return animal
