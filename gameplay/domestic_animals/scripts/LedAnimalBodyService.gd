class_name LedAnimalBodyService
extends RefCounted

# Corpi degli animali condotti con la cavezza (2026-11-18, richiesta utente — disegno di "Conduci al recinto"): per ogni
# record di LedAnimalService in una cella viva, un corpo della specie selvatica (renderer come quello del cane, per specie e
# cella, tenuto dalla scena). In mano a qualcuno: va dietro alla persona, a LEASH_DISTANCE dalla parte opposta a dove
# guarda, con una corda dalla persona al collo. Legato: gironzola appena attorno al paletto, con la corda corta. Cambio di
# macrocella: il corpo rinasce nella cella nuova. Cella non viva, animale nel recinto o morto: nessun corpo. Solo disegno:
# il record (salvato) resta la verità; non si seleziona (per ora). Stateless, statico.

const LEASH_DISTANCE: float = 1.0
# Rimasto troppo indietro (un ostacolo, un balzo perso): riappare al suo posto.
const LEASH_SNAP_DISTANCE: float = 3.0
const LEASH_SPEED_SCALE: float = 1.6
const TIED_RING_MIN: float = 0.2
const TIED_RING_MAX: float = 0.7
const TIED_SPEED_SCALE: float = 0.3
# Il collo: un tratto avanti dal centro del corpo, verso dove guarda.
const NECK_OFFSET: float = 0.35
const ROPE_COLOR := Color(0.62, 0.5, 0.32)
const ROPE_WIDTH: float = 1.2
const STAKE_COLOR := Color(0.36, 0.25, 0.14)
const STAKE_RADIUS: float = 1.6
# Scappato (LedAnimalService): corre via da chi lo teneva per tanto, poi sparisce.
const FLEE_DISTANCE: float = 8.0
const FLEE_MSEC: int = 4000


# Corda (e paletto) di un animale condotto, figlia del renderer del suo corpo: coordinate in pixel del renderer.
class RopeDrawer extends Node2D:
	var hand_point := Vector2.ZERO
	var neck_point := Vector2.ZERO
	var tied := false

	func _draw() -> void:
		draw_line(hand_point, neck_point, LedAnimalBodyService.ROPE_COLOR, LedAnimalBodyService.ROPE_WIDTH, true)
		if tied:
			draw_circle(hand_point, LedAnimalBodyService.STAKE_RADIUS, LedAnimalBodyService.STAKE_COLOR)


# Ogni fotogramma (GameScene, dopo i corpi del cane). `bodies`: led_id -> {"body_id", "key", "tied", "rope"}, tenuto dalla
# scena; `renderers`: chiave "selvatica|domestica|x|y" -> renderer; `make_renderer`: Callable(LiveMacroCell, String selvatica,
# String domestica — "" per i selvatici dell'imbuto, la specie per i domestici dal recinto, col loro aspetto) -> AnimalGroupRenderer.
static func sync(game_data: GameData, individuals: Array[HumanIndividual], bodies: Dictionary, renderers: Dictionary,
		make_renderer: Callable) -> void:
	if game_data.led_animals.is_empty() and bodies.is_empty():
		return
	var by_id := {}
	for member in individuals:
		by_id[member.id] = member
	var seen := {}
	for record in game_data.led_animals:
		var led_id := int(record["id"])
		var holder: HumanIndividual = by_id.get(int(record["holder_id"]))
		var macro := Vector2i(int(record["macro_x"]), int(record["macro_y"]))
		var local := Vector2(float(record["x"]), float(record["y"]))
		if holder != null:
			macro = LedAnimalService.real_macro(holder)
			local = LedAnimalService.real_local(holder)
		var cell := PathfindingService.get_live_cell(macro)
		if cell == null:
			continue
		var entry: Dictionary = record["entry"]
		var wild_species := String(entry.get("wild_species", ""))
		var domestic_species := String(entry.get("species", "")) if entry.has("animal_id") else ""
		var key := "%s|%s|%d|%d" % [wild_species, domestic_species, macro.x, macro.y]
		var state: Dictionary = bodies.get(led_id, {})
		var body := AnimalGroupRenderer.find_live_individual(int(state.get("body_id", 0))) if not state.is_empty() else null
		if body == null or String(state["key"]) != key:
			_remove(state, renderers)
			var renderer = renderers.get(key)
			if not is_instance_valid(renderer):
				renderer = make_renderer.call(cell, wild_species, domestic_species)
				if renderer == null:
					continue
				renderers[key] = renderer
			var start := local
			if holder != null:
				start = _leash_point(holder, local)
			body = renderer.add_identified_individual(entry.get("age_band", GameTypes.AgeBand.ADULT), start, 0, -1)
			var rope := RopeDrawer.new()
			renderer.add_child(rope)
			state = {"body_id": body.id, "key": key, "tied": null, "rope": rope}
			bodies[led_id] = state
		seen[led_id] = true
		var body_renderer: AnimalGroupRenderer = renderers[key]
		var tied := holder == null
		var anchor := local
		if tied:
			if state["tied"] != true:
				AnimalGroupRenderer.set_live_behavior(body.id, AnimalVisualGroup.Behavior.STAND_AROUND, local,
					TIED_RING_MIN, TIED_RING_MAX, TIED_SPEED_SCALE)
		else:
			var target := _leash_point(holder, local)
			if state["tied"] != false:
				AnimalGroupRenderer.set_live_behavior(body.id, AnimalVisualGroup.Behavior.CHASE, target, 0.0, 0.0,
					LEASH_SPEED_SCALE)
			else:
				body_renderer.set_individual_behavior_point(body.id, target)
			if body.position.distance_to(target) > LEASH_SNAP_DISTANCE:
				body.position = target
		state["tied"] = tied
		var rope: RopeDrawer = state["rope"]
		rope.visible = body_renderer.is_individual_visible(body)
		rope.tied = tied
		rope.hand_point = anchor * MicroCellRenderer.CELL_SIZE
		rope.neck_point = (body.position + body.direction * NECK_OFFSET) * MicroCellRenderer.CELL_SIZE
		rope.queue_redraw()
	for led_id in bodies.keys():
		if seen.has(led_id):
			continue
		var gone: Dictionary = bodies[led_id]
		if gone.has("flee_until_msec"):
			if Time.get_ticks_msec() < int(gone["flee_until_msec"]):
				continue
		elif LedAnimalService.take_escaped(int(led_id)) and _start_flee(gone):
			continue
		_remove(gone, renderers)
		bodies.erase(led_id)


# Corsa via dello scappato, lontano dalla persona (la mano della corda); la corda sparisce. false se il corpo non c'è.
static func _start_flee(state: Dictionary) -> bool:
	var body := AnimalGroupRenderer.find_live_individual(int(state["body_id"]))
	if body == null:
		return false
	var rope = state.get("rope")
	var away := Vector2.from_angle(randf() * TAU)
	if is_instance_valid(rope):
		var hand: Vector2 = (rope as RopeDrawer).hand_point / MicroCellRenderer.CELL_SIZE
		if body.position.distance_squared_to(hand) > 0.000001:
			away = (body.position - hand).normalized()
		rope.queue_free()
	state.erase("rope")
	var target := (body.position + away * FLEE_DISTANCE).clamp(Vector2.ZERO,
		Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001))
	AnimalGroupRenderer.set_live_behavior(body.id, AnimalVisualGroup.Behavior.GO_TO, target, 0.0, 0.0, 1.0, true)
	state["flee_until_msec"] = Time.get_ticks_msec() + FLEE_MSEC
	return true


# Dietro alla persona, dalla parte opposta a dove guarda, dentro la cella.
static func _leash_point(holder: HumanIndividual, local: Vector2) -> Vector2:
	var facing := holder.facing_direction.normalized() if holder.facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var point := local - facing * LEASH_DISTANCE
	return point.clamp(Vector2.ZERO, Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001))


static func _remove(state: Dictionary, renderers: Dictionary) -> void:
	if state.is_empty():
		return
	var renderer = renderers.get(String(state["key"]))
	if is_instance_valid(renderer):
		renderer.remove_individual(int(state["body_id"]))
	var rope = state.get("rope")
	if is_instance_valid(rope):
		rope.queue_free()
