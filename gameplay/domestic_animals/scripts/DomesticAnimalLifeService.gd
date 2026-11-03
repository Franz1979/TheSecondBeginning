class_name DomesticAnimalLifeService
extends RefCounted

# Vecchiaia e salute degli animali domestici (cane, passo 4, 2026-11-03). La salute sta in DomesticAnimal.health_ratio, il
# corpo ne è una copia: ferito rallenta da solo (AnimalGroupRenderer._wounded_speed_factor). Niente malattie. Chi muore
# sparisce senza carcassa: le carcasse arrivano col passo 6.


# Ogni giorno (GameSimulation.tick_day): muore chi ha raggiunto l'età massima, gli altri guariscono un po' e il corpo segue
# la fascia d'età. Poi, per specie, cucciolate (passo 5) e il primo giorno d'autunno le partenze oltre il tetto.
static func tick_day(ctx: GameContext, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	var today := game_data.get_absolute_day()
	var species_present: Dictionary = {}
	for animal in game_data.domestic_animals.duplicate():
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null:
			continue
		if rules.max_age_years > 0 and today - animal.birth_day >= _death_age_days(animal, rules):
			_kill(game_data, animal, "vecchiaia")
			continue
		species_present[animal.species] = rules
		if rules.health_recovery_days > 0 and animal.health_ratio < 1.0:
			_set_health_ratio(animal, animal.health_ratio + 1.0 / float(rules.health_recovery_days))
		_refresh_body_age_band(animal, today)
	var is_departure_day: bool = game_data.current_day == SeasonCalculator.get_season_day_range(GameTypes.Season.AUTUMN).x
	for species: String in species_present:
		var rules: DomesticAnimalRules = species_present[species]
		var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
		_give_birth_if_season(game_data, rules, wild_rules, today)
		if is_departure_day:
			_leave_over_cap(ctx, rules, wild_rules, today, effects)


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


# Età di morte in giorni, propria di ogni animale: dipende solo dall'id, quindi resta uguale dopo un caricamento e non si salva.
static func _death_age_days(animal: DomesticAnimal, rules: DomesticAnimalRules) -> int:
	var spread := rules.max_age_variation_years * GameData.DAYS_PER_YEAR
	return rules.max_age_years * GameData.DAYS_PER_YEAR + posmod(hash(animal.id), 2 * spread + 1) - spread


# Fascia d'età cambiata: via il corpo, DomesticAnimalBodyService ne crea uno della taglia giusta dove si trovava.
static func _refresh_body_age_band(animal: DomesticAnimal, today: int) -> void:
	if animal.body_id == 0:
		return
	var body := AnimalGroupRenderer.find_live_individual(animal.body_id)
	if body != null and body.age_band != animal.get_age_band(today, DomesticAnimalCalculator.get_wild_rules(animal.species)):
		AnimalGroupRenderer.remove_live_individual(animal.body_id)
		animal.body_id = 0


# Il primo giorno della stagione delle nascite della selvatica ogni femmina adulta, se c'è un maschio adulto, fa una
# cucciolata. I cuccioli nascono dove si trova la madre.
static func _give_birth_if_season(game_data: GameData, rules: DomesticAnimalRules, wild_rules: AnimalRules, today: int) -> void:
	if wild_rules == null or game_data.current_day != SeasonCalculator.get_season_day_range(wild_rules.birth_season).x:
		return
	var animals := DomesticAnimalService.get_animals(game_data, rules.species_name)
	var has_father := false
	for animal in animals:
		if animal.is_male and animal.get_age_band(today, wild_rules) == GameTypes.AgeBand.ADULT:
			has_father = true
			break
	if not has_father:
		return
	for mother in animals:
		if mother.is_male or mother.get_age_band(today, wild_rules) != GameTypes.AgeBand.ADULT:
			continue
		var litter := randi_range(rules.litter_size_min, rules.litter_size_max)
		for i in range(litter):
			var puppy := DomesticAnimalService.add_animal(game_data, rules.species_name, randf() < 0.5, today, mother.village_id)
			if puppy != null:
				puppy.macro_coords = mother.macro_coords
				puppy.position = mother.position
		print("[DOMESTIC] %s %d: nati %d cuccioli" % [rules.species_name, mother.id, litter])


# Oltre il tetto (abitanti / inhabitants_per_animal, mai sotto min_population_cap) se ne va chi dice _pick_leaver. Un messaggio
# con quanti.
static func _leave_over_cap(ctx: GameContext, rules: DomesticAnimalRules, wild_rules: AnimalRules, today: int,
		effects: GameEffects) -> void:
	var cap := rules.min_population_cap
	if rules.inhabitants_per_animal > 0:
		cap = maxi(ctx.individuals.size() / rules.inhabitants_per_animal, cap)
	var animals := DomesticAnimalService.get_animals(ctx.game_data, rules.species_name)
	var left := 0
	while animals.size() > cap:
		var leaver := _pick_leaver(animals, rules, wild_rules, today)
		if leaver == null:
			break
		animals.erase(leaver)
		_remove(ctx.game_data, leaver)
		left += 1
	if left == 0:
		return
	print("[DOMESTIC] %s: se ne vanno in %d, restano %d (tetto %d)" % [rules.species_name, left, animals.size(), cap])
	if effects != null:
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
			GameContext.tr_text("notification_domestic_left_%s" % rules.species_name).format({"count": left}))


# Prima i giovani più grandi, poi i più anziani tra gli altri; restano sempre gli adulti minimi di ciascun sesso. null = nessuno.
static func _pick_leaver(animals: Array[DomesticAnimal], rules: DomesticAnimalRules, wild_rules: AnimalRules, today: int) -> DomesticAnimal:
	var adult_males := 0
	var adult_females := 0
	for animal in animals:
		if animal.get_age_band(today, wild_rules) == GameTypes.AgeBand.ADULT:
			if animal.is_male:
				adult_males += 1
			else:
				adult_females += 1
	var leaver: DomesticAnimal = null
	var leaver_is_young := false
	for animal in animals:
		var band := animal.get_age_band(today, wild_rules)
		if band == GameTypes.AgeBand.ADULT \
				and (adult_males <= rules.min_adult_males_kept if animal.is_male else adult_females <= rules.min_adult_females_kept):
			continue
		var is_young := band == GameTypes.AgeBand.YOUNG
		if leaver == null or (is_young and not leaver_is_young) \
				or (is_young == leaver_is_young and animal.birth_day < leaver.birth_day):
			leaver = animal
			leaver_is_young = is_young
	return leaver


static func _kill(game_data: GameData, animal: DomesticAnimal, reason: String) -> void:
	_remove(game_data, animal)
	print("[DOMESTIC] %s %d morto: %s" % [animal.species, animal.id, reason])


static func _remove(game_data: GameData, animal: DomesticAnimal) -> void:
	if animal.body_id != 0:
		AnimalGroupRenderer.remove_live_individual(animal.body_id)
	game_data.domestic_animals.erase(animal)
