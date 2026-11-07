class_name DomesticAnimalHuntService
extends RefCounted

# Cane da caccia, passo 1 (2026-11-07, decisione utente): chi parte per una caccia (diretta o in zona,
# HuntService.is_hunt_task) si porta dietro un animale domestico adulto (non giovane né vecchio) della sua macrocella:
# il più vicino libero, cioè con il corpo sulla mappa, non in corsa di guardia e non già a caccia con un altro. Uno solo
# per cacciatore. Gli sta stretto (STAND_AROUND tra hunt_ring_min e hunt_ring_max); se resta indietro più di
# hunt_catch_up_distance lo raggiunge di corsa. Finita la caccia, o se il cacciatore esce dalla macrocella (il corpo
# esiste solo nella sua), torna a seguire la gente (DomesticAnimalFollowService). La guardia ha la precedenza: se
# l'animale corre contro un branco (DomesticAnimalGuardService.start_run) la caccia per lui finisce. Stateless.
# Prossimi passi: fiuto (2), inseguire e tenere a bada (3), rischi e scarti (4).

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
		print("[DOMESTIC HUNT] %s #%d va a caccia con #%d %s (a %.1f microcelle)" % [
			animal.species, animal.id, member.id, member.name, animal.position.distance_to(member.position)])


# Ogni fotogramma, per un animale col corpo sulla mappa. true = è a caccia (chi segue le persone lo lascia stare).
static func update_animal(animal: DomesticAnimal, individuals: Array[HumanIndividual]) -> bool:
	if animal.hunt_person_id < 0 or animal.guard_running:
		return false
	var person := _find_person(individuals, animal.hunt_person_id)
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	if person == null or rules == null:
		return false
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


static func _release(animal: DomesticAnimal, world: World, reason: String) -> void:
	print("[DOMESTIC HUNT] %s #%d torna dalla caccia con #%d (%s)" % [animal.species, animal.id, animal.hunt_person_id, reason])
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
