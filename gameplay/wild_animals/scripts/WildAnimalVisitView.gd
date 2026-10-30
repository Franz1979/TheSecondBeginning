class_name WildAnimalVisitView
extends Node2D

# Disegno di una visita di animali selvatici (2026-10-28, lupi passo L1): un MultiMesh con un'istanza per animale
# presente (una sola chiamata di disegno per visita), nella posizione e direzione calcolate da WildAnimalVisitService.
# Stessa sagoma e stesse scale per età della fauna (AnimalGroupRenderer.build_species_mesh,
# AnimalRules.size_multiplier_by_age), ma un nodo a parte, non un AnimalGroupRenderer: la fauna del mondo e questa
# visita non si toccano. Figlia del container della LiveMacroCell della visita, all'origine della cella (come
# VisitorPartyView). L'anello del selezionato è l'unica cosa disegnata in _draw.

const CELL_SIZE: int = AnimalGroupRenderer.CELL_SIZE

static var _mesh_cache: Dictionary = {}

var visit: WildAnimalVisit = null
var game_data: GameData = null
# Nebbia (2026-10-28): stesso test del renderer della fauna (FogOfWarRenderer.is_animal_visible_at, Callable(Vector2i)
# -> bool). Un animale non visibile ha l'istanza schiacciata a zero (nessun pixel, come AnimalGroupRenderer) e non si
# clicca. Non valorizzato = sempre visibile.
var visibility_test: Callable = Callable()
var _multimesh: MultiMesh = null
# Raggio del corpo dalla mesh (px), per l'anello di selezione.
var _mesh_radius: float = 0.0
# Scala per animale presente (età al momento della visita), stessi indici di visit.animal_ids.
var _scales: Array[float] = []
# Animale selezionato (id del WildAnimal), 0 = nessuno.
var _selected_animal_id: int = 0


func setup(p_visit: WildAnimalVisit, p_game_data: GameData) -> void:
	visit = p_visit
	game_data = p_game_data
	var group_rules := WildAnimalGroupService.get_rules(visit.species)
	var wild_species := group_rules.wild_species_name if group_rules != null else visit.species
	var wild_rules := AnimalCalculator.get_animal_rules(wild_species)
	var mesh := _get_mesh(wild_species)
	_mesh_radius = 0.0
	if mesh != null:
		var aabb: AABB = mesh.get_aabb()
		_mesh_radius = maxf(maxf(absf(aabb.position.x), absf(aabb.end.x)), maxf(absf(aabb.position.y), absf(aabb.end.y)))
	_scales.clear()
	var group: WildAnimalGroup = null
	for candidate in game_data.wild_animal_groups:
		if candidate.id == visit.group_id:
			group = candidate
	var today := game_data.get_absolute_day()
	for animal_id in visit.animal_ids:
		var animal: WildAnimal = group.find_animal(animal_id) if group != null else null
		var animal_scale := 1.0
		if animal != null and wild_rules != null:
			var band := animal.get_age_band(today, wild_rules)
			if band < wild_rules.size_multiplier_by_age.size():
				animal_scale = float(wild_rules.size_multiplier_by_age[band])
		_scales.append(animal_scale)
	if mesh == null:
		return
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.mesh = mesh
	_multimesh.instance_count = visit.animal_ids.size()
	var instance := MultiMeshInstance2D.new()
	instance.multimesh = _multimesh
	add_child(instance)
	_update_instances()


# Sagoma della specie selvatica, costruita una volta per specie.
static func _get_mesh(wild_species: String) -> Mesh:
	if not _mesh_cache.has(wild_species):
		_mesh_cache[wild_species] = AnimalGroupRenderer.build_species_mesh(wild_species)
	return _mesh_cache[wild_species]


func _process(_delta: float) -> void:
	if visit == null:
		return
	_update_instances()
	if _selected_animal_id != 0:
		queue_redraw()


func _update_instances() -> void:
	if _multimesh == null:
		return
	for i in range(visit.animal_ids.size()):
		var animal_position := WildAnimalVisitService.get_animal_position(visit, i)
		if not is_visible_at(animal_position):
			_multimesh.set_instance_transform_2d(i, Transform2D(Vector2.ZERO, Vector2.ZERO, animal_position * CELL_SIZE))
			continue
		var animal_transform := Transform2D(WildAnimalVisitService.get_animal_heading(visit, i), animal_position * CELL_SIZE)
		var animal_scale: float = _scales[i] if i < _scales.size() else 1.0
		animal_transform.x *= animal_scale
		animal_transform.y *= animal_scale
		_multimesh.set_instance_transform_2d(i, animal_transform)


# Animali cliccabili: solo quelli visibili, [{"id": int, "position": Vector2 (microcelle)}] — vedi
# AnimalSelectorController.try_select.
func get_selectable_animals() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if visit == null:
		return result
	for i in range(visit.animal_ids.size()):
		var animal_position := WildAnimalVisitService.get_animal_position(visit, i)
		if is_visible_at(animal_position):
			result.append({"id": visit.animal_ids[i], "position": animal_position})
	return result


func set_selected_animal(animal_id: int) -> void:
	_selected_animal_id = animal_id
	queue_redraw()


func clear_selected_animal() -> void:
	_selected_animal_id = 0
	queue_redraw()


func is_visible_at(point: Vector2) -> bool:
	if not visibility_test.is_valid():
		return true
	return bool(visibility_test.call(Vector2i(
		clampi(int(floor(point.x)), 0, World.WIDTH - 1), clampi(int(floor(point.y)), 0, World.HEIGHT - 1)
	)))


# Solo l'anello del selezionato: stesse costanti di AnimalGroupRenderer._draw/_selection_ring_radius.
func _draw() -> void:
	if visit == null or _selected_animal_id == 0:
		return
	var index := visit.animal_ids.find(_selected_animal_id)
	if index < 0:
		return
	var animal_position := WildAnimalVisitService.get_animal_position(visit, index)
	if not is_visible_at(animal_position):
		return
	var animal_scale: float = _scales[index] if index < _scales.size() else 1.0
	draw_arc(animal_position * CELL_SIZE, maxf(_mesh_radius * animal_scale + AnimalGroupRenderer.SELECTION_RING_MARGIN_PX,
		AnimalGroupRenderer.SELECTION_RING_MIN_RADIUS_PX), 0.0, TAU, AnimalGroupRenderer.SELECTION_RING_SEGMENTS,
		AnimalGroupRenderer.SELECTION_RING_COLOR, AnimalGroupRenderer.SELECTION_RING_WIDTH)
