class_name Lighting3D
extends Node3D

# Luce e atmosfera della vista 3D: sole caldo obliquo con ombre morbide, occlusione ambientale (angoli più scuri),
# bagliore leggero, tonemap ACES e colori pieni. Niente nebbia (spegneva i colori). Per ora luce di giorno fissa; ora e
# stagione arriveranno dopo.

const SUN_COLOR := Color("ffe6bd")
const SUN_ENERGY := 1.2
# Sole da sinistra-dietro, alto 50°.
const SUN_ROTATION_DEG := Vector3(-50.0, -60.0, 0.0)
const SKY_COLOR := Color("a9c8dc")
# Ambiente un po' freddo e debole: ombre fresche e marcate, come nel bozzetto.
const AMBIENT_COLOR := Color("a9b8cc")
const AMBIENT_ENERGY := 0.35


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	# Bagliore solo per ciò che è davvero luminoso (fuochi di notte, più avanti).
	environment.glow_intensity = 0.2
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.2
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.1
	environment.adjustment_contrast = 1.05

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
