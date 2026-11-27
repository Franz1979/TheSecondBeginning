// Terreno della vista 3D a texture con il ruscello disegnato dentro. Ogni vertice porta:
//   COLOR = tinta del bioma (dal 2D, sRGB), UV = posizione assoluta in microcelle, UV2 = (quota di terra, quota d'argilla).
// Suoli, dal basso: prato (ovunque, anche senza la risorsa erba: 2026-11-21), terra solo dove serve (terra battuta, riva), sottobosco (alberi e cespugli), ghiaia (rocce),
// poi la terra color sabbia dei terreni aridi (segnaposto), l'argilla e il ruscello. Quale suolo spetta a ogni microcella
// lo dice cover_mask (una per cella, GroundCover3D); i confini si decidono pixel per pixel con un rumore e col rilievo
// della texture, sempre sfumati: contorni frastagliati che non seguono i quadretti delle microcelle.
// L'erba prende il colore del bioma tenendo il dettaglio della texture (texture / suo colore medio).
// Ruscello: stream_mask (una per cella, StreamMask3D) dice in R quanta acqua e in G quanta riva bagnata c'è.
// Nebbia (2026-11-21): fog_mask è la texture della nebbia del 2D; per ultima, vela tutto come il 2D (ruscello compreso).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Rumore e parte liscia dei bordi tra i suoli: in comune con la cottura (terrain_weights_bake.gdshader).
#include "res://render3d/objects/terrain/terrain_edges.gdshaderinc"

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
uniform sampler2D stream_mask : hint_default_black, filter_linear, repeat_disable;
// Suoli della cella (GroundCover3D), un pixel per microcella: R = erba, G = alberi o cespugli, B = roccia.
// Senza maschera = tutto prato.
uniform sampler2D cover_mask : hint_default_white, filter_linear, repeat_disable;
// Cottura dei pesi (2026-11-27, misura FPS: i 7 rumori dei bordi valevano ~2,8 ms): la parte liscia dei bordi della cella
// (terrain_edges.gdshaderinc) cotta una volta da TerrainWeightsBaker3D, 4 punti per microcella, al posto dei rumori e
// della maschera dei suoli. A = prato, sottobosco, sottocespuglio, ghiaia; B = terra battuta e tre rumori. Finché la
// cella non è cotta (use_baked_weights false) i bordi si calcolano dal vivo, uguali.
uniform bool use_baked_weights = false;
uniform sampler2D baked_weights_a : filter_linear_mipmap, repeat_disable;
uniform sampler2D baked_weights_b : filter_linear_mipmap, repeat_disable;
// Terra battuta (una per microcella, DirtGround3D): R = 1 dove c'è, G = più scura (deposito), B = mattonella dell'edificio
// "Terra battuta" (terra marrone scura); senza B = terra chiara sotto un altro edificio. Nero = niente.
uniform sampler2D beaten_mask : hint_default_black, filter_linear, repeat_disable;

// Nebbia (la texture del 2D, FogOfWarRenderer, un pixel per microcella): l'alfa è il velo del 2D — 0 in vista, 0,1
// dettaglio fresco, 0,25 risorse fresche, 0,5 solo terreno ricordato, 1 mai vista o dimenticata. Senza = niente nebbia.
uniform sampler2D fog_mask : hint_default_transparent, filter_linear, repeat_disable;
// Il velo del 2D si stende sui colori sRGB: in luce lineare il fattore è (1 - velo) ^ fog_gamma, così i gradini scuriscono
// quanto nel 2D. fog_darkness: 1 = come il 2D, meno = più chiaro.
uniform float fog_darkness = 1.0;
uniform float fog_gamma = 2.2;
// Dal "solo terreno ricordato" in su, al posto della terra dove il 2D non dà più l'erba: prato generico tinto del bioma
// (come il colore del terreno nel 2D), un po' desaturato perché è un ricordo.
uniform float fog_remembered_desaturation = 0.5;
// Colore del mai visto (il nero del 2D) e quanto il confine della nebbia è frastagliato (in microcelle).
uniform vec3 fog_unseen_color : source_color = vec3(0.0);
uniform float fog_edge_wiggle = 0.6;

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

// Erba: quanto prende la tinta del bioma (0 = colore vero della texture, 1 = tutta tinta) e saturazione finale.
uniform float grass_tint_strength = 0.55;
uniform float grass_saturation = 0.92;
// Erba-risorsa (2026-11-21): dove il 2D ha l'erba, erba alta (texture a fili del progetto, tallgrass/) più scura e piena
// del prato; altrove resta il prato. Quanto prende la tinta del bioma, quanto si scurisce e quante microcelle copre.
uniform sampler2D tall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tall_average : source_color = vec3(0.35, 0.5, 0.2);
uniform float tall_tint_strength = 0.15;
uniform float tall_brightness = 0.82;
uniform float tall_tile = 6.0;
// Stagione dell'erba alta (2026-11-21), come l'erba del 2D: cambio netto a inizio stagione (TerrainMaterial3D.set_season).
// 0 = primavera/estate (verde), 1 = autunno (stessa texture ricolorata verso il dorato), 2 = inverno (erba secca rada e
// coricata, texture con trasparenza stesa sulla terra: suolo quasi brullo).
uniform int grass_season = 0;
uniform vec3 tall_autumn_color : source_color = vec3(0.74, 0.63, 0.32);
uniform float tall_autumn_amount = 0.8;
uniform sampler2D winter_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D winter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float winter_soil_brightness = 0.85;
// Prato basso (senza erba-risorsa: attorno agli edifici, argilla finita...) e sottobosco/sottocespuglio di stagione
// (2026-11-21, segnalazione utente: restavano verdi tutto l'anno). Stesso cambio netto dell'erba alta (grass_season),
// più tenue così l'erba alta si riconosce ancora. Inverno: erba a riposo, più scura e smorta (la texture quasi brulla
// resta solo all'erba-risorsa). Sottobosco: la sua parte di prato segue il prato basso; la texture del bosco in autunno
// si scalda verso le foglie cadute, d'inverno si scurisce e si spegne.
uniform float low_autumn_amount = 0.55;
uniform vec3 low_winter_color : source_color = vec3(0.52, 0.50, 0.36);
uniform float low_winter_amount = 0.45;
uniform float low_winter_saturation = 0.6;
uniform float low_winter_brightness = 0.78;
uniform vec3 litter_autumn_color : source_color = vec3(0.62, 0.42, 0.22);
uniform float litter_autumn_amount = 0.4;
uniform float litter_winter_saturation = 0.55;
uniform float litter_winter_brightness = 0.8;
// Prato stilizzato (stile dei modelli Quaternius, 2026-11-19): al posto della foto dell'erba, colori pieni a macchie
// morbide (verde chiaro, verde scuro, chiazze secche) con la tinta del bioma. Spento (false) = prato a texture di prima.
// Il sottobosco e il sottocespuglio restano come prima (texture mescolata col prato a texture).
uniform bool stylized_grass = false;
// TEMPORANEO (2026-11-21, misura FPS, tasto F4 di Perf3D): terreno a tinta unita, senza nessuna lettura di texture.
uniform bool debug_flat = false;
// TEMPORANEO misura FPS (tasto F4 di Perf3D, quarto modo): "strati a tinta", ogni lettura del dettaglio dei suoli
// (colore, normale, ruvidità) dà un valore fisso; bordi, rumori e maschere restano veri.
uniform bool debug_layers_flat = false;
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
// Argilla "a chiazze" (2026-11-21, scelta dell'utente fra le anteprime: la vecchia era troppo netta e invadente):
// bruno più spento, dettaglio poco contrastato e mescolato alla grana della terra; verso il bordo la pozza si rompe in
// macchie (rumore di clay_patch_tile microcelle) e l'erba ci entra dentro; orlo scuro attenuato (clay_rim_strength).
// Tinta, contrasto del dettaglio, quanto prende della terra, irregolarità del bordo, orlo di terra bagnata.
uniform vec3 clay_tint : source_color = vec3(0.54, 0.40, 0.30);
uniform float clay_detail_contrast = 1.1;
uniform float clay_dirt_mix = 0.4;
uniform float clay_patch_tile = 4.0;
uniform float clay_patch_strength = 0.9;
uniform float clay_rim_strength = 0.5;
uniform float clay_edge_noise = 0.5;
uniform float clay_roughness_scale = 0.5;
uniform float rim_darkness = 0.72;
// Confini tra i suoli (prato, sottobosco, ghiaia, terra): quanto sono frastagliati e quanto è largo il passaggio.
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

// TEMPORANEO misura FPS: letture del dettaglio dei suoli, fisse con debug_layers_flat.
vec4 layer_tex(sampler2D s, vec2 uv, vec4 fixed_value) {
	if (debug_layers_flat) {
		return fixed_value;
	}
	return texture(s, uv);
}

vec4 layer_grad(sampler2D s, vec2 uv, vec2 dx, vec2 dy, vec4 fixed_value) {
	if (debug_layers_flat) {
		return fixed_value;
	}
	return textureGrad(s, uv, dx, dy);
}

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

// Ricolora c verso color tenendone la luminosità (stesso metodo dell'autunno dell'erba alta).
vec3 recolor(vec3 c, vec3 color, float amount) {
	float luma = dot(c, vec3(0.333));
	return mix(c, color / max(dot(color, vec3(0.333)), 0.01) * luma, amount);
}

// Prato basso di stagione (grass_season: 0 verde, 1 autunno, 2 inverno).
vec3 season_low(vec3 c) {
	if (grass_season == 1) {
		return recolor(c, tall_autumn_color, low_autumn_amount);
	} else if (grass_season == 2) {
		return saturate_color(recolor(c, low_winter_color, low_winter_amount), low_winter_saturation) * low_winter_brightness;
	}
	return c;
}

// Texture del sottobosco di stagione.
vec3 season_litter(vec3 c) {
	if (grass_season == 1) {
		return recolor(c, litter_autumn_color, litter_autumn_amount);
	} else if (grass_season == 2) {
		return saturate_color(c, litter_winter_saturation) * litter_winter_brightness;
	}
	return c;
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
	if (debug_flat) { // TEMPORANEO misura FPS
		ALBEDO = vec3(0.32, 0.45, 0.2);
		ROUGHNESS = 1.0;
		SPECULAR = 0.3;
	} else { // TEMPORANEO misura FPS: chiuso a fine funzione (gli shader Godot non accettano return in fragment)
	vec2 g_uv = ground_pos / grass_tile;
	vec2 d_uv = ground_pos / dirt_tile;
	vec2 c_uv = ground_pos / clay_tile;
	vec2 f_uv = ground_pos / forest_tile;
	vec2 s_uv = ground_pos / gravel_tile;
	// Letture solo dove servono (2026-11-21, misura FPS: ~27 letture per pixel su una Intel UHD, la GPU era il collo di
	// bottiglia). Argilla, ghiaia, sottobosco, erba alta e le normali/ruvidità della terra si leggono solo dove il loro peso
	// non è zero: altrove venivano moltiplicate per zero, quindi l'immagine resta identica. Dentro i rami le letture usano
	// textureGrad con le derivate prese qui fuori (le derivate dentro un ramo non sono affidabili ai bordi del ramo).
	vec2 dpx = dFdx(ground_pos);
	vec2 dpy = dFdy(ground_pos);
	vec3 grass = layer_tex(grass_albedo, g_uv, vec4(grass_average, 1.0)).rgb;
	vec3 dirt = layer_tex(dirt_albedo, d_uv, vec4(dirt_average, 1.0)).rgb;
	// Rilievo della terra e dell'erba (dalla luminosità): rompe i bordi come farebbe il terreno vero.
	float dirt_relief = dot(dirt / max(dirt_average, vec3(0.01)), vec3(0.333)) - 1.0;
	float grass_relief = dot(grass / max(grass_average, vec3(0.01)), vec3(0.333)) - 1.0;

	vec2 cell_uv = (ground_pos - cell_origin) / cell_size;

	float dirt_w = clamp(weights.x, 0.0, 1.0);
	float has_clay = step(0.001, weights.y);
	// Suoli della microcella, sfumati: la parte liscia del bordo (maschera + rumori, terrain_edges.gdshaderinc) cotta o
	// calcolata qui, poi la curva morbida e il rilievo della texture, che rompe i bordi come farebbe il terreno vero.
	vec4 s_a;
	vec4 s_b;
	if (use_baked_weights) {
		s_a = texture(baked_weights_a, cell_uv) * EDGE_SIGNAL_RANGE - EDGE_SIGNAL_OFFSET;
		s_b = texture(baked_weights_b, cell_uv);
		s_b.x = s_b.x * EDGE_SIGNAL_RANGE - EDGE_SIGNAL_OFFSET;
	} else {
		terrain_edge_signals(ground_pos, texture(cover_mask, cell_uv), texture(beaten_mask, cell_uv).r, s_a, s_b);
	}
	float wiggle_a = s_b.y;
	float wiggle_b = s_b.z;
	float edge_n = s_b.w;
	float lo = 0.5 - cover_edge_softness;
	float hi = 0.5 + cover_edge_softness;
	float grass_w = smoothstep(lo, hi, s_a.x - dirt_relief * 0.15);
	float forest_w = smoothstep(0.5 - forest_edge_softness, 0.5 + forest_edge_softness, s_a.y);
	float shrub_w = smoothstep(0.5 - forest_edge_softness, 0.5 + forest_edge_softness, s_a.z);
	vec3 beaten_rg = texture(beaten_mask, cell_uv).rgb;
	float beaten_w = smoothstep(lo, hi, s_b.x + dirt_relief * 0.1);
	float gravel_w = smoothstep(lo, hi, s_a.w + dirt_relief * 0.1);
	grass_w *= 1.0 - dirt_w;
	// L'erba-risorsa vera, prima che la nebbia vi aggiunga il prato "ricordato" (lì la tinta non va).
	float resource_grass_w = grass_w;
	// Fondo a prato (2026-11-21, richiesta utente): anche dove il 2D non ha l'erba-risorsa (vuoto, dopo una demolizione)
	// il suolo è prato, non terra. Dove c'è l'erba-risorsa (grass_w) il prato diventa erba alta.
	float meadow_w = 1.0;
	// Nebbia: letta con la posizione mossa dal rumore, così il confine non segue i quadretti delle microcelle. Dove resta
	// solo il terreno ricordato (velo 0,5 e oltre) il 2D non dà più l'erba: prato generico invece della terra.
	vec2 fog_shift = (vec2(wiggle_a, wiggle_b) - 0.5) * fog_edge_wiggle + (edge_n - 0.5) * fog_edge_wiggle * 0.5;
	float fog = texture(fog_mask, cell_uv + fog_shift / cell_size).a;
	float remembered_w = smoothstep(0.3, 0.45, fog);
	grass_w = max(grass_w, remembered_w * (1.0 - dirt_w));
	forest_w *= 1.0 - dirt_w;
	shrub_w *= 1.0 - dirt_w;
	// Pozza d'argilla, dall'esterno: prato che si dirada (i ciuffi più chiari resistono di più), terra bagnata, argilla
	// che entra seguendo il proprio rilievo. Sfumature larghe: niente bordo netto.
	vec3 clay = vec3(0.0);
	float clay_w = 0.0;
	float rim_w = 0.0;
	if (has_clay > 0.0) {
		clay = layer_grad(clay_albedo, c_uv, dpx / clay_tile, dpy / clay_tile, vec4(clay_average, 1.0)).rgb;
		float clay_relief = dot(clay / max(clay_average, vec3(0.01)), vec3(0.333)) - 1.0;
		float edge = weights.y + (edge_n - 0.5) * clay_edge_noise;
		float clay_patch = texture(edge_noise, ground_pos / clay_patch_tile + vec2(0.21, 0.83)).r;
		clay_w = smoothstep(0.35, 0.75, edge * 0.9 + (clay_patch - 0.5) * clay_patch_strength + clay_relief * 0.2) * has_clay;
		rim_w = smoothstep(0.12, 0.42, edge - grass_relief * 0.18) * has_clay * (1.0 - clay_w) * clay_rim_strength;
	}
	float under_w = max(forest_w, shrub_w);

	vec3 grass_tinted = tint * grass / max(grass_average, vec3(0.01));
	vec3 grass_color = saturate_color(mix(grass, grass_tinted, grass_tint_strength), grass_saturation);
	// Il prato vero e proprio: a texture (grass_color) o stilizzato. Sottobosco e sottocespuglio usano sempre grass_color.
	vec3 meadow_color = grass_color;
	if (stylized_grass) {
		meadow_color = stylized_meadow(ground_pos, tint);
	}
	// Stagione anche sul prato basso e sul sottobosco (l'erba alta ha la sua, sotto).
	grass_color = season_low(grass_color);
	meadow_color = season_low(meadow_color);
	vec3 forest = vec3(0.0);
	if (under_w > 0.0) {
		forest = season_litter(layer_grad(forest_albedo, f_uv, dpx / forest_tile, dpy / forest_tile, vec4(0.3, 0.25, 0.15, 1.0)).rgb);
	}
	// Erba alta sull'erba-risorsa (sottobosco e sottocespuglio restano col prato a texture).
	vec2 t_uv = ground_pos / tall_tile;
	vec2 t_dx = dpx / tall_tile;
	vec2 t_dy = dpy / tall_tile;
	vec4 winter = vec4(0.0);
	if (resource_grass_w > 0.0) {
		vec3 tall = layer_grad(tall_albedo, t_uv, t_dx, t_dy, vec4(tall_average, 1.0)).rgb;
		vec3 tall_color = mix(tall, tint * tall / max(tall_average, vec3(0.01)), tall_tint_strength) * tall_brightness;
		if (grass_season == 1) {
			float tall_luma = dot(tall_color, vec3(0.333));
			tall_color = mix(tall_color, tall_autumn_color / max(dot(tall_autumn_color, vec3(0.333)), 0.01) * tall_luma, tall_autumn_amount);
		} else if (grass_season == 2) {
			winter = layer_grad(winter_albedo, t_uv, t_dx, t_dy, vec4(0.5, 0.45, 0.3, 0.5));
			tall_color = mix(dirt * winter_soil_brightness, winter.rgb, winter.a);
		}
		meadow_color = mix(meadow_color, tall_color, resource_grass_w);
	}
	vec3 ground = mix(dirt, meadow_color, meadow_w);
	// Sottocespuglio, poi sottobosco sopra: dove ci sono alberi e cespugli insieme vince il sottobosco (le chiome lo
	// coprono), e i due si sfumano ai bordi come gli altri suoli.
	ground = mix(ground, mix(forest * shrub_tint, grass_color, shrub_grass_mix), shrub_w);
	ground = mix(ground, mix(forest, grass_color, forest_grass_mix), forest_w);
	// Terra chiara sotto gli edifici; sulle mattonelle dell'edificio "Terra battuta" (canale B) la terra marrone scura.
	vec3 beaten_light = beaten_color * (1.0 - beaten_rg.g * beaten_dark_amount) * mix(vec3(1.0), dirt / max(dirt_average, vec3(0.01)), 0.6);
	ground = mix(ground, mix(beaten_light, dirt, beaten_rg.b), beaten_w);
	ground = mix(ground, sand_color * dirt / max(dirt_average, vec3(0.01)), dirt_w);
	ground = mix(ground, dirt * rim_darkness, rim_w);
	// Argilla: dettaglio della sua texture appena accennato, mescolato alla grana della terra, così non è una tinta piatta.
	vec3 clay_detail = pow(clay / max(clay_average, vec3(0.01)), vec3(clay_detail_contrast));
	vec3 clay_color = clay_tint * mix(clay_detail, dirt / max(dirt_average, vec3(0.01)), clay_dirt_mix);
	vec3 albedo = mix(ground, clay_color, clay_w);
	// Ghiaia sotto le rocce sopra a tutto (anche sabbia e argilla): dove c'è una roccia il fondo è sempre ghiaia.
	if (gravel_w > 0.0) {
		albedo = mix(albedo, layer_grad(gravel_albedo, s_uv, dpx / gravel_tile, dpy / gravel_tile, vec4(0.5, 0.48, 0.45, 1.0)).rgb, gravel_w);
	}

	// Ruscello (letto qui: serve a sapere se occorrono normale e ruvidità della terra).
	vec4 mask = texture(stream_mask, cell_uv);
	bool need_dirt = beaten_w > 0.0 || dirt_w > 0.0 || rim_w > 0.0 || mask.g > 0.001
		|| (grass_season == 2 && resource_grass_w > 0.0);
	vec3 n_dirt = vec3(0.5, 0.5, 1.0);
	float r_dirt = 1.0;
	if (need_dirt) {
		n_dirt = layer_grad(dirt_normal, d_uv, dpx / dirt_tile, dpy / dirt_tile, vec4(0.5, 0.5, 1.0, 1.0)).rgb;
		r_dirt = layer_grad(dirt_roughness, d_uv, dpx / dirt_tile, dpy / dirt_tile, vec4(0.9)).r;
	}

	vec3 n_grass = layer_tex(grass_normal, g_uv, vec4(0.5, 0.5, 1.0, 1.0)).rgb;
	float r_meadow = layer_tex(grass_roughness, g_uv, vec4(0.9)).r;
	if (stylized_grass) {
		// Prato stilizzato quasi liscio: il rilievo della foto non c'è più.
		n_grass = mix(n_grass, vec3(0.5, 0.5, 1.0), stylized_flatten);
		r_meadow = stylized_roughness;
	}
	vec3 normal_map = mix(n_dirt, n_grass, meadow_w);
	if (resource_grass_w > 0.0) {
		vec3 n_tall = layer_grad(tall_normal, t_uv, t_dx, t_dy, vec4(0.5, 0.5, 1.0, 1.0)).rgb;
		if (grass_season == 2) {
			n_tall = mix(n_dirt, layer_grad(winter_normal, t_uv, t_dx, t_dy, vec4(0.5, 0.5, 1.0, 1.0)).rgb, winter.a);
		}
		normal_map = mix(normal_map, n_tall, resource_grass_w * meadow_w);
	}
	if (under_w > 0.0) {
		normal_map = mix(normal_map, layer_grad(forest_normal, f_uv, dpx / forest_tile, dpy / forest_tile, vec4(0.5, 0.5, 1.0, 1.0)).rgb, under_w);
	}
	normal_map = mix(normal_map, mix(n_dirt, vec3(0.5, 0.5, 1.0), beaten_flatten * (1.0 - beaten_rg.b)), beaten_w);
	normal_map = mix(normal_map, n_dirt, max(dirt_w, rim_w));
	float r_clay = 0.0;
	if (clay_w > 0.0) {
		normal_map = mix(normal_map, layer_grad(clay_normal, c_uv, dpx / clay_tile, dpy / clay_tile, vec4(0.5, 0.5, 1.0, 1.0)).rgb, clay_w);
		r_clay = layer_grad(clay_roughness, c_uv, dpx / clay_tile, dpy / clay_tile, vec4(0.9)).r * clay_roughness_scale;
	}
	if (gravel_w > 0.0) {
		normal_map = mix(normal_map, layer_grad(gravel_normal, s_uv, dpx / gravel_tile, dpy / gravel_tile, vec4(0.5, 0.5, 1.0, 1.0)).rgb, gravel_w);
	}

	float roughness = mix(r_dirt, r_meadow, meadow_w);
	roughness = mix(roughness, forest_roughness, under_w);
	roughness = mix(roughness, r_dirt * 0.9, beaten_w);
	roughness = mix(roughness, r_dirt, dirt_w);
	roughness = mix(roughness, r_dirt * 0.7, rim_w);
	roughness = mix(roughness, r_clay, clay_w);
	roughness = mix(roughness, gravel_roughness, gravel_w);
	float specular = 0.3;

	// Ruscello: riva bagnata (terra scura), poi acqua con bordo frastagliato.
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

	// Nebbia: velo come nel 2D, ricordo un po' desaturato, mai visto del colore pieno (niente riflessi né rilievo).
	albedo = saturate_color(albedo, 1.0 - remembered_w * fog_remembered_desaturation);
	albedo *= pow(clamp(1.0 - fog * fog_darkness, 0.0, 1.0), fog_gamma);
	float unseen_w = smoothstep(0.75, 0.98, fog);
	albedo = mix(albedo, fog_unseen_color, unseen_w);
	specular *= 1.0 - fog;
	roughness = mix(roughness, 1.0, unseen_w);
	normal_map = mix(normal_map, vec3(0.5, 0.5, 1.0), unseen_w);

	ALBEDO = albedo;
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	} // TEMPORANEO misura FPS: fine del ramo "else" di debug_flat
}
