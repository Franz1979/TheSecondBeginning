// Bordi tra i suoli del terreno (2026-11-27, cottura dei pesi): la parte LISCIA dei bordi, cioè maschera della cella +
// rumori, prima della curva morbida (smoothstep) e del rilievo della texture, che restano nello shader del terreno.
// Usata da terrain.gdshader (calcolo dal vivo, ripiego) e da terrain_weights_bake.gdshader (cottura una volta per cella,
// TerrainWeightsBaker3D): le formule esistono una volta sola, così i bordi cotti sono gli stessi di quelli dal vivo.

uniform sampler2D edge_noise : filter_linear, repeat_enable;
// Quante microcelle copre il rumore dei bordi.
uniform float noise_tile = 24.0;
// Confini tra i suoli (prato, sottobosco, ghiaia, terra): quanto sono frastagliati (rumore fine e mosso largo).
uniform float cover_edge_noise = 0.35;
uniform float cover_edge_wiggle = 0.3;
// Bordo del sottobosco e del sottocespuglio col prato, più mosso degli altri.
uniform float forest_edge_wiggle = 0.45;
uniform bool debug_one_noise = false; // TEMPORANEO misura FPS (tasto F4 di Perf3D, terzo modo)

// Segnali dei bordi in un punto (microcelle assolute), dalla maschera dei suoli (GroundCover3D) e dalla terra battuta
// (canale R di DirtGround3D). Ogni suolo usa un pezzo diverso del rumore, così i bordi non si ricalcano.
// s_a = prato, sottobosco, sottocespuglio, ghiaia; s_b = terra battuta, poi tre rumori che servono ancora dopo
// (spostamento della nebbia in x e y, rumore base per argilla e ruscello).
void terrain_edge_signals(vec2 ground_pos, vec4 cover, float beaten, out vec4 s_a, out vec4 s_b) {
	float edge_n = texture(edge_noise, ground_pos / noise_tile).r;
	float wiggle_a;
	float wiggle_b;
	float wiggle_c;
	float fine_b;
	float wiggle_d;
	float fine_d;
	if (debug_one_noise) { // TEMPORANEO misura FPS: niente letture in più, tutti i rumori ricavati da edge_n
		wiggle_a = fract(edge_n + 0.31);
		wiggle_b = fract(edge_n + 0.63);
		wiggle_c = fract(edge_n + 0.11);
		fine_b = fract(edge_n + 0.52);
		wiggle_d = fract(edge_n + 0.83);
		fine_d = fract(edge_n + 0.24);
	} else {
		wiggle_a = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.31, 0.71)).r;
		wiggle_b = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.63, 0.17)).r;
		wiggle_c = texture(edge_noise, ground_pos / (noise_tile * 2.0) + vec2(0.11, 0.47)).r;
		fine_b = texture(edge_noise, ground_pos / noise_tile + vec2(0.52, 0.29)).r;
		wiggle_d = texture(edge_noise, ground_pos / (noise_tile * 3.0) + vec2(0.83, 0.39)).r;
		fine_d = texture(edge_noise, ground_pos / noise_tile + vec2(0.24, 0.66)).r;
	}
	float cover_shift = (wiggle_a - 0.5) * cover_edge_wiggle + (edge_n - 0.5) * cover_edge_noise;
	s_a = vec4(
		cover.r + cover_shift,
		cover.g + (wiggle_b - 0.5) * forest_edge_wiggle + (fine_b - 0.5) * cover_edge_noise,
		cover.a + (wiggle_d - 0.5) * forest_edge_wiggle + (fine_d - 0.5) * cover_edge_noise,
		cover.b + (wiggle_c - 0.5) * cover_edge_wiggle + (edge_n - 0.5) * cover_edge_noise);
	s_b = vec4(beaten + cover_shift, wiggle_a, wiggle_b, edge_n);
}

// I segnali dei suoli stanno fra circa -0,4 e 1,4: nella cottura (8 bit per canale) sono scritti come (s + 0,5) / 2.
// I tre rumori di s_b (0..1) sono scritti così come sono.
const float EDGE_SIGNAL_OFFSET = 0.5;
const float EDGE_SIGNAL_RANGE = 2.0;
