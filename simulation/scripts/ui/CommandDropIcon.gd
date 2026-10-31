class_name CommandDropIcon
extends Node2D

# Icona "drink" (2026-10-30, sete — ThirstService): goccia d'acqua, stesso stile delle altre icone di comando disegnate
# (CommandSkullIcon): forma piena con il contorno scuro e un riflesso chiaro. Registrata in IconRegistry.COMMAND_ICON_NODES;
# origine = centro dell'icona, pixel locali della cella (10 px = 1 microcella). Sagoma: cerchio in basso (BODY_RADIUS,
# centrato in BODY_CENTER) chiuso in alto da una punta (TIP).

const WATER := Color(0.30, 0.62, 0.95, 1.0)
const SHINE := Color(0.85, 0.94, 1.0, 1.0)
const OUTLINE := Color(0.10, 0.22, 0.42, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3
const BODY_CENTER := Vector2(0.0, 0.6)
const BODY_RADIUS: float = 1.2
const TIP := Vector2(0.0, -1.8)
const SHINE_CENTER := Vector2(-0.45, 0.4)
const SHINE_RADIUS: float = 0.3
const ARC_SEGMENTS: int = 20

var icon_scale: float = 1.0


func _draw() -> void:
	var s := icon_scale
	var silhouette := _silhouette_polygon(s)
	draw_colored_polygon(silhouette, WATER)
	var outline := silhouette.duplicate()
	outline.append(silhouette[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX * s, true)
	draw_circle(SHINE_CENTER * s, SHINE_RADIUS * s, SHINE)


# Punta in alto, poi l'arco del cerchio dal punto di tangenza destro, passando sotto, fino a quello sinistro.
func _silhouette_polygon(s: float) -> PackedVector2Array:
	var to_tip := TIP - BODY_CENTER
	var tangent_angle := acos(BODY_RADIUS / to_tip.length())
	var tip_angle := to_tip.angle()
	var points := PackedVector2Array([TIP * s])
	for i in range(ARC_SEGMENTS + 1):
		var angle := lerpf(tip_angle + tangent_angle, tip_angle - tangent_angle + TAU, float(i) / float(ARC_SEGMENTS))
		points.append((BODY_CENTER + Vector2.RIGHT.rotated(angle) * BODY_RADIUS) * s)
	return points
