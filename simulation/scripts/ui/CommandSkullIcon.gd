class_name CommandSkullIcon
extends Node2D

# Icona del comando "bury" (2026-10-07, richiesta utente — sepoltura, prima usava la luna dei riti): teschio visto di
# fronte, stesso stile delle altre icone di comando disegnate (CommandMoonIcon, CommandPickaxeIcon): forma piena color
# osso con il contorno scuro, orbite e naso scuri, due righe dei denti. Registrata in IconRegistry.COMMAND_ICON_NODES;
# origine = centro dell'icona, pixel locali della cella (10 px = 1 microcella). `icon_scale` come CommandPickaxeIcon:
# nei bottoni (CommandButtonIcon) disegna alla dimensione reale invece di ingrandire il nodo.
#
# Sagoma: arco del cranio (cerchio CRANIUM_RADIUS centrato in CRANIUM_CENTER) tagliato dai lati della mandibola
# (±JAW_HALF_WIDTH), che scendono fino a JAW_BOTTOM.

const BONE := Color(0.93, 0.90, 0.82, 1.0)
const HOLE := Color(0.20, 0.16, 0.14, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3
const CRANIUM_CENTER := Vector2(0.0, -0.6)
const CRANIUM_RADIUS: float = 2.4
const JAW_HALF_WIDTH: float = 1.3
const JAW_BOTTOM: float = 2.6
const EYE_OFFSET := Vector2(0.85, -0.5)
const EYE_RADIUS: float = 0.62
const TEETH_TOP: float = 1.9
const ARC_SEGMENTS: int = 20

var icon_scale: float = 1.0


func _draw() -> void:
	var s := icon_scale
	var silhouette := _silhouette_polygon(s)
	draw_colored_polygon(silhouette, BONE)
	var outline := silhouette.duplicate()
	outline.append(silhouette[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX * s, true)
	# Orbite e naso.
	draw_circle(Vector2(-EYE_OFFSET.x, EYE_OFFSET.y) * s, EYE_RADIUS * s, HOLE)
	draw_circle(EYE_OFFSET * s, EYE_RADIUS * s, HOLE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, 0.45) * s, Vector2(-0.35, 1.05) * s, Vector2(0.35, 1.05) * s,
	]), HOLE)
	# Denti: due righe verticali sulla mandibola.
	for x in [-0.45, 0.45]:
		draw_line(Vector2(x, TEETH_TOP) * s, Vector2(x, JAW_BOTTOM) * s, OUTLINE, OUTLINE_WIDTH_PX * s, true)


# Arco del cranio dal lato destro della mandibola, passando sopra, fino al lato sinistro; poi gli angoli della mandibola.
func _silhouette_polygon(s: float) -> PackedVector2Array:
	var side_drop := sqrt(CRANIUM_RADIUS * CRANIUM_RADIUS - JAW_HALF_WIDTH * JAW_HALF_WIDTH)
	var start_angle := atan2(side_drop, JAW_HALF_WIDTH)
	var end_angle := PI - start_angle - TAU
	var points := PackedVector2Array()
	for i in range(ARC_SEGMENTS + 1):
		var angle := lerpf(start_angle, end_angle, float(i) / float(ARC_SEGMENTS))
		points.append((CRANIUM_CENTER + Vector2.RIGHT.rotated(angle) * CRANIUM_RADIUS) * s)
	points.append(Vector2(-JAW_HALF_WIDTH, JAW_BOTTOM) * s)
	points.append(Vector2(JAW_HALF_WIDTH, JAW_BOTTOM) * s)
	return points
