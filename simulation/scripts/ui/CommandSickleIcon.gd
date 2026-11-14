class_name CommandSickleIcon
extends Node2D

# Icona del lavoro "reap" (2026-11-15, Mietitura della lista dei lavori): falcetto di selce, manico di legno in basso a
# sinistra e lama ricurva verso l'alto e a destra, stesso stile di CommandAxeIcon. Registrata in
# IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px = 1 microcella).

const WOOD := Color(0.62, 0.42, 0.22, 1.0)
const FLINT := Color(0.6, 0.55, 0.48, 1.0)
const FLINT_EDGE := Color(0.82, 0.79, 0.72, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3

# Fattore applicato a coordinate e spessori, come CommandAxeIcon.
var icon_scale: float = 1.0


func _draw() -> void:
	var s := icon_scale
	# Manico: corto, dal basso a sinistra verso il centro.
	var handle_start := Vector2(-2.8, 3.0) * s
	var handle_end := Vector2(-1.26, 0.89) * s
	draw_line(handle_start, handle_end, OUTLINE, (0.8 + OUTLINE_WIDTH_PX * 2.0) * s, true)
	draw_line(handle_start, handle_end, WOOD, 0.8 * s, true)
	# Lama: fascia ad arco che parte dalla cima del manico, sale, passa sopra e scende a uncino verso destra,
	# assottigliandosi verso la punta.
	var center := Vector2(0.9, 0.1) * s
	var radius := 2.3 * s
	var start_angle := deg_to_rad(200.0)
	var end_angle := deg_to_rad(-15.0)
	var segments := 12
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := lerpf(start_angle, end_angle, t)
		var thickness := lerpf(0.95, 0.1, t) * s
		var direction := Vector2(cos(angle), -sin(angle))
		outer.append(center + direction * radius)
		inner.append(center + direction * (radius - thickness))
	var blade := outer.duplicate()
	for i in range(inner.size() - 1, -1, -1):
		blade.append(inner[i])
	draw_colored_polygon(blade, FLINT)
	var closed := blade.duplicate()
	closed.append(blade[0])
	draw_polyline(closed, OUTLINE, OUTLINE_WIDTH_PX * 1.5 * s, true)
	# Filo interno più chiaro (taglia dalla parte concava).
	draw_polyline(inner, FLINT_EDGE, 0.35 * s, true)
