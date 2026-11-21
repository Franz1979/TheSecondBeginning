extends Node3D

# SCENA DI PROVA (2026-11-20, richiesta utente): quante latifoglie Quaternius (CommonTree, foglie con trasparenza) regge
# la scheda video prima di bloccarsi. Fuori dalla partita: niente salvataggi, niente gioco, solo alberi su un prato.
# Stessa luce della vista 3D (Lighting3D: ombre, SSAO), stessi modelli e stesso MultiMesh di Trees3D.
#
# Tasti:
#   Freccia SU / GIÙ  più o meno alberi, un passo alla volta (STEPS)
#   A                 foglie con trasparenza (come il modello) / foglie opache (stesso modello, alpha spento)
#   S                 ombre del sole sì / no
#   D                 ombre "piene" (come oggi in Lighting3D: 4 suddivisioni fino a 300) / ombre "vicine" (2 suddivisioni,
#                     solo fino a poco oltre il punto guardato, distanza che segue lo zoom, bordo sfumato)
#   C                 alberi in blocchi 10 x 10 (un MultiMesh per blocco, scartati se fuori vista) / MultiMesh unico
#   L                 soglia LOD (versioni semplificate dei modelli, generate all'import): 1 -> 4 -> 8 -> 16 pixel di errore
#                     ammesso (più alta = alberi lontani più semplici prima)
#   O                 SSAO (ombreggiatura ambientale negli angoli) sì / no
#   R                 risoluzione 3D 100% -> 75% -> 50% (FSR ingrandisce; scritte e pannelli restano nitidi)
#   rotellina         telecamera più vicina / più lontana (da vicino le foglie coprono più schermo)
# A ogni cambio scrive una riga [PROVA ALBERI] nell'output: se il PC si blocca, l'ultima riga dice a che punto.
# Lancio: F6 su questa scena nell'editor, oppure
#   Godot_v4.6.3-stable_win64_console.exe --path <game> res://render3d/tests/TreeStressTest.tscn

const STEPS := [0, 10, 25, 50, 100, 150, 200, 250, 300, 350]
const MODEL_DIR := "res://render3d/assets/models/vegetation/common_trees/"
const MODELS := ["commontree_1", "commontree_2", "commontree_3", "commontree_4", "commontree_5"]
const MODEL_HEIGHT := 8.15 # m, media dei 5 modelli
const TREE_HEIGHT := 2.2 # unità del 3D (microcelle): un albero adulto in gioco
const AREA := 100.0 # una macrocella (100 x 100 microcelle), come in partita
const FOV_DEG := 32.0 # come Camera3DController
const PITCH_DEG := 45.0
# Ombre vicine: fin dove arrivano oltre il punto guardato (in unità del 3D) e da che frazione della distanza sfumano.
const NEAR_SHADOW_MARGIN := 30.0
const NEAR_SHADOW_FADE_START := 0.6

var _step := STEPS.size() - 1 # parte da 350: con Vulkan regge (prova del 2026-11-20)
var _near_shadows := false
const RESOLUTION_SCALES := [1.0, 0.75, 0.5]
var _resolution_index := 0
const CHUNK_SIZE := 10.0 # unità del 3D (microcelle): blocchi 10 x 10, 100 per macrocella
var _chunked := false
const LOD_THRESHOLDS := [1.0, 4.0, 8.0, 16.0]
var _lod_index := 0
var _chunk_count := 1
var _environment: Environment
var _full_shadow_distance := 300.0
var _full_shadow_mode := DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
var _full_shadow_fade := 0.8
var _alpha := true
var _distance := 120.0
var _meshes_alpha: Array = []
var _meshes_opaque: Array = []
var _triangles: Array = []
var _positions: Array = [] # [Transform3D, variante] per l'albero i, fissi: stessi alberi a ogni passo
var _sun: DirectionalLight3D
var _camera: Camera3D
var _forest: Node3D
var _label: Label
var _frames := 0
var _fps_time := 0.0


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)

	var lighting := Lighting3D.new()
	add_child(lighting)
	_sun = lighting.get_node("Sun") as DirectionalLight3D
	_environment = (lighting.get_node("WorldEnvironment") as WorldEnvironment).environment
	_full_shadow_distance = _sun.directional_shadow_max_distance
	_full_shadow_mode = _sun.directional_shadow_mode
	_full_shadow_fade = _sun.directional_shadow_fade_start

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(AREA * 1.6, AREA * 1.6)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("5e7a3a")
	ground.material_override = ground_material
	add_child(ground)

	_camera = Camera3D.new()
	_camera.fov = FOV_DEG
	add_child(_camera)
	_camera.make_current()
	_place_camera()

	for model_name in MODELS:
		var mesh := ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".gltf")
		_meshes_alpha.append(mesh)
		_meshes_opaque.append(_opaque_copy(mesh))
		_triangles.append(_count_triangles(mesh))

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(STEPS[STEPS.size() - 1]):
		var size := TREE_HEIGHT / MODEL_HEIGHT * rng.randf_range(0.8, 1.15)
		var tree_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
		var origin := Vector3(rng.randf_range(-AREA / 2, AREA / 2), 0.0, rng.randf_range(-AREA / 2, AREA / 2))
		_positions.append([Transform3D(tree_basis, origin), rng.randi() % MODELS.size()])

	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:
				_step = mini(_step + 1, STEPS.size() - 1)
				_rebuild()
			KEY_DOWN:
				_step = maxi(_step - 1, 0)
				_rebuild()
			KEY_A:
				_alpha = not _alpha
				_rebuild()
			KEY_S:
				_sun.shadow_enabled = not _sun.shadow_enabled
				_rebuild()
			KEY_D:
				_near_shadows = not _near_shadows
				_apply_shadow_mode()
				_rebuild()
			KEY_L:
				_lod_index = (_lod_index + 1) % LOD_THRESHOLDS.size()
				get_viewport().mesh_lod_threshold = LOD_THRESHOLDS[_lod_index]
				_rebuild()
			KEY_C:
				_chunked = not _chunked
				_rebuild()
			KEY_O:
				_environment.ssao_enabled = not _environment.ssao_enabled
				_rebuild()
			KEY_R:
				_resolution_index = (_resolution_index + 1) % RESOLUTION_SCALES.size()
				var viewport := get_viewport()
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if _resolution_index > 0 else Viewport.SCALING_3D_MODE_BILINEAR
				viewport.scaling_3d_scale = RESOLUTION_SCALES[_resolution_index]
				_rebuild()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.88, 10.0)
			_place_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance / 0.88, 300.0)
			_place_camera()


func _process(delta: float) -> void:
	_frames += 1
	_fps_time += delta
	if _fps_time >= 1.0:
		_update_label()
		_frames = 0
		_fps_time = 0.0


func _rebuild() -> void:
	if _forest != null:
		_forest.free()
	var count: int = STEPS[_step]
	var transforms: Array = []
	for i in range(MODELS.size()):
		transforms.append([])
	for i in range(count):
		var entry: Array = _positions[i]
		transforms[entry[1]].append(entry[0])
	var meshes := _meshes_alpha if _alpha else _meshes_opaque
	if _chunked:
		# Un MultiMesh per blocco di CHUNK_SIZE x CHUNK_SIZE: Godot scarta da solo (inquadratura e ombre) i blocchi che non
		# si vedono, invece di disegnare sempre tutti gli alberi di un MultiMesh grande quanto la cella.
		_forest = Node3D.new()
		_forest.name = "Forest"
		var chunks: Dictionary = {} # Vector2i -> Array (per variante) di Array di Transform3D
		for v in range(transforms.size()):
			for t in transforms[v]:
				var key := Vector2i(floori((t as Transform3D).origin.x / CHUNK_SIZE), floori((t as Transform3D).origin.z / CHUNK_SIZE))
				if not chunks.has(key):
					var empty: Array = []
					for i in range(MODELS.size()):
						empty.append([])
					chunks[key] = empty
				chunks[key][v].append(t)
		for key in chunks:
			_forest.add_child(MultiMeshGroup3D.build("Chunk_%d_%d" % [key.x, key.y], meshes, chunks[key], null))
		_chunk_count = chunks.size()
	else:
		_forest = MultiMeshGroup3D.build("Forest", meshes, transforms, null)
		_chunk_count = 1
	add_child(_forest)
	print("[PROVA ALBERI] %d alberi, %d triangoli, foglie %s, ombre %s, %s, %s" % [
		count, _total_triangles(transforms), "trasparenti" if _alpha else "opache", "sì" if _sun.shadow_enabled else "no",
		_shadow_mode_text(), _extras_text()])
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	var count: int = STEPS[_step]
	_label.text = "Alberi: %d   FPS: %d\nFoglie: %s (A)   Ombre: %s (S)\nTipo ombre: %s (D)\n%s\nSU/GIÙ alberi, rotellina distanza (%.0f)" % [
		count, Engine.get_frames_per_second(), "trasparenti" if _alpha else "opache",
		"sì" if _sun.shadow_enabled else "no", _shadow_mode_text(), _extras_text(), _distance]


func _place_camera() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	_camera.position = Vector3(0.0, sin(pitch) * _distance, cos(pitch) * _distance)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_apply_shadow_mode()
	if _label != null:
		_update_label()


# Ombre vicine: la distanza massima segue lo zoom (distanza della telecamera dal punto guardato + un margine), così da
# vicino fanno ombra solo gli alberi attorno a quel punto e da lontano l'ombra copre ancora la zona inquadrata al centro.
func _apply_shadow_mode() -> void:
	if _sun == null:
		return
	if _near_shadows:
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun.directional_shadow_max_distance = _distance + NEAR_SHADOW_MARGIN
		_sun.directional_shadow_fade_start = NEAR_SHADOW_FADE_START
	else:
		_sun.directional_shadow_mode = _full_shadow_mode
		_sun.directional_shadow_max_distance = _full_shadow_distance
		_sun.directional_shadow_fade_start = _full_shadow_fade


func _extras_text() -> String:
	var ssao := _environment != null and _environment.ssao_enabled
	return "SSAO: %s (O)   Risoluzione 3D: %d%% (R)\nBlocchi: %s (C)   Soglia LOD: %d px (L)" % ["sì" if ssao else "no",
		int(RESOLUTION_SCALES[_resolution_index] * 100), ("sì, %d" % _chunk_count) if _chunked else "no, MultiMesh unico",
		int(LOD_THRESHOLDS[_lod_index])]


func _shadow_mode_text() -> String:
	if _near_shadows:
		return "vicine (fino a %.0f)" % (_distance + NEAR_SHADOW_MARGIN)
	return "piene (fino a %.0f)" % _full_shadow_distance


func _total_triangles(transforms: Array) -> int:
	var total := 0
	for i in range(transforms.size()):
		total += (transforms[i] as Array).size() * int(_triangles[i])
	return total


# Stesso modello con le foglie senza trasparenza: separa il costo dei triangoli da quello dei pixel trasparenti.
static func _opaque_copy(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in range(copy.get_surface_count()):
		var material := copy.surface_get_material(s) as BaseMaterial3D
		if material == null:
			continue
		var opaque := material.duplicate() as BaseMaterial3D
		opaque.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		opaque.cull_mode = BaseMaterial3D.CULL_BACK
		copy.surface_set_material(s, opaque)
	return copy


static func _count_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var triangles := 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices == null or (indices as PackedInt32Array).is_empty():
			triangles += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		else:
			triangles += (indices as PackedInt32Array).size() / 3
	return triangles
