// Cottura dei pesi del terreno (2026-11-27, misura FPS): disegna in un SubViewport (TerrainWeightsBaker3D) la parte
// liscia dei bordi tra i suoli di UNA cella, con le stesse formule dello shader del terreno (terrain_edges.gdshaderinc).
// Un solo rettangolo largo il doppio dell'alto: metà sinistra = immagine A (prato, sottobosco, sottocespuglio, ghiaia),
// metà destra = immagine B (terra battuta e tre rumori). Valori scritti così come sono (niente fusione col fondo): li
// rilegge terrain.gdshader (baked_weights_a / baked_weights_b).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://render3d/objects/terrain/terrain_edges.gdshaderinc"

// Gli stessi della cella: maschere (con gli stessi valori di ripiego del terreno), angolo e lato in microcelle.
uniform sampler2D cover_mask : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D beaten_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 cell_origin = vec2(0.0);
uniform float cell_size = 100.0;

void fragment() {
	bool second = UV.x >= 0.5;
	// Ogni metà copre tutta la cella: il centro di ogni punto cade dove il terreno lo rileggerà.
	vec2 cell_uv = vec2(second ? UV.x * 2.0 - 1.0 : UV.x * 2.0, UV.y);
	vec2 ground_pos = cell_origin + cell_uv * cell_size;
	vec4 s_a;
	vec4 s_b;
	terrain_edge_signals(ground_pos, texture(cover_mask, cell_uv), texture(beaten_mask, cell_uv).r, s_a, s_b);
	if (second) {
		COLOR = vec4(clamp((s_b.x + EDGE_SIGNAL_OFFSET) / EDGE_SIGNAL_RANGE, 0.0, 1.0), s_b.yzw);
	} else {
		COLOR = clamp((s_a + EDGE_SIGNAL_OFFSET) / EDGE_SIGNAL_RANGE, vec4(0.0), vec4(1.0));
	}
}
