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
