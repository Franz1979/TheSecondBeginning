// Contorno di selezione (2026-11-19): il modello ripassato un po' più grande, solo le facce dietro, in tinta unita
// senza luce. Si usa come material_overlay del MeshInstance3D (Outline3D). Il modello ha l'origine alla base, quindi
// ingrandire attorno all'origine allarga la sagoma verso l'esterno e verso l'alto, restando a terra.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;

uniform vec4 color : source_color = vec4(1.0, 0.93, 0.75, 1.0);
uniform float grow = 0.05;

void vertex() {
	VERTEX *= 1.0 + grow;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
