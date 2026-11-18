class_name View3D
extends Node3D

# Vista 3D di debug di GameScene: si accende e si spegne col pulsante "3D" (View3DToggleButton). Solo da guardare:
# legge lo stato del gioco tramite GameStateReader e non scrive mai nella simulazione.
# Acceso: nasconde la mappa 2D (la UI resta), crea luce, camera e una Cell3D per ogni macrocella accesa, e le tiene
# allineate a ogni frame (celle che si accendono/spengono, centro che si sposta).
# Spento: libera tutto il 3D (costo zero) e rimette il 2D com'era.

signal active_changed(active: bool)

const GROUP := &"view_3d"

var active: bool = false

var _reader: GameStateReader
var _materials: Materials3D
var _world_root: Node3D
var _camera: Camera3DController
var _cells: Dictionary = {} # Vector2i -> Cell3D


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
	_reader.set_2d_visible(true)
	_reader.set_2d_camera_enabled(true)
	_reader = null
	active_changed.emit(false)


func _process(_delta: float) -> void:
	_sync_cells()


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
		if cell.needs_stone_refresh(stone_signature):
			cell.refresh_stones(_reader.stone_snapshot(coords), stone_signature, _materials)
