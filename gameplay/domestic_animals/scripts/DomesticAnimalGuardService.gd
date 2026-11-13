class_name DomesticAnimalGuardService
extends RefCounted

# Guardia degli animali domestici contro i branchi in visita (cane, passi 8.1 e 8.2, 2026-11-06, richiesta utente).
# Stateless. Fanno la guardia gli animali usciti dalla giovinezza (fascia ADULT o OLD della selvatica), col corpo sulla
# mappa, nella macrocella della visita, di una specie con guard_alarm_radius > 0 (guard_dogs). Ognuno:
#   - abbaia (bark_emitter) quando un animale del branco è entro guard_alarm_radius, e di nuovo ogni
#     guard_bark_interval_hours finché il branco resta a portata;
#   - è un punto mobile da cui il branco sta alla larga, come il focolare: repulsione in sosta di raggio
#     guard_keep_away_reaction (reaction_points della visita) e zona sicura di raggio guard_keep_away_radius (safe_points:
#     lì non si attacca, la carica non entra, chi scappa ci può correre);
#   - conta guard_defense_strength nella difesa del tiro d'attacco se sta entro guard_help_radius da chi è notato
#     (defense_near);
#   - alla carica corre contro il branco se sta entro guard_help_radius da chi è caricato (start_run, tutti, senza tetto),
#     di corsa verso il presente più vicino fermandosi a DangerProfile.drive_off_stop_distance; arrivato (entro
#     WildAnimalVisitService.DRIVE_OFF_GIVE_UP_DISTANCE da un presente) vale come un aiutante della cacciata che copre
#     guard_threats_per_dog animali del branco (arrived_support). Finita la carica torna al magazzino (end_run);
#   - in arrivo e in sosta va incontro al branco e si piazza tra i lupi e il punto da cui è partito (_update_confront,
#     2026-11-07), finché il branco resta a portata; niente morsi. A caccia (DomesticAnimalHuntService) non lo fa.

# Abbaio d'allarme: Callable(DomesticAnimal), impostata da GameScene (funzione della scena, stabile).
static var bark_emitter: Callable = Callable()
# Tra due nuovi punti dati a un cane che corre, se il presente più vicino si è spostato di più (microcelle).
const RUN_REPLAN_DISTANCE: float = 1.5


# Animali di guardia nella macrocella `macro_coords` (vedi il commento in testa).
static func guard_dogs(game_data: GameData, macro_coords: Vector2i) -> Array[DomesticAnimal]:
	var dogs: Array[DomesticAnimal] = []
	var today := game_data.get_absolute_day()
	for animal in game_data.domestic_animals:
		if animal.body_id == 0 or animal.macro_coords != macro_coords:
			continue
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null or rules.guard_alarm_radius <= 0.0 \
				or animal.get_age_band(today, DomesticAnimalCalculator.get_wild_rules(animal.species)) == GameTypes.AgeBand.YOUNG:
			continue
		dogs.append(animal)
	return dogs


# Ogni fotogramma, per ogni visita (WildAnimalVisitService.advance). `game_delta` in giorni di gioco.
static func update_visit(visit: WildAnimalVisit, game_data: GameData, game_delta: float) -> void:
	visit.reaction_points.resize(visit.building_reaction_count)
	visit.reaction_radii.resize(visit.building_reaction_count)
	visit.safe_points.resize(visit.building_safe_count)
	visit.safe_radii.resize(visit.building_safe_count)
	if game_data.domestic_animals.is_empty():
		return
	var hours := game_delta * 24.0
	for animal in guard_dogs(game_data, visit.macro_coords):
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules.guard_keep_away_reaction > 0.0:
			visit.reaction_points.append(animal.position)
			visit.reaction_radii.append(rules.guard_keep_away_reaction)
		if rules.guard_keep_away_radius > 0.0:
			visit.safe_points.append(animal.position)
			visit.safe_radii.append(rules.guard_keep_away_radius)
		_update_alarm(visit, animal, rules, hours)
		_update_confront(visit, animal, rules)


# Peso dei cani di guardia attorno a `point` nella difesa del tiro d'attacco; `dogs` da guard_dogs.
static func defense_near(dogs: Array[DomesticAnimal], point: Vector2) -> Dictionary:
	var strength := 0.0
	var count := 0
	for animal in dogs:
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if animal.position.distance_to(point) <= rules.guard_help_radius and rules.guard_defense_strength > 0.0:
			strength += rules.guard_defense_strength
			count += 1
	return {"strength": strength, "count": count}


# Inizio della carica: corrono tutti i cani di guardia entro guard_help_radius da chi è caricato. Ritorna l'aiuto di
# ognuno ({"position", "helper", "threats"}) per DangerFleeService.start_drive_off, che lo mette in fila con le persone.
static func start_run(visit: WildAnimalVisit, game_data: GameData, target_position: Vector2) -> Array:
	visit.guard_dog_ids.clear()
	visit.guard_dog_points.clear()
	visit.guard_dogs_clashed.clear()
	var support: Array = []
	for animal in guard_dogs(game_data, visit.macro_coords):
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if animal.position.distance_to(target_position) > rules.guard_help_radius:
			continue
		visit.guard_dog_ids.append(animal.id)
		animal.guard_running = true
		animal.guard_confront_group_id = -1
		support.append({"position": animal.position, "helper": rules.guard_helper_weight,
			"threats": rules.guard_threats_per_dog})
		_log("[DOMESTIC GUARD] %s #%d corre contro %s (a %.1f microcelle dal caricato)" % [
			animal.species, animal.id, visit.species, animal.position.distance_to(target_position)])
	return support


# Ogni fotogramma della carica: ogni cane che corre va di corsa verso il presente più vicino (punto rinnovato quando quello
# si sposta di più di RUN_REPLAN_DISTANCE; anche dopo un caricamento, quando guard_dog_points è vuoto).
static func update_run(visit: WildAnimalVisit, game_data: GameData) -> void:
	var profile := DangerFleeService.get_profile(WildAnimalVisitService.DANGER_PROFILE)
	var stop_distance: float = profile.drive_off_stop_distance if profile != null else 2.0
	for animal_id in visit.guard_dog_ids:
		var animal := DomesticAnimalService.find_animal(game_data, animal_id)
		if animal == null or animal.body_id == 0:
			continue
		animal.guard_running = true
		var nearest := _nearest_visitor_position(visit, animal.position)
		if not is_finite(nearest.x):
			continue
		var away := animal.position - nearest
		var point := nearest + (away.normalized() if away.length() > 0.001 else Vector2.RIGHT) * stop_distance
		var last: Variant = visit.guard_dog_points.get(animal_id)
		if last != null and (last as Vector2).distance_to(point) <= RUN_REPLAN_DISTANCE:
			continue
		visit.guard_dog_points[animal_id] = point
		AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.GO_TO, point, 0.0, 0.0, 1.0, true)


# Scontro (passo 8.4), ogni fotogramma della carica: il cane appena arrivato sul branco (entro DRIVE_OFF_GIVE_UP_DISTANCE),
# una volta per carica, può mordere il presente più vicino (guard_bite_chance, guard_bite_damage dalla salute del corpo;
# a 0 il lupo muore come per la caccia: carcassa e fuori dal branco, WildAnimalVisitService.on_member_killed) e può essere
# ferito (guard_wound_chance, guard_wound_health_ratio della salute piena; a 0 muore, DomesticAnimalLifeService.wound).
# true = la visita è finita (ucciso l'ultimo presente).
static func resolve_clashes(visit: WildAnimalVisit, game_data: GameData, individuals: Array[HumanIndividual],
		effects: GameEffects) -> bool:
	for animal_id in visit.guard_dog_ids.duplicate():
		if visit.guard_dogs_clashed.has(animal_id):
			continue
		var animal := DomesticAnimalService.find_animal(game_data, animal_id)
		if animal == null or animal.body_id == 0:
			continue
		var index := _nearest_visitor_index(visit, animal.position)
		if index < 0 or visit.animal_positions[index].distance_to(animal.position) > WildAnimalVisitService.DRIVE_OFF_GIVE_UP_DISTANCE:
			continue
		visit.guard_dogs_clashed[animal_id] = true
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if randf() < rules.guard_bite_chance and _bite(visit, index, animal, rules, game_data, individuals, effects):
			return true
		if randf() < rules.guard_wound_chance:
			_wound_dog(animal, rules, visit, game_data, effects)
	return false


# Morso del cane al presente `index`. true = la visita è finita.
static func _bite(visit: WildAnimalVisit, index: int, animal: DomesticAnimal, rules: DomesticAnimalRules, game_data: GameData,
		individuals: Array[HumanIndividual], effects: GameEffects) -> bool:
	var body := AnimalGroupRenderer.find_live_individual(visit.body_ids[index])
	if body == null:
		return false
	body.health = maxf(body.health - rules.guard_bite_damage, 0.0)
	_log("[DOMESTIC GUARD] %s #%d morde %s #%d: salute %.1f" % [animal.species, animal.id, visit.species, body.wild_animal_id, body.health])
	if body.health > 0.0:
		return false
	GroundPileService.drop_carcass(game_data, visit.macro_coords, body.position, body.species_name, int(body.age_band))
	WildAnimalVisitService.on_member_killed(game_data, body, individuals, effects)
	return WildAnimalVisitService.find_visit(game_data, visit.group_id) == null


static func _wound_dog(animal: DomesticAnimal, rules: DomesticAnimalRules, visit: WildAnimalVisit, game_data: GameData,
		effects: GameEffects) -> void:
	DomesticAnimalLifeService.wound(game_data, animal, rules.guard_wound_health_ratio)
	if DomesticAnimalService.find_animal(game_data, animal.id) != null:
		_log("[DOMESTIC GUARD] %s #%d ferito da %s: salute %d%%" % [animal.species, animal.id, visit.species, roundi(animal.health_ratio * 100.0)])
		return
	_log("[DOMESTIC GUARD] %s #%d ucciso da %s" % [animal.species, animal.id, visit.species])
	if effects != null:
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_ATTACK,
			GameContext.tr_text("notification_domestic_guard_died_%s" % animal.species))


# Cani arrivati sul branco: quanti aiutanti valgono (guard_helper_weight) e quante minacce coprono.
static func arrived_support(visit: WildAnimalVisit, game_data: GameData) -> Dictionary:
	var helpers := 0.0
	var threats := 0
	for animal_id in visit.guard_dog_ids:
		var animal := DomesticAnimalService.find_animal(game_data, animal_id)
		if animal == null or animal.body_id == 0:
			continue
		if _nearest_visitor_distance(visit, animal.position) <= WildAnimalVisitService.DRIVE_OFF_GIVE_UP_DISTANCE:
			var rules := DomesticAnimalCalculator.get_rules(animal.species)
			helpers += rules.guard_helper_weight
			threats += rules.guard_threats_per_dog
	return {"helpers": helpers, "threats": threats}


# Fine della carica: i cani che correvano tornano a seguire le persone.
static func end_run(visit: WildAnimalVisit, game_data: GameData, world: World) -> void:
	for animal_id in visit.guard_dog_ids:
		var animal := DomesticAnimalService.find_animal(game_data, animal_id)
		if animal != null:
			# Riprende a seguire le persone: sceglie di nuovo al prossimo fotogramma.
			animal.guard_running = false
			animal.follow_person_id = -1
			animal.follow_hours_left = 0.0
			DomesticAnimalBodyService.send_home(animal, world)
	visit.guard_dog_ids.clear()
	visit.guard_dog_points.clear()


# Contro il branco (vedi il commento in testa e DomesticAnimalRules): ogni fotogramma della visita, in arrivo e in sosta.
static func _update_confront(visit: WildAnimalVisit, animal: DomesticAnimal, rules: DomesticAnimalRules) -> void:
	if rules.guard_confront_max_advance <= 0.0 or animal.guard_running or animal.hunt_person_id >= 0:
		return
	if visit.phase != WildAnimalVisit.Phase.ARRIVING and visit.phase != WildAnimalVisit.Phase.STAYING:
		return
	var confronting := animal.guard_confront_group_id == visit.group_id
	var origin := animal.guard_post if confronting else animal.position
	var nearest := _nearest_visitor_position(visit, origin)
	if not is_finite(nearest.x) or nearest.distance_to(origin) > rules.guard_alarm_radius:
		if confronting:
			_end_confront(animal, "branco lontano")
		return
	if not confronting:
		if animal.guard_confront_group_id >= 0:
			return
		animal.guard_confront_group_id = visit.group_id
		animal.guard_post = animal.position
		animal.guard_confront_point = Vector2(-1.0, -1.0)
		animal.guard_confront_running = false
		_log("[DOMESTIC GUARD] %s #%d va incontro a %s (a %.1f microcelle)" % [
			animal.species, animal.id, visit.species, nearest.distance_to(animal.position)])
	var to_pack := nearest - animal.guard_post
	var advance := clampf(to_pack.length() - rules.guard_confront_distance, 0.0, rules.guard_confront_max_advance)
	var point := animal.guard_post + (to_pack.normalized() if to_pack.length() > 0.001 else Vector2.ZERO) * advance
	var far := animal.position.distance_to(point) > rules.guard_confront_ring_max * 2.0
	if far:
		if not animal.guard_confront_running or animal.guard_confront_point.distance_to(point) > RUN_REPLAN_DISTANCE:
			animal.guard_confront_running = true
			animal.guard_confront_point = point
			AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.GO_TO, point, 0.0, 0.0, 1.0, true)
		return
	if animal.guard_confront_running or animal.guard_confront_point.distance_to(point) > RUN_REPLAN_DISTANCE:
		animal.guard_confront_running = false
		animal.guard_confront_point = point
		AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.STAND_AROUND, point,
			0.0, rules.guard_confront_ring_max, 1.0)


# Ogni fotogramma, per un animale col corpo (DomesticAnimalBodyService.sync_bodies). true = sta affrontando un branco (chi
# segue le persone o va a caccia lo lascia stare). Visita finita o ripartita: torna a seguire la gente.
static func update_confront_animal(animal: DomesticAnimal, game_data: GameData) -> bool:
	if animal.guard_confront_group_id < 0:
		return false
	if animal.guard_running:
		animal.guard_confront_group_id = -1
		return false
	var visit := WildAnimalVisitService.find_visit(game_data, animal.guard_confront_group_id)
	if visit == null:
		_end_confront(animal, "visita finita")
		return false
	if visit.phase != WildAnimalVisit.Phase.ARRIVING and visit.phase != WildAnimalVisit.Phase.STAYING:
		_end_confront(animal, "branco in partenza o alla carica")
		return false
	return true


static func _end_confront(animal: DomesticAnimal, reason: String) -> void:
	_log("[DOMESTIC GUARD] %s #%d torna dal branco (%s)" % [animal.species, animal.id, reason])
	animal.guard_confront_group_id = -1
	animal.guard_confront_running = false
	# Sceglie di nuovo chi seguire al prossimo fotogramma.
	animal.follow_person_id = -1
	animal.follow_hours_left = 0.0


# Branco a portata: abbaia subito e poi ogni guard_bark_interval_hours; fuori portata il conto si azzera, così al
# prossimo avvicinamento abbaia di nuovo subito. Branco in uscita: nessun abbaio.
static func _update_alarm(visit: WildAnimalVisit, animal: DomesticAnimal, rules: DomesticAnimalRules, hours: float) -> void:
	var nearest := _nearest_visitor_distance(visit, animal.position)
	# Branco in partenza (2026-11-07, richiesta utente): il pericolo è passato, niente allarme.
	if nearest > rules.guard_alarm_radius or visit.phase == WildAnimalVisit.Phase.LEAVING:
		visit.guard_bark_hours_left.erase(animal.id)
		return
	var left := float(visit.guard_bark_hours_left.get(animal.id, 0.0)) - hours
	if left > 0.0:
		visit.guard_bark_hours_left[animal.id] = left
		return
	visit.guard_bark_hours_left[animal.id] = rules.guard_bark_interval_hours
	if not visit.guard_alarm_logged:
		visit.guard_alarm_logged = true
		_log("[DOMESTIC GUARD] %s #%d abbaia: %s a %.1f microcelle" % [animal.species, animal.id, visit.species, nearest])
	if bark_emitter.is_valid():
		bark_emitter.call(animal)


# Distanza dal presente del branco più vicino col corpo in scena (INF se nessuno).
static func _nearest_visitor_distance(visit: WildAnimalVisit, point: Vector2) -> float:
	var nearest := _nearest_visitor_position(visit, point)
	return nearest.distance_to(point) if is_finite(nearest.x) else INF


# Posizione del presente del branco più vicino col corpo in scena (Vector2(INF, INF) se nessuno).
static func _nearest_visitor_position(visit: WildAnimalVisit, point: Vector2) -> Vector2:
	var index := _nearest_visitor_index(visit, point)
	return visit.animal_positions[index] if index >= 0 else Vector2(INF, INF)


# Indice del presente del branco più vicino col corpo in scena (-1 se nessuno).
static func _nearest_visitor_index(visit: WildAnimalVisit, point: Vector2) -> int:
	var nearest := -1
	var best := INF
	for i in range(mini(visit.body_ids.size(), visit.animal_positions.size())):
		if visit.body_ids[i] == 0:
			continue
		var distance := visit.animal_positions[i].distance_to(point)
		if distance < best:
			best = distance
			nearest = i
	return nearest


# Righe [DOMESTIC GUARD], dietro DebugLogging.SHOW_DOMESTIC_GUARD_LOGS.
static func _log(text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_DOMESTIC_GUARD_LOGS:
		print(text)
