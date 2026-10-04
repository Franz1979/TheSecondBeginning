class_name CoveredDepotShape
extends RefCounted

# Copertura del deposito coperto (covered_depot, 2026-10-04, richiesta utente), condivisa da mappa
# (MicroCellRenderer._draw_buildings), anteprima di piazzamento (BuildingGhost) e icona della barra di costruzione
# (CoveredDepotIcon), come StorageHutShape per la capanna di stoccaggio. Sotto c'è lo spiazzo del sito di deposito
# (DepositSiteShape) con i mucchietti per slot, disegnati dal chiamante; qui solo la tettoia leggera sopra: quattro pali
# agli angoli, un telaio e un graticcio di rami radi e due pelli stese, che lasciano intravedere i mucchi.
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10); `scale` per l'icona. Nessuna porta né rotazione.

const POLE_OFFSET: float = 3.7
const POLE_RADIUS: float = 0.5
const POLE_COLOR := Color(0.30, 0.20, 0.10, 1.0)
const FRAME_COLOR := Color(0.42, 0.29, 0.15, 0.95)
const FRAME_WIDTH: float = 0.35
const BRANCH_COLOR := Color(0.50, 0.36, 0.20, 0.8)
const BRANCH_WIDTH: float = 0.22
# Rami del graticcio: posizioni lungo l'asse x (rami verticali) e lungo l'asse y (rami orizzontali), entro il telaio.
const BRANCH_X: Array[float] = [-1.9, 0.0, 1.9]
const BRANCH_Y: Array[float] = [-1.2, 1.2]
const HIDE_COLOR := Color(0.80, 0.66, 0.46, 0.8)
const HIDE_OUTLINE_COLOR := Color(0.48, 0.36, 0.22, 0.9)
const HIDE_OUTLINE_WIDTH: float = 0.2
# Due pelli stese, irregolari, sopra due zone del graticcio (lasciano scoperto il centro).
const HIDES: Array = [
	[Vector2(-3.3, -3.2), Vector2(-0.6, -3.4), Vector2(-0.4, -1.3), Vector2(-3.1, -1.0)],
	[Vector2(0.7, 1.2), Vector2(3.3, 1.0), Vector2(3.4, 3.3), Vector2(0.5, 3.1)],
]
const INVALID_COLOR := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_DARK_COLOR := Color(0.45, 0.06, 0.06, 1.0)


# `invalid` = anteprima su una posizione non edificabile (tutto rossastro); `alpha` per l'anteprima semitrasparente.
static func draw_cover(canvas: CanvasItem, center: Vector2, invalid: bool = false, alpha: float = 1.0, scale: float = 1.0) -> void:
	var tint := func(color: Color, invalid_color: Color) -> Color:
		var base: Color = invalid_color if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)
	var at := func(local: Vector2) -> Vector2:
		return center + local * scale
	var s := POLE_OFFSET
	var corners: Array[Vector2] = [Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)]
	var branch_color: Color = tint.call(BRANCH_COLOR, INVALID_DARK_COLOR)
	for x in BRANCH_X:
		canvas.draw_line(at.call(Vector2(x, -s)), at.call(Vector2(x, s)), branch_color, BRANCH_WIDTH * scale, true)
	for y in BRANCH_Y:
		canvas.draw_line(at.call(Vector2(-s, y)), at.call(Vector2(s, y)), branch_color, BRANCH_WIDTH * scale, true)
	for hide_points in HIDES:
		var hide := PackedVector2Array()
		for point in hide_points:
			hide.append(at.call(point))
		canvas.draw_colored_polygon(hide, tint.call(HIDE_COLOR, INVALID_COLOR))
		var hide_outline := hide.duplicate()
		hide_outline.append(hide[0])
		canvas.draw_polyline(hide_outline, tint.call(HIDE_OUTLINE_COLOR, INVALID_DARK_COLOR), HIDE_OUTLINE_WIDTH * scale, true)
	var frame := PackedVector2Array()
	for corner in corners:
		frame.append(at.call(corner))
	frame.append(frame[0])
	canvas.draw_polyline(frame, tint.call(FRAME_COLOR, INVALID_DARK_COLOR), FRAME_WIDTH * scale, true)
	for corner in corners:
		canvas.draw_circle(at.call(corner), POLE_RADIUS * scale, tint.call(POLE_COLOR, INVALID_DARK_COLOR))
