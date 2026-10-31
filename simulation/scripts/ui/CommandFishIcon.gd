class_name CommandFishIcon
extends Node2D

# Icona "fish" (2026-10-31, pesca — FishCommandService; ridisegnata lo stesso giorno, richiesta utente: il pesciolino
# verticale appeso alla lenza era piccolo e scuro, non si capiva accanto ad accetta e piccone): pesce di profilo in
# diagonale (coda in basso a sinistra, muso in alto a destra) con l'amo d'osso davanti alla bocca, stesso stile delle altre
# icone di comando disegnate (CommandAxeIcon): forme piene con il contorno scuro. Registrata in
# IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px = 1 microcella).
#
# Coordinate del pesce lungo il suo asse: x verso il muso, y verso il ventre.

const BACK := Color(0.44, 0.62, 0.75, 1.0)
const BELLY := Color(0.90, 0.93, 0.94, 1.0)
const EYE_WHITE := Color(1.0, 1.0, 1.0, 1.0)
const BONE := Color(0.94, 0.91, 0.82, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3

const FISH_CENTER := Vector2(-0.5, 0.8)
const FISH_ANGLE_DEG: float = -35.0
const SNOUT_X: float = 3.0
const TAIL_JOIN_X: float = -1.8
const BODY_HALF_HEIGHT: float = 1.4
const TAIL: Array[Vector2] = [Vector2(-1.6, 0.0), Vector2(-3.4, -1.3), Vector2(-2.8, 0.0), Vector2(-3.4, 1.3)]
const DORSAL_FIN: Array[Vector2] = [Vector2(-0.6, -1.25), Vector2(0.2, -1.9), Vector2(0.8, -1.2)]
const EYE := Vector2(1.9, -0.35)
const EYE_RADIUS: float = 0.42
const PUPIL_RADIUS: float = 0.2

# Amo d'osso: gambo verticale davanti al muso, uncino a J in basso con la punta che risale.
const HOOK_TOP := Vector2(3.2, -4.2)
const HOOK_BEND_CENTER := Vector2(2.65, -1.8)
const HOOK_BEND_RADIUS: float = 0.55
const HOOK_TIP := Vector2(2.1, -2.3)
const HOOK_WIDTH: float = 0.45

var icon_scale: float = 1.0


func _draw() -> void:
	var s := icon_scale
	var axis := Vector2.RIGHT.rotated(deg_to_rad(FISH_ANGLE_DEG))
	var down := Vector2(-axis.y, axis.x)
	var to_px := func(local: Vector2) -> Vector2:
		return (FISH_CENTER + axis * local.x + down * local.y) * s
	var outline_width := OUTLINE_WIDTH_PX * 1.5 * s

	var tail := PackedVector2Array()
	for point in TAIL:
		tail.append(to_px.call(point))
	draw_colored_polygon(tail, BACK)
	_draw_closed_outline(tail, outline_width)

	var fin := PackedVector2Array()
	for point in DORSAL_FIN:
		fin.append(to_px.call(point))
	draw_colored_polygon(fin, BACK)
	_draw_closed_outline(fin, outline_width)

	# Corpo a lente tra l'attacco della coda e il muso: dorso pieno, poi la metà del ventre più chiara sopra.
	var segments := 12
	var body := PackedVector2Array()
	var belly := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var x := lerpf(TAIL_JOIN_X, SNOUT_X, t)
		body.append(to_px.call(Vector2(x, -sin(t * PI) * BODY_HALF_HEIGHT)))
		belly.append(to_px.call(Vector2(x, sin(t * PI) * BODY_HALF_HEIGHT)))
	for i in range(segments - 1, 0, -1):
		body.append(belly[i])
	draw_colored_polygon(body, BACK)
	draw_colored_polygon(belly, BELLY)
	_draw_closed_outline(body, outline_width)

	var eye: Vector2 = to_px.call(EYE)
	draw_circle(eye, EYE_RADIUS * s, EYE_WHITE)
	draw_arc(eye, EYE_RADIUS * s, 0.0, TAU, 16, OUTLINE, OUTLINE_WIDTH_PX * s, true)
	draw_circle(to_px.call(EYE + Vector2(0.08, 0.0)), PUPIL_RADIUS * s, OUTLINE)

	# Amo: contorno scuro sotto, osso sopra.
	var hook := PackedVector2Array([HOOK_TOP * s])
	var arc_steps := 8
	for i in range(arc_steps + 1):
		var angle := PI * float(i) / float(arc_steps)
		hook.append((HOOK_BEND_CENTER + Vector2(cos(angle), sin(angle)) * HOOK_BEND_RADIUS) * s)
	hook.append(HOOK_TIP * s)
	draw_polyline(hook, OUTLINE, (HOOK_WIDTH + OUTLINE_WIDTH_PX * 2.0) * s, true)
	draw_polyline(hook, BONE, HOOK_WIDTH * s, true)


func _draw_closed_outline(points: PackedVector2Array, width: float) -> void:
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE, width, true)
