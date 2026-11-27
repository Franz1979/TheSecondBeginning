class_name TerrainMaterial3D
extends RefCounted

# Materiale del terreno a texture (terrain.gdshader): carica erba, terra e argilla (colore, rilievo, ruvidità e colore
# medio, per tingerle senza scurirle), sottobosco e ghiaia (solo colore e rilievo), tutte CC0 in render3d/assets/textures/,
# e prepara il rumore dei bordi.
# Creato una volta sola (Materials3D) e condiviso da tutte le celle.

const SHADER_PATH := "res://render3d/objects/terrain/terrain.gdshader"
const TEXTURE_DIR := "res://render3d/assets/textures/%s/%s_%s.jpg"
const SURFACES := ["grass", "dirt", "clay"]
# Suoli con solo colore e rilievo (la ruvidità è un numero fisso nello shader).
const SIMPLE_SURFACES := ["forest", "gravel"]
# Erba alta dove il 2D ha l'erba-risorsa (2026-11-21): disegnata dal progetto, SOURCES_PER_GIOCO/textures/make_tallgrass.py.
const TALL_GRASS_DIR := "res://render3d/assets/textures/tallgrass/"
# Rumore dei bordi: immagine ripetibile, macchie di circa 1-2 microcelle (vedi noise_tile nello shader).
const NOISE_SIZE := 256
const NOISE_FREQUENCY := 0.05
const AVERAGE_STEP := 16
# Cottura dei pesi dei bordi (2026-11-27, TerrainWeightsBaker3D): false = niente cottura, bordi calcolati dal vivo come
# prima (stesso aspetto, ~3 ms in più).
const BAKED_WEIGHTS_ENABLED := true


static func make() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	for surface in SURFACES:
		var albedo: Texture2D = load(TEXTURE_DIR % [surface, surface, "color"])
		material.set_shader_parameter(surface + "_albedo", albedo)
		material.set_shader_parameter(surface + "_normal", load(TEXTURE_DIR % [surface, surface, "normal"]))
		material.set_shader_parameter(surface + "_roughness", load(TEXTURE_DIR % [surface, surface, "roughness"]))
		material.set_shader_parameter(surface + "_average", _average_color(albedo))
	for surface in SIMPLE_SURFACES:
		material.set_shader_parameter(surface + "_albedo", load(TEXTURE_DIR % [surface, surface, "color"]))
		material.set_shader_parameter(surface + "_normal", load(TEXTURE_DIR % [surface, surface, "normal"]))
	# Erba alta dell'erba-risorsa (texture del progetto, .png): colore, rilievo e colore medio.
	var tall: Texture2D = load(TALL_GRASS_DIR + "tallgrass_color.png")
	material.set_shader_parameter("tall_albedo", tall)
	material.set_shader_parameter("tall_normal", load(TALL_GRASS_DIR + "tallgrass_normal.png"))
	material.set_shader_parameter("tall_average", _average_color(tall))
	material.set_shader_parameter("winter_albedo", load(TALL_GRASS_DIR + "tallgrass_winter_color.png"))
	material.set_shader_parameter("winter_normal", load(TALL_GRASS_DIR + "tallgrass_winter_normal.png"))
	material.set_shader_parameter("edge_noise", _edge_noise_texture())
	return material


# Copia del materiale per una cella: stesse texture condivise, più il suo angolo in microcelle assolute e, se c'è, la
# maschera del ruscello (StreamMask3D).
static func for_cell(shared: ShaderMaterial, cell_origin: Vector2, stream_mask: Image) -> ShaderMaterial:
	var material := shared.duplicate() as ShaderMaterial
	material.set_shader_parameter("cell_origin", cell_origin)
	material.set_shader_parameter("cell_size", float(World.WIDTH))
	if stream_mask != null:
		material.set_shader_parameter("stream_mask", ImageTexture.create_from_image(stream_mask))
	return material


# Stagione del 2D per l'erba alta: primavera ed estate verdi, autunno dorato, inverno secco e rado (terrain.gdshader).
static func set_season(material: ShaderMaterial, season: GameTypes.Season) -> void:
	var index := 0
	if season == GameTypes.Season.AUTUMN:
		index = 1
	elif season == GameTypes.Season.WINTER:
		index = 2
	material.set_shader_parameter("grass_season", index)


# Maschera dei suoli della cella (GroundCover3D).
static func set_cover(material: ShaderMaterial, cover_image: Image) -> void:
	_set_mask(material, "cover_mask", cover_image)


# Maschera della terra battuta della cella (DirtGround3D).
static func set_beaten(material: ShaderMaterial, beaten_image: Image) -> void:
	_set_mask(material, "beaten_mask", beaten_image)


# Pesi dei bordi cotti da TerrainWeightsBaker3D (immagini con le mipmap): da qui lo shader li legge al posto dei rumori.
static func set_baked_weights(material: ShaderMaterial, weights_a: Image, weights_b: Image) -> void:
	_set_mask(material, "baked_weights_a", weights_a)
	_set_mask(material, "baked_weights_b", weights_b)
	material.set_shader_parameter("use_baked_weights", true)


# La prima volta crea la texture, poi la aggiorna sul posto (stesso formato e misura).
static func _set_mask(material: ShaderMaterial, parameter: String, image: Image) -> void:
	var texture := material.get_shader_parameter(parameter) as ImageTexture
	if texture == null:
		material.set_shader_parameter(parameter, ImageTexture.create_from_image(image))
	else:
		texture.update(image)


# Colore medio della texture (campionata a passo fisso: basta e costa poco).
static func _average_color(texture: Texture2D) -> Color:
	if texture == null:
		return Color(0.5, 0.5, 0.5)
	var image := texture.get_image()
	if image == null:
		return Color(0.5, 0.5, 0.5)
	if image.is_compressed():
		image.decompress()
	var sum := Vector3.ZERO
	var count := 0
	for y in range(0, image.get_height(), AVERAGE_STEP):
		for x in range(0, image.get_width(), AVERAGE_STEP):
			var c := image.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			count += 1
	if count == 0:
		return Color(0.5, 0.5, 0.5)
	sum /= float(count)
	return Color(sum.x, sum.y, sum.z)


static func _edge_noise_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 6161
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = NOISE_FREQUENCY
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var image := noise.get_seamless_image(NOISE_SIZE, NOISE_SIZE)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
