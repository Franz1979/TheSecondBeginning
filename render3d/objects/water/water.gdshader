// Superficie dell'acqua (mare, lago, fiume) di UNA macrocella: colore dei vertici con trasparenza, lucida — come il
// vecchio StandardMaterial3D — più la nebbia del 2D (2026-11-21), stesso velo e stesso confine frastagliato dello shader
// del terreno (terrain.gdshader: stesse formule e stessi pezzi di rumore, così acqua e riva cambiano insieme).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Nebbia della cella (FogOfWarRenderer, un pixel per microcella, alfa = velo del 2D). Senza = niente nebbia.
uniform sampler2D fog_mask : hint_default_transparent, filter_linear, repeat_disable;
// Rumore dei bordi del terreno (TerrainMaterial3D), per frastagliare il confine della nebbia allo stesso modo.
uniform sampler2D edge_noise : filter_linear, repeat_enable;
uniform vec2 cell_origin = vec2(0.0);
uniform float cell_size = 100.0;
uniform float noise_tile = 24.0;
uniform float fog_edge_wiggle = 0.6;
uniform float fog_darkness = 1.0;
uniform float fog_gamma = 2.2;
uniform vec3 fog_unseen_color : source_color = vec3(0.0);
uniform float water_roughness = 0.12;
uniform float water_specular = 0.7;

varying vec2 local_pos;
varying vec4 tint;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	local_pos = VERTEX.xz;
	tint = vec4(srgb_to_linear(COLOR.rgb), COLOR.a);
}

void fragment() {
	vec2 ground_pos = cell_origin + local_pos;
	float edge_n = texture(edge_noise, ground_pos / noise_tile).r;
	float wiggle_a = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.31, 0.71)).r;
	float wiggle_b = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.63, 0.17)).r;
	vec2 fog_shift = (vec2(wiggle_a, wiggle_b) - 0.5) * fog_edge_wiggle + (edge_n - 0.5) * fog_edge_wiggle * 0.5;
	float fog = texture(fog_mask, (local_pos + fog_shift) / cell_size).a;
	float unseen_w = smoothstep(0.75, 0.98, fog);
	vec3 albedo = tint.rgb * pow(clamp(1.0 - fog * fog_darkness, 0.0, 1.0), fog_gamma);
	ALBEDO = mix(albedo, fog_unseen_color, unseen_w);
	ALPHA = mix(tint.a, 1.0, unseen_w);
	ROUGHNESS = mix(water_roughness, 1.0, unseen_w);
	SPECULAR = water_specular * (1.0 - fog);
}
