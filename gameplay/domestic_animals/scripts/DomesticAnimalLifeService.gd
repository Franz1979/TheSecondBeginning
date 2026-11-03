class_name DomesticAnimalLifeService
extends RefCounted

# Vecchiaia e salute degli animali domestici (cane, passo 4, 2026-11-03). La salute sta in DomesticAnimal.health_ratio, il
# corpo ne è una copia: ferito rallenta da solo (AnimalGroupRenderer._wounded_speed_factor). Niente malattie. Chi muore
# sparisce senza carcassa: le carcasse arrivano col passo 6.


# Ogni giorno (GameSimulation.tick_day): muore chi ha raggiunto l'età massima, gli altri guariscono un po'.
static func tick_day(game_data: GameData) -> void:
	var today := game_data.get_absolute_day()
	for animal in game_data.domestic_animals.duplicate():
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null:
			continue
		if rules.max_age_years > 0 and animal.get_age_years(today) >= rules.max_age_years:
			_kill(game_data, animal, "vecchiaia")
		elif rules.health_recovery_days > 0 and animal.health_ratio < 1.0:
			_set_health_ratio(animal, animal.health_ratio + 1.0 / float(rules.health_recovery_days))


# Toglie una parte della salute piena (0..1): a zero l'animale muore.
static func wound(game_data: GameData, animal: DomesticAnimal, ratio_lost: float) -> void:
	_set_health_ratio(animal, animal.health_ratio - ratio_lost)
	if animal.health_ratio <= 0.0:
		_kill(game_data, animal, "ferite")


static func _set_health_ratio(animal: DomesticAnimal, ratio: float) -> void:
	animal.health_ratio = clampf(ratio, 0.0, 1.0)
	if animal.body_id != 0:
		var body := AnimalGroupRenderer.find_live_individual(animal.body_id)
		if body != null:
			body.health = AnimalGroupRenderer.get_live_max_health(animal.body_id) * animal.health_ratio


static func _kill(game_data: GameData, animal: DomesticAnimal, reason: String) -> void:
	if animal.body_id != 0:
		AnimalGroupRenderer.remove_live_individual(animal.body_id)
	game_data.domestic_animals.erase(animal)
	print("[DOMESTIC] %s %d morto: %s" % [animal.species, animal.id, reason])
