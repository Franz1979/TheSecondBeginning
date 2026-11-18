shader_type spatial;
// Braci del focolare: mucchietto scuro con chiazze che brillano rosso-arancio. Acceso: brillano forte e sfarfallano;
// solo braci: pulsano piano (respiro lento).
render_mode cull_back;

uniform vec3 char_color : source_color = vec3(0.16, 0.08, 0.06);
uniform vec3 glow_color : source_color = vec3(1.0, 0.25, 0.03);
uniform float glow = 1.0;
// 0 = fisso, 1 = pulsa tutto (braci).
uniform float pulse_amount = 0.0;
uniform float pulse_speed = 1.6;
uniform float flicker = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	// Chiazze che brillano: rumore a blocchetti sulla posizione, con le parti alte più accese.
	float spots = hash(floor(local_pos * 28.0));
	float hot = smoothstep(0.35, 0.9, spots);
	float breath = 1.0 - pulse_amount * (0.5 - 0.5 * sin(TIME * pulse_speed));
	float wobble = 1.0 + flicker * 0.25 * sin(TIME * 13.0 + spots * 20.0);
	ALBEDO = char_color;
	ROUGHNESS = 1.0;
	EMISSION = glow_color * hot * glow * breath * wobble * 3.0;
}
