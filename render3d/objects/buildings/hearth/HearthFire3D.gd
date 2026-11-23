class_name HearthFire3D
extends Node3D

# UN focolare nella vista 3D, in uno dei tre stati di HearthSnapshot3D:
# - acceso: anello di pietre, legna a capanna, braci che brillano, fiamma (flame.gdshader), scintille, fumo e luce calda
#   che tremola;
# - braci: legna annerita, braci che pulsano piano, un filo di fumo e una luce debole;
# - spento: legna nera crollata e cenere fredda.
# Sotto, in ogni stato, una chiazza di terra bruciata e cenere proiettata sul terreno (Decal).
# Misura: largo al massimo un terzo della microcella (richiesta utente: il focolare sta al centro e la gente ci sta
# intorno). Tutto è disegnato per un focolare "di riferimento" largo circa una microcella e poi ridotto di SIZE: i pezzi
# fissi stanno sotto un nodo scalato, mentre fumo, scintille e luce (che non seguono la scala) hanno le misure
# moltiplicate a mano. Base al centro del focolare, a terra.

const SIZE := 0.34
const SCALE := 1.5
const RING_RADIUS := 0.26 * SCALE
const STONE_COUNT := 8
const STONE_SIZE := 0.06 * SCALE
const STONE_VARIANTS := 4
const STONE_COLOR := Color("5a5550")
const LOG_COUNT := 4
const LOG_LENGTH := 0.42
const LOG_RADIUS := 0.03
const LOG_COLOR := Color("5b4532")
const LOG_COLOR_CHARRED := Color("3a2a20")
const LOG_COLOR_OUT := Color("2a2420")
const ASH_SIZE := 1.3
const ASH_TEXTURE_SIZE := 128
# Gli oggetti del focolare stanno su un livello a parte, così la cenere (Decal) si proietta solo sul terreno.
const OBJECT_LAYER := 2
const TERRAIN_LAYERS := 1

# Luce del fuoco (2026-11-21, richiesta utente: era troppo forte, "agghiacciante"): acceso 0,8 (era 1,6, tremolio ±0,2
# invece di ±0,5), braci al massimo 0,4 (era 0,6), arancio meno saturo, e da acceso un po' più in alto (era 0,3) perché
# non faccia una macchia accecante a terra vicino al fuoco.
# Pietre e legna dai modelli Blender (2026-11-21, richiesta utente; SOURCES_PER_GIOCO/blender/scripts/campfire.py): l'anello e
# una legna per stato. false = i pezzi fatti a codice di prima (_add_stones, _add_logs). Il cantiere sta in
# BuildingModels3D.MODELS["campfire"].
const USE_MODELS := true
const STONES_MODEL := "campfire_pietre"
const LOG_MODELS := {
	HearthSnapshot3D.BURNING: "campfire_legna_accesa",
	HearthSnapshot3D.EMBERS: "campfire_legna_braci",
	HearthSnapshot3D.OUT: "campfire_legna_spenta",
}

# Luce: acceso 0,64 (2026-11-21, richiesta utente: era 1,6, poi 0,8, poi ancora -20%), tremolio ±25% come prima;
# braci al massimo 0,4, con un colore rosso brace (LIGHT_COLOR_EMBERS, richiesta utente) invece dell'arancio del fuoco.
# Poi (stesso giorno) la macchia bianca accecante sulla terra vicino al fuoco: veniva dall'attenuazione 2 (luce tutta
# concentrata al centro). Da acceso: attenuazione morbida (LIGHT_ATTENUATION_BURNING), luce più in alto, forza 0,5. Le
# braci restano com'erano (piaciute): attenuazione 2, 0,4.
const LIGHT_BURNING := 0.5
const LIGHT_ATTENUATION_BURNING := 0.8
const LIGHT_EMBERS := 0.4
const LIGHT_COLOR := Color(1.0, 0.68, 0.42)
const LIGHT_COLOR_EMBERS := Color(1.0, 0.32, 0.14)
const LIGHT_HEIGHT := 0.9

const FLAME_SHADER_PATH := "res://render3d/objects/buildings/hearth/flame.gdshader"
const EMBER_SHADER_PATH := "res://render3d/objects/buildings/hearth/ember.gdshader"

static var _stone_meshes: Array = []
static var _ash_texture: ImageTexture
static var _log_materials: Dictionary = {}

var _state: int = HearthSnapshot3D.OUT
var _light: OmniLight3D
# Pezzi fissi (cenere, pietre, legna, braci, fiamme), scalati di SIZE.
var _body: Node3D
var _time := 0.0


# with_stones = false: senza l'anello di pietre, già nel modello dell'edificio (affumicatoio, 2026-11-22).
func setup(state: int, hearth_seed: int, vertex_material: Material, with_stones: bool = true) -> void:
	_state = state
	name = "Hearth"
	_body = Node3D.new()
	_body.name = "Body"
	_body.scale = Vector3.ONE * SIZE
	add_child(_body)
	_add_ash()
	if USE_MODELS:
		_add_models(hearth_seed, with_stones)
	else:
		if with_stones:
			_add_stones(hearth_seed, vertex_material)
		_add_logs(hearth_seed)
	_add_embers()
	if state == HearthSnapshot3D.BURNING:
		_add_flames(hearth_seed)
		_add_sparks()
		_add_smoke(10, 0.32, 0.6)
		_add_light(LIGHT_BURNING, 2.4, true)
	elif state == HearthSnapshot3D.EMBERS:
		_add_smoke(5, 0.18, 0.35)
		_add_light(LIGHT_EMBERS, 1.1, false)


# Godot accende _process quando il nodo entra in scena: va spento qui (lo spento non ha luce da far tremolare).
func _ready() -> void:
	set_process(_light != null)


func _process(delta: float) -> void:
	if _light == null:
		return
	_time += delta
	if _state == HearthSnapshot3D.BURNING:
		_light.light_energy = LIGHT_BURNING * (1.0 + 0.15 * sin(_time * 11.0) + 0.1 * sin(_time * 17.7))
	else:
		_light.light_energy = LIGHT_EMBERS * (0.6 + 0.4 * (0.5 + 0.5 * sin(_time * 1.6)))


func _add_ash() -> void:
	var decal := Decal.new()
	decal.name = "Ash"
	decal.size = Vector3(ASH_SIZE, 0.8, ASH_SIZE)
	decal.texture_albedo = _get_ash_texture()
	decal.cull_mask = TERRAIN_LAYERS
	_body.add_child(decal)


func _add_stones(hearth_seed: int, vertex_material: Material) -> void:
	_ensure_stone_meshes()
	var rng := RandomNumberGenerator.new()
	rng.seed = hearth_seed
	for i in range(STONE_COUNT):
		var angle := TAU * i / STONE_COUNT + rng.randf_range(-0.12, 0.12)
		var stone := MeshInstance3D.new()
		stone.mesh = _stone_meshes[rng.randi_range(0, STONE_VARIANTS - 1)]
		stone.material_override = vertex_material
		stone.layers = OBJECT_LAYER
		var size := STONE_SIZE * rng.randf_range(0.9, 1.25)
		stone.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.85, size * 1.1)),
			Vector3(cos(angle) * RING_RADIUS, -0.01, sin(angle) * RING_RADIUS))
		_body.add_child(stone)


# Pietre e legna dai modelli Blender: l'anello sempre uguale, la legna dello stato girata di un angolo proprio del
# focolare. Fuori dal nodo scalato di SIZE: i modelli sono già in metri (x MODEL_SCALE). Livello degli oggetti, come prima.
func _add_models(hearth_seed: int, with_stones: bool = true) -> void:
	var logs: String = LOG_MODELS.get(_state, LOG_MODELS[HearthSnapshot3D.OUT])
	var turn := float(posmod(hearth_seed, 628)) / 100.0
	var pieces: Array = [[logs, turn]]
	if with_stones:
		pieces.push_front([STONES_MODEL, 0.0])
	for entry in pieces:
		var mesh := ModelMesh3D.load_mesh(BuildingModels3D.MODEL_DIR + String(entry[0]) + ".glb")
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.layers = OBJECT_LAYER
		instance.lod_bias = BuildingModels3D.NO_LOD_BIAS
		instance.transform = Transform3D(Basis(Vector3.UP, float(entry[1])).scaled(Vector3.ONE * BuildingModels3D.MODEL_SCALE), Vector3.ZERO)
		add_child(instance)


# Legna a capanna (acceso, braci) o crollata a terra (spento).
func _add_logs(hearth_seed: int) -> void:
	var color := LOG_COLOR
	if _state == HearthSnapshot3D.EMBERS:
		color = LOG_COLOR_CHARRED
	elif _state == HearthSnapshot3D.OUT:
		color = LOG_COLOR_OUT
	var mesh := CylinderMesh.new()
	mesh.top_radius = LOG_RADIUS * 0.85
	mesh.bottom_radius = LOG_RADIUS
	mesh.height = LOG_LENGTH
	mesh.radial_segments = 6
	mesh.rings = 1
	var collapsed := _state == HearthSnapshot3D.OUT
	var elevation := 0.08 if collapsed else 0.55
	var phase := float(posmod(hearth_seed, 628)) / 100.0
	for i in range(LOG_COUNT):
		var angle := phase + TAU * i / LOG_COUNT
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		# Asse del legno: dal bordo verso il centro, in salita.
		var axis := (-outward * cos(elevation) + Vector3.UP * sin(elevation)).normalized()
		var side := axis.cross(Vector3.UP).normalized()
		var basis := Basis(side, axis, side.cross(axis))
		var middle := outward * (0.1 if not collapsed else 0.06) + Vector3.UP * (sin(elevation) * LOG_LENGTH * 0.5 * 0.85 + 0.01)
		var log_instance := MeshInstance3D.new()
		log_instance.mesh = mesh
		log_instance.material_override = _get_log_material(color)
		log_instance.layers = OBJECT_LAYER
		log_instance.transform = Transform3D(basis, middle)
		_body.add_child(log_instance)


func _add_embers() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := ShaderMaterial.new()
	material.shader = load(EMBER_SHADER_PATH)
	match _state:
		HearthSnapshot3D.BURNING:
			material.set_shader_parameter("glow", 1.2)
			material.set_shader_parameter("flicker", 1.0)
		HearthSnapshot3D.EMBERS:
			material.set_shader_parameter("glow", 1.0)
			material.set_shader_parameter("pulse_amount", 0.6)
			# Più rosso del fuoco acceso (2026-11-21, richiesta utente).
			material.set_shader_parameter("glow_color", Color(0.9, 0.12, 0.03))
		_:
			material.set_shader_parameter("glow", 0.0)
			material.set_shader_parameter("char_color", Color(0.22, 0.21, 0.2))
	var embers := MeshInstance3D.new()
	embers.name = "Embers"
	embers.mesh = mesh
	embers.material_override = material
	embers.layers = OBJECT_LAYER
	embers.scale = Vector3(1.0, 0.25, 1.0)
	embers.position = Vector3(0.0, 0.0, 0.0)
	_body.add_child(embers)


func _add_flames(hearth_seed: int) -> void:
	var shader: Shader = load(FLAME_SHADER_PATH)
	# Una fiamma grande e una più piccola davanti, con un altro seme: lingue che non si ricalcano.
	for k in range(2):
		var size := Vector2(0.42, 0.62) if k == 0 else Vector2(0.3, 0.44)
		var quad := QuadMesh.new()
		quad.size = size
		quad.center_offset = Vector3(0.0, size.y * 0.5, 0.0)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("seed", float(posmod(hearth_seed + k * 97, 1000)) / 100.0)
		material.set_shader_parameter("intensity", 1.4 if k == 0 else 1.1)
		var flame := MeshInstance3D.new()
		flame.name = "Flame%d" % k
		flame.mesh = quad
		flame.material_override = material
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.layers = OBJECT_LAYER
		flame.position = Vector3(0.0, 0.03, 0.0)
		_body.add_child(flame)


func _add_sparks() -> void:
	var particles := CPUParticles3D.new()
	particles.name = "Sparks"
	particles.amount = 14
	particles.lifetime = 1.3
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.08 * SIZE
	particles.direction = Vector3.UP
	particles.spread = 18.0
	particles.initial_velocity_min = 0.5 * SIZE
	particles.initial_velocity_max = 0.9 * SIZE
	particles.gravity = Vector3(0.0, 0.15 * SIZE, 0.0)
	particles.position = Vector3(0.0, 0.2 * SIZE, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.022) * maxf(SIZE, 0.6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	quad.material = material
	particles.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	particles.color_ramp = ramp
	particles.layers = OBJECT_LAYER
	add_child(particles)


func _add_smoke(amount: int, opacity: float, velocity: float) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "Smoke"
	particles.amount = amount
	particles.lifetime = 3.5
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.06 * SIZE
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.initial_velocity_min = velocity * 0.7 * SIZE
	particles.initial_velocity_max = velocity * SIZE
	particles.gravity = Vector3(0.08, 0.05, 0.0) * SIZE
	particles.damping_min = 0.1
	particles.damping_max = 0.2
	particles.position = Vector3(0.0, (0.45 if _state == HearthSnapshot3D.BURNING else 0.1) * SIZE, 0.0)
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(1.0, 1.0))
	particles.scale_amount_curve = scale_curve
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.12 * SIZE
	mesh.height = 0.24 * SIZE
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.shadow_to_opacity = false
	mesh.material = material
	particles.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.53, 0.5, 0.0))
	ramp.set_color(1, Color(0.6, 0.58, 0.56, 0.0))
	ramp.add_point(0.25, Color(0.5, 0.48, 0.46, opacity))
	particles.color_ramp = ramp
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.layers = OBJECT_LAYER
	add_child(particles)


func _add_light(energy: float, light_range: float, shadows: bool) -> void:
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = LIGHT_COLOR
	_light.light_energy = energy
	_light.omni_range = light_range * SIZE * 1.6
	_light.omni_attenuation = LIGHT_ATTENUATION_BURNING if shadows else 2.0
	_light.shadow_enabled = shadows
	_light.position = Vector3(0.0, (LIGHT_HEIGHT if shadows else 0.12) * SIZE, 0.0)
	if not shadows:
		_light.light_color = LIGHT_COLOR_EMBERS
	add_child(_light)


static func _ensure_stone_meshes() -> void:
	if not _stone_meshes.is_empty():
		return
	for variant in range(STONE_VARIANTS):
		_stone_meshes.append(FacetedStoneMesh.build(1.0, 0.9, 6, 0.3, 300 + variant, STONE_COLOR))


static func _get_log_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _log_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_log_materials[key] = material
	return _log_materials[key]


# Chiazza di cenere: scura al centro, terra bruciata attorno, bordo che sfuma mosso da un rumore, granelli chiari.
static func _get_ash_texture() -> ImageTexture:
	if _ash_texture != null:
		return _ash_texture
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = 4243
	var size := ASH_TEXTURE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(center) / (size * 0.5)
			d += noise.get_noise_2d(x, y) * 0.18
			var alpha := 1.0 - smoothstep(0.55, 0.98, d)
			var color := Color(0.17, 0.15, 0.14).lerp(Color(0.42, 0.34, 0.24), smoothstep(0.15, 0.75, d))
			if d < 0.5 and rng.randf() < 0.06:
				color = color.lerp(Color(0.62, 0.6, 0.57), 0.6)
			color.a = alpha * 0.95
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	_ash_texture = ImageTexture.create_from_image(image)
	return _ash_texture
