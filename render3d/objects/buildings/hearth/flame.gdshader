shader_type spatial;
// Fiamma del focolare: un quadrato rivolto sempre verso la camera, con base sul fuoco. Lingue morbide fatte di rumore che
// salgono: cuore giallo chiaro, bordo arancio che sfuma nel trasparente. Luce sommata (si accende sopra la scena).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float speed = 2.2;
uniform float intensity = 1.4;
uniform float seed = 0.0;
uniform vec3 color_outer : source_color = vec3(1.0, 0.32, 0.05);
uniform vec3 color_mid : source_color = vec3(1.0, 0.62, 0.15);
uniform vec3 color_core : source_color = vec3(1.0, 0.93, 0.65);

void vertex() {
	// Sempre di fronte alla camera, scala dell'oggetto mantenuta.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float x = UV.x;
	float y = 1.0 - UV.y;
	float t = TIME * speed + seed * 13.7;
	vec2 q = vec2(x * 3.0 + seed, y * 2.5 - t);
	float d = fbm(q) + 0.5 * fbm(q * 2.3 + vec2(0.0, -t * 0.6));
	// Sagoma a goccia (larga in basso, stretta in alto) mangiata dal rumore, più in alto che in basso.
	float width = 0.5 - abs(x - 0.5) * (1.6 + y * 1.6);
	float shape = width + (d - 0.55) * 0.55 * (0.3 + y) - y * 0.42;
	float alpha = smoothstep(0.0, 0.18, shape) * smoothstep(1.0, 0.6, y);
	vec3 col = mix(color_outer, color_mid, smoothstep(0.05, 0.2, shape));
	col = mix(col, color_core, smoothstep(0.2, 0.34, shape) * (1.0 - y));
	ALBEDO = col * alpha * intensity;
	ALPHA = alpha;
}
