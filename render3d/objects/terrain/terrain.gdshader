// Terreno della vista 3D a texture con il ruscello disegnato dentro. Ogni vertice porta:
//   COLOR = tinta del bioma (dal 2D, sRGB), UV = posizione assoluta in microcelle, UV2 = (quota di terra, quota d'argilla).
// Suoli, dal basso: terra (microcella senza erba), prato (risorsa erba), sottobosco (alberi e cespugli), ghiaia (rocce),
// poi la terra color sabbia dei terreni aridi (segnaposto), l'argilla e il ruscello. Quale suolo spetta a ogni microcella
// lo dice cover_mask (una per cella, GroundCover3D); i confini si decidono pixel per pixel con un rumore e col rilievo
// della texture, sempre sfumati: contorni frastagliati che non seguono i quadretti delle microcelle.
// L'erba prende il colore del bioma tenendo il dettaglio della texture (texture / suo colore medio).
// Ruscello: stream_mask (una per cella, StreamMask3D) dice in R quanta acqua e in G quanta riva bagnata c'è.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clay_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clay_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clay_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D edge_noise : filter_linear, repeat_enable;
uniform sampler2D stream_mask : hint_default_black, filter_linear, repeat_disable;
// Suoli della cella (GroundCover3D), un pixel per microcella: R = erba, G = alberi o cespugli, B = roccia.
// Senza maschera = tutto prato.
uniform sampler2D cover_mask : hint_default_white, filter_linear, repeat_disable;
// Terra battuta (l'edificio, una per microcella, DirtGround3D): R = 1 dove c'è. Nero = niente.
uniform sampler2D beaten_mask : hint_default_black, filter_linear, repeat_disable;

// Colore medio di ogni texture (calcolato da TerrainMaterial3D): serve a tingerla senza scurirla.
uniform vec3 grass_average : source_color = vec3(0.4, 0.5, 0.3);
uniform vec3 dirt_average : source_color = vec3(0.5, 0.4, 0.3);
uniform vec3 clay_average : source_color = vec3(0.7, 0.55, 0.45);

// Quante microcelle copre una ripetizione della texture.
uniform float grass_tile = 3.0;
uniform float dirt_tile = 3.0;
uniform float clay_tile = 2.5;
uniform float forest_tile = 3.0;
uniform float gravel_tile = 2.0;
// Quante microcelle copre il rumore dei bordi.
uniform float noise_tile = 24.0;

// Erba: quanto prende la tinta del bioma (0 = colore vero della texture, 1 = tutta tinta) e saturazione finale.
uniform float grass_tint_strength = 0.55;
uniform float grass_saturation = 0.92;
// Prato stilizzato (stile dei modelli Quaternius, 2026-11-19): al posto della foto dell'erba, colori pieni a macchie
// morbide (verde chiaro, verde scuro, chiazze secche) con la tinta del bioma. Spento (false) = prato a texture di prima.
// Il sottobosco e il sottocespuglio restano come prima (texture mescolata col prato a texture).
uniform bool stylized_grass = false;
uniform vec3 stylized_light : source_color = vec3(0.60, 0.72, 0.26);
uniform vec3 stylized_dark : source_color = vec3(0.38, 0.56, 0.18);
uniform vec3 stylized_dry : source_color = vec3(0.74, 0.70, 0.36);
// Quanto il bioma sposta il colore (0 = solo la tavolozza, 1 = solo la tinta del bioma alla stessa luminosità).
uniform float stylized_biome_strength = 0.35;
// Macchie: grandi (microcelle) e medie; chiazze secche oltre una soglia; grana fine appena visibile.
uniform float stylized_patch_tile = 30.0;
uniform float stylized_detail_tile = 7.0;
uniform float stylized_dry_threshold = 0.64;
uniform float stylized_dry_amount = 0.45;
uniform float stylized_grain = 0.05;
uniform float stylized_flatten = 0.85;
uniform float stylized_roughness = 0.9;
// Argilla: tinta (bruno-rossiccia, bagnata), contrasto del dettaglio, irregolarità del bordo, orlo di terra bagnata.
uniform vec3 clay_tint : source_color = vec3(0.45, 0.31, 0.23);
uniform float clay_detail_contrast = 2.2;
uniform float clay_edge_noise = 0.5;
uniform float clay_roughness_scale = 0.5;
uniform float rim_darkness = 0.72;
// Confini tra i suoli (prato, sottobosco, ghiaia, terra): quanto sono frastagliati e quanto è largo il passaggio.
uniform float cover_edge_noise = 0.35;
uniform float cover_edge_wiggle = 0.3;
uniform float cover_edge_softness = 0.14;
// Sottobosco e ghiaia: ruvidità fissa (non hanno la texture della ruvidità).
uniform float forest_roughness = 0.95;
// Terra battuta: la grana della stessa terra, ma color ocra chiaro (vicino al 2D) e più liscia (rilievo attenuato).
uniform vec3 beaten_color : source_color = vec3(0.74, 0.62, 0.44);
uniform float beaten_flatten = 0.75;
// Terra battuta più scura (canale G della maschera, es. sotto il sito di deposito): quanto si scurisce al massimo.
uniform float beaten_dark_amount = 0.32;
// Sottobosco avvicinato al prato (0 = texture pura, 1 = prato) e bordo col prato più largo e più mosso degli altri.
uniform float forest_grass_mix = 0.65;
// Sottocespuglio (canale A della maschera): per ora uguale al sottobosco; tenuto a parte per poterlo distinguere.
uniform float shrub_grass_mix = 0.65;
uniform vec3 shrub_tint = vec3(1.0, 1.0, 1.0);
uniform float forest_edge_softness = 0.26;
uniform float forest_edge_wiggle = 0.45;
uniform float gravel_roughness = 0.85;
// Segnaposto per i terreni di terra (deserto, spiaggia, collina, roccia...): la terra tinta color sabbia.
uniform vec3 sand_color : source_color = vec3(0.80, 0.70, 0.52);
uniform float normal_strength = 0.8;

// Ruscello: angolo della cella in microcelle assolute (per leggere stream_mask), colore dell'acqua, riva bagnata.
uniform vec2 cell_origin = vec2(0.0);
uniform float cell_size = 100.0;
uniform vec3 water_shallow : source_color = vec3(0.48, 0.64, 0.62);
uniform vec3 water_deep : source_color = vec3(0.28, 0.46, 0.52);
uniform float bank_darkness = 0.55;
// Corrente: velocità (cicli al secondo) e quanto si sposta il disegno delle increspature per ciclo, in microcelle.
uniform float flow_speed = 0.12;
uniform float flow_distance = 0.4;
uniform float ripple_tile = 4.0;
// Quanto sono marcate le increspature (più basso = acqua più liscia).
uniform float ripple_strength = 2.5;

varying vec2 ground_pos;
varying vec3 tint;
varying vec2 weights;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 saturate_color(vec3 c, float amount) {
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(vec3(luma), c, amount);
}

// Altezza delle increspature trascinate dalla corrente (tecnica "flow map": due letture sfasate di mezzo ciclo che si
// danno il cambio, così il disegno scorre nella direzione `dir` senza mai stirarsi).
float ripple_height(vec2 p, vec2 dir) {
	float t0 = fract(TIME * flow_speed);
	float t1 = fract(TIME * flow_speed + 0.5);
	float a = texture(edge_noise, (p - dir * t0 * flow_distance) / ripple_tile).r;
	float b = texture(edge_noise, (p - dir * t1 * flow_distance) / ripple_tile + vec2(0.37, 0.61)).r;
	return mix(a, b, abs(t0 * 2.0 - 1.0));
}

// Prato stilizzato: macchie morbide di verde chiaro e scuro (rumore grande + medio), chiazze secche dove il rumore
// grande è alto, una grana fine appena accennata; poi spostato verso la tinta del bioma tenendo la luminosità.
vec3 stylized_meadow(vec2 p, vec3 biome_tint) {
	float big = texture(edge_noise, p / stylized_patch_tile + vec2(0.13, 0.57)).r;
	float mid = texture(edge_noise, p / stylized_detail_tile + vec2(0.71, 0.29)).r;
	float dry_n = texture(edge_noise, p / (stylized_patch_tile * 1.3) + vec2(0.45, 0.85)).r;
	float fine = texture(edge_noise, p / 0.9 + vec2(0.37, 0.11)).r;
	float shade = smoothstep(0.25, 0.75, big * 0.65 + mid * 0.35);
	vec3 base = mix(stylized_dark, stylized_light, shade);
	base = mix(base, stylized_dry, smoothstep(stylized_dry_threshold, stylized_dry_threshold + 0.12, dry_n) * stylized_dry_amount);
	base *= 1.0 + (fine - 0.5) * 2.0 * stylized_grain;
	float luma = dot(base, vec3(0.333));
	vec3 biome = biome_tint / max(dot(biome_tint, vec3(0.333)), 0.01) * luma;
	return mix(base, biome, stylized_biome_strength);
}

void vertex() {
	ground_pos = UV;
	weights = UV2;
	tint = srgb_to_linear(COLOR.rgb);
	// Texture stese in pianta (x = u, z = v): tangenti coerenti per le normal map.
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	BINORMAL = cross(NORMAL, TANGENT);
}

void fragment() {
	vec2 g_uv = ground_pos / grass_tile;
	vec2 d_uv = ground_pos / dirt_tile;
	vec2 c_uv = ground_pos / clay_tile;
	vec2 f_uv = ground_pos / forest_tile;
	vec2 s_uv = ground_pos / gravel_tile;
	vec3 grass = texture(grass_albedo, g_uv).rgb;
	vec3 dirt = texture(dirt_albedo, d_uv).rgb;
	vec3 clay = texture(clay_albedo, c_uv).rgb;
	vec3 forest = texture(forest_albedo, f_uv).rgb;
	vec3 gravel = texture(gravel_albedo, s_uv).rgb;
	// Rilievo della terra e dell'erba (dalla luminosità): rompe i bordi come farebbe il terreno vero.
	float dirt_relief = dot(dirt / max(dirt_average, vec3(0.01)), vec3(0.333)) - 1.0;
	float grass_relief = dot(grass / max(grass_average, vec3(0.01)), vec3(0.333)) - 1.0;

	float edge_n = texture(edge_noise, ground_pos / noise_tile).r;
	vec2 cell_uv = (ground_pos - cell_origin) / cell_size;

	float dirt_w = clamp(weights.x, 0.0, 1.0);
	float has_clay = step(0.001, weights.y);
	// Suoli della microcella, letti sfumati, col bordo mosso da un rumore largo e rotto dal rumore fine e dal rilievo.
	// Ogni suolo usa un pezzo diverso del rumore, così i bordi non si ricalcano.
	vec4 cover = texture(cover_mask, cell_uv);
	float wiggle_a = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.31, 0.71)).r;
	float wiggle_b = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.63, 0.17)).r;
	float wiggle_c = texture(edge_noise, ground_pos / (noise_tile * 2.0) + vec2(0.11, 0.47)).r;
	float fine_b = texture(edge_noise, ground_pos / noise_tile + vec2(0.52, 0.29)).r;
	float wiggle_d = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.83, 0.39)).r;
	float fine_d = texture(edge_noise, ground_pos / noise_tile + vec2(0.24, 0.66)).r;
	float lo = 0.5 - cover_edge_softness;
	float hi = 0.5 + cover_edge_softness;
	float grass_w = smoothstep(lo, hi, cover.r + (wiggle_a - 0.5) * cover_edge_wiggle + (edge_n - 0.5) * cover_edge_noise - dirt_relief * 0.15);
	float forest_w = smoothstep(0.5 - forest_edge_softness, 0.5 + forest_edge_softness,
		cover.g + (wiggle_b - 0.5) * forest_edge_wiggle + (fine_b - 0.5) * cover_edge_noise);
	float shrub_w = smoothstep(0.5 - forest_edge_softness, 0.5 + forest_edge_softness,
		cover.a + (wiggle_d - 0.5) * forest_edge_wiggle + (fine_d - 0.5) * cover_edge_noise);
	vec2 beaten_rg = texture(beaten_mask, cell_uv).rg;
	float beaten = beaten_rg.r;
	float beaten_w = smoothstep(lo, hi, beaten + (wiggle_a - 0.5) * cover_edge_wiggle + (edge_n - 0.5) * cover_edge_noise + dirt_relief * 0.1);
	float gravel_w = smoothstep(lo, hi, cover.b + (wiggle_c - 0.5) * cover_edge_wiggle + (edge_n - 0.5) * cover_edge_noise + dirt_relief * 0.1);
	grass_w *= 1.0 - dirt_w;
	forest_w *= 1.0 - dirt_w;
	shrub_w *= 1.0 - dirt_w;
	// Pozza d'argilla, dall'esterno: prato che si dirada (i ciuffi più chiari resistono di più), terra bagnata, argilla
	// che entra seguendo il proprio rilievo. Sfumature larghe: niente bordo netto.
	float clay_relief = dot(clay / max(clay_average, vec3(0.01)), vec3(0.333)) - 1.0;
	float edge = weights.y + (edge_n - 0.5) * clay_edge_noise;
	float clay_w = smoothstep(0.4, 0.56, edge + clay_relief * 0.12 + dirt_relief * 0.06) * has_clay;
	float rim_w = smoothstep(0.12, 0.42, edge - grass_relief * 0.18) * has_clay * (1.0 - clay_w);

	vec3 grass_tinted = tint * grass / max(grass_average, vec3(0.01));
	vec3 grass_color = saturate_color(mix(grass, grass_tinted, grass_tint_strength), grass_saturation);
	// Il prato vero e proprio: a texture (grass_color) o stilizzato. Sottobosco e sottocespuglio usano sempre grass_color.
	vec3 meadow_color = grass_color;
	if (stylized_grass) {
		meadow_color = stylized_meadow(ground_pos, tint);
	}
	vec3 ground = mix(dirt, meadow_color, grass_w);
	// Sottocespuglio, poi sottobosco sopra: dove ci sono alberi e cespugli insieme vince il sottobosco (le chiome lo
	// coprono), e i due si sfumano ai bordi come gli altri suoli.
	ground = mix(ground, mix(forest * shrub_tint, grass_color, shrub_grass_mix), shrub_w);
	ground = mix(ground, mix(forest, grass_color, forest_grass_mix), forest_w);
	ground = mix(ground, beaten_color * (1.0 - beaten_rg.g * beaten_dark_amount) * mix(vec3(1.0), dirt / max(dirt_average, vec3(0.01)), 0.6), beaten_w);
	ground = mix(ground, sand_color * dirt / max(dirt_average, vec3(0.01)), dirt_w);
	ground = mix(ground, dirt * rim_darkness, rim_w);
	// Argilla: dettaglio della sua texture accentuato più un po' di grana della terra, così non è una tinta piatta.
	vec3 clay_detail = pow(clay / max(clay_average, vec3(0.01)), vec3(clay_detail_contrast));
	vec3 clay_color = clay_tint * mix(clay_detail, dirt / max(dirt_average, vec3(0.01)), 0.35);
	vec3 albedo = mix(ground, clay_color, clay_w);
	// Ghiaia sotto le rocce sopra a tutto (anche sabbia e argilla): dove c'è una roccia il fondo è sempre ghiaia.
	albedo = mix(albedo, gravel, gravel_w);

	vec3 n_grass = texture(grass_normal, g_uv).rgb;
	float r_meadow = texture(grass_roughness, g_uv).r;
	if (stylized_grass) {
		// Prato stilizzato quasi liscio: il rilievo della foto non c'è più.
		n_grass = mix(n_grass, vec3(0.5, 0.5, 1.0), stylized_flatten);
		r_meadow = stylized_roughness;
	}
	vec3 n_dirt = texture(dirt_normal, d_uv).rgb;
	vec3 n_clay = texture(clay_normal, c_uv).rgb;
	vec3 normal_map = mix(n_dirt, n_grass, grass_w);
	normal_map = mix(normal_map, texture(forest_normal, f_uv).rgb, max(forest_w, shrub_w));
	normal_map = mix(normal_map, mix(n_dirt, vec3(0.5, 0.5, 1.0), beaten_flatten), beaten_w);
	normal_map = mix(normal_map, n_dirt, max(dirt_w, rim_w));
	normal_map = mix(normal_map, n_clay, clay_w);
	normal_map = mix(normal_map, texture(gravel_normal, s_uv).rgb, gravel_w);

	float r_dirt = texture(dirt_roughness, d_uv).r;
	float r_clay = texture(clay_roughness, c_uv).r * clay_roughness_scale;
	float roughness = mix(r_dirt, r_meadow, grass_w);
	roughness = mix(roughness, forest_roughness, max(forest_w, shrub_w));
	roughness = mix(roughness, r_dirt * 0.9, beaten_w);
	roughness = mix(roughness, r_dirt, dirt_w);
	roughness = mix(roughness, r_dirt * 0.7, rim_w);
	roughness = mix(roughness, r_clay, clay_w);
	roughness = mix(roughness, gravel_roughness, gravel_w);
	float specular = 0.3;

	// Ruscello: riva bagnata (terra scura), poi acqua con bordo frastagliato.
	vec4 mask = texture(stream_mask, cell_uv);
	if (mask.g > 0.001) {
		float wobble = (edge_n - 0.5) * 0.35 + dirt_relief * 0.1;
		float bank_w = smoothstep(0.3, 0.6, mask.g + wobble);
		float water_w = smoothstep(0.45, 0.55, mask.r + wobble * 0.6);
		albedo = mix(albedo, dirt * bank_darkness, bank_w);
		normal_map = mix(normal_map, n_dirt, bank_w);
		roughness = mix(roughness, r_dirt * 0.55, bank_w);
		// Increspature che scorrono lungo il ruscello (direzione dalla maschera); pendenza da tre letture vicine.
		vec2 dir = mask.ba * 2.0 - 1.0;
		float h0 = ripple_height(ground_pos, dir);
		float hx = ripple_height(ground_pos + vec2(0.05, 0.0), dir);
		float hz = ripple_height(ground_pos + vec2(0.0, 0.05), dir);
		vec3 ripple = normalize(vec3((h0 - hx) * ripple_strength, (hz - h0) * ripple_strength, 1.0)) * 0.5 + 0.5;
		// Acqua bassa e limpida: si vede il fondo (la terra) sotto, più scura dove è più profonda.
		vec3 bed = dirt / max(dirt_average, vec3(0.01)) * 0.35 + 0.65;
		vec3 water = mix(water_shallow * bed, water_deep, smoothstep(0.6, 1.0, mask.r) * 0.7);
		albedo = mix(albedo, water, water_w);
		normal_map = mix(normal_map, ripple, water_w);
		roughness = mix(roughness, 0.08, water_w);
		specular = mix(specular, 0.6, water_w);
	}

	ALBEDO = albedo;
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
