class_name GameStateReader
extends RefCounted

# L'UNICO file della vista 3D che conosce GameScene: legge le celle accese e la camera 2D e li passa al 3D in forma
# semplice (Cell3DSource). Se GameScene cambia, si aggiusta solo questo file.
# Non scrive mai nello stato della simulazione; tocca solo la vista 2D (visibilità, camera).

# Passi con cui la terra battuta in cantiere cresce nel 3D (10 = ogni 10% di lavoro).
const DIRT_GROUND_STEPS := 10.0
# Terra battuta anche sotto ogni edificio finito (2026-11-19, prova dell'utente, come nel 2D): le sue microcelle entrano
# nella maschera della terra battuta. false = com'era prima (terra nuda della cella vuota). Mai sotto i campi.
const BEATEN_UNDER_BUILDINGS := true
const NO_BEATEN_UNDER_TYPES := ["field", "dirt_ground"]
# Edifici con la terra battuta un po' più scura sotto (2026-11-19, richiesta utente: il deposito non deve sembrare un
# cantiere). Vuoto = tutti uguali; quanto più scura: beaten_dark_amount in terrain.gdshader.
const DARKER_BEATEN_TYPES := ["deposit_site"]

var _game: Node2D
# Etichette 2D in spazio schermo nascoste mentre il 3D è acceso (work_areas), rimesse da set_2d_visible(true).
var _hidden_screen_labels: Array = []


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


# Edifici con modello Blender (BuildingModels3D.MODELS), finiti o in cantiere, più ogni cantiere non ancora allestito
# (cartello), con la fase decisa dal gioco (BuildingConstructionStage). Stesso elenco, centro e porta del 2D.
func building_models(coords: Vector2i) -> BuildingModelsSnapshot3D:
	var snapshot := BuildingModelsSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var by_id := _buildings_by_id()
	for entry in _model_entries(cell.renderer):
		snapshot.type_names.append(String(entry.get("building_type_name", "")))
		snapshot.ids.append(int(entry.get("id", -1)))
		snapshot.centers.append(MicroCellRenderer._building_entry_center(entry) / float(MicroCellRenderer.CELL_SIZE))
		snapshot.doors.append(TentShapes.direction_vector(entry.get("rotation", GameTypes.Direction.SOUTH)))
		snapshot.stages.append(_stage_of_entry(entry, by_id))
	return snapshot


# Impronta: elenco del 2D + fase di ogni edificio con modello (cambia mentre il lavoro avanza).
func building_models_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var signature: Array = [cell.renderer.buildings, cell.renderer.buildings.size()]
	var entries := _model_entries(cell.renderer)
	if entries.is_empty():
		return signature
	var by_id := _buildings_by_id()
	for entry in entries:
		signature.append(_stage_of_entry(entry, by_id))
	return signature


func _model_entries(renderer: MicroCellRenderer) -> Array:
	var entries: Array = []
	for entry in renderer.buildings:
		# Anche ogni cantiere non ancora allestito, di qualsiasi tipo: ha il cartello (come nel 2D).
		var not_set_up: bool = not entry.get("is_complete", true) and not entry.get("site_setup_complete", false)
		if not_set_up or BuildingModels3D.has_models(String(entry.get("building_type_name", ""))):
			entries.append(entry)
	return entries


func _stage_of_entry(entry: Dictionary, by_id: Dictionary) -> int:
	if entry.get("is_complete", true):
		return BuildingConstructionStage.COMPLETE
	return BuildingConstructionStage.stage_of(by_id.get(int(entry.get("id", -1))))


func _buildings_by_id() -> Dictionary:
	var by_id := {}
	var macro_world: World = _game.get("macro_world")
	if macro_world != null:
		for building in macro_world.buildings:
			by_id[building.id] = building
	return by_id


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


# Mattonelle dell'edificio "Terra battuta" della cella, con i lati che il 2D lascia dritti (dirt_neighbors, calcolati
# dal gioco): finite (piene) e in cantiere dopo la pulizia, battute quanto il lavoro fatto.
func dirt_ground_tiles(coords: Vector2i) -> DirtGroundSnapshot3D:
	var snapshot := DirtGroundSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var by_id := {}
	for entry in cell.renderer.buildings:
		if entry.get("building_type_name", "") != "dirt_ground":
			continue
		var strength := 1.0
		if not entry.get("is_complete", true):
			if by_id.is_empty():
				by_id = _buildings_by_id()
			strength = _dirt_ground_strength(by_id.get(int(entry.get("id", -1))))
			if strength <= 0.0:
				continue
		snapshot.positions.append(entry["position"])
		snapshot.neighbor_masks.append(int(entry.get("dirt_neighbors", 0)))
		snapshot.strengths.append(strength)
		snapshot.shades.append(0.0)
	if BEATEN_UNDER_BUILDINGS:
		for entry in cell.renderer.buildings:
			if String(entry.get("building_type_name", "")) in NO_BEATEN_UNDER_TYPES:
				continue
			# Cantieri: terra battuta già da quando l'allestimento è partito (2026-11-19, richiesta utente: non scura
			# durante i lavori e chiara alla fine).
			if not entry.get("is_complete", true) and not _occupies_ground(entry, by_id):
				continue
			var corner: Vector2i = entry["position"]
			var size: Vector2i = entry.get("size", Vector2i(1, 1))
			var shade := 1.0 if String(entry.get("building_type_name", "")) in DARKER_BEATEN_TYPES else 0.0
			for dy in range(size.y):
				for dx in range(size.x):
					snapshot.positions.append(corner + Vector2i(dx, dy))
					snapshot.neighbor_masks.append(0)
					snapshot.strengths.append(1.0)
					snapshot.shades.append(shade)
	return snapshot


# Impronta della terra battuta: elenco del 2D + avanzamento dei cantieri a passi (non a ogni briciola di lavoro).
func dirt_ground_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	var signature: Array = [cell.renderer.buildings, cell.renderer.buildings.size()]
	var by_id := {}
	for entry in cell.renderer.buildings:
		if entry.get("is_complete", true):
			continue
		if entry.get("building_type_name", "") == "dirt_ground":
			if by_id.is_empty():
				by_id = _buildings_by_id()
			signature.append(_dirt_ground_strength(by_id.get(int(entry.get("id", -1)))))
		elif BEATEN_UNDER_BUILDINGS:
			signature.append(_occupies_ground(entry, by_id))
	return signature


# Cantiere con l'allestimento partito (BuildingConstructionStage.occupies_ground). by_id si riempie alla prima richiesta.
func _occupies_ground(entry: Dictionary, by_id: Dictionary) -> bool:
	if by_id.is_empty():
		by_id.merge(_buildings_by_id())
	return BuildingConstructionStage.occupies_ground(by_id.get(int(entry.get("id", -1))))


# Lavoro fatto, a passi di DIRT_GROUND_STEPS, solo dopo la pulizia del cantiere (prima la terra è solo nuda).
func _dirt_ground_strength(building: Building) -> float:
	if building == null or not bool(building.construction_progress.get("ground_cleared", false)):
		return 0.0
	return floorf(BuildingConstructionStage.labor_progress(building) * DIRT_GROUND_STEPS) / DIRT_GROUND_STEPS


# "Impronta" degli edifici della cella: cambia quando il 2D riceve un elenco nuovo.
func buildings_signature(coords: Vector2i) -> Array:
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return []
	return [cell.renderer.buildings, cell.renderer.buildings.size()]


# Mucchietti dei magazzini della cella: uno per posto occupato del sito di deposito e del deposito coperto, nella stessa
# griglia del 2D (MicroCellRenderer._draw_deposit_site_storage_grid: 3×3 in ordine di riga, centrata sull'edificio).
func storage_piles(coords: Vector2i) -> StoragePilesSnapshot3D:
	var snapshot := StoragePilesSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var px := float(MicroCellRenderer.CELL_SIZE)
	var columns := MicroCellRenderer.DEPOSIT_SITE_STORAGE_GRID_COLUMNS
	var spacing := MicroCellRenderer.DEPOSIT_SITE_STORAGE_GRID_CELL_SPACING
	for type_name in ["deposit_site", "covered_depot"]:
		for entry in _complete_entries_of_type(cell.renderer, type_name):
			var center := MicroCellRenderer._building_entry_center(entry)
			var slots: Array = entry.get("slot_breakdown", [])
			for i in range(mini(slots.size(), columns * columns)):
				var resource_name := String((slots[i] as Dictionary).get("resource_name", ""))
				if resource_name == "":
					continue
				var offset := Vector2((float(i % columns) - 1.0) * spacing, (float(i / columns) - 1.0) * spacing)
				snapshot.add((center + offset) / px, resource_name, hash([int(entry.get("id", -1)), i]))
	_add_ground_piles(snapshot, coords)
	return snapshot


# Mucchi a terra della cella (GameData.ground_piles), come GroundPileView: le prime MAX_ICONS risorse in ordine di nome,
# sparse attorno al centro della microcella con le STESSE posizioni stabili (stessa sequenza casuale, seme = id del
# mucchio), più piccole del magazzino. Le carcasse no (modello a parte, più avanti).
func _add_ground_piles(snapshot: StoragePilesSnapshot3D, coords: Vector2i) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	var px := float(MicroCellRenderer.CELL_SIZE)
	for pile in game_data.ground_piles:
		if pile.macro_coords != coords:
			continue
		var names := pile.get_resource_names().slice(0, GroundPileView.MAX_ICONS)
		if names.is_empty():
			continue
		# Stessa sequenza di GroundPileView._build_slots (angolo di partenza, poi per ogni posto distanza e angolo).
		var rng := RandomNumberGenerator.new()
		rng.seed = pile.id
		var start_angle := rng.randf_range(0.0, TAU)
		for i in range(names.size()):
			var distance := 0.0 if i == 0 else rng.randf_range(GroundPileView.SCATTER_RADIUS * 0.6, GroundPileView.SCATTER_RADIUS)
			var angle := start_angle + TAU * float(i) / float(GroundPileView.MAX_ICONS) + rng.randf_range(-0.5, 0.5)
			rng.randf_range(-PI, PI) # rotazione dell'icona del 2D: qui la decide Piles3D, ma la sequenza resta la stessa
			var offset := Vector2.from_angle(angle) * distance / px
			snapshot.add(pile.get_position() + offset, names[i], hash([pile.id, i]), GroundPileView.ICON_SCALE)


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
	if value:
		for labels in _hidden_screen_labels:
			if is_instance_valid(labels):
				(labels as CanvasLayer).visible = true
		_hidden_screen_labels.clear()


# Click nel 3D (2026-11-19): allinea la mappa 2D nascosta al puntatore, così il punto `ground` (microcelle, coordinate
# della vista) cade esattamente sotto `screen`. Le selezioni del gioco (click, doppio click, pannelli) leggono la posizione
# del mouse sulla mappa 2D e funzionano invariate. Solo la trasformazione della tela del mondo: la UI (CanvasLayer) e il
# 3D non cambiano; la camera 2D la rimette a posto da sola quando si muove o si torna al 2D.
func align_2d_pointer(screen: Vector2, ground: Vector2) -> void:
	var zoom := camera_zoom()
	var world := ground * float(MicroCellRenderer.CELL_SIZE)
	_game.get_viewport().canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, screen - world * zoom)


# Altezza del terreno sotto un punto della vista (microcelle), come la disegna il 3D; 0 fuori dalle celle accese.
func ground_height_at(point: Vector2) -> float:
	for coords in (_game.get("live_cells") as Dictionary):
		var origin := cell_origin(coords)
		var local := point - origin
		if local.x >= 0.0 and local.y >= 0.0 and local.x < World.WIDTH and local.y < World.HEIGHT:
			return GroundHeight3D.land_height(coords.x * World.WIDTH + local.x, coords.y * World.HEIGHT + local.y)
	return 0.0


# Selezioni del 2D nella cella (MicroCellRenderer._selected_*) con le stesse misure del 2D, più l'edificio sotto il
# mouse (hovered_building_id, -1 = nessuno). Persone e animali non ancora: non sono nel 3D.
func selection(coords: Vector2i, hovered_building_id: int) -> SelectionSnapshot3D:
	var snapshot := SelectionSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	if cell == null or cell.renderer == null:
		return snapshot
	var renderer := cell.renderer
	var px := float(MicroCellRenderer.CELL_SIZE)
	var padding := MicroCellRenderer.SELECTION_OUTLINE_PADDING_RATIO
	var none := Vector2i(-1, -1)
	for key in ["_selected_microcell", "_selected_stick_lot"]:
		var lot: Vector2i = renderer.get(key)
		if lot != none:
			snapshot.squares.append(lot)
	var selected_id: int = renderer.get("_selected_building_id")
	var building_ids: Array[int] = [selected_id]
	if hovered_building_id != selected_id:
		building_ids.append(hovered_building_id)
	for building_id in building_ids:
		if building_id == -1:
			continue
		var center := renderer.get_building_screen_position(building_id)
		if center == Vector2(-1, -1):
			continue
		var radius := MicroCellRenderer.BUILDING_FENCE_RADIUS * padding
		for entry in renderer.buildings:
			if entry.get("id", -1) == building_id:
				var rect_size: Vector2i = entry.get("size", Vector2i(1, 1))
				if rect_size != Vector2i(1, 1):
					radius = maxf(radius, (Vector2(rect_size) * px).length() / 2.0 * padding)
				break
		var is_selected: bool = building_id == selected_id
		_add_halo(snapshot, center / px, radius / px, SelectionSnapshot3D.SELECTED if is_selected else SelectionSnapshot3D.HOVER)
		if is_selected:
			snapshot.selected_building_id = building_id
		else:
			snapshot.hovered_building_id = building_id
	var stone: Vector2i = renderer.get("_selected_stone_position")
	if stone != none and renderer.stone_positions.has(stone):
		_add_halo(snapshot, renderer.get_stone_screen_position(stone) / px, MicroCellRenderer.STONE_MAX_EXTENT * padding / px, SelectionSnapshot3D.SELECTED)
	var plant_type: int = renderer.get("_selected_individual_type")
	if plant_type != -1:
		var key: Vector3i = renderer.get("_selected_individual_key")
		var radius := 1.6 * padding
		# Centro: nel 2D l'anello sta sulla chioma (vista dall'alto); nel 3D l'alone va a terra, attorno al piede del tronco.
		var center := renderer.get_individual_screen_position(plant_type, key)
		if plant_type == GameTypes.WorldObjectType.TREE:
			center = renderer._compute_tree_visual(key, renderer._lot_extent_counts(plant_type))["ground"]
		if renderer.has_individual(plant_type, key):
			if plant_type == GameTypes.WorldObjectType.TREE:
				var visual: Dictionary = renderer._compute_tree_visual(key, renderer._lot_extent_counts(plant_type))
				radius = float(visual["canopy_radius"]) * padding
			elif plant_type == GameTypes.WorldObjectType.SHRUB:
				var visual: Dictionary = renderer._compute_shrub_visual(key, renderer._lot_extent_counts(plant_type))
				radius = (MicroCellRenderer.SHRUB_BLOB_MAX_DISTANCE_RATIO * float(visual["density_scale"])
					+ MicroCellRenderer.SHRUB_BLOB_MAX_RADIUS_RATIO * float(visual["size_multiplier"])) * padding
		_add_halo(snapshot, center / px, radius / px, SelectionSnapshot3D.SELECTED)
	return snapshot


# Aree di lavoro mostrate dal 2D nella cella (WorkAreaOverlay e WorkAreaDragPreview nel container della cella), con gli
# stessi colori, bordi e riempimenti. Le loro etichette in spazio schermo (MapScreenLabels, un CanvasLayer che il 2D
# nascosto non spegne) seguirebbero la mappa 2D: le nasconde finché il 3D è acceso (set_2d_visible le rimette).
func work_areas(coords: Vector2i) -> WorkAreasSnapshot3D:
	var snapshot := WorkAreasSnapshot3D.new()
	var cell: LiveMacroCell = (_game.get("live_cells") as Dictionary).get(coords)
	var game_data: GameData = GameSettings.active_game_data
	if cell == null or cell.container == null or game_data == null:
		return snapshot
	var by_id := {}
	for child in cell.container.get_children():
		if child is WorkAreaOverlay:
			var overlay := child as WorkAreaOverlay
			_hide_screen_labels(overlay)
			for area in overlay._areas_to_draw(game_data):
				var border := WorkAreaOverlay.BORDER_WIDTH
				var fill := WorkAreaOverlay.FILL_ALPHA
				if WorkAreaOverlay.pick_mode:
					border = WorkAreaOverlay.PICK_BORDER_WIDTH
					fill = WorkAreaOverlay.PICK_FILL_ALPHA
				elif area.id == WorkAreaOverlay.selected_area_id:
					border = WorkAreaOverlay.SELECTED_BORDER_WIDTH
				# Una zona sola anche se due overlay la disegnano (layer acceso + zona selezionata).
				if not by_id.has(area.id) or border > float(by_id[area.id]["border"]):
					by_id[area.id] = {"area": area, "border": border, "fill": fill}
		elif child is WorkAreaDragPreview:
			var preview := child as WorkAreaDragPreview
			_hide_screen_labels(preview)
			var rect: Rect2i = preview.get("_rect")
			if rect.size.x > 0 and rect.size.y > 0:
				snapshot.add(rect, WorkAreaDragPreview.PREVIEW_COLOR, WorkAreaOverlay.BORDER_WIDTH, WorkAreaOverlay.FILL_ALPHA,
					"%d×%d" % [rect.size.x, rect.size.y])
	for entry in by_id.values():
		var area: WorkArea = entry["area"]
		snapshot.add(area.rect, area.color, float(entry["border"]), float(entry["fill"]), area.name,
			PackedStringArray(WorkAreaOverlay.job_icon_keys(area)))
	return snapshot


func _hide_screen_labels(owner: Node) -> void:
	var labels: Node = owner.get("_screen_labels")
	if labels is CanvasLayer and (labels as CanvasLayer).visible:
		(labels as CanvasLayer).visible = false
		_hidden_screen_labels.append(labels)


func _add_halo(snapshot: SelectionSnapshot3D, center: Vector2, radius: float, strength: float) -> void:
	snapshot.halo_centers.append(center)
	snapshot.halo_radii.append(radius)
	snapshot.halo_strengths.append(strength)


# Edificio sotto un punto della vista (microcelle): {"coords": Vector2i, "id": int}, vuoto se nessuno. Come
# GameScene._find_building_at_microcell: se ci sono due strati vince quello che non è un fondo percorribile.
func building_at(point: Vector2) -> Dictionary:
	var macro_world: World = _game.get("macro_world")
	if macro_world == null:
		return {}
	for coords in (_game.get("live_cells") as Dictionary):
		var local := point - cell_origin(coords)
		if local.x < 0.0 or local.y < 0.0 or local.x >= World.WIDTH or local.y >= World.HEIGHT:
			continue
		var lot := Vector2i(int(floor(local.x)), int(floor(local.y)))
		var ground: Building = null
		for building in macro_world.buildings:
			if building.is_demolished or not BuildingFootprint.covers(building, coords, lot):
				continue
			if building.rules != null and building.rules.walkable:
				ground = building
				continue
			return {"coords": coords, "id": building.id}
		if ground != null:
			return {"coords": coords, "id": ground.id}
		return {}
	return {}


# Anteprima del piazzamento (GameScene._building_ghost): il gioco la tiene già sotto il mouse a ogni fotogramma
# (posizione al centro del rettangolo, validità, rotazione col tasto R); qui solo letta. Il fantasma è figlio della scena
# di gioco, quindi la sua posizione su CELL_SIZE è già in coordinate della vista.
func placement_ghost() -> PlacementGhostSnapshot3D:
	var snapshot := PlacementGhostSnapshot3D.new()
	var ghost := _game.get("_building_ghost") as BuildingGhost
	if ghost == null or not is_instance_valid(ghost):
		return snapshot
	var px := float(MicroCellRenderer.CELL_SIZE)
	var center := ghost.position / px
	var size := ghost._footprint_rect_px / px
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2.ONE
	for coords in (_game.get("live_cells") as Dictionary):
		var origin := cell_origin(coords)
		var local := center - origin
		if local.x < 0.0 or local.y < 0.0 or local.x >= World.WIDTH or local.y >= World.HEIGHT:
			continue
		snapshot.active = true
		snapshot.type_name = ghost.building_type_name
		snapshot.coords = coords
		snapshot.origin = origin
		snapshot.rect = Rect2(local - size / 2.0, size)
		snapshot.door_direction = TentShapes.direction_vector(ghost.rotation_dir)
		if ghost._footprint_door_px != Vector2.INF:
			snapshot.door_offset = ghost._footprint_door_px / px
		snapshot.buildable = ghost.is_buildable
		return snapshot
	return snapshot


# Spegne il movimento della camera 2D (tasti, bordo, rotella) mentre comanda il 3D.
func set_2d_camera_enabled(value: bool) -> void:
	var cam := _camera_2d()
	if cam != null:
		cam.set_process(value)
		cam.set_process_unhandled_input(value)
		# Tornando al 2D la tela del mondo torna quella della camera (align_2d_pointer l'aveva spostata).
		if value:
			cam.force_update_scroll()
