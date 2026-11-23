extends Node3D

# Schermi sotto i pannelli (2026-11-22, misura FPS con RenderDoc): la vista 3D disegna su tutta la finestra, anche sotto
# la sidebar e i cassetti aperti (SideDrawer, es. Assegnazione compiti), che coprono fino a un terzo dello schermo. Lì
# terreno, alberi e rocce pagavano luce e ombre per niente. Per ogni pannello aperto un rettangolo nero senza luce, figlio
# della camera, appena oltre il piano vicino: è la cosa più vicina, va per prima nella passata di profondità e tutto
# quello che sta dietro non passa il test di profondità, quindi non viene colorato. Non si vede (è sotto il pannello),
# non fa ombra e non tocca i click (la scelta col mouse non usa la grafica). Rifatto a ogni fotogramma: segue apertura,
# chiusura, spostamento dei pannelli e la misura della finestra.

# Stesso gruppo di CameraController.RIGHT_EDGE_COVER_GROUP (i cassetti laterali, SideDrawer).
const COVER_GROUP := &"camera_right_edge_cover"
const SIDEBAR_PATH := "CanvasLayer/Sidebar"
# Rientro in pixel per lato: gli angoli arrotondati e le cornici sottili dei pannelli non mostrano il nero.
const INSET_PX := 8.0
# Distanza dalla camera, in multipli del piano vicino (oltre il near, prima di qualsiasi cosa del mondo).
const NEAR_FACTOR := 1.5

var _quads: Array[MeshInstance3D] = []
var _material: StandardMaterial3D


func _init() -> void:
	name = "PanelOccluder3D"
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color.BLACK
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(_delta: float) -> void:
	var camera := get_parent() as Camera3D
	if camera == null:
		return
	var screen := get_viewport().get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var rects := _cover_rects()
	var depth := camera.near * NEAR_FACTOR
	var half_h := depth * tan(deg_to_rad(camera.fov) * 0.5)
	var half_w := half_h * screen.x / screen.y
	for i in range(rects.size()):
		var quad := _quad(i)
		var rect: Rect2 = rects[i]
		var center := rect.get_center()
		quad.position = Vector3((center.x / screen.x * 2.0 - 1.0) * half_w, (1.0 - center.y / screen.y * 2.0) * half_h, -depth)
		(quad.mesh as QuadMesh).size = Vector2(rect.size.x / screen.x * 2.0 * half_w, rect.size.y / screen.y * 2.0 * half_h)
		quad.visible = true
	for i in range(rects.size(), _quads.size()):
		_quads[i].visible = false


# Rettangoli a schermo dei pannelli aperti, già rientrati di INSET_PX.
func _cover_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var covers: Array = get_tree().get_nodes_in_group(COVER_GROUP)
	var scene := get_tree().current_scene
	var sidebar := scene.get_node_or_null(SIDEBAR_PATH) if scene != null else null
	if sidebar != null:
		covers.append(sidebar)
	for cover in covers:
		var control := cover as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect().grow(-INSET_PX)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			result.append(rect)
	return result


func _quad(index: int) -> MeshInstance3D:
	while _quads.size() <= index:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.material = _material
		quad.mesh = mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Mai scartato dal controllo d'inquadratura: è sempre davanti alla camera.
		quad.extra_cull_margin = 16384.0
		add_child(quad)
		_quads.append(quad)
	return _quads[index]
