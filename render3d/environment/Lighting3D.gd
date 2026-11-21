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
# Ombre vicine (2026-11-20, scena di prova TreeStressTest): 2 suddivisioni invece di 4 e ombre solo fino a poco oltre il
# punto guardato, distanza che segue lo zoom (follow_camera_distance), con il bordo sfumato. Da lontano coprono ancora
# tutta la zona inquadrata; da vicino gli alberi in fondo allo schermo perdono l'ombra sfumando.
const NEAR_SHADOW_MARGIN := 30.0
const SHADOW_FADE_START := 0.6

var sun: DirectionalLight3D
var environment: Environment


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_fade_start = SHADOW_FADE_START
	add_child(sun)

	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.ssao_enabled = UserOptions.ssao_enabled # opzione del giocatore (Opzioni > Grafica 3D)
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


# Chiamata a ogni fotogramma dalla vista 3D con la distanza della telecamera dal punto guardato.
func follow_camera_distance(camera_distance: float) -> void:
	if sun != null:
		sun.directional_shadow_max_distance = camera_distance + NEAR_SHADOW_MARGIN


# Opzioni "Grafica 3D" del giocatore (UserOptions): ombreggiatura ambientale sì/no.
func apply_graphics_options() -> void:
	if environment != null:
		environment.ssao_enabled = UserOptions.ssao_enabled
