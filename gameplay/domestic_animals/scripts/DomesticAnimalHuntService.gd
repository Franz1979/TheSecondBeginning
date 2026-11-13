class_name DomesticAnimalHuntService
extends RefCounted

# Cane da caccia, passo 1 (2026-11-07, decisione utente): chi parte per una caccia (diretta o in zona,
# HuntService.is_hunt_task) si porta dietro un animale domestico adulto (non giovane né vecchio) della sua macrocella:
# il più vicino libero, cioè con il corpo sulla mappa, non in corsa di guardia e non già a caccia con un altro. Uno solo
# per cacciatore. Gli sta stretto (STAND_AROUND tra hunt_ring_min e hunt_ring_max); se resta indietro più di
# hunt_catch_up_distance lo raggiunge di corsa. Finita la caccia, o se il cacciatore esce dalla macrocella (il corpo
# esiste solo nella sua), torna a seguire la gente (DomesticAnimalFollowService). La guardia ha la precedenza: se
# l'animale corre contro un branco (DomesticAnimalGuardService.start_run) la caccia per lui finisce. Stateless.
# Passo 2, fiuto: scenting_animal_for (HuntZoneService.find_sighted_prey). Passo 3, inseguire e tenere a bada:
# _update_chase (regole in DomesticAnimalRules, gruppo Hunt). Prossimo: rischi e scarti (4).

# Tra due nuovi punti dati di corsa, se il cacciatore si è spostato di più (microcelle).
const CATCH_UP_REPLAN_DISTANCE: float = 1.5


# Ogni fotogramma, una volta (DomesticAnimalBodyService.sync_bodies, prima del giro sugli animali): libera chi non deve più
# cacciare e dà un animale ai cacciatori che non ne hanno.
static func assign(game_data: GameData, world: World, individuals: Array[HumanIndividual]) -> void:
	var taken: Dictionary = {}
	for animal in game_data.domestic_animals:
		if animal.hunt_person_id < 0:
			continue
		var person := _find_person(individuals, animal.hunt_person_id)
		var reason := ""
		if animal.guard_running:
			reason = "corre di guardia"
		elif animal.body_id == 0:
			reason = "corpo non sulla mappa"
		elif person == null:
			reason = "cacciatore sparito"
		elif not HuntService.is_hunt_task(person.current_task) or person.current_task.is_finished():
			reason = "caccia finita"
		elif person.home_macro_coords != animal.macro_coords:
			reason = "cacciatore uscito dalla macrocella"
		if reason != "":
			_release(animal, world, reason)
			continue
		taken[person.id] = true
	for member in individuals:
		if taken.has(member.id) or not HuntService.is_hunt_task(member.current_task) or member.current_task.is_finished():
			continue
		var animal := _nearest_free_animal(game_data, member)
		if animal == null:
			continue
		animal.hunt_person_id = member.id
		animal.hunt_center = Vector2(-1.0, -1.0)
		animal.hunt_catching_up = false
		taken[member.id] = true
		log_line("[DOMESTIC HUNT] %s #%d va a caccia con #%d %s (a %.1f microcelle)" % [
			animal.species, animal.id, member.id, member.name, animal.position.distance_to(member.position)])


# Ogni fotogramma, per un animale col corpo sulla mappa. true = è a caccia (chi segue le persone lo lascia stare).
# `game_delta` in giorni di gioco.
static func update_animal(animal: DomesticAnimal, individuals: Array[HumanIndividual], game_delta: float) -> bool:
	if animal.hunt_person_id < 0 or animal.guard_running:
		return false
	var person := _find_person(individuals, animal.hunt_person_id)
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	if person == null or rules == null:
		return false
	if _update_chase(animal, person, rules, game_delta):
		return true
	var distance := animal.position.distance_to(person.position)
	if distance > rules.hunt_catch_up_distance:
		if not animal.hunt_catching_up or animal.hunt_center.distance_to(person.position) > CATCH_UP_REPLAN_DISTANCE:
			animal.hunt_catching_up = true
			animal.hunt_center = person.position
			AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.GO_TO, person.position,
				0.0, 0.0, 1.0, true)
		return true
	if animal.hunt_catching_up or animal.hunt_center.distance_to(person.position) > rules.hunt_ring_min:
		animal.hunt_catching_up = false
		animal.hunt_center = person.position
		AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.STAND_AROUND, person.position,
			rules.hunt_ring_min, rules.hunt_ring_max, rules.hunt_speed_scale)
	return true


# Inseguimento (passo 3). true = l'animale è occupato con la preda (insegue o la tiene a bada); false = torna/resta col
# cacciatore. Preda = "hunt_prey_id" della caccia in corso (diretta o in zona), un animale della fauna vivo nella stessa
# macrocella; mai un animale di un branco in visita (lupi: li si caccia, ma il cane non li ferma).
static func _update_chase(animal: DomesticAnimal, person: HumanIndividual, rules: DomesticAnimalRules,
		game_delta: float) -> bool:
	if rules.hunt_chase_max_distance <= 0.0:
		return false
	var prey_id := int(person.current_task.context.get(HuntZoneService.CONTEXT_PREY_ID, -1)) \
			if person.current_task != null else -1
	var prey := AnimalGroupRenderer.find_live_individual(prey_id) if prey_id > 0 else null
	if animal.hunt_chase_prey_id >= 0 and animal.hunt_chase_prey_id != prey_id:
		_end_chase(animal, "preda cambiata")
	if prey == null or prey.wild_animal_id > 0 or prey.macro_coords != animal.macro_coords:
		if animal.hunt_chase_prey_id >= 0:
			_end_chase(animal, "preda sparita o fuori dalla macrocella")
		return false
	if animal.hunt_chase_prey_id < 0:
		if prey.flee_timer <= 0.0:
			return false
		animal.hunt_chase_prey_id = prey.id
		animal.hunt_hold_hours_left = 0.0
		animal.hunt_chase_point = Vector2(-1.0, -1.0)
		animal.hunt_catching_up = false
		animal.hunt_center = Vector2(-1.0, -1.0)
		log_line("[DOMESTIC HUNT] %s #%d insegue %s #%d (a %.1f microcelle)" % [
			animal.species, animal.id, prey.species_name, prey.id, animal.position.distance_to(prey.position)])
	if animal.position.distance_to(person.position) > rules.hunt_chase_max_distance:
		_end_chase(animal, "troppo lontano dal cacciatore")
		return false
	# A bada: la preda resta ferma finché non scade il tempo o un tiro la rimette in fuga.
	if animal.hunt_hold_hours_left > 0.0:
		if prey.flee_timer > 0.0:
			animal.hunt_hold_hours_left = 0.0
			animal.hunt_chase_point = Vector2(-1.0, -1.0)
			log_line("[DOMESTIC HUNT] %s #%d: %s #%d scappa di nuovo" % [animal.species, animal.id, prey.species_name, prey.id])
		else:
			animal.hunt_hold_hours_left -= game_delta * 24.0
			if animal.hunt_hold_hours_left <= 0.0:
				_end_chase(animal, "la preda si è liberata")
				return false
			return true
	var distance := animal.position.distance_to(prey.position)
	if distance <= rules.hunt_hold_contact_distance:
		var wild_rules := AnimalCalculator.get_animal_rules(prey.species_name)
		var max_health := wild_rules.max_health if wild_rules != null else INF
		if max_health <= rules.hunt_max_prey_health and rules.hunt_hold_hours > 0.0:
			_hold(animal, prey, rules)
			return true
		# Troppo grossa: le sta addosso finché fugge, poi torna dal cacciatore.
		if prey.flee_timer <= 0.0:
			_end_chase(animal, "preda troppo grossa, smette di fuggire")
			return false
	elif prey.flee_timer <= 0.0 and animal.hunt_chase_point.x >= 0.0 and distance > rules.hunt_chase_max_distance * 0.5:
		_end_chase(animal, "preda ferma lontano")
		return false
	if animal.hunt_chase_point.x < 0.0 or animal.hunt_chase_point.distance_to(prey.position) > CATCH_UP_REPLAN_DISTANCE:
		animal.hunt_chase_point = prey.position
		AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.GO_TO, prey.position,
			0.0, 0.0, 1.0, true)
	return true


# La preda si ferma (fuga spenta, gira sul posto) e l'animale le gira attorno.
static func _hold(animal: DomesticAnimal, prey: AnimalVisualGroup, rules: DomesticAnimalRules) -> void:
	animal.hunt_hold_hours_left = rules.hunt_hold_hours
	prey.flee_timer = 0.0
	AnimalGroupRenderer.set_live_behavior(prey.id, AnimalVisualGroup.Behavior.STAND_AROUND, prey.position, 0.0, 0.4, 0.3)
	AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.STAND_AROUND, prey.position,
		1.0, 2.0, 1.0)
	log_line("[DOMESTIC HUNT] %s #%d tiene a bada %s #%d per %.0f ore" % [
		animal.species, animal.id, prey.species_name, prey.id, rules.hunt_hold_hours])


# Fine dell'inseguimento: la preda tenuta a bada torna libera; l'animale torna dal cacciatore al prossimo fotogramma.
static func _end_chase(animal: DomesticAnimal, reason: String) -> void:
	if animal.hunt_chase_prey_id < 0:
		return
	if animal.hunt_hold_hours_left > 0.0:
		var prey := AnimalGroupRenderer.find_live_individual(animal.hunt_chase_prey_id)
		if prey != null and prey.behavior == AnimalVisualGroup.Behavior.STAND_AROUND:
			AnimalGroupRenderer.set_live_behavior(prey.id, AnimalVisualGroup.Behavior.WANDER)
	log_line("[DOMESTIC HUNT] %s #%d smette di inseguire #%d (%s)" % [animal.species, animal.id, animal.hunt_chase_prey_id, reason])
	animal.hunt_chase_prey_id = -1
	animal.hunt_hold_hours_left = 0.0
	animal.hunt_chase_point = Vector2(-1.0, -1.0)
	animal.hunt_center = Vector2(-1.0, -1.0)
	animal.hunt_catching_up = false


# Animale che accompagna `hunter` col corpo sulla mappa e un fiuto (hunt_scent_radius > 0), null se nessuno (passo 2).
# Letto da HuntZoneService.find_sighted_prey, che non ha GameData: si usa quello condiviso della partita.
static func scenting_animal_for(hunter: HumanIndividual) -> DomesticAnimal:
	var game_data: GameData = GameSettings.active_game_data
	if hunter == null or game_data == null:
		return null
	for animal in game_data.domestic_animals:
		if animal.hunt_person_id != hunter.id or animal.body_id == 0 or animal.guard_running:
			continue
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules != null and rules.hunt_scent_radius > 0.0:
			return animal
	return null


static func _release(animal: DomesticAnimal, world: World, reason: String) -> void:
	_end_chase(animal, reason)
	log_line("[DOMESTIC HUNT] %s #%d torna dalla caccia con #%d (%s)" % [animal.species, animal.id, animal.hunt_person_id, reason])
	animal.hunt_person_id = -1
	animal.hunt_catching_up = false
	if animal.guard_running:
		return
	# Riprende a seguire la gente: sceglie di nuovo al prossimo fotogramma; intanto verso il magazzino.
	animal.follow_person_id = -1
	animal.follow_hours_left = 0.0
	DomesticAnimalBodyService.send_home(animal, world)


static func _nearest_free_animal(game_data: GameData, member: HumanIndividual) -> DomesticAnimal:
	var best: DomesticAnimal = null
	var best_distance := INF
	var today := game_data.get_absolute_day()
	for animal in game_data.domestic_animals:
		if animal.body_id == 0 or animal.hunt_person_id >= 0 or animal.guard_running or animal.guard_confront_group_id >= 0 \
				or animal.macro_coords != member.home_macro_coords:
			continue
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null or rules.hunt_ring_max <= 0.0:
			continue
		if animal.get_age_band(today, DomesticAnimalCalculator.get_wild_rules(animal.species)) != GameTypes.AgeBand.ADULT:
			continue
		var distance := animal.position.distance_to(member.position)
		if distance < best_distance:
			best_distance = distance
			best = animal
	return best


static func _find_person(individuals: Array[HumanIndividual], person_id: int) -> HumanIndividual:
	for member in individuals:
		if member.id == person_id:
			return member
	return null


# Righe [DOMESTIC HUNT], dietro DebugLogging.SHOW_DOMESTIC_HUNT_LOGS.
static func log_line(text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_DOMESTIC_HUNT_LOGS:
		print(text)
