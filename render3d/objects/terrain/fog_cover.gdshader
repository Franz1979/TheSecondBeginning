// Coperta della nebbia nera (2026-11-23, misura FPS con RenderDoc): la stessa griglia del terreno (TerrainMesh3D), nera e
// senza luce, appena sopra il terreno dove la nebbia è nera piena. Lì nasconde il terreno: la scheda ne salta i pixel col
// test di profondità anticipato, invece di pagarne texture, luce e ombre per poi dipingerli di nero (da lontano anche un
// terzo dello schermo). Lo shader del terreno non cambia (uno scarto lì spegneva il test anticipato per tutto il terreno).
// Un angolo della griglia resta su solo se le 16 microcelle attorno (due giri) sono tutte nere: il terreno sfuma la nebbia
// spostandone la lettura fino a ~0,5 microcelle, e con due giri il bordo sfumato resta tutto del terreno, mai coperto.
// Gli altri angoli scendono sotto il terreno, dove non si vedono. Segue la texture della nebbia da sola, a ogni fotogramma.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D fog_mask : hint_default_transparent, filter_nearest, repeat_disable;
uniform vec2 cell_origin = vec2(0.0);
uniform float cell_size = 100.0;
// Quanto sopra il terreno sta la coperta, e quanto sotto scende dove non serve.
uniform float lift = 0.03;
uniform float sink = 2.0;

void vertex() {
	// UV = posizione assoluta dell'angolo in microcelle (come nel terreno); l'angolo (i, j) tocca le microcelle i-1..i.
	ivec2 corner = ivec2(round(UV - cell_origin));
	int last = int(cell_size) - 1;
	bool black = true;
	for (int dy = -2; dy <= 1 && black; dy++) {
		for (int dx = -2; dx <= 1; dx++) {
			ivec2 p = corner + ivec2(dx, dy);
			// Fuori dalla cella non si sa: niente coperta (il bordo resta al terreno).
			if (p.x < 0 || p.y < 0 || p.x > last || p.y > last || texelFetch(fog_mask, p, 0).a < 0.99) {
				black = false;
				break;
			}
		}
	}
	VERTEX.y += black ? lift : -sink;
}

void fragment() {
	ALBEDO = vec3(0.0);
}
