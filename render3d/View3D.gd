class_name View3D
extends Node3D

# Vista 3D di debug di GameScene: si accende e si spegne col pulsante "3D" (View3DToggleButton). Solo da guardare:
# legge lo stato del gioco tramite GameStateReader e non scrive mai nella simulazione.
# Acceso: nasconde la mappa 2D (la UI resta), crea luce, camera e una Cell3D per ogni macrocella accesa, e le tiene
# allineate a ogni frame (celle che si accendono/spengono, centro che si sposta).
# Spento: libera tutto il 3D (costo zero) e rimette il 2D com'era.

signal active_changed(active: bool)

const GROUP := &"view_3d"
const HOVER_ENABLED := false

var active: bool = false

var _reader: GameStateReader
var _materials: Materials3D
var _world_root: Node3D
var _camera: Camera3DController
var _cells: Dictionary = {} # Vector2i -> Cell3D
# Edificio sotto il mouse ({"coords", "id"}, vuoto = nessuno), aggiornato in _input.
var _hovered_building: Dictionary = {}
# Anteprima del piazzamento di un edificio (segue il mouse, non sta in una cella).
var _placement_ghost: PlacementGhost3D
# Icone dei lavori sotto il nome delle zone (sullo schermo).
var _work_area_icons: WorkAreaIcons3D


func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)


func toggle() -> void:
	if active:
		deactivate()
	else:
		activate()


func activate() -> void:
	if active:
		return
	var game := get_parent() as Node2D
	if game == null:
		push_warning("View3D: il genitore deve essere la scena di gioco 2D.")
		return
	_reader = GameStateReader.new(game)
	_materials = Materials3D.new()
	_world_root = Node3D.new()
	_world_root.name = "World3D"
	add_child(_world_root)
	_world_root.add_child(Lighting3D.new())
	_camera = Camera3DController.new()
	_camera.name = "Camera3D"
	_world_root.add_child(_camera)
	_camera.setup(_reader)
	_camera.make_current()
	_placement_ghost = PlacementGhost3D.new()
	_placement_ghost.name = "PlacementGhost"
	_world_root.add_child(_placement_ghost)
	_work_area_icons = WorkAreaIcons3D.new()
	_work_area_icons.name = "WorkAreaIcons"
	_world_root.add_child(_work_area_icons)

	_reader.set_2d_visible(false)
	_reader.set_2d_camera_enabled(false)
	active = true
	_sync_cells()
	set_process(true)
	active_changed.emit(true)


func deactivate() -> void:
	if not active:
		return
	set_process(false)
	active = false
	_cells.clear()
	if _world_root != null:
		_world_root.queue_free()
		_world_root = null
	_camera = null
	_placement_ghost = null
	_work_area_icons = null
	_reader.set_2d_visible(true)
	_reader.set_2d_camera_enabled(true)
	_reader = null
	active_changed.emit(false)


func _process(_delta: float) -> void:
	# Anche a mouse fermo la vista può muoversi (tasti, bordo): la mappa 2D resta allineata al puntatore, così ciò che il
	# gioco segue a ogni fotogramma (trascinamento delle zone, anteprima del piazzamento) resta sotto il mouse.
	var screen := get_viewport().get_mouse_position()
	var ground: Variant = _camera.ground_point(screen) if _camera != null else null
	if ground != null:
		_reader.align_2d_pointer(screen, ground)
	_sync_cells()
	# Anteprima del piazzamento: il gioco la tiene sotto il puntatore allineato; qui solo disegnata.
	_placement_ghost.update(_reader.placement_ghost())
	# Icone dei lavori delle zone: seguono a ogni fotogramma la scritta della loro zona sullo schermo.
	var labels: Array = []
	for coords in _cells:
		labels.append_array((_cells[coords] as Cell3D).work_area_labels())
	_work_area_icons.update(labels, _camera)


# Click nel 3D (2026-11-19): a ogni evento del mouse la mappa 2D nascosta si allinea al punto del terreno sotto il
# puntatore, prima che il gioco legga l'evento (_input viene prima di _unhandled_input). Le selezioni restano del gioco.
func _input(event: InputEvent) -> void:
	if not active or _camera == null or not (event is InputEventMouse):
		return
	var screen := (event as InputEventMouse).position
	var ground: Variant = _camera.ground_point(screen)
	if ground != null:
		_reader.align_2d_pointer(screen, ground)
	# Edificio sotto il mouse: contorno leggero (passaggio del mouse). Spento il 2026-11-19 (richiesta utente: c'era solo
	# sugli edifici, incoerente e fastidioso); true per riaccenderlo.
	if HOVER_ENABLED and event is InputEventMouseMotion:
		_hovered_building = _reader.building_at(ground) if ground != null else {}


# Celle 3D = celle accese del gioco: crea le nuove, toglie quelle spente, riposiziona le altre (il centro può cambiare).
func _sync_cells() -> void:
	var live := {}
	for coords in _reader.live_cell_coords():
		live[coords] = true
	for coords in _cells.keys():
		if not live.has(coords):
			(_cells[coords] as Cell3D).queue_free()
			_cells.erase(coords)
	for coords in live:
		if _cells.has(coords):
			(_cells[coords] as Cell3D).place(_reader.cell_origin(coords))
			continue
		var source := _reader.cell_source(coords)
		if source == null:
			continue
		var cell := Cell3D.new()
		cell.build(source, _materials)
		_world_root.add_child(cell)
		_cells[coords] = cell
	var grid_visible := _reader.grid_visible()
	for coords in _cells:
		var cell: Cell3D = _cells[coords]
		# Griglia: segue l'opzione del gioco anche mentre si è in 3D.
		cell.set_grid_visible(grid_visible, _materials)
		# Rocce e sassi: rifatti quando il gioco li cambia.
		var stone_signature := _reader.stone_signature(coords)
		if cell.needs_refresh(&"stones", stone_signature):
			cell.refresh_stones(_reader.stone_snapshot(coords), stone_signature, _materials)
		# Suoli: prato dove c'è erba, sottobosco sotto alberi e cespugli, ghiaia sotto le rocce, terra altrove.
		var cover_signature := _reader.ground_cover_signature(coords)
		if cell.needs_refresh(&"ground_cover", cover_signature):
			cell.refresh_ground_cover(_reader.ground_cover_snapshot(coords), cover_signature)
		# Alberi: rifatti quando cambia l'elenco del 2D (nascite, tagli, nebbia) o l'anno.
		var tree_signature := _reader.tree_signature(coords)
		if cell.needs_refresh(&"trees", tree_signature):
			cell.refresh_trees(_reader.tree_snapshot(coords), tree_signature, _materials)
		# Cespugli (macchie, rovi da frutto, tagliati): come gli alberi.
		var shrub_signature := _reader.shrub_signature(coords)
		if cell.needs_refresh(&"shrubs", shrub_signature):
			cell.refresh_shrubs(_reader.shrub_snapshot(coords), shrub_signature, _materials)
		# Focolari: rifatti quando cambia l'elenco degli edifici del 2D o lo stato di un focolare (acceso, braci, spento).
		var hearth_signature := _reader.hearth_signature(coords)
		if cell.needs_refresh(&"hearths", hearth_signature):
			cell.refresh_hearths(_reader.hearth_snapshot(coords), hearth_signature, _materials)
		# Siti di deposito (per ora solo lo spiazzo di terra battuta): rifatti quando cambia l'elenco degli edifici.
		var buildings_signature := _reader.buildings_signature(coords)
		if cell.needs_refresh(&"deposit_sites", buildings_signature):
			cell.refresh_deposit_sites(_reader.building_places(coords, "deposit_site"), buildings_signature, _materials)
		# Mucchietti delle scorte (un segnaposto per posto occupato del magazzino): rifatti quando cambia un posto.
		var piles := _reader.storage_piles(coords)
		var piles_signature := piles.signature()
		if cell.needs_refresh(&"storage_piles", piles_signature):
			cell.refresh_storage_piles(piles, piles_signature, _materials)
		# Terra battuta (l'edificio): mattonelle come nel 2D; in cantiere compare man mano col lavoro.
		var dirt_signature := _reader.dirt_ground_signature(coords)
		if cell.needs_refresh(&"dirt_ground", dirt_signature):
			cell.refresh_dirt_ground(_reader.dirt_ground_tiles(coords), dirt_signature)
		# Cerchi di sassi: come i depositi.
		if cell.needs_refresh(&"pebble_circles", buildings_signature):
			cell.refresh_pebble_circles(_reader.building_places(coords, "pebble_circle"), buildings_signature, _materials)
		# Aree di lavoro (layer acceso, zona selezionata, scelta della zona, trascinamento): come nel 2D.
		var areas := _reader.work_areas(coords)
		var areas_signature := areas.signature()
		if cell.needs_refresh(&"work_areas", areas_signature):
			cell.refresh_work_areas(areas, areas_signature)
		# Selezione (dal 2D) e edificio sotto il mouse: alone a terra, riquadro, contorno sui modelli.
		var hovered_id: int = int(_hovered_building.get("id", -1)) if _hovered_building.get("coords") == coords else -1
		var selection := _reader.selection(coords, hovered_id)
		var selection_signature := selection.signature()
		if cell.needs_refresh(&"selection", selection_signature):
			cell.refresh_selection(selection, selection_signature)
		# Edifici con modello Blender (tenda di rami): rifatti anche quando la fase del cantiere cambia.
		var models_signature := _reader.building_models_signature(coords)
		if cell.needs_refresh(&"building_models", models_signature):
			cell.refresh_building_models(_reader.building_models(coords), models_signature)
