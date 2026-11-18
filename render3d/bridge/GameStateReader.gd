class_name GameStateReader
extends RefCounted

# L'UNICO file della vista 3D che conosce GameScene: legge le celle accese e la camera 2D e li passa al 3D in forma
# semplice (Cell3DSource). Se GameScene cambia, si aggiusta solo questo file.
# Non scrive mai nello stato della simulazione; tocca solo la vista 2D (visibilità, camera).

var _game: Node2D


func _init(game: Node2D) -> void:
	_game = game


# Coordinate delle macrocelle accese adesso.
func live_cell_coords() -> Array:
	var live: Dictionary = _game.get("live_cells")
	return live.keys()


# Angolo della macrocella in microcelle rispetto al centro corrente (stesso posto del suo container 2D).
func cell_origin(coords: Vector2i) -> Vector2:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.container == null:
		return Vector2.ZERO
	return cell.container.position / float(MicroCellRenderer.CELL_SIZE)


func cell_source(coords: Vector2i) -> Cell3DSource:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null:
		return null
	var source := Cell3DSource.new()
	source.coords = coords
	source.origin = cell_origin(coords)
	source.world = cell.world
	source.water_type = cell.macro_cell.water_type if cell.macro_cell != null else GameTypes.WaterType.NONE
	source.river_positions = cell.river_positions
	source.stream_positions = cell.stream_positions
	if cell.macro_state != null:
		source.clay_positions = cell.macro_state.clay_positions
	var macro_world: World = _game.get("macro_world")
	if macro_world != null and cell.macro_cell != null:
		source.stream_layout = StreamMicrocellService.get_layout(macro_world, cell.macro_cell)
	return source


# Rocce e sassi della cella, come li disegna il 2D (MicroCellRenderer: posizioni, esaurite, disponibilità dei sassi).
func stone_snapshot(coords: Vector2i) -> StoneSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := StoneSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	for pos in renderer.stone_positions:
		var center := renderer.get_stone_screen_position(pos) / float(MicroCellRenderer.CELL_SIZE)
		snapshot.all_centers[pos] = center
		if not renderer.depleted_stone_positions.has(pos):
			snapshot.rock_centers[pos] = center
	snapshot.pebble_quantities = renderer.pebble_availability.duplicate()
	return snapshot


# "Impronta" di rocce e sassi della cella: cambia quando il 2D riceve dati nuovi (rocce esaurite, sassi raccolti).
# Confrontata con is_same/size, costa pochissimo a ogni frame.
func stone_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	return [renderer.stone_positions, renderer.stone_positions.size(), renderer.depleted_stone_positions,
		renderer.depleted_stone_positions.size(), renderer.pebble_availability]


# Alberi vivi della cella, con la stessa posizione e taglia del 2D (riusa la sua formula, mai una copia).
func tree_snapshot(coords: Vector2i) -> TreeSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := TreeSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	var positions: Array = renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	if positions.is_empty():
		return snapshot
	var lot_counts: Dictionary = renderer._lot_extent_counts(GameTypes.WorldObjectType.TREE)
	var cell_size := float(MicroCellRenderer.CELL_SIZE)
	for key in positions:
		var visual: Dictionary = renderer._compute_tree_visual(key, lot_counts)
		snapshot.grounds.append(visual["ground"] / cell_size)
		snapshot.trunk_heights.append(float(visual["trunk_height"]) / cell_size)
		snapshot.trunk_widths.append(float(visual["trunk_width"]) / cell_size)
		snapshot.canopy_radii.append(float(visual["canopy_radius"]) / cell_size)
		snapshot.seeds.append(hash(visual["jitter_pos"]))
		snapshot.conifer.append(1 if visual["is_conifer"] else 0)
	return snapshot


# "Impronta" degli alberi: cambia quando il 2D riceve un elenco nuovo (nascite, tagli, nebbia) o cambia l'anno (età).
func tree_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var positions: Array = renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	return [renderer.vegetation_positions, positions, positions.size(), renderer.tree_current_year]


# Cespugli vivi e tagliati della cella, con le stesse bolle (posizione, taglia, colore) del 2D: riusa le sue formule,
# mai una copia. Dagli stessi elenchi del 2D (filtrati dalla nebbia).
func shrub_snapshot(coords: Vector2i) -> ShrubSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := ShrubSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	var cell_size := float(MicroCellRenderer.CELL_SIZE)
	var lot_counts: Dictionary = renderer._lot_extent_counts(GameTypes.WorldObjectType.SHRUB)
	for key in renderer.vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, []):
		var visual: Dictionary = renderer._compute_shrub_visual(key, lot_counts)
		var geometry: Dictionary = renderer._compute_shrub_geometry(key, lot_counts, false)
		snapshot.centers.append(visual["center"] / cell_size)
		snapshot.seeds.append(hash(visual["jitter_pos"]))
		snapshot.fruit_bearing.append(1 if visual["is_fruit_bearing"] else 0)
		snapshot.blob_starts.append(snapshot.blob_centers.size())
		var transforms: Array = geometry["blob_transforms"]
		var colors: Array = geometry["blob_colors"]
		for i in range(transforms.size()):
			var t: Transform2D = transforms[i]
			snapshot.blob_centers.append(t.origin / cell_size)
			snapshot.blob_radii.append(t.x.length() / cell_size)
			snapshot.blob_colors.append(colors[i])
	snapshot.blob_starts.append(snapshot.blob_centers.size())
	for entry in renderer.cut_positions.get(GameTypes.WorldObjectType.SHRUB, []):
		var key: Vector3i = entry["key"]
		var t: Transform2D = renderer._build_shrub_stump_transform(key, float(entry["size_multiplier"]), lot_counts)
		snapshot.cut_centers.append(t.origin / cell_size)
		snapshot.cut_radii.append(t.x.length() / cell_size)
		snapshot.cut_seeds.append(hash(key))
	return snapshot


# "Impronta" dei cespugli: cambia quando il 2D riceve elenchi nuovi (nascite, tagli, nebbia) o cambia l'anno (età).
func shrub_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var positions: Array = renderer.vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	var cut: Array = renderer.cut_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	return [renderer.vegetation_positions, positions, positions.size(), renderer.shrub_current_year,
		renderer.cut_positions, cut, cut.size()]


# Focolari finiti della cella (dallo stesso elenco di edifici che disegna il 2D) col loro stato: acceso mentre ci si fa
# una ricetta a combustibile (Building.smoking_now, ProductionService.refresh_smoking), braci se ha combustibile nel
# deposito, spento altrimenti.
func hearth_snapshot(coords: Vector2i) -> HearthSnapshot3D:
	var snapshot := HearthSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	for entry in _hearth_entries(cell.renderer):
		snapshot.centers.append(MicroCellRenderer._building_entry_center(entry) / float(MicroCellRenderer.CELL_SIZE))
		snapshot.states.append(_hearth_state(int(entry.get("id", -1))))
		snapshot.seeds.append(hash(int(entry.get("id", -1))))
	return snapshot


# "Impronta" dei focolari: cambia con l'elenco degli edifici del 2D o con lo stato di un focolare (letto a ogni frame:
# i focolari sono pochi).
func hearth_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var signature: Array = [renderer.buildings, renderer.buildings.size()]
	for entry in _hearth_entries(renderer):
		signature.append(_hearth_state(int(entry.get("id", -1))))
	return signature


func _hearth_entries(renderer: MicroCellRenderer) -> Array:
	return _complete_entries_of_type(renderer, "campfire")


# Edifici finiti di un tipo nella cella (es. "deposit_site"), dallo stesso elenco e con lo stesso centro del 2D.
func building_places(coords: Vector2i, type_name: String) -> BuildingPlacesSnapshot3D:
	var snapshot := BuildingPlacesSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	for entry in _complete_entries_of_type(cell.renderer, type_name):
		snapshot.centers.append(MicroCellRenderer._building_entry_center(entry) / float(MicroCellRenderer.CELL_SIZE))
		snapshot.seeds.append(hash(int(entry.get("id", -1))))
	return snapshot


# Mattonelle dell'edificio "Terra battuta" finite della cella, con i lati che il 2D lascia dritti (dirt_neighbors,
# calcolati dal gioco).
func dirt_ground_tiles(coords: Vector2i) -> DirtGroundSnapshot3D:
	var snapshot := DirtGroundSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	for entry in _complete_entries_of_type(cell.renderer, "dirt_ground"):
		snapshot.positions.append(entry["position"])
		snapshot.neighbor_masks.append(int(entry.get("dirt_neighbors", 0)))
	return snapshot


# "Impronta" degli edifici della cella: cambia quando il 2D riceve un elenco nuovo.
func buildings_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	return [cell.renderer.buildings, cell.renderer.buildings.size()]


func _complete_entries_of_type(renderer: MicroCellRenderer, type_name: String) -> Array:
	var entries: Array = []
	for entry in renderer.buildings:
		if entry.get("building_type_name", "") == type_name and entry.get("is_complete", true):
			entries.append(entry)
	return entries


func _hearth_state(building_id: int) -> int:
	var macro_world: World = _game.get("macro_world")
	if macro_world == null:
		return HearthSnapshot3D.OUT
	for building in macro_world.buildings:
		if building.id != building_id:
			continue
		if building.smoking_now:
			return HearthSnapshot3D.BURNING
		if ProductionService.get_available_fuel(building) > 0.0:
			return HearthSnapshot3D.EMBERS
		return HearthSnapshot3D.OUT
	return HearthSnapshot3D.OUT


# Cosa copre il suolo della cella: erba, alberi e cespugli, rocce non esaurite. Dagli stessi elenchi che disegna il 2D
# (filtrati dalla nebbia come nel 2D), così con la nebbia anche in 3D resterà coerente.
func ground_cover_snapshot(coords: Vector2i) -> GroundCoverSnapshot3D:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var snapshot := GroundCoverSnapshot3D.new()
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	snapshot.grass = renderer.vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
	snapshot.trees = renderer.vegetation_positions.get(GameTypes.WorldObjectType.TREE, [])
	snapshot.shrubs = renderer.vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, [])
	for pos in renderer.stone_positions:
		if not renderer.depleted_stone_positions.has(pos):
			snapshot.rocks.append(pos)
	return snapshot


# "Impronta" del suolo: cambia quando il 2D riceve elenchi nuovi di erba, alberi, cespugli o rocce.
func ground_cover_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var renderer := cell.renderer
	var signature: Array = [renderer.vegetation_positions]
	for object_type in [GameTypes.WorldObjectType.GRASS, GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB]:
		var positions: Array = renderer.vegetation_positions.get(object_type, [])
		signature.append(positions)
		signature.append(positions.size())
	signature.append_array([renderer.stone_positions, renderer.stone_positions.size(),
		renderer.depleted_stone_positions, renderer.depleted_stone_positions.size()])
	return signature


# Opzione "mostra griglia" (la stessa del 2D).
func grid_visible() -> bool:
	return UserOptions.show_grid


# --- Camera 2D: il 3D la usa come punto guardato, così il gioco (celle accese, ritorno al 2D) resta allineato. ---

func _camera_2d() -> Camera2D:
	return _game.get_node_or_null("Camera2D") as Camera2D


# Punto guardato, in microcelle.
func camera_position() -> Vector2:
	var cam := _camera_2d()
	return cam.position / float(MicroCellRenderer.CELL_SIZE) if cam != null else Vector2.ZERO


func camera_zoom() -> float:
	var cam := _camera_2d()
	return cam.zoom.x if cam != null else 1.0


# Spinta di "mouse al bordo dello schermo" (x, y fra -1 e 1), con la stessa regola del 2D (margine, barra laterale e
# pannelli che coprono la mappa, mouse sopra la UI): calcolata dalla camera 2D, mai copiata.
func edge_pan_vector() -> Vector2:
	var cam := _camera_2d()
	if cam == null or not cam.has_method("_get_edge_pan_vector"):
		return Vector2.ZERO
	return cam.call("_get_edge_pan_vector")


# Attesa prima che parta lo spostamento al bordo (la stessa costante della camera 2D).
func edge_pan_delay() -> float:
	var cam := _camera_2d()
	if cam == null or cam.get_script() == null:
		return 0.3
	return float((cam.get_script() as Script).get_script_constant_map().get("EDGE_PAN_ACTIVATION_DELAY", 0.3))


func move_camera(delta_microcells: Vector2) -> void:
	var cam := _camera_2d()
	if cam != null:
		cam.position += delta_microcells * float(MicroCellRenderer.CELL_SIZE)


# true mentre un popup bloccante è aperto (GameScene blocca la camera 2D): il 3D si ferma allo stesso modo.
func camera_input_locked() -> bool:
	var cam := _camera_2d()
	return cam != null and bool(cam.get("input_locked"))


# --- Vista 2D ---

# Nasconde/mostra tutta la mappa 2D (celle, persone, animali). La UI sta nel CanvasLayer e resta visibile.
func set_2d_visible(value: bool) -> void:
	_game.visible = value


# Spegne il movimento della camera 2D (tasti, bordo, rotella) mentre comanda il 3D.
func set_2d_camera_enabled(value: bool) -> void:
	var cam := _camera_2d()
	if cam != null:
		cam.set_process(value)
		cam.set_process_unhandled_input(value)
