class_name CommandMoonIcon
extends Node2D

# Icona del comando "rite" (2026-10-02, richiesta utente — task Rite): falce di luna, simbolo della religione nel
# gioco (stesso soggetto della voce 🌙 del layer di influenza religiosa), stesso stile di CommandHammerIcon/
# CommandPickaxeIcon — disegnata a codice, nitida a ogni zoom. Registrata in IconRegistry.COMMAND_ICON_NODES; origine =
# centro dell'icona, pixel locali della cella (10 px = 1 microcella).
#
# Sagoma: cerchio esterno (OUTER_RADIUS, centrato sull'origine) meno un cerchio interno spostato verso
# CUT_DIRECTION_DEG; il poligono segue l'arco esterno lontano dal taglio e torna lungo l'arco interno.

const MOON := Color(0.95, 0.88, 0.55, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3
const OUTER_RADIUS: float = 2.8
const INNER_RADIUS: float = 2.4
const CUT_OFFSET: float = 1.5
const CUT_DIRECTION_DEG: float = -35.0
const ARC_SEGMENTS: int = 16


func _draw() -> void:
	var crescent := crescent_polygon()
	draw_colored_polygon(crescent, MOON)
	var outline := crescent.duplicate()
	outline.append(crescent[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX, true)


# Punti della falce: le due circonferenze si intersecano agli angoli phi ± alpha (cerchio esterno) e phi ± beta
# (cerchio interno, misurati dal suo centro).
static func crescent_polygon() -> PackedVector2Array:
	var phi := deg_to_rad(CUT_DIRECTION_DEG)
	var d := CUT_OFFSET
	var a := (OUTER_RADIUS * OUTER_RADIUS - INNER_RADIUS * INNER_RADIUS + d * d) / (2.0 * d)
	var alpha := acos(clampf(a / OUTER_RADIUS, -1.0, 1.0))
	var beta := acos(clampf((a - d) / INNER_RADIUS, -1.0, 1.0))
	var inner_center := Vector2.RIGHT.rotated(phi) * d
	var points := PackedVector2Array()
	for i in range(ARC_SEGMENTS + 1):
		var angle := lerpf(phi + alpha, phi + TAU - alpha, float(i) / float(ARC_SEGMENTS))
		points.append(Vector2.RIGHT.rotated(angle) * OUTER_RADIUS)
	for i in range(1, ARC_SEGMENTS):
		var angle := lerpf(phi + TAU - beta, phi + beta, float(i) / float(ARC_SEGMENTS))
		points.append(inner_center + Vector2.RIGHT.rotated(angle) * INNER_RADIUS)
	return points
