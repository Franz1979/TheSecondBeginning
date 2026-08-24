class_name DifficultyCalculator
extends RefCounted

const DIFFICULTY_RULES_PATH := "res://gameplay/data/difficulty/difficulty_rules.tres"


static func get_difficulty_rules() -> DifficultyRules:
	if not ResourceLoader.exists(DIFFICULTY_RULES_PATH):
		return null
	return load(DIFFICULTY_RULES_PATH) as DifficultyRules


# Prodotto degli otto moltiplicatori — 1.0 = combinazione piu' difficile possibile con le regole
# attuali, mai normalizzato/riscalato (vedi DifficultyRules per il perche': un valore gia'
# salvato deve restare confrontabile anche se in futuro cambiano i parametri o se ne aggiungono
# altri). -1.0 = sentinella "non applicabile": world_age_mode "CLASSIC" ignora del tutto
# animal_density/population_size/exclude_hostile_start/exclude_predator_territories/
# resource_richness_preference/group_size_preference/guarantee_animal_presence (vedi
# WorldScene._populate_new_world), assegnare comunque un numero sarebbe fuorviante. Chiave
# assente nel Dictionary (specie/opzione futura non ancora tarata) -> moltiplicatore neutro 1.0,
# mai un errore.
static func compute_difficulty_ratio(
	world_age_mode: String,
	animal_density: String,
	population_size: String,
	exclude_hostile_start: bool,
	exclude_predator_territories: bool,
	resource_richness_preference: String,
	group_size_preference: String,
	guarantee_animal_presence: bool
) -> float:
	if world_age_mode == "CLASSIC":
		return -1.0

	var rules := get_difficulty_rules()
	if rules == null:
		return -1.0

	var world_age_mult: float = float(rules.world_age_multiplier.get(world_age_mode, 1.0))
	var density_mult: float = float(rules.animal_density_multiplier.get(animal_density, 1.0))
	var population_mult: float = float(rules.population_size_multiplier.get(population_size, 1.0))
	var hostile_mult: float = (
		rules.hostile_start_excluded_multiplier if exclude_hostile_start else rules.hostile_start_included_multiplier
	)
	var predator_mult: float = (
		rules.predator_territory_excluded_multiplier if exclude_predator_territories else rules.predator_territory_included_multiplier
	)
	var richness_mult: float = float(rules.resource_richness_multiplier.get(resource_richness_preference, 1.0))
	var group_size_mult: float = float(rules.group_size_multiplier.get(group_size_preference, 1.0))
	var animal_presence_mult: float = (
		rules.animal_presence_guaranteed_multiplier if guarantee_animal_presence else rules.animal_presence_not_guaranteed_multiplier
	)

	return (
		world_age_mult * density_mult * population_mult * hostile_mult
		* predator_mult * richness_mult * group_size_mult * animal_presence_mult
	)
