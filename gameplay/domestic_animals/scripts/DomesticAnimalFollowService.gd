class_name DomesticAnimalFollowService
extends RefCounted

# Animali domestici dietro alle persone (cane, passo 8.3, 2026-11-06, richiesta utente: attorno al magazzino la guardia non
# scattava mai). Stateless. Ogni animale gironzola (STAND_AROUND) attorno a una persona della sua macrocella che sta fuori
# dagli edifici, tra follow_ring_min e follow_ring_max microcelle: non attaccato come un bambino, va a un punto dell'anello,
# si ferma, ne sceglie un altro. Quando la persona si sposta di più di follow_ring_min dal centro, il centro passa su di lei.
# Ogni follow_change_hours ore di gioco sceglie di nuovo, preferendo chi non ha già un animale; nessuno fuori: torna al
# magazzino e riprova dopo NOBODY_RETRY_HOURS. Durante la corsa di guardia (DomesticAnimalGuardService) non si tocca.

const NOBODY_RETRY_HOURS: float = 1.0


# Ogni fotogramma, per un animale col corpo sulla mappa (DomesticAnimalBodyService.sync_bodies).
static func update_animal(animal: DomesticAnimal, game_data: GameData, world: World, individuals: Array[HumanIndividual],
		game_delta: float) -> void:
	if animal.guard_running or animal.hunt_person_id >= 0 or animal.guard_confront_group_id >= 0:
		return
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	if rules == null or rules.follow_ring_max <= 0.0:
		return
	animal.follow_hours_left -= game_delta * 24.0
	var person := _find_person(individuals, animal.follow_person_id) if animal.follow_person_id >= 0 else null
	if person != null and person.home_macro_coords != animal.macro_coords:
		person = null
	if person == null or animal.follow_hours_left <= 0.0:
		person = _choose_person(animal, game_data, world, individuals)
		animal.follow_hours_left = rules.follow_change_hours if person != null else NOBODY_RETRY_HOURS
		if person == null:
			if animal.follow_person_id != -1:
				animal.follow_person_id = -1
				DomesticAnimalBodyService.send_home(animal, world)
			return
		animal.follow_person_id = person.id
		_center_on(animal, person, rules)
		return
	if person.position.distance_to(animal.follow_center) > rules.follow_ring_min:
		_center_on(animal, person, rules)


static func _center_on(animal: DomesticAnimal, person: HumanIndividual, rules: DomesticAnimalRules) -> void:
	animal.follow_center = person.position
	AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.STAND_AROUND, person.position,
		rules.follow_ring_min, rules.follow_ring_max, rules.follow_speed_scale)


# Chi sta fuori dagli edifici nella macrocella dell'animale, col minor numero di altri animali che lo seguono (a caso tra
# i pari). null = nessuno fuori.
static func _choose_person(animal: DomesticAnimal, game_data: GameData, world: World,
		individuals: Array[HumanIndividual]) -> HumanIndividual:
	var rects := _building_rects(world, animal.macro_coords)
	var best: Array[HumanIndividual] = []
	var best_count := 1 << 30
	for member in individuals:
		if member.home_macro_coords != animal.macro_coords \
				or rects.any(func(rect: Rect2) -> bool: return rect.has_point(member.position)):
			continue
		var count := 0
		for other in game_data.domestic_animals:
			if other != animal and other.follow_person_id == member.id:
				count += 1
		if count < best_count:
			best_count = count
			best.clear()
		if count == best_count:
			best.append(member)
	return best.pick_random() if not best.is_empty() else null


# Pianta degli edifici completati e non calpestabili della macrocella: chi ci sta è "dentro".
static func _building_rects(world: World, macro_coords: Vector2i) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if world == null:
		return rects
	for building in world.buildings:
		if building.macro_x != macro_coords.x or building.macro_y != macro_coords.y:
			continue
		if not building.is_complete or building.is_demolished or building.rules == null or building.rules.walkable:
			continue
		rects.append(Rect2(Vector2(building.micro_x, building.micro_y), Vector2(BuildingFootprint.size_of(building))))
	return rects


static func _find_person(individuals: Array[HumanIndividual], person_id: int) -> HumanIndividual:
	for member in individuals:
		if member.id == person_id:
			return member
	return null
