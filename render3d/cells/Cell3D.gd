class_name Cell3D
extends Node3D

# UNA macrocella accesa nella vista 3D: mette insieme i suoi oggetti 3D (terreno, acqua, ruscello, argilla, griglia, rocce e sassi) a partire
# dai dati letti da GameStateReader. Posizionata come il container 2D della stessa cella (1 microcella = 1 unità 3D).

const WATER_SEA := 0
const WATER_LAKE := 1
const WATER_RIVER := 2

var coords: Vector2i
var _grid: MeshInstance3D
var _source: Cell3DSource
# Livelli rifatti quando il gioco li cambia (rocce e sassi, alberi): nome -> nodo e nome -> impronta (vedi needs_refresh).
var _layers: Dictionary = {}
var _layer_signatures: Dictionary = {}
var _terrain_material: ShaderMaterial
var _selected_building_id: int = -1
var _hovered_building_id: int = -1


func build(source: Cell3DSource, materials: Materials3D) -> void:
	coords = source.coords
	_source = source
	name = "Cell_%d_%d" % [coords.x, coords.y]
	place(source.origin)
	var water_cells := _collect_water_cells(source)
	var clay_weights := ClayPatch3D.corner_weights(source)
	# Il ruscello lo disegna lo shader del terreno: ogni cella ha la sua copia del materiale con la sua maschera (le
	# texture restano condivise).
	var stream_mask := StreamMask3D.build(source)
	_terrain_material = TerrainMaterial3D.for_cell(materials.terrain, _base_global(), stream_mask)
	add_child(TerrainMesh3D.build(source, water_cells, clay_weights, stream_mask, _terrain_material))
	var water := WaterMesh3D.build(water_cells, materials.water)
	if water != null:
		add_child(water)
	var clay := ClayPatch3D.build(source, clay_weights, materials.vertex_color)
	if clay != null:
		add_child(clay)


func place(origin: Vector2) -> void:
	position = Vector3(origin.x, 0.0, origin.y)


# La griglia si costruisce solo la prima volta che serve.
func set_grid_visible(value: bool, materials: Materials3D) -> void:
	if value and _grid == null:
		_grid = GridLines3D.build(_source, materials.grid)
		add_child(_grid)
	if _grid != null:
		_grid.visible = value


# true se l'impronta letta dal gioco per quel livello è cambiata (roccia esaurita, sassi raccolti, alberi nati o tagliati).
func needs_refresh(layer: StringName, signature: Array) -> bool:
	var previous: Array = _layer_signatures.get(layer, [])
	if not _layer_signatures.has(layer) or signature.size() != previous.size():
		return true
	for i in range(signature.size()):
		if not _same_value(signature[i], previous[i]):
			return true
	return false


func refresh_stones(snapshot: StoneSnapshot3D, signature: Array, materials: Materials3D) -> void:
	var stones := Node3D.new()
	var base_global := _base_global()
	var rocks := Rock3D.build(snapshot, base_global, materials.vertex_color)
	if rocks != null:
		stones.add_child(rocks)
	var pebbles := Pebble3D.build(snapshot, base_global, materials.vertex_color)
	if pebbles != null:
		stones.add_child(pebbles)
	_set_layer(&"stones", stones, signature)


func refresh_sticks(snapshot: SticksSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_set_layer(&"sticks", Sticks3D.build(snapshot, _base_global(), materials.vertex_color), signature)


# Suoli (prato, sottobosco, ghiaia, terra): non è un nodo, è la maschera del materiale del terreno (aggiornata sul posto).
func refresh_ground_cover(snapshot: GroundCoverSnapshot3D, signature: Array) -> void:
	_layer_signatures[&"ground_cover"] = signature
	TerrainMaterial3D.set_cover(_terrain_material, GroundCover3D.build_image(snapshot))


func refresh_trees(snapshot: TreeSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_set_layer(&"trees", Trees3D.build(snapshot, _base_global(), materials.vertex_color), signature)


func refresh_shrubs(snapshot: ShrubSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_set_layer(&"shrubs", Shrubs3D.build(snapshot, _base_global(), materials.vertex_color), signature)


func refresh_hearths(snapshot: HearthSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_set_layer(&"hearths", Hearth3D.build(snapshot, _base_global(), materials.vertex_color), signature)


func refresh_deposit_sites(snapshot: BuildingPlacesSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_set_layer(&"deposit_sites", DepositSite3D.build(snapshot, _base_global(), materials.vertex_color), signature)


# Mucchietti delle scorte nei magazzini (segnaposto colorato per risorsa).
func refresh_storage_piles(snapshot: StoragePilesSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_set_layer(&"storage_piles", Piles3D.build(snapshot, _base_global(), materials.vertex_color), signature)


func refresh_pebble_circles(snapshot: BuildingPlacesSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_set_layer(&"pebble_circles", PebbleCircle3D.build(snapshot, _base_global(), materials.vertex_color), signature)


func refresh_work_areas(snapshot: WorkAreasSnapshot3D, signature: Array) -> void:
	_set_layer(&"work_areas", WorkAreas3D.build(snapshot, _base_global()), signature)


# Scritte delle zone di questa cella con le icone dei lavori da mettere sotto (WorkAreaIcons3D).
func work_area_labels() -> Array:
	var labels: Array = []
	var layer: Node = _layers.get(&"work_areas")
	if layer != null:
		for child in layer.get_children():
			if child is Label3D and child.has_meta(WorkAreas3D.ICON_KEYS_META):
				labels.append(child)
	return labels


# Selezione (alone a terra, riquadro) e contorno sui modelli degli edifici selezionati o sotto il mouse.
func refresh_selection(snapshot: SelectionSnapshot3D, signature: Array) -> void:
	_set_layer(&"selection", SelectionFrame3D.build(snapshot, _base_global()), signature)
	_selected_building_id = snapshot.selected_building_id
	_hovered_building_id = snapshot.hovered_building_id
	Outline3D.apply(_layers.get(&"building_models"), _selected_building_id, _hovered_building_id)


func refresh_building_models(snapshot: BuildingModelsSnapshot3D, signature: Array) -> void:
	_set_layer(&"building_models", BuildingModels3D.build(snapshot, _base_global()), signature)
	Outline3D.apply(_layers.get(&"building_models"), _selected_building_id, _hovered_building_id)


# Terra battuta: come i suoli, è una maschera del materiale del terreno (aggiornata sul posto), non un nodo.
func refresh_dirt_ground(snapshot: DirtGroundSnapshot3D, signature: Array) -> void:
	_layer_signatures[&"dirt_ground"] = signature
	TerrainMaterial3D.set_beaten(_terrain_material, DirtGround3D.build_image(snapshot))


# Sostituisce il nodo del livello (null = livello vuoto) e ne ricorda l'impronta.
func _set_layer(layer: StringName, node: Node3D, signature: Array) -> void:
	_layer_signatures[layer] = signature
	var old: Node3D = _layers.get(layer)
	if old != null:
		old.queue_free()
	_layers.erase(layer)
	if node != null:
		node.name = String(layer).capitalize()
		add_child(node)
		_layers[layer] = node


func _base_global() -> Vector2:
	return Vector2(coords.x * World.WIDTH, coords.y * World.HEIGHT)


# Microcelle d'acqua a riempimento pieno: mare/lago dal micro-mondo e fiume. Il ruscello no: lo disegna lo shader del
# terreno (StreamMask3D).
func _collect_water_cells(source: Cell3DSource) -> Dictionary:
	var water := {}
	if source.world != null:
		for micro_cell in source.world.cells:
			if micro_cell.water_type == GameTypes.WaterType.SEA:
				water[Vector2i(micro_cell.x, micro_cell.y)] = WATER_SEA
			elif micro_cell.water_type == GameTypes.WaterType.LAKE:
				water[Vector2i(micro_cell.x, micro_cell.y)] = WATER_LAKE
	for pos in source.river_positions:
		water[pos] = WATER_RIVER
	return water


# Confronto di un pezzo d'impronta: per riferimento gli elenchi del gioco (Array, Dictionary, oggetti: lo stesso elenco =
# niente di cambiato, senza scorrerlo), per valore il resto (numeri, vettori, testi, Packed*Array).
static func _same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_ARRAY, TYPE_DICTIONARY, TYPE_OBJECT:
			return is_same(a, b)
	return a == b
