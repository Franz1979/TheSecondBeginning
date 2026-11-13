class_name DomesticAnimalBodyService
extends RefCounted

# Corpi degli animali domestici sulla mappa (cane, passo 3, 2026-11-03): un AnimalGroupRenderer per specie e macrocella, non
# in LiveMacroCell.animal_renderers, quindi fauna, caccia e salvataggio degli individui non lo vedono (come i corpi delle
# visite). Senza padrone né cuccia: gironzolano attorno al magazzino e ignorano le persone. Cella non viva: nessun corpo,
# il cane resta dov'era e ricompare quando torna viva.

const PLACE_ATTEMPTS: int = 8
# Un animale al bordo dell'inquadratura entra ed esce di continuo: al massimo un verso ogni tanto per questo motivo.
const FRAMED_CALL_INTERVAL_MSEC: int = 30000


# Ogni fotogramma (GameScene._sync_domestic_animal_bodies). `renderers`: chiave di _renderer_key -> renderer, tenuto dalla
# scena; `make_renderer`: Callable(LiveMacroCell, DomesticAnimalRules) -> AnimalGroupRenderer. `individuals` e
# `game_delta` (giorni) per chi segue le persone (passo 8.3, DomesticAnimalFollowService).
static func sync_bodies(game_data: GameData, world: World, renderers: Dictionary, make_renderer: Callable,
		individuals: Array[HumanIndividual], game_delta: float) -> void:
	# Cacciatori e loro animale (2026-11-07, DomesticAnimalHuntService): prima del giro, chi è a caccia non segue la gente.
	DomesticAnimalHuntService.assign(game_data, world, individuals)
	for animal in game_data.domestic_animals:
		# Tenuti in un edificio (2026-11-12): nessun corpo sulla mappa.
		if animal.building_id >= 0:
			continue
		var body := AnimalGroupRenderer.find_live_individual(animal.body_id) if animal.body_id != 0 else null
		if body != null:
			animal.position = body.position
			if DomesticAnimalGuardService.update_confront_animal(animal, game_data):
				continue
			if not DomesticAnimalHuntService.update_animal(animal, individuals, game_delta):
				DomesticAnimalFollowService.update_animal(animal, game_data, world, individuals, game_delta)
			continue
		animal.body_id = 0
		# Cella non viva: si esce subito, questo giro è per ogni fotogramma.
		if animal.macro_coords.x >= 0 and PathfindingService.get_live_cell(animal.macro_coords) == null:
			continue
		var rules := DomesticAnimalCalculator.get_rules(animal.species)
		if rules == null:
			continue
		var storage := WildAnimalGroupService.find_anchor_storage(world)
		if animal.macro_coords.x < 0:
			if storage == null:
				continue
			animal.macro_coords = Vector2i(storage.macro_x, storage.macro_y)
		var cell := PathfindingService.get_live_cell(animal.macro_coords)
		if cell == null:
			continue
		var home := _home_point(animal, storage)
		if animal.position.x < 0.0:
			animal.position = _pick_free_point(home, rules, PathfindingService.blocked_test_for(animal.macro_coords))
		var key := _renderer_key(animal)
		var renderer = renderers.get(key)
		if not is_instance_valid(renderer):
			renderer = make_renderer.call(cell, rules)
			renderers[key] = renderer
		var band := animal.get_age_band(game_data.get_absolute_day(), DomesticAnimalCalculator.get_wild_rules(animal.species))
		# Gruppo 0: i corpi delle visite hanno il loro id, questo non è di nessun gruppo selvatico.
		body = renderer.add_identified_individual(band, animal.position, 0, animal.id)
		animal.body_id = body.id
		body.health *= animal.health_ratio
		# Corpo nuovo: comincia dal magazzino e sceglie chi seguire al prossimo fotogramma.
		animal.follow_person_id = -1
		animal.follow_hours_left = 0.0
		animal.guard_running = false
		animal.hunt_person_id = -1
		animal.hunt_catching_up = false
		animal.guard_confront_group_id = -1
		animal.hunt_chase_prey_id = -1
		animal.hunt_hold_hours_left = 0.0
		AnimalGroupRenderer.set_live_behavior(body.id, AnimalVisualGroup.Behavior.STAND_AROUND, home,
			rules.roam_radius_min, rules.roam_radius_max, rules.roam_speed_scale)


# Torna a gironzolare attorno al magazzino, come quando il corpo compare (finita la guardia, passo 8.2).
static func send_home(animal: DomesticAnimal, world: World) -> void:
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	if rules == null or animal.body_id == 0:
		return
	AnimalGroupRenderer.set_live_behavior(animal.body_id, AnimalVisualGroup.Behavior.STAND_AROUND,
		_home_point(animal, WildAnimalGroupService.find_anchor_storage(world)),
		rules.roam_radius_min, rules.roam_radius_max, rules.roam_speed_scale)


static func _home_point(animal: DomesticAnimal, storage: Building) -> Vector2:
	if storage != null and Vector2i(storage.macro_x, storage.macro_y) == animal.macro_coords:
		return VisitorService.get_building_point(storage)
	return animal.position


# Parametri del renderer: quelli della selvatica, con taglia e colore della specie domestica. species_name resta quello della
# selvatica, da cui il renderer legge salute e raggi.
static func build_renderer_config(wild_config: Dictionary, rules: DomesticAnimalRules) -> Dictionary:
	var config := wild_config.duplicate()
	var sizes = config["size_multiplier_by_age"].duplicate()
	for i in range(sizes.size()):
		sizes[i] *= rules.body_size_scale
	config["size_multiplier_by_age"] = sizes
	config["mesh"] = AnimalGroupRenderer.build_domestic_mesh(rules.wild_species_name, rules.body_color)
	return config


# Animali appena entrati nell'inquadratura (`view`, coordinate globali) e visibili: per il loro verso. Lista di
# {"position": Vector2 globale, "species": String}.
static func collect_newly_framed(game_data: GameData, renderers: Dictionary, view: Rect2) -> Array[Dictionary]:
	var framed: Array[Dictionary] = []
	var now_msec := Time.get_ticks_msec()
	for animal in game_data.domestic_animals:
		var body := AnimalGroupRenderer.find_live_individual(animal.body_id) if animal.body_id != 0 else null
		var renderer = renderers.get(_renderer_key(animal))
		if body == null or not is_instance_valid(renderer):
			animal.was_framed = false
			continue
		var global_position: Vector2 = renderer.to_global(body.position * MicroCellRenderer.CELL_SIZE)
		var is_framed: bool = view.has_point(global_position) and renderer.is_individual_visible(body)
		if is_framed and not animal.was_framed \
				and (animal.last_framed_call_msec < 0 or now_msec - animal.last_framed_call_msec >= FRAMED_CALL_INTERVAL_MSEC):
			animal.last_framed_call_msec = now_msec
			framed.append({"position": global_position, "species": animal.species})
		animal.was_framed = is_framed
	return framed


# Posizione globale del corpo di un animale, Vector2.ZERO se non è sulla mappa.
static func get_global_position(animal: DomesticAnimal, renderers: Dictionary) -> Vector2:
	var body := AnimalGroupRenderer.find_live_individual(animal.body_id) if animal.body_id != 0 else null
	var renderer = renderers.get(_renderer_key(animal))
	if body == null or not is_instance_valid(renderer):
		return Vector2.ZERO
	return renderer.to_global(body.position * MicroCellRenderer.CELL_SIZE)


static func set_selected(renderers: Dictionary, body_id: int) -> void:
	for renderer in renderers.values():
		if is_instance_valid(renderer) and renderer.get_individual_by_id(body_id) != null:
			renderer.set_selected_individual(body_id)


static func clear_selected(renderers: Dictionary) -> void:
	for renderer in renderers.values():
		if is_instance_valid(renderer):
			renderer.clear_selected_individual()


static func _renderer_key(animal: DomesticAnimal) -> String:
	return "%s|%d|%d" % [animal.species, animal.macro_coords.x, animal.macro_coords.y]


static func _pick_free_point(home: Vector2, rules: DomesticAnimalRules, blocked_test: Callable) -> Vector2:
	var point := home
	for attempt in range(PLACE_ATTEMPTS):
		point = home + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(rules.roam_radius_min, rules.roam_radius_max)
		point = point.clamp(Vector2.ZERO, Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001))
		if not blocked_test.is_valid() or not bool(blocked_test.call(Vector2i(point.floor()))):
			return point
	return point
