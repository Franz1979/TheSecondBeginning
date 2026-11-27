class_name TerrainWeightsBaker3D
extends Node

# Cottura dei pesi del terreno (2026-11-27, misura FPS: nella passata opaca il terreno costava ~10 ms, di cui ~2,8 i 7
# rumori dei bordi). Per ogni cella accesa disegna UNA volta, con la GPU, la parte liscia dei bordi tra i suoli
# (terrain_weights_bake.gdshader, stesse formule del terreno) in due immagini da 400x400 (4 punti per microcella), le
# rilegge, ci fa le mipmap (da lontano niente sfarfallio) e le dà al materiale della cella (TerrainMaterial3D.
# set_baked_weights): da lì lo shader del terreno legge 2 immagini invece dei rumori e della maschera dei suoli.
# Ricotta solo quando cambiano i suoli o la terra battuta (Cell3D.refresh_ground_cover / refresh_dirt_ground); nebbia,
# stagione, ruscello e argilla restano dal vivo nello shader e non la toccano.
# Una cella per fotogramma, così la vista che si accende non dà uno scatto solo. Uno solo per tutta la vista (View3D),
# raggiungibile dalle celle con request(): senza cuoco (o con TerrainMaterial3D.BAKED_WEIGHTS_ENABLED false) le celle
# restano col calcolo dal vivo, uguale.

const BAKE_SHADER := preload("res://render3d/objects/terrain/terrain_weights_bake.gdshader")
# Punti per microcella dell'immagine cotta.
const POINTS_PER_MICROCELL := 4

static var _instance: TerrainWeightsBaker3D

var _viewport: SubViewport
var _material: ShaderMaterial
# Celle in attesa (Cell3D -> true), nell'ordine delle richieste.
var _pending: Dictionary = {}
var _busy := false


# Chiede (o richiede) la cottura della cella; più richieste prima della cottura valgono una.
static func request(cell: Cell3D) -> void:
	if _instance != null and TerrainMaterial3D.BAKED_WEIGHTS_ENABLED:
		_instance._pending[cell] = true


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	var side := World.WIDTH * POINTS_PER_MICROCELL
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(side * 2, side)
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_material = ShaderMaterial.new()
	_material.shader = BAKE_SHADER
	_material.set_shader_parameter("cell_size", float(World.WIDTH))
	var rect := ColorRect.new()
	rect.size = Vector2(side * 2, side)
	rect.material = _material
	_viewport.add_child(rect)
	add_child(_viewport)


func _process(_delta: float) -> void:
	if not _busy and not _pending.is_empty():
		_bake_next()


func _bake_next() -> void:
	var cell: Cell3D = _pending.keys()[0]
	_pending.erase(cell)
	if not is_instance_valid(cell) or cell._terrain_material == null:
		return
	_busy = true
	var source := cell._terrain_material
	_material.set_shader_parameter("edge_noise", source.get_shader_parameter("edge_noise"))
	_material.set_shader_parameter("cover_mask", source.get_shader_parameter("cover_mask"))
	_material.set_shader_parameter("beaten_mask", source.get_shader_parameter("beaten_mask"))
	_material.set_shader_parameter("cell_origin", source.get_shader_parameter("cell_origin"))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_busy = false
	if not is_instance_valid(cell) or _pending.has(cell):
		return # cella spenta, o cambiata di nuovo nel frattempo: la cottura buona è quella dopo
	var image := _viewport.get_texture().get_image()
	if image == null:
		return
	image.convert(Image.FORMAT_RGBA8)
	var side := image.get_height()
	var weights_a := image.get_region(Rect2i(0, 0, side, side))
	var weights_b := image.get_region(Rect2i(side, 0, side, side))
	weights_a.generate_mipmaps()
	weights_b.generate_mipmaps()
	TerrainMaterial3D.set_baked_weights(cell._terrain_material, weights_a, weights_b)
