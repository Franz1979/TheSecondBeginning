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
var _stones: Node3D
var _stone_signature: Array = []


func build(source: Cell3DSource, materials: Materials3D) -> void:
	coords = source.coords
	_source = source
	name = "Cell_%d_%d" % [coords.x, coords.y]
	place(source.origin)
	var water_cells := _collect_water_cells(source)
	var clay_weights := ClayPatch3D.corner_weights(source)
	add_child(TerrainMesh3D.build(source, water_cells, clay_weights, materials.vertex_color))
	var water := WaterMesh3D.build(water_cells, materials.water)
	if water != null:
		add_child(water)
	var stream := StreamRibbon3D.build(source, materials.vertex_color, materials.water)
	if stream != null:
		add_child(stream)
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


# Rocce e sassi: rifatti solo se l'impronta letta dal gioco è cambiata (roccia esaurita, sassi raccolti).
func needs_stone_refresh(signature: Array) -> bool:
	if signature.size() != _stone_signature.size():
		return true
	for i in range(signature.size()):
		if not is_same(signature[i], _stone_signature[i]):
			return true
	return false


func refresh_stones(snapshot: StoneSnapshot3D, signature: Array, materials: Materials3D) -> void:
	_stone_signature = signature
	if _stones != null:
		_stones.queue_free()
	_stones = Node3D.new()
	_stones.name = "Stones"
	var base_global := Vector2(coords.x * World.WIDTH, coords.y * World.HEIGHT)
	var rocks := Rock3D.build(snapshot, base_global, materials.vertex_color)
	if rocks != null:
		_stones.add_child(rocks)
	var pebbles := Pebble3D.build(snapshot, base_global, materials.vertex_color)
	if pebbles != null:
		_stones.add_child(pebbles)
	add_child(_stones)


# Microcelle d'acqua a riempimento pieno: mare/lago dal micro-mondo e fiume. Il ruscello no: è un nastro a parte
# (StreamRibbon3D) e non scava il terreno.
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
