class_name PileStickers3D
extends Node2D

# "Adesivi" dei mucchietti (2026-11-21, richiesta utente — stampella finché ogni risorsa non avrà il suo modello): le
# STESSE icone del 2D (DepositStorageIcons.draw_icon; senza icona, il pallino nel colore della risorsa come nel 2D)
# disegnate una volta sola in un'immagine (atlante, un riquadro per risorsa) e appoggiate a terra come quadratini piatti.
#
# Come: all'avvio un SubViewport con questo nodo dentro disegna tutte le icone; dopo RENDER_FRAMES fotogrammi l'immagine
# viene copiata (con le mipmap, niente sfarfallio da lontano) nella texture condivisa e il SubViewport si cancella, così
# non costa nulla a regime. Fino ad allora gli adesivi sono trasparenti (scartati dall'alpha scissor).
# Un materiale per risorsa (stessa texture, riquadro scelto con uv1_offset/uv1_scale): nessuno shader proprio.

const SLOT_PX := 64
# Margine trasparente attorno a ogni icona nel suo riquadro: le mipmap non mescolano le icone vicine.
const SLOT_MARGIN_PX := 4
const RENDER_FRAMES := 3
const FALLBACK_RADIUS := 0.28

static var _texture: ImageTexture = null
static var _slot_by_name: Dictionary = {}
static var _columns := 1
static var _meshes: Dictionary = {}

var _names: Array[String] = []
var _frames := 0


# Quadratino 1×1 sdraiato (faccia verso l'alto, alto dell'icona verso -Z come il nord del 2D) col materiale della risorsa.
static func mesh_for(resource_name: String) -> Mesh:
	if _meshes.has(resource_name):
		return _meshes[resource_name]
	_ensure_atlas()
	var slot: int = _slot_by_name.get(resource_name, -1)
	if slot < 0:
		return null
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var cell := 1.0 / float(_columns)
	material.uv1_scale = Vector3(cell, cell, 1.0)
	material.uv1_offset = Vector3(float(slot % _columns) * cell, float(slot / _columns) * cell, 0.0)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material
	_meshes[resource_name] = mesh
	return mesh


# Lato dell'adesivo rispetto al lato dell'icona: il riquadro comprende anche il margine trasparente.
static func slot_to_icon_ratio() -> float:
	return float(SLOT_PX) / float(SLOT_PX - 2 * SLOT_MARGIN_PX)


static func _ensure_atlas() -> void:
	if _texture != null:
		return
	var names := CaloricCalculator.list_secondary_resource_names()
	names.sort()
	for i in range(names.size()):
		_slot_by_name[names[i]] = i
	_columns = maxi(1, ceili(sqrt(float(names.size()))))
	var side := _columns * SLOT_PX
	var blank := Image.create(side, side, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(blank)
	var viewport := SubViewport.new()
	viewport.name = "PileStickersAtlas"
	viewport.size = Vector2i(side, side)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var painter := PileStickers3D.new()
	painter._names = names
	viewport.add_child(painter)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child.call_deferred(viewport)


func _draw() -> void:
	var inner := float(SLOT_PX - 2 * SLOT_MARGIN_PX)
	for i in range(_names.size()):
		var top_left := Vector2(float(i % _columns) * SLOT_PX + SLOT_MARGIN_PX, float(i / _columns) * SLOT_PX + SLOT_MARGIN_PX)
		if not DepositStorageIcons.draw_icon(self, _names[i], top_left, inner):
			draw_circle(top_left + Vector2(inner, inner) * 0.5, inner * FALLBACK_RADIUS, IconRegistry.get_resource_color(_names[i]))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < RENDER_FRAMES:
		return
	set_process(false)
	var viewport := get_viewport() as SubViewport
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	_texture.set_image(image)
	viewport.queue_free()
