class_name DomesticAnimalLifeService
extends RefCounted

# Vecchiaia e salute degli animali domestici (cane, passo 4, 2026-11-03). La salute sta in DomesticAnimal.health_ratio, il
# corpo ne è una copia: ferito rallenta da solo (AnimalGroupRenderer._wounded_speed_factor). Niente malattie. Chi muore
# lascia dov'era una carcassa che marcisce e non si macella (passo 6); chi parte in autunno no.


# Ogni giorno (GameSimulation.tick_day): muore chi ha raggiunto l'età massima, gli altri guariscono un po' e il corpo segue
# la fascia d'età. Poi, per specie, cucciolate (passo 5) e il primo giorno d'autunno le partenze oltre il tetto.
static func tick_day(ctx: GameContext, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	var today := game_data.get_absolute_day()
	# Deperimento del cibo nelle mangiatoie (2026-11-16), prima del pasto.
	AnimalFeederService.advance_decay_day(ctx.world)
	var species_present: Dictionary = {}
	# Animali tenuti negli edifici, ancora vivi oggi: building_id -> Array[DomesticAnimal] (cucciolate in cattività).
	var kept_by_building: Dictionary = {}
	for animal in game_data.domestic_animals.duplicate():
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null:
			continue
		if rules.max_age_years > 0 and today - animal.birth_day >= _death_age_days(animal, rules):
			_kill(game_data, animal, "vecchiaia")
			continue
		# Selvatico in cattività (2026-11-12, richiesta utente): vive dalla cattura la vita da domestico × punti / soglia,
		# ricalcolata ogni giorno (più il villaggio impara, più durano). Muore senza carcassa: non si mangia.
		if animal.is_wild and animal.captured_day >= 0 and today - animal.captured_day >= captivity_life_days(game_data, rules):
			_kill(game_data, animal, "cattività dopo %d giorni (%d/%d punti)" % [today - animal.captured_day,
				DomesticationPointsService.get_points(game_data, rules.species_name), rules.domestication_points_required])
			continue
		# Tenuti in un edificio (2026-11-12): invecchiano, guariscono e fanno cucciolate nell'edificio; niente partenze.
		if animal.building_id >= 0:
			if rules.health_recovery_days > 0 and animal.health_ratio < 1.0:
				_set_health_ratio(animal, animal.health_ratio + 1.0 / float(rules.health_recovery_days))
			if not kept_by_building.has(animal.building_id):
				kept_by_building[animal.building_id] = []
			kept_by_building[animal.building_id].append(animal)
			continue
		species_present[animal.species] = rules
		if rules.health_recovery_days > 0 and animal.health_ratio < 1.0:
			_set_health_ratio(animal, animal.health_ratio + 1.0 / float(rules.health_recovery_days))
		_refresh_body_age_band(animal, today)
	# Pasto dalla mangiatoia (2026-11-14, fame): prima delle cucciolate; chi è oltre i giorni senza cibo muore.
	for building_id: int in kept_by_building:
		var building := WarehouseManagerService.find_building(ctx.world, building_id)
		var alive: Array = []
		var starved := AnimalFeederService.feed_day(game_data, building, kept_by_building[building_id])
		for animal: DomesticAnimal in kept_by_building[building_id]:
			if starved.has(animal):
				_kill(game_data, animal, "fame (%d giorni senza cibo)" % animal.days_without_food)
				var message := GameContext.tr_text("notification_kept_animal_starved").format({
					"animal": KeptAnimalService.display_name(animal),
					"building": building.get_display_name() if building != null else "",
				})
				# Punti tolti (2026-11-14): solo prima dell'addomesticazione, mai sotto 0 (add_points).
				var animal_rules := DomesticAnimalCalculator.get_rules(animal.species)
				if animal_rules != null and animal_rules.starvation_point_loss > 0 \
						and not DomesticAnimalService.is_domesticated(game_data, animal.species):
					DomesticationPointsService.add_points(game_data, ctx.folk, animal.species, -animal_rules.starvation_point_loss, effects,
						"fame: #%d nell'edificio %d, %d giorni senza cibo, mangiatoia %.0f calorie" % [animal.id, building_id,
							animal.days_without_food, building.feeder_calories if building != null else -1.0])
					message += " " + GameContext.tr_text("notification_kept_animal_starved_points").format({"points": animal_rules.starvation_point_loss})
				if effects != null:
					effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS, message)
			else:
				alive.append(animal)
		kept_by_building[building_id] = alive
	# Lettiera (2026-11-17, BeddingService): ogni animale vivo dentro ne consuma la sua parte; avviso il giorno che resta vuota.
	for building_id: int in kept_by_building:
		var bedding_building := WarehouseManagerService.find_building(ctx.world, building_id)
		if BeddingService.consume_day(bedding_building, kept_by_building[building_id]) and effects != null:
			effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
				GameContext.tr_text("notification_bedding_empty").format({"building": bedding_building.get_display_name()}))
		# Letame (2026-11-17, ManureService): con o senza lettiera; avviso il giorno che arriva al massimo.
		if ManureService.produce_day(bedding_building, kept_by_building[building_id]) and effects != null:
			effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
				GameContext.tr_text("notification_manure_full").format({"building": bedding_building.get_display_name()}))
		# Edificio sporco (2026-11-17): lettiera vuota o letame al massimo, morti di malattia.
		kept_by_building[building_id] = _dirty_building_deaths(ctx, bedding_building, kept_by_building[building_id], effects)
		# Prodotti da vivi (2026-11-17, LiveProductService): uova; avviso il giorno che un prodotto arriva al massimo.
		for product in LiveProductService.produce_day(ctx.game_data, bedding_building, kept_by_building[building_id]):
			if effects != null:
				effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
					GameContext.tr_text("notification_live_product_full").format({"building": bedding_building.get_display_name(),
						"product": GameContext.tr_text("carried_resource_tooltip_" + product)}))
	for building_id: int in kept_by_building:
		if (kept_by_building[building_id] as Array).is_empty():
			continue
		_give_birth_in_building(ctx, building_id, kept_by_building[building_id], today, effects)
	# Oltre la capienza (2026-11-14, pezzo 2b): con una soglia si aspetta, senza scappano subito.
	if ctx.world != null:
		for building in ctx.world.buildings:
			if KeptAnimalService.capacity(building) > 0:
				_check_over_capacity(ctx, building, today, effects)
	# Domestici nella tettoia senza posto in un edificio d'allevamento: da macellare (2026-11-16).
	DomesticTransferService.plan_no_room_slaughter(ctx, effects)
	var is_departure_day: bool = game_data.current_day == SeasonCalculator.get_season_day_range(GameTypes.Season.AUTUMN).x
	for species: String in species_present:
		var rules: DomesticAnimalRules = species_present[species]
		var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
		_give_birth_if_season(game_data, rules, wild_rules, today)
		if is_departure_day:
			_leave_over_cap(ctx, rules, wild_rules, today, effects)
	# Rimpiazzi da fuori (2026-11-06): per ogni specie attiva, anche senza più nessun animale.
	for species in DomesticAnimalCalculator.list_species():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules != null and rules.individuals_enabled:
			_tick_stray_arrival(ctx, rules, today, effects)


# Rimpiazzi da fuori (2026-11-06, richiesta utente): solo dopo il primo arrivo dal branco. Quando la regola
# DomesticAnimalService.needs_arrivals chiede animali parte l'attesa (stray_arrival_wait_years); alla fine, se servono ancora,
# arriva un giovane adulto del sesso che manca di più, vicino al magazzino, con un messaggio. Se ne servono altri, la volta
# dopo riparte l'attesa. Salvataggi di prima: con animali presenti la specie conta come già addomesticata da oggi.
static func _tick_stray_arrival(ctx: GameContext, rules: DomesticAnimalRules, today: int, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	var species := rules.species_name
	if not DomesticAnimalService.is_domesticated(game_data, species):
		if DomesticAnimalService.get_animals(game_data, species).is_empty():
			return
		game_data.domestic_first_arrival_day[species] = today
	if rules.stray_arrival_wait_years <= 0 or not DomesticAnimalService.needs_arrivals(game_data, rules):
		game_data.domestic_stray_due_day.erase(species)
		return
	if not game_data.domestic_stray_due_day.has(species):
		game_data.domestic_stray_due_day[species] = today + rules.stray_arrival_wait_years * GameData.DAYS_PER_YEAR
		DebugLogging.print_event("[DOMESTIC] %s: sotto la soglia, un rimpiazzo arriverà il giorno %d" % [species, game_data.domestic_stray_due_day[species]])
		return
	if today < int(game_data.domestic_stray_due_day[species]):
		return
	var storage := WildAnimalGroupService.find_anchor_storage(ctx.world)
	var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
	if storage == null or wild_rules == null:
		return
	game_data.domestic_stray_due_day.erase(species)
	var missing_males := DomesticAnimalService.missing_for_arrival(game_data, rules, true)
	var missing_females := DomesticAnimalService.missing_for_arrival(game_data, rules, false)
	var is_male := missing_males > missing_females or (missing_males == missing_females and randf() < 0.5)
	var birth_day := today - wild_rules.youth_duration_years * GameData.DAYS_PER_YEAR
	if DomesticAnimalService.add_animal(game_data, species, is_male, birth_day, storage.village_id) == null:
		return
	DebugLogging.print_event("[DOMESTIC] %s: arrivato da fuori un %s" % [species, "maschio" if is_male else "femmina"])
	if effects != null:
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
			GameContext.tr_text("notification_domestic_stray_%s" % species))


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


# Una persona morta di fame (GameScene, individual_died): il villaggio soffre e lo soffrono anche gli animali. Raggiunte
# starved_people_per_death morti entro starved_people_window_days muore un adulto a caso, con l'avviso, e il conto riparte.
# Non è una riserva di cibo: la carcassa marcisce. Senza adulti nessuna morte e nessun avviso.
static func on_person_starved(game_data: GameData, effects: GameEffects) -> void:
	var today := game_data.get_absolute_day()
	var species_done: Dictionary = {}
	for animal in game_data.domestic_animals.duplicate():
		if species_done.has(animal.species):
			continue
		species_done[animal.species] = true
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null or rules.starved_people_per_death <= 0:
			continue
		var days: Array = []
		for day in game_data.domestic_starvation_days.get(animal.species, []):
			if today - int(day) <= rules.starved_people_window_days:
				days.append(day)
		days.append(today)
		if days.size() >= rules.starved_people_per_death and _starve_one_adult(game_data, rules, today, effects):
			days.clear()
		game_data.domestic_starvation_days[animal.species] = days


static func _starve_one_adult(game_data: GameData, rules: DomesticAnimalRules, today: int, effects: GameEffects) -> bool:
	var wild_rules := DomesticAnimalCalculator.get_wild_rules(rules.species_name)
	var adults: Array[DomesticAnimal] = []
	for animal in DomesticAnimalService.get_animals(game_data, rules.species_name):
		if animal.get_age_band(today, wild_rules) == GameTypes.AgeBand.ADULT:
			adults.append(animal)
	if adults.is_empty():
		return false
	_kill(game_data, adults[randi() % adults.size()], "fame")
	if effects != null:
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
			GameContext.tr_text("notification_domestic_starved_%s" % rules.species_name))
	return true


# Giorni di vita dalla cattura di un selvatico in cattività: età massima da domestico × punti / soglia (senza minimo).
static func captivity_life_days(game_data: GameData, rules: DomesticAnimalRules) -> int:
	if rules.max_age_years <= 0 or rules.domestication_points_required <= 0:
		return 1 << 30
	var progress := clampf(float(DomesticationPointsService.get_points(game_data, rules.species_name))
		/ float(rules.domestication_points_required), 0.0, 1.0)
	return int(float(rules.max_age_years * GameData.DAYS_PER_YEAR) * progress)


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
		DebugLogging.print_event("[DOMESTIC] %s %d: nati %d cuccioli" % [rules.species_name, mother.id, litter])


# Cucciolate in cattività (2026-11-12, richiesta utente): il primo giorno della stagione delle nascite della selvatica, in
# ogni edificio con almeno un maschio adulto, ogni femmina adulta partorisce. Una specie per edificio.
# - Specie non ancora addomesticata: p = punti / soglia. La femmina partorisce con probabilità p; se partorisce fa almeno un
#   piccolo, e ogni altro fino al tetto della madre selvatica (captive_wild_litter_max, 2026-11-16) arriva con probabilità
#   p. Il piccolo è selvatico e vive come un catturato (captivity_life_days, da oggi).
# - Specie addomesticata: piccoli domestici. Madre domestica: partorisce sempre, piccoli a caso tra litter_size_min e
#   litter_size_max. Madre selvatica (catturata, 2026-11-16): partorisce sempre, da 1 a captive_wild_litter_max.
# Edificio pieno: chi non ci sta nasce e muore subito, senza carcassa e fuori dalle statistiche. Ogni nato vivo conta tra
# i "nati" e dà captivity_birth_points punti addomesticazione.
static func _give_birth_in_building(ctx: GameContext, building_id: int, animals: Array, today: int, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	var species: String = animals[0].species
	var rules := DomesticAnimalCalculator.get_rules(species)
	var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
	if rules == null or wild_rules == null or rules.litter_size_max <= 0 \
			or game_data.current_day != SeasonCalculator.get_season_day_range(wild_rules.birth_season).x:
		return
	var has_father := false
	for animal: DomesticAnimal in animals:
		if animal.is_male and animal.get_age_band(today, wild_rules) == GameTypes.AgeBand.ADULT:
			has_father = true
			break
	if not has_father:
		return
	var building := WarehouseManagerService.find_building(ctx.world, building_id)
	var room := KeptAnimalService.capacity(building) - animals.size()
	var is_wild := not DomesticAnimalService.is_domesticated(game_data, species)
	var progress := DomesticationPointsService.get_progress(game_data, species) if is_wild else 1.0
	# Soglia "Macella oltre" (2026-11-14, pezzo 2b): i piccoli entrano anche oltre la capienza, poi c'è la scadenza.
	var enter_over := KeptAnimalService.has_slaughter_threshold(game_data, building, species)
	var born := 0
	var escaped := 0
	# Lettiera (2026-11-17, BeddingService): i piccoli nascono tutti, ognuno muore appena nato con questa probabilità.
	var bedding_death_chance := BeddingService.newborn_death_chance(building, rules)
	var bedding_dead := 0
	var reserved := KeptAnimalService.reservations(ctx.individuals)
	for mother: DomesticAnimal in animals:
		if mother.is_male or mother.get_age_band(today, wild_rules) != GameTypes.AgeBand.ADULT:
			continue
		var litter := 0
		# Tetto della madre selvatica in cattività (2026-11-16, richiesta utente).
		var wild_max := rules.litter_size_max
		if rules.captive_wild_litter_max > 0:
			wild_max = mini(rules.captive_wild_litter_max, rules.litter_size_max)
		if is_wild:
			if randf() >= progress:
				continue
			litter = 1
			for i in range(wild_max - 1):
				if randf() < progress:
					litter += 1
		elif mother.is_wild:
			litter = randi_range(1, maxi(wild_max, 1))
		else:
			litter = randi_range(maxi(rules.litter_size_min, 1), rules.litter_size_max)
		for i in range(litter):
			# Morto appena nato per la lettiera: conta tra i nati e i morti, non occupa posto, nessuna carcassa.
			if bedding_death_chance > 0.0 and randf() < bedding_death_chance:
				bedding_dead += 1
				KeptAnimalService.count_stat(game_data, species, "born")
				KeptAnimalService.count_stat(game_data, species, "died")
				continue
			# Piena: prima un'altra tettoia della specie con posto (spostamento istantaneo, 2026-11-14), poi oltre la
			# capienza con una soglia, altrimenti scappa.
			var target_id := building_id
			if room <= 0:
				var other := KeptAnimalService.find_building_with_room(game_data, ctx.world, species,
					Vector2i(building.macro_x, building.macro_y) if building != null else Vector2i.ZERO, reserved, building)
				if other != null:
					target_id = other.id
				elif not enter_over:
					escaped += 1
					continue
			var young := DomesticAnimalService.add_kept_animal(game_data, species, randf() < 0.5, today, target_id, is_wild)
			if young == null:
				continue
			if is_wild:
				young.captured_day = today
			if target_id == building_id:
				room -= 1
			born += 1
			KeptAnimalService.count_stat(game_data, species, "born")
	if BeddingService.capacity(building) > 0:
		if bedding_dead > 0 and effects != null:
			effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
				GameContext.tr_text("notification_bedding_newborns_dead").format({
					"building": building.get_display_name(), "dead": bedding_dead, "total": born + escaped + bedding_dead,
					"empty": building.bedding_days_empty, "days": building.bedding_days_with_animals,
				}))
		DebugLogging.print_event("[BEDDING] Edificio %d: nascite, %d morti per la lettiera (rischio %.2f, vuota %d/%d giorni, oggi %.1f paglia)" % [
			building_id, bedding_dead, bedding_death_chance, building.bedding_days_empty, building.bedding_days_with_animals,
			building.bedding_straw])
		BeddingService.reset_year(building)
	if born == 0 and escaped == 0:
		return
	# Tettoia piena (2026-11-14, richiesta utente): i piccoli in più scappano nella mandria selvatica d'origine della
	# macrocella (anche da addomesticati: si rinselvatichiscono); contano tra i nati, ma senza i punti della nascita.
	var joined := 0
	if escaped > 0:
		for i in range(escaped):
			KeptAnimalService.count_stat(game_data, species, "born")
		if building != null:
			joined = WildFaunaService.release_animals(ctx.world, game_data, rules.wild_species_name,
				Vector2i(building.macro_x, building.macro_y), escaped)
		var message := GameContext.tr_text("notification_kept_young_escaped").format({
			"building": building.get_display_name() if building != null else "",
			"count": escaped,
			"species": GameContext.tr_text("animal_species_" + rules.wild_species_name),
		})
		message += _escape_points(ctx, rules, escaped, effects)
		if effects != null:
			effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS, message)
	DebugLogging.print_event("[DOMESTIC] %s nell'edificio %d: nati %d, scappati %d (edificio pieno, %d nella mandria), progresso %.2f" % [species,
		building_id, born, escaped, joined, progress])
	if born > 0 and rules.captivity_birth_points > 0:
		DomesticationPointsService.add_points(game_data, ctx.folk, species, born * rules.captivity_birth_points, effects,
			"nascite: %d nell'edificio %d" % [born, building_id])


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
	DebugLogging.print_event("[DOMESTIC] %s: se ne vanno in %d, restano %d (tetto %d)" % [rules.species_name, left, animals.size(), cap])
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
	if animal.building_id >= 0:
		KeptAnimalService.count_stat(game_data, animal.species, "died")
	# Mai stato sulla mappa (posizione -1): nessun punto dove lasciare la carcassa.
	if animal.macro_coords.x >= 0 and animal.position.x >= 0.0:
		var band := animal.get_age_band(game_data.get_absolute_day(), DomesticAnimalCalculator.get_wild_rules(animal.species))
		GroundPileService.drop_carcass(game_data, animal.macro_coords, animal.position, animal.species, int(band), null, false)
	DebugLogging.print_event("[DOMESTIC] %s %d morto: %s" % [animal.species, animal.id, reason])


# Tettoia oltre la capienza (2026-11-14, pezzo 2b): con una soglia "Macella oltre" parte il conto di
# OVER_CAPACITY_GRACE_DAYS e, se allo scadere è ancora piena, scappano i più giovani in più; senza soglia (es. tolta mentre
# era piena) scappano subito. Tornata dentro la capienza, il conto si azzera.
static func _check_over_capacity(ctx: GameContext, building: Building, today: int, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	var animals := DomesticAnimalService.get_kept_animals(game_data, building.id)
	var extra := animals.size() - KeptAnimalService.capacity(building)
	if extra <= 0:
		building.over_capacity_since_day = -1
		return
	if KeptAnimalService.has_slaughter_threshold(game_data, building, animals[0].species):
		if building.over_capacity_since_day < 0:
			building.over_capacity_since_day = today
			return
		if today - building.over_capacity_since_day < KeptAnimalService.OVER_CAPACITY_GRACE_DAYS:
			return
	building.over_capacity_since_day = -1
	_escape_youngest(ctx, building, animals, extra, effects)


# I `count` più giovani di `animals` lasciano la tettoia e vanno nella mandria selvatica d'origine (WildFaunaService.
# release_animals, ciascuno nella sua fascia d'età); un messaggio. Nessuna statistica e nessun punto.
static func _escape_youngest(ctx: GameContext, building: Building, animals: Array[DomesticAnimal], count: int,
		effects: GameEffects) -> void:
	var game_data := ctx.game_data
	var species := animals[0].species
	var rules := DomesticAnimalCalculator.get_rules(species)
	var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
	if rules == null:
		return
	# Prima i più giovani senza ordine di macellazione, poi (2026-11-14, richiesta utente: oltre la capienza si scappa
	# comunque) anche quelli con l'ordine, i più giovani prima; chi andava a macellarli trova l'animale sparito.
	var sorted: Array[DomesticAnimal] = animals.duplicate()
	sorted.sort_custom(func(a: DomesticAnimal, b: DomesticAnimal) -> bool:
		if a.slaughter_requested != b.slaughter_requested:
			return not a.slaughter_requested
		return a.birth_day > b.birth_day if a.birth_day != b.birth_day else a.id > b.id)
	var by_band: Dictionary = {}
	var today := game_data.get_absolute_day()
	var reserved := KeptAnimalService.reservations(ctx.individuals)
	var moved := 0
	var escaped := 0
	for i in range(mini(count, sorted.size())):
		var animal: DomesticAnimal = sorted[i]
		# Prima un'altra tettoia della specie con posto (spostamento istantaneo, senza messaggio).
		var other := KeptAnimalService.find_building_with_room(game_data, ctx.world, species,
			Vector2i(building.macro_x, building.macro_y), reserved, building)
		if other != null:
			animal.building_id = other.id
			moved += 1
			continue
		var band := int(animal.get_age_band(today, wild_rules)) if wild_rules != null else int(GameTypes.AgeBand.YOUNG)
		by_band[band] = int(by_band.get(band, 0)) + 1
		_remove(game_data, animal)
		escaped += 1
	if moved > 0:
		DebugLogging.print_event("[DOMESTIC] %s nell'edificio %d: troppo piena, spostati %d in altre tettoie" % [species, building.id, moved])
	if escaped == 0:
		return
	var joined := 0
	for band: int in by_band:
		joined += WildFaunaService.release_animals(ctx.world, game_data, rules.wild_species_name,
			Vector2i(building.macro_x, building.macro_y), int(by_band[band]), band)
	DebugLogging.print_event("[DOMESTIC] %s nell'edificio %d: troppo piena, scappati i %d più giovani (%d nella mandria)" % [species,
		building.id, escaped, joined])
	var message := GameContext.tr_text("notification_kept_animals_escaped").format({
		"building": building.get_display_name(),
		"count": escaped,
		"species": GameContext.tr_text("animal_species_" + rules.wild_species_name),
	})
	message += _escape_points(ctx, rules, escaped, effects)
	if effects != null:
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS, message)


# Punti persi per `count` animali scappati (2026-11-14, richiesta utente: −1 ciascuno, DomesticAnimalRules.escape_point_loss),
# solo prima dell'addomesticazione e mai sotto 0. Ritorna il pezzo da aggiungere al messaggio ("" se nessun punto).
static func _escape_points(ctx: GameContext, rules: DomesticAnimalRules, count: int, effects: GameEffects) -> String:
	var loss := rules.escape_point_loss * count
	if loss <= 0 or DomesticAnimalService.is_domesticated(ctx.game_data, rules.species_name):
		return ""
	DomesticationPointsService.add_points(ctx.game_data, ctx.folk, rules.species_name, -loss, effects,
		"fuga: %d da un edificio troppo pieno" % count)
	return " " + GameContext.tr_text("notification_kept_animal_starved_points").format({"points": loss})


# Malattie dell'edificio sporco (2026-11-17, richiesta utente — generico per tutte le specie): un solo controllo per
# edificio; se la lettiera è vuota o il letame è al massimo, ogni animale dentro muore con death_chance_without_bedding /
# death_chance_full_manure della sua specie (sommate). Senza carcassa: un animale malato non si mangia. Un avviso al giorno
# per edificio. Ritorna gli animali rimasti vivi.
static func _dirty_building_deaths(ctx: GameContext, building: Building, animals: Array, effects: GameEffects) -> Array:
	if building == null or animals.is_empty():
		return animals
	var bedding_empty := BeddingService.capacity(building) > 0 and BeddingService.is_empty(building)
	var manure_full := ManureService.capacity(building) > 0 and ManureService.stored(building) >= ManureService.capacity(building)
	if not bedding_empty and not manure_full:
		return animals
	var alive: Array = []
	var dead := 0
	for animal: DomesticAnimal in animals:
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		var chance := 0.0
		if rules != null:
			if bedding_empty:
				chance += rules.death_chance_without_bedding
			if manure_full:
				chance += rules.death_chance_full_manure
		if chance > 0.0 and randf() < chance:
			_remove(ctx.game_data, animal)
			KeptAnimalService.count_stat(ctx.game_data, animal.species, "died")
			DebugLogging.print_event("[DOMESTIC] %s %d morto di malattia nell'edificio %d (lettiera vuota %s, letame al massimo %s)" % [
				animal.species, animal.id, building.id, bedding_empty, manure_full])
			dead += 1
		else:
			alive.append(animal)
	if dead > 0 and effects != null:
		var reasons: Array[String] = []
		if bedding_empty:
			reasons.append(GameContext.tr_text("dirty_reason_bedding_empty"))
		if manure_full:
			reasons.append(GameContext.tr_text("dirty_reason_manure_full"))
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
			GameContext.tr_text("notification_dirty_building_deaths").format({
				"building": building.get_display_name(), "count": dead, "reasons": ", ".join(reasons),
			}))
	return alive


static func _remove(game_data: GameData, animal: DomesticAnimal) -> void:
	if animal.body_id != 0:
		AnimalGroupRenderer.remove_live_individual(animal.body_id)
	game_data.domestic_animals.erase(animal)
